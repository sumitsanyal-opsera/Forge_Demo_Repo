import type { DetectionState } from '../../types/pipeline.js';
import {
  DETECTION_STATE_ORDER,
  DETECTION_STATE_LABELS,
} from '../../types/pipeline.js';
import { StateNode } from './StateNode.js';

interface DetectionStateMachineProps {
  currentState: DetectionState;
}

function StateArrow() {
  return (
    <svg
      width="32"
      height="20"
      viewBox="0 0 32 20"
      aria-hidden="true"
      style={{ flexShrink: 0, alignSelf: 'flex-start', marginTop: 12 }}
    >
      <line
        x1="2"
        y1="10"
        x2="26"
        y2="10"
        stroke="#9ca3af"
        strokeWidth="1.5"
      />
      <polyline
        points="22,5 28,10 22,15"
        fill="none"
        stroke="#9ca3af"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function DetectionStateMachine({ currentState }: DetectionStateMachineProps) {
  const currentIndex = DETECTION_STATE_ORDER.indexOf(currentState);

  return (
    <section
      aria-label="Detection state machine"
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        gap: 0,
        padding: '20px 16px',
        background: 'white',
        borderRadius: 8,
        border: '1px solid #e5e7eb',
        overflowX: 'auto',
      }}
    >
      <ol
        role="list"
        style={{
          display: 'flex',
          alignItems: 'flex-start',
          listStyle: 'none',
          margin: 0,
          padding: 0,
          gap: 0,
        }}
      >
        {DETECTION_STATE_ORDER.map((state, index) => {
          const variant =
            index < currentIndex
              ? 'completed'
              : index === currentIndex
                ? 'active'
                : 'inactive';

          return (
            <li
              key={state}
              style={{ display: 'flex', alignItems: 'flex-start' }}
            >
              <StateNode
                state={state}
                label={DETECTION_STATE_LABELS[state]}
                variant={variant}
              />
              {index < DETECTION_STATE_ORDER.length - 1 && <StateArrow />}
            </li>
          );
        })}
      </ol>
    </section>
  );
}
