export type MetricHighlight = 'green' | 'amber' | 'red' | undefined;

interface MetricCardProps {
  label: string;
  value: string | number | null;
  unit?: string;
  highlight?: MetricHighlight;
}

const HIGHLIGHT_STYLES: Record<NonNullable<MetricHighlight>, React.CSSProperties> = {
  green: { background: '#f0fdf4', borderColor: '#86efac' },
  amber: { background: '#fffbeb', borderColor: '#fcd34d' },
  red: { background: '#fef2f2', borderColor: '#fca5a5' },
};

const HIGHLIGHT_VALUE_COLOR: Record<NonNullable<MetricHighlight>, string> = {
  green: '#15803d',
  amber: '#92400e',
  red: '#b91c1c',
};

export function MetricCard({ label, value, unit, highlight }: MetricCardProps) {
  const highlightStyle = highlight !== undefined ? HIGHLIGHT_STYLES[highlight] : {};
  const valueColor =
    highlight !== undefined ? HIGHLIGHT_VALUE_COLOR[highlight] : '#111827';

  const displayValue = value === null ? 'Pending' : value;

  return (
    <div
      style={{
        padding: '16px',
        borderRadius: 8,
        border: '1px solid #e5e7eb',
        background: 'white',
        display: 'flex',
        flexDirection: 'column',
        gap: 4,
        ...highlightStyle,
      }}
      data-highlight={highlight}
    >
      <span
        style={{ fontSize: 12, color: '#6b7280', textTransform: 'uppercase', letterSpacing: '0.05em' }}
      >
        {label}
      </span>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
        <span
          style={{ fontSize: 24, fontWeight: 700, color: valueColor }}
          aria-label={`${label}: ${displayValue}${unit ? ` ${unit}` : ''}`}
        >
          {displayValue}
        </span>
        {unit !== undefined && value !== null && (
          <span style={{ fontSize: 13, color: '#6b7280' }}>{unit}</span>
        )}
      </div>
    </div>
  );
}
