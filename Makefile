.PHONY: help up down test test-arxiv test-arxiv-ml test-mcp test-eval test-rag smoke-e2e logs status status-report install-ollama pull-models rotate-key check-secrets prune-builder df monitoring-up monitoring-down cache-up verify-redis verify-monitoring seed-rag backup-postgres backup-qdrant backup-all mcp-stdio-up mcp-stdio-down

# Workspace root Makefile for the AI Infrastructure Platform
#
# Targets:
#   make up              # Start all services via docker-compose
#   make down            # Stop all services
#   make test            # Run tests in all 4 projects
#   make smoke-e2e       # Run end-to-end smoke test (ingest → query → evaluate)
#   make install-ollama  # Install Ollama CLI (Linux x86_64)
#   make pull-models     # Pull required Ollama models

COMPOSE ?= docker compose
ENV_FILE ?= .env

# Prefer the workspace virtualenv when present; CI/fresh clones fall back to
# python3 on PATH. Keep this absolute so `cd`-ing into a subproject still works.
PYTHON ?= python3
ifneq ($(wildcard venv/bin/python),)
PYTHON := $(CURDIR)/venv/bin/python
endif

# ──────────────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────────────

help:  ## Show this help
	@echo "AI Infrastructure Workspace — Make targets"
	@echo "=========================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# ──────────────────────────────────────────────────────────────────────
# Docker Compose
# ──────────────────────────────────────────────────────────────────────

up:  ## Start all services via docker-compose
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "No $(ENV_FILE) found — copying from .env.example"; \
		cp $(ENV_FILE).example $(ENV_FILE); \
	fi
	$(COMPOSE) --env-file $(ENV_FILE) up -d

down:  ## Stop all services
	$(COMPOSE) down

logs:  ## Follow logs (service name optional, e.g. make logs SERVICE=arxiv-go-backend)
	$(COMPOSE) --env-file $(ENV_FILE) logs -f $(SERVICE)

status:  ## Show service status
	$(COMPOSE) --env-file $(ENV_FILE) ps

status-report:  ## Generate STATUS.md from executed checks
	bash scripts/generate_status.sh

monitoring-up:  ## Start monitoring only (redis, prometheus, grafana)
	$(COMPOSE) --env-file $(ENV_FILE) --profile monitoring up -d redis prometheus grafana

monitoring-down:  ## Stop monitoring only (core stack tetap jalan)
	$(COMPOSE) --env-file $(ENV_FILE) --profile monitoring stop redis prometheus grafana

cache-up:  ## Start Redis and recreate rag-api with response cache enabled
	$(COMPOSE) --env-file $(ENV_FILE) --profile monitoring up -d redis
	REDIS_ENABLED=true $(COMPOSE) --env-file $(ENV_FILE) up -d --no-deps --force-recreate rag-api

verify-redis: cache-up  ## Verify Redis cache hit path end-to-end
	bash scripts/verify_redis_cache.sh

verify-monitoring:  ## Verify Prometheus targets, p95 data, and Grafana dashboard
	bash scripts/verify_monitoring.sh

mcp-stdio-up:  ## Start MCP stdio adapter for Claude Desktop compatibility
	$(COMPOSE) --env-file $(ENV_FILE) --profile mcp-stdio up -d mcp-stdio-adapter

mcp-stdio-down:  ## Stop MCP stdio adapter
	$(COMPOSE) --env-file $(ENV_FILE) --profile mcp-stdio stop mcp-stdio-adapter

# ──────────────────────────────────────────────────────────────────────
# Tests (each project)
# ──────────────────────────────────────────────────────────────────────

test: test-arxiv test-arxiv-ml test-mcp test-eval test-rag  ## Run tests across all repos (including python-ml)

test-arxiv:  ## Run arxiv-research-assistant Go backend tests
	cd arxiv-research-assistant/go-backend && go test ./... -v

test-arxiv-ml:  ## Run arxiv-research-assistant python-ml tests (offline-safe)
	cd arxiv-research-assistant/python-ml && PYTHONPATH=. $(PYTHON) -m pytest tests/ -v

test-mcp:  ## Run mcp-gateway tests with the race detector
	cd mcp-gateway && go test ./... -v -race

test-eval:  ## Run llm-eval-framework tests
	cd llm-eval-framework && $(PYTHON) -m pytest tests/ -v

test-rag:  ## Run rag-research tests
	cd rag-research && $(PYTHON) -m pytest tests/ -v

# ──────────────────────────────────────────────────────────────────────
# Ollama (needed for LLM generation)
# ──────────────────────────────────────────────────────────────────────

install-ollama:  ## Install Ollama CLI (Linux x86_64)
	curl -fsSL https://ollama.com/install.sh | sh

pull-models:  ## Pull required Ollama models (inside the ws-ollama container, not the host)
	$(COMPOSE) --env-file $(ENV_FILE) exec -T ollama ollama pull phi3:mini
	$(COMPOSE) --env-file $(ENV_FILE) exec -T ollama ollama pull mistral
	$(COMPOSE) --env-file $(ENV_FILE) exec -T ollama ollama pull nomic-embed-text

# ──────────────────────────────────────────────────────────────────────
# End-to-end smoke test
# ──────────────────────────────────────────────────────────────────────

smoke-e2e:  ## Run end-to-end smoke test (ingest → query → evaluate)
	bash scripts/smoke_e2e.sh

smoke-reports:  ## Run reports-focused smoke test (POST /reports → export.md → /r/{token} → audit_reports row)
	bash scripts/smoke_e2e.sh

# ──────────────────────────────────────────────────────────────────────
# Security (P0 pipeline)
# ──────────────────────────────────────────────────────────────────────

rotate-key:  ## KEY=gsk_... rotate Groq key: validate live → rewrite .env → recreate 3 services (add DRY=1 to validate only)
	@bash scripts/rotate_key.sh KEY=$(KEY) DRY=$(DRY)

check-secrets:  ## Sweep tracked files for leaked Groq keys (exit 1 on leak; safe for CI)
	bash scripts/check_secrets.sh

prune-builder:  ## Reclaim docker build cache (keep 3GB) — confirm with y/N
	@echo "Build cache ≥18GB reclaimable — hapus (tahan 3GB)? [y/N]"; \
	read -r ans; \
	case "$$ans" in y|Y) docker builder prune --keep-storage 3GB -f;; *) echo "Batal.";; esac

df:  ## Show docker disk usage
	docker system df

seed-rag:  ## Seed RAG research corpus and Qdrant index idempotently
	# `-m` (not a script path) keeps the repo root on sys.path so `import src`
	# works. Requires the Qdrant service to be running (`make up`).
	cd rag-research && $(PYTHON) -m src.ingestion.document_loader
	cd rag-research && $(PYTHON) -m src.ingestion.semantic_chunker
	cd rag-research && $(PYTHON) -m src.retrieval.qdrant_store

# ──────────────────────────────────────────────────────────────────────
# Backup & Restore
# ──────────────────────────────────────────────────────────────────────

backup-postgres:  ## Backup PostgreSQL database to local backups/ directory
	@bash scripts/backup_postgres.sh --local

backup-qdrant:  ## Backup Qdrant vector database to local backups/ directory
	@bash scripts/backup_qdrant.sh --local

backup-all:  ## Backup all databases (PostgreSQL + Qdrant)
	@bash scripts/backup_all.sh --local

# ──────────────────────────────────────────────────────────────────────
# Project sub-make (delegate to project Makefiles)
# ──────────────────────────────────────────────────────────────────────

arxiv-up:  ## Start arxiv stack only
	cd arxiv-research-assistant && $(MAKE) up

arxiv-down:  ## Stop arxiv stack only
	cd arxiv-research-assistant && $(MAKE) down

verify:  ## Run status + tests + secret scan
	make status
	make test
	make check-secrets
