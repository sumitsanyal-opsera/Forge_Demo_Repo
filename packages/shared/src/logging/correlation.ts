/**
 * Correlation ID propagation via Node.js AsyncLocalStorage.
 * Provides automatic inclusion of correlation IDs in all log entries
 * without manually threading them through function call chains.
 */

import { AsyncLocalStorage } from 'node:async_hooks';

interface CorrelationContext {
  readonly correlationId: string;
}

const storage = new AsyncLocalStorage<CorrelationContext>();

/**
 * Executes `fn` within a new async context that carries the given `correlationId`.
 * Any logger calls within `fn` (or async continuations spawned from it) will
 * automatically include this ID without any explicit passing.
 */
export function runWithCorrelationId<T>(correlationId: string, fn: () => T): T {
  return storage.run({ correlationId }, fn);
}

/**
 * Returns the current correlation ID if one has been set via `runWithCorrelationId`,
 * or `undefined` if called outside such a context.
 */
export function getCorrelationId(): string | undefined {
  return storage.getStore()?.correlationId;
}

/**
 * Generates a new RFC-4122 v4 UUID suitable for use as a correlation ID.
 * Uses the built-in `crypto.randomUUID()` — no external dependency required.
 */
export function generateCorrelationId(): string {
  return crypto.randomUUID();
}
