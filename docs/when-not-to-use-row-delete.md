# When Not To Use Row DELETE

Committed row-delete batches are a fallback for cases where the data cannot be
removed more cleanly. They are safer than one huge `DELETE`, but they still
generate WAL, create dead tuples, consume I/O, and require vacuum work.

## Prefer Partition Operations For Historical Retention

If the table is partitioned by time and the operation is retention cleanup,
prefer dropping or detaching old partitions.

Typical model:

```sql
ALTER TABLE events DETACH PARTITION events_2026_01;
DROP TABLE events_2026_01;
```

This is usually much cheaper than deleting millions of rows because PostgreSQL
does not need to visit and delete each row individually.

Use the exact locking and availability behavior for your PostgreSQL version and
table design. Test the operation on a production-like schema before using it in
production.

## Prefer Rebuild Or Swap For Large Table Rewrites

If most rows must be deleted or rewritten, consider building a new table with the
kept rows and swapping objects during a controlled maintenance window.

This can be better when:

- the operation touches most of the table;
- the resulting table should be physically smaller immediately;
- index rebuild cost is acceptable;
- application downtime or dual-write complexity is acceptable.

This is an application- and environment-specific migration, not a generic recipe.

## Prefer Application Jobs For Business Workflows

If the change requires business logic, external calls, audit events, cache
invalidation, search indexing, or domain-specific retries, a database-only DML
script may be the wrong boundary.

Use an application job when correctness depends on application behavior outside
PostgreSQL.

## Use Row DELETE Batches When

- partition detach/drop is not available;
- only a subset of rows is affected;
- the predicate is clear and indexed;
- the operation can tolerate gradual cleanup;
- dead tuple cleanup is planned;
- the operation can be stopped and resumed;
- logs and monitoring are in place.

## Required Checks For Row DELETE

- Count rows to delete.
- Confirm the predicate.
- Confirm the matching index.
- Test one batch with `EXPLAIN (ANALYZE, BUFFERS)`.
- Watch locks, WAL, replication lag, I/O, storage, and dead tuples.
- Plan `VACUUM (ANALYZE)` after the operation.
