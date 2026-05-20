#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/run_noisia.sh help
  scripts/run_noisia.sh wait-xacts [extra noisia args...]
  scripts/run_noisia.sh idle-xacts [extra noisia args...]
  scripts/run_noisia.sh temp-files [extra noisia args...]
  scripts/run_noisia.sh rollbacks [extra noisia args...]
  scripts/run_noisia.sh cleanup

Environment:
  NOISIA_DURATION=60
  NOISIA_JOBS=2
  NOISIA_CONNINFO='host=postgres port=5432 dbname=massive_dml_lab user=postgres password=postgres sslmode=disable'

This script runs noisia inside the Docker Compose network against the lab
PostgreSQL container. Use it only for local/demo environments.
USAGE
}

ENV_FILE="${ENV_FILE:-.env}"
if [[ "$ENV_FILE" = /* ]]; then
  ENV_PATH="$ENV_FILE"
else
  ENV_PATH="$REPO_DIR/$ENV_FILE"
fi

if [[ -f "$ENV_PATH" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_PATH"
  set +a
fi

read -r -a COMPOSE_CMD <<< "${COMPOSE:-docker compose}"
COMPOSE_ARGS=()
if [[ -f "$ENV_PATH" ]]; then
  COMPOSE_ARGS+=(--env-file "$ENV_PATH")
fi

POSTGRES_DB="${POSTGRES_DB:-massive_dml_lab}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
NOISIA_CONNINFO="${NOISIA_CONNINFO:-host=postgres port=5432 dbname=$POSTGRES_DB user=$POSTGRES_USER password=$POSTGRES_PASSWORD sslmode=disable}"
NOISIA_DURATION="${NOISIA_DURATION:-60}"
NOISIA_JOBS="${NOISIA_JOBS:-2}"

WORKLOAD="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$WORKLOAD" in
  help|-h|--help)
    usage
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm noisia --help
    exit 0
    ;;
  wait-xacts)
    WORKLOAD_ARGS=(
      --wait-xacts
      --wait-xacts.locktime-min="${NOISIA_WAIT_LOCKTIME_MIN:-5}"
      --wait-xacts.locktime-max="${NOISIA_WAIT_LOCKTIME_MAX:-15}"
    )
    ;;
  idle-xacts)
    WORKLOAD_ARGS=(
      --idle-xacts
      --idle-xacts.naptime-min="${NOISIA_IDLE_NAPTIME_MIN:-5}"
      --idle-xacts.naptime-max="${NOISIA_IDLE_NAPTIME_MAX:-20}"
    )
    ;;
  temp-files)
    WORKLOAD_ARGS=(
      --temp-files
      --temp-files.rate="${NOISIA_TEMP_FILES_RATE:-2}"
      --temp-files.scale-factor="${NOISIA_TEMP_FILES_SCALE_FACTOR:-10}"
    )
    ;;
  rollbacks)
    WORKLOAD_ARGS=(
      --rollbacks
      --rollbacks.min-rate="${NOISIA_ROLLBACKS_MIN_RATE:-5}"
      --rollbacks.max-rate="${NOISIA_ROLLBACKS_MAX_RATE:-20}"
    )
    ;;
  cleanup)
    WORKLOAD_ARGS=(--cleanup)
    ;;
  *)
    usage >&2
    echo "Unknown noisia workload: $WORKLOAD" >&2
    exit 2
    ;;
esac

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d postgres
"$REPO_DIR/scripts/wait_for_pg.sh"

RUN_ARGS=(--conninfo "$NOISIA_CONNINFO")
if [[ "$WORKLOAD" != "cleanup" ]]; then
  RUN_ARGS+=(--duration "$NOISIA_DURATION" --jobs "$NOISIA_JOBS")
fi

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm noisia \
  "${RUN_ARGS[@]}" \
  "${WORKLOAD_ARGS[@]}" \
  "$@"
