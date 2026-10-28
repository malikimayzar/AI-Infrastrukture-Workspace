# LLM Provider Fallback Strategy

> **Last Updated:** 2026-10-28
> **Purpose:** Guide for implementing multi-provider fallback mechanism

## Overview

This document describes the multi-provider fallback strategy for the AI Infra Workspace to ensure high availability and graceful degradation when providers experience rate limits or outages.

## Provider Strategy

### Recommended Provider Stack

| Priority | Provider | Model | Cost | Speed | Use Case |
|---------|----------|-------|------|-------|----------|
| **Primary** | Groq | `openai/gpt-oss-20b` | Very Low ($0.59/1M tokens) | Very Fast | Production primary |
| **Secondary** | Anthropic | `claude-3-haiku-20240307` | Low ($0.25/1M input, $1.25/1M output) | Fast | Fallback for quality |
| **Tertiary** | OpenAI | `gpt-4o-mini` | Medium ($0.15/1M input, $0.60/1M output) | Fast | Reliable fallback |
| **Local** | Ollama | `phi3:mini` | Free (local) | Slow | Final fallback |

### Why This Stack?

1. **Groq (Primary):**
   - Extremely fast (sub-100ms latency)
   - Very cost-effective
   - Good quality for RAG tasks
   - **Risk:** Rate limits during peak usage

2. **Anthropic (Secondary):**
   - Higher quality outputs
   - Reasonable cost
   - More reliable than Groq
   - **Risk:** Higher cost, rate limits

3. **OpenAI (Tertiary):**
   - Most reliable
   - Good quality
   - Higher cost
   - **Risk:** Highest cost

4. **Ollama (Local):**
   - No API costs
   - No rate limits
   - **Risk:** High latency, requires local GPU/RAM

## Fallback Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Request                                 │
└──────────────────────────┬────────────────────────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │   Groq API      │
                  │ (Primary)       │
                  └────────┬────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
         SUCCESS                  FAILURE
         (Response)           (429/Timeout/Error)
              │                         │
              ▼                         ▼
        Return to User         ┌─────────────────┐
                              │  Anthropic API  │
                              │  (Secondary)    │
                              └────────┬────────┘
                                       │
                           ┌───────────┴───────────┐
                           │                       │
                      SUCCESS               FAILURE
                           │                       │
                           ▼                       ▼
                     Return to User         ┌─────────────────┐
                                            │   OpenAI API    │
                                            │   (Tertiary)    │
                                            └────────┬────────┘
                                                     │
                                         ┌────────────┴────────────┐
                                         │                         │
                                    SUCCESS                FAILURE
                                         │                         │
                                         ▼                         ▼
                                   Return to User         ┌─────────────────┐
                                                          │   Ollama API   │
                                                          │   (Local)      │
                                                          └────────┬────────┘
                                                                   │
                                                       ┌───────────┴───────────┐
                                                       │                       │
                                                  SUCCESS                FAILURE
                                                       │                       │
                                                       ▼                       ▼
                                                 Return to User      ABSTAIN
                                                                    (No answer)
```

## Implementation

### Environment Configuration

```bash
# Provider strategy
LLM_PROVIDER_STRATEGY=fallback
LLM_PRIMARY_PROVIDER=groq
LLM_FALLBACK_PROVIDERS=anthropic,openai,ollama

# Provider-specific configs
GROQ_API_KEY=gsk_your_key
ANTHROPIC_API_KEY=sk-ant-your_key
OPENAI_API_KEY=sk-your_key
```

### Python Implementation Example

```python
# src/llm/fallback_client.py
import os
from typing import Optional, List
from enum import Enum

class Provider(Enum):
    GROQ = "groq"
    ANTHROPIC = "anthropic"
    OPENAI = "openai"
    OLLAMA = "ollama"

class LLMFallbackClient:
    def __init__(self):
        self.strategy = os.getenv("LLM_PROVIDER_STRATEGY", "single")
        self.primary = Provider(os.getenv("LLM_PRIMARY_PROVIDER", "groq"))
        self.fallbacks = [
            Provider(p.strip())
            for p in os.getenv("LLM_FALLBACK_PROVIDERS", "").split(",")
            if p.strip()
        ]

    def generate(self, prompt: str, max_retries: int = 2) -> str:
        if self.strategy == "single":
            return self._call_provider(self.primary, prompt)

        # Fallback strategy
        providers = [self.primary] + self.fallbacks

        for provider in providers:
            try:
                response = self._call_provider(provider, prompt, max_retries)
                # Log successful provider
                self._log_provider_used(provider)
                return response
            except (RateLimitError, TimeoutError, APIError) as e:
                # Log failure and try next provider
                self._log_provider_failed(provider, str(e))
                continue

        # All providers failed
        raise GenerationError("All LLM providers failed")

    def _call_provider(self, provider: Provider, prompt: str, retries: int) -> str:
        """Call specific provider with retry logic"""
        if provider == Provider.GROQ:
            return self._call_groq(prompt, retries)
        elif provider == Provider.ANTHROPIC:
            return self._call_anthropic(prompt, retries)
        elif provider == Provider.OPENAI:
            return self._call_openai(prompt, retries)
        elif provider == Provider.OLLAMA:
            return self._call_ollama(prompt, retries)
        else:
            raise ValueError(f"Unknown provider: {provider}")

    def _call_groq(self, prompt: str, retries: int) -> str:
        """Groq API call with retry"""
        api_key = os.getenv("GROQ_API_KEY")
        model = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b")
        timeout = int(os.getenv("GROQ_TIMEOUT_MS", "30000"))

        # Implementation using Groq SDK
        # Handle 429, timeout, and other errors
        pass

    def _call_anthropic(self, prompt: str, retries: int) -> str:
        """Anthropic API call with retry"""
        api_key = os.getenv("ANTHROPIC_API_KEY")
        model = os.getenv("ANTHROPIC_MODEL", "claude-3-haiku-20240307")
        timeout = int(os.getenv("ANTHROPIC_TIMEOUT_MS", "60000"))
        pass

    def _call_openai(self, prompt: str, retries: int) -> str:
        """OpenAI API call with retry"""
        api_key = os.getenv("OPENAI_API_KEY")
        model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        timeout = int(os.getenv("OPENAI_TIMEOUT_MS", "60000"))
        pass

    def _call_ollama(self, prompt: str, retries: int) -> str:
        """Ollama local call with retry"""
        model = os.getenv("OLLAMA_MODEL", "phi3:mini")
        timeout = int(os.getenv("OLLAMA_TIMEOUT_MS", "120000"))
        pass

    def _log_provider_used(self, provider: Provider):
        """Log which provider succeeded"""
        # Implement logging
        pass

    def _log_provider_failed(self, provider: Provider, error: str):
        """Log provider failure"""
        # Implement logging
        pass
```

### Go Implementation Example

```go
// internal/llm/fallback_client.go
package llm

import (
	"context"
	"fmt"
	"os"
	"strings"
)

type Provider string

const (
	ProviderGroq       Provider = "groq"
	ProviderAnthropic  Provider = "anthropic"
	ProviderOpenAI     Provider = "openai"
	ProviderOllama     Provider = "ollama"
)

type Strategy string

const (
	StrategySingle      Strategy = "single"
	StrategyFallback    Strategy = "fallback"
	StrategyLoadBalanced Strategy = "load_balanced"
)

type FallbackClient struct {
	strategy  Strategy
	primary   Provider
	fallbacks []Provider
}

func NewFallbackClient() *FallbackClient {
	strategy := Strategy(os.Getenv("LLM_PROVIDER_STRATEGY"))
	if strategy == "" {
		strategy = StrategySingle
	}

	primary := Provider(os.Getenv("LLM_PRIMARY_PROVIDER"))
	if primary == "" {
		primary = ProviderGroq
	}

	fallbacksStr := os.Getenv("LLM_FALLBACK_PROVIDERS")
	var fallbacks []Provider
	if fallbacksStr != "" {
		for _, p := range strings.Split(fallbacksStr, ",") {
			if trimmed := strings.TrimSpace(p); trimmed != "" {
				fallbacks = append(fallbacks, Provider(trimmed))
			}
		}
	}

	return &FallbackClient{
		strategy:  strategy,
		primary:   primary,
		fallbacks: fallbacks,
	}
}

func (c *FallbackClient) Generate(ctx context.Context, prompt string) (string, error) {
	if c.strategy == StrategySingle {
		return c.callProvider(ctx, c.primary, prompt)
	}

	// Fallback strategy
	providers := append([]Provider{c.primary}, c.fallbacks...)

	var lastErr error
	for _, provider := range providers {
		response, err := c.callProvider(ctx, provider, prompt)
		if err == nil {
			// Log successful provider
			c.logProviderUsed(provider)
			return response, nil
		}

		// Log failure and try next
		lastErr = err
		c.logProviderFailed(provider, err.Error())
	}

	return "", fmt.Errorf("all LLM providers failed, last error: %w", lastErr)
}

func (c *FallbackClient) callProvider(ctx context.Context, provider Provider, prompt string) (string, error) {
	switch provider {
	case ProviderGroq:
		return c.callGroq(ctx, prompt)
	case ProviderAnthropic:
		return c.callAnthropic(ctx, prompt)
	case ProviderOpenAI:
		return c.callOpenAI(ctx, prompt)
	case ProviderOllama:
		return c.callOllama(ctx, prompt)
	default:
		return "", fmt.Errorf("unknown provider: %s", provider)
	}
}

func (c *FallbackClient) callGroq(ctx context.Context, prompt string) (string, error) {
	// Implementation
	return "", nil
}

func (c *FallbackClient) callAnthropic(ctx context.Context, prompt string) (string, error) {
	// Implementation
	return "", nil
}

func (c *FallbackClient) callOpenAI(ctx context.Context, prompt string) (string, error) {
	// Implementation
	return "", nil
}

func (c *FallbackClient) callOllama(ctx context.Context, prompt string) (string, error) {
	// Implementation
	return "", nil
}

func (c *FallbackClient) logProviderUsed(provider Provider) {
	// Implement logging
}

func (c *FallbackClient) logProviderFailed(provider Provider, error string) {
	// Implement logging
}
```

## Cost Management

### Cost Comparison (per 1M tokens)

| Provider | Input | Output | Notes |
|----------|-------|--------|-------|
| Groq | $0.59 | $0.59 | Fastest, cheapest |
| Anthropic Haiku | $0.25 | $1.25 | Good quality |
| OpenAI GPT-4o-mini | $0.15 | $0.60 | Reliable |
| Ollama | $0 | $0 | Free, but requires hardware |

### Cost Optimization Strategies

1. **Prioritize Groq:** Use Groq for 80-90% of requests
2. **Fallback Trigger:** Only fallback on 429/timeout
3. **Cache Results:** Implement Redis cache for identical queries
4. **Batch Requests:** Process multiple queries in single API call
5. **Monitor Usage:** Track token usage per provider

### Estimated Monthly Costs

Assuming 1M tokens/day:

| Scenario | Groq | Anthropic | OpenAI | Total |
|----------|------|-----------|--------|-------|
| Groq only (ideal) | $17.70 | $0 | $0 | $17.70 |
| 80% Groq, 20% Anthropic | $14.16 | $5.40 | $0 | $19.56 |
| 60% Groq, 30% Anthropic, 10% OpenAI | $10.62 | $8.10 | $1.80 | $20.52 |

## Monitoring & Alerting

### Metrics to Track

1. **Provider Success Rate:**
   ```promql
   rate(llm_provider_success_total{provider="groq"}[5m])
   ```

2. **Provider Latency:**
   ```promql
   histogram_quantile(0.95, llm_provider_latency_seconds{provider="groq"})
   ```

3. **Fallback Rate:**
   ```promql
   rate(llm_fallback_triggered_total[5m])
   ```

4. **Token Usage per Provider:**
   ```promql
   sum(llm_tokens_used_total{provider="groq"})
   ```

### Alerting Rules

```yaml
# Alert if Groq success rate drops below 90%
- alert: HighGroqFailureRate
  expr: rate(llm_provider_success_total{provider="groq"}[5m]) < 0.9
  for: 5m
  annotations:
    summary: "Groq provider failure rate is high"

# Alert if fallback rate exceeds 20%
- alert: HighFallbackRate
  expr: rate(llm_fallback_triggered_total[5m]) > 0.2
  for: 10m
  annotations:
    summary: "High fallback rate detected"

# Alert if all providers fail
- alert: AllProvidersDown
  expr: rate(llm_provider_success_total[5m]) == 0
  for: 2m
  annotations:
    summary: "All LLM providers are failing"
```

## Testing

### Test Scenarios

1. **Primary Success:**
   - Mock Groq success → Should use Groq only

2. **Primary Rate Limit:**
   - Mock Groq 429 → Should fallback to Anthropic

3. **All Cloud Fail:**
   - Mock all cloud providers fail → Should fallback to Ollama

4. **All Fail:**
   - Mock all providers fail → Should return error/abstain

### Test Implementation

```python
# tests/test_fallback_client.py
import pytest
from unittest.mock import patch
from src.llm.fallback_client import LLMFallbackClient, Provider

def test_primary_success():
    client = LLMFallbackClient()
    with patch.object(client, '_call_groq', return_value="Groq response"):
        response = client.generate("test prompt")
        assert response == "Groq response"

def test_fallback_on_rate_limit():
    client = LLMFallbackClient()
    with patch.object(client, '_call_groq', side_effect=RateLimitError):
        with patch.object(client, '_call_anthropic', return_value="Anthropic response"):
            response = client.generate("test prompt")
            assert response == "Anthropic response"

def test_all_cloud_fail_fallback_to_ollama():
    client = LLMFallbackClient()
    with patch.object(client, '_call_groq', side_effect=APIError):
        with patch.object(client, '_call_anthropic', side_effect=APIError):
            with patch.object(client, '_call_openai', side_effect=APIError):
                with patch.object(client, '_call_ollama', return_value="Ollama response"):
                    response = client.generate("test prompt")
                    assert response == "Ollama response"

def test_all_fail_raises_error():
    client = LLMFallbackClient()
    with patch.object(client, '_call_groq', side_effect=APIError):
        with patch.object(client, '_call_anthropic', side_effect=APIError):
            with patch.object(client, '_call_openai', side_effect=APIError):
                with patch.object(client, '_call_ollama', side_effect=APIError):
                    with pytest.raises(GenerationError):
                        client.generate("test prompt")
```

## Rollout Plan

### Phase 1: Configuration (Week 1)
- [ ] Update `.env.example` with multi-provider config
- [ ] Add API keys for Anthropic and OpenAI (optional)
- [ ] Update documentation

### Phase 2: Implementation (Week 2)
- [ ] Implement `LLMFallbackClient` in Python
- [ ] Implement `FallbackClient` in Go
- [ ] Update existing LLM calls to use fallback client

### Phase 3: Testing (Week 2-3)
- [ ] Unit tests for fallback logic
- [ ] Integration tests with real providers
- [ ] Load testing with simulated failures

### Phase 4: Monitoring (Week 3)
- [ ] Add Prometheus metrics for provider usage
- [ ] Setup Grafana dashboards
- [ ] Configure alerting rules

### Phase 5: Rollout (Week 4)
- [ ] Deploy to staging with fallback disabled
- [ ] Enable fallback in staging
- [ ] Monitor for 1 week
- [ ] Deploy to production

## Troubleshooting

### Issue: Fallback not triggering

**Symptoms:** Requests fail when Groq rate limits, but no fallback

**Solutions:**
1. Check `LLM_PROVIDER_STRATEGY=fallback` is set
2. Verify fallback providers are configured
3. Check API keys for fallback providers
4. Review logs for provider failure reasons

### Issue: High latency due to fallback

**Symptoms:** Response time increases significantly

**Solutions:**
1. Check if primary provider is failing frequently
2. Implement circuit breaker to stop failing providers
3. Increase timeout for primary provider
4. Consider load balancing instead of sequential fallback

### Issue: Cost spike

**Symptoms:** Unexpected cost increase

**Solutions:**
1. Check which provider is being used most
2. Review fallback rate metrics
3. Adjust fallback provider priority
4. Implement cost alerts

## References

- [Groq API Documentation](https://console.groq.com/docs)
- [Anthropic API Documentation](https://docs.anthropic.com/)
- [OpenAI API Documentation](https://platform.openai.com/docs)
- [Ollama Documentation](https://ollama.com/)
