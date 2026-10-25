# MCP Integration Examples

## Claude Desktop Configuration

For Claude Desktop integration, you need to configure the MCP server in Claude's settings.

### HTTP-based MCP (Current Implementation)

Since the gateway currently uses HTTP-based MCP, you can configure Claude Desktop to connect via HTTP:

```json
{
  "mcpServers": {
    "scientific-audit": {
      "command": "node",
      "args": [
        "-e",
        "require('http').request('http://localhost:8090/mcp', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{},_meta:{'io.modelcontextprotocol/protocolVersion':'2026-07-28','io.modelcontextprotocol/clientCapabilities':{tools:{}}}})}).then(r=>r.json()).then(console.log)"
      ]
    }
  }
}
```

**Note:** HTTP-based MCP in Claude Desktop may require a custom client or proxy. The stdio adapter (planned) will provide native support.

---

## Cursor Integration

For Cursor IDE integration with MCP:

### Configuration in Cursor Settings

1. Open Cursor Settings → MCP Servers
2. Add new server:
   - Name: `scientific-audit`
   - URL: `http://localhost:8090/mcp`
   - Protocol: HTTP-based MCP

### Usage in Cursor

```python
# In Cursor, you can use the tools directly:
# The AI agent will automatically discover available tools

# Example prompt to Cursor:
# "Search for papers about attention mechanism and verify the claim about spatial bias"
```

Cursor will automatically:
1. Call `tools/list` to discover available tools
2. Call `tools/call` with `search_scientific_literature`
3. Call `tools/call` with `verify_factual_claim`
4. Present results with evidence

---

## Devin Integration

For Devin CLI integration, the MCP tools can be called via the skill system:

### Example Workflow

```bash
# Ask Devin to use the MCP tools
devin "Search for papers about transformer architecture and verify the claim about attention mechanism"
```

Devin will:
1. Use the `devin-cli` skill to understand the task
2. Call MCP tools via HTTP endpoint
3. Return results with evidence

---

## Example: Complete Workflow

### Step 1: Initialize MCP

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {},
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {
        "tools": {}
      }
    }
  }'
```

### Step 2: List Available Tools

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {},
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {
        "tools": {}
      }
    }
  }'
```

### Step 3: Search for Papers

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "search_scientific_literature",
      "arguments": {
        "query": "transformer architecture attention mechanism",
        "top_k": 5
      }
    },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {
        "tools": {}
      }
    }
  }'
```

### Step 4: Verify a Claim

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 4,
    "method": "tools/call",
    "params": {
      "name": "verify_factual_claim",
      "arguments": {
        "query": "Multi-head attention reduces spatial bias in images",
        "top_k": 5,
        "use_reranker": true
      }
    },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {
        "tools": {}
      }
    }
  }'
```

### Step 5: Generate Audit Dossier

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 5,
    "method": "tools/call",
    "params": {
      "name": "generate_audit_dossier",
      "arguments": {
        "question": "How does multi-head attention work?",
        "answer": "Multi-head attention projects queries, keys, and values into multiple subspaces...",
        "context": "Attention is all you need paper excerpt..."
      }
    },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {
        "tools": {}
      }
    }
  }'
```

---

## Future: stdio Adapter (Planned)

Once the stdio adapter is implemented, Claude Desktop configuration will be simpler:

```json
{
  "mcpServers": {
    "scientific-audit": {
      "command": "mcp-stdio-adapter",
      "args": ["--url", "http://localhost:8090/mcp"]
    }
  }
}
```

This will provide native Claude Desktop support without workarounds.

---

## Troubleshooting

### Claude Desktop Can't Connect
- Ensure gateway is running: `make status`
- Check if port 8090 is accessible
- Try HTTP-based MCP workaround above

### Cursor Can't Discover Tools
- Check MCP endpoint is accessible: `curl http://localhost:8090/mcp`
- Verify protocol version is 2026-07-28
- Check Cursor MCP settings

### Timeouts
- Default timeout: 30s (from config)
- Increase if needed by modifying `RequestTimeout` in config
- For long-running queries, consider streaming (SSE) implementation

---

## References

- MCP Integration Guide: `docs/mcp-integration-guide.md`
- MCP Specification: https://modelcontextprotocol.io/specification/2026-07-28
- Transport Decision: `docs/mcp-transport-decision.md`
