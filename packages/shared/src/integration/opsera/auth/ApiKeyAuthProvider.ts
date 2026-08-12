/**
 * Authentication provider that injects an Opsera API key via the `x-api-key`
 * HTTP header.
 *
 * The key is read from the OPSERA_API_KEY environment variable at construction
 * time and transmitted verbatim — special characters (=, /, +) are NOT
 * percent-encoded in headers per RFC 7230.
 *
 * Security: the key value is never logged — callers must ensure the AuthHeaders
 * map is not logged at a level visible in production.
 */

import type { AuthHeaders, AuthProvider } from './types.js';

export class ApiKeyAuthProvider implements AuthProvider {
  private readonly apiKey: string;

  constructor(apiKey: string) {
    if (!apiKey || apiKey.trim() === '') {
      throw new Error(
        'OPSERA_API_KEY is required for API key auth mode. ' +
          'Set it in the environment configuration.',
      );
    }
    this.apiKey = apiKey;
  }

  async getHeaders(): Promise<AuthHeaders> {
    return { 'x-api-key': this.apiKey };
  }

  /** No-op: API key auth has no cached state to invalidate. */
  invalidateCache(): void {
    // Nothing to invalidate for a static API key.
  }
}
