/**
 * Unit tests for OpseraAuthService, ApiKeyAuthProvider, and OAuthAuthProvider.
 *
 * All HTTP calls are mocked via jest.fn() — no real network traffic.
 */

import { jest } from '@jest/globals';
import { ApiKeyAuthProvider } from '../ApiKeyAuthProvider.js';
import { OAuthAuthProvider } from '../OAuthAuthProvider.js';
import { OpseraAuthService } from '../OpseraAuthService.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeJsonResponse(status: number, body: unknown, headers?: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

// ─── ApiKeyAuthProvider ───────────────────────────────────────────────────────

describe('ApiKeyAuthProvider', () => {
  it('returns x-api-key header with the provided key', async () => {
    const provider = new ApiKeyAuthProvider('my-secret-key');
    const headers = await provider.getHeaders();
    expect(headers['x-api-key']).toBe('my-secret-key');
  });

  it('preserves special characters in the API key (no encoding)', async () => {
    const keyWithSpecialChars = 'key=abc/def+ghi==';
    const provider = new ApiKeyAuthProvider(keyWithSpecialChars);
    const headers = await provider.getHeaders();
    expect(headers['x-api-key']).toBe(keyWithSpecialChars);
  });

  it('throws when constructed with an empty key', () => {
    expect(() => new ApiKeyAuthProvider('')).toThrow(/OPSERA_API_KEY/);
  });

  it('invalidateCache() does not throw', () => {
    const provider = new ApiKeyAuthProvider('key');
    expect(() => provider.invalidateCache()).not.toThrow();
  });
});

// ─── OAuthAuthProvider ────────────────────────────────────────────────────────

describe('OAuthAuthProvider', () => {
  const AUTH_URL = 'https://auth.example.com/token';
  const CLIENT_ID = 'test-client-id';
  const CLIENT_SECRET = 'test-client-secret';
  const ACCESS_TOKEN = 'eyJhbGciOiJSUzI1NiJ9.payload.signature';

  beforeEach(() => {
    global.fetch = jest.fn<typeof global.fetch>();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  function mockTokenSuccess(token = ACCESS_TOKEN, expiresIn = 3600): void {
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(200, { access_token: token, token_type: 'Bearer', expires_in: expiresIn }),
    );
  }

  it('performs client credentials token exchange', async () => {
    mockTokenSuccess();
    const provider = new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, AUTH_URL);
    const headers = await provider.getHeaders();

    expect(headers['Authorization']).toBe(`Bearer ${ACCESS_TOKEN}`);
    expect(global.fetch).toHaveBeenCalledTimes(1);

    const [url, init] = (global.fetch as jest.MockedFunction<typeof global.fetch>).mock.calls[0]!;
    expect(String(url)).toBe(AUTH_URL);
    expect((init as RequestInit)?.method).toBe('POST');
  });

  it('sends client_id and client_secret in the token request body', async () => {
    mockTokenSuccess();
    const provider = new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, AUTH_URL);
    await provider.getHeaders();

    const [, init] = (global.fetch as jest.MockedFunction<typeof global.fetch>).mock.calls[0]!;
    const body = (init as RequestInit)?.body as string;
    const params = new URLSearchParams(body);
    expect(params.get('grant_type')).toBe('client_credentials');
    expect(params.get('client_id')).toBe(CLIENT_ID);
    expect(params.get('client_secret')).toBe(CLIENT_SECRET);
  });

  it('caches the token and reuses it without a second exchange', async () => {
    mockTokenSuccess(ACCESS_TOKEN, 3600);
    const provider = new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, AUTH_URL);

    const headers1 = await provider.getHeaders();
    const headers2 = await provider.getHeaders();

    expect(headers1['Authorization']).toBe(headers2['Authorization']);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('fetches a new token after invalidateCache()', async () => {
    mockTokenSuccess(ACCESS_TOKEN, 3600);
    mockTokenSuccess('new-access-token', 3600);
    const provider = new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, AUTH_URL);

    await provider.getHeaders();
    provider.invalidateCache();
    const headers = await provider.getHeaders();

    expect(headers['Authorization']).toBe('Bearer new-access-token');
    expect(global.fetch).toHaveBeenCalledTimes(2);
  });

  it('throws with a descriptive error for non-standard OAuth error response', async () => {
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(400, { error: 'invalid_client', error_description: 'Bad credentials' }),
    );
    const provider = new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, AUTH_URL);
    await expect(provider.getHeaders()).rejects.toThrow(/invalid_client/);
  });

  it('throws when access_token is missing from the response', async () => {
    (global.fetch as jest.MockedFunction<typeof global.fetch>).mockResolvedValueOnce(
      makeJsonResponse(200, { token_type: 'Bearer' }),
    );
    const provider = new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, AUTH_URL);
    await expect(provider.getHeaders()).rejects.toThrow(/access_token is missing/);
  });

  it('throws when constructed without clientId', () => {
    expect(() => new OAuthAuthProvider('', CLIENT_SECRET, AUTH_URL)).toThrow(
      /OPSERA_CLIENT_ID/,
    );
  });

  it('throws when constructed without authUrl', () => {
    expect(() => new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, '')).toThrow(
      /OPSERA_AUTH_URL/,
    );
  });

  it('proactively sets a refresh buffer on the token', async () => {
    mockTokenSuccess(ACCESS_TOKEN, 3600);
    const provider = new OAuthAuthProvider(CLIENT_ID, CLIENT_SECRET, AUTH_URL);
    await provider.getHeaders();

    const expiresAt = provider.tokenExpiresAt;
    const nowPlusTTL = Date.now() + 3600 * 1000;
    // Token expires at approximately now + TTL
    expect(expiresAt).toBeGreaterThan(nowPlusTTL - 5_000);
    expect(expiresAt).toBeLessThanOrEqual(nowPlusTTL + 5_000);
  });
});

// ─── OpseraAuthService ────────────────────────────────────────────────────────

describe('OpseraAuthService', () => {
  const ORIGINAL_ENV = { ...process.env };

  afterEach(() => {
    // Restore environment
    for (const key of Object.keys(process.env)) {
      if (!(key in ORIGINAL_ENV)) delete process.env[key];
    }
    Object.assign(process.env, ORIGINAL_ENV);
    jest.restoreAllMocks();
  });

  it('uses ApiKeyAuthProvider when authMode is apikey', async () => {
    const svc = new OpseraAuthService({ authMode: 'apikey', apiKey: 'test-key-123' });
    const headers = await svc.getHeaders();
    expect(headers['x-api-key']).toBe('test-key-123');
    expect(svc.authMode).toBe('apikey');
  });

  it('uses OAuthAuthProvider when authMode is oauth', async () => {
    global.fetch = jest.fn<typeof global.fetch>().mockResolvedValueOnce(
      makeJsonResponse(200, {
        access_token: 'oauth-token-xyz',
        token_type: 'Bearer',
        expires_in: 3600,
      }),
    );

    const svc = new OpseraAuthService({
      authMode: 'oauth',
      clientId: 'cid',
      clientSecret: 'csec',
      authUrl: 'https://auth.example.com/token',
    });

    const headers = await svc.getHeaders();
    expect(headers['Authorization']).toContain('Bearer');
    expect(svc.authMode).toBe('oauth');
  });

  it('defaults to apikey mode when OPSERA_AUTH_MODE is not set', () => {
    delete process.env['OPSERA_AUTH_MODE'];
    const svc = new OpseraAuthService({ apiKey: 'fallback-key' });
    expect(svc.authMode).toBe('apikey');
  });

  it('reads config from environment variables', async () => {
    process.env['OPSERA_AUTH_MODE'] = 'apikey';
    process.env['OPSERA_API_KEY'] = 'env-key-456';
    const svc = new OpseraAuthService();
    const headers = await svc.getHeaders();
    expect(headers['x-api-key']).toBe('env-key-456');
  });

  it('validateCredentials() returns valid:true on successful verify call', async () => {
    global.fetch = jest.fn<typeof global.fetch>().mockResolvedValueOnce(
      makeJsonResponse(200, {
        orgId: 'org-123',
        orgName: 'Test Org',
        environment: 'production',
      }),
    );

    const svc = new OpseraAuthService({
      authMode: 'apikey',
      apiKey: 'valid-key',
      apiBaseUrl: 'https://api.opsera.io',
    });

    const result = await svc.validateCredentials();
    expect(result.valid).toBe(true);
    expect(result.orgInfo?.orgId).toBe('org-123');
    expect(result.orgInfo?.orgName).toBe('Test Org');
  });

  it('validateCredentials() returns valid:false for 401 response', async () => {
    global.fetch = jest.fn<typeof global.fetch>().mockResolvedValueOnce(
      makeJsonResponse(401, { message: 'Invalid API key' }),
    );

    const svc = new OpseraAuthService({
      authMode: 'apikey',
      apiKey: 'bad-key',
      apiBaseUrl: 'https://api.opsera.io',
    });

    const result = await svc.validateCredentials();
    expect(result.valid).toBe(false);
    expect(result.code).toBe('AUTH_INVALID_KEY');
    expect(result.remediationMessage).toBeDefined();
  });

  it('validateCredentials() returns valid:false with NETWORK_ERROR on timeout', async () => {
    global.fetch = jest.fn<typeof global.fetch>().mockRejectedValueOnce(
      new Error('ECONNREFUSED'),
    );

    const svc = new OpseraAuthService({
      authMode: 'apikey',
      apiKey: 'any-key',
      apiBaseUrl: 'https://unreachable.example.com',
    });

    const result = await svc.validateCredentials();
    expect(result.valid).toBe(false);
    expect(result.code).toBe('NETWORK_ERROR');
  });

  it('switchAuthMode() invalidates cache and changes the provider', async () => {
    const tokenFetch = jest.fn<typeof global.fetch>()
      .mockResolvedValueOnce(
        makeJsonResponse(200, { access_token: 'original-token', token_type: 'Bearer', expires_in: 3600 }),
      )
      .mockResolvedValueOnce(
        makeJsonResponse(200, { access_token: 'switched-token', token_type: 'Bearer', expires_in: 3600 }),
      );
    global.fetch = tokenFetch;

    const svc = new OpseraAuthService({
      authMode: 'oauth',
      clientId: 'cid',
      clientSecret: 'csec',
      authUrl: 'https://auth.example.com/token',
    });

    await svc.getHeaders(); // primes the cache

    svc.switchAuthMode('apikey', { apiKey: 'switched-to-apikey' });
    const headers = await svc.getHeaders();
    expect(headers['x-api-key']).toBe('switched-to-apikey');
    expect(svc.authMode).toBe('apikey');
  });
});
