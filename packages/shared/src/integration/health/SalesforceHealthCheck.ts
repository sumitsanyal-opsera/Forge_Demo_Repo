import { createLogger } from '../../logging/logger.js';
import { HealthStatus } from './types.js';
import type { ConnectorHealth, HealthCheck } from './types.js';

const logger = createLogger('SalesforceHealthCheck');

const HEALTH_TIMEOUT_MS = 10_000;
const RATE_LIMIT_DEGRADED_THRESHOLD = 20;

/**
 * Minimal interface for the Salesforce connection dependency.
 * The full Salesforce connector (WO-020) implements this contract.
 */
export interface SalesforceConnectionConfig {
  /** Salesforce instance URL, e.g. https://myorg.my.salesforce.com */
  instanceUrl: string;
  /** Returns a valid access token or throws if auth has failed. */
  getAccessToken(): Promise<string>;
}

/**
 * Checks the health of the Salesforce connector by:
 *  1. Requesting an access token (verifies auth lifecycle is functional)
 *  2. Pinging /services/data/ (lightweight version list — does not count against deploy limits)
 *  3. Parsing Sforce-Limit-Info header to compute rate limit headroom
 */
export class SalesforceHealthCheck implements HealthCheck {
  readonly name = 'salesforce';

  private lastSuccessAt?: string;

  constructor(private readonly connection: SalesforceConnectionConfig) {}

  async check(): Promise<ConnectorHealth> {
    const checkedAt = new Date().toISOString();

    // ── Step 1: verify auth ────────────────────────────────────────────────────
    let accessToken: string;
    try {
      accessToken = await this.connection.getAccessToken();
    } catch (err) {
      logger.warn('Salesforce health check: auth token acquisition failed', {
        error: String(err),
      });
      return {
        name: this.name,
        status: HealthStatus.UNHEALTHY,
        authStatus: 'unauthenticated',
        apiReachable: false,
        checkedAt,
        error: `Token acquisition failed: ${String(err)}`,
      };
    }

    // ── Step 2: ping /services/data/ with timeout ─────────────────────────────
    const controller = new AbortController();
    const timerId = setTimeout(() => controller.abort(), HEALTH_TIMEOUT_MS);
    const startMs = Date.now();

    let response: Response;
    try {
      response = await fetch(`${this.connection.instanceUrl}/services/data/`, {
        method: 'GET',
        headers: { Authorization: `Bearer ${accessToken}` },
        signal: controller.signal,
      });
      clearTimeout(timerId);
    } catch (err) {
      clearTimeout(timerId);
      const isTimeout = err instanceof Error && err.name === 'AbortError';
      logger.warn('Salesforce health check: API ping failed', {
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
          ? `Salesforce API did not respond within ${HEALTH_TIMEOUT_MS / 1000}s`
          : `Network error: ${String(err)}`,
      };
    }

    const latencyMs = Date.now() - startMs;

    if (!response.ok) {
      logger.warn('Salesforce health check: non-OK response from /services/data/', {
        statusCode: response.status,
      });
      return {
        name: this.name,
        status: HealthStatus.UNHEALTHY,
        authStatus: 'authenticated',
        apiReachable: false,
        latencyMs,
        checkedAt,
        error: `/services/data/ returned HTTP ${response.status}`,
      };
    }

    // ── Step 3: parse rate limit from Sforce-Limit-Info header ────────────────
    const rateLimitRemaining = parseSforceLimitInfo(response.headers.get('Sforce-Limit-Info'));

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
 * Parses the `Sforce-Limit-Info` header, e.g. "api-usage=12345/15000",
 * and returns the percentage of daily API calls remaining (0–100), or
 * undefined if the header is absent or unparseable.
 */
function parseSforceLimitInfo(header: string | null): number | undefined {
  if (header === null) return undefined;
  const match = /api-usage=(\d+)\/(\d+)/i.exec(header);
  if (match === null) return undefined;
  const used = parseInt(match[1]!, 10);
  const total = parseInt(match[2]!, 10);
  if (total <= 0) return undefined;
  return Math.round(((total - used) / total) * 100);
}
