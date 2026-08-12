import { describe, it, expect, jest, beforeEach } from '@jest/globals';
import type { Request, Response } from 'express';
import { createRateLimiterMiddleware, type RateLimiterRedisClient } from '../middleware/rate-limiter.js';

function makeMockRedis(): jest.Mocked<RateLimiterRedisClient> {
  return {
    zadd: jest.fn<() => Promise<number>>().mockResolvedValue(1),
    zremrangebyscore: jest.fn<() => Promise<number>>().mockResolvedValue(0),
    zcount: jest.fn<() => Promise<number>>().mockResolvedValue(1),
    expire: jest.fn<() => Promise<number>>().mockResolvedValue(1),
  };
}

function makeReq(userId?: string): Partial<Request> & { userId?: string } {
  return {
    userId,
    ip: '127.0.0.1',
    headers: {},
    method: 'GET',
    path: '/api/v1/test',
  };
}

function makeMockRes() {
  const headers: Record<string, string | number> = {};
  let statusCode = 200;
  let body: unknown;
  const chainable = { json: jest.fn((data: unknown) => { body = data; }) };
  return {
    setHeader: jest.fn((name: string, val: string | number) => { headers[name] = val; }),
    status: jest.fn((code: number) => { statusCode = code; return chainable; }),
    getStatusCode: () => statusCode,
    getBody: () => body,
    headers,
  };
}

describe('createRateLimiterMiddleware', () => {
  let redis: jest.Mocked<RateLimiterRedisClient>;

  beforeEach(() => {
    redis = makeMockRedis();
  });

  it('calls next when request count is below limit', async () => {
    redis.zcount.mockResolvedValue(50);
    const middleware = createRateLimiterMiddleware(redis, { windowMs: 60000, maxRequests: 100 });
    const next = jest.fn();

    middleware(makeReq('user-1') as Request, makeMockRes() as unknown as Response, next);

    await new Promise((r) => setTimeout(r, 10));
    expect(next).toHaveBeenCalledTimes(1);
  });

  it('returns 429 when request count exceeds limit', async () => {
    redis.zcount.mockResolvedValue(101);
    const middleware = createRateLimiterMiddleware(redis, { windowMs: 60000, maxRequests: 100 });
    const res = makeMockRes();
    const next = jest.fn();

    middleware(makeReq('user-1') as Request, res as unknown as Response, next);

    await new Promise((r) => setTimeout(r, 10));
    expect(res.status).toHaveBeenCalledWith(429);
    expect(next).not.toHaveBeenCalled();
  });

  it('sets Retry-After header on 429', async () => {
    redis.zcount.mockResolvedValue(101);
    const middleware = createRateLimiterMiddleware(redis, { windowMs: 60000, maxRequests: 100 });
    const res = makeMockRes();

    middleware(makeReq('user-1') as Request, res as unknown as Response, jest.fn());

    await new Promise((r) => setTimeout(r, 10));
    expect(res.headers['Retry-After']).toBeDefined();
  });

  it('sets X-RateLimit headers', async () => {
    redis.zcount.mockResolvedValue(30);
    const middleware = createRateLimiterMiddleware(redis, { windowMs: 60000, maxRequests: 100 });
    const res = makeMockRes();

    middleware(makeReq('user-1') as Request, res as unknown as Response, jest.fn());

    await new Promise((r) => setTimeout(r, 10));
    expect(res.headers['X-RateLimit-Limit']).toBe(100);
    expect(res.headers['X-RateLimit-Remaining']).toBe(70);
  });

  it('includes RATE_LIMIT_EXCEEDED error code in body', async () => {
    redis.zcount.mockResolvedValue(101);
    const middleware = createRateLimiterMiddleware(redis, { windowMs: 60000, maxRequests: 100 });
    const res = makeMockRes();

    middleware(makeReq('user-1') as Request, res as unknown as Response, jest.fn());

    await new Promise((r) => setTimeout(r, 10));
    const body = res.getBody() as { errors: Array<{ code: string }> };
    expect(body.errors[0]?.code).toBe('RATE_LIMIT_EXCEEDED');
  });

  it('fails open when Redis throws', async () => {
    redis.zadd.mockRejectedValue(new Error('Redis connection refused'));
    const middleware = createRateLimiterMiddleware(redis, { windowMs: 60000, maxRequests: 100 });
    const next = jest.fn();

    middleware(makeReq('user-1') as Request, makeMockRes() as unknown as Response, next);

    await new Promise((r) => setTimeout(r, 10));
    expect(next).toHaveBeenCalledTimes(1);
  });

  it('uses userId as key when available', async () => {
    redis.zcount.mockResolvedValue(1);
    const middleware = createRateLimiterMiddleware(redis, { windowMs: 60000, maxRequests: 100, keyPrefix: 'rl' });

    middleware(makeReq('user-abc') as Request, makeMockRes() as unknown as Response, jest.fn());

    await new Promise((r) => setTimeout(r, 10));
    const addCall = redis.zadd.mock.calls[0] as [string, ...unknown[]];
    expect(addCall[0]).toContain('user-abc');
  });
});
