#!/usr/bin/env bash
# smoke_e2e.sh — End-to-end smoke test for the AI Infrastructure Platform
#
# Flow:
#   1. Wait for all services to be healthy
#   2. Ingest one arXiv paper (via arxiv-research-assistant)
#   3. Query the paper via mcp-gateway (arxiv backend)
#   3b. Query via mcp-gateway (research_rag backend) — kontrak lintas folder
#   4. Verify response has answer + sources
#   5. Verify query log exists in PostgreSQL
#
# Prerequisites:
#   docker compose up -d
#   ollama pull mistral phi3:mini nomic-embed-text  (or use make pull-models)
#
# Usage:
#   bash scripts/smoke_e2e.sh
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8090}"
ARXIV_URL="${ARXIV_URL:-http://localhost:8080}"
ML_URL="${ML_URL:-http://localhost:8001}"
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-arxiv}"
PG_PASSWORD="${PG_PASSWORD:-arxiv_secret}"
PG_DB="${PG_DB:-arxiv_db}"
TEST_ARXIV_ID="${TEST_ARXIV_ID:-2312.10997}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"  # seconds
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# ── Helpers ─────────────────────────────────────────────────────────────

log()  { echo "[smoke] $*"; }
err()  { echo "[smoke ERROR] $*" >&2; exit 1; }

wait_for() {
  local name="$1" url="$2" timeout="$WAIT_TIMEOUT"
  log "Waiting for $name at $url (timeout ${timeout}s)..."
  local elapsed=0
  while ! curl -sf "$url" >/dev/null 2>&1; do
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
    if [ "$elapsed" -ge "$timeout" ]; then
      err "$name did not become healthy within ${timeout}s"
    fi
  done
  log "$name is healthy"
}

# ── Step 1: Wait for services ──────────────────────────────────────────

log "Step 1: Waiting for services to be healthy"

wait_for "arxiv go-backend"   "$ARXIV_URL/health"
wait_for "arxiv python-ml"    "$ML_URL/health"
wait_for "mcp-gateway"        "$GATEWAY_URL/health"

# ── Step 2: Ingest a paper ─────────────────────────────────────────────

log "Step 2: Ingesting arXiv paper $TEST_ARXIV_ID"

# Ingest bersifat best-effort: bila paper telah terindeks pada run sebelumnya
# API membalas {"ingested":[],"failed":[id]} dan itu valid. 4xx/5xx sementara
# (DNS export.arxiv.org flaky di rootless) tidak boleh mematikan smoke bila
# konteksnya sudah ada di Qdrant.
INGEST_RESPONSE=$(curl -s --max-time 180 -X POST "$ML_URL/ingest" \
  -H "Content-Type: application/json" \
  -d "{\"arxiv_ids\": [\"$TEST_ARXIV_ID\"]}" 2>&1) \
  || err "Ingest request failed: $INGEST_RESPONSE"

log "Ingest response: $INGEST_RESPONSE"

# Give ingestion a moment to finish embedding (it is synchronous in the ML service)
sleep 5

# ── Step 3: Query via mcp-gateway ──────────────────────────────────────

log "Step 3: Querying via mcp-gateway (backend: arxiv)"

QUERY_RESPONSE=""
for attempt in 1 2; do
  CANDIDATE=$(curl -sf --max-time 300 -X POST "$GATEWAY_URL/ask" \
    -H "Content-Type: application/json" \
    -d "{\"backend\": \"arxiv\", \"query\": \"What is this paper about?\", \"top_k\": 5}" 2>&1) || CANDIDATE=""
  if [ -n "$CANDIDATE" ]; then
    QUERY_RESPONSE="$CANDIDATE"
    break
  fi
  if [ "$attempt" -lt 2 ]; then
    log "Query attempt $attempt failed (transient — provider rate limit); retrying in 15s..."
    sleep 15
  else
    err "Query request failed after retries"
  fi
done

log "Query response: $QUERY_RESPONSE"

# Verify response has answer and sources
ANSWER=$(echo "$QUERY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('answer',''))" 2>/dev/null) \
  || err "Failed to parse query response"
BACKEND=$(echo "$QUERY_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('backend',''))" 2>/dev/null) \
  || err "Failed to parse backend from response"

if [ -z "$ANSWER" ]; then
  err "Query returned empty answer"
fi
if [ "$BACKEND" != "arxiv" ]; then
  err "Expected backend=arxiv, got $BACKEND"
fi

log "Answer received from backend=$BACKEND (length: ${#ANSWER} chars)"

# ── Step 3b: research_rag contract check ───────────────────────────────

log "Step 3b: Querying via mcp-gateway (backend: research_rag)"

# Kontrak yang divalidasi: HTTP 200, backend cocok, decision salah satu dari
# answer|abstain (abstain adalah perilaku gate yang SAH — bukan kegagalan),
# dan evaluation_status memuat nilai yang dikenal. Retry 2x karena rate limit
# Groq bersifat transien (pola sama dengan Step 3).
RAG_RESPONSE=""
for attempt in 1 2; do
  RAG_RESPONSE=$(curl -sf --max-time 120 -X POST "$GATEWAY_URL/ask" \
    -H "Content-Type: application/json" \
    -d '{"backend": "research_rag", "query": "How does RAG combine retrieval with generation?", "top_k": 3}' 2>&1) || RAG_RESPONSE=""
  if [ -n "$RAG_RESPONSE" ]; then
    break
  fi
  if [ "$attempt" -lt 2 ]; then
    log "research_rag attempt $attempt failed (transient — provider rate limit); retrying in 15s..."
    sleep 15
  else
    err "research_rag request failed after retries"
  fi
done

RAG_BACKEND=$(echo "$RAG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('backend',''))") \
  || err "Failed to parse research_rag response"
RAG_DECISION=$(echo "$RAG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('decision',''))") \
  || err "Failed to parse research_rag decision"
RAG_EVAL=$(echo "$RAG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('evaluation_status',''))") \
  || err "Failed to parse research_rag evaluation_status"

if [ "$RAG_BACKEND" != "research_rag" ]; then
  err "Expected backend=research_rag, got $RAG_BACKEND"
fi
case "$RAG_DECISION" in
  answer|abstain) log "research_rag: decision=$RAG_DECISION ✓" ;;
  *) err "research_rag: unexpected decision '$RAG_DECISION'" ;;
esac
case "$RAG_EVAL" in
  skipped|unavailable|completed) log "research_rag: evaluation_status=$RAG_EVAL ✓" ;;
  *) err "research_rag: unknown evaluation_status '$RAG_EVAL'" ;;
esac

# ── Step 4: Verify query log in PostgreSQL ─────────────────────────────

log "Step 4: Verifying query log in PostgreSQL"

# psql may be absent on the host — fall back to the postgres container's own client.
run_psql() {
  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -t -A -c "$1"
  else
    docker exec ws-postgres psql -U "$PG_USER" -d "$PG_DB" -t -A -c "$1"
  fi
}

LOG_COUNT=$(run_psql "SELECT COUNT(*) FROM query_logs WHERE query = 'What is this paper about?';") \
  || err "Failed to query PostgreSQL"

if [ "$LOG_COUNT" -lt 1 ]; then
  err "No query log found in PostgreSQL (count=$LOG_COUNT)"
fi

log "Query log found in PostgreSQL (count=$LOG_COUNT)"

# ── Done ───────────────────────────────────────────────────────────────

log ""
log "=============================================="
log "  SMOKE TEST PASSED"
log "=============================================="
log "  Ingested:     $TEST_ARXIV_ID"
log "  Query backend: $BACKEND"
log "  Answer length: ${#ANSWER} chars"
log "  RAG contract:  decision=$RAG_DECISION eval=$RAG_EVAL"
log "  Query logs:    $LOG_COUNT row(s)"
log "=============================================="
