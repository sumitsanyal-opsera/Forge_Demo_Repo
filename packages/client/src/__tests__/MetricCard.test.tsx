import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { MetricCard } from '../components/pipeline/MetricCard.js';
import { ExecutionMetrics } from '../components/pipeline/ExecutionMetrics.js';
import type { ExecutionMetrics as ExecutionMetricsType } from '../types/pipeline.js';

describe('MetricCard', () => {
  describe('renders label and value', () => {
    it('displays the label', () => {
      render(<MetricCard label="Current Duration" value="5m 30s" />);
      expect(screen.getByText('Current Duration')).toBeInTheDocument();
    });

    it('displays the value', () => {
      render(<MetricCard label="Current Duration" value="5m 30s" />);
      expect(screen.getByText('5m 30s')).toBeInTheDocument();
    });

    it('displays unit when provided', () => {
      render(<MetricCard label="P50" value={45} unit="s" />);
      expect(screen.getByText('s')).toBeInTheDocument();
    });

    it('displays Pending when value is null', () => {
      render(<MetricCard label="P50 Baseline" value={null} />);
      expect(screen.getByText('Pending')).toBeInTheDocument();
    });

    it('does not render unit when value is null', () => {
      render(<MetricCard label="P50 Baseline" value={null} unit="s" />);
      expect(screen.queryByText('s')).not.toBeInTheDocument();
    });
  });

  describe('threshold highlight', () => {
    it('has data-highlight=green for green highlight', () => {
      const { container } = render(
        <MetricCard label="Duration" value="2m" highlight="green" />,
      );
      expect(container.firstChild).toHaveAttribute('data-highlight', 'green');
    });

    it('has data-highlight=amber for amber highlight', () => {
      const { container } = render(
        <MetricCard label="Duration" value="4m" highlight="amber" />,
      );
      expect(container.firstChild).toHaveAttribute('data-highlight', 'amber');
    });

    it('has data-highlight=red for red highlight', () => {
      const { container } = render(
        <MetricCard label="Duration" value="8m" highlight="red" />,
      );
      expect(container.firstChild).toHaveAttribute('data-highlight', 'red');
    });

    it('has no data-highlight when highlight is undefined', () => {
      const { container } = render(
        <MetricCard label="P50 Baseline" value="3m" />,
      );
      expect(container.firstChild).not.toHaveAttribute('data-highlight');
    });
  });
});

describe('ExecutionMetrics (integration of MetricCard)', () => {
  const baseMetrics: ExecutionMetricsType = {
    currentDurationMs: 60_000,
    p50BaselineMs: 180_000,
    p90BaselineMs: 300_000,
    p99BaselineMs: 420_000,
    staleDurationMs: null,
    componentCount: 12,
  };

  it('renders six MetricCard sections', () => {
    render(<ExecutionMetrics metrics={baseMetrics} />);
    expect(screen.getByText('Current Duration')).toBeInTheDocument();
    expect(screen.getByText('P50 Baseline')).toBeInTheDocument();
    expect(screen.getByText('P90 Baseline')).toBeInTheDocument();
    expect(screen.getByText('P99 Baseline')).toBeInTheDocument();
    expect(screen.getByText('Stale Duration')).toBeInTheDocument();
    expect(screen.getByText('Component Count')).toBeInTheDocument();
  });

  it('Current Duration card is green when below P50', () => {
    // currentDurationMs=60000 < p50=180000 → green
    const { container } = render(<ExecutionMetrics metrics={baseMetrics} />);
    const cards = container.querySelectorAll('[data-highlight]');
    const greenCard = Array.from(cards).find((c) => c.getAttribute('data-highlight') === 'green');
    expect(greenCard).toBeTruthy();
  });

  it('Current Duration card is amber when between P50 and P90', () => {
    const metrics: ExecutionMetricsType = { ...baseMetrics, currentDurationMs: 200_000 };
    const { container } = render(<ExecutionMetrics metrics={metrics} />);
    const cards = container.querySelectorAll('[data-highlight]');
    const amberCard = Array.from(cards).find((c) => c.getAttribute('data-highlight') === 'amber');
    expect(amberCard).toBeTruthy();
  });

  it('Current Duration card is red when above P90', () => {
    const metrics: ExecutionMetricsType = { ...baseMetrics, currentDurationMs: 350_000 };
    const { container } = render(<ExecutionMetrics metrics={metrics} />);
    const cards = container.querySelectorAll('[data-highlight]');
    const redCard = Array.from(cards).find((c) => c.getAttribute('data-highlight') === 'red');
    expect(redCard).toBeTruthy();
  });

  it('no highlight when baselines are null', () => {
    const metrics: ExecutionMetricsType = {
      ...baseMetrics,
      p50BaselineMs: null,
      p90BaselineMs: null,
    };
    const { container } = render(<ExecutionMetrics metrics={metrics} />);
    expect(container.querySelectorAll('[data-highlight]')).toHaveLength(0);
  });

  it('Stale Duration shows Pending when null', () => {
    render(<ExecutionMetrics metrics={baseMetrics} />);
    // staleDurationMs is null in baseMetrics → Pending
    const pending = screen.getAllByText('Pending');
    expect(pending.length).toBeGreaterThanOrEqual(1);
  });

  it('Component Count shows the numeric value', () => {
    render(<ExecutionMetrics metrics={baseMetrics} />);
    expect(screen.getByText('12')).toBeInTheDocument();
  });
});
