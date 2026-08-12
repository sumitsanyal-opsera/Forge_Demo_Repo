/**
 * Process-level error handlers for unhandled rejections and uncaught exceptions.
 * These are the last line of defense — they log critical errors and initiate
 * graceful shutdown to avoid running in an unknown/corrupt state.
 */

import { createLogger } from '../logging/logger.js';

const logger = createLogger('process-handlers');

/**
 * Registers handlers for `unhandledRejection`, `uncaughtException`, `SIGTERM`, and `SIGINT`.
 *
 * @param onShutdown Optional async cleanup function (e.g., disconnect database, flush queues).
 *                   Called before the process exits. Must resolve within a reasonable timeout.
 */
export function registerProcessHandlers(onShutdown?: () => Promise<void>): void {
  // ── Unhandled promise rejections ─────────────────────────────────────────
  process.on('unhandledRejection', (reason: unknown) => {
    const error =
      reason instanceof Error ? reason : new Error(`Unhandled rejection: ${String(reason)}`);
    logger.error('Unhandled promise rejection detected', error, {
      note: 'Process will continue but this indicates a missing .catch() handler',
    });
    // We log but do NOT exit — some test runners intentionally have unhandled rejections.
    // Adjust per deployment policy if desired.
  });

  // ── Uncaught synchronous exceptions ─────────────────────────────────────
  process.on('uncaughtException', (error: Error) => {
    logger.error('Uncaught exception — process is in an unknown state, initiating shutdown', error);
    void gracefulShutdown('uncaughtException', onShutdown).finally(() => {
      process.exit(1);
    });
  });

  // ── Graceful shutdown signals ────────────────────────────────────────────
  process.on('SIGTERM', () => {
    void gracefulShutdown('SIGTERM', onShutdown).then(
      () => process.exit(0),
      () => process.exit(1),
    );
  });

  process.on('SIGINT', () => {
    void gracefulShutdown('SIGINT', onShutdown).then(
      () => process.exit(0),
      () => process.exit(1),
    );
  });
}

async function gracefulShutdown(
  signal: string,
  onShutdown?: () => Promise<void>,
): Promise<void> {
  logger.info(`Received ${signal} — initiating graceful shutdown`);
  try {
    if (onShutdown !== undefined) {
      await onShutdown();
    }
    logger.info('Graceful shutdown complete');
  } catch (error) {
    logger.error(
      'Error during graceful shutdown',
      error instanceof Error ? error : new Error(String(error)),
    );
    throw error;
  }
}
