import type { DetectionState } from '../../types/pipeline.js';
import { DETECTION_STATE_COLORS } from '../../types/pipeline.js';

export type StateNodeVariant = 'inactive' | 'active' | 'completed';

interface StateNodeProps {
  state: DetectionState;
  label: string;
  variant: StateNodeVariant;
}

const SIZE = 44;
const FONT_SIZE = 11;

const checkmark = (
  <svg
    width="20"
    height="20"
    viewBox="0 0 20 20"
    aria-hidden="true"
    style={{ display: 'block' }}
  >
    <polyline
      points="4,10 8,15 16,5"
      stroke="white"
      strokeWidth="2.5"
      fill="none"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
);

export function StateNode({ state, label, variant }: StateNodeProps) {
  const isActive = variant === 'active';
  const isCompleted = variant === 'completed';
  const color = DETECTION_STATE_COLORS[state];

  const circleStyle: React.CSSProperties = {
    width: SIZE,
    height: SIZE,
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    border: isActive || isCompleted ? `3px solid ${color}` : '2px solid #9ca3af',
    backgroundColor: isActive || isCompleted ? color : '#f3f4f6',
    transition: 'all 0.2s ease',
    flexShrink: 0,
  };

  const labelStyle: React.CSSProperties = {
    marginTop: 6,
    fontSize: FONT_SIZE,
    textAlign: 'center',
    color: isActive ? color : isCompleted ? '#374151' : '#9ca3af',
    fontWeight: isActive ? 700 : 400,
    maxWidth: 72,
    lineHeight: '1.3',
  };

  const ariaLabel = `${label} — ${
    isActive ? 'current state' : isCompleted ? 'completed' : 'not yet reached'
  }`;

  return (
    <div
      style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}
      role="listitem"
      aria-label={ariaLabel}
      data-state={state}
      data-variant={variant}
    >
      <div style={circleStyle}>
        {isCompleted ? (
          checkmark
        ) : (
          <span
            style={{
              width: 10,
              height: 10,
              borderRadius: '50%',
              backgroundColor: isActive ? 'white' : '#9ca3af',
            }}
          />
        )}
      </div>
      <span style={labelStyle}>{label}</span>
    </div>
  );
}
