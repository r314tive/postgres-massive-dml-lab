#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_SQL="$REPO_DIR/generated/test_generated_update.sql"
GENERATED_DELETE_SQL="$REPO_DIR/generated/test_generated_delete.sql"

mkdir -p "$REPO_DIR/generated"

PSQL=("$REPO_DIR/scripts/psql.sh")

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

expect_sql_failure() {
  local label="$1"
  local sql="$2"

  if "${PSQL[@]}" -c "$sql" >/dev/null 2>&1; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi

  echo "PASS: $label failed as expected"
}

echo "Test 1: setup and representative EXPLAIN"
reset_lab
assert_eq "50000" "$(sql_scalar "SELECT total_rows FROM dml_lab.transaction_log_backfill_stats;")" "transaction_log row count"
assert_eq "30000" "$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")" "audit_record row count"
"${PSQL[@]}" -f "$REPO_DIR/sql/50_explain_one_update_batch.sql" >/dev/null
echo "PASS: representative EXPLAIN ran inside rollback"

echo "Test 2: generated SQL update batches"
reset_lab
"$REPO_DIR/scripts/generate_update_batches.sh" "$GENERATED_SQL"
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
expect_sql_failure \
  "procedure with internal COMMIT inside external transaction" \
  "BEGIN; CALL dml_lab.backfill_transaction_log_timestamps(3500, 0); COMMIT;"
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
"$REPO_DIR/scripts/generate_delete_batches.sh" "$GENERATED_DELETE_SQL"
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
expect_sql_failure \
  "TEMP TABLE ON COMMIT DROP with internal COMMIT loop" \
  "CALL dml_lab.bad_temp_table_on_commit_drop_demo();"

echo "Test 8: configurable data volume"
TRANSACTION_ROWS=12345 \
AUDIT_ROWS=6789 \
OLD_AUDIT_ROWS=2345 \
TRANSACTION_PAYLOAD_BYTES=10 \
AUDIT_PAYLOAD_BYTES=10 \
"$REPO_DIR/scripts/reset_lab.sh" >/dev/null
assert_eq "12345" "$(sql_scalar "SELECT total_rows FROM dml_lab.transaction_log_backfill_stats;")" "custom transaction_log row count"
assert_eq "6789" "$(sql_scalar "SELECT total_rows FROM dml_lab.audit_record_delete_stats;")" "custom audit_record row count"
assert_eq "2345" "$(sql_scalar "SELECT old_rows FROM dml_lab.audit_record_delete_stats;")" "custom old audit rows"

echo "All tests passed"
