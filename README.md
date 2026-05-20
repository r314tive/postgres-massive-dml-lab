# PostgreSQL Massive DML Lab

Reproducible PostgreSQL environment for showing and testing production-safe
massive `UPDATE` and `DELETE` patterns.

This repository is intentionally a lab, not a production migration package. It
creates synthetic tables from scratch, loads deterministic data, and proves the
examples with real PostgreSQL transactions.

## What It Demonstrates

- Why the safe unit of work is a committed batch.
- How to create small or large deterministic datasets for experiments.
- Generated SQL batches with explicit `BEGIN` / `COMMIT`.
- Generated SQL execution with `psql` meta commands, `tee`, `tmux`, and `nohup`.
- Optional noisy PostgreSQL demo workloads with `lesovsky/noisia`.
- Procedure-based update with internal transaction control.
- Why procedures with internal `COMMIT` must be called top-level.
- Queue-based update with `FOR UPDATE SKIP LOCKED`.
- Indexed batched delete with `FOR UPDATE SKIP LOCKED`.
- Representative `EXPLAIN (ANALYZE, BUFFERS)` inside `BEGIN ... ROLLBACK`.
- Why `TEMP TABLE ... ON COMMIT DROP` is incompatible with internal commit loops.

## Requirements

For the fully self-contained test runner:

- PostgreSQL binaries in `PATH`: `initdb`, `pg_ctl`, `psql`
- Bash
- PostgreSQL 11+ for procedure transaction control

For the interactive Docker environment:

- Docker
- Docker Compose v2
- `psql` and `pg_isready` on the host

## Fastest Verification

```bash
make test-local
```

This starts a temporary local PostgreSQL cluster, runs the full test suite, and
stops the server. It does not require Docker.

## Interactive Docker Lab

```bash
make docker-reset
make psql
```

The Makefile uses `.env` when it exists, otherwise it falls back to
`.env.example`.

Useful targets:

```bash
make explain
make generate-update
make generate-delete
make run-generated
make run-delete
make test-docker
make docker-down
```

To load a larger demo dataset:

```bash
make setup-large
```

To prepare a full demo run with generated SQL files:

```bash
make demo-prepare
```

Optional noisy workload demo:

```bash
NOISIA_DURATION=120 NOISIA_JOBS=2 make noisia-wait
```

## Repository Layout

- `sql/00_setup.sql`  
  Creates `dml_lab.transaction_log`, `dml_lab.audit_record`, indexes, views, and
  deterministic data.

- `sql/10_generated_update_batches_generator.sql`  
  Generates executable update batches with explicit transaction boundaries.

- `sql/20_procedure_update.sql`  
  Defines a procedure that commits each id-range update batch internally.

- `sql/30_queue_update.sql`  
  Defines and fills a queue table, then provides a queue-based update procedure.

- `sql/40_delete_procedure.sql`  
  Defines an indexed batched delete procedure.

- `sql/50_explain_one_update_batch.sql`  
  Runs one representative `EXPLAIN (ANALYZE, BUFFERS)` batch inside rollback.

- `sql/60_transaction_caveats.sql`  
  Contains deliberately bad transaction-control examples for demonstration.

- `tests/run_local_pg_tests.sh`  
  Starts temporary PostgreSQL with `initdb` / `pg_ctl` and runs the full suite.

- `tests/run_existing_pg_tests.sh`  
  Runs the same suite against an already running PostgreSQL instance, usually
  the Docker environment.

- `docs/demo-script.md`  
  Step-by-step flow for a live explanation or master class.

- `docs/noisia-demo.md`
  Optional noisy workload demo using `lesovsky/noisia`.

- `docs/generated-first-runbook.md`
  Main operational runbook. It treats generated SQL as the primary production
  maintenance approach and procedures as the secondary approach.

- `docs/production-checklist.md`  
  Production-oriented pre-check, monitoring, resume, and post-operation
  checklist.

- `docs/when-not-to-use-row-delete.md`  
  Notes on partition detach/drop, rebuild/swap, and cases where row-by-row
  `DELETE` batches should not be the first choice.

- `docs/article-outline.md`  
  Suggested structure for a long-form article backed by this repository.

- `docs/wiki-snippet.md`  
  Short neutral text that can be pasted into a wiki article to point readers to
  this lab.

- `docs/samples/`  
  Shortened generated SQL, run log, and `EXPLAIN` samples for article evidence.

## Manual Batch Generation

Generated SQL must be produced with quiet unaligned output:

```bash
./scripts/generate_update_batches.sh generated/transaction_log_backfill.sql
```

For DELETE:

```bash
./scripts/generate_delete_batches.sh generated/audit_record_delete.sql
```

Equivalent raw `psql` form:

```bash
psql -q -X -A -t \
  -v batch_size=5000 \
  -v sleep_seconds=0.05 \
  -f sql/10_generated_update_batches_generator.sql \
  > generated/transaction_log_backfill.sql
```

The generated file should contain repeated blocks:

```sql
BEGIN;
...
COMMIT;
SELECT pg_sleep(...);
```

Run generated files with logging:

```bash
./scripts/run_generated_update.sh generated/transaction_log_backfill.sql
./scripts/run_generated_delete.sh generated/audit_record_delete.sql
```

## Demo Workloads

The lab includes optional `lesovsky/noisia` integration through Docker Compose.
It is intended for local/demo use only.

```bash
make noisia-help
make noisia-wait
make noisia-idle
make noisia-temp
make noisia-rollbacks
make noisia-cleanup
```

See `docs/noisia-demo.md`.

## Production Notes

- Generated SQL batches are the default recommendation for one-time production
  maintenance because the final file is reviewable.
- A procedure with internal `COMMIT` must be called top-level. Do not wrap it in
  external `BEGIN ... COMMIT`.
- Sleep belongs between committed batches, not inside one long transaction.
- The lab uses `timestamptz` and `SET LOCAL TimeZone = 'UTC'`. If a production
  table uses `timestamp without time zone`, validate timezone semantics before
  backfill.
- Always validate real production predicates and indexes with
  `EXPLAIN (ANALYZE, BUFFERS)`.
- For historical deletion, prefer partition detach/drop when the table design
  supports it. Row-by-row `DELETE` batches are a fallback, not the universal
  best option.

## License

MIT. See `LICENSE`.
