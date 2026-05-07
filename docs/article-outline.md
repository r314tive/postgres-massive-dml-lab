# Article Outline

This outline maps the repository to a long-form article or internal runbook
about massive `UPDATE` and `DELETE` operations in PostgreSQL.

## 1. Problem Statement

Massive DML is risky when it is executed as one large transaction:

- rollback becomes expensive;
- WAL generation can spike;
- replication lag can grow;
- dead tuples accumulate;
- vacuum cannot clean rows still visible to a long-running transaction;
- locks and application impact last longer than expected.

Article thesis:

```text
The safe unit of work is a committed batch, not a loop iteration.
```

Repository support:

- `README.md`
- `docs/generated-first-runbook.md`
- `sql/60_transaction_caveats.sql`

## 2. Lab Setup

Explain that the repository is independent from any production system. It uses
synthetic deterministic data and a local PostgreSQL environment.

Repository support:

- `compose.yaml`
- `.env.example`
- `sql/00_setup.sql`
- `tests/run_local_pg_tests.sh`
- `tests/run_existing_pg_tests.sh`

Main verification command:

```bash
make test-local
```

## 3. Pre-Checks Before Production DML

Cover affected row count, table size, indexes, table statistics, rollback plan,
maintenance window, and monitoring.

Repository support:

- `docs/production-checklist.md`
- `sql/50_explain_one_update_batch.sql`

## 4. Test One Batch

Show why a representative batch should be tested with:

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
...
ROLLBACK;
```

Repository support:

- `sql/50_explain_one_update_batch.sql`
- `docs/samples/explain-update-batch.txt`

## 5. Recommended Path: Generated SQL Batches

Present generated SQL as the default operational model for one-time production
maintenance.

Repository support:

- `sql/10_generated_update_batches_generator.sql`
- `sql/11_generated_delete_batches_generator.sql`
- `scripts/generate_update_batches.sh`
- `scripts/generate_delete_batches.sh`
- `scripts/run_generated_update.sh`
- `scripts/run_generated_delete.sh`
- `scripts/run_sql_logged.sh`
- `docs/samples/generated-update-batch.sql`
- `docs/samples/generated-delete-batch.sql`
- `docs/samples/run-log.txt`

Core flow:

```text
generate -> review -> run with psql -> log -> monitor -> stop/resume -> validate
```

## 6. UPDATE Walkthrough

Use the timestamp backfill as the primary UPDATE example.

Repository support:

- `dml_lab.transaction_log`
- `dml_lab.transaction_log_backfill_stats`
- `sql/10_generated_update_batches_generator.sql`
- `sql/20_procedure_update.sql`
- `sql/30_queue_update.sql`

## 7. DELETE Walkthrough

Use historical audit cleanup as the primary DELETE example.

Repository support:

- `dml_lab.audit_record`
- `dml_lab.audit_record_delete_stats`
- `sql/11_generated_delete_batches_generator.sql`
- `sql/40_delete_procedure.sql`
- `docs/when-not-to-use-row-delete.md`

Important article point:

```text
For historical deletion, partition detach/drop is usually better than row delete.
```

## 8. Stop And Resume

Show that stopping the process rolls back only the current batch and preserves
already committed batches.

Repository support:

- `docs/generated-first-runbook.md`
- generated SQL files from `make generate-update` and `make generate-delete`

## 9. Procedure Alternative

Show procedures as a secondary approach for repeatable database-side maintenance,
not as the default for one-time production work.

Repository support:

- `sql/20_procedure_update.sql`
- `sql/40_delete_procedure.sql`
- `sql/60_transaction_caveats.sql`

Required caveats:

- `DO $$ ... LOOP` and functions without transaction control are still one
  transaction;
- `pg_sleep()` inside one large transaction does not solve WAL, vacuum, lock,
  bloat, rollback, or replication impact;
- `CALL` with internal transaction control must be top-level;
- external transaction wrappers break it;
- `GET DIAGNOSTICS ROW_COUNT` must be read immediately after DML;
- `TEMP TABLE ... ON COMMIT DROP` breaks after an internal `COMMIT`.
- `ctid` is not the default general-purpose batching key.

## 10. Concurrent Workers

Explain when `FOR UPDATE SKIP LOCKED` is appropriate.

Repository support:

- `sql/30_queue_update.sql`
- `sql/40_delete_procedure.sql`

## 11. Monitoring

Cover `pg_stat_activity`, `pg_locks`, `pg_stat_user_tables`,
`pg_stat_replication`, provider metrics, and application latency.

Repository support:

- `docs/production-checklist.md`

## 12. Post-Operation Work

Cover validation, dead tuples, `VACUUM (ANALYZE)`, and why `VACUUM FULL` is
usually not a hot-production cleanup tool.

Repository support:

- `docs/production-checklist.md`

## 13. Demo Flow

Use the repository as a live master class/demo script.

Repository support:

- `docs/demo-script.md`

## 14. Summary

Final message:

```text
Generated SQL batches are boring, reviewable, stoppable, resumable, and native
to PostgreSQL tooling. For one-time massive DML, that operational control is
usually more valuable than hiding the loop inside code.
```
