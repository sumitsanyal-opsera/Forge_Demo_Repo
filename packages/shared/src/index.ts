/**
 * @opsera/shared — public API surface.
 *
 * Import specific sub-paths for tree-shaking-friendly usage:
 *   import { createLogger } from '@opsera/shared';
 *   import { getPrismaClient } from '@opsera/shared/database';
 *
 * Or import everything from the root for convenience in service bootstrapping.
 */

// ── Database ──────────────────────────────────────────────────────────────────
export {
  connectDatabase,
  disconnectDatabase,
  getPrismaClient,
} from './database/client.js';

export type { DatabaseHealthResult } from './database/health.js';
export { checkDatabaseHealth } from './database/health.js';

// ── Logging ───────────────────────────────────────────────────────────────────
export type { LogEntry, LogLevel, Logger } from './logging/logger.js';
export { createLogger } from './logging/logger.js';

export {
  generateCorrelationId,
  getCorrelationId,
  runWithCorrelationId,
} from './logging/correlation.js';

export {
  DEFAULT_SENSITIVE_FIELDS,
  maskPii,
  redactSensitiveFields,
} from './logging/masking.js';

// ── Errors ────────────────────────────────────────────────────────────────────
export {
  AppError,
  BadRequestError,
  ConflictError,
  ForbiddenError,
  InternalServerError,
  NotFoundError,
  RateLimitError,
  UnauthorizedError,
  isAppError,
} from './errors/http-errors.js';

export { errorMiddleware } from './errors/error-middleware.js';
export { mapPrismaError } from './errors/prisma-errors.js';
export { registerProcessHandlers } from './errors/process-handlers.js';

// ── Validation ────────────────────────────────────────────────────────────────
export type { AjvSchema, ValidationTarget } from './validation/validate.js';
export {
  validate,
  validateBody,
  validateParams,
  validateQuery,
} from './validation/validate.js';

export type { FieldError } from './validation/error-formatter.js';
export { formatValidationErrors } from './validation/error-formatter.js';

export {
  dateSchema,
  datetimeSchema,
  emailSchema,
  enumSchema,
  nonEmptyStringSchema,
  nonNegativeIntegerSchema,
  paginationSchema,
  percentageSchema,
  positiveIntegerSchema,
  timeRangeSchema,
  uuidSchema,
} from './validation/schemas.js';

// ── Common utilities ──────────────────────────────────────────────────────────
export { TokenCache } from './common/auth/TokenCache.js';
export type { RetryOptions } from './common/http/retry.js';
export { sleep, withRetry } from './common/http/retry.js';

// ── Opsera integration ────────────────────────────────────────────────────────
export type { AuthHeaders, AuthProvider, CredentialValidationResult, OAuthErrorResponse, OAuthTokenResponse, OrgInfo } from './integration/opsera/auth/types.js';
export { AuthMode } from './integration/opsera/auth/types.js';
export { ApiKeyAuthProvider } from './integration/opsera/auth/ApiKeyAuthProvider.js';
export { OAuthAuthProvider } from './integration/opsera/auth/OAuthAuthProvider.js';
export { OpseraAuthService } from './integration/opsera/auth/OpseraAuthService.js';

export type { PaginatedResponse, Pipeline, PipelineConfig, PipelineListFilters, PipelineRun, PipelineStep, TriggerPipelineParams, ToolRegistryEntry, OpseraErrorBody } from './integration/opsera/client/types.js';
export { PipelineStatus } from './integration/opsera/client/types.js';
export { OpseraApiError, OpseraAuthError, isOpseraApiError, isOpseraAuthError } from './integration/opsera/client/OpseraApiError.js';
export { OpseraApiClient } from './integration/opsera/client/OpseraApiClient.js';
