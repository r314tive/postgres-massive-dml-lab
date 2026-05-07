\set ON_ERROR_STOP on
\timing on
\echo 'generated DELETE batches: dml_lab.audit_record old rows'

\echo 'delete batch 1: limit 5000'
BEGIN;

SET LOCAL lock_timeout = '1s';
SET LOCAL statement_timeout = '10min';

WITH target AS (
    SELECT audit_record_id
    FROM dml_lab.audit_record
    WHERE created_at < '2026-04-07 00:00:00+00'::timestamptz
    ORDER BY created_at, audit_record_id
    LIMIT 5000
    FOR UPDATE SKIP LOCKED
)
DELETE FROM dml_lab.audit_record ar
USING target t
WHERE ar.audit_record_id = t.audit_record_id;

COMMIT;

SELECT pg_sleep('0.05');
