# MCP Transport Layer Decision
> **Date:** 2026-10-24
> **Decision:** HTTP-based MCP (SSE) with optional stdio adapter
> **Status:** APPROVED

---

## Context

The Model Context Protocol (MCP) supports multiple transport layers:
- **stdio** - Standard input/output (common for Claude Desktop)
- **SSE (Server-Sent Events)** - HTTP-based streaming
- **WebSocket** - Real-time bidirectional communication
- **HTTP** - Standard HTTP request/response

The `mcp-gateway` currently runs as an HTTP server (Go + Chi) with mature endpoints:
- `/ask` - Answer generation endpoint
- `/plan` - Planning endpoint
- `/tool` - Tool execution endpoint
- `/health` - Liveness check
- `/ready` - Readiness check

---

## Decision

**Primary Transport:** HTTP-based MCP with SSE for streaming
**Secondary Transport:** stdio adapter (for Claude Desktop compatibility)

### Phase 1: HTTP-based MCP (SSE)

**Implementation Approach:**
1. Add MCP-specific HTTP endpoints to existing Chi router:
   - `POST /mcp` - Main MCP endpoint (JSON-RPC 2.0 over HTTP)
   - Support both request/response and SSE for streaming

2. Implement MCP server structure:
   - JSON-RPC 2.0 message handler
   - Tool registry (reuse existing `internal/registry`)
   - Initialization handshake (initialize, initialized)
   - Capability negotiation

3. Map existing tools to MCP tools:
   - `search_scientific_literature` → `search_arxiv` tool
   - `verify_factual_claim` → `research_rag` tool
   - `generate_audit_dossier` → `evaluate_answer` tool

**Why HTTP First:**
- Gateway already has HTTP infrastructure (Chi router, middleware, metrics)
- HTTP supports authentication/authorization (critical for B2B enterprise)
- HTTP is more scalable for multi-tenant SaaS
- Easier to debug and monitor (existing Prometheus metrics)
- Can be load-balanced behind nginx/traefik
- Lower development effort (reuse existing HTTP stack)

### Phase 2: stdio Adapter (Optional)

**Implementation Approach:**
1. Build a separate CLI executable that wraps HTTP MCP:
   - Reads MCP JSON-RPC messages from stdin
   - Forwards to HTTP `/mcp` endpoint
   - Writes responses to stdout

2. Configuration:
   - CLI accepts `--url` parameter for HTTP MCP endpoint
   - Supports authentication headers if needed

**Why stdio Second:**
- stdio is primarily for local development (Claude Desktop)
- Less critical for B2B enterprise SaaS
- Can be implemented as thin wrapper around HTTP
- Lower priority for commercialization

---

## Comparison

| Aspect | HTTP-based MCP | stdio | WebSocket |
|--------|----------------|-------|-----------|
| **Development Effort** | LOW (reuse existing) | MEDIUM (new adapter) | HIGH (new infrastructure) |
| **Authentication** | Native support | Limited | Native support |
| **Scalability** | HIGH (load balancer) | LOW (single process) | MEDIUM |
| **Enterprise Fit** | EXCELLENT | POOR | GOOD |
| **Claude Desktop** | Possible via adapter | NATIVE | Possible |
| **Monitoring** | EXCELLENT (Prometheus) | LIMITED | GOOD |
| **Debugging** | EXCELLENT (curl, logs) | LIMITED | GOOD |

---

## Implementation Plan

### Phase 1: HTTP-based MCP (Week 1-2)

**Tasks:**
1. Create `internal/mcp/` package:
   - `jsonrpc.go` - JSON-RPC 2.0 message types
   - `server.go` - MCP server structure
   - `handler.go` - HTTP handler for MCP
   - `tools.go` - MCP tool definitions

2. Add MCP endpoint to router:
   ```go
   r.Post("/mcp", handleMCP(reg, cfg))
   ```

3. Implement MCP handshake:
   - `initialize` - Client → Server
   - `initialized` - Server → Client
   - Capability negotiation

4. Register MCP tools:
   - `tools/list` - List available tools
   - `tools/call` - Execute tool

### Phase 2: stdio Adapter (Week 3-4)

**Tasks:**
1. Create `cmd/mcp-stdio/` directory
2. Implement stdio → HTTP bridge
3. Test with Claude Desktop

---

## Technical Details

### JSON-RPC 2.0 Message Format

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {},
  "_meta": {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {
      "tools": {}
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "resultType": "complete",
    "tools": [...]
  }
}
```

### Tool Definition

```go
type MCPTool struct {
    Name        string                 `json:"name"`
    Description string                 `json:"description"`
    InputSchema map[string]interface{} `json:"inputSchema"`
}
```

### Existing Tool Mapping

| MCP Tool Name | Existing Gateway Tool | Backend |
|---------------|----------------------|---------|
| `search_scientific_literature` | `search_arxiv` | arxiv-go-backend |
| `verify_factual_claim` | `research_rag` | rag-api |
| `generate_audit_dossier` | `evaluate_answer` | llm-eval-framework |

---

## Risks & Mitigations

### Risk 1: stdio Required by Claude Desktop
**Mitigation:** Build stdio adapter as thin wrapper around HTTP MCP

### Risk 2: HTTP MCP Not Supported by Some Clients
**Mitigation:** Support both HTTP and stdio; document both options

### Risk 3: SSE Implementation Complexity
**Mitigation:** Start with simple HTTP request/response; add SSE later if needed

---

## References

- MCP Specification: https://modelcontextprotocol.io/specification/2026-07-28
- MCP Tools: https://modelcontextprotocol.io/specification/2026-07-28/server/tools.md
- JSON-RPC 2.0: https://www.jsonrpc.org/specification
- Existing Gateway: `mcp-gateway/cmd/server/router.go`
- Existing Registry: `mcp-gateway/internal/registry/registry.go`

---

**Approved by:** Product Strategy Decision
**Next Review:** After Phase 1 implementation (2 weeks)
