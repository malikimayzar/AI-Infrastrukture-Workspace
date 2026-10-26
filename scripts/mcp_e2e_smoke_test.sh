#!/bin/bash
# E2E MCP Smoke Test
# Tests MCP gateway end-to-end: stdio, SSE, auth, rate limiting,
# span-level attribution, calibrated confidence, query_logs.

set -euo pipefail

WORKSPACE="/home/malikimayzar/projects/ai-infra-workspace"
API_KEY="sk-live-abc123"
WRONG_KEY="wrong-key"
BASE_URL="http://localhost:8090"

PASS=0
FAIL=0

log_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
log_fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
log_info() { echo "  INFO: $1"; }

# Helper: HTTP POST to MCP endpoint
mcp_call() {
  local transport="$1"
  local method="$2"
  local tool_name="$3"
  local tool_args="$4"
  local api_key="$5"

  local id
  id=$(date +%s%N)

  local body
  if [[ "$method" == "tools/call" ]]; then
    body="{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"${method}\",\"params\":{\"name\":\"${tool_name}\",\"arguments\":${tool_args},\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
  else
    body="{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"${method}\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
  fi

  local headers=(
    -H "Content-Type: application/json"
    -H "MCP-Protocol-Version: 2026-07-28"
    -H "Mcp-Method: ${method}"
  )

  if [[ -n "$api_key" ]]; then
    headers+=(-H "Authorization: Bearer ${api_key}")
  fi

  if [[ "$transport" == "sse" ]]; then
    headers+=(-H "Accept: text/event-stream")
  fi

  if [[ "$method" == "tools/call" && -n "$tool_name" ]]; then
    headers+=(-H "Mcp-Name: ${tool_name}")
  fi

  curl -s -o /tmp/mcp_response.txt -w "%{http_code}" -X POST "${BASE_URL}/mcp" \
    "${headers[@]}" \
    -d "${body}"
}

echo "============================================="
echo "E2E MCP Smoke Test"
echo "============================================="
echo ""

# ──────────────────────────────────────────────
# 1. server/discover via HTTP (with API key)
# ──────────────────────────────────────────────
echo "1. MCP server/discover (HTTP + auth)"
code=$(mcp_call "http" "server/discover" "" "" "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "server/discover returns 200"
else
  log_fail "server/discover returns $code (expected 200)"
fi

# ──────────────────────────────────────────────
# 2. tools/list via HTTP (with API key)
# ──────────────────────────────────────────────
echo ""
echo "2. MCP tools/list (HTTP + auth)"
code=$(mcp_call "http" "tools/list" "" "" "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "tools/list returns 200"
else
  log_fail "tools/list returns $code (expected 200)"
fi

# ──────────────────────────────────────────────
# 3. tools/call - search_scientific_literature via HTTP (with API key)
# ──────────────────────────────────────────────
echo ""
echo "3. MCP tools/call - search_scientific_literature (HTTP + auth)"
code=$(mcp_call "http" "tools/call" "search_scientific_literature" '{"query":"attention mechanism","top_k":3}' "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "search_scientific_literature returns 200"
else
  log_fail "search_scientific_literature returns $code (expected 200)"
fi

# ──────────────────────────────────────────────
# 4. tools/call - verify_factual_claim via HTTP with span-level attribution
# ──────────────────────────────────────────────
echo ""
echo "4. MCP tools/call - verify_factual_claim with span-level attribution (HTTP + auth)"
code=$(mcp_call "http" "tools/call" "verify_factual_claim" '{"query":"What is self-attention in Transformers?","top_k":5,"use_reranker":true}' "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "verify_factual_claim returns 200"
  # Check for span_level_attribution in the inner text response
  if python3 -c "
import json,sys
d=json.load(open('/tmp/mcp_response.txt'))
txt=d['result']['content'][0]['text']
parsed=json.loads(txt)
assert 'span_level_attribution' in parsed, 'missing span_level_attribution'
assert 'calibrated_confidence' in parsed, 'missing calibrated_confidence'
" 2>/dev/null; then
    log_pass "span_level_attribution present in response"
    log_pass "calibrated_confidence present in response"
  else
    log_fail "span_level_attribution or calibrated_confidence missing from response"
  fi
else
  log_fail "verify_factual_claim returns $code (expected 200)"
fi

# ──────────────────────────────────────────────
# 5. tools/call - generate_audit_dossier via HTTP (with API key)
# ──────────────────────────────────────────────
echo ""
echo "5. MCP tools/call - generate_audit_dossier (HTTP + auth)"
code=$(mcp_call "http" "tools/call" "generate_audit_dossier" '{"question":"How does multi-head attention work?","answer":"Multi-head attention projects queries keys and values into multiple subspaces.","context":"Attention mechanism allows the model to focus on different parts of input."}' "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "generate_audit_dossier returns 200"
else
  log_fail "generate_audit_dossier returns $code (expected 200)"
fi

# ──────────────────────────────────────────────
# 6. SSE transport (with API key)
# ──────────────────────────────────────────────
echo ""
echo "6. MCP SSE transport (with auth)"
sleep 2
code=$(mcp_call "sse" "server/discover" "" "" "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "SSE server/discover returns 200"
else
  log_fail "SSE server/discover returns $code (expected 200)"
fi

code=$(mcp_call "sse" "tools/list" "" "" "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "SSE tools/list returns 200"
else
  log_fail "SSE tools/list returns $code (expected 200)"
fi

code=$(mcp_call "sse" "tools/call" "verify_factual_claim" '{"query":"What is self-attention in Transformers?","top_k":3}' "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "SSE tools/call returns 200"
else
  log_fail "SSE tools/call returns $code (expected 200)"
fi

# ──────────────────────────────────────────────
# 7. Auth - no API key (should be 401)
# ──────────────────────────────────────────────
echo ""
echo "7. Auth - no API key (should be 401)"
code=$(mcp_call "http" "tools/list" "" "" "")
if [[ "$code" == "401" ]]; then
  log_pass "No API key returns 401"
else
  log_fail "No API key returns $code (expected 401)"
fi

# ──────────────────────────────────────────────
# 8. Auth - valid API key (should be 200)
# ──────────────────────────────────────────────
echo ""
echo "8. Auth - valid API key (should be 200)"
code=$(mcp_call "http" "tools/list" "" "" "$API_KEY")
if [[ "$code" == "200" ]]; then
  log_pass "Valid API key returns 200"
else
  log_fail "Valid API key returns $code (expected 200)"
fi

# ──────────────────────────────────────────────
# 9. Auth - wrong API key (should be 401)
# ──────────────────────────────────────────────
echo ""
echo "9. Auth - wrong API key (should be 401)"
code=$(mcp_call "http" "tools/list" "" "" "$WRONG_KEY")
if [[ "$code" == "401" ]]; then
  log_pass "Wrong API key returns 401"
else
  log_fail "Wrong API key returns $code (expected 401)"
fi

# ──────────────────────────────────────────────
# 10. Rate limiting - burst=5
# ──────────────────────────────────────────────
echo ""
echo "10. Rate limiting (burst=5)"
sleep 3  # Allow token bucket to refill
codes=()
for i in $(seq 1 10); do
  code=$(mcp_call "http" "tools/list" "" "" "$API_KEY")
  codes+=("$code")
done

# Count 200s and 429s
count_200=0
count_429=0
for code in "${codes[@]}"; do
  if [[ "$code" == "200" ]]; then
    count_200=$((count_200+1))
  elif [[ "$code" == "429" ]]; then
    count_429=$((count_429+1))
  fi
done

if [[ $count_200 -gt 0 && $count_429 -gt 0 ]]; then
  log_pass "Rate limiting active: ${count_200}x200, ${count_429}x429"
else
  log_fail "Rate limiting not working: got ${codes[*]}"
fi

# ──────────────────────────────────────────────
# 11. Health check
# ──────────────────────────────────────────────
echo ""
echo "11. Health check"
health_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health")
if [[ "$health_code" == "200" ]]; then
  log_pass "Health check returns 200"
else
  log_fail "Health check returns $health_code (expected 200)"
fi

# ──────────────────────────────────────────────
# 12. Ready check
# ──────────────────────────────────────────────
echo ""
echo "12. Ready check"
ready_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/ready")
if [[ "$ready_code" == "200" ]]; then
  log_pass "Ready check returns 200"
else
  log_fail "Ready check returns $ready_code (expected 200)"
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo ""
echo "============================================="
echo "E2E MCP Smoke Test Summary"
echo "============================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "All E2E MCP smoke tests passed!"
  exit 0
else
  echo "Some E2E MCP smoke tests failed!"
  exit 1
fi
