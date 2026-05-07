\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '1s';
SET LOCAL statement_timeout = '10min';
SET LOCAL TimeZone = 'UTC';

EXPLAIN (ANALYZE, BUFFERS)
UPDATE dml_lab.transaction_log
SET created_ts = CASE
        WHEN created_ts IS NULL AND created_at IS NOT NULL
        THEN to_timestamp(created_at / 1000000.0)
        ELSE created_ts
    END,
    processed_ts = CASE
        WHEN processed_ts IS NULL AND processed_at IS NOT NULL
        THEN to_timestamp(processed_at / 1000000.0)
        ELSE processed_ts
    END
WHERE id BETWEEN 1 AND 5000
  AND (
        (created_ts IS NULL AND created_at IS NOT NULL)
     OR (processed_ts IS NULL AND processed_at IS NOT NULL)
  );

ROLLBACK;
