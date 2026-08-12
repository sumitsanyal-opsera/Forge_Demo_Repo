import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { StateNode } from '../components/pipeline/StateNode.js';

describe('StateNode', () => {
  describe('inactive variant', () => {
    it('renders the label', () => {
      render(
        <StateNode state="monitoring" label="Monitoring" variant="inactive" />,
      );
      expect(screen.getByText('Monitoring')).toBeInTheDocument();
    });

    it('has aria-label describing state as not yet reached', () => {
      render(
        <StateNode state="monitoring" label="Monitoring" variant="inactive" />,
      );
      expect(
        screen.getByRole('listitem', { name: /not yet reached/i }),
      ).toBeInTheDocument();
    });

    it('has data-variant=inactive', () => {
      render(
        <StateNode state="monitoring" label="Monitoring" variant="inactive" />,
      );
      expect(screen.getByRole('listitem')).toHaveAttribute('data-variant', 'inactive');
    });
  });

  describe('active variant', () => {
    it('has aria-label describing state as current state', () => {
      render(
        <StateNode state="at_risk" label="At Risk" variant="active" />,
      );
      expect(
        screen.getByRole('listitem', { name: /current state/i }),
      ).toBeInTheDocument();
    });

    it('has data-variant=active', () => {
      render(<StateNode state="at_risk" label="At Risk" variant="active" />);
      expect(screen.getByRole('listitem')).toHaveAttribute('data-variant', 'active');
    });

    it('has data-state matching the state prop', () => {
      render(<StateNode state="at_risk" label="At Risk" variant="active" />);
      expect(screen.getByRole('listitem')).toHaveAttribute('data-state', 'at_risk');
    });
  });

  describe('completed variant', () => {
    it('has aria-label describing state as completed', () => {
      render(
        <StateNode state="monitoring" label="Monitoring" variant="completed" />,
      );
      expect(
        screen.getByRole('listitem', { name: /completed/i }),
      ).toBeInTheDocument();
    });

    it('has data-variant=completed', () => {
      render(
        <StateNode state="monitoring" label="Monitoring" variant="completed" />,
      );
      expect(screen.getByRole('listitem')).toHaveAttribute(
        'data-variant',
        'completed',
      );
    });

    it('renders a checkmark SVG for completed state', () => {
      const { container } = render(
        <StateNode state="monitoring" label="Monitoring" variant="completed" />,
      );
      expect(container.querySelector('svg polyline')).toBeInTheDocument();
    });
  });

  describe('all five states render', () => {
    it.each([
      ['monitoring', 'Monitoring'],
      ['at_risk', 'At Risk'],
      ['potentially_stuck', 'Potentially Stuck'],
      ['confirmed_stuck', 'Confirmed Stuck'],
      ['resolved', 'Resolved'],
    ] as const)('renders %s state with label %s', (state, label) => {
      render(<StateNode state={state} label={label} variant="inactive" />);
      expect(screen.getByText(label)).toBeInTheDocument();
    });
  });
});
