/**
 * Unit tests for logging infrastructure:
 *  - Logger structured JSON output format
 *  - PII masking (email detection and masking)
 *  - Sensitive field redaction (at various nesting depths)
 *  - Correlation ID propagation across async boundaries
 *  - Log level filtering via LOG_LEVEL env var
 */

import { createLogger } from '../logging/logger.js';
import { maskPii, redactSensitiveFields } from '../logging/masking.js';
import {
  generateCorrelationId,
  getCorrelationId,
  runWithCorrelationId,
} from '../logging/correlation.js';
import { captureLogOutput, findLogEntry } from '../logging/test-capture.js';

// ─── Logger output format ─────────────────────────────────────────────────────

describe('Logger — output format', () => {
  it('writes a JSON entry with required fields to stdout', async () => {
    const logger = createLogger('test-service');
    const entries = await captureLogOutput(() => {
      logger.info('Hello, world!');
    });

    expect(entries).toHaveLength(1);
    const entry = entries[0]!;
    expect(entry.level).toBe('info');
    expect(entry.service).toBe('test-service');
    expect(entry.message).toBe('Hello, world!');
    expect(typeof entry.timestamp).toBe('string');
    // Timestamp must be a valid ISO 8601 string
    expect(() => new Date(entry.timestamp)).not.toThrow();
    expect(new Date(entry.timestamp).toISOString()).toBe(entry.timestamp);
  });

  it('includes context in the log entry when provided', async () => {
    const logger = createLogger('test-service');
    const entries = await captureLogOutput(() => {
      logger.info('Processing event', { eventId: 'abc-123', step: 'deploy' });
    });

    const entry = entries[0]!;
    expect(entry.context).toMatchObject({ eventId: 'abc-123', step: 'deploy' });
  });

  it('includes error details for error-level logs', async () => {
    const logger = createLogger('test-service');
    const testError = new Error('Something broke');
    const entries = await captureLogOutput(() => {
      logger.error('Operation failed', testError);
    });

    const entry = entries[0]!;
    expect(entry.level).toBe('error');
    expect(entry.error).toBeDefined();
    expect(entry.error?.name).toBe('Error');
    expect(entry.error?.message).toBe('Something broke');
  });

  it('handles circular references in context without throwing', async () => {
    const logger = createLogger('test-service');
    const circular: Record<string, unknown> = { name: 'test' };
    circular['self'] = circular; // intentional circular ref

    const entries = await captureLogOutput(() => {
      logger.info('Circular context test', circular);
    });

    expect(entries).toHaveLength(1);
    // The circular ref should be replaced with '[Circular]'
    const entry = entries[0]!;
    expect(JSON.stringify(entry)).toContain('[Circular]');
  });

  it('child logger inherits service name and merges default context', async () => {
    const parent = createLogger('parent-service');
    const child = parent.child({ requestId: 'req-999' });

    const entries = await captureLogOutput(() => {
      child.info('Child log message');
    });

    const entry = entries[0]!;
    expect(entry.service).toBe('parent-service');
    expect(entry.context).toMatchObject({ requestId: 'req-999' });
  });

  it('does not throw even when log output itself fails', () => {
    // The logger should be resilient — it must never propagate exceptions.
    const logger = createLogger('test-service');
    const originalWrite = process.stdout.write.bind(process.stdout);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (process.stdout as any).write = () => { throw new Error('write failed'); };
    expect(() => logger.info('This should not throw')).not.toThrow();
    process.stdout.write = originalWrite;
  });
});

// ─── Log level filtering ──────────────────────────────────────────────────────

describe('Logger — log level filtering', () => {
  const original = process.env['LOG_LEVEL'];

  afterEach(() => {
    if (original === undefined) {
      delete process.env['LOG_LEVEL'];
    } else {
      process.env['LOG_LEVEL'] = original;
    }
  });

  it('suppresses debug logs when LOG_LEVEL=info', async () => {
    process.env['LOG_LEVEL'] = 'info';
    const logger = createLogger('filter-test');
    const entries = await captureLogOutput(() => {
      logger.debug('This should be filtered out');
      logger.info('This should appear');
    });

    expect(entries).toHaveLength(1);
    expect(entries[0]?.level).toBe('info');
  });

  it('shows all levels when LOG_LEVEL=debug', async () => {
    process.env['LOG_LEVEL'] = 'debug';
    const logger = createLogger('filter-test');
    const entries = await captureLogOutput(() => {
      logger.debug('debug msg');
      logger.info('info msg');
      logger.warn('warn msg');
      logger.error('error msg');
    });

    expect(entries).toHaveLength(4);
  });

  it('shows only error when LOG_LEVEL=error', async () => {
    process.env['LOG_LEVEL'] = 'error';
    const logger = createLogger('filter-test');
    const entries = await captureLogOutput(() => {
      logger.debug('debug');
      logger.info('info');
      logger.warn('warn');
      logger.error('error only');
    });

    expect(entries).toHaveLength(1);
    expect(entries[0]?.level).toBe('error');
  });
});

// ─── PII masking ──────────────────────────────────────────────────────────────

describe('maskPii', () => {
  it('masks a simple email address', () => {
    expect(maskPii('admin@example.com')).toBe('a***@example.com');
  });

  it('masks an email embedded in a longer string', () => {
    const result = maskPii('User admin@example.com logged in');
    expect(result).toBe('User a***@example.com logged in');
  });

  it('masks a plus-addressed email', () => {
    const result = maskPii('contact+newsletter@domain.org');
    expect(result).toBe('c***@domain.org');
  });

  it('masks an email with subdomain', () => {
    expect(maskPii('user@mail.subdomain.example.com')).toBe('u***@mail.subdomain.example.com');
  });

  it('masks multiple emails in a single string', () => {
    const result = maskPii('Send to alice@foo.com and bob@bar.net for review');
    expect(result).toContain('a***@foo.com');
    expect(result).toContain('b***@bar.net');
  });

  it('returns the string unchanged when no emails are present', () => {
    expect(maskPii('No emails here')).toBe('No emails here');
  });

  it('masks emails in log messages automatically', async () => {
    const logger = createLogger('pii-test');
    const entries = await captureLogOutput(() => {
      logger.info('Processing request for user@example.com');
    });

    expect(entries[0]?.message).not.toContain('user@example.com');
    expect(entries[0]?.message).toContain('u***@example.com');
  });
});

// ─── Sensitive field redaction ────────────────────────────────────────────────

describe('redactSensitiveFields', () => {
  it('redacts top-level sensitive fields', () => {
    const result = redactSensitiveFields({ password: 'secret123', name: 'Alice' }) as Record<string, unknown>;
    expect(result['password']).toBe('[REDACTED]');
    expect(result['name']).toBe('Alice');
  });

  it('redacts nested sensitive fields', () => {
    const input = { user: { token: 'bearer-xyz', email: 'a@b.com', role: 'admin' } };
    const result = redactSensitiveFields(input) as { user: Record<string, unknown> };
    expect(result.user['token']).toBe('[REDACTED]');
    expect(result.user['role']).toBe('admin');
  });

  it('redacts sensitive fields inside arrays', () => {
    const input = [{ cookie: 'session=abc' }, { name: 'safe' }];
    const result = redactSensitiveFields(input) as Array<Record<string, unknown>>;
    expect(result[0]?.['cookie']).toBe('[REDACTED]');
    expect(result[1]?.['name']).toBe('safe');
  });

  it('is case-insensitive for field names', () => {
    const result = redactSensitiveFields({ Password: 'abc', TOKEN: 'xyz' }) as Record<string, unknown>;
    expect(result['Password']).toBe('[REDACTED]');
    expect(result['TOKEN']).toBe('[REDACTED]');
  });

  it('returns primitives unchanged (except strings which get PII masking)', () => {
    expect(redactSensitiveFields(42)).toBe(42);
    expect(redactSensitiveFields(true)).toBe(true);
    expect(redactSensitiveFields(null)).toBeNull();
  });

  it('masks emails within string values', () => {
    const result = redactSensitiveFields({ message: 'Sent to user@example.com' }) as Record<string, unknown>;
    expect(result['message']).toContain('u***@example.com');
  });
});

// ─── Correlation ID propagation ───────────────────────────────────────────────

describe('Correlation ID', () => {
  it('generates a valid UUID', () => {
    const id = generateCorrelationId();
    expect(id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  it('returns undefined outside a correlation context', () => {
    // Ensure we are NOT in a context for this test.
    expect(getCorrelationId()).toBeUndefined();
  });

  it('propagates the correlation ID within runWithCorrelationId', () => {
    let captured: string | undefined;
    runWithCorrelationId('test-id-123', () => {
      captured = getCorrelationId();
    });
    expect(captured).toBe('test-id-123');
  });

  it('includes correlationId in log output when set', async () => {
    const logger = createLogger('correlation-test');
    const entries = await captureLogOutput(() => {
      runWithCorrelationId('corr-abc', () => {
        logger.info('Message with correlation');
      });
    });

    expect(entries[0]?.correlationId).toBe('corr-abc');
  });

  it('propagates correlation ID across async boundaries', async () => {
    const logger = createLogger('async-correlation-test');
    let capturedInsideAsync: string | undefined;

    await new Promise<void>((resolve) => {
      runWithCorrelationId('async-id-456', () => {
        // Simulate an async operation
        setTimeout(() => {
          capturedInsideAsync = getCorrelationId();
          resolve();
        }, 1);
      });
    });

    expect(capturedInsideAsync).toBe('async-id-456');
  });
});
