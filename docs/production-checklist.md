# Production Checklist

This checklist is intentionally tool-agnostic. The lab uses local PostgreSQL and
synthetic data; production execution must use the actual database, workload,
maintenance window, observability, and rollback requirements.

## Before

- Confirm the exact database, schema, table, and predicate.
- Count affected rows.
- Check table and index sizes.
- Check primary key or batching key distribution.
- Confirm the predicate is idempotent.
- Confirm the update does not rewrite already-correct values.
- Confirm the DELETE predicate cannot delete fresh or unrelated rows.
- For timestamp backfills, validate source units, target type, and timezone
  semantics.
- Check relevant indexes with `pg_get_indexdef`.
- For `ORDER BY ... LIMIT` DELETE selectors, confirm a matching index and test
  the exact plan.
- Run one representative batch with `EXPLAIN (ANALYZE, BUFFERS)` inside
  `BEGIN ... ROLLBACK`.
- Select initial batch size from measured batch cost, not from habit.
- Select sleep interval between committed batches.
- Set `lock_timeout` per batch.
- Set `statement_timeout` per batch.
- Decide rollback strategy before the first commit.
- Decide whether a backup table is required.
- Confirm replication lag monitoring is available.
- Confirm application latency monitoring is available.
- Confirm disk I/O, CPU, storage, and connection metrics are available.
- Generate the SQL file.
- Review the generated SQL file.
- Confirm every batch has explicit `BEGIN` and `COMMIT`.
- Confirm `pg_sleep()` is after `COMMIT`.
- Confirm the runner uses `psql -v ON_ERROR_STOP=1`.
- Confirm the runner or migration tool does not wrap the whole file in one
  external transaction.
- Confirm logs are written somewhere durable enough for the maintenance task.
- Run from a stable host, job runner, bastion, or controlled session.

## During

- Watch `pg_stat_activity`.
- Watch waits and blockers.
- Watch locks on the target table.
- Watch replication lag.
- Watch application latency.
- Watch database CPU and disk I/O.
- Watch storage growth.
- Watch dead tuples.
- Watch per-batch duration in logs.
- Stop if impact becomes unacceptable.
- If stopped, inspect committed progress from database state, not terminal
  memory.

## Stop Criteria

Stop or pause when:

- replication lag grows beyond the agreed threshold;
- application latency degrades;
- lock waits appear on critical application paths;
- batch duration grows unexpectedly;
- disk I/O is saturated;
- storage growth is unsafe;
- error rate increases;
- the actual rows affected differ from expectation.

## Resume

- Count remaining rows from the database.
- Regenerate batches from remaining rows or trim the generated file carefully.
- Reduce batch size if needed.
- Increase sleep interval if needed.
- Re-run with `ON_ERROR_STOP`.
- Keep the previous log file.
- Start a new log file for the resumed run.

## After

- Validate remaining rows.
- Validate sample transformed rows.
- Validate row counts if rows were deleted.
- Check `pg_stat_user_tables`.
- Check dead tuples.
- Run or schedule `VACUUM (ANALYZE)` if needed.
- Do not run `VACUUM FULL` on a hot production table unless the lock and rewrite
  cost are explicitly accepted.
- Attach execution logs to the task.
- Attach the final summary to the task.

## Execution Summary Template

```text
Database:
Table:
Operation:
Execution model:
Runner:
Batch size:
Sleep:
Total batches:
Started:
Finished:
Rows changed:
Rollback strategy:
Monitoring checked:
Observed impact:
Post-operation validation:
Vacuum/analyze action:
Logs:
Follow-up:
```
