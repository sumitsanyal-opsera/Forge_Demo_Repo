import { SalesforceTokenCache } from '../SalesforceTokenCache.js';

const TOKEN_A = { accessToken: 'TOKEN_A', instanceUrl: 'https://org-a.salesforce.com' };
const TOKEN_B = { accessToken: 'TOKEN_B', instanceUrl: 'https://org-b.salesforce.com' };
const CLIENT_A = 'client_a';
const CLIENT_B = 'client_b';
const USER_A = 'user@org-a.com';
const USER_B = 'user@org-b.com';

describe('SalesforceTokenCache', () => {
  describe('get() and set()', () => {
    it('returns null for an unknown org', () => {
      const cache = new SalesforceTokenCache();
      expect(cache.get(CLIENT_A, USER_A)).toBeNull();
    });

    it('returns a stored token within its TTL', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      expect(cache.get(CLIENT_A, USER_A)).toEqual(TOKEN_A);
    });

    it('returns null after the TTL minus the proactive buffer has elapsed', async () => {
      // Use a 100ms TTL and 50ms proactive buffer
      const cache = new SalesforceTokenCache(50);
      cache.set(CLIENT_A, USER_A, TOKEN_A, 0.1); // 100ms TTL
      await new Promise((r) => setTimeout(r, 60)); // wait 60ms — inside buffer
      expect(cache.get(CLIENT_A, USER_A)).toBeNull();
    });

    it('isolates tokens by org (different clientId+username pairs)', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      cache.set(CLIENT_B, USER_B, TOKEN_B, 3_600);
      expect(cache.get(CLIENT_A, USER_A)).toEqual(TOKEN_A);
      expect(cache.get(CLIENT_B, USER_B)).toEqual(TOKEN_B);
    });

    it('same clientId but different username are independent', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      expect(cache.get(CLIENT_A, USER_B)).toBeNull();
    });

    it('same username but different clientId are independent', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      expect(cache.get(CLIENT_B, USER_A)).toBeNull();
    });

    it('overwrites existing entry when set() is called again', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      const updated = { accessToken: 'TOKEN_A_V2', instanceUrl: 'https://org-a-v2.salesforce.com' };
      cache.set(CLIENT_A, USER_A, updated, 3_600);
      expect(cache.get(CLIENT_A, USER_A)).toEqual(updated);
    });
  });

  describe('invalidate()', () => {
    it('clears the cached token', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      cache.invalidate(CLIENT_A, USER_A);
      expect(cache.get(CLIENT_A, USER_A)).toBeNull();
    });

    it('does not affect other org entries', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      cache.set(CLIENT_B, USER_B, TOKEN_B, 3_600);
      cache.invalidate(CLIENT_A, USER_A);
      expect(cache.get(CLIENT_B, USER_B)).toEqual(TOKEN_B);
    });

    it('is a no-op when the entry does not exist', () => {
      const cache = new SalesforceTokenCache();
      expect(() => cache.invalidate(CLIENT_A, USER_A)).not.toThrow();
    });
  });

  describe('isExpiringSoon()', () => {
    it('returns true when no token is cached', () => {
      const cache = new SalesforceTokenCache();
      expect(cache.isExpiringSoon(CLIENT_A, USER_A)).toBe(true);
    });

    it('returns false when a valid token exists', () => {
      const cache = new SalesforceTokenCache();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      expect(cache.isExpiringSoon(CLIENT_A, USER_A)).toBe(false);
    });

    it('returns true when token is within the proactive buffer', async () => {
      const cache = new SalesforceTokenCache(50);
      cache.set(CLIENT_A, USER_A, TOKEN_A, 0.05); // 50ms TTL = right in buffer
      await new Promise((r) => setTimeout(r, 10));
      expect(cache.isExpiringSoon(CLIENT_A, USER_A)).toBe(true);
    });
  });

  describe('withExclusiveRefresh() — promise deduplication', () => {
    it('calls the factory once when no refresh is in-flight', async () => {
      const cache = new SalesforceTokenCache();
      let calls = 0;
      const factory = (): Promise<typeof TOKEN_A> =>
        new Promise((r) => {
          calls++;
          setTimeout(() => r(TOKEN_A), 10);
        });

      await cache.withExclusiveRefresh(CLIENT_A, USER_A, factory);
      expect(calls).toBe(1);
    });

    it('returns the same promise for concurrent callers', async () => {
      const cache = new SalesforceTokenCache();
      let calls = 0;
      const factory = (): Promise<typeof TOKEN_A> =>
        new Promise((r) => {
          calls++;
          setTimeout(() => r(TOKEN_A), 50);
        });

      const p1 = cache.withExclusiveRefresh(CLIENT_A, USER_A, factory);
      const p2 = cache.withExclusiveRefresh(CLIENT_A, USER_A, factory);
      const [r1, r2] = await Promise.all([p1, p2]);

      expect(calls).toBe(1);
      expect(r1).toEqual(TOKEN_A);
      expect(r2).toEqual(TOKEN_A);
    });

    it('clears the pending entry after resolution', async () => {
      const cache = new SalesforceTokenCache();
      const factory = (): Promise<typeof TOKEN_A> => Promise.resolve(TOKEN_A);

      await cache.withExclusiveRefresh(CLIENT_A, USER_A, factory);
      expect(cache.hasPendingRefresh(CLIENT_A, USER_A)).toBe(false);
    });

    it('clears the pending entry even when the factory rejects', async () => {
      const cache = new SalesforceTokenCache();
      const factory = (): Promise<typeof TOKEN_A> =>
        Promise.reject(new Error('exchange failed'));

      await expect(
        cache.withExclusiveRefresh(CLIENT_A, USER_A, factory),
      ).rejects.toThrow('exchange failed');
      expect(cache.hasPendingRefresh(CLIENT_A, USER_A)).toBe(false);
    });

    it('allows a second refresh after the first completes', async () => {
      const cache = new SalesforceTokenCache();
      let calls = 0;
      const factory = (): Promise<typeof TOKEN_A> =>
        new Promise((r) => {
          calls++;
          r(TOKEN_A);
        });

      await cache.withExclusiveRefresh(CLIENT_A, USER_A, factory);
      await cache.withExclusiveRefresh(CLIENT_A, USER_A, factory);
      expect(calls).toBe(2);
    });

    it('does not deduplicate across different org keys', async () => {
      const cache = new SalesforceTokenCache();
      let calls = 0;
      const factory = (): Promise<typeof TOKEN_A> =>
        new Promise((r) => {
          calls++;
          setTimeout(() => r(TOKEN_A), 20);
        });

      await Promise.all([
        cache.withExclusiveRefresh(CLIENT_A, USER_A, factory),
        cache.withExclusiveRefresh(CLIENT_B, USER_B, factory),
      ]);
      expect(calls).toBe(2);
    });
  });

  describe('getExpiresAt()', () => {
    it('returns 0 when no token is cached', () => {
      const cache = new SalesforceTokenCache();
      expect(cache.getExpiresAt(CLIENT_A, USER_A)).toBe(0);
    });

    it('returns a future timestamp after set()', () => {
      const cache = new SalesforceTokenCache();
      const before = Date.now();
      cache.set(CLIENT_A, USER_A, TOKEN_A, 3_600);
      const expiresAt = cache.getExpiresAt(CLIENT_A, USER_A);
      expect(expiresAt).toBeGreaterThan(before + 3_590_000);
      expect(expiresAt).toBeLessThan(before + 3_610_000);
    });
  });
});
