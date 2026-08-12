/**
 * OAuth 2.0 client credentials provider for Opsera API authentication.
 *
 * Performs a token exchange POST to OPSERA_AUTH_URL, caches the access token
 * with its TTL, and proactively refreshes 60 seconds before expiry to prevent
 * mid-request token expiration.
 *
 * Security: client_id and client_secret are never logged. The access_token
 * is treated as a secret — avoid logging the AuthHeaders map at INFO level.
 */

import { TokenCache } from '../../../common/auth/TokenCache.js';
import type {
  AuthHeaders,
  AuthProvider,
  OAuthErrorResponse,
  OAuthTokenResponse,
} from './types.js';

/** Proactive refresh buffer: refresh token 60 s before it expires. */
const REFRESH_BUFFER_MS = 60_000;

export class OAuthAuthProvider implements AuthProvider {
  private readonly tokenCache: TokenCache;
  private readonly authUrl: string;
  private readonly clientId: string;
  private readonly clientSecret: string;

  constructor(clientId: string, clientSecret: string, authUrl: string) {
    if (!clientId || !clientSecret) {
      throw new Error(
        'OPSERA_CLIENT_ID and OPSERA_CLIENT_SECRET are required for OAuth mode.',
      );
    }
    if (!authUrl) {
      throw new Error('OPSERA_AUTH_URL is required for OAuth mode.');
    }
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.authUrl = authUrl;
    this.tokenCache = new TokenCache(REFRESH_BUFFER_MS);
  }

  async getHeaders(): Promise<AuthHeaders> {
    const token = await this.getAccessToken();
    return { Authorization: `Bearer ${token}` };
  }

  /** Clears the cached token, forcing a fresh exchange on the next call. */
  invalidateCache(): void {
    this.tokenCache.invalidate();
  }

  /** Returns the token expiry time (ms epoch) for inspection in tests. */
  get tokenExpiresAt(): number {
    return this.tokenCache.expiresAt;
  }

  private async getAccessToken(): Promise<string> {
    const cached = this.tokenCache.getValid();
    if (cached !== null) return cached;
    return this.exchangeTokens();
  }

  private async exchangeTokens(): Promise<string> {
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: this.clientId,
      client_secret: this.clientSecret,
    });

    let response: Response;
    try {
      response = await fetch(this.authUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      });
    } catch (networkError) {
      throw new Error(
        `Network error during Opsera OAuth token exchange: ${String(networkError)}`,
      );
    }

    const rawBody: unknown = await response.json().catch(() => null);

    if (!response.ok) {
      const errBody = rawBody as Partial<OAuthErrorResponse> | null;
      const errorCode = errBody?.error ?? 'unknown_error';
      const errorDesc = errBody?.error_description ?? response.statusText;
      throw new Error(
        `Opsera OAuth token exchange failed [${response.status}] ${errorCode}: ${errorDesc}`,
      );
    }

    const tokenData = rawBody as Partial<OAuthTokenResponse>;
    if (typeof tokenData?.access_token !== 'string' || tokenData.access_token === '') {
      throw new Error(
        'Opsera OAuth token exchange returned an unexpected response format — ' +
          'access_token is missing or empty.',
      );
    }

    const expiresIn = typeof tokenData.expires_in === 'number' ? tokenData.expires_in : 3_600;
    this.tokenCache.set(tokenData.access_token, expiresIn);
    return tokenData.access_token;
  }
}
