import { createLogger } from '../../logging/logger.js';

const logger = createLogger('cardinality-guard');

const DEFAULT_THRESHOLD = 500;

const labelCounts = new Map<string, Set<string>>();

export interface CardinalityGuardOptions {
  threshold?: number;
}

/**
 * Tracks unique label combinations per metric and warns when the cardinality
 * threshold is exceeded. Prevents unbounded metric label explosion.
 */
export function checkCardinality(
  metricName: string,
  labels: Record<string, string | number>,
  options: CardinalityGuardOptions = {},
): void {
  const threshold = options.threshold ?? DEFAULT_THRESHOLD;
  const labelKey = JSON.stringify(labels);

  let labelSet = labelCounts.get(metricName);
  if (labelSet === undefined) {
    labelSet = new Set<string>();
    labelCounts.set(metricName, labelSet);
  }

  labelSet.add(labelKey);

  if (labelSet.size > threshold) {
    logger.warn('Metric cardinality threshold exceeded', {
      metric: metricName,
      uniqueCombinations: labelSet.size,
      threshold,
    });
  }
}

/**
 * Resets cardinality tracking state. Use in tests to avoid cross-test pollution.
 */
export function resetCardinalityStateForTests(): void {
  labelCounts.clear();
}

/**
 * Returns the current unique label combination count for a metric.
 */
export function getCardinalityCount(metricName: string): number {
  return labelCounts.get(metricName)?.size ?? 0;
}
