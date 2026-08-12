import { type RequestHandler } from 'express';
import { validate, generateCorrelationId } from '@opsera/shared';
import type { AjvSchema } from '@opsera/shared';

export interface InputValidatorOptions {
  schema: AjvSchema;
  target?: 'body' | 'query' | 'params';
}

/**
 * Request body input validation middleware using AJV JSON Schema validation.
 * Returns 400 with field-level errors on validation failure.
 * Stack traces are never included in the response.
 */
export function createInputValidatorMiddleware(options: InputValidatorOptions): RequestHandler {
  const { schema, target = 'body' } = options;

  const schemaValidator =
    target === 'body'
      ? validate(schema, 'body')
      : target === 'query'
        ? validate(schema, 'query')
        : validate(schema, 'params');

  return (req, res, next) => {
    const requestId = (req.headers['x-request-id'] as string | undefined) ?? generateCorrelationId();

    try {
      // Delegate to shared validate middleware, intercept validation errors
      const mockNext = (err?: unknown) => {
        if (err !== undefined && err !== null) {
          // AJV validation error — format as standard error envelope
          const validationError = err as { errors?: Array<{ field?: string; message?: string }> };
          res.status(400).json({
            data: null,
            meta: {
              timestamp: new Date().toISOString(),
              requestId,
            },
            errors: validationError.errors ?? [
              { code: 'VALIDATION_ERROR', message: 'Request validation failed' },
            ],
          });
          return;
        }
        next();
      };

      schemaValidator(req, res, mockNext);
    } catch {
      res.status(400).json({
        data: null,
        meta: { timestamp: new Date().toISOString(), requestId },
        errors: [{ code: 'VALIDATION_ERROR', message: 'Request validation failed' }],
      });
    }
  };
}
