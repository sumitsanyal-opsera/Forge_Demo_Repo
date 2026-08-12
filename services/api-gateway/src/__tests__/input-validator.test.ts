import { describe, it, expect, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import { createInputValidatorMiddleware } from '../middleware/input-validator.js';
import type { AjvSchema } from '@opsera/shared';

const testSchema: AjvSchema = {
  type: 'object',
  required: ['name', 'orgId'],
  properties: {
    name: { type: 'string', minLength: 1, maxLength: 100 },
    orgId: { type: 'string', minLength: 15, maxLength: 18 },
  },
  additionalProperties: false,
};

function makeReq(body: unknown): Partial<Request> {
  return {
    body,
    headers: {},
    method: 'POST',
    path: '/api/v1/test',
  };
}

function makeMockRes() {
  let statusCode = 200;
  let body: unknown;
  const chainable = { json: jest.fn((data: unknown) => { body = data; }) };
  return {
    status: jest.fn((code: number) => { statusCode = code; return chainable; }),
    getStatusCode: () => statusCode,
    getBody: () => body,
    // AJV middleware also calls these:
    locals: {},
  };
}

describe('createInputValidatorMiddleware', () => {
  it('calls next for valid request body', () => {
    const middleware = createInputValidatorMiddleware({ schema: testSchema });
    const next = jest.fn();

    middleware(
      makeReq({ name: 'My Pipeline', orgId: '001000000000001AAA' }) as Request,
      makeMockRes() as unknown as Response,
      next,
    );

    expect(next).toHaveBeenCalledTimes(1);
    expect(next).toHaveBeenCalledWith();
  });

  it('returns 400 when required field is missing', () => {
    const middleware = createInputValidatorMiddleware({ schema: testSchema });
    const res = makeMockRes();
    const next = jest.fn();

    middleware(
      makeReq({ name: 'My Pipeline' }) as Request, // missing orgId
      res as unknown as Response,
      next,
    );

    expect(res.status).toHaveBeenCalledWith(400);
    expect(next).not.toHaveBeenCalled();
  });

  it('returns 400 for additional properties', () => {
    const middleware = createInputValidatorMiddleware({ schema: testSchema });
    const res = makeMockRes();

    middleware(
      makeReq({ name: 'My Pipeline', orgId: '001000000000001AAA', hack: true }) as Request,
      res as unknown as Response,
      jest.fn(),
    );

    expect(res.status).toHaveBeenCalledWith(400);
  });

  it('response body includes structured error envelope', () => {
    const middleware = createInputValidatorMiddleware({ schema: testSchema });
    const res = makeMockRes();

    middleware(
      makeReq({ orgId: '001000000000001AAA' }) as Request, // missing name
      res as unknown as Response,
      jest.fn(),
    );

    const body = res.getBody() as { data: null; meta: { requestId: string }; errors: unknown[] };
    expect(body.data).toBeNull();
    expect(typeof body.meta.requestId).toBe('string');
    expect(Array.isArray(body.errors)).toBe(true);
    expect(body.errors.length).toBeGreaterThan(0);
  });

  it('does not include stack traces in error response', () => {
    const middleware = createInputValidatorMiddleware({ schema: testSchema });
    const res = makeMockRes();

    middleware(makeReq({}) as Request, res as unknown as Response, jest.fn());

    const body = JSON.stringify(res.getBody());
    expect(body).not.toContain('at Object');
    expect(body).not.toContain('stack');
  });

  it('returns 400 for type mismatch', () => {
    const middleware = createInputValidatorMiddleware({ schema: testSchema });
    const res = makeMockRes();

    middleware(
      makeReq({ name: 123, orgId: '001000000000001AAA' }) as Request,
      res as unknown as Response,
      jest.fn(),
    );

    expect(res.status).toHaveBeenCalledWith(400);
  });
});
