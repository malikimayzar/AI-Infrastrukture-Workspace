# AI Infra Workspace — Scientific Claim & Prior-Art Auditor

## Current State

See `STATUS.md` for the authoritative runtime/acceptance status. Do not treat this project as production-ready until `STATUS.md` reports Phase 1 PASS.

Root Compose is the canonical way to run the four repositories and shared infrastructure. Per-repo Compose is for isolated development only.

## Quickstart

```bash
cp .env.example .env          # Set GROQ_API_KEY
make up                       # Start all services (Mode A)
make smoke-e2e                # Ingest → query → verify logs
```

## Architecture

- **mcp-gateway** (:8090) — Orchestrator, routing, tracing, audit logs, MCP (stdio/SSE/HTTP)
- **arxiv-research-assistant** (:8080 go, :8001 ml) — ArXiv ingestion & paper-scoped queries
- **rag-research** (:8000) — Hybrid retrieval, reranking, hard abstention, calibration, span-level attribution
- **llm-eval-framework** (:8002) — Faithfulness evaluation (no LLM judge)
- **Infra** — Postgres (:5432), Qdrant (:6333), Ollama (:11434/:11435), Redis/Prometheus/Grafana (opt-in)

## Documentation

| Document | Purpose |
|---|---|
| [`PROJECT_GOALS.md`](PROJECT_GOALS.md) | Engineering specs, success criteria, contracts |
| [`PROJECT_CONTEXT.md`](PROJECT_CONTEXT.md) | Runtime snapshot & integration status |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | **Single source of truth** — Phases 1-4, status, test results |
| [`docs/OPERATIONS.md`](docs/OPERATIONS.md) | Run, debug, troubleshooting, backups |
| [`AGENTS.md`](AGENTS.md) | Guide for AI agents working in this workspace |
| [`CONVENTIONS.md`](CONVENTIONS.md) | Collaboration rules |
| [`docs/mcp-integration-guide.md`](docs/mcp-integration-guide.md) | MCP transport & integration guide |
| [`docs/confidence-calibration.md`](docs/confidence-calibration.md) | Confidence calibration guide |

## Testing

```bash
make test        # Run all tests (921 tests total)
make smoke-e2e   # Integration smoke test
make check-secrets
```

## Ports

| Service | Host Port |
|---|---|
| mcp-gateway | 8090 |
| arxiv-go-backend | 8080 |
| arxiv-python-ml | 8001 |
| llm-eval-framework | 8002 |
| rag-api | 8000 |
| ollama | 11435 (container 11434) |
| postgres | 5432 |
| qdrant | 6333/6334 |
| redis | 6379 (monitoring) |
| prometheus | 9090 (monitoring) |
| grafana | 3000 (monitoring) |
