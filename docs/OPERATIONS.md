# Operations Guide

> **Last Updated:** 2026-10-25
> **Purpose:** Run, debug, and maintain the workspace. For quickstart, see [`README.md`](../README.md).

## Mode A/B Rules

| Aspect | Mode A (Canonical) | Mode B (Per-Project) |
|---|---|---|
| **Start** | `make up` from root | `docker compose up -d` from repo folder |
| **Containers** | `ws-*` | Project-named containers |
| **Env** | Uses root `.env` automatically | Must pass `--env-file ../.env` or key will be empty |
| **Use case** | Integration testing, full stack | Isolated development in single repo |

**Rules:**
1. Mode A and Mode B cannot run simultaneously (port conflicts)
2. Before switching to Mode B: `docker compose down` in repo folder
3. Before switching back to Mode A: ensure no Mode B containers running
4. Key rotation only via root: `KEY=gsk_... make rotate-key`

## Essential Commands

```bash
# Start/stop
make up
make down
make status
make logs SERVICE=ws-rag-api

# Testing
make test
make smoke-e2e

# Security
make check-secrets
KEY=gsk_... make rotate-key

# Monitoring (opt-in)
make monitoring-up
make verify-monitoring
make monitoring-down

# Cache (opt-in)
make cache-up
make verify-redis

# Maintenance
make prune-builder
make df
make backup-all
```

## Troubleshooting

### 502 `backend_timeout` / EOF on `/ask`
- **Cause:** `rag-api` recreating mid-generation
- **Fix:** Wait for healthy status (~1 min), retry request

### Empty `GROQ_API_KEY` in container
- **Cause:** Ran compose from repo folder without `--env-file ../.env`
- **Fix:** Return to Mode A (`make up`) or restart with env file

### Container exit 137 (OOM)
- **Cause:** Insufficient RAM for model load (phi3:mini needs ~4.5GB)
- **Fix:** Use Groq as default (`LLM_PROVIDER=groq`), check `free -m`, unload host Ollama if needed

### Internal DNS resolution failure
- **Symptom:** `NameResolutionError` to `ws-qdrant`/`ws-postgres`
- **Cause:** Rootless Docker embedded DNS corruption
- **Fix:** `docker compose --env-file .env up -d --force-recreate --no-deps --no-build <service>`

### Port conflicts
- **Cause:** Both Mode A and Mode B running
- **Fix:** Stop the other mode, verify ports are free

## Health Checks

```bash
curl http://localhost:8090/health    # mcp-gateway
curl http://localhost:8080/health    # arxiv-go-backend
curl http://localhost:8001/health    # arxiv-python-ml
curl http://localhost:8002/health    # llm-eval-framework
curl http://localhost:8000/health    # rag-api
```

Gateway also exposes `/ready` with per-backend status.

## Monitoring

- **Prometheus:** http://localhost:9090
- **Grafana:** http://localhost:3000 (admin/admin)
- **Redis:** http://localhost:6379 (only in monitoring profile)

Metrics exposed on all 5 app services. Run `make smoke-e2e` before `make verify-monitoring` to populate histogram data.

## Backups

```bash
make backup-postgres  # PostgreSQL
make backup-qdrant    # Qdrant
make backup-all      # Both
```

See [`docs/backup-guide.md`](backup-guide.md) for restore procedures.

## Security

- Never commit `.env` or secrets
- Run `make check-secrets` before changes
- Rotate keys via `make rotate-key` only
- Use `scripts/check_secrets.sh` to audit tracked files
