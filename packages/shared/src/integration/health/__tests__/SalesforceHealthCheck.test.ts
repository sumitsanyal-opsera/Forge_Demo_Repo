import { jest } from '@jest/globals';
import { SalesforceHealthCheck } from '../SalesforceHealthCheck.js';
import { HealthStatus } from '../types.js';
import type { SalesforceConnectionConfig } from '../SalesforceHealthCheck.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeResponse(
  status: number,
  body: string,
  headers?: Record<string, string>,
): Response {
  return new Response(body, { status, headers });
}

function makeConnection(
  instanceUrl: string,
  tokenResult: 'ok' | 'throw',
  token = 'sf-access-token',
): SalesforceConnectionConfig {
  return {
    instanceUrl,
    getAccessToken: tokenResult === 'ok'
      ? jest.fn<SalesforceConnectionConfig['getAccessToken']>().mockResolvedValue(token)
      : jest.fn<SalesforceConnectionConfig['getAccessToken']>().mockRejectedValue(
          new Error('invalid_grant'),
        ),
  };
}

beforeEach(() => {
  global.fetch = jest.fn<typeof global.fetch>();
});

afterEach(() => {
  jest.restoreAllMocks();
});

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('SalesforceHealthCheck', () => {
  const INSTANCE_URL = 'https://myorg.my.salesforce.com';

  it('returns HEALTHY when auth succeeds and /services/data/ responds 200', async () => {
    const conn = makeConnection(INSTANCE_URL, 'ok');
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeResponse(200, '[]', { 'Sforce-Limit-Info': 'api-usage=5000/15000' }),
    );

    const check = new SalesforceHealthCheck(conn);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.HEALTHY);
    expect(result.authStatus).toBe('authenticated');
    expect(result.apiReachable).toBe(true);
    expect(result.rateLimitRemaining).toBe(67);
  });

  it('returns DEGRADED when Salesforce rate limit is below 20%', async () => {
    const conn = makeConnection(INSTANCE_URL, 'ok');
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeResponse(200, '[]', { 'Sforce-Limit-Info': 'api-usage=14700/15000' }),
    );

    const check = new SalesforceHealthCheck(conn);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.DEGRADED);
    // 300/15000 = 2% remaining
    expect(result.rateLimitRemaining).toBe(2);
  });

  it('returns UNHEALTHY when token acquisition throws', async () => {
    const conn = makeConnection(INSTANCE_URL, 'throw');

    const check = new SalesforceHealthCheck(conn);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.authStatus).toBe('unauthenticated');
    expect(result.apiReachable).toBe(false);
    expect(result.error).toContain('invalid_grant');
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('returns UNHEALTHY when the API ping times out', async () => {
    const conn = makeConnection(INSTANCE_URL, 'ok');
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockRejectedValueOnce(
      Object.assign(new Error('Aborted'), { name: 'AbortError' }),
    );

    const check = new SalesforceHealthCheck(conn);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.apiReachable).toBe(false);
    expect(result.error).toContain('10s');
  });

  it('returns UNHEALTHY when /services/data/ returns non-OK status', async () => {
    const conn = makeConnection(INSTANCE_URL, 'ok');
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeResponse(401, '{"message":"Session expired or invalid"}'),
    );

    const check = new SalesforceHealthCheck(conn);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.UNHEALTHY);
    expect(result.apiReachable).toBe(false);
    expect(result.error).toContain('401');
  });

  it('includes Bearer token in the Authorization header', async () => {
    const conn = makeConnection(INSTANCE_URL, 'ok', 'my-sf-token');
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeResponse(200, '[]'),
    );

    const check = new SalesforceHealthCheck(conn);
    await check.check();

    const [url, init] = (global.fetch as jest.MockedFunction<typeof global.fetch>).mock.calls[0]!;
    expect(String(url)).toContain('/services/data/');
    expect((init as RequestInit).headers as Record<string, string>).toMatchObject({
      Authorization: 'Bearer my-sf-token',
    });
  });

  it('handles missing Sforce-Limit-Info header as healthy (unknown headroom)', async () => {
    const conn = makeConnection(INSTANCE_URL, 'ok');
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeResponse(200, '[]'),
    );

    const check = new SalesforceHealthCheck(conn);
    const result = await check.check();

    expect(result.status).toBe(HealthStatus.HEALTHY);
    expect(result.rateLimitRemaining).toBeUndefined();
  });

  it('records lastSuccessAt on successful check', async () => {
    const conn = makeConnection(INSTANCE_URL, 'ok');
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeResponse(200, '[]'),
    );

    const check = new SalesforceHealthCheck(conn);
    const result = await check.check();

    expect(result.lastSuccessAt).toBeDefined();
    expect(result.lastSuccessAt).toBe(result.checkedAt);
  });
});
