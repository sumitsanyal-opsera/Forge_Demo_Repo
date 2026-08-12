import { createLogger } from '../../logging/logger.js';
import type { OpseraAuthService } from '../opsera/auth/OpseraAuthService.js';
import { HealthStatus } from './types.js';
import type { ConnectorHealth, HealthCheck } from './types.js';

const logger = createLogger('OpseraHealthCheck');

const HEALTH_TIMEOUT_MS = 10_000;
const RATE_LIMIT_DEGRADED_THRESHOLD = 20;

/**
 * Checks the health of the Opsera connector by:
 *  1. Calling validateCredentials() to verify auth and org access
 *  2. Pinging GET /api/v1/health with a 10s timeout
 *  3. Reading X-RateLimit-Remaining / X-RateLimit-Limit headers for headroom
 */
export class OpseraHealthCheck implements HealthCheck {
  readonly name = 'opsera';

  private lastSuccessAt?: string;

  constructor(
    private readonly authService: OpseraAuthService,
    private readonly baseUrl: string = process.env['OPSERA_API_BASE_URL'] ?? 'https://api.opsera.io',
  ) {}

  async check(): Promise<ConnectorHealth> {
    const checkedAt = new Date().toISOString();

    // ── Step 1: validate credentials ─────────────────────────────────────────
    const validation = await this.authService.validateCredentials();
    if (!validation.valid) {
      const isNetwork = validation.code === 'NETWORK_ERROR';
      logger.warn('Opsera health check: credential validation failed', {
        code: validation.code,
        error: validation.error,
      });
      return {
        name: this.name,
        status: HealthStatus.UNHEALTHY,
        authStatus: isNetwork ? 'error' : 'unauthenticated',
        apiReachable: isNetwork ? false : false,
        checkedAt,
        error: validation.error,
      };
    }

    // ── Step 2: ping /api/v1/health with timeout ──────────────────────────────
    const controller = new AbortController();
    const timerId = setTimeout(() => controller.abort(), HEALTH_TIMEOUT_MS);
    const startMs = Date.now();

    let response: Response;
    try {
      const headers = await this.authService.getHeaders();
      response = await fetch(`${this.baseUrl}/api/v1/health`, {
        method: 'GET',
        headers,
        signal: controller.signal,
      });
      clearTimeout(timerId);
    } catch (err) {
      clearTimeout(timerId);
      const isTimeout = err instanceof Error && err.name === 'AbortError';
      logger.warn('Opsera health check: API ping failed', {
        timeout: isTimeout,
        error: String(err),
      });
      return {
        name: this.name,
        status: HealthStatus.UNHEALTHY,
        authStatus: 'authenticated',
        apiReachable: false,
        checkedAt,
        error: isTimeout
          ? `Opsera API did not respond within ${HEALTH_TIMEOUT_MS / 1000}s`
          : `Network error: ${String(err)}`,
      };
    }

    const latencyMs = Date.now() - startMs;

    if (!response.ok) {
      logger.warn('Opsera health check: non-OK response from /api/v1/health', {
        statusCode: response.status,
      });
      return {
        name: this.name,
        status: HealthStatus.UNHEALTHY,
        authStatus: 'authenticated',
        apiReachable: false,
        latencyMs,
        checkedAt,
        error: `/api/v1/health returned HTTP ${response.status}`,
      };
    }

    // ── Step 3: parse rate limit headers ──────────────────────────────────────
    const rateLimitRemaining = parseRateLimitHeaders(response.headers);

    const status =
      rateLimitRemaining !== undefined && rateLimitRemaining < RATE_LIMIT_DEGRADED_THRESHOLD
        ? HealthStatus.DEGRADED
        : HealthStatus.HEALTHY;

    this.lastSuccessAt = checkedAt;

    return {
      name: this.name,
      status,
      authStatus: 'authenticated',
      apiReachable: true,
      rateLimitRemaining,
      lastSuccessAt: this.lastSuccessAt,
      latencyMs,
      checkedAt,
    };
  }
}

/**
 * Parses X-RateLimit-Remaining and X-RateLimit-Limit headers and returns
 * the percentage of quota remaining (0–100), or undefined if headers are absent.
 */
function parseRateLimitHeaders(headers: Headers): number | undefined {
  const remaining = headers.get('X-RateLimit-Remaining');
  const limit = headers.get('X-RateLimit-Limit');
  if (remaining === null || limit === null) return undefined;
  const rem = parseInt(remaining, 10);
  const lim = parseInt(limit, 10);
  if (isNaN(rem) || isNaN(lim) || lim <= 0) return undefined;
  return Math.round((rem / lim) * 100);
}
