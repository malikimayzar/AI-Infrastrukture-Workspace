# Deep Health Check Implementation Guide

## Overview

This workspace provides comprehensive health check utilities for verifying dependencies:
- PostgreSQL database connectivity
- Qdrant vector database connectivity
- Ollama LLM service availability
- Embedding model loading status

## Components

### 1. Health Check Utilities

Location: `scripts/health_check_utils.py`

Provides:
- `HealthChecker` class for async health checks
- Synchronous wrapper functions for non-async contexts
- `HealthCheckResult` dataclass for structured results
- `HealthStatus` enum (HEALTHY, DEGRADED, UNHEALTHY, UNKNOWN)

### 2. FastAPI Health Endpoints

Location: `scripts/health_check_api.py`

Provides:
- `/health` - Basic liveness probe
- `/health/deep` - Comprehensive readiness probe with dependency checks

## Integration Guide

### For Python Services (FastAPI)

#### rag-api Integration

Add to `rag-research/src/api/main.py`:

```python
import sys
import os
sys.path.insert(0, '/home/malikimayzar/projects/ai-infra-workspace/scripts')

from health_check_api import add_health_routes
from fastapi import FastAPI

app = FastAPI()
add_health_routes(app, service_name="rag-api")

# Rest of your app...
```

#### arxiv-python-ml Integration

Add to `arxiv-research-assistant/python-ml/main.py`:

```python
import sys
import os
sys.path.insert(0, '/home/malikimayzar/projects/ai-infra-workspace/scripts')

from health_check_api import add_health_routes
from fastapi import FastAPI

app = FastAPI()
add_health_routes(app, service_name="arxiv-python-ml")

# Rest of your app...
```

#### llm-eval-framework Integration

Add to `llm-eval-framework/main.py` or wherever FastAPI app is defined:

```python
import sys
import os
sys.path.insert(0, '/home/malikimayzar/projects/ai-infra-workspace/scripts')

from health_check_api import add_health_routes
from fastapi import FastAPI

app = FastAPI()
add_health_routes(app, service_name="llm-eval-framework")

# Rest of your app...
```

### For Go Services (mcp-gateway)

Create `mcp-gateway/internal/health/checker.go`:

```go
package health

import (
    "database/sql"
    "encoding/json"
    "fmt"
    "net/http"
    "time"
)

type HealthStatus string

const (
    StatusHealthy   HealthStatus = "healthy"
    StatusDegraded  HealthStatus = "degraded"
    StatusUnhealthy HealthStatus = "unhealthy"
    StatusUnknown   HealthStatus = "unknown"
)

type HealthCheckResult struct {
    Component  string                 `json:"component"`
    Status     HealthStatus           `json:"status"`
    Message    string                 `json:"message"`
    LatencyMs  float64                `json:"latency_ms"`
    Details    map[string]interface{} `json:"details,omitempty"`
}

type HealthResponse struct {
    Status  string                      `json:"status"`
    Service string                      `json:"service"`
    Checks  map[string]HealthCheckResult `json:"checks"`
}

func CheckPostgres(db *sql.DB) HealthCheckResult {
    start := time.Now()
    err := db.Ping()
    latency := float64(time.Since(start).Milliseconds())

    if err != nil {
        return HealthCheckResult{
            Component: "postgres",
            Status:    StatusUnhealthy,
            Message:   fmt.Sprintf("PostgreSQL ping failed: %v", err),
            LatencyMs: latency,
        }
    }

    return HealthCheckResult{
        Component: "postgres",
        Status:    StatusHealthy,
        Message:   "PostgreSQL connected successfully",
        LatencyMs: latency,
    }
}

// Add similar functions for Qdrant, Ollama, etc.
```

Add health endpoints to `mcp-gateway/cmd/server/router.go`:

```go
import "ai-infra-workspace/mcp-gateway/internal/health"

// Basic health check
router.Get("/health", func(c echo.Context) error {
    return c.JSON(http.StatusOK, map[string]string{
        "status":  "healthy",
        "service": "mcp-gateway",
    })
})

// Deep health check
router.Get("/health/deep", func(c echo.Context) error {
    results := make(map[string]health.HealthCheckResult)

    // Check PostgreSQL
    results["postgres"] = health.CheckPostgres(db)

    // Add other checks...

    // Determine overall status
    overallStatus := health.StatusHealthy
    for _, result := range results {
        if result.Status == health.StatusUnhealthy {
            overallStatus = health.StatusUnhealthy
            break
        }
    }

    response := health.HealthResponse{
        Status:  string(overallStatus),
        Service: "mcp-gateway",
        Checks:  results,
    }

    if overallStatus == health.StatusHealthy {
        return c.JSON(http.StatusOK, response)
    }
    return c.JSON(http.StatusServiceUnavailable, response)
})
```

## Usage Examples

### Manual Testing

```bash
# Test basic health
curl http://localhost:8000/health

# Test deep health
curl http://localhost:8000/health/deep
```

### Example Response (Deep Health)

```json
{
  "status": "healthy",
  "service": "rag-api",
  "checks": {
    "postgres": {
      "status": "healthy",
      "message": "PostgreSQL connected successfully",
      "latency_ms": 12.5,
      "details": {
        "version": "PostgreSQL 16.3 on x86_64-pc-linux-gnu..."
      }
    },
    "qdrant": {
      "status": "healthy",
      "message": "Qdrant connected successfully",
      "latency_ms": 8.3,
      "details": {
        "version": "Qdrant"
      }
    },
    "ollama": {
      "status": "healthy",
      "message": "Ollama connected, 3 models available",
      "latency_ms": 15.2,
      "details": {
        "model_count": 3,
        "models": ["phi3:mini", "mistral", "nomic-embed-text"]
      }
    },
    "embedding_model": {
      "status": "unknown",
      "message": "Embedding model check not implemented",
      "latency_ms": 0.1
    }
  }
}
```

## Docker Compose Health Checks

Update docker-compose.yml to use deep health checks:

```yaml
rag-api:
  # ... existing config ...
  healthcheck:
    test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/deep', timeout=10)"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 60s
```

## Monitoring Integration

### Prometheus

The deep health check results can be exposed as metrics:

```python
from prometheus_client import Gauge, Info

health_status_gauge = Gauge('health_component_status', 'Health status of components', ['component'])
health_latency_gauge = Gauge('health_component_latency_ms', 'Health check latency in ms', ['component'])

@app.get("/health/deep")
async def health_deep():
    checker = HealthChecker()
    results = await checker.check_all()

    # Update Prometheus metrics
    for component, result in results.items():
        health_status_gauge.labels(component=component).set(
            1 if result.status == HealthStatus.HEALTHY else 0
        )
        health_latency_gauge.labels(component=component).set(result.latency_ms)

    # ... rest of implementation
```

### Grafana

Create a dashboard panel showing:
- Overall health status (color-coded)
- Component health status (table)
- Health check latency over time (graph)
- Alert when any component is unhealthy

## Best Practices

1. **Use deep health checks for readiness probes** - Not just liveness
2. **Set appropriate timeouts** - Don't let health checks hang
3. **Cache expensive checks** - Model loading checks shouldn't run every request
4. **Monitor health check latency** - Slow health checks indicate issues
5. **Alert on unhealthy status** - Set up alerts for 503 responses
6. **Document health check behavior** - Explain what each check verifies

## Troubleshooting

### Health check times out

- Increase timeout in health check configuration
- Check if dependency is actually reachable
- Verify network connectivity

### Component always unhealthy

- Check environment variables (DB_HOST, QDRANT_URL, etc.)
- Verify credentials are correct
- Check dependency service logs

### Health check too slow

- Reduce check complexity
- Cache results where appropriate
- Use connection pooling for database checks

## Advanced Customization

### Custom Component Checks

Extend `HealthChecker` for service-specific checks:

```python
class CustomHealthChecker(HealthChecker):
    async def check_custom_component(self) -> HealthCheckResult:
        """Custom health check for service-specific component"""
        start_time = time.time()
        try:
            # Your custom check logic here
            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="custom_component",
                status=HealthStatus.HEALTHY,
                message="Custom component healthy",
                latency_ms=latency_ms
            )
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="custom_component",
                status=HealthStatus.UNHEALTHY,
                message=f"Custom component failed: {str(e)}",
                latency_ms=latency_ms
            )
```

### Conditional Health Checks

Skip certain checks based on configuration:

```python
async def check_all(self) -> Dict[str, HealthCheckResult]:
    results = {}

    # Only check Ollama if enabled
    if os.getenv("OLLAMA_ENABLED", "false").lower() == "true":
        results["ollama"] = await self.check_ollama()

    # Always check critical dependencies
    results["postgres"] = await self.check_postgres()
    results["qdrant"] = await self.check_qdrant()

    return results
```
