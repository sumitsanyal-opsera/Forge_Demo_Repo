/**
 * Salesforce OAuth 2.0 JWT Bearer Flow authentication service.
 *
 * Orchestrates JWT construction → token exchange → caching → proactive refresh.
 * Callers receive a valid {accessToken, instanceUrl} without needing to
 * understand the underlying OAuth flow.
 *
 * Key design decisions:
 *   - Injectable HTTP client and private key for unit testing without I/O
 *   - Promise deduplication via SalesforceTokenCache.withExclusiveRefresh()
 *   - Retry with exponential backoff (1s, 2s, 4s) for network errors only
 *   - Structured SalesforceAuthError for all Salesforce OAuth error codes
 *   - Private key NEVER logged — only its presence is recorded
 *
 * Security: See SF_JWT_PRIVATE_KEY and SF_JWT_PRIVATE_KEY_PATH env vars.
 */

import { readFileSync } from 'node:fs';
import { createLogger } from '../../../logging/logger.js';
import { withRetry } from '../../../common/http/retry.js';
import { getCorrelationId } from '../../../logging/correlation.js';
import { JwtBuilder } from './JwtBuilder.js';
import { SalesforceTokenCache, type SalesforceToken } from './SalesforceTokenCache.js';
import {
  SalesforceAuthError,
  SF_AUTH_ERROR_CODES,
  mapSalesforceOAuthError,
} from './SalesforceAuthError.js';

const logger = createLogger('salesforce-auth');

// ─── Types ────────────────────────────────────────────────────────────────────

/** Minimal fetch-compatible HTTP client interface for DI in tests. */
export type SalesforceHttpClient = (
  url: string,
  init: RequestInit,
) => Promise<Response>;

export interface SalesforceAuthConfig {
  /** Salesforce Connected App consumer key. Defaults to SF_CLIENT_ID env var. */
  clientId?: string;
  /** Salesforce username for the integration user. Defaults to SF_USERNAME env var. */
  username?: string;
  /**
   * Login URL: 'https://login.salesforce.com' (production) or
   * 'https://test.salesforce.com' (sandbox). Defaults to SF_LOGIN_URL env var
   * then 'https://login.salesforce.com'.
   */
  loginUrl?: string;
  /**
   * PEM-encoded RSA private key string. If omitted, loaded from
   * SF_JWT_PRIVATE_KEY env var (with \\n→\n replacement) or
   * the file at SF_JWT_PRIVATE_KEY_PATH.
   */
  privateKey?: string;
  /** Injectable HTTP client — uses global fetch by default. */
  httpClient?: SalesforceHttpClient;
  /** Token cache — creates a fresh instance by default. */
  tokenCache?: SalesforceTokenCache;
  /** JWT builder — creates a default instance. */
  jwtBuilder?: JwtBuilder;
}

interface SalesforceOAuthSuccessResponse {
  access_token: string;
  instance_url: string;
  id?: string;
  token_type?: string;
  issued_at?: string;
}

interface SalesforceOAuthErrorResponse {
  error: string;
  error_description?: string;
}

const OAUTH_TOKEN_PATH = '/services/oauth2/token';
const GRANT_TYPE = 'urn:ietf:params:oauth:grant-type:jwt-bearer';

// Tokens have no explicit expires_in in SF JWT bearer responses; SF docs say
// tokens last until revoked or until the org session timeout (default 2 hours).
// We cache for 115 minutes so the 5-minute buffer triggers a refresh at 110m.
const DEFAULT_TOKEN_TTL_SECONDS = 115 * 60;

const RETRY_OPTIONS = {
  maxRetries: 3,
  baseDelayMs: 1_000,
  maxDelayMs: 4_000,
  jitterMs: 200,
};

// ─── Private key loading ──────────────────────────────────────────────────────

function loadPrivateKey(explicitKey?: string): string {
  if (explicitKey) return explicitKey;

  const keyFromEnv = process.env['SF_JWT_PRIVATE_KEY'];
  if (keyFromEnv) {
    // Env vars encoded with literal \n separators (common in Docker/K8s secrets)
    return keyFromEnv.replace(/\\n/g, '\n');
  }

  const keyPath = process.env['SF_JWT_PRIVATE_KEY_PATH'];
  if (keyPath) {
    try {
      return readFileSync(keyPath, 'utf-8');
    } catch (err) {
      throw new SalesforceAuthError(
        `Failed to load private key from ${keyPath}: ${String(err)}`,
        SF_AUTH_ERROR_CODES.AUTH_PRIVATE_KEY_LOAD_ERROR,
        'Ensure SF_JWT_PRIVATE_KEY_PATH points to a readable PEM file.',
      );
    }
  }

  throw new SalesforceAuthError(
    'No Salesforce private key configured. Set SF_JWT_PRIVATE_KEY (PEM string) ' +
      'or SF_JWT_PRIVATE_KEY_PATH (file path).',
    SF_AUTH_ERROR_CODES.AUTH_PRIVATE_KEY_LOAD_ERROR,
    'Set the SF_JWT_PRIVATE_KEY environment variable to the PEM-encoded private key, ' +
      'or set SF_JWT_PRIVATE_KEY_PATH to the path of the PEM file.',
  );
}

// ─── Service ──────────────────────────────────────────────────────────────────

export class SalesforceAuthService {
  private readonly clientId: string;
  private readonly username: string;
  private readonly loginUrl: string;
  private readonly privateKey: string;
  private readonly httpClient: SalesforceHttpClient;
  private readonly tokenCache: SalesforceTokenCache;
  private readonly jwtBuilder: JwtBuilder;

  constructor(config: SalesforceAuthConfig = {}) {
    this.clientId = config.clientId ?? process.env['SF_CLIENT_ID'] ?? '';
    this.username = config.username ?? process.env['SF_USERNAME'] ?? '';
    this.loginUrl =
      config.loginUrl ??
      process.env['SF_LOGIN_URL'] ??
      'https://login.salesforce.com';
    this.privateKey = loadPrivateKey(config.privateKey);

    if (!this.clientId) {
      throw new SalesforceAuthError(
        'SF_CLIENT_ID is required.',
        SF_AUTH_ERROR_CODES.AUTH_INVALID_CLIENT,
        'Set the SF_CLIENT_ID environment variable to the Connected App consumer key.',
      );
    }
    if (!this.username) {
      throw new SalesforceAuthError(
        'SF_USERNAME is required.',
        SF_AUTH_ERROR_CODES.AUTH_INVALID_GRANT,
        'Set the SF_USERNAME environment variable to the Salesforce integration user.',
      );
    }

    this.httpClient = config.httpClient ?? fetch;
    this.tokenCache = config.tokenCache ?? new SalesforceTokenCache();
    this.jwtBuilder = config.jwtBuilder ?? new JwtBuilder();

    logger.debug('SalesforceAuthService initialised', {
      clientId: this.clientId,
      username: this.username,
      loginUrl: this.loginUrl,
      privateKeyPresent: true,
    });
  }

  /**
   * Returns a valid access token and instance URL.
   *
   * On the first call (or after expiry), performs a full JWT assertion →
   * token exchange. Subsequent calls within the TTL window return the cached
   * token without a network request. Concurrent callers share a single
   * in-flight exchange.
   */
  async getAccessToken(): Promise<SalesforceToken> {
    const cached = this.tokenCache.get(this.clientId, this.username);
    if (cached !== null) return cached;

    return this.tokenCache.withExclusiveRefresh(
      this.clientId,
      this.username,
      () => this.exchangeToken(),
    );
  }

  /**
   * Forces a token refresh regardless of cache state.
   * Call this when a downstream request fails with HTTP 401 to recover
   * from mid-session token revocation.
   */
  async forceRefresh(): Promise<SalesforceToken> {
    this.tokenCache.invalidate(this.clientId, this.username);
    return this.getAccessToken();
  }

  // ─── Private ───────────────────────────────────────────────────────────────

  private async exchangeToken(): Promise<SalesforceToken> {
    const correlationId = getCorrelationId() ?? 'none';

    return withRetry(
      async () => this.performExchange(correlationId),
      RETRY_OPTIONS,
      (attempt, delayMs, err) => {
        logger.warn('Salesforce token exchange retry', {
          attempt,
          delayMs,
          correlationId,
          error: err instanceof Error ? err.message : String(err),
        });
      },
    );
  }

  private async performExchange(correlationId: string): Promise<SalesforceToken> {
    const assertion = this.jwtBuilder.build(
      {
        iss: this.clientId,
        sub: this.username,
        aud: this.loginUrl,
      },
      this.privateKey,
    );

    const tokenUrl = `${this.loginUrl}${OAUTH_TOKEN_PATH}`;
    const body = new URLSearchParams({
      grant_type: GRANT_TYPE,
      assertion,
    });

    let response: Response;
    try {
      response = await this.httpClient(tokenUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      });
    } catch (networkErr) {
      throw new SalesforceAuthError(
        `Network error during Salesforce token exchange: ${String(networkErr)}`,
        SF_AUTH_ERROR_CODES.AUTH_NETWORK_ERROR,
        'Check network connectivity to Salesforce OAuth endpoint.',
      );
    }

    const rawBody: unknown = await response.json().catch(() => null);

    if (!response.ok) {
      const errBody = rawBody as Partial<SalesforceOAuthErrorResponse> | null;
      const sfErrorCode = errBody?.error ?? 'unknown_error';
      const sfDescription = errBody?.error_description ?? response.statusText;

      logger.error('Salesforce token exchange failed', undefined, {
        status: response.status,
        sfErrorCode,
        correlationId,
      });

      // Network-layer errors (5xx) are retryable; OAuth errors (4xx) are not.
      if (response.status >= 500) {
        throw new SalesforceAuthError(
          `Salesforce token endpoint returned ${response.status}: ${sfDescription}`,
          SF_AUTH_ERROR_CODES.AUTH_TOKEN_EXCHANGE_FAILED,
          'This is a transient Salesforce error — the request will be retried.',
        );
      }

      throw mapSalesforceOAuthError(sfErrorCode, sfDescription);
    }

    const data = rawBody as Partial<SalesforceOAuthSuccessResponse>;
    if (typeof data?.access_token !== 'string' || data.access_token === '') {
      throw new SalesforceAuthError(
        'Salesforce token response missing access_token.',
        SF_AUTH_ERROR_CODES.AUTH_TOKEN_EXCHANGE_FAILED,
        'This may indicate an API contract change. Check the Salesforce OAuth endpoint version.',
      );
    }
    if (typeof data.instance_url !== 'string' || data.instance_url === '') {
      throw new SalesforceAuthError(
        'Salesforce token response missing instance_url.',
        SF_AUTH_ERROR_CODES.AUTH_TOKEN_EXCHANGE_FAILED,
        'Unexpected response shape from Salesforce OAuth endpoint.',
      );
    }

    const token: SalesforceToken = {
      accessToken: data.access_token,
      instanceUrl: data.instance_url,
    };

    this.tokenCache.set(this.clientId, this.username, token, DEFAULT_TOKEN_TTL_SECONDS);

    logger.info('Salesforce access token obtained', {
      instanceUrl: data.instance_url,
      correlationId,
    });

    return token;
  }
}
