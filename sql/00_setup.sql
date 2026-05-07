\set ON_ERROR_STOP on

\if :{?transaction_rows}
\else
\set transaction_rows 50000
\endif

\if :{?audit_rows}
\else
\set audit_rows 30000
\endif

\if :{?old_audit_rows}
\else
\set old_audit_rows 12000
\endif

\if :{?transaction_payload_bytes}
\else
\set transaction_payload_bytes 100
\endif

\if :{?audit_payload_bytes}
\else
\set audit_payload_bytes 120
\endif

SET client_min_messages = warning;
SET TimeZone = 'UTC';

DROP SCHEMA IF EXISTS dml_lab CASCADE;
CREATE SCHEMA dml_lab;

CREATE TABLE dml_lab.transaction_log (
    id bigint PRIMARY KEY,
    created_at bigint,
    processed_at bigint,
    created_ts timestamptz,
    processed_ts timestamptz,
    payload text NOT NULL
);

WITH src AS (
    SELECT
        gs AS id,
        TIMESTAMPTZ '2026-01-01 00:00:00+00' + make_interval(secs => gs) AS created_time,
        TIMESTAMPTZ '2026-01-01 00:00:00+00' + make_interval(secs => gs + 60) AS processed_time
    FROM generate_series(1, :transaction_rows::bigint) AS gs
),
prepared AS (
    SELECT
        id,
        CASE
            WHEN id % 17 = 0 THEN NULL
            ELSE (extract(epoch FROM created_time) * 1000000)::bigint
        END AS created_at,
        CASE
            WHEN id % 19 = 0 THEN NULL
            ELSE (extract(epoch FROM processed_time) * 1000000)::bigint
        END AS processed_at,
        created_time,
        processed_time
    FROM src
)
INSERT INTO dml_lab.transaction_log (
    id,
    created_at,
    processed_at,
    created_ts,
    processed_ts,
    payload
)
SELECT
    id,
    created_at,
    processed_at,
    CASE
        WHEN created_at IS NOT NULL AND id % 2 <> 0 THEN created_time
        ELSE NULL
    END AS created_ts,
    CASE
        WHEN processed_at IS NOT NULL AND id % 3 <> 0 THEN processed_time
        ELSE NULL
    END AS processed_ts,
    repeat('x', :transaction_payload_bytes::integer) AS payload
FROM prepared;

CREATE TABLE dml_lab.audit_record (
    audit_record_id bigint PRIMARY KEY,
    created_at timestamptz NOT NULL,
    payload text NOT NULL
);

INSERT INTO dml_lab.audit_record (audit_record_id, created_at, payload)
SELECT
    gs AS audit_record_id,
    CASE
        WHEN gs <= LEAST(:old_audit_rows::bigint, :audit_rows::bigint)
        THEN TIMESTAMPTZ '2026-03-01 00:00:00+00' + make_interval(secs => gs)
        ELSE TIMESTAMPTZ '2026-04-15 00:00:00+00' + make_interval(secs => gs)
    END AS created_at,
    repeat('a', :audit_payload_bytes::integer) AS payload
FROM generate_series(1, :audit_rows::bigint) AS gs;

CREATE INDEX audit_record_created_at_audit_record_id_idx
ON dml_lab.audit_record (created_at, audit_record_id);

CREATE VIEW dml_lab.transaction_log_backfill_stats AS
SELECT
    count(*) AS total_rows,
    count(*) FILTER (
        WHERE (created_ts IS NULL AND created_at IS NOT NULL)
           OR (processed_ts IS NULL AND processed_at IS NOT NULL)
    ) AS backfillable_remaining,
    count(*) FILTER (
        WHERE created_at IS NULL AND created_ts IS NULL
    ) AS created_source_null_rows,
    count(*) FILTER (
        WHERE processed_at IS NULL AND processed_ts IS NULL
    ) AS processed_source_null_rows
FROM dml_lab.transaction_log;

CREATE VIEW dml_lab.audit_record_delete_stats AS
SELECT
    count(*) AS total_rows,
    count(*) FILTER (
        WHERE created_at < TIMESTAMPTZ '2026-04-07 00:00:00+00'
    ) AS old_rows
FROM dml_lab.audit_record;

ANALYZE dml_lab.transaction_log;
ANALYZE dml_lab.audit_record;
