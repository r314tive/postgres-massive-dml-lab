#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${1:-$REPO_DIR/generated/audit_record_delete.sql}"
BATCH_SIZE="${BATCH_SIZE:-5000}"
SLEEP_SECONDS="${SLEEP_SECONDS:-0.05}"
CUTOFF="${CUTOFF:-2026-04-07 00:00:00+00}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

"$REPO_DIR/scripts/psql.sh" \
  -q \
  -A \
  -t \
  -v batch_size="$BATCH_SIZE" \
  -v sleep_seconds="$SLEEP_SECONDS" \
  -v cutoff="'$CUTOFF'" \
  -f "$REPO_DIR/sql/11_generated_delete_batches_generator.sql" \
  > "$OUTPUT_FILE"
