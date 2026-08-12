# Metrics Catalog

All Prometheus metrics exposed by the Opsera Stuck Pipeline Detection System.

Each service exposes `GET /metrics` (unauthenticated, Prometheus exposition format, Content-Type `text/plain; version=0.0.4`).

---

## Machine-Readable Catalog

The validation script `scripts/validate-dashboards.ts` uses the metric names in this section for cross-referencing.

```
CATALOG_START
stuck_pipeline_detections_total
detection_latency_seconds
false_positive_rate_1h
active_monitored_pipelines
alert_delivery_latency_seconds
http_request_duration_seconds
http_requests_total
http_active_connections
sf_api_calls_total
sf_api_latency_seconds
sf_cometd_connection_status
sf_token_refresh_total
sf_api_budget_utilization
pg_connections_active
pg_query_duration_seconds
redis_memory_used_bytes
redis_streams_consumer_lag
redis_streams_messages_processed_total
CATALOG_END
```

---

## Business Metrics

These metrics are incremented by business-domain logic in the Detection, Baseline, and Alert services.

### `stuck_pipeline_detections_total`

| Field | Value |
|-------|-------|
| Type | Counter |
| Labels | `org` (org ID), `pipeline` (pipeline ID), `severity` (`warning` \| `critical`) |
| Description | Total number of pipelines that transitioned to `confirmed_stuck` or `resolved` state with a stuck detection. |
| Instrumented by | Detection Service state machine transitions |

**Example:**
```
stuck_pipeline_detections_total{org="org-001",pipeline="pipe-abc",severity="critical"} 3
```

---

### `detection_latency_seconds`

| Field | Value |
|-------|-------|
| Type | Histogram |
| Labels | `org` |
| Buckets | 1, 5, 10, 30, 60, 120, 300 seconds |
| Description | Time elapsed from pipeline start to first `confirmed_stuck` detection. |
| Instrumented by | Detection Service |

**SLO target:** P95 < 5 minutes (300 seconds).

---

### `false_positive_rate_1h`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | `org` |
| Range | 0.0–1.0 |
| Description | Rolling 1-hour false positive rate — ratio of detections later marked as false positives to total detections. |
| Instrumented by | Detection Service, updated on pipeline resolution |

**SLO target:** < 5% (0.05).

---

### `active_monitored_pipelines`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | `org` |
| Description | Number of pipelines currently in the `monitoring` or `at_risk` state (actively watched). |
| Instrumented by | Detection Service |

---

### `alert_delivery_latency_seconds`

| Field | Value |
|-------|-------|
| Type | Histogram |
| Labels | `org`, `channel` (`email` \| `slack` \| `webhook`) |
| Buckets | 1, 5, 10, 30, 60, 120 seconds |
| Description | Time from alert creation to confirmed delivery confirmation. |
| Instrumented by | Alert Service |

**SLO target:** P95 < 2 minutes (120 seconds).

---

## API Metrics

Automatically recorded by the HTTP instrumentation middleware for all inbound requests. Paths `/metrics` and `/health/**` are excluded.

### `http_request_duration_seconds`

| Field | Value |
|-------|-------|
| Type | Histogram |
| Labels | `method` (HTTP verb), `path` (normalised — UUIDs replaced by `:id`), `status` (HTTP status code as string) |
| Buckets | 0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10 seconds |
| Description | Duration of every handled HTTP request in seconds. |

**SLO target:** P95 < 500ms.

---

### `http_requests_total`

| Field | Value |
|-------|-------|
| Type | Counter |
| Labels | `method`, `path`, `status` |
| Description | Total number of HTTP requests received and responded to. |

---

### `http_active_connections`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | none |
| Description | Number of HTTP requests currently in-flight. |

---

## Integration Metrics (Salesforce)

### `sf_api_calls_total`

| Field | Value |
|-------|-------|
| Type | Counter |
| Labels | `org` (org ID), `endpoint` (normalised Salesforce REST path) |
| Description | Total outbound Salesforce REST API calls. |

---

### `sf_api_latency_seconds`

| Field | Value |
|-------|-------|
| Type | Histogram |
| Labels | `org` |
| Buckets | 0.1, 0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600 seconds |
| Description | Roundtrip latency for Salesforce REST API calls. Upper bucket covers the 10-minute Salesforce API timeout. |

---

### `sf_cometd_connection_status`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | `org` |
| Values | `1` = connected, `0` = disconnected |
| Description | Current state of the Salesforce CometD Streaming API connection. |

---

### `sf_token_refresh_total`

| Field | Value |
|-------|-------|
| Type | Counter |
| Labels | `org`, `result` (`success` \| `failure`) |
| Description | Total Salesforce OAuth JWT Bearer token refresh attempts. |

---

### `sf_api_budget_utilization`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | `org` |
| Range | 0.0–1.0 |
| Description | Fraction of the Salesforce org's daily API request limit consumed. Derived from `Sforce-Limit-Info` response header. |

**Warning threshold:** 70% (0.70). Alert at 90%.

---

## Infrastructure Metrics

### `pg_connections_active`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | none |
| Description | Current number of active PostgreSQL connections in the Prisma connection pool. Reports `0` on cold start before first query. |

---

### `pg_query_duration_seconds`

| Field | Value |
|-------|-------|
| Type | Histogram |
| Labels | `operation` (e.g. `SELECT`, `INSERT`, `UPDATE`) |
| Buckets | 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5 seconds |
| Description | Execution duration for PostgreSQL queries. |

---

### `redis_memory_used_bytes`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | none |
| Description | Redis RSS memory usage in bytes, sourced from `INFO memory → used_memory_rss`. |

---

### `redis_streams_consumer_lag`

| Field | Value |
|-------|-------|
| Type | Gauge |
| Labels | `stream` (stream key name) |
| Description | Number of pending unacknowledged messages in the consumer group for each Redis Stream. A sustained non-zero value indicates a backlog. |

---

### `redis_streams_messages_processed_total`

| Field | Value |
|-------|-------|
| Type | Counter |
| Labels | `stream` |
| Description | Total messages successfully acknowledged from each Redis Stream consumer group. |

---

## Label Cardinality Constraints

| Label | Value constraints |
|-------|------------------|
| `org` | Salesforce org ID (15/18 char alphanumeric) — not org display name |
| `pipeline` | Opsera pipeline ID (UUID) — not pipeline name |
| `severity` | Enum: `warning`, `critical` |
| `result` | Enum: `success`, `failure` |
| `channel` | Enum: `email`, `slack`, `webhook` |
| `path` | URL-normalised with UUIDs and numeric IDs replaced by `:id` |

A cardinality guard logs a warning when any single metric exceeds 500 unique label combinations.

---

## Scrape Configuration

```yaml
scrape_configs:
  - job_name: opsera-detection-service
    static_configs:
      - targets: ['detection-service:3002']
    scrape_interval: 15s
    metrics_path: /metrics

  - job_name: opsera-baseline-service
    static_configs:
      - targets: ['baseline-service:3001']
    scrape_interval: 15s
    metrics_path: /metrics

  - job_name: opsera-alert-service
    static_configs:
      - targets: ['alert-service:3003']
    scrape_interval: 15s
    metrics_path: /metrics

  - job_name: opsera-dashboard-service
    static_configs:
      - targets: ['dashboard-service:3004']
    scrape_interval: 15s
    metrics_path: /metrics

  - job_name: opsera-api-gateway
    static_configs:
      - targets: ['api-gateway:3000']
    scrape_interval: 15s
    metrics_path: /metrics
```
