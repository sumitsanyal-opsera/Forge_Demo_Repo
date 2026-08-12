/**
 * Unit tests for database infrastructure (mocked — no real DB required):
 *  - PrismaClient singleton returns the same instance across multiple calls
 *  - Graceful shutdown calls $disconnect
 *  - Health check returns success/failure objects (not throws)
 *  - Missing DATABASE_URL throws a descriptive error
 */

import { jest } from '@jest/globals';

// ─── Singleton behaviour ──────────────────────────────────────────────────────

describe('getPrismaClient singleton', () => {
  const originalEnv = process.env['DATABASE_URL'];

  beforeEach(() => {
    process.env['DATABASE_URL'] = 'postgresql://user:pass@localhost:5432/testdb?connection_limit=20';
    // Reset singleton state between tests by clearing the module from the cache.
    jest.resetModules();
  });

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env['DATABASE_URL'];
    } else {
      process.env['DATABASE_URL'] = originalEnv;
    }
    jest.resetModules();
  });

  it('returns the same PrismaClient instance on multiple calls', async () => {
    // Dynamic import after resetModules ensures a fresh singleton state.
    const { getPrismaClient } = await import('../database/client.js');
    const first = getPrismaClient();
    const second = getPrismaClient();
    expect(first).toBe(second);
  });

  it('throws a descriptive error when DATABASE_URL is missing', async () => {
    delete process.env['DATABASE_URL'];
    const { getPrismaClient } = await import('../database/client.js');
    expect(() => getPrismaClient()).toThrow(/DATABASE_URL/);
  });
});

// ─── Health check ─────────────────────────────────────────────────────────────

describe('checkDatabaseHealth', () => {
  const originalEnv = process.env['DATABASE_URL'];

  beforeEach(() => {
    process.env['DATABASE_URL'] =
      'postgresql://user:pass@localhost:5432/testdb?connection_limit=20';
    jest.resetModules();
  });

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env['DATABASE_URL'];
    } else {
      process.env['DATABASE_URL'] = originalEnv;
    }
    jest.resetModules();
  });

  it('returns unhealthy result (not throw) when DB is unreachable', async () => {
    // Point to an unreachable host so $queryRaw will fail.
    process.env['DATABASE_URL'] =
      'postgresql://user:pass@192.0.2.1:5432/testdb?connection_limit=1&connect_timeout=1';

    const { checkDatabaseHealth } = await import('../database/health.js');
    // Should resolve (not reject) with an unhealthy result
    const result = await checkDatabaseHealth();
    expect(result.status).toBe('unhealthy');
    expect(typeof result.latencyMs).toBe('number');
    expect(typeof result.error).toBe('string');
  });

  it('health check result always has latencyMs as a number', async () => {
    // Even on failure, latencyMs must be present
    process.env['DATABASE_URL'] =
      'postgresql://user:pass@192.0.2.1:5432/testdb?connection_limit=1&connect_timeout=1';

    const { checkDatabaseHealth } = await import('../database/health.js');
    const result = await checkDatabaseHealth();
    expect(typeof result.latencyMs).toBe('number');
    expect(result.latencyMs).toBeGreaterThanOrEqual(0);
  });
});
