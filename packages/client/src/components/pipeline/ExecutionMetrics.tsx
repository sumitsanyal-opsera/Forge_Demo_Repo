import type { ExecutionMetrics as ExecutionMetricsType } from '../../types/pipeline.js';
import { MetricCard } from './MetricCard.js';
import type { MetricHighlight } from './MetricCard.js';

interface ExecutionMetricsProps {
  metrics: ExecutionMetricsType;
}

function msToDisplay(ms: number | null): string | null {
  if (ms === null) return null;
  if (ms < 60_000) return `${Math.round(ms / 1000)}`;
  const mins = Math.floor(ms / 60_000);
  const secs = Math.round((ms % 60_000) / 1000);
  return secs > 0 ? `${mins}m ${secs}s` : `${mins}m`;
}

function msUnit(ms: number | null): string | undefined {
  if (ms === null) return undefined;
  return ms < 60_000 ? 's' : undefined;
}

function getDurationHighlight(
  valueMs: number,
  p50: number | null,
  p90: number | null,
): MetricHighlight {
  if (p50 === null || p90 === null) return undefined;
  if (valueMs > p90) return 'red';
  if (valueMs > p50) return 'amber';
  return 'green';
}

export function ExecutionMetrics({ metrics }: ExecutionMetricsProps) {
  const { currentDurationMs, p50BaselineMs, p90BaselineMs, p99BaselineMs, staleDurationMs, componentCount } =
    metrics;

  const durationHighlight = getDurationHighlight(
    currentDurationMs,
    p50BaselineMs,
    p90BaselineMs,
  );

  return (
    <section aria-label="Execution metrics">
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(160px, 1fr))',
          gap: 12,
        }}
      >
        <MetricCard
          label="Current Duration"
          value={msToDisplay(currentDurationMs)}
          unit={msUnit(currentDurationMs)}
          highlight={durationHighlight}
        />
        <MetricCard
          label="P50 Baseline"
          value={msToDisplay(p50BaselineMs)}
          unit={msUnit(p50BaselineMs)}
        />
        <MetricCard
          label="P90 Baseline"
          value={msToDisplay(p90BaselineMs)}
          unit={msUnit(p90BaselineMs)}
        />
        <MetricCard
          label="P99 Baseline"
          value={msToDisplay(p99BaselineMs)}
          unit={msUnit(p99BaselineMs)}
        />
        <MetricCard
          label="Stale Duration"
          value={msToDisplay(staleDurationMs)}
          unit={msUnit(staleDurationMs)}
        />
        <MetricCard
          label="Component Count"
          value={componentCount}
        />
      </div>
    </section>
  );
}
