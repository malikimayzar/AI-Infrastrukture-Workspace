# PROJECT CONTEXT — AI Infrastructure Platform
> **Workspace:** `ai-infra-workspace`
> **Runtime Snapshot:** 2026-10-26
> **Target Product:** Scientific Claim & Prior-Art Auditor Platform

---

## 1. TOPOLOGI WORKSPACE (KONFIGURASI)

Workspace ini mengorkestrasi 4 repositori inti menggunakan topologi kanonik Docker Compose di root ([`docker-compose.yml`](docker-compose.yml)):

```text
mcp-gateway :8090 ─┬─ ARXIV_SERVICE_URL → arxiv-go-backend :8080
                   │                        └─ ML_SERVICE_URL → arxiv-python-ml :8001
                   ├─ EVAL_SERVICE_URL  → llm-eval-framework :8002 (Ollama / offline)
                   └─ RAG_SERVICE_URL   → rag-api :8000
semua service     → qdrant :6333 / ollama :11434 (internal) / postgres :5432
host mengakses Ollama container melalui :11435
```

* **Model generasi backend:** Groq `openai/gpt-oss-20b` untuk layanan `python-ml` dan `rag-api`.
* **Model LLM Lokal (Opsional/Demo):** Ollama `phi3:mini` (port container `11434` dipetakan ke host `11435`).
* **Model Embedding Baku:** `sentence-transformers/all-MiniLM-L6-v2` (vektor 384 dimensi, cache di-mount read-only dengan `HF_HUB_OFFLINE=1`).

---

## 2. STATUS INTEGRASI

1. **Jalur eksekusi integrasi (root Compose):**
   * Compose mendefinisikan 8 layanan inti; 3 layanan monitoring/Redis aktif melalui profile `monitoring`.
   * Gateway memiliki adapter source-level untuk backend `arxiv` dan `research_rag`.
   * Smoke test memakai `RUN_ID` unik, header `X-Request-ID`, dan query unik.
2. **Monitoring (Opt-In):**
   * Profil `monitoring` (`make monitoring-up`) menyalakan Prometheus `:9090`, Grafana `:3000`, Redis `:6379`.
   * Prometheus men-scrape lima job. `make verify-monitoring` membuktikan 5/5 target `up`.
   * Redis untuk cache RAG bersifat opt-in (`REDIS_ENABLED=false` default).
3. **Pengelolaan Rahasia:**
   * Diatur via `scripts/rotate_key.sh` dan `scripts/check_secrets.sh`. File `.env` berada di root dan di-gitignored.
   * Compose masih memiliki nilai fallback untuk kredensial layanan (development only).

---

## 3. SNAPSHOT TEST YANG TERCATAT

* **`arxiv-research-assistant/go-backend`:** 15 test PASS (2026-10-24).
* **`mcp-gateway`:** 143 test PASS dengan `-race` (2026-10-24).
* **`llm-eval-framework`:** 226 test PASS (2026-10-24).
* **`arxiv-research-assistant/python-ml`:** 45 test PASS (2026-10-24).
* **`rag-research`:** 492 test PASS (2026-10-26).
* **E2E MCP smoke test:** 16/16 PASS (2026-10-26).

---

## 4. RUJUKAN DOKUMENTASI TERKAIT

* Spesifikasi dan Tujuan Lengkap: [`PROJECT_GOALS.md`](PROJECT_GOALS.md)
* Roadmap & Status: [`docs/ROADMAP.md`](docs/ROADMAP.md)
* Panduan Operasional: [`docs/OPERATIONS.md`](docs/OPERATIONS.md)
* Panduan MCP: [`docs/mcp-integration-guide.md`](docs/mcp-integration-guide.md)
* Kalibrasi Confidence: [`docs/confidence-calibration.md`](docs/confidence-calibration.md)
* Kontrak Submodul:
  * [`mcp-gateway/PROJECT_GOALS.md`](mcp-gateway/PROJECT_GOALS.md)
  * [`rag-research/PROJECT_GOALS.md`](rag-research/PROJECT_GOALS.md)
