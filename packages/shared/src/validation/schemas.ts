/**
 * Reusable JSON Schema (draft-07) fragments for common field types.
 * Compose these into your endpoint-specific schemas using `$ref` or spread.
 *
 * All schemas are typed as `const` to enable precise TypeScript inference.
 */

// ─── Primitive types ──────────────────────────────────────────────────────────

/** UUID v4 string validated via AJV's built-in 'uuid' format (via ajv-formats). */
export const uuidSchema = {
  type: 'string' as const,
  format: 'uuid',
} as const;

/** ISO 8601 datetime string validated via AJV's 'date-time' format. */
export const datetimeSchema = {
  type: 'string' as const,
  format: 'date-time',
} as const;

/** ISO 8601 date string (YYYY-MM-DD). */
export const dateSchema = {
  type: 'string' as const,
  format: 'date',
} as const;

/** Email address validated via AJV's 'email' format. */
export const emailSchema = {
  type: 'string' as const,
  format: 'email',
  maxLength: 255,
} as const;

/** Non-empty string. */
export const nonEmptyStringSchema = {
  type: 'string' as const,
  minLength: 1,
} as const;

// ─── Composite schemas ────────────────────────────────────────────────────────

/**
 * Standard pagination query parameters.
 * All fields are optional with sensible defaults (page=1, limit=20).
 */
export const paginationSchema = {
  type: 'object' as const,
  properties: {
    page: {
      type: 'integer' as const,
      minimum: 1,
      default: 1,
    },
    limit: {
      type: 'integer' as const,
      minimum: 1,
      maximum: 100,
      default: 20,
    },
    offset: {
      type: 'integer' as const,
      minimum: 0,
    },
  },
  additionalProperties: false as const,
} as const;

/**
 * Builds a string schema restricted to a fixed set of allowed values.
 * Example:
 *   const statusSchema = enumSchema(['active', 'inactive', 'pending'] as const);
 */
export function enumSchema<T extends string>(
  values: readonly T[],
): { type: 'string'; enum: T[] } {
  return { type: 'string', enum: [...values] };
}

/**
 * Schema for a positive integer (useful for IDs and counts).
 */
export const positiveIntegerSchema = {
  type: 'integer' as const,
  minimum: 1,
} as const;

/**
 * Schema for a non-negative integer.
 */
export const nonNegativeIntegerSchema = {
  type: 'integer' as const,
  minimum: 0,
} as const;

/**
 * Schema for a percentage value (0–100).
 */
export const percentageSchema = {
  type: 'number' as const,
  minimum: 0,
  maximum: 100,
} as const;

/**
 * Schema fragment for a time range query (used by dashboard and alert history endpoints).
 */
export const timeRangeSchema = {
  type: 'object' as const,
  properties: {
    from: datetimeSchema,
    to: datetimeSchema,
  },
  required: ['from', 'to'] as const,
  additionalProperties: false as const,
} as const;
