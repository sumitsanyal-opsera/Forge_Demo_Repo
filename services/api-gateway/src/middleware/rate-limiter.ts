import { type RequestHandler } from 'express';
import { createLogger, generateCorrelationId } from '@opsera/shared';

const logger = createLogger('rate-limiter');

export interface RateLimiterRedisClient {
  zadd(key: string, score: number, member: string): Promise<number>;
  zremrangebyscore(key: string, min: string | number, max: string | number): Promise<number>;
  zcount(key: string, min: string | number, max: string | number): Promise<number>;
  expire(key: string, seconds: number): Promise<number>;
}

export interface RateLimiterOptions {
  windowMs: number;
  maxRequests: number;
  keyPrefix?: string;
}

function getRateLimitKey(prefix: string, userId: string): string {
  return `${prefix}:${userId}`;
}

/**
 * Redis-backed sliding window rate limiter keyed by authenticated user ID.
 * Returns 429 with Retry-After header when the per-minute limit is exceeded.
 * Fails open (allows request) if Redis is unavailable, logging a critical alert.
 */
export function createRateLimiterMiddleware(
  redis: RateLimiterRedisClient,
  options: RateLimiterOptions,
): RequestHandler {
  const { windowMs, maxRequests, keyPrefix = 'rl' } = options;
  const windowSec = Math.ceil(windowMs / 1000);

  return (req, res, next) => {
    const userId = (req as { userId?: string }).userId ?? req.ip ?? 'anonymous';
    const key = getRateLimitKey(keyPrefix, userId);
    const now = Date.now();
    const windowStart = now - windowMs;
    const member = `${now}-${Math.random().toString(36).slice(2, 8)}`;

    void (async () => {
      try {
        // Sliding window: remove entries outside window, add current, count
        await redis.zremrangebyscore(key, '-inf', windowStart);
        await redis.zadd(key, now, member);
        const count = await redis.zcount(key, '-inf', '+inf');
        await redis.expire(key, windowSec + 1);

        res.setHeader('X-RateLimit-Limit', maxRequests);
        res.setHeader('X-RateLimit-Remaining', Math.max(0, maxRequests - count));

        if (count > maxRequests) {
          const retryAfterSec = Math.ceil(windowMs / 1000);
          res.setHeader('Retry-After', retryAfterSec);
          res.setHeader('X-RateLimit-Reset', Math.ceil((now + windowMs) / 1000));

          logger.warn('Rate limit exceeded', { userId, count, maxRequests });

          res.status(429).json({
            data: null,
            meta: {
              timestamp: new Date().toISOString(),
              requestId: (req.headers['x-request-id'] as string | undefined) ?? generateCorrelationId(),
            },
            errors: [
              {
                code: 'RATE_LIMIT_EXCEEDED',
                message: `Rate limit exceeded. Maximum ${maxRequests} requests per minute per user.`,
                retryAfterSeconds: retryAfterSec,
              },
            ],
          });
          return;
        }

        next();
      } catch (err) {
        // Fail open — never block traffic on Redis connection failure
        logger.error('Rate limiter Redis failure — failing open', err instanceof Error ? err : undefined, {
          userId,
          alert: 'RATE_LIMITER_DEGRADED',
        });
        next();
      }
    })();
  };
}
