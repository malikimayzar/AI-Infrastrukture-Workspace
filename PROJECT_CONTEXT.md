# PROJECT CONTEXT — AI Infrastructure Platform
> **Workspace:** `ai-infra-workspace`  
> **Runtime Snapshot:** 2026-10-20  
> **Target Product:** Scientific Claim & Prior-Art Auditor Platform  

---

## 1. RINGKASAN RUNTIME EKOSISTEM

Workspace ini mengorkestrasi 4 repositori inti menggunakan topologi kanonik Docker Compose di root ([`docker-compose.yml`](docker-compose.yml)):

```text
mcp-gateway :8090 ─┬─ ARXIV_SERVICE_URL → arxiv-go-backend :8080
                   │                        └─ ML_SERVICE_URL → arxiv-python-ml :8001
                   ├─ EVAL_SERVICE_URL  → llm-eval-framework :8002 (Ollama / offline)
                   └─ RAG_SERVICE_URL   → rag-api :8000
semua service     → qdrant :6333 / ollama :11435 / postgres :5432
```

* **Model Orkestrator & Generasi Utama:** Groq `openai/gpt-oss-20b` (seragam di semua titik lewat `.env` root).
* **Model LLM Lokal (Opsional/Demo):** Ollama `phi3:mini` (port container `11434` dipetakan ke host `11435` untuk menghindari bentrok dengan daemon host).
* **Model Embedding Baku:** `sentence-transformers/all-MiniLM-L6-v2` (vektor 384 dimensi, cache di-mount read-only dengan `HF_HUB_OFFLINE=1`).

---

## 2. STATUS INTEGRASI SAAT INI

1. **Jalur Eksekusi Kanonik (Mode A — Root Compose):**
   * Perintah `make up` menyalakan 8 kontainer inti (`ws-*`).
   * Perintah `make smoke-e2e` menguji end-to-end: *ingest 1 paper arXiv $\rightarrow$ query via gateway backend arxiv $\rightarrow$ query via gateway backend research_rag $\rightarrow$ validasi baris di PostgreSQL*.
2. **Monitoring (Opt-In):**
   * Profil `monitoring` (`make monitoring-up`) menyalakan Prometheus `:9090`, Grafana `:3000` (admin/admin), dan Redis `:6379`.
3. **Pengelolaan Rahasia:**
   * Diatur via `scripts/rotate_key.sh` dan `scripts/check_secrets.sh`. File `.env` berada di root dan di-gitignored.

---

## 3. STATUS PENGUJIAN KODE (TEST SUITE STATUS)

* **`arxiv-research-assistant/go-backend`:** 100% PASS (`go test ./...`).
* **`mcp-gateway`:** 100% PASS (`go test ./...` dengan `-race` detection).
* **`llm-eval-framework`:** 100% PASS (199 test unit lulus dalam ~5 detik).
* **`arxiv-research-assistant/python-ml`:** 100% PASS (19 test unit lulus jika dijalankan dengan `PYTHONPATH`).
* **`rag-research`:** 411 PASS, 8 FAILED, 1 SKIPPED (per 2026-10-20; seluruh kegagalan berakar pada dependensi opsional `ragas` yang belum terpasang — 6× `test_ragas_importable.py`, `test_ci_contracts.py::test_every_src_module_imports`, dan `test_scripts_load_env.py::test_run_eval_works_standalone`). **Query leakage: PASS** (`test_query_leakage.py`, 18 test lulus) — 4 pertanyaan dataset v2 yang sebelumnya bocor sudah di bawah ambang cosine 0.90.
* **`test_qdrant_store.py`:** offline-safe setelah `QdrantVectorStore` menerima `embedder`/`client` injeksi — **~27,4 s → ~1,2 s**, lolos dengan `HF_HUB_OFFLINE=1`.

---

## 4. RUJUKAN DOKUMENTASI TERKAIT

* Spesifikasi dan Tujuan Lengkap: [`PROJECT_GOALS.md`](PROJECT_GOALS.md)
* Riwayat Insiden & Solusi Operasional: [`docs/ops-postmortem.md`](docs/ops-postmortem.md)
* Panduan Operasional Cepat: [`README.md`](README.md)
* Kontrak Submodul:
  * [`mcp-gateway/PROJECT_GOALS.md`](mcp-gateway/PROJECT_GOALS.md)
  * [`rag-research/PROJECT_GOALS.md`](rag-research/PROJECT_GOALS.md)
