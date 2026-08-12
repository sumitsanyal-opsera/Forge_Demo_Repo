import { useParams } from 'react-router-dom';
import { usePipelineDetail } from '../hooks/usePipelineDetail.js';
import { DetailHeader } from '../components/pipeline/DetailHeader.js';
import { DetectionStateMachine } from '../components/pipeline/DetectionStateMachine.js';
import { ExecutionMetrics } from '../components/pipeline/ExecutionMetrics.js';
import { ExecutionDetailsTabs } from '../components/pipeline/ExecutionDetailsTabs.js';

function LoadingSkeleton() {
  const bar = (w: string, h = 16) => (
    <div
      aria-hidden="true"
      style={{
        width: w,
        height: h,
        borderRadius: 4,
        background: '#e5e7eb',
        animation: 'pulse 1.5s ease-in-out infinite',
      }}
    />
  );
  return (
    <div data-testid="loading-skeleton" aria-label="Loading pipeline details" style={{ padding: 24 }}>
      {bar('60%', 28)}
      <div style={{ marginTop: 12, display: 'flex', gap: 12 }}>
        {bar('120px')} {bar('160px')} {bar('140px')}
      </div>
      <div style={{ marginTop: 24, height: 100, background: '#f3f4f6', borderRadius: 8 }} />
      <div style={{ marginTop: 24, display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 12 }}>
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} style={{ height: 80, background: '#f3f4f6', borderRadius: 8 }} />
        ))}
      </div>
    </div>
  );
}

function ErrorState({ message }: { message: string }) {
  return (
    <div
      role="alert"
      data-testid="error-state"
      style={{
        padding: 32,
        textAlign: 'center',
        color: '#b91c1c',
        background: '#fef2f2',
        borderRadius: 8,
        border: '1px solid #fca5a5',
        margin: 24,
      }}
    >
      <p style={{ fontWeight: 600, margin: '0 0 4px' }}>Failed to load pipeline details</p>
      <p style={{ margin: 0, fontSize: 13, color: '#dc2626' }}>{message}</p>
    </div>
  );
}

function NotFoundState({ id }: { id: string }) {
  return (
    <div
      data-testid="not-found-state"
      style={{
        padding: 32,
        textAlign: 'center',
        color: '#374151',
        margin: 24,
      }}
    >
      <p style={{ fontWeight: 600, fontSize: 18, margin: '0 0 8px' }}>Pipeline not found</p>
      <p style={{ margin: 0, fontSize: 14, color: '#6b7280' }}>
        No pipeline execution with ID <code>{id}</code> was found.
      </p>
    </div>
  );
}

export function PipelineDetailPage() {
  const { id = '' } = useParams<{ id: string }>();
  const { data, loading, error, notFound } = usePipelineDetail(id);

  if (loading) return <LoadingSkeleton />;
  if (error !== null) return <ErrorState message={error} />;
  if (notFound) return <NotFoundState id={id} />;
  if (data === null) return null;

  return (
    <main
      data-testid="pipeline-detail-page"
      style={{ padding: 24, maxWidth: 1100, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 24 }}
    >
      <DetailHeader pipeline={data} />
      <DetectionStateMachine currentState={data.detectionState} />
      <ExecutionMetrics metrics={data.metrics} />
      <ExecutionDetailsTabs steps={data.steps} metadataComponents={data.metadataComponents} />
    </main>
  );
}
