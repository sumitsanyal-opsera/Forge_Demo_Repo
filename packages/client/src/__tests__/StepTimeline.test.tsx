import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { StepTimeline } from '../components/pipeline/StepTimeline.js';
import type { PipelineStep } from '../types/pipeline.js';

function makeStep(overrides: Partial<PipelineStep> = {}): PipelineStep {
  return {
    id: 'step-1',
    name: 'Deploy Components',
    status: 'success',
    startTime: '2024-06-01T10:00:00Z',
    durationMs: 30_000,
    ...overrides,
  };
}

describe('StepTimeline', () => {
  describe('empty state', () => {
    it('shows empty state message when steps is empty array', () => {
      render(<StepTimeline steps={[]} />);
      expect(screen.getByTestId('empty-timeline')).toBeInTheDocument();
    });

    it('does not render any timeline items for empty steps', () => {
      render(<StepTimeline steps={[]} />);
      expect(screen.queryAllByTestId('timeline-item')).toHaveLength(0);
    });
  });

  describe('single step', () => {
    it('renders 1 timeline item', () => {
      render(<StepTimeline steps={[makeStep()]} />);
      expect(screen.getAllByTestId('timeline-item')).toHaveLength(1);
    });

    it('renders step name', () => {
      render(<StepTimeline steps={[makeStep({ name: 'Run Apex Tests' })]} />);
      expect(screen.getByText('Run Apex Tests')).toBeInTheDocument();
    });

    it('renders formatted duration', () => {
      render(<StepTimeline steps={[makeStep({ durationMs: 30_000 })]} />);
      expect(screen.getByText('30.0s')).toBeInTheDocument();
    });

    it('renders duration bar for step with durationMs', () => {
      render(<StepTimeline steps={[makeStep({ durationMs: 30_000 })]} />);
      expect(screen.getByTestId('duration-bar')).toBeInTheDocument();
    });

    it('does not render duration bar when durationMs is null', () => {
      render(<StepTimeline steps={[makeStep({ durationMs: null })]} />);
      expect(screen.queryByTestId('duration-bar')).not.toBeInTheDocument();
    });
  });

  describe('multiple steps', () => {
    const steps: PipelineStep[] = [
      makeStep({ id: 's1', name: 'Validate Metadata', durationMs: 10_000, status: 'success' }),
      makeStep({ id: 's2', name: 'Deploy Components', durationMs: 60_000, status: 'running' }),
      makeStep({ id: 's3', name: 'Run Apex Tests', durationMs: null, status: 'pending' }),
    ];

    it('renders 3 timeline items for 3 steps', () => {
      render(<StepTimeline steps={steps} />);
      expect(screen.getAllByTestId('timeline-item')).toHaveLength(3);
    });

    it('renders all step names', () => {
      render(<StepTimeline steps={steps} />);
      expect(screen.getByText('Validate Metadata')).toBeInTheDocument();
      expect(screen.getByText('Deploy Components')).toBeInTheDocument();
      expect(screen.getByText('Run Apex Tests')).toBeInTheDocument();
    });

    it('longest step has 100% bar width', () => {
      render(<StepTimeline steps={steps} />);
      const bars = screen.getAllByTestId('duration-bar');
      const widths = bars.map((b) => b.style.width);
      expect(widths).toContain('100%');
    });

    it('shorter step has proportionally smaller bar width', () => {
      render(<StepTimeline steps={steps} />);
      const bars = screen.getAllByTestId('duration-bar');
      // 10000ms / 60000ms * 100 = ~17%
      const smallBar = bars.find((b) => b.style.width !== '100%');
      expect(smallBar).toBeTruthy();
    });
  });

  describe('five steps', () => {
    it('renders 5 items', () => {
      const steps = Array.from({ length: 5 }, (_, i) =>
        makeStep({ id: `s${i}`, name: `Step ${i + 1}`, durationMs: (i + 1) * 10_000 }),
      );
      render(<StepTimeline steps={steps} />);
      expect(screen.getAllByTestId('timeline-item')).toHaveLength(5);
    });
  });

  describe('step statuses', () => {
    it.each(['pending', 'running', 'success', 'failed', 'skipped'] as const)(
      'renders status %s without crashing',
      (status) => {
        render(
          <StepTimeline
            steps={[makeStep({ status, durationMs: status === 'pending' ? null : 5_000 })]}
          />,
        );
        expect(screen.getByTestId('timeline-item')).toBeInTheDocument();
      },
    );
  });

  describe('duration formatting', () => {
    it('formats milliseconds under 1s', () => {
      render(<StepTimeline steps={[makeStep({ durationMs: 500 })]} />);
      expect(screen.getByText('500ms')).toBeInTheDocument();
    });

    it('formats minutes and seconds', () => {
      render(<StepTimeline steps={[makeStep({ durationMs: 90_500 })]} />);
      expect(screen.getByText('1m 31s')).toBeInTheDocument();
    });

    it('shows dash for null duration', () => {
      render(<StepTimeline steps={[makeStep({ durationMs: null })]} />);
      expect(screen.getByText('—')).toBeInTheDocument();
    });
  });
});
