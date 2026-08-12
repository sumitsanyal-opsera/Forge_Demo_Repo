import { type RequestHandler } from 'express';
import { createLogger, generateCorrelationId } from '@opsera/shared';

const logger = createLogger('brute-force-protection');

export interface BruteForceRedisClient {
  incr(key: string): Promise<number>;
  expire(key: string, seconds: number): Promise<number>;
  get(key: string): Promise<string | null>;
  set(key: string, value: string, expiryMode: 'EX', ttlSeconds: number): Promise<string | null>;
  exists(key: string): Promise<number>;
}

export interface BruteForceOptions {
  windowMs: number;
  maxFailures: number;
  lockoutMs: number;
  keyPrefix?: string;
}

export interface BruteForceTracker {
  middleware: RequestHandler;
  recordFailure(userId: string): Promise<void>;
  recordSuccess(userId: string): Promise<void>;
  isLockedOut(userId: string): Promise<boolean>;
}

/**
 * Redis-backed brute-force protection.
 * Tracks failed authentication attempts per user/IP.
 * Locks out the user for lockoutMs after maxFailures failures within windowMs.
 * Lockout is per-user — does not affect other accounts.
 */
export function createBruteForceProtection(
  redis: BruteForceRedisClient,
  options: BruteForceOptions,
): BruteForceTracker {
  const { windowMs, maxFailures, lockoutMs, keyPrefix = 'bf' } = options;
  const windowSec = Math.ceil(windowMs / 1000);
  const lockoutSec = Math.ceil(lockoutMs / 1000);

  function failKey(userId: string): string {
    return `${keyPrefix}:fail:${userId}`;
  }

  function lockKey(userId: string): string {
    return `${keyPrefix}:lock:${userId}`;
  }

  async function isLockedOut(userId: string): Promise<boolean> {
    try {
      return (await redis.exists(lockKey(userId))) === 1;
    } catch {
      return false; // Fail open
    }
  }

  async function recordFailure(userId: string): Promise<void> {
    try {
      const count = await redis.incr(failKey(userId));
      // Set TTL only on first increment (preserves sliding window)
      if (count === 1) {
        await redis.expire(failKey(userId), windowSec);
      }
      if (count >= maxFailures) {
        await redis.set(lockKey(userId), '1', 'EX', lockoutSec);
        logger.warn('Brute-force lockout activated', { userId, failureCount: count, lockoutSec });
      }
    } catch (err) {
      logger.error('Brute-force tracker Redis failure', err instanceof Error ? err : undefined, { userId });
    }
  }

  async function recordSuccess(userId: string): Promise<void> {
    // On successful auth, clear failure counter (not the lockout — that expires naturally)
    try {
      await redis.set(failKey(userId), '0', 'EX', 1);
    } catch {
      // Non-critical
    }
  }

  const middleware: RequestHandler = (req, res, next) => {
    const userId = (req as { userId?: string }).userId ?? req.ip ?? 'anonymous';

    void (async () => {
      try {
        if (await isLockedOut(userId)) {
          logger.warn('Brute-force lockout rejected request', { userId, path: req.path });

          res.status(429).json({
            data: null,
            meta: {
              timestamp: new Date().toISOString(),
              requestId: (req.headers['x-request-id'] as string | undefined) ?? generateCorrelationId(),
            },
            errors: [
              {
                code: 'ACCOUNT_LOCKED',
                message: `Account temporarily locked due to too many failed attempts. Retry after ${lockoutSec} seconds.`,
                retryAfterSeconds: lockoutSec,
              },
            ],
          });
          return;
        }
        next();
      } catch (err) {
        // Fail open
        logger.error('Brute-force check Redis failure — failing open', err instanceof Error ? err : undefined, { userId });
        next();
      }
    })();
  };

  return { middleware, recordFailure, recordSuccess, isLockedOut };
}
