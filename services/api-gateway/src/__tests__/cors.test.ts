import { describe, it, expect, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import { createCorsMiddleware } from '../middleware/cors.js';

const ALLOWED_ORIGIN = 'https://app.opsera.io';

function makeReq(method: string, origin?: string): Partial<Request> {
  return {
    method,
    headers: origin ? { origin } : {},
  };
}

function makeMockRes() {
  const headers: Record<string, string> = {};
  let statusCode = 200;
  return {
    setHeader: jest.fn((name: string, value: string) => { headers[name.toLowerCase()] = value; }),
    status: jest.fn((code: number) => { statusCode = code; return { end: jest.fn() }; }),
    headers,
    getStatusCode: () => statusCode,
    end: jest.fn(),
  };
}

describe('createCorsMiddleware', () => {
  it('sets ACAO header for the allowed origin', () => {
    const middleware = createCorsMiddleware(ALLOWED_ORIGIN);
    const res = makeMockRes();
    const next = jest.fn();

    middleware(makeReq('GET', ALLOWED_ORIGIN) as Request, res as unknown as Response, next);

    expect(res.headers['access-control-allow-origin']).toBe(ALLOWED_ORIGIN);
    expect(next).toHaveBeenCalled();
  });

  it('does NOT set ACAO header for disallowed origins', () => {
    const middleware = createCorsMiddleware(ALLOWED_ORIGIN);
    const res = makeMockRes();

    middleware(makeReq('GET', 'https://evil.example.com') as Request, res as unknown as Response, jest.fn());

    expect(res.headers['access-control-allow-origin']).toBeUndefined();
  });

  it('does NOT set ACAO header when no Origin header is present', () => {
    const middleware = createCorsMiddleware(ALLOWED_ORIGIN);
    const res = makeMockRes();

    middleware(makeReq('GET') as Request, res as unknown as Response, jest.fn());

    expect(res.headers['access-control-allow-origin']).toBeUndefined();
  });

  it('responds 204 to OPTIONS preflight without calling next', () => {
    const middleware = createCorsMiddleware(ALLOWED_ORIGIN);
    const res = makeMockRes();
    const next = jest.fn();

    middleware(makeReq('OPTIONS', ALLOWED_ORIGIN) as Request, res as unknown as Response, next);

    expect(res.status).toHaveBeenCalledWith(204);
    expect(next).not.toHaveBeenCalled();
  });

  it('responds 204 to OPTIONS preflight from disallowed origin (block via missing ACAO, not error)', () => {
    const middleware = createCorsMiddleware(ALLOWED_ORIGIN);
    const res = makeMockRes();
    const next = jest.fn();

    middleware(makeReq('OPTIONS', 'https://other.example.com') as Request, res as unknown as Response, next);

    expect(res.status).toHaveBeenCalledWith(204);
    expect(next).not.toHaveBeenCalled();
    expect(res.headers['access-control-allow-origin']).toBeUndefined();
  });

  it('sets Vary: Origin header when origin matches', () => {
    const middleware = createCorsMiddleware(ALLOWED_ORIGIN);
    const res = makeMockRes();

    middleware(makeReq('GET', ALLOWED_ORIGIN) as Request, res as unknown as Response, jest.fn());

    expect(res.headers['vary']).toBe('Origin');
  });

  it('calls next for non-OPTIONS requests from allowed origin', () => {
    const middleware = createCorsMiddleware(ALLOWED_ORIGIN);
    const next = jest.fn();

    middleware(makeReq('POST', ALLOWED_ORIGIN) as Request, makeMockRes() as unknown as Response, next);

    expect(next).toHaveBeenCalledTimes(1);
  });
});
