\set ON_ERROR_STOP on
\pset pager off
\x off

\echo '== active sessions =='
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    now() - query_start AS duration,
    wait_event_type,
    wait_event,
    state,
    left(query, 160) AS query
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
ORDER BY query_start NULLS LAST;

\echo '== locks on lab tables =='
SELECT
    a.pid,
    a.application_name,
    now() - a.query_start AS duration,
    a.wait_event_type,
    a.wait_event,
    l.locktype,
    l.mode,
    l.granted,
    l.relation::regclass AS relation,
    left(a.query, 120) AS query
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.relation IN (
    'dml_lab.transaction_log'::regclass,
    'dml_lab.audit_record'::regclass
)
ORDER BY l.granted, a.query_start NULLS LAST;

\echo '== relation locks in current database =='
SELECT
    a.pid,
    a.application_name,
    now() - a.query_start AS duration,
    a.wait_event_type,
    a.wait_event,
    l.mode,
    l.granted,
    l.relation::regclass AS relation,
    left(a.query, 120) AS query
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.database = (
    SELECT oid
    FROM pg_database
    WHERE datname = current_database()
)
  AND l.relation IS NOT NULL
ORDER BY l.granted, a.query_start NULLS LAST, relation::text;

\echo '== table stats =='
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    vacuum_count,
    autovacuum_count,
    analyze_count,
    autoanalyze_count,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'dml_lab'
ORDER BY relname;

\echo '== lab progress =='
SELECT * FROM dml_lab.transaction_log_backfill_stats;
SELECT * FROM dml_lab.audit_record_delete_stats;
