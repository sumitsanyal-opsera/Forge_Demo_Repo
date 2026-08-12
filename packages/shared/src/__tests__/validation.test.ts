/**
 * Unit tests for validation middleware:
 *  - Valid payloads pass through
 *  - Invalid payloads produce 400 with field-level errors
 *  - Unknown properties are stripped (additionalProperties: false)
 *  - Query parameter type coercion
 *  - Empty body detection
 *  - Common schema helpers
 */

import { validate, validateBody, validateQuery } from '../validation/validate.js';
import { uuidSchema, emailSchema, paginationSchema, enumSchema } from '../validation/schemas.js';
import { createMockNext, createMockRequest } from '../database/test-utils.js';
import type { AjvSchema } from '../validation/validate.js';
import type { Request, Response } from 'express';

// Minimal no-op response mock
function mockRes(): Response {
  return {} as Response;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const pipelineCreateSchema: AjvSchema = {
  type: 'object',
  properties: {
    name: { type: 'string', minLength: 1, maxLength: 100 },
    orgId: { type: 'string', format: 'uuid' },
    threshold: { type: 'integer', minimum: 1 },
  },
  required: ['name', 'orgId'],
};

// ─── Successful validation ────────────────────────────────────────────────────

describe('validate middleware — success cases', () => {
  it('calls next() without arguments for a valid body', () => {
    const middleware = validate(pipelineCreateSchema, 'body');
    const req = createMockRequest({
      body: {
        name: 'My Pipeline',
        orgId: '550e8400-e29b-41d4-a716-446655440000',
        threshold: 30,
      },
    }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);

    expect(getCalledWith()).toBeUndefined();
  });

  it('strips unknown properties from the body (additionalProperties: false)', () => {
    const middleware = validate(pipelineCreateSchema, 'body');
    const req = createMockRequest({
      body: {
        name: 'Test',
        orgId: '550e8400-e29b-41d4-a716-446655440000',
        unknownField: 'should be stripped',
      },
    }) as Request;
    const { next } = createMockNext();

    middleware(req, mockRes(), next);

    // AJV with removeAdditional:true strips the unknown field in-place
    expect((req.body as Record<string, unknown>)['unknownField']).toBeUndefined();
  });

  it('coerces query string integers with validateQuery', () => {
    const middleware = validateQuery(paginationSchema as AjvSchema);
    const req = createMockRequest({
      query: { page: '2', limit: '25' } as unknown as Request['query'],
    }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);

    expect(getCalledWith()).toBeUndefined();
    // After coercion, page and limit should be numbers
    expect(typeof (req.query as Record<string, unknown>)['page']).toBe('number');
    expect((req.query as Record<string, unknown>)['page']).toBe(2);
  });
});

// ─── Validation failure ───────────────────────────────────────────────────────

describe('validate middleware — failure cases', () => {
  it('calls next(BadRequestError) for missing required fields', () => {
    const middleware = validate(pipelineCreateSchema, 'body');
    const req = createMockRequest({
      body: { name: 'My Pipeline' }, // orgId is missing
    }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);

    const err = getCalledWith() as { message: string; code: string; details: unknown[] };
    expect(err).toBeDefined();
    expect(err.message).toBe('Validation failed');
    expect(err.code).toBe('VALIDATION_ERROR');
    expect(Array.isArray(err.details)).toBe(true);
  });

  it('includes field-level details for type mismatch', () => {
    const middleware = validate(pipelineCreateSchema, 'body');
    const req = createMockRequest({
      body: {
        name: 'Test',
        orgId: '550e8400-e29b-41d4-a716-446655440000',
        threshold: 'not-a-number', // wrong type
      },
    }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);

    const err = getCalledWith() as { details: Array<{ field: string; message: string }> };
    expect(err.details).toBeDefined();
    expect(err.details.some((d) => d.field.includes('threshold'))).toBe(true);
  });

  it('produces BODY_REQUIRED error for empty body with required fields', () => {
    const middleware = validateBody(pipelineCreateSchema);
    const req = createMockRequest({ body: {} }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);

    const err = getCalledWith() as { code: string };
    expect(err.code).toBe('BODY_REQUIRED');
  });

  it('produces VALIDATION_ERROR for format violations (invalid UUID)', () => {
    const middleware = validate(pipelineCreateSchema, 'body');
    const req = createMockRequest({
      body: { name: 'Test', orgId: 'not-a-uuid' },
    }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);

    const err = getCalledWith() as { code: string; details: Array<{ field: string }> };
    expect(err.code).toBe('VALIDATION_ERROR');
    expect(err.details.some((d) => d.field.includes('orgId'))).toBe(true);
  });
});

// ─── Schema helpers ───────────────────────────────────────────────────────────

describe('enumSchema helper', () => {
  const statusValues = ['healthy', 'at_risk', 'stuck'] as const;

  it('accepts values that are in the enum', () => {
    const schema: AjvSchema = {
      type: 'object',
      properties: { status: enumSchema(statusValues) },
      required: ['status'],
    };
    const middleware = validate(schema, 'body');
    const req = createMockRequest({ body: { status: 'healthy' } }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);
    expect(getCalledWith()).toBeUndefined();
  });

  it('rejects values not in the enum', () => {
    const schema: AjvSchema = {
      type: 'object',
      properties: { status: enumSchema(statusValues) },
      required: ['status'],
    };
    const middleware = validate(schema, 'body');
    const req = createMockRequest({ body: { status: 'unknown_status' } }) as Request;
    const { next, getCalledWith } = createMockNext();

    middleware(req, mockRes(), next);
    expect(getCalledWith()).toBeDefined();
  });
});

describe('uuidSchema', () => {
  it('is a string schema with format uuid', () => {
    expect(uuidSchema.type).toBe('string');
    expect(uuidSchema.format).toBe('uuid');
  });
});

describe('emailSchema', () => {
  it('is a string schema with format email and maxLength', () => {
    expect(emailSchema.type).toBe('string');
    expect(emailSchema.format).toBe('email');
    expect(emailSchema.maxLength).toBe(255);
  });
});
