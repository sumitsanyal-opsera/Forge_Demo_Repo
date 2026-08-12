/**
 * Opsera authentication service.
 *
 * Selects between ApiKeyAuthProvider and OAuthAuthProvider based on the
 * OPSERA_AUTH_MODE environment variable ('apikey' | 'oauth', default: 'apikey').
 * Delegates header generation and cache invalidation to the chosen provider.
 *
 * Startup credential validation uses graceful degradation: if the Opsera
 * verify endpoint is unreachable, a warning is logged and the service starts
 * anyway — validation is retried lazily on the first real API call.
 */

import { createLogger } from '../../../logging/logger.js';
import { ApiKeyAuthProvider } from './ApiKeyAuthProvider.js';
import { OAuthAuthProvider } from './OAuthAuthProvider.js';
import type {
  AuthHeaders,
  AuthMode,
  AuthProvider,
  CredentialValidationResult,
} from './types.js';

const logger = createLogger('OpseraAuthService');

export interface OpseraAuthServiceConfig {
  authMode?: string;
  apiKey?: string;
  clientId?: string;
  clientSecret?: string;
  authUrl?: string;
  /** Base URL used to call the /api/v1/auth/verify endpoint. */
  apiBaseUrl?: string;
}

export class OpseraAuthService {
  private provider: AuthProvider;
  private currentMode: string;
  private readonly apiBaseUrl: string;

  constructor(config?: OpseraAuthServiceConfig) {
    const mode =
      config?.authMode ?? process.env['OPSERA_AUTH_MODE'] ?? 'apikey';
    this.currentMode = mode;
    this.apiBaseUrl =
      config?.apiBaseUrl ??
      process.env['OPSERA_API_BASE_URL'] ??
      'https://api.opsera.io';

    this.provider = this.buildProvider(mode, config);
    logger.info('OpseraAuthService initialised', { mode });
  }

  /** Returns auth headers for the next outbound Opsera request. */
  async getHeaders(): Promise<AuthHeaders> {
    return this.provider.getHeaders();
  }

  /**
   * Validates the configured credentials against GET /api/v1/auth/verify.
   * Returns a structured result rather than throwing — callers decide whether
   * to treat a failed validation as fatal.
   */
  async validateCredentials(): Promise<CredentialValidationResult> {
    const verifyUrl = `${this.apiBaseUrl}/api/v1/auth/verify`;
    let headers: AuthHeaders;
    try {
      headers = await this.provider.getHeaders();
    } catch (err) {
      return {
        valid: false,
        error: `Failed to obtain auth headers: ${String(err)}`,
        code: 'AUTH_HEADER_ERROR',
        remediationMessage: 'Check OPSERA_API_KEY or OPSERA_CLIENT_ID/SECRET configuration.',
      };
    }

    let response: Response;
    try {
      response = await fetch(verifyUrl, { method: 'GET', headers });
    } catch (networkErr) {
      logger.warn('Opsera credential validation endpoint unreachable — will retry on first call', {
        error: String(networkErr),
      });
      return {
        valid: false,
        error: `Network error during credential validation: ${String(networkErr)}`,
        code: 'NETWORK_ERROR',
        remediationMessage:
          'The Opsera API is currently unreachable. The service will retry on the first API call.',
      };
    }

    if (response.status === 401 || response.status === 403) {
      const body = await response.json().catch(() => null) as Record<string, unknown> | null;
      return {
        valid: false,
        error: body?.['message'] as string | undefined ?? 'Invalid or expired credentials',
        code: response.status === 401 ? 'AUTH_INVALID_KEY' : 'AUTH_FORBIDDEN',
        remediationMessage:
          'Verify your Opsera API key or OAuth client credentials in the environment configuration.',
      };
    }

    if (!response.ok) {
      return {
        valid: false,
        error: `Unexpected HTTP ${response.status} from auth verify endpoint`,
        code: 'UNEXPECTED_RESPONSE',
      };
    }

    const body = await response.json().catch(() => ({})) as Record<string, unknown>;
    return {
      valid: true,
      orgInfo: {
        orgId: String(body['orgId'] ?? ''),
        orgName: String(body['orgName'] ?? ''),
        environment: String(body['environment'] ?? 'production'),
        plan: body['plan'] !== undefined ? String(body['plan']) : undefined,
      },
    };
  }

  /**
   * Switches the authentication mode at runtime.
   * Invalidates any cached OAuth token before switching to prevent stale usage.
   */
  switchAuthMode(mode: string, config?: OpseraAuthServiceConfig): void {
    this.provider.invalidateCache();
    this.currentMode = mode;
    this.provider = this.buildProvider(mode, config);
    logger.info('OpseraAuthService auth mode switched', { mode });
  }

  /** Returns the currently active auth mode string. */
  get authMode(): string {
    return this.currentMode;
  }

  private buildProvider(mode: string, config?: OpseraAuthServiceConfig): AuthProvider {
    if (mode === ('oauth' satisfies AuthMode extends 'oauth' ? 'oauth' : string)) {
      return new OAuthAuthProvider(
        config?.clientId ?? process.env['OPSERA_CLIENT_ID'] ?? '',
        config?.clientSecret ?? process.env['OPSERA_CLIENT_SECRET'] ?? '',
        config?.authUrl ?? process.env['OPSERA_AUTH_URL'] ?? '',
      );
    }

    // Default: API key mode
    return new ApiKeyAuthProvider(
      config?.apiKey ?? process.env['OPSERA_API_KEY'] ?? '',
    );
  }
}
