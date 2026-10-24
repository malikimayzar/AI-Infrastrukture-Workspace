# PROJECT CONTEXT — AI Infrastructure Platform
> **Workspace:** `ai-infra-workspace`
> **Runtime Snapshot:** 2026-10-22
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

* **Model generasi backend:** Groq `openai/gpt-oss-20b` untuk layanan `python-ml` dan `rag-api` (dikonfigurasi melalui `.env` root). `mcp-gateway` memakai rencana backend deterministik dan tidak memanggil Groq untuk memilih tool.
* **Model LLM Lokal (Opsional/Demo):** Ollama `phi3:mini` (port container `11434` dipetakan ke host `11435` untuk menghindari bentrok dengan daemon host).
* **Model Embedding Baku:** `sentence-transformers/all-MiniLM-L6-v2` (vektor 384 dimensi, cache di-mount read-only dengan `HF_HUB_OFFLINE=1`).

---

## 2. STATUS INTEGRASI DAN BATAS BUKTI

1. **Jalur eksekusi integrasi yang disarankan (root Compose):**
   * Compose mendefinisikan 8 layanan inti; tiga layanan monitoring/Redis aktif melalui profile `monitoring`. Gate operasional Fase 2 terverifikasi pada 2026-10-24 — lihat `docs/acceptance/phase-2-verification.md`.
   * Gateway memiliki adapter source-level untuk backend `arxiv` dan `research_rag`. Smoke 2026-10-24 mencatat ingest dan query keduanya dengan kontrak RAG `decision=answer`/`evaluation_status=completed`; ini bukan evaluasi mutu jawaban atau gate kesiapan produksi.
   * Smoke memakai `RUN_ID` unik, header `X-Request-ID`, dan query unik; verifikasi mengikat baris baru di `gateway_query_logs` (per request ID) dan `query_logs` (per query), sehingga baris dari run lama tidak dapat lolos.
2. **Monitoring (Opt-In):**
   * Profil `monitoring` (`make monitoring-up`) menyalakan Prometheus `:9090`, Grafana `:3000` (admin/admin), dan Redis `:6379`.
   * Prometheus men-scrape lima job: go-backend, python-ml, mcp-gateway, llm-eval-framework, dan rag-api. `make verify-monitoring` membuktikan 5/5 target `up`, `sum(up)=5`, series p95 tersedia, dan dashboard 5 panel (2026-10-24).
   * Redis untuk cache RAG bersifat opt-in (`REDIS_ENABLED=false` default) karena Redis hanya hidup di profil monitoring. Jalur cache sudah diverifikasi runtime (`cache_hit=false → true`, TTL 600 s) dan diaktifkan dengan `make cache-up`/`make verify-redis`.
3. **Pengelolaan Rahasia:**
   * Diatur via `scripts/rotate_key.sh` dan `scripts/check_secrets.sh`. File `.env` berada di root dan di-gitignored.
   * Compose masih memiliki nilai fallback untuk kredensial layanan dan Grafana. Perlakukan sebagai konfigurasi pengembangan lokal; ganti sebelum mengekspos layanan ke jaringan bersama.

---

## 3. SNAPSHOT TEST YANG TERCATAT

Angka di bawah adalah catatan dari dokumen dan tanggal yang disebutkan, bukan hasil
test yang dijalankan saat snapshot konteks ini dibaca. Jalankan gate yang sesuai
sebelum memakai angka tersebut sebagai bukti rilis.

* **`arxiv-research-assistant/go-backend`:** 100% PASS (15 test, 2026-10-24).
* **`mcp-gateway`:** 100% PASS (143 test dengan `-race`, 2026-10-24).
* **`llm-eval-framework`:** 100% PASS (226 test unit, 2026-10-24).
* **`arxiv-research-assistant/python-ml`:** 100% PASS (45 test unit dengan `PYTHONPATH`, 2026-10-24).
* **`rag-research`:** 469 PASS, 0 SKIPPED, 0 FAILED (2026-10-24; `ragas` terpasang di venv root). **Query leakage: PASS** (`test_query_leakage.py`, 18 test lulus) — 4 pertanyaan dataset v2 yang sebelumnya bocor sudah di bawah ambang cosine 0.90.
* **`test_qdrant_store.py`:** offline-safe setelah `QdrantVectorStore` menerima `embedder`/`client` injeksi — **~27,4 s → ~1,2 s**, lolos dengan `HF_HUB_OFFLINE=1`.

---

## 4. RUJUKAN DOKUMENTASI TERKAIT

* Spesifikasi dan Tujuan Lengkap: [`PROJECT_GOALS.md`](PROJECT_GOALS.md)
* Riwayat Insiden & Solusi Operasional: [`docs/ops-postmortem.md`](docs/ops-postmortem.md)
* Panduan Operasional Cepat: [`README.md`](README.md)
* Kontrak Submodul:
  * [`mcp-gateway/PROJECT_GOALS.md`](mcp-gateway/PROJECT_GOALS.md)
  * [`rag-research/PROJECT_GOALS.md`](rag-research/PROJECT_GOALS.md)
