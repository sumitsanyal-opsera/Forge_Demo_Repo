import { render, screen, within } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { DetectionStateMachine } from '../components/pipeline/DetectionStateMachine.js';
import type { DetectionState } from '../types/pipeline.js';
import { DETECTION_STATE_ORDER, DETECTION_STATE_LABELS } from '../types/pipeline.js';

function getNodes() {
  return screen.getAllByRole('listitem');
}

describe('DetectionStateMachine', () => {
  describe('renders five state nodes', () => {
    it('always renders 5 nodes regardless of current state', () => {
      render(<DetectionStateMachine currentState="monitoring" />);
      expect(getNodes()).toHaveLength(5);
    });

    it('renders all five labels', () => {
      render(<DetectionStateMachine currentState="monitoring" />);
      for (const label of Object.values(DETECTION_STATE_LABELS)) {
        expect(screen.getByText(label)).toBeInTheDocument();
      }
    });
  });

  describe('state: monitoring (first state)', () => {
    it('the first node is active', () => {
      render(<DetectionStateMachine currentState="monitoring" />);
      const nodes = getNodes();
      expect(nodes[0]).toHaveAttribute('data-variant', 'active');
    });

    it('all remaining nodes are inactive', () => {
      render(<DetectionStateMachine currentState="monitoring" />);
      const nodes = getNodes();
      for (let i = 1; i < 5; i++) {
        expect(nodes[i]).toHaveAttribute('data-variant', 'inactive');
      }
    });

    it('no node is completed', () => {
      render(<DetectionStateMachine currentState="monitoring" />);
      getNodes().forEach((n) =>
        expect(n).not.toHaveAttribute('data-variant', 'completed'),
      );
    });
  });

  describe('state: at_risk (second state)', () => {
    it('monitoring node is completed', () => {
      render(<DetectionStateMachine currentState="at_risk" />);
      const nodes = getNodes();
      expect(nodes[0]).toHaveAttribute('data-variant', 'completed');
    });

    it('at_risk node is active', () => {
      render(<DetectionStateMachine currentState="at_risk" />);
      const nodes = getNodes();
      expect(nodes[1]).toHaveAttribute('data-variant', 'active');
    });

    it('remaining nodes are inactive', () => {
      render(<DetectionStateMachine currentState="at_risk" />);
      const nodes = getNodes();
      for (let i = 2; i < 5; i++) {
        expect(nodes[i]).toHaveAttribute('data-variant', 'inactive');
      }
    });
  });

  describe('state: confirmed_stuck (fourth state)', () => {
    it('first three nodes are completed', () => {
      render(<DetectionStateMachine currentState="confirmed_stuck" />);
      const nodes = getNodes();
      for (let i = 0; i < 3; i++) {
        expect(nodes[i]).toHaveAttribute('data-variant', 'completed');
      }
    });

    it('confirmed_stuck node is active', () => {
      render(<DetectionStateMachine currentState="confirmed_stuck" />);
      const nodes = getNodes();
      expect(nodes[3]).toHaveAttribute('data-variant', 'active');
    });

    it('resolved node is inactive', () => {
      render(<DetectionStateMachine currentState="confirmed_stuck" />);
      const nodes = getNodes();
      expect(nodes[4]).toHaveAttribute('data-variant', 'inactive');
    });
  });

  describe('state: resolved (all completed)', () => {
    it('all five nodes show completed or active — resolved is the terminal active state', () => {
      render(<DetectionStateMachine currentState="resolved" />);
      const nodes = getNodes();
      // All 4 before resolved are completed; resolved itself is active
      for (let i = 0; i < 4; i++) {
        expect(nodes[i]).toHaveAttribute('data-variant', 'completed');
      }
      expect(nodes[4]).toHaveAttribute('data-variant', 'active');
    });

    it('no node is inactive in resolved state', () => {
      render(<DetectionStateMachine currentState="resolved" />);
      getNodes().forEach((n) =>
        expect(n).not.toHaveAttribute('data-variant', 'inactive'),
      );
    });
  });

  describe('accessibility', () => {
    it('has aria-label for the section', () => {
      render(<DetectionStateMachine currentState="monitoring" />);
      expect(
        screen.getByRole('region', { name: /detection state machine/i }),
      ).toBeInTheDocument();
    });

    it('active node aria-label mentions current state', () => {
      render(<DetectionStateMachine currentState="potentially_stuck" />);
      expect(
        screen.getByRole('listitem', { name: /potentially stuck.*current state/i }),
      ).toBeInTheDocument();
    });

    it('completed node aria-label mentions completed', () => {
      render(<DetectionStateMachine currentState="at_risk" />);
      expect(
        screen.getByRole('listitem', { name: /monitoring.*completed/i }),
      ).toBeInTheDocument();
    });
  });

  describe('all states parametric check', () => {
    it.each(DETECTION_STATE_ORDER as DetectionState[])(
      'current state %s renders exactly 1 active node',
      (state) => {
        render(<DetectionStateMachine currentState={state} />);
        const active = getNodes().filter(
          (n) => n.getAttribute('data-variant') === 'active',
        );
        expect(active).toHaveLength(1);
      },
    );
  });
});
