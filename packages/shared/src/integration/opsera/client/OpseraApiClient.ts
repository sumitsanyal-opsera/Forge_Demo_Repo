/**
 * Opsera API client.
 *
 * Provides typed methods for all Opsera pipeline management operations.
 * Authentication is delegated to OpseraAuthService, which injects the
 * appropriate headers transparently.
 *
 * Retry policy:
 *  - 429 Too Many Requests: honours Retry-After header, up to MAX_RETRIES
 *  - 500 / 502 / 503: exponential backoff with jitter, up to MAX_RETRIES
 *  - All other errors: not retried
 *
 * Security: pipeline config bodies are logged at DEBUG only — never at INFO+.
 */

import { createLogger } from '../../../logging/logger.js';
import {
  generateCorrelationId,
  getCorrelationId,
} from '../../../logging/correlation.js';
import { sleep } from '../../../common/http/retry.js';
import type { OpseraAuthService } from '../auth/OpseraAuthService.js';
import { OpseraApiError, OpseraAuthError } from './OpseraApiError.js';
import type {
  OpseraErrorBody,
  PaginatedResponse,
  Pipeline,
  PipelineConfig,
  PipelineListFilters,
  PipelineRun,
  ToolRegistryEntry,
  TriggerPipelineParams,
} from './types.js';

const logger = createLogger('OpseraApiClient');

const MAX_RETRIES = 3;
const BASE_DELAY_MS = 1_000;
const MAX_DELAY_MS = 30_000;

const RETRYABLE_STATUS_CODES = new Set([500, 502, 503]);

export interface OpseraApiClientConfig {
  baseUrl?: string;
  timeoutMs?: number;
}

export class OpseraApiClient {
  private readonly authService: OpseraAuthService;
  private readonly baseUrl: string;

  constructor(authService: OpseraAuthService, config?: OpseraApiClientConfig) {
    this.authService = authService;
    this.baseUrl =
      config?.baseUrl ??
      process.env['OPSERA_API_BASE_URL'] ??
      'https://api.opsera.io';
  }

  // ── Pipeline CRUD ────────────────────────────────────────────────────────────

  async getPipeline(id: string): Promise<Pipeline> {
    return this.request<Pipeline>('GET', `/api/v1/pipelines/${encodeURIComponent(id)}`);
  }

  async createPipeline(config: PipelineConfig): Promise<Pipeline> {
    logger.debug('Creating pipeline', { stepCount: config.steps.length });
    return this.request<Pipeline>('POST', '/api/v1/pipelines', { body: config });
  }

  async updatePipeline(id: string, config: PipelineConfig): Promise<Pipeline> {
    logger.debug('Updating pipeline', { id, stepCount: config.steps.length });
    return this.request<Pipeline>('PUT', `/api/v1/pipelines/${encodeURIComponent(id)}`, {
      body: config,
    });
  }

  async deletePipeline(id: string): Promise<void> {
    await this.request<void>('DELETE', `/api/v1/pipelines/${encodeURIComponent(id)}`);
  }

  // ── Pipeline execution ───────────────────────────────────────────────────────

  async triggerPipeline(id: string, params?: TriggerPipelineParams): Promise<PipelineRun> {
    return this.request<PipelineRun>(
      'POST',
      `/api/v1/pipelines/${encodeURIComponent(id)}/trigger`,
      { body: params ?? {} },
    );
  }

  async getPipelineStatus(id: string, runId: string): Promise<PipelineRun> {
    return this.request<PipelineRun>(
      'GET',
      `/api/v1/pipelines/${encodeURIComponent(id)}/runs/${encodeURIComponent(runId)}`,
    );
  }

  // ── Listing with pagination ──────────────────────────────────────────────────

  /**
   * Async generator that yields individual Pipeline objects across all pages.
   * Handles both cursor-based and offset-based pagination transparently.
   *
   * Usage:
   *   for await (const pipeline of client.listPipelines({ status: 'running' })) {
   *     console.log(pipeline.id);
   *   }
   */
  async *listPipelines(filters?: PipelineListFilters): AsyncGenerator<Pipeline, void, unknown> {
    let cursor: string | undefined = filters?.cursor;
    let page = filters?.page ?? 1;
    const limit = filters?.limit ?? 20;

    while (true) {
      const queryParams: Record<string, string> = {
        limit: String(limit),
      };

      if (filters?.status !== undefined) queryParams['status'] = filters.status;
      if (filters?.tag !== undefined) queryParams['tag'] = filters.tag;
      if (filters?.owner !== undefined) queryParams['owner'] = filters.owner;
      if (filters?.fromDate !== undefined) queryParams['fromDate'] = filters.fromDate;
      if (filters?.toDate !== undefined) queryParams['toDate'] = filters.toDate;

      if (cursor !== undefined) {
        queryParams['cursor'] = cursor;
      } else {
        queryParams['page'] = String(page);
      }

      const pageResponse = await this.request<PaginatedResponse<Pipeline>>(
        'GET',
        '/api/v1/pipelines',
        { params: queryParams },
      );

      for (const pipeline of pageResponse.data) {
        yield pipeline;
      }

      if (!pageResponse.hasMore || pageResponse.data.length === 0) break;

      if (pageResponse.nextCursor !== undefined) {
        cursor = pageResponse.nextCursor;
      } else {
        page++;
        cursor = undefined;
      }
    }
  }

  // ── Tool registry ────────────────────────────────────────────────────────────

  async getToolRegistry(): Promise<ToolRegistryEntry[]> {
    return this.request<ToolRegistryEntry[]>('GET', '/api/v1/tools');
  }

  // ── Internal request machinery ───────────────────────────────────────────────

  private async request<T>(
    method: string,
    path: string,
    options?: { body?: unknown; params?: Record<string, string> },
  ): Promise<T> {
    const correlationId = getCorrelationId() ?? generateCorrelationId();
    const url = this.buildUrl(path, options?.params);
    const startMs = Date.now();

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      let headers: Record<string, string>;
      try {
        const authHeaders = await this.authService.getHeaders();
        headers = {
          ...authHeaders,
          'Content-Type': 'application/json',
          'X-Correlation-ID': correlationId,
        };
      } catch (authErr) {
        throw new OpseraAuthError(
          `Failed to obtain auth headers: ${String(authErr)}`,
          'AUTH_HEADER_ERROR',
        );
      }

      logger.debug('Opsera API request', { method, path, correlationId, attempt });

      let response: Response;
      try {
        response = await fetch(url.toString(), {
          method,
          headers,
          ...(options?.body !== undefined
            ? { body: JSON.stringify(options.body) }
            : {}),
        });
      } catch (networkErr) {
        const isLast = attempt >= MAX_RETRIES;
        if (!isLast) {
          const delayMs = computeBackoff(attempt);
          logger.warn('Opsera API network error, retrying', {
            method,
            path,
            attempt: attempt + 1,
            delayMs,
            error: String(networkErr),
          });
          await sleep(delayMs);
          continue;
        }
        throw new OpseraApiError(
          `Network error calling Opsera API: ${String(networkErr)}`,
          'NETWORK_ERROR',
          0,
          false,
          { method, path, correlationId },
        );
      }

      const responseTimeMs = Date.now() - startMs;
      logger.debug('Opsera API response', {
        method,
        path,
        statusCode: response.status,
        responseTimeMs,
        correlationId,
      });

      // ── Rate limiting ────────────────────────────────────────────────────────
      if (response.status === 429) {
        const retryAfterHeader = response.headers.get('Retry-After');
        const retryAfterMs = retryAfterHeader !== null
          ? parseInt(retryAfterHeader, 10) * 1_000
          : computeBackoff(attempt);

        if (attempt < MAX_RETRIES) {
          logger.warn('Opsera API rate limited, retrying', {
            method,
            path,
            retryAfterMs,
            attempt: attempt + 1,
          });
          await sleep(retryAfterMs);
          continue;
        }
        throw new OpseraApiError(
          `Rate limit exceeded for ${method} ${path}`,
          'RATE_LIMIT_EXCEEDED',
          429,
          true,
          { method, path, correlationId },
        );
      }

      // ── Transient server errors ──────────────────────────────────────────────
      if (RETRYABLE_STATUS_CODES.has(response.status)) {
        if (attempt < MAX_RETRIES) {
          const delayMs = computeBackoff(attempt);
          logger.warn('Opsera API transient error, retrying', {
            method,
            path,
            statusCode: response.status,
            delayMs,
            attempt: attempt + 1,
          });
          await sleep(delayMs);
          continue;
        }
        throw new OpseraApiError(
          `Opsera API server error [${response.status}] on ${method} ${path}`,
          'SERVER_ERROR',
          response.status,
          true,
          { method, path, correlationId },
        );
      }

      // ── Auth errors ──────────────────────────────────────────────────────────
      if (response.status === 401 || response.status === 403) {
        const body = await this.safeJsonParse(response);
        const msg = (body?.message as string | undefined) ?? 'Invalid or expired credentials';
        throw new OpseraAuthError(
          msg,
          response.status === 401 ? 'AUTH_INVALID_KEY' : 'AUTH_FORBIDDEN',
          response.status,
        );
      }

      // ── Client errors ────────────────────────────────────────────────────────
      if (!response.ok) {
        await this.parseAndThrow(response, method, path, correlationId);
      }

      // ── Success ──────────────────────────────────────────────────────────────
      if (response.status === 204 || method === 'DELETE') {
        return undefined as unknown as T;
      }

      const body: unknown = await response.json().catch(() => {
        throw new OpseraApiError(
          `Failed to parse JSON response from Opsera API: ${method} ${path}`,
          'UNEXPECTED_RESPONSE',
          response.status,
          false,
          { method, path, correlationId },
        );
      });

      return body as T;
    }

    // Should be unreachable — the loop always throws or returns before this.
    throw new OpseraApiError(
      'Max retries exceeded',
      'MAX_RETRIES_EXCEEDED',
      0,
      false,
      { method, path, correlationId: undefined },
    );
  }

  private async parseAndThrow(
    response: Response,
    method: string,
    path: string,
    correlationId: string,
  ): Promise<never> {
    const body = await this.safeJsonParse(response);
    const code = typeof body?.code === 'string' ? body.code : undefined;
    const message = typeof body?.message === 'string' ? body.message : undefined;
    const ctx = { method, path, correlationId };

    if (response.status === 404) {
      throw new OpseraApiError(
        message ?? `Resource not found: ${path}`,
        'PIPELINE_NOT_FOUND',
        404,
        false,
        ctx,
      );
    }

    if (response.status === 409) {
      throw new OpseraApiError(
        message ?? 'The pipeline is already running',
        'PIPELINE_ALREADY_RUNNING',
        409,
        false,
        ctx,
      );
    }

    if (response.status === 400) {
      throw new OpseraApiError(
        message ?? `Invalid request to ${method} ${path}`,
        code ?? 'INVALID_REQUEST',
        400,
        false,
        ctx,
      );
    }

    throw new OpseraApiError(
      message ?? `Unexpected Opsera API error [${response.status}]: ${method} ${path}`,
      code ?? 'UNEXPECTED_RESPONSE',
      response.status,
      false,
      ctx,
    );
  }

  private async safeJsonParse(response: Response): Promise<OpseraErrorBody | null> {
    try {
      return await response.json() as OpseraErrorBody;
    } catch {
      return null;
    }
  }

  private buildUrl(path: string, params?: Record<string, string>): string {
    const url = new URL(path, this.baseUrl);
    if (params !== undefined) {
      for (const [key, value] of Object.entries(params)) {
        url.searchParams.set(key, value);
      }
    }
    return url.toString();
  }
}

function computeBackoff(attempt: number): number {
  const exponential = Math.min(BASE_DELAY_MS * Math.pow(2, attempt), MAX_DELAY_MS);
  const jitter = Math.random() * BASE_DELAY_MS;
  return Math.floor(exponential + jitter);
}
