# Operational Runbook: Evaluation Service Incidents & Troubleshooting

> **Scope:** `llm-eval-framework` & FastAPI Evaluation API (`api.py`)  
> **Audience:** DevOps, ML Engineers, On-Call Operators  

---

## 1. Common Incident Scenarios

### Scenario A: Ollama Service Timeout or Connection Refused
* **Symptoms:** 
  - Evaluation pipeline hangs or throws `requests.exceptions.ConnectionError`.
  - FastAPI `/evaluate` endpoint returns `503 Service Unavailable`.
* **Root Cause:** 
  - Ollama local daemon is not running or model (`mistral` / `nomic-embed-text`) is not loaded in memory.
* **Resolution Steps:**
  1. Check Ollama status: `ollama list` or `curl http://localhost:11434/api/tags`.
  2. Start Ollama daemon if stopped: `ollama serve &`.
  3. Pull required models if missing: `ollama pull mistral` and `ollama pull nomic-embed-text`.

### Scenario B: FastAPI `/evaluate` Returns Validation Error (`422 Unprocessable Entity`)
* **Symptoms:** 
  - Downstream services (`mcp-gateway`) receive 422 errors when invoking evaluation.
* **Root Cause:** 
  - Malformed JSON payload missing required keys (`question`, `answer`, `context`).
* **Resolution Steps:**
  1. Verify the request payload matches the canonical contract:
     ```json
     {
       "question": "string",
       "answer": "string",
       "context": "string"
     }
     ```
  2. Inspect FastAPI logs or run unit tests: `pytest llm-eval-framework/tests/test_api.py`.

### Scenario C: Provenance Drift Error (`make verify` fails)
* **Symptoms:** 
  - CI pipeline or `make verify` fails with a drift warning.
* **Root Cause:** 
  - `config.yaml` was modified after evaluation artifacts were generated, or git repository is dirty.
* **Resolution Steps:**
  1. Re-run evaluation pipeline: `make eval`.
  2. Regenerate reports: `make report`.
  3. Commit updated artifacts and summary JSONs.

---

## 2. Graceful Degradation & Fallback Strategy

When integrated with `mcp-gateway`, if the evaluation service (`api.py`) encounters an error or timeout:
1. The gateway must catch the exception and log a warning.
2. The gateway must return a graceful diagnostic fallback payload (`"faithfulness_score": 0.0`, `"has_failure": true`, `"failure_mode": "evaluator_unavailable"`).
3. **Never** crash the user request or fabricate a false positive score.
