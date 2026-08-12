// UUID v4 pattern
const UUID_PATTERN = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

// Numeric path segment (e.g. /api/users/12345/posts)
const NUMERIC_SEGMENT_PATTERN = /\/\d+(?=\/|$)/g;

const EXCLUDED_PATHS = ['/metrics', '/health'];

/**
 * Normalises an HTTP request path for use as a Prometheus label.
 * Replaces UUID and numeric ID segments with `:id` to prevent cardinality explosion.
 *
 * Examples:
 *   /api/v1/pipelines/abc123-def4-...  → /api/v1/pipelines/:id
 *   /api/v1/orgs/42/runs              → /api/v1/orgs/:id/runs
 */
export function normalizePath(path: string): string {
  return path
    .replace(UUID_PATTERN, ':id')
    .replace(NUMERIC_SEGMENT_PATTERN, '/:id');
}

/**
 * Returns true for paths that should be excluded from HTTP instrumentation
 * (/metrics and /health/**) to avoid self-referential metric pollution.
 */
export function isExcludedPath(path: string): boolean {
  const normalised = path.split('?')[0] ?? path;
  return EXCLUDED_PATHS.some((excluded) => normalised === excluded || normalised.startsWith(`${excluded}/`));
}
