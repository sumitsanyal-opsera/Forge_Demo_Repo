export type DetectionState =
  | 'monitoring'
  | 'at_risk'
  | 'potentially_stuck'
  | 'confirmed_stuck'
  | 'resolved';

export type StepStatus = 'pending' | 'running' | 'success' | 'failed' | 'skipped';

export type ComponentDeployStatus = 'deployed' | 'pending' | 'failed';

export interface PipelineStep {
  id: string;
  name: string;
  status: StepStatus;
  startTime: string | null;
  durationMs: number | null;
}

export interface MetadataComponent {
  name: string;
  type: string;
  status: ComponentDeployStatus;
}

export interface ExecutionMetrics {
  currentDurationMs: number;
  p50BaselineMs: number | null;
  p90BaselineMs: number | null;
  p99BaselineMs: number | null;
  staleDurationMs: number | null;
  componentCount: number;
}

export interface PipelineDetail {
  id: string;
  name: string;
  orgName: string;
  deployId: string;
  startTime: string;
  detectionState: DetectionState;
  metrics: ExecutionMetrics;
  steps: PipelineStep[];
  metadataComponents: MetadataComponent[];
}

export const DETECTION_STATE_LABELS: Record<DetectionState, string> = {
  monitoring: 'Monitoring',
  at_risk: 'At Risk',
  potentially_stuck: 'Potentially Stuck',
  confirmed_stuck: 'Confirmed Stuck',
  resolved: 'Resolved',
};

export const DETECTION_STATE_ORDER: DetectionState[] = [
  'monitoring',
  'at_risk',
  'potentially_stuck',
  'confirmed_stuck',
  'resolved',
];

export const DETECTION_STATE_COLORS: Record<DetectionState, string> = {
  monitoring: '#2563eb',
  at_risk: '#d97706',
  potentially_stuck: '#ea580c',
  confirmed_stuck: '#dc2626',
  resolved: '#16a34a',
};
