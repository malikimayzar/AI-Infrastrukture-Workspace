# ADR-001: Use Groq as Primary LLM Provider

## Status

Accepted

## Context

The AI Infrastructure Platform requires a fast, reliable LLM provider for generation tasks across multiple services:
- `arxiv-python-ml` - Generates answers for ArXiv paper queries
- `rag-api` - Generates answers for general research queries
- Both services support multiple backends: Groq (cloud) and Ollama (local)

### Constraints

1. **RAM Constraint**: Host has ~15 GB RAM; loading Ollama's `phi3:mini` requires ~4.5 GB peak memory, which can cause OOM when desktop GUI is running
2. **Latency Requirement**: Target end-to-end latency ≤ 3.5s for generation
3. **Cost Consideration**: Need to balance between performance and operational cost
4. **Reliability**: Provider must be stable with minimal downtime

### Evaluated Options

#### Option 1: Ollama (Local) - `phi3:mini`
- **Pros**: Free, no API dependency, full control
- **Cons**: High RAM usage (~4.5 GB peak), cold load takes ~2.5 min, limited to host resources
- **Latency**: Slower on CPU, especially cold loads
- **Suitability**: Good for offline/demo scenarios when RAM is available

#### Option 2: Groq (Cloud) - `openai/gpt-oss-20b`
- **Pros**: Fast generation (2-5s per query), no RAM impact on host, high throughput
- **Cons**: API dependency, cost at scale, requires internet
- **Latency**: Consistently fast, no cold start
- **Suitability**: Primary provider for production and development

#### Option 3: Hybrid - Groq primary, Ollama fallback
- **Pros**: Best of both worlds, resilience through fallback
- **Cons**: Increased complexity, need to handle two code paths
- **Suitability**: Production with redundancy requirements

## Decision

**Use Groq as the primary LLM provider for all generation services.**

Configuration:
- Default model: `openai/gpt-oss-20b`
- Default provider: `groq` (set via `LLM_PROVIDER=groq` in `.env`)
- Ollama available as fallback when `LLM_PROVIDER=ollama`
- Ollama models: `phi3:mini`, `mistral`, `nomic-embed-text`

### Rationale

1. **Performance**: Groq provides consistently fast generation (~2-5s) without cold start penalties
2. **Resource Efficiency**: No RAM impact on host, avoiding OOM scenarios
3. **Developer Experience**: Faster iteration during development due to consistent latency
4. **Scalability**: Cloud provider scales horizontally without host resource constraints
5. **Cost-Performance**: At development/testing scale, Groq cost is acceptable vs RAM upgrade cost

### Implementation

#### Environment Variables
```bash
# Primary provider
LLM_PROVIDER=groq
GROQ_MODEL=openai/gpt-oss-20b
GROQ_API_KEY=gsk_...

# Fallback (set to "ollama" for local/demo)
LLM_PROVIDER=ollama
OLLAMA_HOST=http://ollama:11434
```

#### Service Configuration
- `arxiv-python-ml`: Reads `LLM_PROVIDER` from environment, defaults to `groq`
- `rag-api`: Reads `LLM_PROVIDER` from environment, defaults to `groq`
- Both services have same model configuration: `GROQ_MODEL`

#### Docker Compose
```yaml
environment:
  LLM_PROVIDER: ${LLM_PROVIDER:-groq}
  GROQ_MODEL: ${GROQ_MODEL:-openai/gpt-oss-20b}
  GROQ_API_KEY: ${GROQ_API_KEY:-}
  OLLAMA_HOST: ${OLLAMA_HOST:-http://ollama:11434}
```

## Consequences

### Positive
- ✅ Consistent, fast generation across all services
- ✅ No RAM constraints on host
- ✅ Simplified resource planning (no need for high-RAM machines)
- ✅ Better developer experience (no cold waits)
- ✅ Production-ready from day one

### Negative
- ❌ API dependency on Groq (requires internet and API key)
- ❌ Cost at scale (need to monitor usage)
- ❌ Potential rate limiting (need retry logic)
- ❌ Vendor lock-in (mitigated by keeping Ollama fallback)

### Mitigations
- Implement retry logic with exponential backoff (already in place)
- Add rate limit handling and circuit breakers
- Keep Ollama as documented fallback for offline scenarios
- Monitor Groq usage and costs via Prometheus metrics
- Use `make rotate-key` for secure key management

## Alternatives Considered

### Alternative 1: Use Ollama as Primary
**Rejected** due to RAM constraints and cold start latency on 15 GB host.

### Alternative 2: Use Both Equally
**Rejected** due to increased complexity without clear benefit for current scale.

### Alternative 3: Use Different Cloud Provider (OpenAI, Anthropic)
**Not evaluated** - Groq selected based on fast generation and cost-effectiveness for development/testing. Can revisit if Groq doesn't meet production needs.

## References

- `docs/ops-postmortem.md` - Scenario-3: `phi3:mini` OOM incident
- `docker-compose.yml` - Service configuration
- `.env.example` - Environment variable documentation
- `scripts/rotate_key.sh` - Key rotation script

## Revisions

- 2026-10-24: Initial ADR creation
