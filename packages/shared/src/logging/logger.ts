/**
 * Structured JSON logger.
 *
 * Design goals:
 *  - Zero external dependencies (no winston, pino)
 *  - Never throws — any logging failure falls back to stderr
 *  - Automatic PII masking and sensitive-field redaction
 *  - Automatic correlation ID inclusion via AsyncLocalStorage
 *  - Configurable minimum log level via LOG_LEVEL env var
 *  - Circular-reference-safe JSON serialisation
 */

import { getCorrelationId } from './correlation.js';
import { redactSensitiveFields, maskPii } from './masking.js';

// ─── Types ───────────────────────────────────────────────────────────────────

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LogEntry {
  timestamp: string;
  level: LogLevel;
  service: string;
  message: string;
  correlationId?: string;
  context?: Record<string, unknown>;
  error?: {
    name: string;
    message: string;
    stack?: string;
  };
}

export interface Logger {
  debug(message: string, context?: Record<string, unknown>): void;
  info(message: string, context?: Record<string, unknown>): void;
  warn(message: string, context?: Record<string, unknown>): void;
  /**
   * Logs an error-level message.
   * @param message  Human-readable description of what went wrong.
   * @param error    The thrown Error object (stack trace captured in non-production).
   * @param context  Optional additional structured context.
   */
  error(message: string, error?: Error | unknown, context?: Record<string, unknown>): void;
  /** Creates a child logger that merges `bindings` into every log entry's context. */
  child(bindings: Record<string, unknown>): Logger;
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

const LOG_LEVEL_PRIORITY: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

function parseLogLevel(raw: string | undefined): LogLevel {
  const normalised = raw?.toLowerCase().trim();
  if (normalised && normalised in LOG_LEVEL_PRIORITY) {
    return normalised as LogLevel;
  }
  return 'info';
}

/**
 * JSON.stringify replacement that handles circular references by substituting
 * '[Circular]' for any object already in the serialisation stack.
 */
function safeStringify(obj: unknown): string {
  const seen = new WeakSet<object>();
  return JSON.stringify(obj, (_key, value: unknown) => {
    if (typeof value === 'object' && value !== null) {
      if (seen.has(value as object)) return '[Circular]';
      seen.add(value as object);
    }
    return value;
  });
}

// ─── Factory ──────────────────────────────────────────────────────────────────

/**
 * Creates a named logger for the given service.
 *
 * @param service        Service/module name included in every log entry.
 * @param defaultContext Optional key/value pairs merged into every entry's context.
 */
export function createLogger(service: string, defaultContext?: Record<string, unknown>): Logger {
  function writeLog(level: LogLevel, message: string, extraContext?: Record<string, unknown>): void {
    try {
      const minLevel = parseLogLevel(process.env['LOG_LEVEL']);
      if ((LOG_LEVEL_PRIORITY[level] ?? 0) < (LOG_LEVEL_PRIORITY[minLevel] ?? 0)) return;

      const correlationId = getCorrelationId();

      const mergedContext =
        defaultContext !== undefined || extraContext !== undefined
          ? { ...(defaultContext ?? {}), ...(extraContext ?? {}) }
          : undefined;

      const entry: LogEntry = {
        timestamp: new Date().toISOString(),
        level,
        service,
        message: maskPii(message),
        ...(correlationId !== undefined ? { correlationId } : {}),
        ...(mergedContext !== undefined
          ? { context: redactSensitiveFields(mergedContext) as Record<string, unknown> }
          : {}),
      };

      process.stdout.write(safeStringify(entry) + '\n');
    } catch (writeError) {
      // Absolute fallback — never let the logger crash the application.
      try {
        process.stderr.write(
          `[LOGGER_FALLBACK] Failed to write log entry: ${String(writeError)}\n`,
        );
      } catch {
        // Truly unrecoverable — swallow silently.
      }
    }
  }

  const logger: Logger = {
    debug: (message, context) => writeLog('debug', message, context),
    info: (message, context) => writeLog('info', message, context),
    warn: (message, context) => writeLog('warn', message, context),

    error: (message, errorOrContext?, extraContext?) => {
      let errorMeta: LogEntry['error'] | undefined;
      let ctx: Record<string, unknown> | undefined = extraContext;

      if (errorOrContext instanceof Error) {
        errorMeta = {
          name: errorOrContext.name,
          message: errorOrContext.message,
          ...(process.env['NODE_ENV'] !== 'production' && errorOrContext.stack !== undefined
            ? { stack: errorOrContext.stack }
            : {}),
        };
      } else if (errorOrContext !== undefined && errorOrContext !== null) {
        // Non-Error thrown value — merge into context rather than crashing.
        ctx = {
          ...(extraContext ?? {}),
          thrownValue: String(errorOrContext),
        };
      }

      try {
        const minLevel = parseLogLevel(process.env['LOG_LEVEL']);
        if ((LOG_LEVEL_PRIORITY['error'] ?? 0) < (LOG_LEVEL_PRIORITY[minLevel] ?? 0)) return;

        const correlationId = getCorrelationId();
        const mergedContext =
          defaultContext !== undefined || ctx !== undefined
            ? { ...(defaultContext ?? {}), ...(ctx ?? {}) }
            : undefined;

        const entry: LogEntry = {
          timestamp: new Date().toISOString(),
          level: 'error',
          service,
          message: maskPii(message),
          ...(correlationId !== undefined ? { correlationId } : {}),
          ...(mergedContext !== undefined
            ? { context: redactSensitiveFields(mergedContext) as Record<string, unknown> }
            : {}),
          ...(errorMeta !== undefined ? { error: errorMeta } : {}),
        };

        process.stdout.write(safeStringify(entry) + '\n');
      } catch (writeError) {
        try {
          process.stderr.write(
            `[LOGGER_FALLBACK] Failed to write error log: ${String(writeError)}\n`,
          );
        } catch {
          // swallow
        }
      }
    },

    child: (bindings) =>
      createLogger(service, { ...(defaultContext ?? {}), ...bindings }),
  };

  return logger;
}
