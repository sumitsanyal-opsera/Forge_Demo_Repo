-- [HAND_AUTHORED] Complete schema migration for Opsera Stuck Pipeline Detection System
-- Merges core relational tables, time-series partitioned tables, supporting tables,
-- audit trigger, and all indexes into a single migration.
--
-- Partitioned tables (pipeline_executions, execution_steps) are created with raw SQL
-- because Prisma does not support PARTITION BY RANGE natively.
-- All other tables are standard Prisma-compatible DDL.
--
-- Do NOT regenerate this file with `prisma migrate diff` — it will lose the partitioning DDL.

-- ── Enum types ─────────────────────────────────────────────────────────────────

CREATE TYPE "Role" AS ENUM ('ADMIN', 'RELEASE_ENGINEER', 'VIEWER');

CREATE TYPE "ConnectionStatus" AS ENUM ('CONNECTED', 'DISCONNECTED', 'ERROR');

CREATE TYPE "ExecutionStatus" AS ENUM ('QUEUED', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'CANCELLED', 'STUCK');

CREATE TYPE "StepStatus" AS ENUM ('QUEUED', 'IN_PROGRESS', 'COMPLETED', 'FAILED', 'SKIPPED');

CREATE TYPE "ThresholdMode" AS ENUM ('COMPUTED', 'STATIC');

CREATE TYPE "DetectionState" AS ENUM ('MONITORING', 'AT_RISK', 'POTENTIALLY_STUCK', 'CONFIRMED_STUCK', 'RESOLVED');

CREATE TYPE "AlertStatus" AS ENUM ('PENDING', 'SENT', 'DELIVERED', 'FAILED', 'ACKNOWLEDGED');

CREATE TYPE "NotificationPreference" AS ENUM ('REALTIME', 'DIGEST');

-- ── Core relational tables ─────────────────────────────────────────────────────

CREATE TABLE "users" (
    "id"              UUID        NOT NULL DEFAULT gen_random_uuid(),
    "opsera_user_id"  TEXT        NOT NULL,
    -- Confidential: PII field. Application-layer encryption applied before persist.
    "email"           TEXT        NOT NULL,
    "display_name"    TEXT        NOT NULL,
    "role"            "Role"      NOT NULL DEFAULT 'VIEWER',
    "created_at"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updated_at"      TIMESTAMPTZ NOT NULL,
    "is_active"       BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "users_opsera_user_id_key" ON "users"("opsera_user_id");
CREATE INDEX "users_email_idx" ON "users"("email");

-- ──

CREATE TABLE "salesforce_orgs" (
    "id"                    UUID              NOT NULL DEFAULT gen_random_uuid(),
    "org_id"                TEXT              NOT NULL,
    "org_name"              TEXT              NOT NULL,
    "instance_url"          TEXT              NOT NULL,
    "connection_status"     "ConnectionStatus" NOT NULL DEFAULT 'DISCONNECTED',
    -- Vault key reference only — never the raw OAuth token
    "token_vault_reference" TEXT,
    "connected_by"          UUID,
    "connected_at"          TIMESTAMPTZ,
    "last_health_check_at"  TIMESTAMPTZ,
    "created_at"            TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
    "updated_at"            TIMESTAMPTZ       NOT NULL,

    CONSTRAINT "salesforce_orgs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "salesforce_orgs_connected_by_fkey"
        FOREIGN KEY ("connected_by") REFERENCES "users"("id") ON DELETE RESTRICT
);

CREATE UNIQUE INDEX "salesforce_orgs_org_id_key" ON "salesforce_orgs"("org_id");
CREATE INDEX "salesforce_orgs_org_id_idx" ON "salesforce_orgs"("org_id");
CREATE INDEX "salesforce_orgs_connection_status_idx" ON "salesforce_orgs"("connection_status");

-- ──

CREATE TABLE "monitored_pipelines" (
    "id"                  UUID        NOT NULL DEFAULT gen_random_uuid(),
    "opsera_pipeline_id"  TEXT        NOT NULL,
    "pipeline_name"       TEXT        NOT NULL,
    "salesforce_org_id"   UUID        NOT NULL,
    "monitoring_enabled"  BOOLEAN     NOT NULL DEFAULT TRUE,
    "created_by"          UUID,
    "created_at"          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updated_at"          TIMESTAMPTZ NOT NULL,

    CONSTRAINT "monitored_pipelines_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "monitored_pipelines_salesforce_org_id_fkey"
        FOREIGN KEY ("salesforce_org_id") REFERENCES "salesforce_orgs"("id") ON DELETE CASCADE,
    CONSTRAINT "monitored_pipelines_created_by_fkey"
        FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT
);

CREATE UNIQUE INDEX "monitored_pipelines_opsera_pipeline_id_key" ON "monitored_pipelines"("opsera_pipeline_id");
CREATE INDEX "monitored_pipelines_opsera_pipeline_id_idx" ON "monitored_pipelines"("opsera_pipeline_id");

-- ── Partitioned time-series tables ────────────────────────────────────────────
-- Composite primary key (id, started_at) is required because PostgreSQL declarative
-- partitioning mandates the partition key be part of every unique constraint and PK.
-- Application code must always include started_at in lookups by id.

CREATE TABLE "pipeline_executions" (
    "id"                   UUID            NOT NULL DEFAULT gen_random_uuid(),
    "monitored_pipeline_id" UUID           NOT NULL,
    "salesforce_deploy_id" TEXT,
    "status"               "ExecutionStatus" NOT NULL DEFAULT 'QUEUED',
    "started_at"           TIMESTAMPTZ     NOT NULL,
    "completed_at"         TIMESTAMPTZ,
    "duration_seconds"     INTEGER,
    -- metadata JSONB fields: component_count, test_count, test_results, error_messages, deployment_type
    "metadata"             JSONB,
    "created_at"           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT "pipeline_executions_pkey" PRIMARY KEY ("id", "started_at"),
    CONSTRAINT "pipeline_executions_monitored_pipeline_id_fkey"
        FOREIGN KEY ("monitored_pipeline_id") REFERENCES "monitored_pipelines"("id") ON DELETE RESTRICT
) PARTITION BY RANGE ("started_at");

-- B-tree composite indexes on the parent table propagate to all partitions
CREATE INDEX "pipeline_executions_monitored_pipeline_id_started_at_idx"
    ON "pipeline_executions"("monitored_pipeline_id", "started_at" DESC);

CREATE INDEX "pipeline_executions_status_started_at_idx"
    ON "pipeline_executions"("status", "started_at" DESC);

-- GIN index on metadata JSONB using jsonb_path_ops for efficient containment queries
CREATE INDEX "pipeline_executions_metadata_gin_idx"
    ON "pipeline_executions" USING GIN ("metadata" jsonb_path_ops);

-- ── pipeline_executions monthly partitions ────────────────────────────────────
-- Months 2026-06 and 2026-07 included for seed/historical data
-- Current month 2026-08 and next 3 months (AC-6: current + 3 future)

CREATE TABLE "pipeline_executions_2026_06"
    PARTITION OF "pipeline_executions"
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE TABLE "pipeline_executions_2026_07"
    PARTITION OF "pipeline_executions"
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE TABLE "pipeline_executions_2026_08"
    PARTITION OF "pipeline_executions"
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

CREATE TABLE "pipeline_executions_2026_09"
    PARTITION OF "pipeline_executions"
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

CREATE TABLE "pipeline_executions_2026_10"
    PARTITION OF "pipeline_executions"
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');

CREATE TABLE "pipeline_executions_2026_11"
    PARTITION OF "pipeline_executions"
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');

-- ──

CREATE TABLE "execution_steps" (
    "id"                            UUID        NOT NULL DEFAULT gen_random_uuid(),
    "pipeline_execution_id"         UUID        NOT NULL,
    -- Mirror of pipeline_executions.started_at required for composite FK
    "pipeline_execution_started_at" TIMESTAMPTZ NOT NULL,
    "step_name"                     TEXT        NOT NULL,
    "step_type"                     TEXT        NOT NULL,
    "status"                        "StepStatus" NOT NULL DEFAULT 'QUEUED',
    "started_at"                    TIMESTAMPTZ NOT NULL,
    "completed_at"                  TIMESTAMPTZ,
    "duration_seconds"              INTEGER,
    -- progress_indicators JSONB: components_processed, tests_completed, last_status_change_at
    "progress_indicators"           JSONB,
    "created_at"                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT "execution_steps_pkey" PRIMARY KEY ("id", "started_at"),
    CONSTRAINT "execution_steps_pipeline_execution_fkey"
        FOREIGN KEY ("pipeline_execution_id", "pipeline_execution_started_at")
        REFERENCES "pipeline_executions"("id", "started_at") ON DELETE CASCADE
) PARTITION BY RANGE ("started_at");

CREATE INDEX "execution_steps_pipeline_execution_id_started_at_idx"
    ON "execution_steps"("pipeline_execution_id", "started_at");

CREATE INDEX "execution_steps_progress_indicators_gin_idx"
    ON "execution_steps" USING GIN ("progress_indicators" jsonb_path_ops);

-- ── execution_steps monthly partitions ────────────────────────────────────────

CREATE TABLE "execution_steps_2026_06"
    PARTITION OF "execution_steps"
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE TABLE "execution_steps_2026_07"
    PARTITION OF "execution_steps"
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE TABLE "execution_steps_2026_08"
    PARTITION OF "execution_steps"
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

CREATE TABLE "execution_steps_2026_09"
    PARTITION OF "execution_steps"
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

CREATE TABLE "execution_steps_2026_10"
    PARTITION OF "execution_steps"
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');

CREATE TABLE "execution_steps_2026_11"
    PARTITION OF "execution_steps"
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');

-- ── Supporting tables ─────────────────────────────────────────────────────────

CREATE TABLE "threshold_configs" (
    "id"                          UUID            NOT NULL DEFAULT gen_random_uuid(),
    -- NULL = org-level default (applies to all pipelines in the org)
    "monitored_pipeline_id"       UUID,
    "salesforce_org_id"           UUID            NOT NULL,
    -- NULL = pipeline-level threshold (not step-specific)
    "step_name"                   TEXT,
    "threshold_mode"              "ThresholdMode" NOT NULL DEFAULT 'COMPUTED',
    "p50_seconds"                 INTEGER,
    "p90_seconds"                 INTEGER,
    "p99_seconds"                 INTEGER,
    "stale_state_timeout_minutes" INTEGER         NOT NULL DEFAULT 30,
    "grace_period_minutes"        INTEGER         NOT NULL DEFAULT 5,
    "peak_hour_multiplier"        DECIMAL(4,2)    NOT NULL DEFAULT 1.5,
    "created_at"                  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    "updated_at"                  TIMESTAMPTZ     NOT NULL,

    CONSTRAINT "threshold_configs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "threshold_configs_monitored_pipeline_id_fkey"
        FOREIGN KEY ("monitored_pipeline_id") REFERENCES "monitored_pipelines"("id") ON DELETE CASCADE,
    CONSTRAINT "threshold_configs_salesforce_org_id_fkey"
        FOREIGN KEY ("salesforce_org_id") REFERENCES "salesforce_orgs"("id") ON DELETE CASCADE,
    -- Standard unique constraint covers non-NULL pipeline cases
    CONSTRAINT "threshold_configs_monitored_pipeline_id_step_name_key"
        UNIQUE ("monitored_pipeline_id", "step_name")
);

-- Partial unique index for org-level defaults (monitored_pipeline_id IS NULL).
-- PostgreSQL unique constraints treat NULLs as distinct, so we need an explicit
-- partial index to enforce uniqueness for the org-level default case.
CREATE UNIQUE INDEX "threshold_configs_org_default_step_name_key"
    ON "threshold_configs"("salesforce_org_id", "step_name")
    WHERE "monitored_pipeline_id" IS NULL;

-- ──

CREATE TABLE "execution_baselines" (
    "id"                    UUID        NOT NULL DEFAULT gen_random_uuid(),
    "monitored_pipeline_id" UUID        NOT NULL,
    -- NULL = pipeline-level baseline (not step-specific)
    "step_name"             TEXT,
    -- timeBucket: "2026-08" for monthly or "weekday_morning" for intraday
    "time_bucket"           TEXT        NOT NULL,
    "p50_seconds"           INTEGER     NOT NULL,
    "p90_seconds"           INTEGER     NOT NULL,
    "p99_seconds"           INTEGER     NOT NULL,
    "sample_count"          INTEGER     NOT NULL,
    "last_computed_at"      TIMESTAMPTZ NOT NULL,
    -- time_of_day_factors JSONB: { "hour_0": 0.8, "hour_9": 1.2, ... }
    "time_of_day_factors"   JSONB,
    "created_at"            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "updated_at"            TIMESTAMPTZ NOT NULL,

    CONSTRAINT "execution_baselines_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "execution_baselines_monitored_pipeline_id_fkey"
        FOREIGN KEY ("monitored_pipeline_id") REFERENCES "monitored_pipelines"("id") ON DELETE CASCADE,
    CONSTRAINT "execution_baselines_monitored_pipeline_id_step_name_time_bucket_key"
        UNIQUE ("monitored_pipeline_id", "step_name", "time_bucket")
);

CREATE INDEX "execution_baselines_time_of_day_factors_gin_idx"
    ON "execution_baselines" USING GIN ("time_of_day_factors" jsonb_path_ops);

-- ──

CREATE TABLE "detection_events" (
    "id"                              UUID            NOT NULL DEFAULT gen_random_uuid(),
    "pipeline_execution_id"           UUID            NOT NULL,
    -- Composite FK requires the partition key from pipeline_executions
    "pipeline_execution_started_at"   TIMESTAMPTZ     NOT NULL,
    "previous_state"                  "DetectionState",
    "new_state"                       "DetectionState" NOT NULL,
    "transition_reason"               TEXT,
    "detected_at"                     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    "metadata"                        JSONB,

    CONSTRAINT "detection_events_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "detection_events_pipeline_execution_fkey"
        FOREIGN KEY ("pipeline_execution_id", "pipeline_execution_started_at")
        REFERENCES "pipeline_executions"("id", "started_at") ON DELETE CASCADE
);

CREATE INDEX "detection_events_pipeline_execution_id_idx"
    ON "detection_events"("pipeline_execution_id");
CREATE INDEX "detection_events_new_state_detected_at_idx"
    ON "detection_events"("new_state", "detected_at" DESC);
CREATE INDEX "detection_events_metadata_gin_idx"
    ON "detection_events" USING GIN ("metadata" jsonb_path_ops);

-- ──

CREATE TABLE "alert_records" (
    "id"                UUID          NOT NULL DEFAULT gen_random_uuid(),
    "detection_event_id" UUID         NOT NULL,
    "alert_type"        TEXT          NOT NULL,
    "status"            "AlertStatus" NOT NULL DEFAULT 'PENDING',
    "sent_at"           TIMESTAMPTZ,
    "delivered_at"      TIMESTAMPTZ,
    "acknowledged_at"   TIMESTAMPTZ,
    "acknowledged_by"   UUID,
    "retry_count"       INTEGER       NOT NULL DEFAULT 0,
    "created_at"        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    "updated_at"        TIMESTAMPTZ   NOT NULL,

    CONSTRAINT "alert_records_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "alert_records_detection_event_id_fkey"
        FOREIGN KEY ("detection_event_id") REFERENCES "detection_events"("id") ON DELETE CASCADE
);

CREATE INDEX "alert_records_detection_event_id_idx" ON "alert_records"("detection_event_id");
CREATE INDEX "alert_records_status_created_at_idx" ON "alert_records"("status", "created_at" DESC);

-- ──

CREATE TABLE "alert_recipients" (
    "id"                      UUID                    NOT NULL DEFAULT gen_random_uuid(),
    -- NULL = org-wide recipient (receives alerts for all pipelines in the org)
    "monitored_pipeline_id"   UUID,
    "salesforce_org_id"       UUID,
    "email"                   TEXT                    NOT NULL,
    "notification_preference" "NotificationPreference" NOT NULL DEFAULT 'REALTIME',
    "is_active"               BOOLEAN                 NOT NULL DEFAULT TRUE,
    "created_at"              TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    "updated_at"              TIMESTAMPTZ             NOT NULL,

    CONSTRAINT "alert_recipients_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "alert_recipients_monitored_pipeline_id_fkey"
        FOREIGN KEY ("monitored_pipeline_id") REFERENCES "monitored_pipelines"("id") ON DELETE CASCADE,
    CONSTRAINT "alert_recipients_salesforce_org_id_fkey"
        FOREIGN KEY ("salesforce_org_id") REFERENCES "salesforce_orgs"("id") ON DELETE CASCADE,
    CONSTRAINT "alert_recipients_monitored_pipeline_id_email_key"
        UNIQUE ("monitored_pipeline_id", "email")
);

-- ── AuditLog: no foreign keys — audit records must survive entity deletion ────

CREATE TABLE "audit_log" (
    "id"             UUID        NOT NULL DEFAULT gen_random_uuid(),
    "actor"          TEXT        NOT NULL,
    "action"         TEXT        NOT NULL,
    "resource_type"  TEXT        NOT NULL,
    "resource_id"    TEXT        NOT NULL,
    -- change_details JSONB: before/after state, diff of changed fields
    "change_details" JSONB,
    "ip_address"     TEXT,
    "timestamp"      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    "correlation_id" TEXT,

    CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "audit_log_resource_type_resource_id_idx" ON "audit_log"("resource_type", "resource_id");
CREATE INDEX "audit_log_actor_timestamp_idx" ON "audit_log"("actor", "timestamp" DESC);

-- ── Audit log immutability trigger ────────────────────────────────────────────
-- Enforces immutability at the database level. Application-level checks alone
-- are insufficient — this trigger blocks UPDATE and DELETE from any connection.

CREATE OR REPLACE FUNCTION prevent_audit_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Audit log records are immutable: % on audit_log is not permitted', TG_OP;
END;
$$;

CREATE TRIGGER audit_immutability
    BEFORE UPDATE OR DELETE ON "audit_log"
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_modification();
