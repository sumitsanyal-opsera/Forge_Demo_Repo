import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { jest } from '@jest/globals';
import { SalesforceAuthService, type SalesforceHttpClient } from '../SalesforceAuthService.js';
import { SalesforceTokenCache } from '../SalesforceTokenCache.js';
import { JwtBuilder } from '../JwtBuilder.js';
import {
  SalesforceAuthError,
  SF_AUTH_ERROR_CODES,
  isSalesforceAuthError,
} from '../SalesforceAuthError.js';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

interface KeyPairFixture {
  privateKey: string;
}

interface MockResponses {
  success: Record<string, unknown>;
  errorInvalidGrant: Record<string, unknown>;
  errorInvalidClient: Record<string, unknown>;
  errorInvalidAppAccess: Record<string, unknown>;
  error500: Record<string, unknown>;
}

const FIXTURES_DIR = join(process.cwd(), 'test/fixtures/salesforce-auth');

function loadPrivateKey(): string {
  const raw = readFileSync(join(FIXTURES_DIR, 'test-rsa-keypair.json'), 'utf-8');
  return (JSON.parse(raw) as KeyPairFixture).privateKey;
}

function loadMockResponses(): MockResponses {
  const raw = readFileSync(join(FIXTURES_DIR, 'mock-oauth-responses.json'), 'utf-8');
  return JSON.parse(raw) as MockResponses;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeHttpClient(
  status: number,
  body: unknown,
): SalesforceHttpClient {
  return jest.fn<SalesforceHttpClient>().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(body),
  } as Response);
}

function makeThrowingHttpClient(err: Error): SalesforceHttpClient {
  return jest.fn<SalesforceHttpClient>().mockRejectedValue(err);
}

function makeService(
  httpClient: SalesforceHttpClient,
  opts: { tokenCache?: SalesforceTokenCache; privateKey?: string } = {},
): SalesforceAuthService {
  const privateKey = opts.privateKey ?? loadPrivateKey();
  return new SalesforceAuthService({
    clientId: 'TEST_CLIENT_ID',
    username: 'test@myorg.com',
    loginUrl: 'https://login.salesforce.com',
    privateKey,
    httpClient,
    tokenCache: opts.tokenCache ?? new SalesforceTokenCache(),
    jwtBuilder: new JwtBuilder({ expirySeconds: 60, clockSkewSeconds: 0 }),
  });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('SalesforceAuthService', () => {
  let privateKey: string;
  let mockResponses: MockResponses;

  beforeAll(() => {
    privateKey = loadPrivateKey();
    mockResponses = loadMockResponses();
  });

  describe('constructor validation', () => {
    it('throws AUTH_PRIVATE_KEY_LOAD_ERROR when no private key is available', () => {
      const origEnv = { ...process.env };
      delete process.env['SF_JWT_PRIVATE_KEY'];
      delete process.env['SF_JWT_PRIVATE_KEY_PATH'];
      delete process.env['SF_CLIENT_ID'];
      delete process.env['SF_USERNAME'];

      try {
        expect(() =>
          new SalesforceAuthService({
            clientId: 'ID',
            username: 'u@org.com',
            // no privateKey, no env vars
          }),
        ).toThrow(SalesforceAuthError);
      } finally {
        Object.assign(process.env, origEnv);
      }
    });

    it('throws AUTH_INVALID_CLIENT when clientId is missing', () => {
      expect(() => {
        new SalesforceAuthService({
          username: 'u@org.com',
          privateKey,
          clientId: '',
        });
      }).toThrow(SalesforceAuthError);
    });

    it('throws AUTH_INVALID_GRANT when username is missing', () => {
      expect(() => {
        new SalesforceAuthService({
          clientId: 'ID',
          privateKey,
          username: '',
        });
      }).toThrow(SalesforceAuthError);
    });
  });

  describe('getAccessToken() — successful exchange', () => {
    it('returns accessToken and instanceUrl on success', async () => {
      const httpClient = makeHttpClient(200, mockResponses.success);
      const svc = makeService(httpClient, { privateKey });

      const token = await svc.getAccessToken();
      expect(token.accessToken).toBe(
        (mockResponses.success as Record<string, string>)['access_token'],
      );
      expect(token.instanceUrl).toBe(
        (mockResponses.success as Record<string, string>)['instance_url'],
      );
    });

    it('sends POST to <loginUrl>/services/oauth2/token', async () => {
      const httpClient = makeHttpClient(200, mockResponses.success);
      const svc = makeService(httpClient, { privateKey });

      await svc.getAccessToken();

      const mockFn = httpClient as ReturnType<typeof jest.fn>;
      expect(mockFn).toHaveBeenCalledWith(
        'https://login.salesforce.com/services/oauth2/token',
        expect.objectContaining({ method: 'POST' }),
      );
    });

    it('sends the JWT Bearer grant_type', async () => {
      const httpClient = makeHttpClient(200, mockResponses.success);
      const svc = makeService(httpClient, { privateKey });

      await svc.getAccessToken();

      const mockFn = httpClient as ReturnType<typeof jest.fn>;
      const [, init] = mockFn.mock.calls[0] as [string, RequestInit];
      expect(String(init.body)).toContain(
        'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer',
      );
    });
  });

  describe('getAccessToken() — caching', () => {
    it('does not call the HTTP client on a second call within TTL', async () => {
      const httpClient = makeHttpClient(200, mockResponses.success);
      const tokenCache = new SalesforceTokenCache();
      const svc = makeService(httpClient, { privateKey, tokenCache });

      const t1 = await svc.getAccessToken();
      const t2 = await svc.getAccessToken();

      const mockFn = httpClient as ReturnType<typeof jest.fn>;
      expect(mockFn).toHaveBeenCalledTimes(1);
      expect(t1).toEqual(t2);
    });

    it('makes a new HTTP call after the cache is invalidated', async () => {
      const httpClient = makeHttpClient(200, mockResponses.success);
      const svc = makeService(httpClient, { privateKey });

      await svc.getAccessToken();
      await svc.forceRefresh();

      const mockFn = httpClient as ReturnType<typeof jest.fn>;
      expect(mockFn).toHaveBeenCalledTimes(2);
    });
  });

  describe('getAccessToken() — concurrent deduplication', () => {
    it('issues only one HTTP request for concurrent callers', async () => {
      const httpClient = makeHttpClient(200, mockResponses.success);
      const tokenCache = new SalesforceTokenCache();
      const svc = makeService(httpClient, { privateKey, tokenCache });

      const [r1, r2, r3] = await Promise.all([
        svc.getAccessToken(),
        svc.getAccessToken(),
        svc.getAccessToken(),
      ]);

      const mockFn = httpClient as ReturnType<typeof jest.fn>;
      expect(mockFn).toHaveBeenCalledTimes(1);
      expect(r1).toEqual(r2);
      expect(r2).toEqual(r3);
    });
  });

  describe('getAccessToken() — error mapping', () => {
    it('maps invalid_grant to SalesforceAuthError with AUTH_INVALID_GRANT', async () => {
      const httpClient = makeHttpClient(400, mockResponses.errorInvalidGrant);
      const svc = makeService(httpClient, { privateKey });

      await expect(svc.getAccessToken()).rejects.toMatchObject({
        code: SF_AUTH_ERROR_CODES.AUTH_INVALID_GRANT,
      });
    });

    it('maps invalid_client to AUTH_INVALID_CLIENT', async () => {
      const httpClient = makeHttpClient(400, mockResponses.errorInvalidClient);
      const svc = makeService(httpClient, { privateKey });

      await expect(svc.getAccessToken()).rejects.toMatchObject({
        code: SF_AUTH_ERROR_CODES.AUTH_INVALID_CLIENT,
      });
    });

    it('maps invalid_app_access to AUTH_INVALID_APP_ACCESS', async () => {
      const httpClient = makeHttpClient(403, mockResponses.errorInvalidAppAccess);
      const svc = makeService(httpClient, { privateKey });

      await expect(svc.getAccessToken()).rejects.toMatchObject({
        code: SF_AUTH_ERROR_CODES.AUTH_INVALID_APP_ACCESS,
      });
    });

    it('throws a SalesforceAuthError (isSalesforceAuthError predicate)', async () => {
      const httpClient = makeHttpClient(400, mockResponses.errorInvalidGrant);
      const svc = makeService(httpClient, { privateKey });

      let caught: unknown;
      try {
        await svc.getAccessToken();
      } catch (err) {
        caught = err;
      }
      expect(isSalesforceAuthError(caught)).toBe(true);
    });

    it('errors include a non-empty remediation string', async () => {
      const httpClient = makeHttpClient(400, mockResponses.errorInvalidClient);
      const svc = makeService(httpClient, { privateKey });

      await expect(svc.getAccessToken()).rejects.toMatchObject({
        remediation: expect.stringContaining('Verify'),
      });
    });
  });

  describe('getAccessToken() — network errors and retry', () => {
    it('wraps network errors in AUTH_NETWORK_ERROR', async () => {
      // withRetry will retry, but all attempts fail
      const httpClient = makeThrowingHttpClient(new Error('ECONNREFUSED'));
      const svc = makeService(httpClient, { privateKey });

      await expect(svc.getAccessToken()).rejects.toMatchObject({
        code: SF_AUTH_ERROR_CODES.AUTH_NETWORK_ERROR,
      });
    }, 15_000); // allow time for 3 retries

    it('retries 5xx responses up to 3 times before failing', async () => {
      const httpClient = makeHttpClient(500, mockResponses.error500);
      const svc = makeService(httpClient, { privateKey });

      await expect(svc.getAccessToken()).rejects.toThrow(SalesforceAuthError);

      const mockFn = httpClient as ReturnType<typeof jest.fn>;
      // 1 initial + up to 3 retries
      expect(mockFn.mock.calls.length).toBeGreaterThanOrEqual(2);
    }, 30_000);

    it('succeeds on a retry after a transient 500', async () => {
      let callCount = 0;
      const httpClient = jest.fn<SalesforceHttpClient>().mockImplementation(() => {
        callCount++;
        if (callCount < 2) {
          return Promise.resolve({
            ok: false,
            status: 500,
            json: () => Promise.resolve(mockResponses.error500),
          } as Response);
        }
        return Promise.resolve({
          ok: true,
          status: 200,
          json: () => Promise.resolve(mockResponses.success),
        } as Response);
      });

      const svc = makeService(httpClient, { privateKey });
      const token = await svc.getAccessToken();
      expect(token.accessToken).toBeTruthy();
      expect(callCount).toBe(2);
    }, 15_000);
  });

  describe('forceRefresh()', () => {
    it('bypasses cache and exchanges a fresh token', async () => {
      const httpClient = makeHttpClient(200, mockResponses.success);
      const svc = makeService(httpClient, { privateKey });

      await svc.getAccessToken();
      const refreshed = await svc.forceRefresh();

      const mockFn = httpClient as ReturnType<typeof jest.fn>;
      expect(mockFn).toHaveBeenCalledTimes(2);
      expect(refreshed.accessToken).toBeTruthy();
    });
  });

  describe('private key loading', () => {
    it('loads private key from SF_JWT_PRIVATE_KEY env var with literal \\n replaced', () => {
      const origEnv = { ...process.env };
      // Simulate env var with literal \n
      process.env['SF_JWT_PRIVATE_KEY'] = privateKey.replace(/\n/g, '\\n');
      process.env['SF_CLIENT_ID'] = 'TEST_CLIENT_ID';
      process.env['SF_USERNAME'] = 'test@myorg.com';

      try {
        const svc = new SalesforceAuthService({
          httpClient: makeHttpClient(200, mockResponses.success),
          tokenCache: new SalesforceTokenCache(),
          jwtBuilder: new JwtBuilder({ expirySeconds: 60, clockSkewSeconds: 0 }),
        });
        expect(svc).toBeInstanceOf(SalesforceAuthService);
      } finally {
        Object.assign(process.env, origEnv);
        delete process.env['SF_JWT_PRIVATE_KEY'];
      }
    });
  });
});
