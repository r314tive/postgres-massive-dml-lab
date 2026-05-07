#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$REPO_DIR/scripts/psql.sh" \
  -v transaction_rows="${TRANSACTION_ROWS:-50000}" \
  -v audit_rows="${AUDIT_ROWS:-30000}" \
  -v old_audit_rows="${OLD_AUDIT_ROWS:-12000}" \
  -v transaction_payload_bytes="${TRANSACTION_PAYLOAD_BYTES:-100}" \
  -v audit_payload_bytes="${AUDIT_PAYLOAD_BYTES:-120}" \
  -f "$REPO_DIR/sql/00_setup.sql"
