import type { PipelineStep, StepStatus } from '../../types/pipeline.js';

interface StepTimelineProps {
  steps: PipelineStep[];
  maxDurationMs?: number;
}

const STATUS_COLORS: Record<StepStatus, string> = {
  pending: '#9ca3af',
  running: '#2563eb',
  success: '#16a34a',
  failed: '#dc2626',
  skipped: '#6b7280',
};

const STATUS_ICONS: Record<StepStatus, string> = {
  pending: '○',
  running: '◉',
  success: '✓',
  failed: '✗',
  skipped: '–',
};

function formatDuration(ms: number | null): string {
  if (ms === null) return '—';
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  const mins = Math.floor(ms / 60_000);
  const secs = Math.round((ms % 60_000) / 1000);
  return secs > 0 ? `${mins}m ${secs}s` : `${mins}m`;
}

function formatTime(iso: string | null): string {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  } catch {
    return iso;
  }
}

interface TimelineItemProps {
  step: PipelineStep;
  barWidthPct: number;
}

function TimelineItem({ step, barWidthPct }: TimelineItemProps) {
  const color = STATUS_COLORS[step.status];
  const icon = STATUS_ICONS[step.status];

  return (
    <li
      style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: '12px 0', borderBottom: '1px solid #f3f4f6' }}
      data-testid="timeline-item"
      data-step-id={step.id}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span
          style={{ color, fontSize: 16, width: 20, textAlign: 'center', flexShrink: 0 }}
          aria-label={`Status: ${step.status}`}
        >
          {icon}
        </span>
        <span style={{ fontWeight: 500, fontSize: 14, color: '#111827', flex: 1 }}>
          {step.name}
        </span>
        <span style={{ fontSize: 12, color: '#6b7280', flexShrink: 0 }}>
          {formatTime(step.startTime)}
        </span>
        <span style={{ fontSize: 12, color: '#374151', fontWeight: 500, flexShrink: 0, minWidth: 60, textAlign: 'right' }}>
          {formatDuration(step.durationMs)}
        </span>
      </div>

      {/* Proportional duration bar */}
      {step.durationMs !== null && (
        <div
          style={{
            marginLeft: 30,
            height: 4,
            borderRadius: 2,
            background: '#f3f4f6',
            overflow: 'hidden',
          }}
          aria-hidden="true"
        >
          <div
            data-testid="duration-bar"
            style={{
              height: '100%',
              width: `${barWidthPct}%`,
              background: color,
              borderRadius: 2,
              transition: 'width 0.3s ease',
            }}
          />
        </div>
      )}
    </li>
  );
}

export function StepTimeline({ steps, maxDurationMs }: StepTimelineProps) {
  if (steps.length === 0) {
    return (
      <div
        style={{ padding: '32px 0', textAlign: 'center', color: '#9ca3af', fontSize: 14 }}
        data-testid="empty-timeline"
      >
        No steps recorded for this execution.
      </div>
    );
  }

  const maxMs =
    maxDurationMs ??
    Math.max(...steps.map((s) => s.durationMs ?? 0), 1);

  return (
    <ol
      aria-label="Pipeline execution timeline"
      style={{ listStyle: 'none', margin: 0, padding: 0 }}
    >
      {steps.map((step) => (
        <TimelineItem
          key={step.id}
          step={step}
          barWidthPct={step.durationMs !== null ? Math.round((step.durationMs / maxMs) * 100) : 0}
        />
      ))}
    </ol>
  );
}
