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
RAG_URL="${RAG_URL:-http://localhost:8000}"
EVAL_URL="${EVAL_URL:-http://localhost:8002}"
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-arxiv}"
PG_PASSWORD="${PG_PASSWORD:-arxiv_secret}"
PG_DB="${PG_DB:-arxiv_db}"
TEST_ARXIV_ID="${TEST_ARXIV_ID:-2312.10997}"

RUN_ID="${SMOKE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
GATEWAY_REQUEST_ID="smoke-$RUN_ID"
GATEWAY_REQUEST_ID_RAG="smoke-rag-$RUN_ID"
ARXIV_QUERY="What is this paper about? [smoke:$RUN_ID]"
RAG_QUERY="How does RAG combine retrieval with generation? [smoke:$RUN_ID]"

if ! [[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "[smoke ERROR] SMOKE_RUN_ID contains unsafe characters" >&2
  exit 1
fi

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

# psql may be absent on the host — fall back to the postgres container's own client.
run_psql() {
  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -t -A -c "$1"
  else
    docker exec ws-postgres psql -U "$PG_USER" -d "$PG_DB" -t -A -c "$1"
  fi
}

wait_for_count() {
  local sql="$1" expected="$2" label="$3"
  local deadline=$((SECONDS + 20))
  local count=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    count=$(run_psql "$sql") || err "psql failed for $label (run $RUN_ID)"
    count=$(printf '%s' "$count" | tr -d '[:space:]')
    if [ "${count:-0}" -ge "$expected" ] 2>/dev/null; then
      log "$label: $count row(s) ✓"
      return 0
    fi
    sleep 1
  done
  err "$label: expected >=$expected row(s), got ${count:-unknown} (run $RUN_ID)"
}

# ── Step 1: Wait for services ──────────────────────────────────────────

log "Step 1: Waiting for services to be healthy"

wait_for "arxiv go-backend"   "$ARXIV_URL/health"
wait_for "arxiv python-ml"    "$ML_URL/health"
wait_for "rag-api"            "$RAG_URL/health"
wait_for "llm-eval-framework" "$EVAL_URL/health"
# /ready probes ArXiv, evaluator, and RAG together; /health is liveness only.
wait_for "mcp-gateway readiness" "$GATEWAY_URL/ready"

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
    -H "X-Request-ID: $GATEWAY_REQUEST_ID" \
    -d "{\"backend\": \"arxiv\", \"query\": \"$ARXIV_QUERY\", \"top_k\": 5}" 2>&1) || CANDIDATE=""
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

RESPONSE_REQUEST_ID=$(echo "$QUERY_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('request_id',''))" 2>/dev/null) \
  || err "Failed to parse request_id from response"
[ "$RESPONSE_REQUEST_ID" = "$GATEWAY_REQUEST_ID" ] \
  || err "gateway request_id mismatch: $RESPONSE_REQUEST_ID (run $RUN_ID)"

log "Answer received from backend=$BACKEND (length: ${#ANSWER} chars, request_id=$RESPONSE_REQUEST_ID)"

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
    -H "X-Request-ID: $GATEWAY_REQUEST_ID_RAG" \
    -d "{\"backend\": \"research_rag\", \"query\": \"$RAG_QUERY\", \"top_k\": 3}" 2>&1) || RAG_RESPONSE=""
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

RAG_RESPONSE_REQUEST_ID=$(echo "$RAG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('request_id',''))" 2>/dev/null) \
  || err "Failed to parse request_id from research_rag response"
[ "$RAG_RESPONSE_REQUEST_ID" = "$GATEWAY_REQUEST_ID_RAG" ] \
  || err "gateway rag request_id mismatch: $RAG_RESPONSE_REQUEST_ID (run $RUN_ID)"

# ── Step 4: Verify query logs in PostgreSQL ────────────────────────────

log "Step 4: Verifying query logs in PostgreSQL"

wait_for_count \
  "SELECT COUNT(*) FROM gateway_query_logs WHERE request_id = '$GATEWAY_REQUEST_ID' AND backend = 'arxiv';" \
  1 "gateway arxiv log"

wait_for_count \
  "SELECT COUNT(*) FROM gateway_query_logs WHERE request_id = '$GATEWAY_REQUEST_ID_RAG' AND backend = 'research_rag';" \
  1 "gateway rag log"

wait_for_count \
  "SELECT COUNT(*) FROM query_logs WHERE request_id = '$GATEWAY_REQUEST_ID';" \
  1 "arxiv backend query log"

# Negative check: an id that was never issued must not match anything. Without
# this, a query that ignores the filter (or a handler that stores "" for every
# row) would still look healthy.
MISSING_COUNT=$(run_psql "SELECT COUNT(*) FROM query_logs WHERE request_id = 'missing-$RUN_ID';") \
  || err "psql failed for query_logs negative check (run $RUN_ID)"
MISSING_COUNT=$(printf '%s' "$MISSING_COUNT" | tr -d '[:space:]')
[ "${MISSING_COUNT:-x}" = "0" ] \
  || err "query_logs negative check: expected 0 rows for unissued id, got ${MISSING_COUNT:-unknown} (run $RUN_ID)"

for pair in "arxiv:$GATEWAY_REQUEST_ID" "research_rag:$GATEWAY_REQUEST_ID_RAG"; do
  backend="${pair%%:*}"
  rid="${pair#*:}"
  exact=$(run_psql "SELECT COUNT(*) FROM gateway_query_logs WHERE request_id = '$rid' AND backend = '$backend';") \
    || err "psql failed for gateway $backend log (run $RUN_ID)"
  exact=$(printf '%s' "$exact" | tr -d '[:space:]')
  [ "${exact:-0}" -eq 1 ] || err "gateway $backend log: expected exactly 1 row, got ${exact:-unknown} (run $RUN_ID)"
done

log "Query logs verified for run $RUN_ID"

# ── Done ───────────────────────────────────────────────────────────────

log ""
log "=============================================="
log "  SMOKE TEST PASSED"
log "=============================================="
log "  RUN_ID:        $RUN_ID"
log "  Request ID:    $GATEWAY_REQUEST_ID (arxiv)"
log "  Request ID:    $GATEWAY_REQUEST_ID_RAG (rag)"
log "  Ingested:     $TEST_ARXIV_ID"
log "  Query backend: $BACKEND"
log "  Answer length: ${#ANSWER} chars"
log "  RAG contract:  decision=$RAG_DECISION eval=$RAG_EVAL"
log "  Query logs:    gateway + arxiv rows verified"
log "=============================================="
