/**
 * Express error-handling middleware.
 *
 * Security requirement (OWASP A10): stack traces MUST NOT appear in
 * production error responses. Only the code and a safe message are returned.
 *
 * Response envelope format:
 * {
 *   "success": false,
 *   "error": {
 *     "code": "NOT_FOUND",
 *     "message": "Pipeline abc123 not found",
 *     "details": [...]   // optional, only for validation errors
 *   }
 * }
 */

import type { ErrorRequestHandler, NextFunction, Request, Response } from 'express';
import { AppError, BadRequestError, InternalServerError, isAppError } from './http-errors.js';
import { createLogger } from '../logging/logger.js';

const logger = createLogger('error-middleware');

interface ErrorResponseBody {
  success: false;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

function buildErrorResponse(err: AppError): ErrorResponseBody {
  const body: ErrorResponseBody = {
    success: false,
    error: {
      code: err.code,
      message: err.message,
    },
  };

  // Include validation field details when present.
  if (err instanceof BadRequestError && err.details !== undefined) {
    body.error.details = err.details;
  }

  return body;
}

/**
 * Four-argument Express error handler. Must be registered AFTER all routes:
 *   app.use(errorMiddleware);
 */
export const errorMiddleware: ErrorRequestHandler = (
  err: unknown,
  req: Request,
  res: Response,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _next: NextFunction,
): void => {
  try {
    if (isAppError(err)) {
      if (err.statusCode >= 500) {
        logger.error('Application error', err, { path: req.path, method: req.method });
      } else {
        logger.warn(`Client error [${err.statusCode}]`, {
          code: err.code,
          message: err.message,
          path: req.path,
          method: req.method,
        });
      }

      res.status(err.statusCode).json(buildErrorResponse(err));
      return;
    }

    // Non-AppError (programming error, unexpected throw, etc.)
    const wrappedError =
      err instanceof Error
        ? err
        : new Error(typeof err === 'string' ? err : 'Unknown error');

    logger.error('Unexpected error', wrappedError, {
      path: req.path,
      method: req.method,
    });

    const isProduction = process.env['NODE_ENV'] === 'production';
    const safeError = new InternalServerError(
      isProduction ? 'Internal Server Error' : wrappedError.message,
    );

    res.status(500).json(buildErrorResponse(safeError));
  } catch (middlewareError) {
    // The error middleware itself crashed — absolute fallback.
    logger.error(
      'Error middleware failed',
      middlewareError instanceof Error ? middlewareError : new Error(String(middlewareError)),
    );
    try {
      res.status(500).json({
        success: false,
        error: { code: 'INTERNAL_SERVER_ERROR', message: 'Internal Server Error' },
      });
    } catch {
      // Response was already sent — nothing we can do.
    }
  }
};
