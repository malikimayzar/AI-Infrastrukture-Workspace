#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8090}"

echo "Checking /audit UI..."
curl -sf "$BASE_URL/audit/" >/dev/null

echo "Submitting claim..."
resp=$(curl -sf -X POST "$BASE_URL/ask" -H 'Content-Type: application/json' \
  -d '{"query":"What is self-attention?","backend":"rag_research"}')

echo "$resp" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("span_level_attribution") is not None or d.get("span_level_attribution")==[]
print("span_level_attribution present")
'
echo "PASS"
