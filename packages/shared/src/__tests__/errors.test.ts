/**
 * Unit tests for error handling infrastructure:
 *  - AppError class hierarchy instantiation and properties
 *  - Error middleware response format
 *  - Stack trace suppression in production
 *  - Prisma error mapping (P2002, P2025, P2003)
 */

import { Prisma } from '@prisma/client';
import {
  AppError,
  BadRequestError,
  ConflictError,
  ForbiddenError,
  InternalServerError,
  NotFoundError,
  RateLimitError,
  UnauthorizedError,
  isAppError,
} from '../errors/http-errors.js';
import { errorMiddleware } from '../errors/error-middleware.js';
import { mapPrismaError } from '../errors/prisma-errors.js';
import {
  createMockNext,
  createMockRequest,
  createMockResponse,
} from '../database/test-utils.js';
import { captureLogOutput } from '../logging/test-capture.js';

// ─── AppError hierarchy ───────────────────────────────────────────────────────

describe('HTTP error classes', () => {
  it('BadRequestError has statusCode 400', () => {
    const err = new BadRequestError('Invalid input');
    expect(err.statusCode).toBe(400);
    expect(err.code).toBe('BAD_REQUEST');
    expect(err.message).toBe('Invalid input');
    expect(err.isOperational).toBe(true);
    expect(err instanceof AppError).toBe(true);
    expect(err instanceof Error).toBe(true);
  });

  it('UnauthorizedError has statusCode 401', () => {
    const err = new UnauthorizedError();
    expect(err.statusCode).toBe(401);
    expect(err.code).toBe('UNAUTHORIZED');
  });

  it('ForbiddenError has statusCode 403', () => {
    const err = new ForbiddenError();
    expect(err.statusCode).toBe(403);
    expect(err.code).toBe('FORBIDDEN');
  });

  it('NotFoundError has statusCode 404', () => {
    const err = new NotFoundError('Pipeline not found');
    expect(err.statusCode).toBe(404);
    expect(err.message).toBe('Pipeline not found');
  });

  it('ConflictError has statusCode 409', () => {
    const err = new ConflictError();
    expect(err.statusCode).toBe(409);
    expect(err.code).toBe('CONFLICT');
  });

  it('RateLimitError has statusCode 429', () => {
    const err = new RateLimitError('Too many requests', 'RATE_LIMIT_EXCEEDED', 30);
    expect(err.statusCode).toBe(429);
    expect(err.retryAfter).toBe(30);
  });

  it('InternalServerError has statusCode 500 and isOperational=false', () => {
    const err = new InternalServerError();
    expect(err.statusCode).toBe(500);
    expect(err.isOperational).toBe(false);
  });

  it('BadRequestError stores validation details', () => {
    const details = [{ field: 'email', message: 'Invalid format' }];
    const err = new BadRequestError('Validation failed', 'VALIDATION_ERROR', details);
    expect(err.details).toEqual(details);
  });

  it('isAppError type guard correctly identifies AppError instances', () => {
    expect(isAppError(new BadRequestError())).toBe(true);
    expect(isAppError(new Error('plain error'))).toBe(false);
    expect(isAppError('string')).toBe(false);
    expect(isAppError(null)).toBe(false);
  });

  it('error name matches class constructor name', () => {
    expect(new BadRequestError().name).toBe('BadRequestError');
    expect(new NotFoundError().name).toBe('NotFoundError');
    expect(new InternalServerError().name).toBe('InternalServerError');
  });
});

// ─── Error middleware ─────────────────────────────────────────────────────────

describe('errorMiddleware', () => {
  const originalNodeEnv = process.env['NODE_ENV'];

  afterEach(() => {
    process.env['NODE_ENV'] = originalNodeEnv;
  });

  it('returns JSON envelope with correct status for AppError', async () => {
    const err = new NotFoundError('Pipeline abc123 not found');
    const req = createMockRequest();
    const { res, getStatusCode, getJsonBody } = createMockResponse();
    const { next } = createMockNext();

    await captureLogOutput(() => {
      errorMiddleware(err, req as never, res as never, next);
    });

    expect(getStatusCode()).toBe(404);
    const body = getJsonBody() as { success: boolean; error: { code: string; message: string } };
    expect(body.success).toBe(false);
    expect(body.error.code).toBe('NOT_FOUND');
    expect(body.error.message).toBe('Pipeline abc123 not found');
  });

  it('returns 400 with field-level details for validation errors', async () => {
    const details = [{ field: 'threshold', message: 'Must be a positive number' }];
    const err = new BadRequestError('Validation failed', 'VALIDATION_ERROR', details);
    const req = createMockRequest();
    const { res, getStatusCode, getJsonBody } = createMockResponse();
    const { next } = createMockNext();

    await captureLogOutput(() => {
      errorMiddleware(err, req as never, res as never, next);
    });

    expect(getStatusCode()).toBe(400);
    const body = getJsonBody() as { error: { details: unknown[] } };
    expect(body.error.details).toEqual(details);
  });

  it('returns 500 for non-AppError with safe message in production', async () => {
    process.env['NODE_ENV'] = 'production';
    const err = new Error('Database connection string leaked');
    const req = createMockRequest();
    const { res, getStatusCode, getJsonBody } = createMockResponse();
    const { next } = createMockNext();

    await captureLogOutput(() => {
      errorMiddleware(err, req as never, res as never, next);
    });

    expect(getStatusCode()).toBe(500);
    const body = getJsonBody() as { error: { message: string } };
    // In production, the original message must NOT be exposed.
    expect(body.error.message).toBe('Internal Server Error');
    expect(body.error.message).not.toContain('Database connection string leaked');
  });

  it('returns 500 with actual message in development', async () => {
    process.env['NODE_ENV'] = 'development';
    const err = new Error('Detailed error message');
    const req = createMockRequest();
    const { res, getStatusCode, getJsonBody } = createMockResponse();
    const { next } = createMockNext();

    await captureLogOutput(() => {
      errorMiddleware(err, req as never, res as never, next);
    });

    expect(getStatusCode()).toBe(500);
    const body = getJsonBody() as { error: { message: string } };
    expect(body.error.message).toBe('Detailed error message');
  });

  it('handles non-Error thrown values gracefully', async () => {
    const req = createMockRequest();
    const { res, getStatusCode } = createMockResponse();
    const { next } = createMockNext();

    // Throw a plain string (not an Error object)
    await captureLogOutput(() => {
      errorMiddleware('a plain string error', req as never, res as never, next);
    });

    expect(getStatusCode()).toBe(500);
  });

  it('never includes stack traces in production responses', async () => {
    process.env['NODE_ENV'] = 'production';
    const err = new InternalServerError('DB crash');
    const req = createMockRequest();
    const { res, getJsonBody } = createMockResponse();
    const { next } = createMockNext();

    await captureLogOutput(() => {
      errorMiddleware(err, req as never, res as never, next);
    });

    const body = JSON.stringify(getJsonBody());
    expect(body).not.toContain('at '); // no stack trace lines
    expect(body).not.toContain('.test.ts');
  });
});

// ─── Prisma error mapping ─────────────────────────────────────────────────────

describe('mapPrismaError', () => {
  function makePrismaError(code: string, meta?: Record<string, unknown>): Prisma.PrismaClientKnownRequestError {
    // Construct a minimal PrismaClientKnownRequestError for testing purposes.
    const err = new Prisma.PrismaClientKnownRequestError('Prisma error', {
      code,
      clientVersion: '5.0.0',
      meta,
    });
    return err;
  }

  it('maps P2002 (unique constraint) to ConflictError', () => {
    const err = makePrismaError('P2002', { target: ['email'] });
    const mapped = mapPrismaError(err);
    expect(mapped instanceof ConflictError).toBe(true);
    expect((mapped as ConflictError).statusCode).toBe(409);
  });

  it('maps P2025 (record not found) to NotFoundError', () => {
    const err = makePrismaError('P2025', { cause: 'No record found' });
    const mapped = mapPrismaError(err);
    expect(mapped instanceof NotFoundError).toBe(true);
    expect((mapped as NotFoundError).statusCode).toBe(404);
  });

  it('maps P2003 (foreign key constraint) to BadRequestError', () => {
    const err = makePrismaError('P2003', { field_name: 'pipeline_id' });
    const mapped = mapPrismaError(err);
    expect(mapped instanceof BadRequestError).toBe(true);
    expect((mapped as BadRequestError).statusCode).toBe(400);
  });

  it('maps unknown Prisma codes to InternalServerError', () => {
    const err = makePrismaError('P9999');
    const mapped = mapPrismaError(err);
    expect(mapped instanceof InternalServerError).toBe(true);
  });

  it('passes through AppError instances unchanged', () => {
    const original = new ForbiddenError('Already an AppError');
    const mapped = mapPrismaError(original);
    expect(mapped).toBe(original);
  });

  it('wraps plain Error in InternalServerError', () => {
    const plain = new Error('generic database issue');
    const mapped = mapPrismaError(plain);
    expect(mapped instanceof InternalServerError).toBe(true);
  });
});
