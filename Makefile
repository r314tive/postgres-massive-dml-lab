SHELL := /usr/bin/env bash

COMPOSE ?= docker compose
ENV_FILE ?= $(if $(wildcard .env),.env,.env.example)

.DEFAULT_GOAL := help

.PHONY: help
help:
	@printf '%s\n' 'Targets:'
	@printf '%s\n' '  make test-local       Run full test suite on a temporary local PostgreSQL cluster'
	@printf '%s\n' '  make docker-up        Start Docker PostgreSQL environment'
	@printf '%s\n' '  make docker-down      Stop Docker PostgreSQL environment'
	@printf '%s\n' '  make docker-reset     Recreate Docker PostgreSQL data and load lab schema'
	@printf '%s\n' '  make setup-docker     Load schema/data into Docker PostgreSQL'
	@printf '%s\n' '  make setup-large      Load larger demo data into Docker PostgreSQL'
	@printf '%s\n' '  make demo-prepare     Load larger demo data and generate UPDATE/DELETE files'
	@printf '%s\n' '  make test-docker      Run the same SQL scenarios against Docker PostgreSQL'
	@printf '%s\n' '  make psql             Open psql against Docker PostgreSQL'
	@printf '%s\n' '  make explain          Run representative EXPLAIN (ANALYZE, BUFFERS)'
	@printf '%s\n' '  make monitor          Show active sessions, locks, table stats, and progress'
	@printf '%s\n' '  make generate-update  Generate reviewable committed UPDATE batches'
	@printf '%s\n' '  make generate-delete  Generate reviewable committed DELETE batches'
	@printf '%s\n' '  make run-generated    Execute generated UPDATE batches'
	@printf '%s\n' '  make run-delete       Execute generated DELETE batches'
	@printf '%s\n' '  make noisia-help      Show noisia help via Docker Compose'
	@printf '%s\n' '  make noisia-wait      Run noisia waiting-transactions workload'
	@printf '%s\n' '  make noisia-idle      Run noisia idle-transactions workload'
	@printf '%s\n' '  make noisia-temp      Run noisia temp-files workload'
	@printf '%s\n' '  make noisia-rollbacks Run noisia rollback workload'
	@printf '%s\n' '  make noisia-cleanup   Remove noisia workload tables'

.PHONY: test-local
test-local:
	./tests/run_local_pg_tests.sh

.PHONY: docker-up
docker-up:
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	./scripts/wait_for_pg.sh

.PHONY: docker-down
docker-down:
	$(COMPOSE) --env-file $(ENV_FILE) down

.PHONY: docker-reset
docker-reset:
	$(COMPOSE) --env-file $(ENV_FILE) down -v
	$(COMPOSE) --env-file $(ENV_FILE) up -d
	./scripts/wait_for_pg.sh
	./scripts/reset_lab.sh

.PHONY: setup-docker
setup-docker: docker-up
	./scripts/reset_lab.sh

.PHONY: setup-large
setup-large: docker-up
	TRANSACTION_ROWS=1000000 AUDIT_ROWS=500000 OLD_AUDIT_ROWS=250000 \
	TRANSACTION_PAYLOAD_BYTES=200 AUDIT_PAYLOAD_BYTES=200 \
	./scripts/reset_lab.sh

.PHONY: demo-prepare
demo-prepare: setup-large generate-update generate-delete

.PHONY: test-docker
test-docker: docker-up
	./tests/run_existing_pg_tests.sh

.PHONY: psql
psql: docker-up
	./scripts/psql.sh

.PHONY: explain
explain: setup-docker
	./scripts/psql.sh -f sql/50_explain_one_update_batch.sql

.PHONY: monitor
monitor: docker-up
	./scripts/psql.sh -f sql/70_monitoring.sql

.PHONY: generate-update
generate-update: docker-up
	mkdir -p generated
	./scripts/generate_update_batches.sh generated/transaction_log_backfill.sql
	@printf 'Generated: generated/transaction_log_backfill.sql\n'

.PHONY: generate-delete
generate-delete: docker-up
	mkdir -p generated
	./scripts/generate_delete_batches.sh generated/audit_record_delete.sql
	@printf 'Generated: generated/audit_record_delete.sql\n'

.PHONY: run-generated
run-generated:
	./scripts/run_generated_update.sh generated/transaction_log_backfill.sql

.PHONY: run-delete
run-delete:
	./scripts/run_generated_delete.sh generated/audit_record_delete.sql

.PHONY: noisia-help
noisia-help:
	./scripts/run_noisia.sh help

.PHONY: noisia-wait
noisia-wait:
	./scripts/run_noisia.sh wait-xacts

.PHONY: noisia-idle
noisia-idle:
	./scripts/run_noisia.sh idle-xacts

.PHONY: noisia-temp
noisia-temp:
	./scripts/run_noisia.sh temp-files

.PHONY: noisia-rollbacks
noisia-rollbacks:
	./scripts/run_noisia.sh rollbacks

.PHONY: noisia-cleanup
noisia-cleanup:
	./scripts/run_noisia.sh cleanup
