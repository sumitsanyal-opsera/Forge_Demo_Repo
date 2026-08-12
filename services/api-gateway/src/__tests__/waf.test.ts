import { describe, it, expect, jest } from '@jest/globals';
import type { Request, Response } from 'express';
import { createWafMiddleware } from '../middleware/waf.js';

function makeReq(overrides: Partial<Request> = {}): Partial<Request> {
  return {
    path: '/api/v1/test',
    method: 'POST',
    url: '/api/v1/test',
    ip: '127.0.0.1',
    headers: {},
    body: undefined,
    ...overrides,
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

describe('createWafMiddleware', () => {
  describe('SQL injection blocking', () => {
    it.each([
      ['union select in path', '/api/v1/items?id=1 UNION SELECT username,password FROM users'],
      ['drop table in query', '/api/v1/items?id=1; DROP TABLE users'],
    ])('blocks %s with 403', (_label, url) => {
      const middleware = createWafMiddleware();
      const res = makeMockRes();
      const next = jest.fn();

      middleware(makeReq({ url, path: url.split('?')[0] }) as Request, res as unknown as Response, next);

      expect(res.status).toHaveBeenCalledWith(403);
      expect(next).not.toHaveBeenCalled();
    });

    it('blocks SQL injection in body', () => {
      const middleware = createWafMiddleware();
      const res = makeMockRes();
      const next = jest.fn();

      middleware(makeReq({ body: { name: "1; DROP TABLE users" } }) as Request, res as unknown as Response, next);

      expect(res.status).toHaveBeenCalledWith(403);
      expect(next).not.toHaveBeenCalled();
    });
  });

  describe('XSS blocking', () => {
    it('blocks script tag in query', () => {
      const middleware = createWafMiddleware();
      const res = makeMockRes();
      const next = jest.fn();

      middleware(makeReq({ url: '/api?q=<script>alert(1)</script>', path: '/api' }) as Request, res as unknown as Response, next);

      expect(res.status).toHaveBeenCalledWith(403);
      expect(next).not.toHaveBeenCalled();
    });

    it('blocks javascript: protocol', () => {
      const middleware = createWafMiddleware();
      const res = makeMockRes();
      const next = jest.fn();

      middleware(makeReq({ url: '/api?url=javascript:alert(1)', path: '/api' }) as Request, res as unknown as Response, next);

      expect(res.status).toHaveBeenCalledWith(403);
      expect(next).not.toHaveBeenCalled();
    });
  });

  describe('path traversal blocking', () => {
    it('blocks ../ in path', () => {
      const middleware = createWafMiddleware();
      const res = makeMockRes();
      const next = jest.fn();

      middleware(makeReq({ path: '/api/../../etc/passwd', url: '/api/../../etc/passwd' }) as Request, res as unknown as Response, next);

      expect(res.status).toHaveBeenCalledWith(403);
      expect(next).not.toHaveBeenCalled();
    });

    it('blocks /etc/passwd in path', () => {
      const middleware = createWafMiddleware();
      const res = makeMockRes();
      const next = jest.fn();

      middleware(makeReq({ path: '/api?file=/etc/passwd', url: '/api?file=/etc/passwd' }) as Request, res as unknown as Response, next);

      expect(res.status).toHaveBeenCalledWith(403);
      expect(next).not.toHaveBeenCalled();
    });
  });

  describe('legitimate requests', () => {
    it('passes a normal JSON request body', () => {
      const middleware = createWafMiddleware();
      const next = jest.fn();

      middleware(
        makeReq({ body: { pipelineId: 'abc123', orgId: 'org001', status: 'monitoring' } }) as Request,
        makeMockRes() as unknown as Response,
        next,
      );

      expect(next).toHaveBeenCalledTimes(1);
    });

    it('passes a normal GET request', () => {
      const middleware = createWafMiddleware();
      const next = jest.fn();

      middleware(
        makeReq({ method: 'GET', path: '/api/v1/pipelines', url: '/api/v1/pipelines?orgId=org001' }) as Request,
        makeMockRes() as unknown as Response,
        next,
      );

      expect(next).toHaveBeenCalledTimes(1);
    });
  });

  describe('trusted path exception', () => {
    it('skips body checks for /api/v1/pipelines (Salesforce metadata)', () => {
      const middleware = createWafMiddleware();
      const next = jest.fn();

      // UNION SELECT in body is normally blocked — but trusted path skips body WAF
      middleware(
        makeReq({
          path: '/api/v1/pipelines',
          url: '/api/v1/pipelines',
          body: { metadata: 'SELECT Name FROM ApexClass WHERE UNION ALL' },
        }) as Request,
        makeMockRes() as unknown as Response,
        next,
      );

      expect(next).toHaveBeenCalledTimes(1);
    });
  });

  describe('disabled WAF', () => {
    it('calls next for all requests when disabled', () => {
      const middleware = createWafMiddleware({ enabled: false });
      const next = jest.fn();

      middleware(
        makeReq({ url: '/evil?id=1 UNION SELECT * FROM passwords', path: '/evil' }) as Request,
        makeMockRes() as unknown as Response,
        next,
      );

      expect(next).toHaveBeenCalledTimes(1);
    });
  });

  describe('WAF response format', () => {
    it('returns standard error envelope without rule details', () => {
      const middleware = createWafMiddleware();
      const res = makeMockRes();

      middleware(makeReq({ url: '/api?q=<script>', path: '/api' }) as Request, res as unknown as Response, jest.fn());

      const body = res.getBody() as { errors: Array<{ code: string; message: string }> };
      expect(body.errors[0]?.code).toBe('WAF_BLOCKED');
      expect(body.errors[0]?.message).not.toContain('XSS');
      expect(body.errors[0]?.message).not.toContain('rule');
    });
  });
});
