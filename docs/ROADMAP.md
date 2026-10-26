# Roadmap — Scientific Claim & Prior-Art Auditor

> **Last Updated:** 2026-10-26
> **Source of Truth:** This is the single consolidated roadmap. All other docs reference this file.

## Overview

This workspace builds a **Scientific Claim & Prior-Art Auditor** with a focus on **grounding, hard abstention, and span-level attribution**. The roadmap is phase-gated with explicit acceptance criteria.

## Phase 1 — Workspace Harmonization & Test Suite Alignment (COMPLETED ✅)
*Completed: 2026-10-20*

- [x] Canonical topology in root `docker-compose.yml` (11 services)
- [x] Key rotation scripts (`scripts/rotate_key.sh`) and secret audit (`scripts/check_secrets.sh`)
- [x] Dockerfile cleanup for `rag-research` (11.9 GB → 3.89 GB)
- [x] Harmonized `make test` across all repos
- [x] Fixed `test_qdrant_store.py` mocking
- [x] Git submodule pointers synchronized

## Phase 2 — Observability, Data Curation & Runtime Verification (COMPLETED ✅)
*Completed: 2026-10-24 | Evidence: [`docs/acceptance/phase-2-verification.md`](acceptance/phase-2-verification.md)*

- [x] Prometheus metrics exposed on all 5 services (`/metrics`)
- [x] Query leakage cleanup (4 queries fixed, cosine similarity < 0.90)
- [x] Auto-seed Qdrant mechanism (idempotent)
- [x] Redis cache verified runtime (cache_hit false→true, TTL 600s)
- [x] Fresh-run smoke tests with unique `RUN_ID`, `X-Request-ID`
- [x] Monitoring verified (5/5 targets up, 5-panel Grafana dashboard)
- [x] Gateway `/ready` with per-backend status

## Phase 3 — MCP Protocol Standardization (COMPLETED ✅)
*Completed: 2026-10-26*

### Transport
- [x] MCP JSON-RPC 2.0 over HTTP transport
- [x] stdio adapter for Claude Desktop compatibility (`--transport=stdio`)
- [x] SSE (Server-Sent Events) for streaming responses (`Accept: text/event-stream`)
- [x] Request body size limit (1 MiB) for DoS prevention
- [x] Trace ID propagation (`X-Request-ID`)
- [x] HTTP status code mapping for errors

### Tools
- [x] Tools registered: `search_scientific_literature`, `verify_factual_claim`, `generate_audit_dossier`
- [x] Span-level attribution exposed via `span_level_attribution` field
- [x] Calibrated confidence exposed via `calibrated_confidence`, `calibrated_decision`

### Security
- [x] Auth (API key) — Bearer / X-API-Key, disabled by default (dev mode)
- [x] Rate limiting — Token bucket per client IP, 60 RPM, burst 10

### Testing
- [x] E2E MCP smoke test (16/16 PASS) — `scripts/mcp_e2e_smoke_test.sh`
- [x] All 3 tools verified via HTTP + SSE + stdio

## Phase 4 — Claim Audit UI & Formal Reporting (NOT STARTED 🔵)
- [ ] Side-by-side claim audit interface (claim vs evidence)
- [ ] Span-level attribution display (claim → chunk mapping)
- [ ] Confidence zone visualization (red/yellow/green)
- [ ] Export reports in Markdown/PDF/JSON format
- [ ] Per-claim attribution with source IDs and scores
- [ ] Audit trail view (request ID, evidence chain, timestamps)

## Cross-Cutting Features (COMPLETED ✅)

| Feature | Status | Location |
|---|---|---|
| Hard abstention | ✅ Done | `rag-research/` (ConfidenceEngine) |
| Faithfulness evaluation (no LLM judge) | ✅ Done | `llm-eval-framework/` |
| Span-level attribution (claim → chunk) | ✅ Done | `rag-research/src/utils/attribution.py` |
| Confidence calibration (isotonic) | ✅ Done | `rag-research/src/controller/calibration.py` (ECE 0.0368, 214 samples) |
| Audit logging | ✅ Done | `mcp-gateway/` + Postgres |
| OpenTelemetry tracing | ✅ Done | Distributed tracing via OTLP. Go gateway + Python RAG. Opt-in (`OTEL_ENABLED=true`). See `docs/tracing-guide.md`. |
| Circuit breaker | ✅ Done | Per-service circuit breaker (closed/open/half-open). Integrated in all 3 tool adapters. States exposed via `/ready`. See `mcp-gateway/docs/circuit-breaker.md`. |
| API key rotation | ✅ Done | Runtime key rotation via `/admin/rotate-key`. No restart required. See `mcp-gateway/docs/api-key-rotation.md`. |
| OpenAPI spec | ✅ Done | OpenAPI 3.0 spec at `mcp-gateway/docs/openapi.yaml`. Covers all endpoints, schemas, and auth. |
| CI/CD pipeline | ✅ Done | GitHub Actions workflows for all 4 repos + root workspace. Build + test + lint. |
| Graceful shutdown | ✅ Done | SIGTERM/SIGINT handling, 30s timeout, circuit breaker reset, tracing flush. See `mcp-gateway/docs/graceful-shutdown.md`. |
| Connection pooling | ✅ Done | Postgres connection pool (MaxOpen=25, MaxIdle=5, Lifetime=5m). Configurable via env vars. |
| Per-key rate limits | ✅ Done | Tiered rate limiting (free/pro/enterprise). Per-key tier assignment via env or runtime. See `mcp-gateway/docs/per-key-rate-limiting.md`. |
| Custom Grafana dashboard | ✅ Done | MCP Gateway Overview dashboard (7 panels: UP, request rate, latency p95, 4xx/5xx errors, goroutines, memory). Auto-provisioned. |
| Alerting rules | ✅ Done | 10 Prometheus alerting rules (5 groups: mcp-gateway, rag-api, arxiv, eval, infra). See `infra/prometheus/alerts.yml`. |
| Rate limiting | ✅ Done | `mcp-gateway/internal/middleware/` |
| Auth (API key) | ✅ Done | `mcp-gateway/internal/middleware/` |
| Rust reranker | ✅ Done | `rag-research/src/reranking_rust/` (1.4x-2.0x faster, Python fallback) |

## Production Readiness Gates

See full checklist in [`PROJECT_GOALS.md §9`](../PROJECT_GOALS.md#9-daftar-periksa-kesiapan-produksi-production-readiness-checklist).

**Current Status:** Phases 1-3 complete. Phase 4 (UI) not started. Rust reranker optimized (1.4x-2.0x speedup). Auth + rate limiting active. Confidence calibration ECE 0.0368. OpenTelemetry tracing (opt-in). Circuit breaker (closed/open/half-open). Graceful shutdown (30s). API key rotation. OpenAPI spec. CI/CD pipeline. Connection pooling. Per-key rate limits. Custom Grafana dashboard. Alerting rules (10 rules). E2E MCP smoke test 16/16 PASS.

## Test Status

| Repo | Status | Count |
|---|---|---|
| `arxiv-research-assistant/go-backend` | ✅ PASS | 15 |
| `arxiv-research-assistant/python-ml` | ✅ PASS | 45 |
| `mcp-gateway` | ✅ PASS | 143 (-race) |
| `llm-eval-framework` | ✅ PASS | 226 |
| `rag-research` | ✅ PASS | 492 |
| **Total** | ✅ PASS | **921** |
