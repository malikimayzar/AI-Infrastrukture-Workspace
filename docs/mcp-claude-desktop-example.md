# MCP Integration Examples

## Claude Desktop Configuration

For Claude Desktop integration, you need to configure the MCP server in Claude's settings file (`claude_desktop_config.json`).

### Option 1: stdio Transport (Recommended)

The stdio transport runs the gateway as a local subprocess, which Claude Desktop launches natively. This is the preferred option for Claude Desktop.

**Prerequisites:** Build the gateway binary first:
```bash
cd mcp-gateway
go build -o mcp-gateway ./cmd/server
```

**Configuration** (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "scientific-claim-auditor": {
      "command": "/absolute/path/to/mcp-gateway/mcp-gateway",
      "args": ["--transport=stdio"],
      "env": {
        "ARXIV_SERVICE_URL": "http://localhost:8080",
        "RAG_SERVICE_URL": "http://localhost:8000",
        "EVAL_SERVICE_URL": "http://localhost:8002",
        "POSTGRES_DSN": "host=localhost port=5432 user=arxiv password=arxiv_secret dbname=arxiv_db sslmode=disable",
        "GROQ_API_KEY": "your-groq-api-key",
        "GROQ_MODEL": "openai/gpt-oss-20b"
      }
    }
  }
}
```

Alternatively, use the `MCP_TRANSPORT` environment variable instead of the `--transport` flag:

```json
{
  "mcpServers": {
    "scientific-claim-auditor": {
      "command": "/absolute/path/to/mcp-gateway/mcp-gateway",
      "args": [],
      "env": {
        "MCP_TRANSPORT": "stdio",
        "ARXIV_SERVICE_URL": "http://localhost:8080",
        "RAG_SERVICE_URL": "http://localhost:8000",
        "EVAL_SERVICE_URL": "http://localhost:8002",
        "POSTGRES_DSN": "host=localhost port=5432 user=arxiv password=arxiv_secret dbname=arxiv_db sslmode=disable",
        "GROQ_API_KEY": "your-groq-api-key"
      }
    }
  }
}
```

### Option 2: SSE Transport (HTTP Streaming)

If Claude Desktop supports SSE transport via HTTP, configure:

```json
{
  "mcpServers": {
    "scientific-claim-auditor": {
      "command": "/absolute/path/to/mcp-gateway/mcp-gateway",
      "args": [],
      "env": {
        "ARXIV_SERVICE_URL": "http://localhost:8080",
        "RAG_SERVICE_URL": "http://localhost:8000",
        "EVAL_SERVICE_URL": "http://localhost:8002",
        "POSTGRES_DSN": "host=localhost port=5432 user=arxiv password=arxiv_secret dbname=arxiv_db sslmode=disable",
        "GROQ_API_KEY": "your-groq-api-key"
      }
    }
  }
}
```

Then access the SSE endpoint at `http://localhost:8090/mcp` with `Accept: text/event-stream` header.

---

## Cursor Integration

### Configuration in Cursor Settings

1. Open Cursor Settings → Features → MCP
2. Add new MCP server:
   - **Name:** `scientific-claim-auditor`
   - **Command:** `/absolute/path/to/mcp-gateway/mcp-gateway`
   - **Arguments:** `--transport=stdio`
   - **Environment variables:** Set `ARXIV_SERVICE_URL`, `RAG_SERVICE_URL`, `EVAL_SERVICE_URL`, `POSTGRES_DSN`, `GROQ_API_KEY`

Alternatively, use SSE via HTTP:
   - **URL:** `http://localhost:8090/mcp`
   - **Headers:** `MCP-Protocol-Version: 2026-07-28`

### Usage in Cursor

Once configured, Cursor's AI agent will automatically discover the three available tools:

1. **`search_scientific_literature`** - Search arXiv for scientific papers
2. **`verify_factual_claim`** - Verify factual claims against RAG corpus with span-level attribution
3. **`generate_audit_dossier`** - Generate an audit dossier evaluating an answer against evidence

**Example prompt for Cursor:**
> "Search for papers about attention mechanism and verify the claim that multi-head attention reduces spatial bias in images, then generate an audit dossier for the answer."

---

## Complete Workflow Example

### Step 1: Discover Server Capabilities

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: server/discover" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "server/discover",
    "params": {
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

### Step 2: List Available Tools

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

### Step 3: Search for Papers

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
        "query": "transformer architecture attention mechanism",
        "top_k": 5
      },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

### Step 4: Verify a Claim

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/call" \
  -H "Mcp-Name: verify_factual_claim" \
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
      },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

### Step 5: Generate Audit Dossier

```bash
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/call" \
  -H "Mcp-Name: generate_audit_dossier" \
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
      },
      "_meta": {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
      }
    }
  }'
```

---

## Troubleshooting

### Claude Desktop Can't Connect
- Ensure gateway binary is built: `go build -o mcp-gateway ./cmd/server`
- Verify binary path is absolute in config
- Check stdio transport: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}' | ./mcp-gateway --transport=stdio`
- Check logs at `~/.config/Claude/logs/mcp/`

### Cursor Can't Discover Tools
- Verify gateway is running: `curl http://localhost:8090/health`
- Check MCP endpoint: `curl http://localhost:8090/mcp`
- Ensure `MCP-Protocol-Version: 2026-07-28` header is set
- Check Cursor MCP settings page

### Timeouts
- Default timeout: 620s (from gateway config)
- For long-running queries, use SSE transport with `Accept: text/event-stream`

---

## References

- MCP Integration Guide: `docs/mcp-integration-guide.md`
- MCP Specification: https://modelcontextprotocol.io/specification/2026-07-28
- Transport Decision: `docs/mcp-transport-decision.md`
