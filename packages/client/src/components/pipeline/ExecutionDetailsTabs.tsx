import { useState } from 'react';
import type { PipelineStep, MetadataComponent } from '../../types/pipeline.js';
import { StepTimeline } from './StepTimeline.js';
import { MetadataComponents } from './MetadataComponents.js';

interface ExecutionDetailsTabsProps {
  steps: PipelineStep[];
  metadataComponents: MetadataComponent[];
}

type TabId = 'timeline' | 'metadata';

interface TabConfig {
  id: TabId;
  label: string;
}

const TABS: TabConfig[] = [
  { id: 'timeline', label: 'Timeline' },
  { id: 'metadata', label: 'Metadata' },
];

export function ExecutionDetailsTabs({ steps, metadataComponents }: ExecutionDetailsTabsProps) {
  const [activeTab, setActiveTab] = useState<TabId>('timeline');

  return (
    <section aria-label="Execution details">
      {/* TabGroup */}
      <div
        role="tablist"
        aria-label="Execution details tabs"
        style={{
          display: 'flex',
          borderBottom: '2px solid #e5e7eb',
          marginBottom: 20,
          gap: 0,
        }}
      >
        {TABS.map(({ id, label }) => {
          const isActive = activeTab === id;
          return (
            <button
              key={id}
              role="tab"
              id={`tab-${id}`}
              aria-selected={isActive}
              aria-controls={`panel-${id}`}
              onClick={() => setActiveTab(id)}
              style={{
                padding: '10px 20px',
                border: 'none',
                borderBottom: isActive ? '2px solid #2563eb' : '2px solid transparent',
                marginBottom: -2,
                background: 'none',
                cursor: 'pointer',
                fontSize: 14,
                fontWeight: isActive ? 600 : 400,
                color: isActive ? '#2563eb' : '#6b7280',
                transition: 'all 0.15s ease',
              }}
            >
              {label}
            </button>
          );
        })}
      </div>

      {/* Tab panels */}
      <div
        role="tabpanel"
        id="panel-timeline"
        aria-labelledby="tab-timeline"
        hidden={activeTab !== 'timeline'}
        data-testid="panel-timeline"
      >
        <StepTimeline steps={steps} />
      </div>
      <div
        role="tabpanel"
        id="panel-metadata"
        aria-labelledby="tab-metadata"
        hidden={activeTab !== 'metadata'}
        data-testid="panel-metadata"
      >
        <MetadataComponents components={metadataComponents} />
      </div>
    </section>
  );
}
