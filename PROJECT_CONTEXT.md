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
   * Compose mendefinisikan 8 layanan inti; tiga layanan monitoring/Redis aktif melalui profile `monitoring`.
   * Gateway memiliki adapter source-level untuk backend `arxiv` dan `research_rag`. Laporan smoke 2026-10-20 mencatat ingest dan query keduanya, tetapi smoke bukan evaluasi mutu jawaban atau gate kesiapan produksi.
   * Pemeriksaan query log smoke mencari teks query tetap; baris dari run lama dapat ikut terhitung. Jangan gunakan hasil tersebut sebagai bukti bahwa run terbaru menulis log tanpa verifikasi tambahan.
2. **Monitoring (Opt-In):**
   * Profil `monitoring` (`make monitoring-up`) menyalakan Prometheus `:9090`, Grafana `:3000` (admin/admin), dan Redis `:6379`.
   * Prometheus men-scrape lima job: go-backend, python-ml, mcp-gateway, llm-eval-framework, dan rag-api.
   * Redis untuk cache RAG bersifat opt-in (`REDIS_ENABLED=false` default) karena Redis hanya hidup di profil monitoring.
3. **Pengelolaan Rahasia:**
   * Diatur via `scripts/rotate_key.sh` dan `scripts/check_secrets.sh`. File `.env` berada di root dan di-gitignored.
   * Compose masih memiliki nilai fallback untuk kredensial layanan dan Grafana. Perlakukan sebagai konfigurasi pengembangan lokal; ganti sebelum mengekspos layanan ke jaringan bersama.

---

## 3. SNAPSHOT TEST YANG TERCATAT

Angka di bawah adalah catatan dari dokumen dan tanggal yang disebutkan, bukan hasil
test yang dijalankan saat snapshot konteks ini dibaca. Jalankan gate yang sesuai
sebelum memakai angka tersebut sebagai bukti rilis.

* **`arxiv-research-assistant/go-backend`:** 100% PASS (`go test ./...`).
* **`mcp-gateway`:** 100% PASS (`go test ./...` dengan `-race` detection).
* **`llm-eval-framework`:** 100% PASS (208 test unit lulus dalam ~5 detik).
* **`arxiv-research-assistant/python-ml`:** 100% PASS (19 test unit lulus jika dijalankan dengan `PYTHONPATH`).
* **`rag-research`:** 419 PASS, 1 SKIPPED, 0 FAILED (per 2026-10-22; `ragas` sudah terpasang di venv root). **Query leakage: PASS** (`test_query_leakage.py`, 18 test lulus) — 4 pertanyaan dataset v2 yang sebelumnya bocor sudah di bawah ambang cosine 0.90.
* **`test_qdrant_store.py`:** offline-safe setelah `QdrantVectorStore` menerima `embedder`/`client` injeksi — **~27,4 s → ~1,2 s**, lolos dengan `HF_HUB_OFFLINE=1`.

---

## 4. RUJUKAN DOKUMENTASI TERKAIT

* Spesifikasi dan Tujuan Lengkap: [`PROJECT_GOALS.md`](PROJECT_GOALS.md)
* Riwayat Insiden & Solusi Operasional: [`docs/ops-postmortem.md`](docs/ops-postmortem.md)
* Panduan Operasional Cepat: [`README.md`](README.md)
* Kontrak Submodul:
  * [`mcp-gateway/PROJECT_GOALS.md`](mcp-gateway/PROJECT_GOALS.md)
  * [`rag-research/PROJECT_GOALS.md`](rag-research/PROJECT_GOALS.md)
