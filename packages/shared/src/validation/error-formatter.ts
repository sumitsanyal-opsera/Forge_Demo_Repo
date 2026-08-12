/**
 * Formats AJV ErrorObject arrays into developer-friendly field-level error details.
 */

import type { ErrorObject } from 'ajv';

export interface FieldError {
  /** Dot-notation path to the invalid field (e.g. 'user.email', 'items[0].name'). */
  field: string;
  /** Human-readable description of the validation failure. */
  message: string;
  /** The actual invalid value (omitted for security if the path looks sensitive). */
  value?: unknown;
}

/**
 * Converts AJV's internal `ErrorObject[]` into a clean array of `FieldError` objects
 * suitable for inclusion in a 400 Bad Request response body.
 */
export function formatValidationErrors(errors: ErrorObject[]): FieldError[] {
  return errors.map((error): FieldError => {
    const field = deriveFieldPath(error);
    const message = error.message ?? 'Validation failed';

    return {
      field,
      message,
      ...(shouldIncludeValue(field) ? { value: error.data } : {}),
    };
  });
}

/** Derives a human-readable field path from an AJV ErrorObject. */
function deriveFieldPath(error: ErrorObject): string {
  // instancePath is like '/body/user/email' — normalise to 'body.user.email'
  if (error.instancePath && error.instancePath.length > 0) {
    return error.instancePath
      .replace(/^\//, '')   // strip leading slash
      .replace(/\//g, '.'); // replace path separators with dots
  }

  // For 'required' keyword errors, AJV puts the missing field name in params.
  if (
    error.keyword === 'required' &&
    error.params !== null &&
    typeof error.params === 'object' &&
    'missingProperty' in error.params
  ) {
    return String(error.params['missingProperty']);
  }

  // For 'additionalProperties' keyword errors.
  if (
    error.keyword === 'additionalProperties' &&
    error.params !== null &&
    typeof error.params === 'object' &&
    'additionalProperty' in error.params
  ) {
    return String(error.params['additionalProperty']);
  }

  return 'root';
}

/** Returns false for fields that look sensitive — we don't echo back passwords etc. */
const SENSITIVE_FIELD_PATTERN = /password|token|secret|authorization|cookie/i;

function shouldIncludeValue(field: string): boolean {
  return !SENSITIVE_FIELD_PATTERN.test(field);
}
