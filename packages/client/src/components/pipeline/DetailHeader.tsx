import type { PipelineDetail } from '../../types/pipeline.js';
import { DETECTION_STATE_LABELS, DETECTION_STATE_COLORS } from '../../types/pipeline.js';

interface DetailHeaderProps {
  pipeline: PipelineDetail;
}

const BADGE_TEXT_COLOR: Record<string, string> = {
  monitoring: '#1d4ed8',
  at_risk: '#92400e',
  potentially_stuck: '#9a3412',
  confirmed_stuck: '#991b1b',
  resolved: '#14532d',
};

function formatStartTime(iso: string): string {
  try {
    return new Date(iso).toLocaleString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return iso;
  }
}

export function DetailHeader({ pipeline }: DetailHeaderProps) {
  const { name, orgName, deployId, startTime, detectionState } = pipeline;
  const stateLabel = DETECTION_STATE_LABELS[detectionState];
  const stateColor = DETECTION_STATE_COLORS[detectionState];
  const badgeTextColor = BADGE_TEXT_COLOR[detectionState] ?? stateColor;

  return (
    <header style={{ marginBottom: 24 }}>
      {/* Title row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
        <h1
          style={{ margin: 0, fontSize: 22, fontWeight: 700, color: '#111827' }}
          data-testid="pipeline-name"
        >
          {name}
        </h1>
        <span
          data-testid="detection-state-badge"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            padding: '3px 10px',
            borderRadius: 999,
            fontSize: 12,
            fontWeight: 600,
            background: `${stateColor}22`,
            color: badgeTextColor,
            border: `1px solid ${stateColor}55`,
          }}
        >
          {stateLabel}
        </span>
      </div>

      {/* Meta info row */}
      <div
        style={{
          display: 'flex',
          gap: 20,
          marginTop: 8,
          flexWrap: 'wrap',
          color: '#6b7280',
          fontSize: 13,
        }}
      >
        <span data-testid="org-name">
          <strong>Org:</strong> {orgName}
        </span>
        <span data-testid="deploy-id">
          <strong>Deploy ID:</strong> {deployId}
        </span>
        <span data-testid="start-time">
          <strong>Started:</strong> {formatStartTime(startTime)}
        </span>
      </div>

      {/* Deferred action buttons (P3 scope — visible but disabled) */}
      <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
        <button
          disabled
          title="Resume pipeline — coming soon"
          aria-label="Resume pipeline (coming soon)"
          style={{
            padding: '6px 14px',
            borderRadius: 6,
            border: '1px solid #d1d5db',
            background: '#f9fafb',
            color: '#9ca3af',
            cursor: 'not-allowed',
            fontSize: 13,
          }}
        >
          Resume
        </button>
        <button
          disabled
          title="Cancel pipeline — coming soon"
          aria-label="Cancel pipeline (coming soon)"
          style={{
            padding: '6px 14px',
            borderRadius: 6,
            border: '1px solid #d1d5db',
            background: '#f9fafb',
            color: '#9ca3af',
            cursor: 'not-allowed',
            fontSize: 13,
          }}
        >
          Cancel
        </button>
      </div>
    </header>
  );
}
