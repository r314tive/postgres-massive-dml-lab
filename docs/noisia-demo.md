# Noisia Demo Workloads

This lab can optionally use
[`lesovsky/noisia`](https://github.com/lesovsky/noisia) to add noisy PostgreSQL
workloads during a massive DML demonstration.

Noisia is intentionally harmful test tooling. Use it only against this local lab
or another disposable database.

## Why Use It Here

Generated SQL batches already show the safe execution model. Noisia adds
background pressure so the demo can also show:

- active sessions in `pg_stat_activity`;
- waits and lock-related symptoms;
- rollback noise;
- temporary file pressure;
- why monitoring matters while batches are running.

Noisia is not required for the core lab and is not used by the automated tests.
Some noisia workloads create and stress their own tables instead of directly
locking `dml_lab.*` tables. That is still useful for demonstrating database
pressure, active sessions, waits, and noisy neighbors during a massive DML run.

## Prepare The Demo

```bash
make demo-prepare
```

The Makefile uses `.env` when it exists, otherwise it falls back to
`.env.example`.

This loads the larger synthetic dataset and generates:

```text
generated/transaction_log_backfill.sql
generated/audit_record_delete.sql
```

## Terminal Layout

Use three terminals or tmux panes.

Terminal 1: monitor:

```bash
make monitor
```

Run it repeatedly while the demo is active.

Terminal 2: start a noisia workload:

```bash
NOISIA_DURATION=120 NOISIA_JOBS=2 make noisia-wait
```

Terminal 3: run generated batches:

```bash
./scripts/run_generated_update.sh generated/transaction_log_backfill.sql
```

## Useful Workloads

Waiting transactions:

```bash
NOISIA_DURATION=120 \
NOISIA_JOBS=2 \
NOISIA_WAIT_LOCKTIME_MIN=5 \
NOISIA_WAIT_LOCKTIME_MAX=15 \
make noisia-wait
```

Idle transactions:

```bash
NOISIA_DURATION=120 \
NOISIA_JOBS=2 \
make noisia-idle
```

Temporary files:

```bash
NOISIA_DURATION=60 \
NOISIA_JOBS=1 \
NOISIA_TEMP_FILES_RATE=2 \
NOISIA_TEMP_FILES_SCALE_FACTOR=10 \
make noisia-temp
```

Rollback noise:

```bash
NOISIA_DURATION=60 \
NOISIA_JOBS=2 \
make noisia-rollbacks
```

Cleanup noisia tables:

```bash
make noisia-cleanup
```

## What Not To Run By Default

Noisia also has workloads that can terminate sessions or exhaust connections.
They are useful for failure-injection experiments, but they are too disruptive
for the normal massive DML demo. This repository intentionally does not expose
Make targets for those modes.

## Demo Point

The point is not that noisia changes the batching strategy. The point is that
committed batches remain reviewable, logged, stoppable, and resumable while the
database is under observable pressure.
