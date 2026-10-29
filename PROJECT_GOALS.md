# AI INFRASTRUCTURE PLATFORM — ENGINEERING GOALS & PRODUCTION SPEC
> **Project Title:** Scientific Claim & Prior-Art Auditor (Autonomous Research Grounding & Audit Engine)
> **Workspace:** `ai-infra-workspace` (Orchestrating `arxiv-research-assistant`, `mcp-gateway`, `rag-research`, `llm-eval-framework`)
> **Version:** 1.0.0
> **Status:** Phase 1 acceptance pending. Phase 4 (Claim Audit UI) not started. See `docs/ROADMAP.md` for full roadmap. Confidence calibration ECE 0.0576. Span-level attribution implemented. Auth + rate limiting active. E2E MCP smoke test 16/16 PASS.
> **Last Updated:** 2026-10-26

---

## CORE PRINCIPLE

> **"If evidence is insufficient, refusing to answer is correct engineering. Grounded truth supersedes fluent speculation."**
> Kami tidak membangun chatbot percakapan umum (*commodity chat-with-PDF*). Kami membangun **mesin audit ilmiah deterministik** yang mengutamakan ketertelusuran bukti kalimat-per-kalimat (*span-level attribution*), penolakan halusinasi (*hard abstention*), dan evaluasi tanpa bias (*zero LLM-as-judge*).

---

## DAFTAR ISI

1. [System Objective & Product Vision](#1-system-objective--product-vision)
2. [Workspace Architecture & Repository Ownership](#2-workspace-architecture--repository-ownership)
3. [Kriteria Keberhasilan Terukur (Measurable Success Criteria)](#3-kriteria-keberhasilan-terukur-measurable-success-criteria)
4. [Kontrak Antar-Layanan (Cross-Service Wire Contracts)](#4-kontrak-antar-layanan-cross-service-wire-contracts)
5. [Registri Kegagalan Sistem (Failure Mode Registry)](#5-registri-kegagalan-sistem-failure-mode-registry)
6. [Spesifikasi Kalibrasi & Kebijakan Abstensi (Confidence & Abstention Spec)](#6-spesifikasi-kalibrasi--kebijakan-abstensi-confidence--abstention-spec)
7. [Alokasi Memori, Sumber Daya & Latensi (Resource & Latency Envelope)](#7-alokasi-memori-sumber-daya--latensi-resource--latency-envelope)
8. [Roadmap Integrasi Bertahap (Phase-Gated Roadmap)](#8-roadmap-integrasi-bertahap-phase-gated-roadmap)
9. [Daftar Periksa Kesiapan Produksi (Production Readiness Checklist)](#9-daftar-periksa-kesiapan-produksi-production-readiness-checklist)
10. [Batas Non-Tujuan (Non-Goals)](#10-batas-non-tujuan-non-goals)

---

## 1. System Objective & Product Vision

> **Status boundary:** This section describes the intended product, not the current
> release capability. The current gateway is HTTP/JSON; claim-level attribution,
> calibrated confidence, MCP interoperability, and production readiness require
> their own acceptance evidence below.

### 1.1 Visi Produk: *Scientific Claim & Prior-Art Auditor*
Sebuah platform perangkat lunak B2B berstandar *mission-critical* untuk tim R&D, konsultan paten, penerbit jurnal akademis, dan regulator kepatuhan yang:
1. **Memvalidasi Kebaruan & Orisinalitas (*Novelty Audit*):** Membandingkan draf klaim penemuan atau hipotesis terhadap korpus literatur ilmiah tanpa halusinasi sitasi.
2. **Audit Klaim Kalimat-per-Kalimat (*Span-Level Attribution*):** Membedah teks jawaban menjadi proposisi/klaim terisolasi dan memetakannya langsung ke nomor dokumen, ID chunk, dan baris teks sumber.
3. **Penyedia Alat MCP Terstandarisasi (*Model Context Protocol*):** Menyediakan antarmuka alat (*tools*) verifikasi bukti yang dapat langsung diakses oleh agen AI pihak ketiga (seperti Claude Desktop, Cursor, atau Devin) saat menulis naskah teknis.

```text
               KLIEN (Browser / IDE / Claude Desktop via MCP)
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│               mcp-gateway (:8090) — Orkestrator & Gerbang              │
│  - Verifikasi Request & Rate Limiter                                   │
│  - Perencana Langkah deterministik per backend                           │
│  - Penjejak Audit Tracing & Asynchronous Logging                       │
└───────┬───────────────────────────┬────────────────────────────┬───────┘
        │                           │                            │
        ▼                           ▼                            ▼
┌──────────────────┐       ┌──────────────────┐         ┌────────────────────┐
│ arxiv-assistant  │       │   rag-research   │         │ llm-eval-framework │
│ (Fiber :8080 &   │       │ (FastAPI :8000)  │         │ (FastAPI :8002)    │
│  FastAPI :8001)  │       │                  │         │                    │
│                  │       │ - Hybrid Search  │         │ - Faithfulness     │
│ - ArXiv Ingest   │       │   (Dense + BM25) │         │   (No LLM Judge)   │
│ - PDF Extraction │       │ - RRF Fusion     │         │ - Paraphrase       │
│ - Doc Metadata   │       │ - Cross-Encoder  │         │   Consistency      │
│ - Audit History  │       │ - Hard Abstain   │         │ - Perturbation     │
└────────┬─────────┘       └────────┬─────────┘         │   Sensitivity      │
         │                          │                   └─────────┬──────────┘
         └──────────────────────────┼─────────────────────────────┘
                                    ▼
                SHARED INFRASTRUCTURE (Docker Compose KANONIK)
    PostgreSQL :5432  │  Qdrant :6333  │  Ollama :11435  │  Redis :6379
                 Prometheus :9090  │  Grafana :3000
```

---

## 2. Workspace Architecture & Repository Ownership

Untuk menjaga kebersihan arsitektur, kepemilikan tanggung jawab (*ownership boundaries*) dibagi secara ketat:

| Repositori | Bahasa & Framework | Port | Tanggung Jawab Utama | Apa yang TIDAK Boleh Dimiliki |
|---|---|---|---|---|
| [`mcp-gateway`](mcp-gateway/) | Go 1.22 + Chi | `8090` | Routing publik, validasi parameter, orkestrasi adapter, eksekusi plan, penulisan log audit ke `gateway_query_logs`. | Tidak boleh melakukan parsing dokumen mentah, indexing vektor, atau menjalankan evaluasi secara internal. |
| [`arxiv-research-assistant`](arxiv-research-assistant/) | Go (Fiber) + Python (FastAPI) | `8080`, `8001` | Ingestion PDF arXiv resmi, pemecahan chunk deterministik, integrasi paper metadata PostgreSQL, serving rute query arXiv spesifik. | Tidak boleh mengatur routing lintas repositori atau memaksakan evaluasi di luar domain paper-nya. |
| [`rag-research`](rag-research/) | Python 3.12 (FastAPI) + Rust Chunker | `8000` | Mesin *Hybrid Retrieval* ilmiah, *Reciprocal Rank Fusion* (RRF), *Cross-Encoder reranking*, kalibrasi *ConfidenceEngine*, *hard abstention*. | Tidak boleh memanggil servis repositori lain untuk menyelesaikan siklus retrival intinya. |
| [`llm-eval-framework`](llm-eval-framework/) | Python 3.11 (FastAPI) + Ollama Embeddings | `8002` | Evaluasi kesetiaan (*faithfulness*), konsistensi semantik, dependensi konteks, dan analisis ketahanan terhadap gangguan tanpa ketergantungan LLM-as-judge. | Tidak boleh bertindak sebagai oracle kebenaran absolut tanpa bukti konteks yang diserahkan. |
| **Root Workspace** | Docker Compose + Make + Bash | — | Orkestrasi kontainer bersama (`ws-*`), rotasi kredensial aman, *smoke testing* end-to-end, monitoring Prometheus/Grafana. | Tidak boleh memuat kode logika aplikasi khusus yang berada di luar skrip utilitas orkestrasi. |

---

## 3. Kriteria Keberhasilan Terukur (Measurable Success Criteria)

### 3.1 Kualitas Jawaban & Kepercayaan Bukti (*Answer Quality & Grounding*)

| Metrik | Target Produksi | Protokol Pengukuran | Status Saat Ini |
|---|---|---|---|
| **Faithfulness** | Target awal $\ge 0.90$; belum menjadi gate rilis | Skor heuristik dukungan klaim terhadap konteks, bukan ukuran kebenaran faktual atau confidence terkalibrasi. | Diimplementasikan; validitas lintas-domain dan kalibrasinya belum dibuktikan |
| **Hallucination rate** | Target jangka panjang 0%; belum terbukti | Ukur klaim salah/tidak didukung pada dataset berlabel dan hasil review manusia. | Bukti statistik belum cukup untuk mengklaim 0% |
| **Abstention accuracy** | Target awal $\ge 95\%$; belum menjadi gate rilis | Ukur keputusan abstain dan false-abstain pada set answerable/unanswerable terpisah. | Heuristik ada; confidence belum terkalibrasi |
| **Citation attribution** | Target jangka panjang 100%; belum terbukti | Ukur apakah klaim/kalimat jawaban memiliki rujukan sumber dan chunk yang tepat. | Gateway membawa evidence per chunk; atribusi klaim per kalimat belum dijamin |
| **Consistency / paraphrase** | Target awal $\ge 0.85$; perlu hasil evaluasi bertanggal | Bandingkan jawaban parafrasa pada dataset dan model dengan versi tercatat. | Evaluator tersedia; jumlah unit test bukan hasil kualitas |

### 3.2 Kualitas Retrieval (*Retrieval Quality*)

| Metrik | Target Produksi | Protokol Pengukuran |
|---|---|---|
| **Recall@10** | $\ge 90\%$ | Persentase query di mana *gold chunk* muncul dalam 10 kandidat teratas. |
| **MRR@10** | $\ge 0.70$ | *Mean Reciprocal Rank* pada 10 kandidat teratas di seluruh dataset evaluasi. |
| **RRF Contribution** | Ukur per dataset; belum menjadi gate numerik | Laporkan kontribusi dan kasus dense-only/BM25-only. Sampel saat ini belum cukup untuk menetapkan rentang universal 30–70%. |
| **Leakage Tolerance** | $0$ Baris Bocor | Cosine similarity query terhadap gold chunk tidak boleh $\ge 0.90$ (mencegah *data contamination*). |

---

## 4. Kontrak Antar-Layanan (Cross-Service Wire Contracts)

### 4.1 Permintaan Jawaban ke Gateway (`POST /ask`)
```json
{
  "backend": "research_rag",
  "query": "Bagaimana mekanisme multi-head attention mengurangi bias representasi spasial?",
  "top_k": 5
}
```

### 4.2 Respons Kanonik Gateway (Kontrak Publik API)
```json
{
  "request_id": "req-98765432-1111-2222-3333",
  "backend": "research_rag",
  "decision": "answer",
  "failure_type": "none",
  "answer": "Multi-head attention memproyeksikan query, key, dan value ke beberapa sub-ruang representasi linear secara paralel...",
  "evidence": [
    {
      "chunk_id": "doc_transformer_s0014",
      "source_id": "arxiv:1706.03762",
      "text": "Multi-head attention allows the model to jointly attend to information from different representation subspaces...",
      "score": 0.8845
    }
  ],
  "model": "openai/gpt-oss-20b",
  "evaluation_status": "completed",
  "evaluation": {
    "faithfulness_score": 0.94,
    "failure_mode": "none",
    "supported_claims": 3,
    "total_claims": 3
  },
  "latency_ms": {
    "retrieval": 64.2,
    "generation": 1420.5,
    "total": 1510.8
  }
}
```

### 4.3 Kasus Abstensi Bukti Kurang (*Hard Abstention*)
Ketika skor kepercayaan retrieval di bawah ambang batas:
```json
{
  "request_id": "req-98765432-1111-2222-4444",
  "backend": "research_rag",
  "decision": "abstain",
  "failure_type": "insufficient_context",
  "answer": "INSUFFICIENT_CONTEXT",
  "evidence": [],
  "evaluation_status": "skipped",
  "evaluation": null
}
```

---

## 5. Registri Kegagalan Sistem (Failure Mode Registry)

Setiap kegagalan harus diklasifikasikan secara deterministik ke dalam kode berikut (tidak boleh melempar generic 500 tanpa diagnosis):

| Kode Kegagalan | Kategori | Kondisi Pemicu | Aksi Sistem |
|---|---|---|---|
| `F-01: NO_RETRIEVAL_MATCH` | Data | Skor Dense & BM25 di bawah batas minimum threshold $\le 0.0$. | Abstain seketika; lewati LLM generator; evaluasi di-skip. |
| `F-02: UNGROUNDED_CLAIM` | Kualitas | LLM menghasilkan klaim yang kesamaan kosinusnya $< 0.82$ terhadap bukti konteks. | Tandai `failure_mode: unsupported_claims`, skor faithfulness jatuh. |
| `F-03: SENSITIVITY_DRIFT` | Ketahanan | Perubahan kecil tanda baca atau parafrasa membalikkan kesimpulan jawaban. | Flag pada log audit PostgreSQL untuk analisis drift prompt. |
| `F-04: PROVIDER_TIMEOUT` | Infrastruktur | Groq API atau Ollama lokal tidak membalas dalam batas timeout (30-60s). | Failover/Circuit Breaker terbuka; kirim status 502 terkontrol. |
| `F-05: REPAIR_COMPENSATION` | Database | Qdrant gagal upsert setelah PostgreSQL berhasil menyimpan metadata paper. | Transaksi kompensasi rollback otomatis pada PostgreSQL (`test_ingest_compensation.py`). |
| `F-06: MEMORY_OOM` | Sumber Daya | Beban pemuatan model lokal melebihi batas RAM host 15 GB. | Gunakan Groq cloud sebagai default rute; isolasi keep_alive Ollama. |
| `F-07: EMBEDDED_DNS_CORRUPTION` | Jaringan | Resolv.conf container berpindah ke bentuk eksternal (quirk rootless docker). | Eksekusi force-recreate otomatis terisolasi tanpa merestart stack infra. |

---

## 6. Spesifikasi Kalibrasi & Kebijakan Abstensi (Confidence & Abstention Spec)

Gateway dan Engine RAG menetapkan 3 zona keyakinan:

```text
 Skor Relevansi Bukti (Normalisasi RRF + Cross-Encoder)
 0.00                    0.35                    0.65                    1.00
  ├─── HARD REJECT ───────┼─── PARTIAL TRUST ─────┼────── FULL GENERATE ──┤
  │    (Abstensi Murni)   │    (Maksimal 3 Chunks │      (Rute Jawaban    │
  │    Lewati Generator   │     Peringatan Rendah)│       Normal Lengkap) │
```

1. **Zona Merah ($< 0.35$):** Menolak secara keras (*Hard Abstain*). Tidak memanggil LLM untuk menghemat kuota token dan menjamin nol halusinasi.
2. **Zona Kuning ($0.35 - 0.65$):** Membatasi generator hanya pada 3 bukti terkuat; jawaban ditandai dengan flag `partial_trust`.
3. **Zona Hijau ($\ge 0.65$):** Relevansi tinggi dan konsisten lintas sumber dense & sparse; diizinkan menghasilkan jawaban lengkap dengan atribusi penuh.

---

## 7. Alokasi Memori, Sumber Daya & Latensi (Resource & Latency Envelope)

### 7.1 Anggaran Latensi (SLA Target pada Jalur Groq Cloud)

| Tahapan Operasi | Target P50 | Target P95 | Catatan Batasan |
|---|---|---|---|
| Gateway Dispatch & Validation | $\le 5$ ms | $\le 15$ ms | Go HTTP routing tanpa alokasi memori berlebih |
| Hybrid Retrieval (Dense + BM25) | $\le 60$ ms | $\le 120$ ms | Qdrant HNSW vector search + BM25 in-memory |
| Cross-Encoder Reranking (opsional) | $\le 550$ ms | $\le 1200$ ms | Dibatasi pada top-5 kandidat teratas (CPU mode) |
| Groq LLM Generation | $\le 1500$ ms | $\le 3000$ ms | Menggunakan `openai/gpt-oss-20b` |
| Online Faithfulness Evaluation | $\le 80$ ms | $\le 200$ ms | Ekstraksi klaim regex + embedding dot-product |
| **Total End-to-End Budget** | **$\le 2.2$ s** | **$\le 4.5$ s** | Jalur tanpa retry |

### 7.2 Profil Memori RAM (Batas Host $\le 16$ GB)
* **Infrastruktur Bersama (Postgres + Qdrant + Redis):** $\sim 1.0 - 1.5$ GB.
* **Service Container (Gateway + Python-ML + RAG-API + Eval-API):** $\sim 2.5 - 3.5$ GB.
* **Model Cache MiniLM (Baked / Mounted Read-Only):** $\sim 0.8$ GB.
* **Sisa Memori untuk Desktop OS & Disk Buffer:** $\ge 9.0$ GB (Menghindari bahaya *OOM Killer signal 137*).

---

## 8. Roadmap Integrasi Bertahap (Phase-Gated Roadmap)

### 🟢 Fase 1 — Workspace Harmonization & Test Suite Alignment (Selesai — 2026-10-20)
* [x] Topologi kanonik 11 service di root `docker-compose.yml`.
* [x] Integrasi skrip rotasi kunci API (`scripts/rotate_key.sh`) dan audit rahasia (`scripts/check_secrets.sh`).
* [x] **Pemberesan Dockerfile `rag-research`:** Dockerfile mandiri multi-stage tanpa base image lokal; build `--no-cache` terverifikasi — ukuran image **11,9 GB → 3,89 GB** (lihat `docs/ops-postmortem.md` S-5).
* [x] **Harmonisasi `make test` di Root:** Target `test-arxiv-ml` (19 test, `PYTHONPATH=.`) masuk agregat `make test`; `test-mcp` kini memakai `-race`.
* [x] **Perbaikan Mocking `test_qdrant_store.py`:** `QdrantVectorStore` menerima `embedder`/`client` injeksi; suite **~27,4 s → ~1,2 s** dan lolos dengan `HF_HUB_OFFLINE=1`.
* [x] **Sinkronisasi Git Submodule Pointer:** Seluruh pointer submodule sinkron (`git submodule status` tanpa penanda `+`).

### ✅ Fase 2 — Observabilitas Standar & Data Curation (gate operasional selesai)
* [x] **Ekspos Prometheus Metrics di Semua Titik:** `/metrics` tersedia di `go-backend`, `python-ml`, `mcp-gateway`, `llm-eval-framework`, dan `rag-research`; kelima job terdaftar di `infra/prometheus/prometheus.yml`.
* [x] **Pembersihan Kebocoran Dataset (*Query Leakage*):** Memparafrasakan query `q02`, `q16`, `q13`, dan `q03` pada dataset evaluasi agar skor kesamaan terhadap gold chunk $< 0.90$.
* [x] **Mekanisme Auto-Seed Qdrant:** `make seed-rag` dan auto-seed saat startup kini memanggil modul dengan `python -m` dari root repo, sehingga boot awal dari volume Qdrant kosong tidak lagi gagal `ModuleNotFoundError` sebelum mencapai `require_nonempty_index`.
* [x] **Koneksi Caching Redis:** Jalur cache terverifikasi runtime pada 2026-10-24 (`cache_hit=false → true`, TTL 600 s). Redis tetap opt-in: default `REDIS_ENABLED=false` dan Redis hanya hidup di profil `monitoring`; aktifkan dengan `make cache-up`/`make verify-redis`.
* [x] **Verifikasi Runtime Monitoring:** `make verify-monitoring` membuktikan 5/5 target Prometheus `up`, `sum(up)=5`, series p95 tersedia, dan dashboard Grafana `workspace-overview` memiliki 5 panel (2026-10-24).
* [x] **Smoke Fresh-Run:** `make smoke-e2e` memakai `RUN_ID` unik, header `X-Request-ID`, dan query unik; verifikasi mengikat baris baru di `gateway_query_logs` dan `query_logs` sehingga hasil run lama tidak dapat memenuhi assertion.
* [x] **Readiness per Kapabilitas:** Gateway `/ready` melaporkan `answers`, `arxiv`, `research_rag`, dan `evaluation` secara terpisah; probe evaluator memakai `/ready` (embedding) dan bukan sekadar liveness proses.

### 🔵 Fase 3 — Standarisasi Protokol Wire MCP (Model Context Protocol) (Dalam Progress — 2026-10-24)
* [x] Mengembangkan gateway dari HTTP REST biasa ke implementasi resmi **MCP JSON-RPC 2.0 (HTTP transport)**.
* [x] Mendaftarkan tools: `search_scientific_literature`, `verify_factual_claim`, dan `generate_audit_dossier`.
* [x] Implement handshake initialize/initialized, tools/list, tools/call.
* [x] Add request body size limit (1 MiB) untuk DoS prevention.
* [x] Implement trace ID propagation (X-Request-ID header).
* [x] Fix HTTP status code mapping untuk error responses.
* [x] Fix tool response format (JSON serialization).
* [ ] Uji coba interoperabilitas langsung dengan klien eksternal seperti Claude Desktop dan ekstensi IDE Cursor.
* [ ] stdio adapter untuk Claude Desktop compatibility.
* [ ] SSE (Server-Sent Events) untuk streaming responses.

### 🟣 Fase 4 — Antarmuka Audit Klaim & Pelaporan Formal (*Claim Dossier UI*)
* [ ] Mengubah tampilan UI dari sekadar jendela chat biasa menjadi **Tampilan Audit Dua Sisi (Side-by-Side Claim Audit)**.
* [ ] Ekspor laporan berkas resmi berformat Markdown / PDF yang merinci klaim, status grounding, sitasi terverifikasi, dan metrik keyakinan.

---

## 9. Daftar Periksa Kesiapan Produksi (Production Readiness Checklist)

Sistem hanya dianggap siap rilis (*production-ready*) apabila seluruh gerbang berikut berstatus **PASS**:

- [x] **Kemandirian Build:** `docker compose build --no-cache --pull` berhasil dari nol pada 2026-10-24; kelima image workspace dibangun ulang. Image `python-ml` turun dari 10,1 GB menjadi 2,86 GB setelah torch CPU-only.
- [x] **Kelulusan Uji 100%:** `make test` lulus 898 test, 0 failed (arxiv Go 15, python-ml 45, gateway 143 dengan `-race`, evaluator 226, rag 469) pada 2026-10-24. Tidak ada skip yang memengaruhi gate ini.
- [x] **Nol Kebocoran Kunci:** `make check-secrets` mengembalikan `CLEAN` dengan exit code 0 pada 2026-10-24.
- [x] **Smoke integrasi tercatat:** smoke 2026-10-24 memakai `RUN_ID` unik, header `X-Request-ID`, dan query unik; baris baru di `gateway_query_logs` dan `query_logs` terverifikasi per request ID. Ini tetap smoke dasar, bukan acceptance kualitas/produksi.
- [x] **Monitoring Aktif:** Prometheus men-scrape 5/5 job (`go-backend`, `python-ml`, `mcp-gateway`, `llm-eval-framework`, `rag-api`), `sum(up)=5`, series p95 tersedia, dan dashboard `workspace-overview` memiliki 5 panel tanpa error (2026-10-24).

---

## 10. Batas Non-Tujuan (Non-Goals)

Untuk menjaga fokus dan keandalan sistem, hal-hal berikut secara eksplisit **BUKAN** merupakan tujuan proyek ini:

1. **Bukan Chatbot Percakapan Bebas (*Casual Chatbot*):** Sistem tidak dirancang untuk obrolan santai atau ramah tamah; sistem adalah mesin pengekstraksi fakta terarah.
2. **Tidak Melakukan Penalaran Tanpa Bukti (*Unconstrained Generative Reasoning*):** Model dilarang mengisi kekosongan informasi dengan asumsi saat literatur korpus tidak membahas topik tersebut.
3. **Bukan Tolok Ukur Generalis (*No General Benchmark*):** Kami tidak mengejar skor tinggi pada MMLU umum; fokus tunggal adalah presisi retrieval dan ketepatan atribusi bukti di domain riset.
4. **Bukan Oracle Kebenaran Mutlak:** Sistem memverifikasi apakah klaim didukung oleh dokumen korpus, bukan membuktikan kebenaran alam semesta di luar dokumen yang diindeks.
