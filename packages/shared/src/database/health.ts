/**
 * Database health check.
 * Executes `SELECT 1` to verify the PostgreSQL connection and measures latency.
 * Returns a structured result — never throws.
 */

import { getPrismaClient } from './client.js';
import { createLogger } from '../logging/logger.js';

const logger = createLogger('db-health');

export interface DatabaseHealthResult {
  /** Whether the database is reachable and responsive. */
  status: 'healthy' | 'unhealthy';
  /** Round-trip time for the `SELECT 1` probe in milliseconds. */
  latencyMs: number;
  /** Error message when status is 'unhealthy'. */
  error?: string;
}

/**
 * Checks database connectivity by executing `SELECT 1`.
 *
 * @returns A `DatabaseHealthResult` — never rejects.
 */
export async function checkDatabaseHealth(): Promise<DatabaseHealthResult> {
  const start = Date.now();
  try {
    const client = getPrismaClient();
    // $queryRaw uses a parameterised query interface — safe from SQL injection.
    await client.$queryRaw`SELECT 1`;
    const latencyMs = Date.now() - start;
    logger.debug('Database health check passed', { latencyMs });
    return { status: 'healthy', latencyMs };
  } catch (error) {
    const latencyMs = Date.now() - start;
    const message = error instanceof Error ? error.message : String(error);
    logger.warn('Database health check failed', { latencyMs, error: message });
    return { status: 'unhealthy', latencyMs, error: message };
  }
}
