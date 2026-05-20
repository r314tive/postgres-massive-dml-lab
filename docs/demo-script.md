# Demo Script

This is a short flow for showing why massive DML needs committed batches.

## 1. Run The Verified Lab

```bash
make test-local
```

This starts a temporary PostgreSQL cluster, loads data, runs all scenarios, and
stops the server.

## 2. Start An Interactive Environment

```bash
make docker-reset
make psql
```

The Makefile uses `.env` when it exists, otherwise it falls back to
`.env.example`.

For a larger demo:

```bash
make setup-large
```

Inside `psql`:

```sql
SELECT * FROM dml_lab.transaction_log_backfill_stats;
SELECT * FROM dml_lab.audit_record_delete_stats;
```

## 3. Show One Batch Plan

```bash
make explain
```

The key point is to inspect real write pressure with:

```sql
EXPLAIN (ANALYZE, BUFFERS)
```

inside:

```sql
BEGIN;
...
ROLLBACK;
```

For a shortened article-ready example, use:

```text
docs/samples/explain-update-batch.txt
```

## 4. Show Reviewable Generated Batches

```bash
make demo-prepare
less generated/transaction_log_backfill.sql
make run-generated
```

The generated file contains explicit:

```sql
BEGIN;
...
COMMIT;
SELECT pg_sleep(...);
```

Shortened examples are available in:

```text
docs/samples/generated-update-batch.sql
docs/samples/generated-delete-batch.sql
docs/samples/run-log.txt
```

Generate and run DELETE batches the same way:

```bash
make generate-delete
less generated/audit_record_delete.sql
make run-delete
```

## Optional: Add Noisy Workload With Noisia

In another terminal:

```bash
NOISIA_DURATION=120 NOISIA_JOBS=2 make noisia-wait
```

In a monitoring terminal:

```bash
make monitor
```

Then run the generated UPDATE or DELETE batches. This shows why monitoring,
timeouts, committed batches, and stop/resume behavior matter under database
pressure.

More examples are in `docs/noisia-demo.md`.

For operational execution, use `tmux`:

```bash
tmux new -s massive-dml
./scripts/run_generated_update.sh generated/transaction_log_backfill.sql
```

or `nohup`:

```bash
nohup ./scripts/run_generated_update.sh generated/transaction_log_backfill.sql \
  > logs/nohup-update.out 2>&1 &
```

## 5. Show Procedure Caveat

```sql
\i sql/20_procedure_update.sql
BEGIN;
CALL dml_lab.backfill_transaction_log_timestamps(3500, 0);
COMMIT;
```

This fails because a procedure with transaction control must be called top-level.

Correct:

```sql
CALL dml_lab.backfill_transaction_log_timestamps(3500, 0);
```

## 6. Show TEMP TABLE ON COMMIT DROP Caveat

```sql
\i sql/60_transaction_caveats.sql
CALL dml_lab.bad_temp_table_on_commit_drop_demo();
```

The procedure creates a temp table with `ON COMMIT DROP`, commits internally,
and then fails because the temp table was dropped after the commit.

## 7. Show Queue-Based Update

```sql
\i sql/00_setup.sql
\i sql/30_queue_update.sql
CALL dml_lab.backfill_transaction_log_timestamps_from_queue(2500, 0);
SELECT * FROM dml_lab.transaction_log_backfill_stats;
```

## 8. Show Batched DELETE

```sql
\i sql/00_setup.sql
\i sql/40_delete_procedure.sql
SELECT * FROM dml_lab.audit_record_delete_stats;
CALL dml_lab.delete_old_audit_records('2026-04-07 00:00:00+00', 2500, 0);
SELECT * FROM dml_lab.audit_record_delete_stats;
```
