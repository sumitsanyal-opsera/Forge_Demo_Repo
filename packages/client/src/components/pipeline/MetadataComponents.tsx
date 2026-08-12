import type { MetadataComponent, ComponentDeployStatus } from '../../types/pipeline.js';

interface MetadataComponentsProps {
  components: MetadataComponent[];
}

const STATUS_COLORS: Record<ComponentDeployStatus, string> = {
  deployed: '#16a34a',
  pending: '#d97706',
  failed: '#dc2626',
};

interface ComponentGroup {
  type: string;
  items: MetadataComponent[];
}

function groupByType(components: MetadataComponent[]): ComponentGroup[] {
  const map = new Map<string, MetadataComponent[]>();
  for (const c of components) {
    const group = map.get(c.type);
    if (group) {
      group.push(c);
    } else {
      map.set(c.type, [c]);
    }
  }
  return Array.from(map.entries()).map(([type, items]) => ({ type, items }));
}

interface ComponentCardProps {
  component: MetadataComponent;
}

function ComponentCard({ component }: ComponentCardProps) {
  const statusColor = STATUS_COLORS[component.status];
  return (
    <div
      data-testid="component-card"
      style={{
        padding: '10px 14px',
        border: '1px solid #e5e7eb',
        borderRadius: 6,
        background: 'white',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: 8,
      }}
    >
      <span style={{ fontSize: 13, color: '#374151', fontWeight: 500 }}>
        {component.name}
      </span>
      <span
        style={{
          fontSize: 11,
          fontWeight: 600,
          color: statusColor,
          textTransform: 'uppercase',
        }}
        aria-label={`Status: ${component.status}`}
      >
        {component.status}
      </span>
    </div>
  );
}

export function MetadataComponents({ components }: MetadataComponentsProps) {
  if (components.length === 0) {
    return (
      <div
        style={{ padding: '32px 0', textAlign: 'center', color: '#9ca3af', fontSize: 14 }}
        data-testid="empty-metadata"
      >
        No metadata components found for this deployment.
      </div>
    );
  }

  const groups = groupByType(components);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      {groups.map(({ type, items }) => (
        <section key={type} aria-label={`${type} components`} data-testid="component-group">
          <h3
            style={{
              margin: '0 0 10px',
              fontSize: 13,
              fontWeight: 600,
              color: '#374151',
              textTransform: 'uppercase',
              letterSpacing: '0.05em',
              display: 'flex',
              alignItems: 'center',
              gap: 8,
            }}
          >
            {type}
            <span
              style={{
                background: '#f3f4f6',
                color: '#6b7280',
                borderRadius: 999,
                padding: '1px 7px',
                fontSize: 11,
                fontWeight: 600,
              }}
            >
              {items.length}
            </span>
          </h3>
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))',
              gap: 8,
            }}
          >
            {items.map((c) => (
              <ComponentCard key={c.name} component={c} />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}
