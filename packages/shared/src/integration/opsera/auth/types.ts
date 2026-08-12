/**
 * Auth types for the Opsera integration layer.
 */

/** Selects the authentication mechanism used for Opsera API calls. */
export enum AuthMode {
  /** API key passed as an `x-api-key` request header. Default. */
  API_KEY = 'apikey',
  /** OAuth 2.0 client credentials flow — produces a Bearer access token. */
  OAUTH = 'oauth',
}

/** HTTP headers to inject into every outbound Opsera request. */
export interface AuthHeaders {
  [key: string]: string;
}

/**
 * Abstraction over an auth strategy.
 * Implementors: ApiKeyAuthProvider, OAuthAuthProvider.
 */
export interface AuthProvider {
  /** Returns the headers required to authenticate the next request. */
  getHeaders(): Promise<AuthHeaders>;
  /** Clears any cached credential state (e.g., cached OAuth token). */
  invalidateCache(): void;
}

/** Result of a credential validation call to GET /api/v1/auth/verify. */
export interface CredentialValidationResult {
  /** Whether the credentials were accepted by the Opsera API. */
  valid: boolean;
  /** Org information returned on success. */
  orgInfo?: OrgInfo;
  /** Human-readable error description (when valid is false). */
  error?: string;
  /** Machine-readable error code (when valid is false). */
  code?: string;
  /** Actionable remediation suggestion (when valid is false). */
  remediationMessage?: string;
}

/** Opsera organisation details returned by the auth verification endpoint. */
export interface OrgInfo {
  orgId: string;
  orgName: string;
  environment: string;
  plan?: string;
}

/** Internal shape of a successful OAuth token exchange response. */
export interface OAuthTokenResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
  scope?: string;
}

/** Internal shape of an OAuth error response. */
export interface OAuthErrorResponse {
  error: string;
  error_description?: string;
}
