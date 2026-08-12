/**
 * HTTP error class hierarchy.
 *
 * All application errors extend `AppError`, which carries:
 *  - `statusCode`    — HTTP status code for the response
 *  - `code`          — machine-readable error code string
 *  - `isOperational` — true for expected errors (client mistakes, not-found, etc.)
 *                      false for unexpected infrastructure failures
 *
 * Usage:
 *   throw new NotFoundError('Pipeline abc123 not found');
 *   throw new BadRequestError('Invalid threshold value', 'INVALID_THRESHOLD');
 */

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly code: string;

  constructor(
    message: string,
    statusCode: number,
    code: string,
    isOperational = true,
  ) {
    super(message);
    this.name = this.constructor.name;
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    this.code = code;
    // Capture the stack trace pointing to the actual throw site, not this constructor.
    Error.captureStackTrace(this, this.constructor);
  }
}

/** 400 Bad Request — invalid input, missing required fields, schema validation failure. */
export class BadRequestError extends AppError {
  public readonly details?: unknown;

  constructor(message = 'Bad Request', code = 'BAD_REQUEST', details?: unknown) {
    super(message, 400, code);
    if (details !== undefined) {
      this.details = details;
    }
  }
}

/** 401 Unauthorized — missing or invalid authentication credentials. */
export class UnauthorizedError extends AppError {
  constructor(message = 'Unauthorized', code = 'UNAUTHORIZED') {
    super(message, 401, code);
  }
}

/** 403 Forbidden — authenticated but lacks the required permission. */
export class ForbiddenError extends AppError {
  constructor(message = 'Forbidden', code = 'FORBIDDEN') {
    super(message, 403, code);
  }
}

/** 404 Not Found — the requested resource does not exist. */
export class NotFoundError extends AppError {
  constructor(message = 'Not Found', code = 'NOT_FOUND') {
    super(message, 404, code);
  }
}

/** 409 Conflict — resource state conflict (e.g., unique constraint violation). */
export class ConflictError extends AppError {
  constructor(message = 'Conflict', code = 'CONFLICT') {
    super(message, 409, code);
  }
}

/** 429 Too Many Requests — rate limit exceeded. Optionally includes retryAfter (seconds). */
export class RateLimitError extends AppError {
  public readonly retryAfter?: number;

  constructor(message = 'Too Many Requests', code = 'RATE_LIMIT_EXCEEDED', retryAfter?: number) {
    super(message, 429, code);
    if (retryAfter !== undefined) {
      this.retryAfter = retryAfter;
    }
  }
}

/** 500 Internal Server Error — unexpected infrastructure or programming error. */
export class InternalServerError extends AppError {
  constructor(message = 'Internal Server Error', code = 'INTERNAL_SERVER_ERROR') {
    // isOperational = false — this should never happen under normal operation.
    super(message, 500, code, false);
  }
}

/** Type guard: returns true if the given value is an AppError instance. */
export function isAppError(value: unknown): value is AppError {
  return value instanceof AppError;
}
