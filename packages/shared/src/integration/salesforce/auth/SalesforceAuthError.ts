/**
 * Structured error hierarchy for Salesforce OAuth authentication failures.
 *
 * Each error carries a machine-readable code and a human-readable remediation
 * hint so operators can act without reading the Salesforce documentation.
 */

export const SF_AUTH_ERROR_CODES = {
  AUTH_INVALID_GRANT: 'AUTH_INVALID_GRANT',
  AUTH_INVALID_CLIENT: 'AUTH_INVALID_CLIENT',
  AUTH_INVALID_APP_ACCESS: 'AUTH_INVALID_APP_ACCESS',
  AUTH_NETWORK_ERROR: 'AUTH_NETWORK_ERROR',
  AUTH_PRIVATE_KEY_LOAD_ERROR: 'AUTH_PRIVATE_KEY_LOAD_ERROR',
  AUTH_TOKEN_EXCHANGE_FAILED: 'AUTH_TOKEN_EXCHANGE_FAILED',
  AUTH_UNKNOWN_ERROR: 'AUTH_UNKNOWN_ERROR',
} as const;

export type SfAuthErrorCode = (typeof SF_AUTH_ERROR_CODES)[keyof typeof SF_AUTH_ERROR_CODES];

export class SalesforceAuthError extends Error {
  readonly code: SfAuthErrorCode;
  readonly remediation: string;

  constructor(message: string, code: SfAuthErrorCode, remediation: string) {
    super(message);
    this.name = 'SalesforceAuthError';
    this.code = code;
    this.remediation = remediation;
    // Restore prototype chain (required for instanceof checks in compiled JS)
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * Maps a Salesforce OAuth error code to a structured SalesforceAuthError.
 * Never includes the raw private key or access token in the error message.
 */
export function mapSalesforceOAuthError(sfErrorCode: string, description: string): SalesforceAuthError {
  switch (sfErrorCode) {
    case 'invalid_grant':
      return new SalesforceAuthError(
        `Salesforce JWT grant rejected: ${description}`,
        SF_AUTH_ERROR_CODES.AUTH_INVALID_GRANT,
        'Re-upload the self-signed certificate in the Connected App settings and ensure ' +
          'the Salesforce username is pre-authorized for JWT access.',
      );
    case 'invalid_client':
      return new SalesforceAuthError(
        `Salesforce client rejected: ${description}`,
        SF_AUTH_ERROR_CODES.AUTH_INVALID_CLIENT,
        'Verify the Connected App consumer key (SF_CLIENT_ID) and confirm the app is ' +
          'active in your Salesforce org.',
      );
    case 'invalid_app_access':
      return new SalesforceAuthError(
        `Salesforce app access denied: ${description}`,
        SF_AUTH_ERROR_CODES.AUTH_INVALID_APP_ACCESS,
        'Ensure the Connected App is configured for the JWT Bearer Flow and the user ' +
          "profile/permission set has been granted 'Access' to the app.",
      );
    default:
      return new SalesforceAuthError(
        `Salesforce OAuth error [${sfErrorCode}]: ${description}`,
        SF_AUTH_ERROR_CODES.AUTH_UNKNOWN_ERROR,
        'Check Salesforce org setup logs for more details on this error code.',
      );
  }
}

export function isSalesforceAuthError(err: unknown): err is SalesforceAuthError {
  return err instanceof SalesforceAuthError;
}
