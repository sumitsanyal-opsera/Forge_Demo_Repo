/**
 * Structured error class for Salesforce REST API failures.
 *
 * Salesforce returns errors as a JSON array:
 *   [{ errorCode, message, fields }]
 *
 * SalesforceApiError captures the primary error (first element) and preserves
 * the full array for callers that need multi-error context.
 */

import type { SalesforceErrorBody } from './types.js';

/** Machine-readable Salesforce REST API error codes relevant to retry logic. */
export const SF_API_ERROR_CODES = {
  INVALID_SESSION_ID: 'INVALID_SESSION_ID',
  REQUEST_LIMIT_EXCEEDED: 'REQUEST_LIMIT_EXCEEDED',
  QUERY_TIMEOUT: 'QUERY_TIMEOUT',
  SERVER_UNAVAILABLE: 'SERVER_UNAVAILABLE',
  UNKNOWN_EXCEPTION: 'UNKNOWN_EXCEPTION',
} as const;

/** Error codes that indicate a transient rate-limit condition (retryable). */
export const RATE_LIMIT_ERROR_CODES = new Set([
  SF_API_ERROR_CODES.REQUEST_LIMIT_EXCEEDED,
  'CONCURRENT_REQUESTS_LIMIT_EXCEEDED',
  'TXN_SECURITY_METERING_ERROR',
]);

/** Error codes that indicate an expired/invalid session (triggers token refresh). */
export const SESSION_EXPIRED_ERROR_CODES = new Set([
  SF_API_ERROR_CODES.INVALID_SESSION_ID,
  'INVALID_AUTH_HEADER',
]);

export class SalesforceApiError extends Error {
  /** Salesforce-specific error code from the first error element. */
  readonly errorCode: string;
  /** Fields involved in the error (e.g., for field validation failures). */
  readonly fields: readonly string[];
  /** HTTP status code from the response. */
  readonly statusCode: number;
  /** Whether the request can be safely retried. */
  readonly isRetryable: boolean;
  /** All error objects from the Salesforce response body. */
  readonly allErrors: readonly SalesforceErrorBody[];
  /** HTTP method and URL path of the request that produced this error. */
  readonly requestContext?: { method: string; urlPath: string; correlationId: string };

  constructor(
    message: string,
    errorCode: string,
    statusCode: number,
    isRetryable: boolean,
    allErrors: SalesforceErrorBody[],
    requestContext?: { method: string; urlPath: string; correlationId: string },
  ) {
    super(message);
    this.name = 'SalesforceApiError';
    this.errorCode = errorCode;
    this.fields = allErrors[0]?.fields ?? [];
    this.statusCode = statusCode;
    this.isRetryable = isRetryable;
    this.allErrors = allErrors;
    this.requestContext = requestContext;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * Parses a Salesforce REST API error response body (array format) into a
 * SalesforceApiError. Falls back gracefully for non-JSON or empty responses.
 */
export function parseSalesforceApiError(
  rawBody: unknown,
  statusCode: number,
  requestContext: { method: string; urlPath: string; correlationId: string },
): SalesforceApiError {
  const errors = normaliseSalesforceErrors(rawBody);
  const primary = errors[0] ?? {
    errorCode: 'UNKNOWN_ERROR',
    message: `Salesforce API error [HTTP ${statusCode}]`,
    fields: [],
  };

  const isRateLimit =
    statusCode === 429 || RATE_LIMIT_ERROR_CODES.has(primary.errorCode);
  const isSessionExpired =
    statusCode === 401 && SESSION_EXPIRED_ERROR_CODES.has(primary.errorCode);
  const isTransient =
    statusCode >= 500 || isRateLimit;

  return new SalesforceApiError(
    primary.message,
    primary.errorCode,
    statusCode,
    isTransient && !isSessionExpired,
    errors,
    requestContext,
  );
}

/**
 * Normalises the raw Salesforce error body into a consistent array.
 * Handles: array of error objects, single object, and non-JSON strings.
 */
function normaliseSalesforceErrors(raw: unknown): SalesforceErrorBody[] {
  if (Array.isArray(raw)) {
    return raw.filter(isErrorBody);
  }
  if (isErrorBody(raw)) {
    return [raw];
  }
  return [];
}

function isErrorBody(v: unknown): v is SalesforceErrorBody {
  return (
    typeof v === 'object' &&
    v !== null &&
    typeof (v as Record<string, unknown>)['errorCode'] === 'string' &&
    typeof (v as Record<string, unknown>)['message'] === 'string'
  );
}

/** Type guard. */
export function isSalesforceApiError(err: unknown): err is SalesforceApiError {
  return err instanceof SalesforceApiError;
}
