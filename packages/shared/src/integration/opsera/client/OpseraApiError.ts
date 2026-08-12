/**
 * Structured error types for the Opsera API client.
 *
 * All errors produced by OpseraApiClient are instances of `OpseraApiError`
 * or its subclass `OpseraAuthError`, enabling callers to distinguish Opsera
 * errors from generic JavaScript errors with a simple `instanceof` check.
 */

/** Machine-readable error codes produced by the Opsera client. */
export type OpseraErrorCode =
  | 'AUTH_INVALID_KEY'
  | 'AUTH_INVALID_CREDENTIALS'
  | 'AUTH_TOKEN_EXCHANGE_FAILED'
  | 'AUTH_EXPIRED'
  | 'AUTH_FORBIDDEN'
  | 'PIPELINE_NOT_FOUND'
  | 'PIPELINE_ALREADY_RUNNING'
  | 'RATE_LIMIT_EXCEEDED'
  | 'INVALID_REQUEST'
  | 'NETWORK_ERROR'
  | 'UNEXPECTED_RESPONSE'
  | 'MAX_RETRIES_EXCEEDED'
  | 'SERVER_ERROR'
  // Allow extension for future Opsera-specific codes.
  | (string & { readonly __brand: unique symbol });

/** HTTP request context attached to every Opsera error for debugging. */
export interface RequestContext {
  method: string;
  path: string;
  correlationId?: string;
}

/**
 * Base error class for all Opsera API failures.
 *
 * Properties:
 *  - `code`           Machine-readable error code (see `OpseraErrorCode`).
 *  - `statusCode`     HTTP status code from the Opsera response (0 for network errors).
 *  - `isRetryable`    Whether the operation can be safely retried.
 *  - `requestContext` Method, path, and correlation ID of the failed request.
 */
export class OpseraApiError extends Error {
  public readonly code: string;
  public readonly statusCode: number;
  public readonly isRetryable: boolean;
  public readonly requestContext?: RequestContext;

  constructor(
    message: string,
    code: string,
    statusCode: number,
    isRetryable: boolean,
    requestContext?: RequestContext,
  ) {
    super(message);
    this.name = 'OpseraApiError';
    this.code = code;
    this.statusCode = statusCode;
    this.isRetryable = isRetryable;
    this.requestContext = requestContext;
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Authentication-specific Opsera error.
 * Carries a `remediationMessage` to guide operators on how to resolve the issue.
 */
export class OpseraAuthError extends OpseraApiError {
  public readonly remediationMessage: string;

  constructor(
    message: string,
    code: string,
    statusCode = 401,
    remediationMessage = 'Verify your Opsera API credentials in the environment configuration.',
  ) {
    super(message, code, statusCode, false);
    this.name = 'OpseraAuthError';
    this.remediationMessage = remediationMessage;
  }
}

/** Type guard: returns `true` if the value is an OpseraApiError. */
export function isOpseraApiError(value: unknown): value is OpseraApiError {
  return value instanceof OpseraApiError;
}

/** Type guard: returns `true` if the value is an OpseraAuthError. */
export function isOpseraAuthError(value: unknown): value is OpseraAuthError {
  return value instanceof OpseraAuthError;
}
