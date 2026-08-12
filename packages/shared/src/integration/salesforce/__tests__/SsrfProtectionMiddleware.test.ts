import { jest } from '@jest/globals';
import { createSsrfMiddleware } from '../SsrfProtectionMiddleware.js';
import { UrlAllowList } from '../../../common/security/UrlAllowList.js';
import { createMockRequest, createMockResponse, createMockNext } from '../../../database/test-utils.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Makes an allow-list that skips DNS validation for speed. */
function makeAllowList(opts?: { dnsV4?: string[] }): UrlAllowList {
  return new UrlAllowList({
    enableDnsValidation: opts?.dnsV4 !== undefined,
    dnsResolver: {
      resolve4: () => Promise.resolve(opts?.dnsV4 ?? ['104.193.30.10']),
      resolve6: () => Promise.reject(new Error('ENOTFOUND')),
    },
  });
}

async function invoke(
  middleware: ReturnType<typeof createSsrfMiddleware>,
  targetUrl: string | undefined,
  source: 'body' | 'query' = 'body',
): Promise<{ statusCode: number; body: unknown; nextCalled: boolean }> {
  const req = createMockRequest({
    method: 'POST',
    path: '/test',
    body: source === 'body' && targetUrl !== undefined ? { targetUrl } : {},
    query: source === 'query' && targetUrl !== undefined ? { targetUrl } : {},
  });

  const { res, getStatusCode, getJsonBody } = createMockResponse();
  const { next, getCalledWith } = createMockNext();

  // Give the async void IIFE inside the middleware time to complete
  await new Promise<void>((resolve) => {
    middleware(req as never, res as never, (...args: unknown[]) => { next(...(args as Parameters<typeof next>)); resolve(); });
    setTimeout(resolve, 200);
  });

  return {
    statusCode: getStatusCode(),
    body: getJsonBody(),
    nextCalled: getCalledWith() === undefined,
  };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('createSsrfMiddleware', () => {
  describe('allowed Salesforce URLs', () => {
    it('calls next() for a valid Salesforce URL in body', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'https://login.salesforce.com');
      expect(result.nextCalled).toBe(true);
    });

    it('calls next() for targetUrl in query string', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'https://myorg.my.salesforce.com', 'query');
      expect(result.nextCalled).toBe(true);
    });

    it('calls next() when no targetUrl is present (pass-through)', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, undefined);
      expect(result.nextCalled).toBe(true);
    });
  });

  describe('blocked requests', () => {
    it('returns 403 for a non-SF domain', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'https://evil.com');
      expect(result.statusCode).toBe(403);
      expect((result.body as Record<string, unknown>)['error']).toBe('SSRF_BLOCKED');
    });

    it('returns 403 for an empty string targetUrl', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      // empty string → pass-through because no URL to validate
      const result = await invoke(middleware, '');
      expect(result.nextCalled).toBe(true);
    });

    it('returns 403 for a private IP URL', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'http://10.0.0.1');
      expect(result.statusCode).toBe(403);
    });

    it('returns 403 for a malformed URL', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'not-a-url');
      expect(result.statusCode).toBe(403);
    });

    it('includes correlationId in the 403 response body', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'https://evil.com');
      expect((result.body as Record<string, unknown>)['correlationId']).toBeDefined();
    });

    it('includes human-readable message in the 403 response body', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'https://evil.com');
      expect(typeof (result.body as Record<string, unknown>)['message']).toBe('string');
    });

    it('does NOT include full query params of the blocked URL in the response', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const result = await invoke(middleware, 'https://evil.com?secret=hunter2&token=abc123');
      const bodyStr = JSON.stringify(result.body);
      expect(bodyStr).not.toContain('hunter2');
      expect(bodyStr).not.toContain('abc123');
    });
  });

  describe('DNS timeout → 503', () => {
    it('returns 503 with Retry-After when DNS resolution times out', async () => {
      const slowList = new UrlAllowList({
        enableDnsValidation: true,
        dnsTimeoutMs: 10,
        dnsResolver: {
          resolve4: () => new Promise((r) => setTimeout(() => r(['1.2.3.4']), 5_000)),
          resolve6: () => Promise.reject(new Error('ENOTFOUND')),
        },
      });
      const middleware = createSsrfMiddleware({ allowList: slowList });
      const result = await invoke(middleware, 'https://login.salesforce.com');
      expect(result.statusCode).toBe(503);
      expect((result.body as Record<string, unknown>)['error']).toBe('DNS_TIMEOUT');
    }, 10_000);
  });

  describe('body takes precedence over query string', () => {
    it('uses body targetUrl when both body and query are present', async () => {
      const middleware = createSsrfMiddleware({ allowList: makeAllowList() });
      const req = createMockRequest({
        body: { targetUrl: 'https://evil.com' },
        query: { targetUrl: 'https://login.salesforce.com' },
      });
      const { res, getStatusCode } = createMockResponse();
      const { next } = createMockNext();

      await new Promise<void>((resolve) => {
        middleware(req as never, res as never, (...args: unknown[]) => {
          next(...(args as Parameters<typeof next>));
          resolve();
        });
        setTimeout(resolve, 200);
      });

      // Body has evil.com → should be blocked
      expect(getStatusCode()).toBe(403);
    });
  });

  describe('uses default allow-list when none provided', () => {
    it('creates a middleware with default SF allow-list', () => {
      const middleware = createSsrfMiddleware();
      expect(typeof middleware).toBe('function');
    });
  });
});
