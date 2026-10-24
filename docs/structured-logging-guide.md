# Structured JSON Logging Guide

## Overview

This workspace provides unified structured logging utilities for both Python and Go services. All logs are output as JSON with consistent fields for easy parsing and analysis.

## Python Logging Utility

Location: `scripts/logging_utils.py`

### Basic Usage

```python
from logging_utils import get_logger, log_info, log_error, log_duration

# Initialize logger
logger = get_logger("rag-api", level=logging.INFO)

# Simple log
logger.info("Service started")

# Log with context
log_info(logger, "Processing query", request_id="req-123", query="test", top_k=5)

# Log with duration context manager
with log_duration(logger, "query_processing", query_id="req-123", backend="research_rag"):
    # Do work here
    result = process_query()
```

### Log Fields

All JSON logs include:
- `timestamp`: ISO 8601 timestamp (UTC)
- `level`: DEBUG, INFO, WARNING, ERROR
- `service`: Service name (e.g., "rag-api")
- `message`: Log message
- `request_id`: Request ID for tracing (optional)
- `duration_ms`: Operation duration in milliseconds (optional)
- `backend`: Backend name (optional)
- `error`: Error message (optional)
- `extra`: Additional custom fields (optional)

### Example Output

```json
{
  "timestamp": "2026-10-24T10:30:45.123Z",
  "level": "INFO",
  "service": "rag-api",
  "message": "Processing query",
  "request_id": "req-123",
  "extra": {
    "query": "What is attention?",
    "top_k": 5
  }
}
```

### Integration Example

Replace existing print statements:

```python
# Before
print(f"Processing query: {query}")

# After
from logging_utils import get_logger
logger = get_logger("rag-api")
logger.info("Processing query", extra={"query": query})
```

## Go Logging Utility

Location: `scripts/logging_utils.go`

### Basic Usage

```go
import "ai-infra-workspace/scripts/logging"

// Initialize logger
logger := logging.NewLogger("mcp-gateway", logging.INFO)

// Simple log
logger.Info("Service started", nil)

// Log with fields
logger.Info("Processing request", logging.Fields{
    "request_id": "req-123",
    "backend": "research_rag",
})

// Fluent API
logger.WithFields(logging.Fields{
    "request_id": "req-123",
}).WithBackend("research_rag").Info("Processing request")

// Duration tracking
dur := logger.StartDuration("query_processing", logging.Fields{
    "request_id": "req-123",
})
// Do work
dur.End("Query processing completed")
```

### Integration Example

Replace existing log statements:

```go
// Before
log.Printf("Processing request: %s", requestID)

// After
logger := logging.NewLogger("mcp-gateway", logging.INFO)
logger.Info("Processing request", logging.Fields{
    "request_id": requestID,
})
```

## Service-Specific Integration

### mcp-gateway (Go)

Add to `cmd/server/main.go`:

```go
import "ai-infra-workspace/scripts/logging"

var logger = logging.NewLogger("mcp-gateway", logging.INFO)

func main() {
    logger.Info("Starting mcp-gateway", nil)
    // ... rest of main
}
```

### rag-api (Python)

Add to `src/api/main.py` or `src/api/config.py`:

```python
import sys
sys.path.insert(0, '/home/malikimayzar/projects/ai-infra-workspace/scripts')
from logging_utils import get_logger

logger = get_logger("rag-api")
```

### arxiv-python-ml (Python)

Add to `main.py`:

```python
import sys
sys.path.insert(0, '/home/malikimayzar/projects/ai-infra-workspace/scripts')
from logging_utils import get_logger

logger = get_logger("arxiv-python-ml")
```

## Log Analysis

### Query with jq

```bash
# Get all INFO logs
docker logs ws-rag-api 2>&1 | jq 'select(.level == "INFO")'

# Get logs for specific request_id
docker logs ws-rag-api 2>&1 | jq 'select(.request_id == "req-123")'

# Get average duration for an operation
docker logs ws-rag-api 2>&1 | jq -s 'map(select(.duration_ms != null) | .duration_ms) | add / length'
```

### Query with grep

```bash
# Simple filter
docker logs ws-rag-api 2>&1 | grep "ERROR"

# Extract request IDs
docker logs ws-rag-api 2>&1 | grep -o '"request_id":"[^"]*"'
```

## Migration Checklist

For each service:

- [ ] Import logging utility
- [ ] Initialize logger with service name
- [ ] Replace print statements with logger calls
- [ ] Add request_id to logs where available
- [ ] Add duration tracking for key operations
- [ ] Test log output format
- [ ] Update documentation

## Best Practices

1. **Always include request_id** in logs for request-scoped operations
2. **Use duration tracking** for operations that may be slow
3. **Log at appropriate levels**:
   - DEBUG: Detailed diagnostic information
   - INFO: Normal operational events
   - WARNING: Unexpected but non-critical events
   - ERROR: Critical failures
4. **Include context** in logs (query parameters, backend names, etc.)
5. **Don't log sensitive data** (API keys, passwords, PII)
6. **Use structured fields** instead of string concatenation

## Troubleshooting

### Logs not appearing

- Check logger level (set to DEBUG for all logs)
- Verify output destination (stdout vs stderr)
- Check if handlers are duplicated (causes duplicate logs)

### JSON parsing errors

- Ensure log messages don't contain unescaped quotes
- Verify extra fields are JSON-serializable
- Check for exception info in logs

### Performance impact

- JSON logging has minimal overhead (< 1ms per log)
- Use DEBUG level sparingly in production
- Consider async logging for high-volume services
