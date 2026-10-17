.PHONY: help up down test test-arxiv test-mcp test-eval test-rag smoke-e2e logs status install-ollama pull-models

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

# ──────────────────────────────────────────────────────────────────────
# Tests (each project)
# ──────────────────────────────────────────────────────────────────────

test: test-arxiv test-mcp test-eval test-rag  ## Run tests in all 4 projects

test-arxiv:  ## Run arxiv-research-assistant tests
	cd arxiv-research-assistant/go-backend && go test ./... -v

test-mcp:  ## Run mcp-gateway tests
	cd mcp-gateway && go test ./... -v

test-eval:  ## Run llm-eval-framework tests
	cd llm-eval-framework && python -m pytest tests/ -v

test-rag:  ## Run rag-research tests
	cd rag-research && python -m pytest tests/ -v

# ──────────────────────────────────────────────────────────────────────
# Ollama (needed for LLM generation)
# ──────────────────────────────────────────────────────────────────────

install-ollama:  ## Install Ollama CLI (Linux x86_64)
	curl -fsSL https://ollama.com/install.sh | sh

pull-models:  ## Pull required Ollama models
	ollama pull nomic-embed-text
	ollama pull phi3:mini
	ollama pull mistral

# ──────────────────────────────────────────────────────────────────────
# End-to-end smoke test
# ──────────────────────────────────────────────────────────────────────

smoke-e2e:  ## Run end-to-end smoke test (ingest → query → evaluate)
	bash scripts/smoke_e2e.sh

# ──────────────────────────────────────────────────────────────────────
# Project sub-make (delegate to project Makefiles)
# ──────────────────────────────────────────────────────────────────────

arxiv-up:  ## Start arxiv stack only
	cd arxiv-research-assistant && $(MAKE) up

arxiv-down:  ## Stop arxiv stack only
	cd arxiv-research-assistant && $(MAKE) down
