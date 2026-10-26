# MCP Integration Guide
> **Last Updated:** 2026-10-25
> **Protocol Version:** 2026-07-28
> **Status:** Streamable HTTP MCP + stdio transport implemented

---

## Overview

The mcp-gateway exposes the Model Context Protocol (MCP) with support for two transports:

- **Streamable HTTP** - Network access at `POST http://localhost:8090/mcp`
- **stdio** - Local access for Claude Desktop, Cursor, and other MCP clients

Both transports use JSON-RPC 2.0 following the MCP 2026-07-28 specification. The stdio transport reuses the same server logic as HTTP with simplified parsing (no HTTP headers required).

**Protocol Version:** 2026-07-28

Revision 2026-07-28 uses a per-request model: there is no `initialize` handshake, no protocol-level session, and no `GET` stream endpoint. Every request declares its protocol version, identity, and capabilities in `params._meta`. For HTTP transport, these are also mirrored in HTTP headers. For stdio transport, only `params._meta` is required.

---

## Transport Options

### 1. HTTP Transport (Default)
**Endpoint:** `POST http://localhost:8090/mcp`

Start the gateway in HTTP mode:
```bash
make up  # or
cd mcp-gateway && go run ./cmd/server
```

HTTP transport requires MCP headers as specified below.

### 2. stdio Transport (For Claude Desktop, Cursor)
**Use case:** Local MCP clients that communicate via stdin/stdout

Build and run:
```bash
cd mcp-gateway
go build -o mcp-gateway ./cmd/server
./mcp-gateway --transport=stdio
# or
MCP_TRANSPORT=stdio ./mcp-gateway
```

**Notes:**
- Logs go to stderr (stdout is reserved for JSON-RPC messages)
- Uses line-delimited JSON (NDJSON)
- No HTTP headers required - only `params._meta` needed
- Trace IDs are auto-generated if not provided

#### Claude Desktop Configuration

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "scientific-claim-auditor": {
      "command": "/path/to/mcp-gateway/mcp-gateway",
      "args": ["--transport=stdio"],
      "env": {
        "ARXIV_SERVICE_URL": "http://localhost:8080",
        "RAG_SERVICE_URL": "http://localhost:8000",
        "EVAL_SERVICE_URL": "http://localhost:8002",
        "POSTGRES_DSN": "host=localhost port=5432 user=arxiv password=arxiv_secret dbname=arxiv_db sslmode=disable"
      }
    }
  }
}
```

Or use `MCP_TRANSPORT` env var:
```json
{
  "mcpServers": {
    "scientific-claim-auditor": {
      "command": "/path/to/mcp-gateway/mcp-gateway",
      "args": [],
      "env": {
        "MCP_TRANSPORT": "stdio",
        "ARXIV_SERVICE_URL": "http://localhost:8080",
        "RAG_SERVICE_URL": "http://localhost:8000",
        "EVAL_SERVICE_URL": "http://localhost:8002"
      }
    }
  }
}
```

### 1. search_scientific_literature
Search arXiv for scientific papers based on a query.

**Parameters:**
- `query` (string, required): Search query for arXiv papers
- `top_k` (integer, optional): Number of results to return (1-20)

**Response:** Paper metadata with citations and excerpts

### 2. verify_factual_claim
Verify a factual claim against the RAG corpus with span-level attribution.

**Parameters:**
- `query` (string, required): Claim or question to verify
- `top_k` (integer, optional): Number of evidence chunks to retrieve (1-20)
- `use_reranker` (boolean, optional): Whether to use cross-encoder reranking

**Response:** Answer with evidence chunks, confidence score, and hard abstention if insufficient evidence

### 3. generate_audit_dossier
Generate an audit dossier by evaluating an answer against evidence.

**Parameters:**
- `question` (string, required): Original question or claim
- `answer` (string, required): Answer to evaluate
- `context` (string, required): Evidence context used to generate the answer

**Response:** Faithfulness score, supported claims, failure mode

---

## Required Request Metadata

### For HTTP Transport
Every HTTP request must carry all of the following.

#### HTTP headers

| Header | Value |
|--------|-------|
| `Content-Type` | `application/json` |
| `MCP-Protocol-Version` | `2026-07-28` (must match the body) |
| `Mcp-Method` | The JSON-RPC `method` (must match the body) |
| `Mcp-Name` | Tool name; required for `tools/call` and must match `params.name` |

Missing or mismatched values return HTTP 400 with JSON-RPC code `-32020`
(`HeaderMismatch`).

#### `params._meta`

```json
{
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientInfo": {
    "name": "ExampleClient",
    "version": "1.0.0"
  },
  "io.modelcontextprotocol/clientCapabilities": {}
}
```

`protocolVersion` and `clientCapabilities` are required; `clientInfo` is
optional. Metadata belongs inside `params`, not at the top level of the
JSON-RPC envelope. A top-level `_meta` is ignored and the request fails with
`-32602` (`InvalidParams`).

### For stdio Transport
Only `params._meta` is required. HTTP headers are not used.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

### Notifications

A message without an `id` is a notification. It returns HTTP `202 Accepted`
with an empty body.

---

## Protocol Flow

### 1. Discover

`server/discover` replaces the legacy handshake. It reports supported
versions, capabilities, and server identity.

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: server/discover" \
  -d '{
    "jsonrpc": "2.0",
    "id": "discover-1",
    "method": "server/discover",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "id": "discover-1",
  "result": {
    "resultType": "complete",
    "supportedVersions": ["2026-07-28"],
    "capabilities": {
      "tools": {
        "listChanged": false
      }
    },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "mcp-gateway",
        "version": "1.0.0"
      }
    }
  }
}
```

### 2. List Tools

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/list" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

Tools are returned in deterministic (alphabetical) order.

### 3. Call Tool

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/call" \
  -H "Mcp-Name: search_scientific_literature" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "search_scientific_literature",
      "arguments": {
        "query": "attention mechanism neural networks",
        "top_k": 3
      },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

**Success response:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "resultType": "complete",
    "content": [
      {
        "type": "text",
        "text": "{\"results\":[...]}"
      }
    ],
    "isError": false,
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "mcp-gateway",
        "version": "1.0.0"
      }
    }
  }
}
```

### 4. Legacy `initialize`

The 2026-07-28 revision removed the handshake. `initialize` and `initialized`
return HTTP 404 with `-32601` (`MethodNotFound`) and advertise the supported
versions so a legacy client can retry using the per-request model:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found",
    "data": {
      "method": "initialize",
      "supported": ["2026-07-28"]
    }
  }
}
```

---

## Error Handling

### HTTP Status Codes

| JSON-RPC Error Code | HTTP Status | Description |
|-------------------|-------------|-------------|
| `-32700` (ParseError) | 400 | Invalid JSON |
| `-32600` (InvalidRequest) | 400 | Invalid request |
| `-32601` (MethodNotFound) | 404 | Unknown method or legacy `initialize` |
| `-32602` (InvalidParams) | 400 | Missing/invalid `_meta`, tool name, arguments, or unknown tool |
| `-32020` (HeaderMismatch) | 400 | Missing or mismatched MCP headers |
| `-32021` (MissingRequiredClientCapability) | 400 | Client lacks a required capability |
| `-32022` (UnsupportedProtocolVersion) | 400 | Version not supported; `data.supported` lists valid versions |
| `-32603` (InternalError) | 500 | Internal server error |
| — (Origin rejected) | 403 | `Origin` does not match the gateway host |

Tool execution failures are **not** JSON-RPC errors. They return HTTP 200 with
`result.isError: true` and the error text in `result.content`:

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "resultType": "complete",
    "content": [
      {
        "type": "text",
        "text": "invalid departure date"
      }
    ],
    "isError": true
  }
}
```

### Unsupported Version Example

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32022,
    "message": "Unsupported protocol version",
    "data": {
      "requested": "2025-11-25",
      "supported": ["2026-07-28"]
    }
  }
}
```

---

## Trace ID Propagation

To enable distributed tracing, include `X-Request-ID` or `X-Trace-ID` header:

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: server/discover" \
  -H "X-Request-ID: my-custom-trace-id" \
  -d '{...}'
```

This trace ID will be propagated to downstream services (arxiv-go-backend, rag-api, llm-eval-framework).

---

## Security Considerations

### Origin Validation
- Requests with an `Origin` header are accepted only when it matches the
  request host (`http` or `https`); otherwise the server returns 403.
- Non-browser clients normally omit `Origin`.

### Request Body Size Limit
- Maximum request body: 1 MiB
- Prevents DoS attacks

### No Authentication (Current)
- MCP endpoint currently has no authentication
- For production, add authentication middleware before MCP handler
- Recommended: API key, JWT, or mutual TLS

### Rate Limiting
- Currently no rate limiting
- For production, add rate limiting middleware

---

## Configuration

### Environment Variables

MCP server uses the same configuration as gateway:
- `ARXIV_SERVICE_URL`: Backend arxiv service URL
- `RAG_SERVICE_URL`: Backend RAG service URL
- `EVAL_SERVICE_URL`: Backend evaluator service URL
- `GROQ_API_KEY`: Groq API key for generation
- `OLLAMA_HOST`: Ollama service URL (for local LLM)

### Docker Compose

MCP endpoint is available when running in Mode A (root compose):

```bash
make up
# MCP endpoint: http://localhost:8090/mcp
```

---

### 3. SSE (Server-Sent Events) Transport
The MCP endpoint also supports SSE for clients that prefer streaming responses. When `Accept: text/event-stream` is sent, responses are returned in SSE format.

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/list" \
  -H "Accept: text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

**SSE Response Format:**
```
event: message
data: {"jsonrpc":"2.0","id":1,"result":{...}}

```

### Optional
- [ ] Authentication/authorization
- [ ] Rate limiting
- [ ] Metrics specific to MCP (request count, latency)
- [ ] Webhook notifications for tool list changes

---

## Testing

### Manual Test with curl

```bash
# Discover
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: server/discover" \
  -d '{"jsonrpc":"2.0","id":"discover-1","method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'

# List tools
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/list" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'

# Call tool
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/call" \
  -H "Mcp-Name: search_scientific_literature" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_scientific_literature","arguments":{"query":"attention mechanism","top_k":3},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

### Automated Tests

```bash
cd mcp-gateway
go test ./internal/mcp -count=1
go test ./... -race -count=1
```

---

## Troubleshooting

### Connection Refused
- Ensure gateway is running: `make status`
- Check if port 8090 is available

### 400 Bad Request
- Check JSON syntax
- Verify `params._meta.io.modelcontextprotocol/protocolVersion` is `"2026-07-28"`
- Verify `params._meta.io.modelcontextprotocol/clientCapabilities` is present
- Verify `MCP-Protocol-Version` and `Mcp-Method` headers are present and match the body
- Verify `Mcp-Name` is present for `tools/call` and matches `params.name`

### 403 Forbidden
- The request carried an `Origin` that does not match the gateway host
- Remove the header (non-browser clients) or use the gateway's own origin

### 404 Not Found
- Check method name is correct (case-sensitive)
- `initialize` is intentionally unsupported; use `server/discover`

### 500 Internal Server Error
- Check gateway logs: `make logs SERVICE=ws-mcp-gateway`
- Verify downstream services are healthy: `curl http://localhost:8080/health`

---

## References

- MCP Specification: https://modelcontextprotocol.io/specification/2026-07-28
- MCP Versioning: https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning.md
- MCP Discovery: https://modelcontextprotocol.io/specification/2026-07-28/server/discover.md
- MCP Streamable HTTP: https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http.md
- MCP Tools: https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md
- JSON-RPC 2.0: https://www.jsonrpc.org/specification
- Transport Decision: `docs/mcp-transport-decision.md`
- Product Strategy: `docs/product-strategy.md`
