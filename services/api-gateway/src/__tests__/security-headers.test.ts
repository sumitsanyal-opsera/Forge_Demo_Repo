import { describe, it, expect, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import { createSecurityHeadersMiddleware } from '../middleware/security-headers.js';

function makeMockRes() {
  const headers: Record<string, string | number> = {};
  const removedHeaders: string[] = [];
  return {
    setHeader: jest.fn((name: string, value: string | number) => { headers[name.toLowerCase()] = value; }),
    removeHeader: jest.fn((name: string) => { removedHeaders.push(name.toLowerCase()); }),
    headers,
    removedHeaders,
    locals: {} as Record<string, unknown>,
  };
}

describe('createSecurityHeadersMiddleware', () => {
  it('sets Content-Security-Policy with nonce', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res = makeMockRes();
    const next = jest.fn();

    middleware({} as Request, res as unknown as Response, next);

    const csp = res.headers['content-security-policy'] as string;
    expect(csp).toBeDefined();
    expect(csp).toContain("nonce-");
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
  });

  it('sets HSTS with default max-age 31536000 and includeSubDomains', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res = makeMockRes();
    const next = jest.fn();

    middleware({} as Request, res as unknown as Response, next);

    const hsts = res.headers['strict-transport-security'] as string;
    expect(hsts).toContain('max-age=31536000');
    expect(hsts).toContain('includeSubDomains');
  });

  it('sets X-Content-Type-Options to nosniff', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res = makeMockRes();

    middleware({} as Request, res as unknown as Response, jest.fn());

    expect(res.headers['x-content-type-options']).toBe('nosniff');
  });

  it('sets X-Frame-Options to DENY', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res = makeMockRes();

    middleware({} as Request, res as unknown as Response, jest.fn());

    expect(res.headers['x-frame-options']).toBe('DENY');
  });

  it('sets Referrer-Policy to strict-origin-when-cross-origin', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res = makeMockRes();

    middleware({} as Request, res as unknown as Response, jest.fn());

    expect(res.headers['referrer-policy']).toBe('strict-origin-when-cross-origin');
  });

  it('removes X-Powered-By header', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res = makeMockRes();

    middleware({} as Request, res as unknown as Response, jest.fn());

    expect(res.removedHeaders).toContain('x-powered-by');
  });

  it('stores nonce on res.locals.cspNonce', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res = makeMockRes();

    middleware({} as Request, res as unknown as Response, jest.fn());

    expect(typeof res.locals['cspNonce']).toBe('string');
    expect((res.locals['cspNonce'] as string).length).toBeGreaterThan(0);
  });

  it('generates a unique nonce per request', () => {
    const middleware = createSecurityHeadersMiddleware();
    const res1 = makeMockRes();
    const res2 = makeMockRes();

    middleware({} as Request, res1 as unknown as Response, jest.fn());
    middleware({} as Request, res2 as unknown as Response, jest.fn());

    expect(res1.locals['cspNonce']).not.toBe(res2.locals['cspNonce']);
  });

  it('respects custom HSTS max-age', () => {
    const middleware = createSecurityHeadersMiddleware({ hstsMaxAge: 7776000 });
    const res = makeMockRes();

    middleware({} as Request, res as unknown as Response, jest.fn());

    expect(res.headers['strict-transport-security']).toContain('max-age=7776000');
  });

  it('calls next()', () => {
    const middleware = createSecurityHeadersMiddleware();
    const next = jest.fn();

    middleware({} as Request, makeMockRes() as unknown as Response, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(next).toHaveBeenCalledWith();
  });
});
