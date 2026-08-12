/**
 * PrismaClient singleton with lazy initialisation, event-based logging,
 * and automatic graceful shutdown on SIGTERM/SIGINT.
 *
 * Connection pool size is configured via the DATABASE_URL query parameter:
 *   postgresql://user:pass@host:5432/db?connection_limit=20
 *
 * Usage:
 *   import { getPrismaClient } from '@opsera/shared/database';
 *   const prisma = getPrismaClient();
 *   const result = await prisma.someModel.findMany();
 */

import { PrismaClient } from '@prisma/client';
import { createLogger } from '../logging/logger.js';

const logger = createLogger('prisma-client');

// ─── Singleton state ──────────────────────────────────────────────────────────

let instance: PrismaClient | undefined;
let shutdownRegistered = false;

// ─── Factory ──────────────────────────────────────────────────────────────────

function buildPrismaClient(): PrismaClient {
  const databaseUrl = process.env['DATABASE_URL'];
  if (databaseUrl === undefined || databaseUrl.trim() === '') {
    throw new Error(
      'DATABASE_URL environment variable is required but not set. ' +
        'Set it to a valid PostgreSQL connection string, e.g.: ' +
        'postgresql://user:pass@localhost:5432/dbname?connection_limit=20',
    );
  }

  const client = new PrismaClient({
    log: [
      { emit: 'event', level: 'error' },
      { emit: 'event', level: 'warn' },
      // 'query' events emit one entry per SQL statement — enable only for debugging.
      // { emit: 'event', level: 'query' },
    ],
  });

  // Forward Prisma events to the structured logger.
  client.$on('error', (e) => {
    logger.error('Prisma client error', new Error(e.message), { target: e.target });
  });

  client.$on('warn', (e) => {
    logger.warn('Prisma client warning', { message: e.message, target: e.target });
  });

  return client;
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Returns the shared PrismaClient singleton, creating it on first call.
 * The client is NOT yet connected — call `connectDatabase()` during app startup
 * or let Prisma establish the connection lazily on the first query.
 */
export function getPrismaClient(): PrismaClient {
  if (instance === undefined) {
    instance = buildPrismaClient();
    registerShutdownHandlers();
  }
  return instance;
}

/**
 * Explicitly connects to the database.
 * Call this during application startup to fail fast if the database is unreachable.
 */
export async function connectDatabase(): Promise<void> {
  const client = getPrismaClient();
  try {
    await client.$connect();
    logger.info('Database connection established');
  } catch (error) {
    logger.error(
      'Failed to connect to database',
      error instanceof Error ? error : new Error(String(error)),
      { hint: 'Verify DATABASE_URL and that PostgreSQL is running' },
    );
    throw error;
  }
}

/**
 * Disconnects the PrismaClient and clears the singleton.
 * Called automatically on SIGTERM/SIGINT.
 */
export async function disconnectDatabase(): Promise<void> {
  if (instance !== undefined) {
    try {
      await instance.$disconnect();
      logger.info('Database connection closed');
    } catch (error) {
      logger.error(
        'Error while disconnecting database',
        error instanceof Error ? error : new Error(String(error)),
      );
    } finally {
      instance = undefined;
    }
  }
}

// ─── Shutdown integration ─────────────────────────────────────────────────────

function registerShutdownHandlers(): void {
  if (shutdownRegistered) return;
  shutdownRegistered = true;

  const handler = (): void => {
    void disconnectDatabase();
  };

  process.on('SIGTERM', handler);
  process.on('SIGINT', handler);
}
