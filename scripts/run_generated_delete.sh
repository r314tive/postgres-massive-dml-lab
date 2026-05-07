#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_SQL="${1:-$REPO_DIR/generated/audit_record_delete.sql}"

if [[ ! -f "$GENERATED_SQL" ]]; then
  echo "Generated SQL file not found: $GENERATED_SQL" >&2
  echo "Run: make generate-delete" >&2
  exit 1
fi

"$REPO_DIR/scripts/run_sql_logged.sh" "$GENERATED_SQL"
