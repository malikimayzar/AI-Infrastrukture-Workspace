#!/usr/bin/env bash
set -euo pipefail

RAG_URL="${RAG_URL:-http://localhost:8000}"
REDIS_CONTAINER="${REDIS_CONTAINER:-ws-redis}"
RAG_CONTAINER="${RAG_CONTAINER:-ws-rag-api}"
RUN_ID="${SMOKE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
QUERY="What is retrieval-augmented generation? [cache-verify:$RUN_ID]"

fail() { echo "❌ verify-redis: $*" >&2; exit 1; }
inconclusive() { echo "⚠️ INCONCLUSIVE: $*" >&2; exit 2; }

KEY=""
cleanup() {
    if [ -n "$KEY" ]; then
        docker exec "$REDIS_CONTAINER" redis-cli del "$KEY" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

command -v jq >/dev/null 2>&1 || fail "jq is required"

docker inspect "$REDIS_CONTAINER" >/dev/null 2>&1 \
    || fail "Redis container '$REDIS_CONTAINER' is not running; run 'make cache-up'"
PING=$(docker exec "$REDIS_CONTAINER" redis-cli ping 2>/dev/null || true)
[ "$PING" = "PONG" ] || fail "redis-cli ping returned '$PING', expected PONG"

docker inspect "$RAG_CONTAINER" >/dev/null 2>&1 \
    || fail "RAG container '$RAG_CONTAINER' is not running; run 'make cache-up'"
REDIS_ENABLED=$(docker exec "$RAG_CONTAINER" printenv REDIS_ENABLED 2>/dev/null || true)
[ "$REDIS_ENABLED" = "true" ] \
    || fail "ws-rag-api REDIS_ENABLED='$REDIS_ENABLED', expected true; run 'make cache-up'"

HEALTH_DEADLINE=$((SECONDS + 300))
while [ "$SECONDS" -lt "$HEALTH_DEADLINE" ]; do
    STATUS=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$RAG_CONTAINER" 2>/dev/null || echo missing)
    [ "$STATUS" = "healthy" ] && break
    sleep 5
done
[ "${STATUS:-}" = "healthy" ] || fail "ws-rag-api not healthy after 300s (last status: ${STATUS:-unknown})"

generate() {
    local body
    body=$(jq -cn --arg q "$QUERY" '{query: $q, top_k: 3}')
    curl -fsS --max-time 120 -H 'Content-Type: application/json' -d "$body" "$RAG_URL/generate"
}

echo "verify-redis: run=$RUN_ID"
echo "verify-redis: first request (expect cache_hit=false)"
FIRST=$(generate) || fail "first POST /generate failed; is ws-rag-api reachable at $RAG_URL?"
FIRST_DECISION=$(jq -r '.decision' <<<"$FIRST")
FIRST_FAILURE=$(jq -r '.failure_type' <<<"$FIRST")
FIRST_CACHE_HIT=$(jq -r '.cache_hit' <<<"$FIRST")
echo "verify-redis: decision=$FIRST_DECISION failure_type=$FIRST_FAILURE cache_hit=$FIRST_CACHE_HIT"

[ "$FIRST_DECISION" != "REJECT" ] \
    || inconclusive "query abstained; pilih query korpus yang answerable"
[ "$FIRST_FAILURE" = "none" ] \
    || inconclusive "first call failure_type=$FIRST_FAILURE; cache hit cannot be proven"
[ "$FIRST_CACHE_HIT" = "false" ] \
    || fail "first call cache_hit=$FIRST_CACHE_HIT, expected false"

echo "verify-redis: second request (expect cache_hit=true)"
SECOND=$(generate) || fail "second POST /generate failed"
SECOND_DECISION=$(jq -r '.decision' <<<"$SECOND")
SECOND_FAILURE=$(jq -r '.failure_type' <<<"$SECOND")
SECOND_CACHE_HIT=$(jq -r '.cache_hit' <<<"$SECOND")
SECOND_RETRIEVAL_MS=$(jq -r '.latency_retrieval_ms' <<<"$SECOND")
SECOND_GENERATION_MS=$(jq -r '.latency_generation_ms' <<<"$SECOND")
echo "verify-redis: decision=$SECOND_DECISION failure_type=$SECOND_FAILURE cache_hit=$SECOND_CACHE_HIT retrieval_ms=$SECOND_RETRIEVAL_MS generation_ms=$SECOND_GENERATION_MS"

[ "$SECOND_CACHE_HIT" = "true" ] || fail "second call cache_hit=$SECOND_CACHE_HIT, expected true"
[ "$(jq -r '.answer' <<<"$FIRST")" = "$(jq -r '.answer' <<<"$SECOND")" ] \
    || fail "cached answer differs from first answer"
jq -e '.latency_retrieval_ms == 0' >/dev/null <<<"$SECOND" \
    || fail "cached latency_retrieval_ms=$SECOND_RETRIEVAL_MS, expected 0"
jq -e '.latency_generation_ms == 0' >/dev/null <<<"$SECOND" \
    || fail "cached latency_generation_ms=$SECOND_GENERATION_MS, expected 0"

KEY=$(docker exec "$REDIS_CONTAINER" redis-cli --scan --pattern 'rag:gen:*' | grep -F -- "$QUERY" | head -n 1 || true)
[ -n "$KEY" ] || fail "no rag:gen:* key containing the verification query"
TTL=$(docker exec "$REDIS_CONTAINER" redis-cli ttl "$KEY" | tr -d '\r')
[ "$TTL" -gt 0 ] 2>/dev/null || fail "ttl for '$KEY' is '$TTL', expected > 0"
echo "verify-redis: redis key=$KEY ttl=${TTL}s"
echo "✅ verify-redis: PASS (cache_hit=false → true, ttl=${TTL}s)"
