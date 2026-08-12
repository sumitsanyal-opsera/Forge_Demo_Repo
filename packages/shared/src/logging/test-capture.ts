/**
 * Test helper for capturing and asserting on structured log output.
 * Import this only in test files — not in production code.
 */

import type { LogEntry } from './logger.js';

export type { LogEntry };

/**
 * Executes `fn` and captures every JSON log line written to stdout during the call.
 * Restores the original `process.stdout.write` even if `fn` throws.
 *
 * @returns Array of parsed LogEntry objects written during the execution of `fn`.
 */
export async function captureLogOutput(
  fn: () => void | Promise<void>,
): Promise<LogEntry[]> {
  const entries: LogEntry[] = [];
  const originalWrite = process.stdout.write.bind(process.stdout) as typeof process.stdout.write;

  // Temporarily replace stdout.write to intercept JSON log lines.
  // The eslint-disable is intentional — we intentionally override a built-in.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (process.stdout as any).write = (chunk: string | Buffer): boolean => {
    const line = (typeof chunk === 'string' ? chunk : chunk.toString('utf8')).trim();
    if (line.length > 0) {
      try {
        entries.push(JSON.parse(line) as LogEntry);
      } catch {
        // Not a JSON log line — ignore (e.g. raw process.stdout.write in non-logger code).
      }
    }
    return true;
  };

  try {
    await Promise.resolve(fn());
  } finally {
    process.stdout.write = originalWrite;
  }

  return entries;
}

/**
 * Returns the first captured log entry at the given level, or undefined.
 */
export function findLogEntry(
  entries: LogEntry[],
  level: LogEntry['level'],
  messageSubstring?: string,
): LogEntry | undefined {
  return entries.find(
    (e) =>
      e.level === level &&
      (messageSubstring === undefined || e.message.includes(messageSubstring)),
  );
}
