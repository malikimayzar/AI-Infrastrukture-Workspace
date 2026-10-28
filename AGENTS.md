# AGENTS.md — AI Agent Guide for AI Infrastructure Workspace

> **Purpose:** Guide for AI agents (Devin, OpenCode, Aider, etc.) working in this workspace.
> **Last Updated:** 2026-10-24
> **Workspace:** `ai-infra-workspace` (4 submodules: arxiv-research-assistant, mcp-gateway, rag-research, llm-eval-framework)

---

## 1. Workspace Overview

This is a **multi-repo AI infrastructure workspace** orchestrated via Docker Compose at the root. The workspace builds a **Scientific Claim & Prior-Art Auditor** platform with the following structure:

```
ai-infra-workspace/
├── arxiv-research-assistant/    # Go + Python (ArXiv paper ingestion & query)
├── mcp-gateway/                 # Go (Orchestration & API routing)
├── rag-research/                 # Python (Hybrid retrieval, confidence engine)
├── llm-eval-framework/          # Python (Faithfulness evaluation, no LLM judge)
├── docker-compose.yml           # Canonical topology (11 services)
├── Makefile                     # Orchestration commands
├── PROJECT_GOALS.md             # Engineering specs & success criteria
├── PROJECT_CONTEXT.md           Runtime snapshot & integration status
├── CONVENTIONS.md               # AI collaboration rules (Aider + OpenCode)
└── scripts/                     # Utility scripts (rotate_key, check_secrets, smoke_e2e)
```

### Service Topology (Root Compose - Mode A)

```
mcp-gateway :8090 ─┬─ ARXIV_SERVICE_URL → arxiv-go-backend :8080
                   │                        └─ ML_SERVICE_URL → arxiv-python-ml :8001
                   ├─ EVAL_SERVICE_URL  → llm-eval-framework :8002
                   └─ RAG_SERVICE_URL   → rag-api :8000
All services → postgres :5432 / qdrant :6333 / ollama :11434
Host ports: 8090, 8080, 8001, 8002, 8000, 5432, 6333, 11435
```

### Key Concepts

- **Mode A (Canonical):** Run from root with `make up` — containers prefixed `ws-*`
- **Mode B (Isolated):** Run from project folder with `docker compose up` — containers use project names
- **Rule:** Mode A and Mode B CANNOT run simultaneously (port conflicts)
- **Generation Provider:** Groq `openai/gpt-oss-20b` (default), Ollama `phi3:mini` (local, RAM-heavy)
- **Embedding Model:** `sentence-transformers/all-MiniLM-L6-v2` (cached, HF_HUB_OFFLINE=1)

---

## 2. Essential Commands

### 2.1 Workspace Orchestration (Root)

```bash
# Start all services (Mode A - canonical)
make up

# Stop all services
make down

# View service status
make status

# Follow logs (specific service: SERVICE=ws-rag-api)
make logs

# Start monitoring stack (Redis, Prometheus, Grafana)
make monitoring-up

# Stop monitoring only (core stack remains running)
make monitoring-down
```

### 2.2 Testing

```bash
# Run all tests across 4 repos
make test

# Individual repo tests
make test-arxiv          # Go backend tests
make test-arxiv-ml       # Python ML tests (19 tests)
make test-mcp            # Gateway tests with -race detector
make test-eval           # Evaluation framework tests
make test-rag            # RAG research tests (~2 minutes)

# Targeted RAG test (faster during iteration)
cd rag-research && python -m pytest tests/test_specific_file.py -v
```

### 2.3 End-to-End Verification

```bash
# Smoke test: ingest → query → verify query_logs in DB
make smoke-e2e

# Seed RAG corpus idempotently (requires Qdrant running)
make seed-rag

# Check for leaked secrets in tracked files
make check-secrets

# Rotate Groq API key (validate → rewrite .env → recreate 3 services)
KEY=gsk_... make rotate-key
```

### 2.4 Docker Maintenance

```bash
# Reclaim build cache (keep 3GB)
make prune-builder

# Show disk usage
make df
```

### 2.5 Ollama Models (Optional)

```bash
# Install Ollama CLI on host (Linux x86_64)
make install-ollama

# Pull models inside ws-ollama container (not host)
make pull-models
```

---

## 3. Repository Ownership & Responsibilities

| Repository | Language | Port | What it Owns | What it MUST NOT Own |
|------------|----------|------|--------------|---------------------|
| `arxiv-research-assistant` | Go (Fiber) + Python (FastAPI) | 8080, 8001 | ArXiv ingestion, paper metadata, paper-scoped retrieval/generation | Workspace orchestration, cross-repo routing, evaluation of other backends |
| `mcp-gateway` | Go + Chi | 8090 | Public API, backend selection, adapter validation, trace propagation, timeouts | Document ingestion, vector search, answer generation, evaluator internals |
| `rag-research` | Python 3.12 (FastAPI) + Rust Chunker | 8000 | Hybrid retrieval, RRF fusion, cross-encoder reranking, confidence/abstention | Calling other repos to complete its core query path |
| `llm-eval-framework` | Python 3.11 (FastAPI) + Ollama Embeddings | 8002 | Faithfulness/robust evaluators, datasets, reports, evaluation API | Being treated as truth oracle, silently deciding factual correctness |
| **Root Workspace** | Docker Compose + Make + Bash | — | Container orchestration, credential rotation, smoke testing, monitoring | Application-specific logic outside orchestration utilities |

**Rule:** Never cross repository boundaries unless explicitly documented in PROJECT_GOALS.md or PROJECT_CONTEXT.md.

---

## 4. Strict Prohibitions (DO NOT)

### 4.1 Operational Safety

- **NEVER** run `make down`, `docker compose down`, or `docker rm` — stack may be in production use
- **NEVER** stop or kill containers without explicit user confirmation
- **NEVER** upgrade/downgrade global dependency pins without approval — follow existing pins in `requirements/` or `go.mod`

### 4.2 Security

- **NEVER** read or write `.env` — it contains secrets and is gitignored
- **NEVER** commit secrets (API keys, passwords) to tracked files
- **NEVER** add secrets to `.env.example` — use `scripts/rotate_key.sh` for rotation
- **ALWAYS** run `make check-secrets` before proposing changes

### 4.3 Git Workflow

- **NEVER** use `git add -A` or `git add .` — specify paths explicitly
- **NEVER** push to remote — commit locally, report hash to integrator
- **NEVER** modify files outside task scope (including user's dirty files)

### 4.4 Mode Conflicts

- **NEVER** run Mode A (`make up`) and Mode B (per-project compose) simultaneously
- **ALWAYS** `docker compose down` in project folder before returning to Mode A
- **ALWAYS** verify port availability before starting services

---

## 5. Change Workflow

### 5.1 Before Making Changes

1. **Read the relevant documentation:**
   - `PROJECT_GOALS.md` — engineering specs & roadmap
   - `PROJECT_CONTEXT.md` — current integration status
   - `CONVENTIONS.md` — AI collaboration rules
   - Repo-specific `PROJECT_GOALS.md` for domain-specific context

2. **Understand the ownership:**
   - Which repo owns the component you're modifying?
   - Are you crossing repository boundaries? (if yes, stop and ask)

3. **Check the current state:**
   - `make status` — are services running?
   - `make test` — do tests pass?
   - `make check-secrets` — is the workspace clean?

### 5.2 Making Changes

1. **Work within the correct repo:**
   - For arxiv backend: `cd arxiv-research-assistant/go-backend` or `python-ml`
   - For gateway: `cd mcp-gateway`
   - For RAG: `cd rag-research`
   - For evaluation: `cd llm-eval-framework`

2. **Follow existing patterns:**
   - Match code style (majority English, follow surrounding conventions)
   - Use existing libraries (check `requirements.txt`, `go.mod`, `go.sum`)
   - Mimic existing abstractions and patterns

3. **Test incrementally:**
   - Run targeted tests during iteration
   - Run full test suite before completion: `make test`
   - If breaking cross-repo integration, run `make smoke-e2e`

### 5.3 Verification Before Completion

1. **Run the appropriate gate:**
   - Code change: `make test` (all repos)
   - Integration change: `make smoke-e2e`
   - Security change: `make check-secrets`
   - Infrastructure change: `make up` + `make status`

2. **Check git status:**
   - Ensure no irrelevant files are staged
   - Verify only files in task scope are modified

3. **Report results:**
   - What was changed?
   - Which tests were run?
   - Test results (pass/fail with counts)
   - Any risks or edge cases?
   - Commit hash

### 5.4 Commit Style

- Root workspace: conventional commits (`docs:`, `fix:`, `chore:`, `feat:`)
- Individual repos: prefix with agent name (`aider:`, `opencode:`, `devin:`)
- Keep commits atomic and small
- Do NOT add/remove comments unless explicitly asked

---

## 6. Environment Variables

### 6.1 Required for Operation

Create `.env` from `.env.example` at root:

```bash
cp .env.example .env
# Edit .env and set GROQ_API_KEY
```

**Critical variables:**
- `GROQ_API_KEY` — Required for generation (python-ml, rag-api)
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` — Database credentials
- `GROQ_MODEL` — Model name (default: `openai/gpt-oss-20b`)
- `LLM_PROVIDER` — `groq` (default, fast) or `ollama` (local, RAM-heavy)

### 6.2 Service URLs (Internal)

These are set in `.env` but resolved via Docker internal DNS:
- `ARXIV_SERVICE_URL=http://arxiv-go-backend:8080`
- `EVAL_SERVICE_URL=http://llm-eval-framework:8002`
- `RAG_SERVICE_URL=http://rag-api:8000`
- `QDRANT_URL=http://qdrant:6333`
- `OLLAMA_HOST=http://ollama:11434`

**Note:** Do NOT hardcode these URLs in code. Use environment variables.

---

## 7. Common Scenarios & Solutions

### 7.1 Service Not Starting

**Symptom:** Container exits with error or unhealthy

**Diagnosis:**
```bash
make status                    # Check which services are unhealthy
make logs SERVICE=<service>    # Check logs for errors
docker inspect <container>     # Check configuration
```

**Common causes:**
- `.env` missing or `GROQ_API_KEY` empty
- Port conflict (Mode A + Mode B running together)
- Database not healthy (check postgres logs)
- Qdrant not healthy (check qdrant logs)

### 7.2 DNS Resolution Failure

**Symptom:** `NameResolutionError` to `ws-qdrant`/`ws-postgres`

**Cause:** Rootless Docker embedded DNS corruption (resolv.conf changed to external nameservers)

**Solution:**
```bash
docker compose --env-file .env up -d --force-recreate --no-deps --no-build <service>
```

**Prevention:** Check `docker exec <container> cat /etc/resolv.conf` after big recreates. If it shows external DNS (1.1.1.1, 8.8.8.8), force-recreate.

### 7.3 OOM (Out of Memory)

**Symptom:** Container exit code 137, logs show `signal: killed`

**Cause:** Host RAM insufficient for model load (phi3:mini needs ~4.5 GB peak)

**Solution:**
- Use Groq as default provider (`LLM_PROVIDER=groq`)
- Check `free -m` before using Ollama
- Unload host daemon: `curl -X POST localhost:11434/api/generate -d '{"model":"phi3:mini","keep_alive":0}'`

### 7.4 Test Failures

**Diagnosis:**
```bash
# Run specific test with verbose output
cd <repo> && python -m pytest tests/test_file.py -v

# For Go tests
cd <repo> && go test ./... -v
```

**Common causes:**
- Missing dependency (check `requirements.txt` or `go.mod`)
- PYTHONPATH not set (for python-ml: `PYTHONPATH=. python -m pytest tests/`)
- Database/Qdrant not running (check `make status`)

### 7.5 Groq API Rate Limit

**Symptom:** 429 errors or timeout during generation

**Solution:**
- Implement retry logic (already in place with 1 retry max)
- Adjust timeout (current: 60s)
- Fall back to Ollama if quota exhausted

---

## 8. Monitoring & Debugging

### 8.1 Enable Monitoring

```bash
make monitoring-up
# Access:
# - Prometheus: http://localhost:9090
# - Grafana: http://localhost:3000 (admin/admin)
```

**Metrics exposed:**
- `go-backend`: `/metrics`
- `python-ml`: `/metrics`
- `mcp-gateway`: `/metrics`
- `llm-eval-framework`: `/metrics`
- `rag-api`: `/metrics`

### 8.2 Check Logs

```bash
# All services
make logs

# Specific service
make logs SERVICE=ws-rag-api

# Docker direct
docker logs -f ws-rag-api
```

### 8.3 Health Checks

```bash
# All services
curl http://localhost:8090/health    # mcp-gateway
curl http://localhost:8080/health    # arxiv-go-backend
curl http://localhost:8001/health    # arxiv-python-ml
curl http://localhost:8002/health    # llm-eval-framework
curl http://localhost:8000/health    # rag-api
```

---

## 9. Roadmap Context

> **Source of Truth:** [`docs/ROADMAP.md`](docs/ROADMAP.md) — single consolidated roadmap.

**Current Status:** Phase 1 acceptance pending. Phase 4 (Claim Audit UI) not started. Auth + rate limiting active. Confidence calibration ECE 0.0576. Rust reranker optimized (1.4x-2.0x speedup). OpenTelemetry tracing (opt-in). Circuit breaker (closed/open/half-open). Graceful shutdown (30s). API key rotation. OpenAPI spec. CI/CD pipeline. Connection pooling. Per-key rate limits. Custom Grafana dashboard. Alerting rules (10 rules). E2E MCP smoke test 16/16 PASS.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for full details.

---

## 10. Production Readiness Gates

Before claiming production readiness, ensure:

- [ ] **Build Independence:** `docker compose build --no-cache` succeeds in clean environment
- [ ] **Test Suite Pass:** `make test` passes 100% across all 4 repos
- [ ] **Zero Secret Leaks:** `make check-secrets` returns CLEAN (exit 0)
- [ ] **Smoke Integration:** `make smoke-e2e` passes (basic integration, not quality gate)
- [ ] **Monitoring Active:** Prometheus scrapes all 5 jobs, Grafana shows metrics without errors
- [ ] **Confidence Calibrated:** Isotonic Regression fitted with ECE < 0.10 on 200+ labeled samples
- [ ] **Dataset Size:** Evaluation dataset ≥ 200 labeled queries
- [ ] **Latency Verified:** End-to-end P95 ≤ 3.5s measured on deployment hardware

**Current Status:** Phase 1 acceptance pending. Phase 4 (Claim Audit UI) not started. Auth + rate limiting active. Confidence calibration ECE 0.0576. Rust reranker optimized (1.4x-2.0x speedup). OpenTelemetry tracing (opt-in). Circuit breaker (closed/open/half-open). Graceful shutdown (30s). API key rotation. OpenAPI spec. CI/CD pipeline. Connection pooling. Per-key rate limits. Custom Grafana dashboard. Alerting rules (10 rules). E2E MCP smoke test 16/16 PASS.

---

## 11. Non-Goals (What This Project Is NOT)

1. **NOT a casual chatbot** — This is a scientific fact extraction engine, not a conversational assistant
2. **NOT unconstrained reasoning** — Model must refuse to answer without evidence (hard abstention)
3. **NOT a general benchmark chaser** — We do not optimize for MMLU or general-domain scores
4. **NOT a truth oracle** — System verifies claims against indexed corpus, not universal truth

---

## 12. Quick Reference

| Command | Purpose |
|---------|---------|
| `make up` | Start all services (Mode A) |
| `make down` | Stop all services |
| `make test` | Run all tests |
| `make smoke-e2e` | End-to-end smoke test |
| `make check-secrets` | Audit for leaked secrets |
| `make monitoring-up` | Start Redis/Prometheus/Grafana |
| `make logs SERVICE=ws-*` | Follow service logs |
| `make status` | Show service status |
| `make seed-rag` | Seed RAG corpus |

---

## 13. Emergency Contacts

If you encounter issues beyond these guidelines:

1. Check `docs/ops-postmortem.md` for historical incident solutions
2. Check repo-specific `PROJECT_GOALS.md` for domain context
3. Check `PROJECT_CONTEXT.md` for current integration status
4. Ask for clarification before making assumptions

---

## 14. Recent Improvements (2026-10-24)

### Quick Wins Implemented

1. **Pre-commit Hooks**
   - Black (Python), flake8 (Python), YAML/JSON validation
   - Trailing whitespace, end-of-file-fixer, large file check
   - Run: `pre-commit run --all-files`
   - Guide: `docs/pre-commit-guide.md`

2. **Structured JSON Logging**
   - Python utility: `scripts/logging_utils.py`
   - Go utility: `scripts/logging_utils.go`
   - Consistent fields: timestamp, level, service, request_id, duration_ms
   - Guide: `docs/structured-logging-guide.md`

3. **Backup Scripts**
   - PostgreSQL: `scripts/backup_postgres.sh`
   - Qdrant: `scripts/backup_qdrant.sh`
   - Combined: `scripts/backup_all.sh`
   - Make targets: `make backup-postgres`, `make backup-qdrant`, `make backup-all`
   - Guide: `docs/backup-guide.md`

4. **Deep Health Check Utilities**
   - Python: `scripts/health_check_utils.py`
   - FastAPI endpoints: `scripts/health_check_api.py`
   - Checks: PostgreSQL, Qdrant, Ollama, embedding model
   - Guide: `docs/health-check-guide.md`

5. **Smoke Test Improvements**
   - Unique request_id per run (timestamp-based)
   - More reliable log verification
   - Script: `scripts/smoke_e2e.sh`

6. **Architecture Decision Records**
   - ADR-001: Use Groq as Primary LLM Provider
   - Location: `docs/adr/001-use-groq-as-primary-llm-provider.md`

### Files Added Today

- `.pre-commit-config.yaml` - Pre-commit hooks configuration
- `.golangci.yml` - Go linting configuration
- `scripts/logging_utils.py` - Python structured logging
- `scripts/logging_utils.go` - Go structured logging
- `scripts/backup_postgres.sh` - PostgreSQL backup script
- `scripts/backup_qdrant.sh` - Qdrant backup script
- `scripts/backup_all.sh` - Combined backup script
- `scripts/health_check_utils.py` - Health check utilities
- `scripts/health_check_api.py` - FastAPI health endpoints
- `docs/pre-commit-guide.md` - Pre-commit usage guide
- `docs/structured-logging-guide.md` - Logging implementation guide
- `docs/backup-guide.md` - Backup and restore guide
- `docs/health-check-guide.md` - Health check implementation guide
- `docs/adr/001-use-groq-as-primary-llm-provider.md` - ADR for Groq provider
- `mcp-gateway/.env.example` - Updated with GROQ_MODEL and GROQ_API_KEY

### Makefile Additions

```bash
make backup-postgres  # Backup PostgreSQL
make backup-qdrant    # Backup Qdrant
make backup-all      # Backup both databases
```

---

**Remember:** This is a mission-critical scientific audit platform. Prioritize correctness, grounding, and reliability over feature velocity. When in doubt, ask.
