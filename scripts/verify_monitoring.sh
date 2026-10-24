#!/usr/bin/env bash
set -euo pipefail

PROM_URL="${PROM_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_AUTH="${GRAFANA_AUTH:-admin:admin}"
EXPECTED_JOBS='["go-backend","llm-eval-framework","mcp-gateway","python-ml","rag-api"]'

fail() { echo "❌ verify-monitoring: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq is required"

check_metric() {
    local name="$1" url="$2" needle="$3" body
    body=$(curl -sf --max-time 10 "$url") || fail "$name metrics unreachable at $url"
    grep -q "$needle" <<<"$body" || fail "$name metrics missing '$needle'"
    echo "✓ $name metrics: $needle"
}

check_metric "go-backend" "http://localhost:8080/metrics" "http_requests_total"
check_metric "python-ml" "http://localhost:8001/metrics" "http_requests_total"
check_metric "mcp-gateway" "http://localhost:8090/metrics" "gateway_http_requests_total"
check_metric "llm-eval-framework" "http://localhost:8002/metrics" "http_request_duration_seconds"
check_metric "rag-api" "http://localhost:8000/metrics" "rag_requests_total"

echo "verify-monitoring: waiting for Prometheus targets (max 60s)"
TARGETS_OK=0
TARGETS_JSON=""
DEADLINE=$((SECONDS + 60))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
    TARGETS_JSON=$(curl -sf "$PROM_URL/api/v1/targets?state=active" 2>/dev/null || true)
    if [ -n "$TARGETS_JSON" ] && \
        jq -e --argjson expected "$EXPECTED_JOBS" \
        '[.data.activeTargets[] | select(.health == "up") | .labels.job] | sort == $expected' \
        >/dev/null 2>&1 <<<"$TARGETS_JSON"; then
        TARGETS_OK=1
        break
    fi
    sleep 2
done

if [ "$TARGETS_OK" -ne 1 ]; then
    SUMMARY=$(jq -c '[.data.activeTargets[] | {job: .labels.job, health: .health}]' 2>/dev/null <<<"$TARGETS_JSON" || echo "${TARGETS_JSON:-unreachable}")
    fail "Prometheus targets not all up after 60s: $SUMMARY"
fi
echo "✓ Prometheus targets: 5/5 up"

SUM_UP=$(curl -sfG "$PROM_URL/api/v1/query" --data-urlencode "query=sum(up)" | jq -r '.data.result[0].value[1] // empty')
[ "$SUM_UP" = "5" ] || fail "sum(up)=${SUM_UP:-empty}, expected 5"
echo "✓ sum(up)=5"

P95_EXPR='histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]) or rate(gateway_http_request_duration_seconds_bucket[5m]) or rate(rag_latency_seconds_bucket[5m])))'
P95_COUNT=0
DEADLINE=$((SECONDS + 60))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
    P95_JSON=$(curl -sfG "$PROM_URL/api/v1/query" --data-urlencode "query=$P95_EXPR" 2>/dev/null || true)
    P95_COUNT=$(jq -r '.data.result | length' 2>/dev/null <<<"${P95_JSON:-}" || echo 0)
    [ "${P95_COUNT:-0}" -gt 0 ] && break
    sleep 3
done
[ "${P95_COUNT:-0}" -gt 0 ] \
    || fail "p95 query returned no series; run 'make smoke-e2e' first to generate traffic"
echo "✓ p95 query: ${P95_COUNT} series"

echo "verify-monitoring: waiting for Grafana dashboard (max 60s)"
GRAFANA_OK=0
GRAFANA_HEALTH=""
DEADLINE=$((SECONDS + 60))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
    GRAFANA_HEALTH=$(curl -sf -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/health" 2>/dev/null || true)
    DASHBOARD=$(curl -sf -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/dashboards/uid/workspace-overview" 2>/dev/null || true)
    if jq -e '.database == "ok"' >/dev/null 2>&1 <<<"${GRAFANA_HEALTH:-}" && \
        jq -e '.dashboard.title == "Workspace Overview" and (.dashboard.panels | length) == 5' \
        >/dev/null 2>&1 <<<"${DASHBOARD:-}"; then
        GRAFANA_OK=1
        break
    fi
    sleep 2
done

[ "$GRAFANA_OK" -eq 1 ] \
    || fail "Grafana dashboard 'workspace-overview' with 5 panels not ready after 60s (health: ${GRAFANA_HEALTH:-unreachable})"
echo "✓ Grafana dashboard: workspace-overview (5 panels)"
echo "✅ verify-monitoring: PASS (5 targets, sum(up)=5, p95 series=${P95_COUNT}, dashboard=5 panels)"
