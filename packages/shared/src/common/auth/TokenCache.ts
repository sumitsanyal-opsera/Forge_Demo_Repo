/**
 * Generic in-memory token cache with proactive refresh support.
 *
 * The cache considers a token "valid" only if it won't expire within
 * `proactiveRefreshBufferMs` (default 60 s), preventing race conditions where
 * a token is returned but expires before the outbound request completes.
 *
 * Used by OAuthAuthProvider and any future OAuth-based integrations.
 */

export class TokenCache {
  private cachedToken: string | null = null;
  private expiresAtMs = 0;
  private readonly proactiveRefreshBufferMs: number;

  constructor(proactiveRefreshBufferMs = 60_000) {
    this.proactiveRefreshBufferMs = proactiveRefreshBufferMs;
  }

  /**
   * Returns the cached token if it is still valid (with buffer), or `null`
   * if missing or about to expire.
   */
  getValid(): string | null {
    if (
      this.cachedToken !== null &&
      Date.now() < this.expiresAtMs - this.proactiveRefreshBufferMs
    ) {
      return this.cachedToken;
    }
    return null;
  }

  /**
   * Stores a new token.
   * @param token           The raw access token string.
   * @param expiresInSeconds TTL in seconds returned by the auth server.
   */
  set(token: string, expiresInSeconds: number): void {
    this.cachedToken = token;
    this.expiresAtMs = Date.now() + expiresInSeconds * 1_000;
  }

  /** Clears the cached token, forcing a fresh exchange on next `getValid()`. */
  invalidate(): void {
    this.cachedToken = null;
    this.expiresAtMs = 0;
  }

  /** `true` when the token is absent or within the proactive refresh window. */
  isExpiringSoon(): boolean {
    return (
      this.cachedToken === null ||
      Date.now() >= this.expiresAtMs - this.proactiveRefreshBufferMs
    );
  }

  /** Expiry timestamp as a Unix epoch in milliseconds (0 if not set). */
  get expiresAt(): number {
    return this.expiresAtMs;
  }
}
