/**
 * Multi-org Salesforce token cache with proactive refresh and promise
 * deduplication.
 *
 * Unlike the generic TokenCache in common/auth/, this cache:
 *   - Is keyed by (clientId, username) to support multiple orgs
 *   - Stores both accessToken and instanceUrl
 *   - Deduplicates concurrent refresh requests so only one token exchange
 *     is in-flight at a time per org
 *
 * Default proactive refresh buffer: 5 minutes (SF tokens live for ~2 hours by
 * default, so a 5-minute buffer gives ample time to complete in-flight calls).
 */

export interface SalesforceToken {
  accessToken: string;
  instanceUrl: string;
}

interface CacheEntry extends SalesforceToken {
  expiresAtMs: number;
}

export class SalesforceTokenCache {
  private readonly cache = new Map<string, CacheEntry>();
  private readonly pendingRefreshes = new Map<string, Promise<SalesforceToken>>();
  private readonly proactiveRefreshBufferMs: number;

  constructor(proactiveRefreshBufferMs = 5 * 60 * 1_000) {
    this.proactiveRefreshBufferMs = proactiveRefreshBufferMs;
  }

  private key(clientId: string, username: string): string {
    return `${clientId}::${username}`;
  }

  /**
   * Returns the cached token if it is still valid (with buffer), or `null` if
   * absent or within the proactive refresh window.
   */
  get(clientId: string, username: string): SalesforceToken | null {
    const entry = this.cache.get(this.key(clientId, username));
    if (entry === undefined) return null;
    if (Date.now() >= entry.expiresAtMs - this.proactiveRefreshBufferMs) return null;
    return { accessToken: entry.accessToken, instanceUrl: entry.instanceUrl };
  }

  /** Stores a token for the given org identity. */
  set(clientId: string, username: string, token: SalesforceToken, expiresInSeconds: number): void {
    this.cache.set(this.key(clientId, username), {
      ...token,
      expiresAtMs: Date.now() + expiresInSeconds * 1_000,
    });
  }

  /** Removes the cached token, forcing a fresh exchange on next `get()`. */
  invalidate(clientId: string, username: string): void {
    this.cache.delete(this.key(clientId, username));
  }

  /** `true` when no valid (non-expiring) token exists for this org. */
  isExpiringSoon(clientId: string, username: string): boolean {
    return this.get(clientId, username) === null;
  }

  /**
   * Returns the expiry timestamp (ms epoch) for a cached entry, or 0 if absent.
   * Exposed for tests.
   */
  getExpiresAt(clientId: string, username: string): number {
    return this.cache.get(this.key(clientId, username))?.expiresAtMs ?? 0;
  }

  /**
   * Promise deduplication: if a refresh is already in-flight for this org,
   * returns the existing Promise instead of starting a second token exchange.
   *
   * @param factory  Called only when no refresh is in-flight. Must resolve with
   *                 the new token or reject on failure.
   */
  withExclusiveRefresh(
    clientId: string,
    username: string,
    factory: () => Promise<SalesforceToken>,
  ): Promise<SalesforceToken> {
    const cacheKey = this.key(clientId, username);
    const existing = this.pendingRefreshes.get(cacheKey);
    if (existing !== undefined) return existing;

    const pending = factory().finally(() => {
      this.pendingRefreshes.delete(cacheKey);
    });
    this.pendingRefreshes.set(cacheKey, pending);
    return pending;
  }

  /** `true` when a refresh is currently in-flight for this org (for tests). */
  hasPendingRefresh(clientId: string, username: string): boolean {
    return this.pendingRefreshes.has(this.key(clientId, username));
  }
}
