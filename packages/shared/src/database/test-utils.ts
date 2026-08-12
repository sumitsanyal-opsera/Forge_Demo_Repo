/**
 * Test database utilities.
 * Provides isolated PrismaClient instances for integration tests.
 * Import only in test files — not in production code.
 */

import { PrismaClient } from '@prisma/client';
import { createLogger } from '../logging/logger.js';

const logger = createLogger('db-test-utils');

/**
 * Creates and connects an isolated PrismaClient for use in tests.
 * Uses `TEST_DATABASE_URL` if set, falling back to `DATABASE_URL`.
 *
 * Remember to call `cleanupTestDatabase(client)` in your `afterAll`/`afterEach`.
 */
export async function createTestDatabase(): Promise<PrismaClient> {
  const url = process.env['TEST_DATABASE_URL'] ?? process.env['DATABASE_URL'];
  if (url === undefined || url.trim() === '') {
    throw new Error(
      'TEST_DATABASE_URL (or DATABASE_URL) must be set to run database integration tests. ' +
        'Start the local database with: docker compose up -d postgres',
    );
  }

  const client = new PrismaClient({
    datasources: { db: { url } },
    log: [{ emit: 'event', level: 'error' }],
  });

  client.$on('error', (e) => {
    logger.error('Test database error', new Error(e.message), { target: e.target });
  });

  await client.$connect();
  logger.debug('Test database connected', { url: sanitiseUrl(url) });
  return client;
}

/**
 * Disconnects the test PrismaClient created by `createTestDatabase`.
 */
export async function cleanupTestDatabase(client: PrismaClient): Promise<void> {
  await client.$disconnect();
  logger.debug('Test database disconnected');
}

/**
 * Returns the database URL with credentials redacted for safe logging.
 */
function sanitiseUrl(url: string): string {
  try {
    const parsed = new URL(url);
    if (parsed.password) parsed.password = '***';
    if (parsed.username) parsed.username = parsed.username.replace(/.+/, '***');
    return parsed.toString();
  } catch {
    return '[unparseable URL]';
  }
}

// ─── Mock Express helpers ─────────────────────────────────────────────────────

import type { Request, Response, NextFunction } from 'express';

/**
 * Creates a minimal mock Express Request object for unit tests.
 */
export function createMockRequest(
  overrides: Partial<Request> = {},
): Partial<Request> {
  return {
    path: '/test',
    method: 'GET',
    body: {},
    query: {},
    params: {},
    headers: {},
    ...overrides,
  };
}

/**
 * Creates a mock Express Response object that captures status code and JSON body.
 */
export function createMockResponse(): {
  res: Partial<Response>;
  getStatusCode: () => number;
  getJsonBody: () => unknown;
} {
  let statusCode = 200;
  let jsonBody: unknown;

  const res: Partial<Response> = {
    status: (code: number): Response => {
      statusCode = code;
      return res as Response;
    },
    json: (body: unknown): Response => {
      jsonBody = body;
      return res as Response;
    },
    setHeader: () => res as Response,
  };

  return {
    res,
    getStatusCode: () => statusCode,
    getJsonBody: () => jsonBody,
  };
}

/**
 * Returns a no-op NextFunction mock that optionally captures the argument passed to it.
 */
export function createMockNext(): { next: NextFunction; getCalledWith: () => unknown } {
  let calledWith: unknown;
  const next: NextFunction = (value?: unknown) => {
    calledWith = value;
  };
  return { next, getCalledWith: () => calledWith };
}
