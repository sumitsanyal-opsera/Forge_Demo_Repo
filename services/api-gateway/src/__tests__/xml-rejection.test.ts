import { describe, it, expect, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import { createXmlRejectionMiddleware } from '../middleware/xml-rejection.js';

function makeReq(contentType?: string): Partial<Request> {
  return {
    headers: contentType ? { 'content-type': contentType } : {},
  };
}

function makeMockRes() {
  let statusCode = 200;
  let body: unknown;
  const chainable = {
    json: jest.fn((data: unknown) => { body = data; }),
  };
  return {
    status: jest.fn((code: number) => { statusCode = code; return chainable; }),
    getStatusCode: () => statusCode,
    getBody: () => body,
  };
}

describe('createXmlRejectionMiddleware', () => {
  it('returns 415 for application/xml', () => {
    const middleware = createXmlRejectionMiddleware();
    const res = makeMockRes();
    const next = jest.fn();

    middleware(makeReq('application/xml') as Request, res as unknown as Response, next);

    expect(res.status).toHaveBeenCalledWith(415);
    expect(next).not.toHaveBeenCalled();
  });

  it('returns 415 for text/xml', () => {
    const middleware = createXmlRejectionMiddleware();
    const res = makeMockRes();
    const next = jest.fn();

    middleware(makeReq('text/xml') as Request, res as unknown as Response, next);

    expect(res.status).toHaveBeenCalledWith(415);
    expect(next).not.toHaveBeenCalled();
  });

  it('returns 415 for application/xhtml+xml', () => {
    const middleware = createXmlRejectionMiddleware();
    const res = makeMockRes();
    const next = jest.fn();

    middleware(makeReq('application/xhtml+xml') as Request, res as unknown as Response, next);

    expect(res.status).toHaveBeenCalledWith(415);
    expect(next).not.toHaveBeenCalled();
  });

  it('includes UNSUPPORTED_MEDIA_TYPE error code in response body', () => {
    const middleware = createXmlRejectionMiddleware();
    const res = makeMockRes();

    middleware(makeReq('application/xml') as Request, res as unknown as Response, jest.fn());

    const body = res.getBody() as { errors: Array<{ code: string }> };
    expect(body.errors[0]?.code).toBe('UNSUPPORTED_MEDIA_TYPE');
  });

  it('does not block application/json', () => {
    const middleware = createXmlRejectionMiddleware();
    const next = jest.fn();

    middleware(makeReq('application/json') as Request, makeMockRes() as unknown as Response, next);

    expect(next).toHaveBeenCalledTimes(1);
  });

  it('does not block requests without content-type', () => {
    const middleware = createXmlRejectionMiddleware();
    const next = jest.fn();

    middleware(makeReq() as Request, makeMockRes() as unknown as Response, next);

    expect(next).toHaveBeenCalledTimes(1);
  });

  it('strips charset suffix before comparison', () => {
    const middleware = createXmlRejectionMiddleware();
    const res = makeMockRes();

    middleware(makeReq('application/xml; charset=utf-8') as Request, res as unknown as Response, jest.fn());

    expect(res.status).toHaveBeenCalledWith(415);
  });
});
