# Generated-First Massive DML Runbook

This lab shows two approaches:

1. Generated SQL batches.
2. Procedures with transaction control.

The preferred operational default is generated SQL batches.

Related supporting docs:

- `docs/production-checklist.md` for production pre-checks, monitoring, stop,
  resume, and post-operation validation.
- `docs/when-not-to-use-row-delete.md` for cases where partition operations,
  rebuild/swap, or application jobs are better than row deletes.
- `docs/samples/` for shortened generated SQL, log, and `EXPLAIN` examples.
- `docs/article-outline.md` for turning this lab into a long-form guide.

## Why Generated SQL Is The Primary Path

Generated SQL is boring in a useful way:

- the exact executable file can be reviewed before execution;
- every batch has visible `BEGIN` / `COMMIT`;
- `psql` meta commands are visible in the file;
- `ON_ERROR_STOP` stops on the first failed batch;
- `\timing on` records per-statement timing;
- `\echo` shows the current batch in logs;
- `SET LOCAL lock_timeout` and `statement_timeout` are applied per batch;
- `pg_sleep()` happens after `COMMIT`;
- execution can be run from `tmux`, `screen`, or `nohup`;
- output can be saved with `tee`;
- stopping the process rolls back only the current batch;
- already committed batches stay committed;
- resume is explicit: regenerate from remaining rows or edit the remaining file.

This is why generated SQL is usually better for one-time production maintenance
than hiding the loop inside PL/pgSQL.

## Create Enough Data To See The Shape

Small fast dataset:

```bash
make setup-docker
```

Larger demo dataset:

```bash
make setup-large
```

Custom dataset:

```bash
TRANSACTION_ROWS=3000000 \
AUDIT_ROWS=1500000 \
OLD_AUDIT_ROWS=700000 \
TRANSACTION_PAYLOAD_BYTES=200 \
AUDIT_PAYLOAD_BYTES=200 \
./scripts/reset_lab.sh
```

Check what was created:

```bash
./scripts/psql.sh -c "SELECT * FROM dml_lab.transaction_log_backfill_stats;"
./scripts/psql.sh -c "SELECT * FROM dml_lab.audit_record_delete_stats;"
```

## Approach A: Generated UPDATE

Generate:

```bash
BATCH_SIZE=10000 SLEEP_SECONDS=0.1 \
./scripts/generate_update_batches.sh generated/transaction_log_backfill.sql
```

Review:

```bash
less generated/transaction_log_backfill.sql
```

The generated file starts with:

```sql
\set ON_ERROR_STOP on
\timing on
\echo 'generated UPDATE batches: dml_lab.transaction_log timestamp backfill'
```

Each batch looks like:

```sql
\echo 'batch 1: id 1..10000'
BEGIN;

SET LOCAL lock_timeout = '1s';
SET LOCAL statement_timeout = '10min';
SET LOCAL TimeZone = 'UTC';

UPDATE ...

COMMIT;

SELECT pg_sleep(0.1);
```

Run with logging:

```bash
./scripts/run_generated_update.sh generated/transaction_log_backfill.sql
```

The runner logs through `tee` into `logs/`.

Run inside `tmux`:

```bash
tmux new -s massive-update
./scripts/run_generated_update.sh generated/transaction_log_backfill.sql
```

Run with `nohup`:

```bash
nohup ./scripts/run_generated_update.sh generated/transaction_log_backfill.sql \
  > logs/nohup-update.out 2>&1 &
```

## Approach A: Generated DELETE

Generate:

```bash
BATCH_SIZE=10000 SLEEP_SECONDS=0.1 \
./scripts/generate_delete_batches.sh generated/audit_record_delete.sql
```

Review:

```bash
less generated/audit_record_delete.sql
```

Run:

```bash
./scripts/run_generated_delete.sh generated/audit_record_delete.sql
```

The DELETE batch selector uses:

```sql
ORDER BY created_at, audit_record_id
LIMIT ...
FOR UPDATE SKIP LOCKED
```

and requires this index:

```sql
CREATE INDEX audit_record_created_at_audit_record_id_idx
ON dml_lab.audit_record (created_at, audit_record_id);
```

For historical retention, first check whether partition detach/drop is available.
Row-by-row DELETE batches are a fallback when partition operations are not
available or do not match the data model.

## Stop And Resume

Stop:

```bash
Ctrl+C
```

or kill the `psql` process.

Result:

- current open transaction rolls back;
- committed batches remain committed;
- the log shows the last started/completed batch;
- remaining work can be regenerated from current table state.

Regenerate remaining UPDATE work:

```bash
./scripts/generate_update_batches.sh generated/transaction_log_backfill_resume.sql
```

Regenerate remaining DELETE work:

```bash
./scripts/generate_delete_batches.sh generated/audit_record_delete_resume.sql
```

## Approach B: Procedure-Controlled UPDATE/DELETE

Procedures are useful when the maintenance logic should live in the database:

```bash
./scripts/psql.sh -f sql/20_procedure_update.sql
./scripts/psql.sh -c "CALL dml_lab.backfill_transaction_log_timestamps(10000, 0.1);"
```

```bash
./scripts/psql.sh -f sql/40_delete_procedure.sql
./scripts/psql.sh -c "CALL dml_lab.delete_old_audit_records('2026-04-07 00:00:00+00', 10000, 0.1);"
```

But procedure transaction control has sharper edges:

- the `CALL` must be top-level;
- it must not be wrapped in external `BEGIN ... COMMIT`;
- migration tools may wrap SQL in a transaction automatically;
- `TEMP TABLE ... ON COMMIT DROP` breaks after the first internal `COMMIT`;
- operational logs are usually less reviewable than a generated SQL file.

Use procedures when repeatability or database-side encapsulation matters. For
one-time production maintenance, generated SQL is usually easier to control.

## Validate Before Full Execution

Run one representative batch inside rollback:

```bash
make explain
```

A shortened example of the expected output shape is in
`docs/samples/explain-update-batch.txt`.

Watch:

- execution time;
- buffers hit/read/dirtied/written;
- index usage;
- row count;
- lock waits;
- replication lag;
- application latency;
- disk I/O and storage growth.
