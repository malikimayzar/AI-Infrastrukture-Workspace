# OpenTelemetry Distributed Tracing Guide

> **Last Updated:** 2026-10-26
> **Status:** Implemented (opt-in, disabled by default)

## Overview

OpenTelemetry distributed tracing provides end-to-end visibility across the MCP gateway → RAG service → evaluation service chain. Each request gets a unique trace ID that propagates across all services.

## Architecture

```
Client → MCP Gateway (Go) → RAG Service (Python) → LLM (Groq)
              │                    │
              └── OTLP Exporter ───┘── OTLP Exporter
                    │                    │
                    └──────→ Jaeger/Tempo ←──────┘
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OTEL_ENABLED` | `false` | Enable tracing (`true`/`1`/`yes`) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` (Python) / `localhost:4317` (Go) | OTLP collector endpoint |
| `OTEL_SERVICE_NAME` | `mcp-gateway` (Go) / `rag-research` (Python) | Service name in traces |

### Enable Tracing

```bash
# In .env
OTEL_ENABLED=true
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=mcp-gateway

# Start Jaeger (optional, for visualization)
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4317:4317 \
  -p 4318:4318 \
  jaegertracing/all-in-one:latest
```

Access Jaeger UI: http://localhost:16686

## Implementation

### Go (mcp-gateway)
- **Package:** `internal/tracing/` — TracerProvider, HTTP middleware, helper functions
- **Middleware:** `tracing.HTTPMiddleware` wraps chi router (creates span per request)
- **Propagation:** W3C TraceContext via `otelhttp` (automatic header injection/extraction)
- **Downstream calls:** Trace context propagated via `traceparent` header to RAG service

### Python (rag-research)
- **Module:** `src/api/tracing.py` — TracerProvider, FastAPI instrumentation
- **Instrumentation:** `FastAPIInstrumentor.instrument_app(app)` (automatic span creation)
- **Propagation:** W3C TraceContext via global textmap propagator
- **Response:** `trace_id` and `span_id` included in `GenerateResponse`

## Trace Context Flow

1. Client sends request to MCP Gateway with optional `traceparent` header
2. Gateway creates root span, extracts/creates trace ID
3. Gateway propagates trace context to RAG service via HTTP headers
4. RAG service extracts trace context, creates child span
5. Both services export spans to OTLP collector (Jaeger/Tempo)
6. Trace ID is returned in response headers and body

## Response Fields

### RAG API (`/generate`)
```json
{
  "trace_id": "abc123def456...",
  "span_id": "789abc...",
  ...
}
```

### MCP Gateway (`/mcp`)
Trace context is propagated via response headers:
- `X-Trace-ID`: Trace ID
- `X-Request-ID`: Request ID (existing)

## Testing

```bash
# Enable tracing
OTEL_ENABLED=true make up

# Send a request
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/call" \
  -H "Authorization: Bearer sk-live-abc123" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"verify_factual_claim","arguments":{"query":"What is self-attention?"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'

# Check Jaeger UI for traces
open http://localhost:16686
```

## Files

| File | Purpose |
|------|---------|
| `mcp-gateway/internal/tracing/tracing.go` | TracerProvider setup, helper functions |
| `mcp-gateway/internal/tracing/middleware.go` | HTTP middleware (otelhttp) |
| `rag-research/src/api/tracing.py` | Python tracing module |
| `rag-research/src/api/main.py` | FastAPI instrumentation, trace_id in response |
