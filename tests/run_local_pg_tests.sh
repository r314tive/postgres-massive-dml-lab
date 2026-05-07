#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_bin() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required binary: $name" >&2
    exit 1
  fi
}

require_bin initdb
require_bin pg_ctl
require_bin psql

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/massive-dml-pgtest.XXXXXX")"
PGDATA="$TMP_ROOT/data"
SOCKDIR="$TMP_ROOT/socket"
LOGFILE="$TMP_ROOT/postgres.log"
GENERATED_SQL="$TMP_ROOT/generated_update.sql"
GENERATED_DELETE_SQL="$TMP_ROOT/generated_delete.sql"
PORT="$((54000 + RANDOM % 10000))"
DB_USER="$(id -un)"

mkdir -p "$SOCKDIR"

server_started=0
cleanup() {
  if [[ "$server_started" == "1" ]]; then
    pg_ctl -D "$PGDATA" -w stop >/dev/null
  fi
}
trap cleanup EXIT

echo "Temporary test directory: $TMP_ROOT"

initdb -D "$PGDATA" --no-locale -E UTF8 -A trust >/dev/null
pg_ctl -D "$PGDATA" \
  -o "-F -k $SOCKDIR -p $PORT -c listen_addresses=''" \
  -l "$LOGFILE" \
  -w start >/dev/null
server_started=1

PSQL=(psql -h "$SOCKDIR" -p "$PORT" -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -X)

sql_scalar() {
  "${PSQL[@]}" -A -t -c "$1"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label, expected '$expected', got '$actual'" >&2
    exit 1
  fi

  echo "PASS: $label"
}

reset_lab() {
  "${PSQL[@]}" -f "$REPO_DIR/sql/00_setup.sql" >/dev/null
}

assert_backfill_complete() {
  assert_eq "0" "$(sql_scalar "SELECT backfillable_remaining FROM dml_lab.transaction_log_backfill_stats;")" "$1 backfillable rows remaining"
}

echo "Test 1: setup and representative EXPLAIN"
reset_lab
assert_eq "50000" "$(sql_scalar "SELECT total_rows FROM dml_lab.transaction_log_backfill_stats;")" "transaction_log row count"
assert_eq "30000" "$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")" "audit_record row count"
"${PSQL[@]}" -f "$REPO_DIR/sql/50_explain_one_update_batch.sql" >/dev/null
echo "PASS: representative EXPLAIN ran inside rollback"

echo "Test 2: generated SQL update batches"
reset_lab
"${PSQL[@]}" -q -v batch_size=4000 -v sleep_seconds=0 -A -t \
  -f "$REPO_DIR/sql/10_generated_update_batches_generator.sql" > "$GENERATED_SQL"
if ! grep -q '^BEGIN;$' "$GENERATED_SQL"; then
  echo "FAIL: generated SQL does not contain explicit BEGIN" >&2
  exit 1
fi
if ! grep -q '^COMMIT;$' "$GENERATED_SQL"; then
  echo "FAIL: generated SQL does not contain explicit COMMIT" >&2
  exit 1
fi
"${PSQL[@]}" -f "$GENERATED_SQL" >/dev/null
assert_backfill_complete "generated SQL"
assert_eq "2941" "$(sql_scalar "SELECT created_source_null_rows FROM dml_lab.transaction_log_backfill_stats;")" "created source-null rows preserved"
assert_eq "2631" "$(sql_scalar "SELECT processed_source_null_rows FROM dml_lab.transaction_log_backfill_stats;")" "processed source-null rows preserved"

echo "Test 3: procedure update with internal commits"
reset_lab
"${PSQL[@]}" -f "$REPO_DIR/sql/20_procedure_update.sql" >/dev/null
if "${PSQL[@]}" -c "BEGIN; CALL dml_lab.backfill_transaction_log_timestamps(3500, 0); COMMIT;" >/dev/null 2>&1; then
  echo "FAIL: procedure with internal COMMIT inside external transaction unexpectedly succeeded" >&2
  exit 1
fi
echo "PASS: procedure with internal COMMIT inside external transaction failed as expected"
"${PSQL[@]}" -c "CALL dml_lab.backfill_transaction_log_timestamps(3500, 0);" >/dev/null
assert_backfill_complete "procedure"

echo "Test 4: queue-based update"
reset_lab
"${PSQL[@]}" -f "$REPO_DIR/sql/30_queue_update.sql" >/dev/null
QUEUE_INITIAL="$(sql_scalar "SELECT count(*) FROM dml_lab.transaction_update_queue WHERE status = 'pending';")"
if [[ "$QUEUE_INITIAL" == "0" ]]; then
  echo "FAIL: queue was not populated" >&2
  exit 1
fi
echo "PASS: queue populated with $QUEUE_INITIAL ids"
"${PSQL[@]}" -c "CALL dml_lab.backfill_transaction_log_timestamps_from_queue(2500, 0);" >/dev/null
assert_backfill_complete "queue procedure"
assert_eq "0" "$(sql_scalar "SELECT count(*) FROM dml_lab.transaction_update_queue WHERE status = 'pending';")" "queue pending rows"
assert_eq "$QUEUE_INITIAL" "$(sql_scalar "SELECT count(*) FROM dml_lab.transaction_update_queue WHERE status = 'done';")" "queue done rows"

echo "Test 5: batched delete procedure"
reset_lab
"${PSQL[@]}" -f "$REPO_DIR/sql/40_delete_procedure.sql" >/dev/null
OLD_ROWS="$(sql_scalar "SELECT old_rows FROM dml_lab.audit_record_delete_stats;")"
TOTAL_ROWS="$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")"
"${PSQL[@]}" -c "CALL dml_lab.delete_old_audit_records(TIMESTAMPTZ '2026-04-07 00:00:00+00', 2500, 0);" >/dev/null
assert_eq "0" "$(sql_scalar "SELECT old_rows FROM dml_lab.audit_record_delete_stats;")" "old audit rows deleted"
assert_eq "$((TOTAL_ROWS - OLD_ROWS))" "$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")" "new audit rows preserved"

echo "Test 6: generated SQL delete batches"
reset_lab
"${PSQL[@]}" -q -v batch_size=4000 -v sleep_seconds=0 -A -t \
  -f "$REPO_DIR/sql/11_generated_delete_batches_generator.sql" > "$GENERATED_DELETE_SQL"
if ! grep -q '^BEGIN;$' "$GENERATED_DELETE_SQL"; then
  echo "FAIL: generated delete SQL does not contain explicit BEGIN" >&2
  exit 1
fi
if ! grep -q '^COMMIT;$' "$GENERATED_DELETE_SQL"; then
  echo "FAIL: generated delete SQL does not contain explicit COMMIT" >&2
  exit 1
fi
OLD_ROWS="$(sql_scalar "SELECT old_rows FROM dml_lab.audit_record_delete_stats;")"
TOTAL_ROWS="$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")"
"${PSQL[@]}" -f "$GENERATED_DELETE_SQL" >/dev/null
assert_eq "0" "$(sql_scalar "SELECT old_rows FROM dml_lab.audit_record_delete_stats;")" "generated delete old audit rows"
assert_eq "$((TOTAL_ROWS - OLD_ROWS))" "$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")" "generated delete new audit rows preserved"

echo "Test 7: temp table ON COMMIT DROP caveat"
reset_lab
"${PSQL[@]}" -f "$REPO_DIR/sql/60_transaction_caveats.sql" >/dev/null
if "${PSQL[@]}" -c "CALL dml_lab.bad_temp_table_on_commit_drop_demo();" >/dev/null 2>&1; then
  echo "FAIL: TEMP TABLE ON COMMIT DROP with internal COMMIT loop unexpectedly succeeded" >&2
  exit 1
fi
echo "PASS: TEMP TABLE ON COMMIT DROP with internal COMMIT loop failed as expected"

echo "Test 8: configurable data volume"
"${PSQL[@]}" \
  -v transaction_rows=12345 \
  -v audit_rows=6789 \
  -v old_audit_rows=2345 \
  -v transaction_payload_bytes=10 \
  -v audit_payload_bytes=10 \
  -f "$REPO_DIR/sql/00_setup.sql" >/dev/null
assert_eq "12345" "$(sql_scalar "SELECT total_rows FROM dml_lab.transaction_log_backfill_stats;")" "custom transaction_log row count"
assert_eq "6789" "$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")" "custom audit_record row count"
assert_eq "2345" "$(sql_scalar "SELECT old_rows FROM dml_lab.audit_record_delete_stats;")" "custom old audit rows"

echo "All tests passed"
