/**
 * HTTP retry utility with exponential backoff and jitter.
 *
 * Extracted from the integration layer so both the Opsera and Salesforce
 * connectors can share identical retry semantics.
 */

export interface RetryOptions {
  /** Maximum number of retry attempts (not including the initial call). */
  maxRetries: number;
  /** Base delay for the first retry in milliseconds. */
  baseDelayMs: number;
  /** Upper bound on computed delay in milliseconds. */
  maxDelayMs: number;
  /** Maximum random jitter added to each delay in milliseconds. Defaults to baseDelayMs. */
  jitterMs?: number;
}

export type OnRetryCallback = (attempt: number, delayMs: number, error: unknown) => void;

/**
 * Executes `fn` and retries on failure using exponential backoff with jitter.
 *
 * The caller is responsible for deciding which errors are retryable by
 * wrapping non-retryable errors before calling this utility (e.g., re-throwing
 * immediately from within `fn` after inspecting the error code).
 *
 * @param fn        Async operation to execute and potentially retry.
 * @param options   Backoff configuration.
 * @param onRetry   Optional callback invoked before each retry (useful for logging).
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions,
  onRetry?: OnRetryCallback,
): Promise<T> {
  let lastError: unknown;

  for (let attempt = 0; attempt <= options.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt >= options.maxRetries) break;

      const delayMs = computeBackoff(attempt, options);
      onRetry?.(attempt + 1, delayMs, error);
      await sleep(delayMs);
    }
  }

  // Re-throw the last error — it is guaranteed to be set because the loop
  // runs at least once.
  throw lastError;
}

/**
 * Computes the next backoff delay:
 *   delay = min(baseDelay * 2^attempt, maxDelay) + random(0, jitter)
 */
function computeBackoff(attempt: number, options: RetryOptions): number {
  const exponential = Math.min(
    options.baseDelayMs * Math.pow(2, attempt),
    options.maxDelayMs,
  );
  const jitter = Math.random() * (options.jitterMs ?? options.baseDelayMs);
  return Math.floor(exponential + jitter);
}

/** Promise-based sleep. */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
