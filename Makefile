.PHONY: dev lint format test test-unit pg-up pg-down

# 9.6 by default: it hits the pre-10 code paths this source exists for.
PG_VERSION ?= 9.6
export PG_VERSION

PG_COMPOSE = docker compose -f tests/postgres/docker-compose.yml
PG_TEST_ENV = ALL_DESTINATIONS='["duckdb"]' \
	DESTINATION__POSTGRES__CREDENTIALS=postgresql://loader:loader@localhost:5432/dlt_data

dev:
	uv sync

lint:
	uv run ruff check .

format:
	uv run ruff format .

test: pg-up
	$(PG_TEST_ENV) uv run pytest tests/pg_legacy_replication

# No database needed.
test-unit:
	uv run pytest tests/pg_legacy_replication/test_helpers.py

pg-up:
	$(PG_COMPOSE) up -d --wait

pg-down:
	$(PG_COMPOSE) down -v
