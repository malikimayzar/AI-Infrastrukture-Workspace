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
  - Ollama is unreachable from the evaluator container, or the `nomic-embed-text` embedding model is unavailable. The HTTP evaluator uses embeddings; generation models are used by the offline pipeline.
* **Resolution Steps:**
  1. In the workspace Compose deployment, check the Ollama service from the evaluator network (`http://ollama:11434`); host `localhost` is not the container address.
  2. Check that the configured Ollama server is healthy and can list models.
  3. Pull `nomic-embed-text` into the Ollama instance used by the evaluator. Pull `mistral` or `phi3:mini` only when running the offline generation pipeline.

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
1. The gateway reports `evaluation_status: "unavailable"` and may record a sanitized operational error.
2. Keep the backend's valid answer and evidence; evaluator failure does not change the answer decision.
3. Do not return or persist a fabricated score such as `0.0`. A zero is valid only when the evaluator completed successfully and actually returned zero.
