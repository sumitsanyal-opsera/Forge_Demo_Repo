/**
 * Salesforce REST API client for pipeline status queries and sObject reads.
 *
 * Responsibilities:
 *   - Injects Bearer token from SalesforceAuthService on every request
 *   - API version configurable via SF_API_VERSION env var (default v59.0)
 *   - Exponential backoff + jitter for rate-limited (429 / REQUEST_LIMIT_EXCEEDED)
 *     and transient 5xx responses; max 3 retries; respects Retry-After header
 *   - Single token refresh + retry on INVALID_SESSION_ID (HTTP 401)
 *   - Follows nextRecordsUrl pagination via queryMore()
 *   - Logs method, URL path (no query params), status code, response time at INFO
 *     Body logging is DEBUG-only — never INFO+ (PII / credential leakage risk)
 *
 * Security: request and response bodies are NEVER logged at INFO level.
 */

import { createLogger } from '../../../logging/logger.js';
import {
  generateCorrelationId,
  getCorrelationId,
} from '../../../logging/correlation.js';
import { sleep } from '../../../common/http/retry.js';
import type { SalesforceAuthService } from '../auth/SalesforceAuthService.js';
import {
  SalesforceApiError,
  parseSalesforceApiError,
  SESSION_EXPIRED_ERROR_CODES,
  RATE_LIMIT_ERROR_CODES,
} from './SalesforceApiError.js';
import type {
  QueryResult,
  SObjectRecord,
  SalesforceApiClientConfig,
} from './types.js';

const logger = createLogger('SalesforceApiClient');

const DEFAULT_API_VERSION = 'v59.0';
const MAX_RETRIES = 3;
const BASE_DELAY_MS = 1_000;
const MAX_DELAY_MS = 30_000;

const TRANSIENT_STATUS_CODES = new Set([500, 502, 503]);

// ─── Client ──────────────────────────────────────────────────────────────────

export class SalesforceApiClient {
  private readonly authService: SalesforceAuthService;
  private readonly apiVersion: string;
  private readonly httpClient: (url: string, init: RequestInit) => Promise<Response>;

  constructor(authService: SalesforceAuthService, config?: SalesforceApiClientConfig) {
    this.authService = authService;
    this.apiVersion =
      config?.apiVersion ??
      process.env['SF_API_VERSION'] ??
      DEFAULT_API_VERSION;
    this.httpClient = config?.httpClient ?? ((url, init) => fetch(url, init));
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /**
   * Executes a SOQL query and returns the first page of results.
   * For large result sets, iterate subsequent pages with queryMore().
   *
   * @param soql  SOQL query string — special characters are URL-encoded automatically.
   */
  async query<T extends SObjectRecord = SObjectRecord>(
    soql: string,
  ): Promise<QueryResult<T>> {
    const path = `/services/data/${this.apiVersion}/query`;
    return this.request<QueryResult<T>>('GET', path, { soql });
  }

  /**
   * Fetches the next page of results from a previous query() call.
   *
   * @param nextRecordsUrl  The nextRecordsUrl value from a QueryResult.
   */
  async queryMore<T extends SObjectRecord = SObjectRecord>(
    nextRecordsUrl: string,
  ): Promise<QueryResult<T>> {
    // nextRecordsUrl is an absolute path on the same instanceUrl, e.g.
    // /services/data/v59.0/query/01gXXX-2000
    return this.request<QueryResult<T>>('GET', nextRecordsUrl);
  }

  /**
   * Retrieves a single sObject record by type and ID.
   *
   * @param sObjectType  Salesforce sObject API name (e.g. 'Account', 'AsyncApexJob')
   * @param id           18-character Salesforce record ID
   * @param fields       Optional list of fields to retrieve (default: all fields)
   */
  async getRecord<T extends SObjectRecord = SObjectRecord>(
    sObjectType: string,
    id: string,
    fields?: string[],
  ): Promise<T> {
    const path = `/services/data/${this.apiVersion}/sobjects/${encodeURIComponent(sObjectType)}/${encodeURIComponent(id)}`;
    return this.request<T>('GET', path, fields !== undefined && fields.length > 0 ? { fields } : undefined);
  }

  // ─── Internal request machinery ──────────────────────────────────────────

  private async request<T>(
    method: string,
    path: string,
    queryOptions?: { soql?: string; fields?: string[] },
  ): Promise<T> {
    const correlationId = getCorrelationId() ?? generateCorrelationId();
    const ctx = { method, urlPath: path, correlationId };

    // First attempt may trigger a single session refresh; subsequent attempts
    // after a refresh never refresh again to prevent infinite loops.
    return this.requestWithRefresh<T>(method, path, queryOptions, correlationId, ctx, false);
  }

  private async requestWithRefresh<T>(
    method: string,
    path: string,
    queryOptions: { soql?: string; fields?: string[] } | undefined,
    correlationId: string,
    ctx: { method: string; urlPath: string; correlationId: string },
    hasRefreshed: boolean,
  ): Promise<T> {
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      // ── Obtain a valid token ────────────────────────────────────────────
      let accessToken: string;
      let instanceUrl: string;
      try {
        const token = await this.authService.getAccessToken();
        accessToken = token.accessToken;
        instanceUrl = token.instanceUrl;
      } catch (authErr) {
        throw new SalesforceApiError(
          `Failed to obtain Salesforce access token: ${String(authErr)}`,
          'AUTH_TOKEN_ERROR',
          0,
          false,
          [],
          ctx,
        );
      }

      const url = this.buildUrl(instanceUrl, path, queryOptions);

      logger.debug('Salesforce API request', {
        method,
        urlPath: path,
        correlationId,
        attempt,
      });

      const startMs = Date.now();

      // ── Send request ────────────────────────────────────────────────────
      let response: Response;
      try {
        response = await this.httpClient(url, {
          method,
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'X-Correlation-ID': correlationId,
            Accept: 'application/json',
          },
        });
      } catch (networkErr) {
        const isLast = attempt >= MAX_RETRIES;
        if (!isLast) {
          const delayMs = computeBackoff(attempt);
          logger.warn('Salesforce API network error, retrying', {
            method,
            urlPath: path,
            attempt: attempt + 1,
            delayMs,
            correlationId,
            error: String(networkErr),
          });
          await sleep(delayMs);
          continue;
        }
        throw new SalesforceApiError(
          `Network error calling Salesforce API: ${String(networkErr)}`,
          'NETWORK_ERROR',
          0,
          true,
          [],
          ctx,
        );
      }

      const responseTimeMs = Date.now() - startMs;

      // Log at INFO: method, path (no query params), status, response time.
      // Body is intentionally omitted here — logged at DEBUG only below.
      logger.info('Salesforce API response', {
        method,
        urlPath: path,
        statusCode: response.status,
        responseTimeMs,
        correlationId,
      });

      // ── Parse body ──────────────────────────────────────────────────────
      const rawBody: unknown = await this.safeJsonParse(response);

      logger.debug('Salesforce API response body', {
        // WARNING: response body may contain PII — DEBUG only, never INFO+
        method,
        urlPath: path,
        statusCode: response.status,
        correlationId,
        body: rawBody,
      });

      // ── Session expired → single token refresh ──────────────────────────
      if (response.status === 401) {
        const isSessionExpired = isSessionExpiredError(rawBody);
        if (isSessionExpired && !hasRefreshed) {
          logger.warn('Salesforce session expired — refreshing token and retrying', {
            urlPath: path,
            correlationId,
          });
          try {
            await this.authService.forceRefresh();
          } catch {
            // If refresh itself fails, fall through and throw the original 401 error
          }
          return this.requestWithRefresh<T>(
            method,
            path,
            queryOptions,
            correlationId,
            ctx,
            true,
          );
        }
        throw parseSalesforceApiError(rawBody, response.status, ctx);
      }

      // ── Rate limit (429 or REQUEST_LIMIT_EXCEEDED in body) ───────────────
      if (response.status === 429 || isRateLimitError(rawBody)) {
        if (attempt < MAX_RETRIES) {
          const retryAfterHeader = response.headers.get('Retry-After');
          const baseDelay = retryAfterHeader !== null
            ? parseInt(retryAfterHeader, 10) * 1_000
            : computeBackoff(attempt);
          const delayMs = addJitter(baseDelay);
          logger.warn('Salesforce API rate limited, retrying', {
            method,
            urlPath: path,
            delayMs,
            attempt: attempt + 1,
            correlationId,
          });
          await sleep(delayMs);
          continue;
        }
        throw parseSalesforceApiError(rawBody, response.status, ctx);
      }

      // ── Transient server errors ─────────────────────────────────────────
      if (TRANSIENT_STATUS_CODES.has(response.status)) {
        if (attempt < MAX_RETRIES) {
          const delayMs = computeBackoff(attempt);
          logger.warn('Salesforce API transient error, retrying', {
            method,
            urlPath: path,
            statusCode: response.status,
            delayMs,
            attempt: attempt + 1,
            correlationId,
          });
          await sleep(delayMs);
          continue;
        }
        throw parseSalesforceApiError(rawBody, response.status, ctx);
      }

      // ── Client errors (400, 403, etc.) — not retried ────────────────────
      if (!response.ok) {
        throw parseSalesforceApiError(rawBody, response.status, ctx);
      }

      // ── Success ─────────────────────────────────────────────────────────
      if (rawBody === null) {
        throw new SalesforceApiError(
          'Salesforce API returned non-JSON or empty response for a successful status code.',
          'UNEXPECTED_RESPONSE',
          response.status,
          false,
          [],
          ctx,
        );
      }
      return rawBody as T;
    }

    // Should be unreachable — the loop always returns or throws.
    throw new SalesforceApiError(
      'Salesforce API: max retries exceeded',
      'MAX_RETRIES_EXCEEDED',
      0,
      false,
      [],
      ctx,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  private buildUrl(
    instanceUrl: string,
    path: string,
    queryOptions?: { soql?: string; fields?: string[] },
  ): string {
    const url = new URL(path, instanceUrl);
    if (queryOptions?.soql !== undefined) {
      url.searchParams.set('q', queryOptions.soql);
    }
    if (queryOptions?.fields !== undefined && queryOptions.fields.length > 0) {
      url.searchParams.set('fields', queryOptions.fields.join(','));
    }
    return url.toString();
  }

  private async safeJsonParse(response: Response): Promise<unknown> {
    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('application/json')) {
      // Salesforce maintenance windows return HTML — wrap as a structured error
      return null;
    }
    try {
      return await response.json() as unknown;
    } catch {
      return null;
    }
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

function computeBackoff(attempt: number): number {
  const exponential = Math.min(BASE_DELAY_MS * Math.pow(2, attempt), MAX_DELAY_MS);
  const jitter = Math.random() * BASE_DELAY_MS;
  return Math.floor(exponential + jitter);
}

function addJitter(baseMs: number): number {
  return Math.floor(baseMs + Math.random() * BASE_DELAY_MS);
}

function isSessionExpiredError(rawBody: unknown): boolean {
  if (!Array.isArray(rawBody)) return false;
  return rawBody.some(
    (e) =>
      typeof e === 'object' &&
      e !== null &&
      SESSION_EXPIRED_ERROR_CODES.has((e as Record<string, unknown>)['errorCode'] as string),
  );
}

function isRateLimitError(rawBody: unknown): boolean {
  if (!Array.isArray(rawBody)) return false;
  return rawBody.some(
    (e) =>
      typeof e === 'object' &&
      e !== null &&
      RATE_LIMIT_ERROR_CODES.has((e as Record<string, unknown>)['errorCode'] as string),
  );
}
