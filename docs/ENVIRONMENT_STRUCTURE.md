# Environment Configuration Structure

> **Last Updated:** 2026-10-28
> **Purpose:** Guide for understanding and managing environment variables across the workspace

## Overview

The AI Infra Workspace uses a hierarchical environment configuration system with two modes:

- **Mode A (Root Docker Compose):** Canonical mode for running all services together
- **Mode B (Standalone):** Individual service development mode

## File Structure

```
ai-infra-workspace/
├── .env.example              # Mode A: Root workspace (canonical)
├── arxiv-research-assistant/
│   └── .env.example          # Mode B: Standalone ArXiv service
├── mcp-gateway/
│   └── .env.example          # Mode B: Standalone Gateway
├── rag-research/
│   └── .env.example          # Mode B: Standalone RAG service
└── llm-eval-framework/
    ├── .env.example          # Mode B: Standalone Evaluation
    └── config.yaml           # Evaluation thresholds and model config
```

## Mode A: Root Docker Compose (Canonical)

**File:** `.env.example` (root workspace)

**When to use:**
- Running the full stack with `make up`
- Production deployment
- Integration testing

**Key characteristics:**
- All services use Docker internal DNS (container names)
- Single source of truth for shared infrastructure
- Includes all gateway, RAG, and evaluation configuration

**Service URLs (internal Docker network):**
```
ARXIV_SERVICE_URL=http://arxiv-go-backend:8080
EVAL_SERVICE_URL=http://llm-eval-framework:8002
RAG_SERVICE_URL=http://rag-api:8000
ML_SERVICE_URL=http://arxiv-python-ml:8001
QDRANT_URL=http://qdrant:6333
OLLAMA_HOST=http://ollama:11434
```

## Mode B: Standalone Development

**Files:** Individual `.env.example` in each service directory

**When to use:**
- Developing a single service in isolation
- Local debugging without Docker
- Unit testing individual components

**Key characteristics:**
- All services use `localhost` URLs
- Each service has its own configuration
- Useful for rapid iteration on specific services

**Service URLs (localhost):**
```
ARXIV_SERVICE_URL=http://localhost:8080
EVAL_SERVICE_URL=http://localhost:8002
RAG_SERVICE_URL=http://rag-api:8000
QDRANT_URL=http://localhost:6333
OLLAMA_HOST=http://localhost:11434
```

## Environment Variable Sections

All `.env.example` files are organized into logical sections:

### Section 1: Shared Infrastructure
- PostgreSQL configuration
- Database credentials

### Section 2: Service URLs
- Internal service endpoints
- Docker network vs localhost distinction

### Section 3: LLM Provider Configuration
- Provider selection (groq/ollama)
- Model configuration
- API keys (NEVER commit actual keys)

### Section 4: Service-Specific Configuration
- API server settings
- Confidence calibration (RAG)
- Embedding models (Evaluation)

### Section 5: Advanced Features
- Redis cache (opt-in)
- OpenTelemetry tracing (opt-in)
- Connection pooling

### Section 6: Gateway Configuration (MCP Gateway only)
- Authentication
- Rate limiting
- Backend timeouts
- Response size limits

## Secret Management

### Rules

1. **NEVER commit `.env` files** - They are gitignored
2. **ALWAYS use placeholders in `.env.example`** - Format: `gsk_your_actual_key_here`
3. **Use `make check-secrets`** - Validates no leaked secrets before commit
4. **Rotate keys via `make rotate-key`** - Safe key rotation without restart

### Placeholder Format

```bash
# Correct (placeholder)
GROQ_API_KEY=gsk_your_actual_key_here

# Incorrect (actual key - DO NOT COMMIT)
GROQ_API_KEY=gsk_abc123xyz789
```

## Quick Start

### Mode A (Root Workspace)

```bash
# 1. Copy example to actual env
cp .env.example .env

# 2. Set your Groq API key
nano .env  # Edit GROQ_API_KEY

# 3. Start all services
make up

# 4. Verify secrets are clean
make check-secrets
```

### Mode B (Standalone)

```bash
# 1. Navigate to service directory
cd rag-research

# 2. Copy example to actual env
cp .env.example .env

# 3. Set your Groq API key
nano .env  # Edit GROQ_API_KEY

# 4. Start service locally
python -m uvicorn src.api:app --host 0.0.0.0 --port 8000
```

## Migration Notes

### From Old Structure to New Structure

**Changes made on 2026-10-28:**
1. Added comprehensive section headers to all `.env.example` files
2. Standardized placeholder format for secrets
3. Added instructions and usage comments
4. Organized variables into logical groups
5. Created `.env.example` for llm-eval-framework (was missing)
6. Improved `config.yaml` documentation for llm-eval-framework

**No breaking changes:**
- All existing variable names remain the same
- Default values unchanged
- Docker compose configuration unchanged

## Troubleshooting

### Issue: "Variable not found" error

**Cause:** Missing variable in `.env` file

**Solution:**
1. Check `.env.example` for the variable
2. Copy the variable to your `.env`
3. Set appropriate value

### Issue: Services can't connect to each other

**Cause:** Mode mismatch (using localhost URLs in Docker Mode A)

**Solution:**
- For Mode A: Use root `.env` with container names
- For Mode B: Use individual `.env` with localhost URLs

### Issue: Secrets detected by `make check-secrets`

**Cause:** Actual key committed to `.env.example` or tracked file

**Solution:**
1. Run `make check-secrets` to identify the file
2. Replace actual key with placeholder
3. Commit the fix
4. Verify with `make check-secrets` again

## References

- [AGENTS.md](../AGENTS.md) - Full agent guide with environment variable details
- [PROJECT_GOALS.md](../PROJECT_GOALS.md) - Engineering specifications
- [docs/OPERATIONS.md](OPERATIONS.md) - Operations and troubleshooting guide
