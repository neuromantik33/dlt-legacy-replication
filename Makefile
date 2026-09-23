SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --silent

## Uv / python
dev: ## Prepare the dev environment
	uv sync
.PHONY: dev

install-hooks: ## Install the prek git hooks
	prek install
.PHONY: install-hooks

ci: typecheck lint test-cov ## Run all checks (test, lint, typecheck)
.PHONY: ci

lint: ## Run linting tasks
	uv run ruff check
.PHONY: lint

format: ## Run formatters
	uv run ruff check --select I,F401 --fix
	uv run ruff format
.PHONY: format

typecheck: ## Run type checkers
	uv run pyrefly check
.PHONY: typecheck

## Testing

# 9.6 by default: it hits the pre-10 code paths this source exists for.
PG_VERSION ?= 9.6
export PG_VERSION

PG_TEST_ENV = ALL_DESTINATIONS='["duckdb"]' \
	DESTINATION__POSTGRES__CREDENTIALS=postgresql://loader:loader@localhost:5432/dlt_data

test: ## Run tests
	$(PG_TEST_ENV) uv run pytest
.PHONY: test

test-cov: ## Run tests with coverage
	$(PG_TEST_ENV) uv run pytest --cov
.PHONY: test-cov

PG_COMPOSE = docker compose -f tests/postgres/docker-compose.yml

pg-up:
	$(PG_COMPOSE) up -d --wait
.PHONY: pg-up

pg-down:
	$(PG_COMPOSE) down -v
.PHONY: pg-down

.DEFAULT_GOAL := help
help: Makefile
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | \
	sed 's/^Makefile://' | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | \
	sed -e 's/\[32m##/[33m/'
