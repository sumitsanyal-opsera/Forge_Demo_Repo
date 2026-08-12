import { jest } from '@jest/globals';
import { OpseraHealthCheck } from '../OpseraHealthCheck.js';
import { HealthStatus } from '../types.js';
import type { OpseraAuthService } from '../../opsera/auth/OpseraAuthService.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeJsonResponse(
  status: number,
  body: unknown,
  headers?: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

function makeAuthService(
  valid: boolean,
  opts?: { code?: string; error?: string },
): jest.Mocked<Pick<OpseraAuthService, 'validateCredentials' | 'getHeaders'>> {
  return {
    validateCredentials: jest.fn<OpseraAuthService['validateCredentials']>().mockResolvedValue(
      valid
        ? {
            valid: true,
            orgInfo: { orgId: 'org-1', orgName: 'Test Org', environment: 'production' },
          }
        : {
            valid: false,
            error: opts?.error ?? 'Invalid API key',
            code: opts?.code ?? 'AUTH_INVALID_KEY',
            remediationMessage: 'Check your API key',
          },
    ),
    getHeaders: jest
      .fn<OpseraAuthService['getHeaders']>()
      .mockResolvedValue({ 'x-api-key': 'test-key' }),
  };
}

const BASE_URL = 'https://api.opsera.io';

// ─── Tests ────────────────────────────────────────────────────────────────────

beforeEach(() => {
  global.fetch = jest.fn<typeof global.fetch>();
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('OpseraHealthCheck', () => {
  it('returns HEALTHY when auth is valid and /api/v1/health responds 200', async () => {
    const auth = makeAuthService(true);
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(200, { status: 'ok' }, {
        'X-RateLimit-Remaining': '80',
        'X-RateLimit-Limit': '100',
      }),
    );

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.HEALTHY);
    expect(result.authStatus).toBe('authenticated');
    expect(result.apiReachable).toBe(true);
    expect(result.rateLimitRemaining).toBe(80);
    expect(result.lastSuccessAt).toBeDefined();
  });

  it('returns DEGRADED when rate limit remaining is below 20%', async () => {
    const auth = makeAuthService(true);
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(200, {}, {
        'X-RateLimit-Remaining': '10',
        'X-RateLimit-Limit': '100',
      }),
    );

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.DEGRADED);
    expect(result.rateLimitRemaining).toBe(10);
    expect(result.apiReachable).toBe(true);
  });

  it('returns UNHEALTHY when credentials are invalid', async () => {
    const auth = makeAuthService(false, { code: 'AUTH_INVALID_KEY', error: 'Bad key' });

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.authStatus).toBe('unauthenticated');
    expect(result.apiReachable).toBe(false);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('returns UNHEALTHY when network fails with NETWORK_ERROR code', async () => {
    const auth = makeAuthService(false, { code: 'NETWORK_ERROR', error: 'ECONNREFUSED' });

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.authStatus).toBe('error');
  });

  it('returns UNHEALTHY when /api/v1/health ping times out', async () => {
    jest.useRealTimers();
    const auth = makeAuthService(true);
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockRejectedValueOnce(
      Object.assign(new Error('The operation was aborted'), { name: 'AbortError' }),
    );

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.apiReachable).toBe(false);
    expect(result.error).toContain('10s');
  });

  it('returns UNHEALTHY when /api/v1/health returns non-2xx', async () => {
    const auth = makeAuthService(true);
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(502, {}),
    );

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.apiReachable).toBe(false);
    expect(result.error).toContain('502');
  });

  it('treats missing rate limit headers as healthy (unknown headroom)', async () => {
    const auth = makeAuthService(true);
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(200, {}),
    );

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.HEALTHY);
    expect(result.rateLimitRemaining).toBeUndefined();
  });

  it('injects auth headers into the ping request', async () => {
    const auth = makeAuthService(true);
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(200, {}),
    );

    const check = new OpseraHealthCheck(auth as unknown as OpseraAuthService, BASE_URL);
    await check.check();

    const [url, init] = (global.fetch as jest.MockedFunction<typeof global.fetch>).mock.calls[0]!;
    expect(String(url)).toContain('/api/v1/health');
    expect((init as RequestInit).headers as Record<string, string>).toMatchObject({
      'x-api-key': 'test-key',
    });
  });
});
