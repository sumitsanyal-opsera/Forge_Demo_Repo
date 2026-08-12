/**
 * PII masking utilities for structured log output.
 * Detects and masks email addresses; redacts sensitive field names.
 */

// Regex for RFC-5321-compliant email addresses embedded anywhere in a string.
const EMAIL_REGEX = /\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b/g;

/**
 * Masks a single email address as `u***@domain.com`.
 * The local part is truncated to the first character + *** for brevity.
 */
function maskEmail(email: string): string {
  const atIndex = email.indexOf('@');
  if (atIndex <= 0) return '***' + email.substring(atIndex);
  return email[0] + '***' + email.substring(atIndex);
}

/**
 * Detects and masks all email addresses within an arbitrary string.
 * Emails embedded in longer strings are masked in-place:
 *   "User admin@example.com logged in" → "User a***@example.com logged in"
 */
export function maskPii(text: string): string {
  return text.replace(EMAIL_REGEX, (match) => maskEmail(match));
}

/**
 * Default set of field names whose values are always redacted.
 * Keys are lower-cased for case-insensitive matching.
 */
export const DEFAULT_SENSITIVE_FIELDS: ReadonlySet<string> = new Set([
  'password',
  'passwd',
  'token',
  'accesstoken',
  'refreshtoken',
  'secret',
  'authorization',
  'cookie',
  'apikey',
  'api_key',
  'privatekey',
  'private_key',
  'clientsecret',
  'client_secret',
  'ssn',
  'creditcard',
  'credit_card',
  'cvv',
]);

/**
 * Recursively walks an object and:
 *   1. Replaces values whose key appears in `sensitiveFields` with '[REDACTED]'.
 *   2. Masks PII (emails) in string values.
 *
 * Handles arrays, plain objects, and primitives. Returns a new deep copy —
 * the original object is never mutated.
 */
export function redactSensitiveFields(
  obj: unknown,
  sensitiveFields: ReadonlySet<string> = DEFAULT_SENSITIVE_FIELDS,
): unknown {
  if (obj === null || obj === undefined) return obj;

  if (typeof obj === 'string') {
    return maskPii(obj);
  }

  if (typeof obj !== 'object') {
    return obj;
  }

  if (Array.isArray(obj)) {
    return (obj as unknown[]).map((item) => redactSensitiveFields(item, sensitiveFields));
  }

  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
    if (sensitiveFields.has(key.toLowerCase())) {
      result[key] = '[REDACTED]';
    } else {
      result[key] = redactSensitiveFields(value, sensitiveFields);
    }
  }
  return result;
}
