/**
 * AJV-based Express validation middleware factory.
 *
 * Security: `additionalProperties` defaults to `false` to prevent mass-assignment.
 * Schema: JSON Schema draft-07 (AJV 8 supports draft-07, draft-2019-09, draft-2020-12).
 * Coercion: query/params are strings by default — `coerceTypes: true` converts them.
 *
 * Usage:
 *   router.post('/pipelines',
 *     validate(createPipelineSchema, 'body'),
 *     createPipelineHandler,
 *   );
 */

import Ajv, { type JSONSchemaType } from 'ajv';
import addFormats from 'ajv-formats';
import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { BadRequestError } from '../errors/http-errors.js';
import { formatValidationErrors } from './error-formatter.js';

// ─── AJV instance ─────────────────────────────────────────────────────────────

/**
 * Shared AJV instance with:
 *  - allErrors: collect all errors rather than stopping at the first
 *  - useDefaults: populate missing optional fields with their schema defaults
 *  - coerceTypes: convert query/param strings to their declared types
 *  - removeAdditional: strip unknown properties (enforcement of additionalProperties:false)
 */
const ajv = new Ajv({
  allErrors: true,
  useDefaults: true,
  coerceTypes: true,
  removeAdditional: true,
});
addFormats(ajv);

// ─── Types ────────────────────────────────────────────────────────────────────

/** The request property to validate. */
export type ValidationTarget = 'body' | 'query' | 'params';

/**
 * Minimal type for a JSON Schema object acceptable to AJV.
 * We avoid `JSONSchemaType<T>` here to keep the public API untyped-generic —
 * callers provide plain object literals that JSON Schema tooling can validate separately.
 */
export interface AjvSchema {
  type: 'object';
  properties: Record<string, unknown>;
  required?: string[];
  additionalProperties?: boolean;
  [key: string]: unknown;
}

// ─── Middleware factory ───────────────────────────────────────────────────────

/**
 * Returns an Express middleware that validates `req[target]` against `schema`.
 *
 * - `additionalProperties` defaults to `false` if not specified in the schema.
 * - Returns 400 with field-level error details on validation failure.
 * - Passes the error to `next()` rather than sending the response directly,
 *   so the shared `errorMiddleware` handles the formatting consistently.
 *
 * @param schema   JSON Schema (type: 'object') describing the expected shape.
 * @param target   Which part of the request to validate ('body' | 'query' | 'params').
 */
export function validate(
  schema: AjvSchema,
  target: ValidationTarget = 'body',
): RequestHandler {
  // Merge schema with our security defaults.
  const compiledSchema: AjvSchema = {
    additionalProperties: false, // default — caller can override with true if needed
    ...schema,
  };

  const validateFn = ajv.compile(compiledSchema);

  return (req: Request, _res: Response, next: NextFunction): void => {
    const data: unknown = req[target];

    // Detect empty body when validation requires at least one field.
    if (target === 'body') {
      const isEmpty =
        data === undefined ||
        data === null ||
        (typeof data === 'object' && Object.keys(data as Record<string, unknown>).length === 0);

      if (isEmpty && compiledSchema.required !== undefined && compiledSchema.required.length > 0) {
        next(new BadRequestError('Request body is required', 'BODY_REQUIRED'));
        return;
      }
    }

    const valid = validateFn(data);

    if (!valid && validateFn.errors !== null && validateFn.errors !== undefined) {
      const fieldErrors = formatValidationErrors(validateFn.errors);
      next(new BadRequestError('Validation failed', 'VALIDATION_ERROR', fieldErrors));
      return;
    }

    next();
  };
}

/**
 * Convenience overload: validate the request body.
 * Equivalent to `validate(schema, 'body')`.
 */
export function validateBody(schema: AjvSchema): RequestHandler {
  return validate(schema, 'body');
}

/**
 * Convenience overload: validate query parameters.
 * Equivalent to `validate(schema, 'query')`.
 */
export function validateQuery(schema: AjvSchema): RequestHandler {
  return validate(schema, 'query');
}

/**
 * Convenience overload: validate route path parameters.
 * Equivalent to `validate(schema, 'params')`.
 */
export function validateParams(schema: AjvSchema): RequestHandler {
  return validate(schema, 'params');
}
