#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${1:-$REPO_DIR/generated/transaction_log_backfill.sql}"
BATCH_SIZE="${BATCH_SIZE:-5000}"
SLEEP_SECONDS="${SLEEP_SECONDS:-0.05}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

"$REPO_DIR/scripts/psql.sh" \
  -q \
  -A \
  -t \
  -v batch_size="$BATCH_SIZE" \
  -v sleep_seconds="$SLEEP_SECONDS" \
  -f "$REPO_DIR/sql/10_generated_update_batches_generator.sql" \
  > "$OUTPUT_FILE"
