# Reproducible Lab Snippet

The examples in this guide are backed by a reproducible PostgreSQL lab:

```bash
make test-local
```

The lab creates synthetic tables, loads deterministic data, and validates:

* generated SQL batches with explicit `BEGIN` / `COMMIT`;
* generated UPDATE and DELETE execution with `psql` meta commands and logs;
* procedure-based update with internal transaction control;
* queue-based update with `FOR UPDATE SKIP LOCKED`;
* indexed batched delete with `FOR UPDATE SKIP LOCKED`;
* representative `EXPLAIN (ANALYZE, BUFFERS)` inside `BEGIN ... ROLLBACK`;
* failure of procedure transaction control inside an external transaction block;
* failure of `TEMP TABLE ... ON COMMIT DROP` after an internal `COMMIT`.

This keeps the article examples demonstrable instead of purely theoretical.

The recommended path for one-time production maintenance is generated SQL:

```text
generate file -> review file -> run with psql ON_ERROR_STOP -> log with tee
```

Procedures are included as a secondary approach for repeatable database-side
maintenance, but they require top-level `CALL` and careful runner behavior.
