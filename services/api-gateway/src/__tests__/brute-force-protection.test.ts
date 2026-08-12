import { describe, it, expect, jest, beforeEach } from '@jest/globals';
import type { Request, Response } from 'express';
import { createBruteForceProtection, type BruteForceRedisClient } from '../middleware/brute-force-protection.js';

function makeMockRedis(): jest.Mocked<BruteForceRedisClient> {
  const store: Record<string, string> = {};
  return {
    incr: jest.fn<(key: string) => Promise<number>>().mockImplementation(async (key) => {
      store[key] = String((parseInt(store[key] ?? '0', 10) + 1));
      return parseInt(store[key], 10);
    }),
    expire: jest.fn<() => Promise<number>>().mockResolvedValue(1),
    get: jest.fn<(key: string) => Promise<string | null>>().mockImplementation(async (key) => store[key] ?? null),
    set: jest.fn<(key: string, value: string, mode: 'EX', ttl: number) => Promise<string | null>>().mockImplementation(async (key, value) => {
      store[key] = value;
      return 'OK';
    }),
    exists: jest.fn<(key: string) => Promise<number>>().mockImplementation(async (key) => store[key] !== undefined ? 1 : 0),
  };
}

const OPTIONS = { windowMs: 15 * 60 * 1000, maxFailures: 5, lockoutMs: 30 * 60 * 1000 };

function makeReq(userId?: string): Partial<Request> & { userId?: string } {
  return { userId, ip: '192.168.1.100', headers: {}, method: 'POST', path: '/api/v1/auth' };
}

function makeMockRes() {
  let statusCode = 200;
  let body: unknown;
  const chainable = { json: jest.fn((data: unknown) => { body = data; }) };
  return {
    status: jest.fn((code: number) => { statusCode = code; return chainable; }),
    getStatusCode: () => statusCode,
    getBody: () => body,
  };
}

describe('createBruteForceProtection', () => {
  let redis: jest.Mocked<BruteForceRedisClient>;

  beforeEach(() => {
    redis = makeMockRedis();
  });

  describe('middleware', () => {
    it('calls next when user is not locked out', async () => {
      const tracker = createBruteForceProtection(redis, OPTIONS);
      const next = jest.fn();

      tracker.middleware(makeReq('user-1') as Request, makeMockRes() as unknown as Response, next);

      await new Promise((r) => setTimeout(r, 10));
      expect(next).toHaveBeenCalledTimes(1);
    });

    it('returns 429 when user is locked out', async () => {
      const tracker = createBruteForceProtection(redis, OPTIONS);
      // Simulate lockout by setting the lock key
      await redis.set('bf:lock:user-1', '1', 'EX', 1800);
      const res = makeMockRes();
      const next = jest.fn();

      tracker.middleware(makeReq('user-1') as Request, res as unknown as Response, next);

      await new Promise((r) => setTimeout(r, 10));
      expect(res.status).toHaveBeenCalledWith(429);
      expect(next).not.toHaveBeenCalled();
    });

    it('includes ACCOUNT_LOCKED error code in body', async () => {
      const tracker = createBruteForceProtection(redis, OPTIONS);
      await redis.set('bf:lock:user-1', '1', 'EX', 1800);
      const res = makeMockRes();

      tracker.middleware(makeReq('user-1') as Request, res as unknown as Response, jest.fn());

      await new Promise((r) => setTimeout(r, 10));
      const body = res.getBody() as { errors: Array<{ code: string }> };
      expect(body.errors[0]?.code).toBe('ACCOUNT_LOCKED');
    });

    it('fails open when Redis throws', async () => {
      redis.exists.mockRejectedValue(new Error('Connection refused'));
      const tracker = createBruteForceProtection(redis, OPTIONS);
      const next = jest.fn();

      tracker.middleware(makeReq('user-1') as Request, makeMockRes() as unknown as Response, next);

      await new Promise((r) => setTimeout(r, 10));
      expect(next).toHaveBeenCalledTimes(1);
    });
  });

  describe('recordFailure', () => {
    it('activates lockout after maxFailures failures', async () => {
      const tracker = createBruteForceProtection(redis, OPTIONS);

      for (let i = 0; i < OPTIONS.maxFailures; i++) {
        await tracker.recordFailure('user-bad');
      }

      expect(await tracker.isLockedOut('user-bad')).toBe(true);
    });

    it('does not lock out before maxFailures threshold', async () => {
      const tracker = createBruteForceProtection(redis, OPTIONS);

      for (let i = 0; i < OPTIONS.maxFailures - 1; i++) {
        await tracker.recordFailure('user-ok');
      }

      expect(await tracker.isLockedOut('user-ok')).toBe(false);
    });
  });

  describe('recordSuccess', () => {
    it('clears the failure counter on success', async () => {
      const tracker = createBruteForceProtection(redis, OPTIONS);

      await tracker.recordFailure('user-1');
      await tracker.recordSuccess('user-1');

      // The set call with '0' confirms counter was cleared
      const setCalls = redis.set.mock.calls as Array<[string, string, 'EX', number]>;
      const clearCall = setCalls.find(([k, v]) => k.includes('fail') && v === '0');
      expect(clearCall).toBeDefined();
    });
  });

  describe('per-user isolation', () => {
    it('lockout of user-A does not affect user-B', async () => {
      const tracker = createBruteForceProtection(redis, OPTIONS);

      for (let i = 0; i < OPTIONS.maxFailures; i++) {
        await tracker.recordFailure('user-A');
      }

      expect(await tracker.isLockedOut('user-A')).toBe(true);
      expect(await tracker.isLockedOut('user-B')).toBe(false);
    });
  });
});
