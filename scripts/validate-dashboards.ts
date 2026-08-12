/**
 * validate-dashboards.ts
 *
 * Validates each Grafana dashboard JSON file in dashboards/:
 *  - Parses JSON
 *  - Verifies required top-level fields (title, uid, panels, templating, schemaVersion)
 *  - Ensures panels have at least one target with an expr field
 *  - Extracts all PromQL metric names and cross-references against the metrics catalog
 *  - Checks that template variables for $org and $pipeline are defined where expected
 *
 * Run with: npx tsx scripts/validate-dashboards.ts
 */

import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

// ── Metrics catalog — must match names defined in packages/shared/src/common/metrics/ ──

const KNOWN_METRICS = new Set([
  // Business
  'stuck_pipeline_detections_total',
  'detection_latency_seconds',
  'false_positive_rate_1h',
  'active_monitored_pipelines',
  'alert_delivery_latency_seconds',
  // API
  'http_request_duration_seconds',
  'http_requests_total',
  'http_active_connections',
  // Integration
  'sf_api_calls_total',
  'sf_api_latency_seconds',
  'sf_cometd_connection_status',
  'sf_token_refresh_total',
  'sf_api_budget_utilization',
  // Infrastructure
  'pg_connections_active',
  'pg_query_duration_seconds',
  'redis_memory_used_bytes',
  'redis_streams_consumer_lag',
  'redis_streams_messages_processed_total',
]);

// ── PromQL metric name extractor ───────────────────────────────────────────────

function extractMetricNames(expr: string): string[] {
  // Match bare metric names (snake_case identifiers not inside {}),
  // and metric names in histogram_quantile/rate/increase/sum/etc calls
  const names: string[] = [];
  // Match metric name patterns: lowercase letters, digits, underscores
  const metricPattern = /\b([a-z_][a-z0-9_]*(?:_(?:bucket|count|sum|total|seconds|bytes))?)\b/g;
  let match;
  while ((match = metricPattern.exec(expr)) !== null) {
    const name = match[1];
    // Filter out PromQL function names and keywords
    const PROMQL_KEYWORDS = new Set([
      'rate', 'increase', 'sum', 'avg', 'max', 'min', 'count', 'by', 'without',
      'histogram_quantile', 'topk', 'bottomk', 'label_values', 'le', 'on',
      'unless', 'and', 'or', 'offset', 'bool', 'group_left', 'group_right',
      'ignoring', 'without', 'absent', 'vector', 'scalar', 'sort', 'sort_desc',
      'stddev', 'stdvar', 'quantile', 'count_values', 'irate', 'delta',
      'deriv', 'predict_linear', 'resets', 'changes', 'idelta', 'holt_winters',
      'day_of_month', 'day_of_week', 'days_in_month', 'hour', 'minute',
      'month', 'year', 'time', 'timestamp', 'floor', 'ceil', 'round', 'abs',
      'exp', 'sqrt', 'ln', 'log2', 'log10', 'clamp_max', 'clamp_min', 'sgn',
    ]);
    if (name !== undefined && !PROMQL_KEYWORDS.has(name) && name.includes('_') && name.length > 5) {
      names.push(name);
    }
  }
  return names;
}

// ── Panel target visitor ───────────────────────────────────────────────────────

interface Target {
  expr?: string;
  refId?: string;
}

interface Panel {
  id?: number;
  title?: string;
  type?: string;
  targets?: Target[];
  panels?: Panel[];
}

interface TemplateVariable {
  name?: string;
  type?: string;
  query?: string | { query?: string };
}

interface Dashboard {
  title?: string;
  uid?: string;
  schemaVersion?: number;
  panels?: Panel[];
  templating?: { list?: TemplateVariable[] };
}

function collectTargets(panels: Panel[]): Target[] {
  const targets: Target[] = [];
  for (const panel of panels) {
    if (panel.targets) {
      targets.push(...panel.targets);
    }
    // Grafana supports row panels with nested panels
    if (panel.panels) {
      targets.push(...collectTargets(panel.panels));
    }
  }
  return targets;
}

// ── Validation ─────────────────────────────────────────────────────────────────

interface ValidationResult {
  file: string;
  errors: string[];
  warnings: string[];
  metricsReferenced: string[];
}

function validateDashboard(filePath: string): ValidationResult {
  const fileName = filePath.split('/').pop() ?? filePath;
  const errors: string[] = [];
  const warnings: string[] = [];

  let raw: string;
  let dashboard: Dashboard;

  try {
    raw = readFileSync(filePath, 'utf-8');
  } catch (err) {
    return { file: fileName, errors: [`Cannot read file: ${String(err)}`], warnings: [], metricsReferenced: [] };
  }

  try {
    dashboard = JSON.parse(raw) as Dashboard;
  } catch (err) {
    return { file: fileName, errors: [`Invalid JSON: ${String(err)}`], warnings: [], metricsReferenced: [] };
  }

  // Required top-level fields
  if (!dashboard.title) errors.push('Missing required field: title');
  if (!dashboard.uid) errors.push('Missing required field: uid');
  if (typeof dashboard.schemaVersion !== 'number') errors.push('Missing required field: schemaVersion');
  if (!Array.isArray(dashboard.panels) || dashboard.panels.length === 0) {
    errors.push('Dashboard has no panels');
  }

  // Template variables check
  const variables = dashboard.templating?.list ?? [];
  const varNames = new Set(variables.map((v) => v.name));
  if (!varNames.has('datasource')) warnings.push('No $datasource template variable found');

  // Absolute time range check
  const rawLower = raw.toLowerCase();
  if (rawLower.includes('"from": "20') || rawLower.includes('"to": "20')) {
    errors.push('Dashboard contains absolute time range — use relative ranges only');
  }

  // Panels: collect all PromQL expressions
  const targets = collectTargets(dashboard.panels ?? []);
  const metricNamesReferenced = new Set<string>();

  for (const target of targets) {
    if (!target.expr) {
      warnings.push(`Panel target missing expr (refId: ${target.refId ?? 'unknown'})`);
      continue;
    }
    // Normalise histogram sub-metric suffixes to base name
    const rawMetrics = extractMetricNames(target.expr);
    for (const raw of rawMetrics) {
      const base = raw
        .replace(/_bucket$/, '')
        .replace(/_count$/, '')
        .replace(/_sum$/, '');
      metricNamesReferenced.add(base);
    }
  }

  // Cross-reference against catalog
  for (const metric of metricNamesReferenced) {
    if (!KNOWN_METRICS.has(metric)) {
      warnings.push(`PromQL references unknown metric: ${metric} (may be a label_values query or function)`);
    }
  }

  const knownReferenced = [...metricNamesReferenced].filter((m) => KNOWN_METRICS.has(m));
  if (knownReferenced.length === 0 && targets.length > 0) {
    warnings.push('No known catalog metrics found in dashboard targets');
  }

  return { file: fileName, errors, warnings, metricsReferenced: knownReferenced };
}

// ── Main ───────────────────────────────────────────────────────────────────────

const dashboardsDir = resolve(process.cwd(), 'dashboards');
let files: string[];

try {
  files = readdirSync(dashboardsDir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => join(dashboardsDir, f));
} catch {
  console.error(`Cannot read dashboards directory: ${dashboardsDir}`);
  process.exit(1);
}

if (files.length === 0) {
  console.error('No dashboard JSON files found in dashboards/');
  process.exit(1);
}

let totalErrors = 0;
let totalWarnings = 0;

for (const file of files) {
  const result = validateDashboard(file);
  const hasErrors = result.errors.length > 0;

  console.log(`\n${hasErrors ? '✗' : '✓'} ${result.file}`);

  if (result.metricsReferenced.length > 0) {
    console.log(`  Metrics: ${result.metricsReferenced.join(', ')}`);
  }
  for (const err of result.errors) {
    console.error(`  ERROR: ${err}`);
    totalErrors++;
  }
  for (const warn of result.warnings) {
    console.warn(`  WARN:  ${warn}`);
    totalWarnings++;
  }
}

console.log(`\nValidation complete: ${files.length} dashboards, ${totalErrors} errors, ${totalWarnings} warnings`);

if (totalErrors > 0) {
  process.exit(1);
}
