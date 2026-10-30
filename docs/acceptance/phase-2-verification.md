# Fase 2 — Acceptance Gate Operasional

**Tanggal verifikasi:** 2026-10-24
**Operator:** OpenCode (DeepSeek V4.1 Flash Free)
**Branch:** `remediation/2026-10-24`
**Lingkup:** gate operasional Fase 2 (build, test, rahasia, kesehatan stack,
readiness, seed, smoke, cache, monitoring, persistensi). Dokumen ini **bukan**
acceptance kualitas jawaban dan tidak menyatakan sistem production-ready penuh.

## Baseline

| Item | Nilai |
|---|---|
| Root commit saat Task 7 dimulai | `4ca77d9` |
| Root commit perbaikan build | `2610010` |
| `arxiv-research-assistant` | `c796b55` → `2a6b393` (perbaikan build) |
| `llm-eval-framework` | `3281d36` |
| `mcp-gateway` | `3391b18` |
| `rag-research` | `6b96bcf` |
| Docker | rootless 29.9.2 |
| Host | Linux, disk 32 GB (5,8 GB bebas saat Task 7 dimulai) |
| Working tree | bersih saat baseline; hanya path terencana yang di-commit |

Perbaikan build yang lahir dari verifikasi ini:

- `a9a64da` — `python-ml` memasang `torch==2.14.1+cpu` dari index PyTorch CPU
  sebelum `requirements.txt`, sehingga wheel CUDA (~2 GB) tidak lagi ditarik.
- `2a6b393` — builder `go-backend` memakai `golang:1.25-alpine`, sesuai
  `go.mod` yang mensyaratkan `go >= 1.25.0`.

## Hasil Gate

| Gate | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| Secrets | `make check-secrets` | CLEAN, exit 0 | CLEAN, 4/4 `.env.example` placeholder, exit 0 | **PASS** |
| Tests | `make test` | 0 failed | 898 passed, 0 failed (rincian di bawah) | **PASS** |
| Clean build | `docker compose build --no-cache --pull` | sukses | 5 image dibangun ulang, exit 0 | **PASS** |
| Compose config | `docker compose --env-file .env config` | exit 0 | valid, exit 0 | **PASS** |
| Stack health | `docker compose up -d --wait --wait-timeout 600` | semua healthy | 8/8 layanan inti healthy | **PASS** |
| Evaluator readiness | `ollama pull` + warmup + `/ready` | HTTP 200 | model ada, warmup sukses, `/ready` 200 | **PASS** |
| Gateway readiness | `curl /ready` | `ready` + answers/evaluation | `status=ready`, `answers=true`, `evaluation=true` | **PASS** |
| Seed idempotent | `make seed-rag` ×2 | `points_count` sama | 796 → 796 → 796 | **PASS** |
| Smoke fresh log | `make smoke-e2e` ×2 | request ID & row count benar | 2 RUN_ID berbeda, 1 baris per request ID | **PASS** |
| Redis cache | `make verify-redis` | `cache_hit` false→true, TTL > 0 | false→true, TTL 600 s | **PASS** |
| Monitoring | `make verify-monitoring` | 5 target, p95, dashboard | 5/5 up, `sum(up)=5`, p95 5 series, dashboard 5 panel | **PASS** |
| Persistence | `down` (tanpa `-v`) lalu `up --wait` | data bertahan | 48/25/796 sebelum = sesudah | **PASS** |

## Bukti

### 1. Secrets

```**text**
✅ CLEAN — no tracked credential leaks found
```

`scripts/check_secrets.sh` memeriksa prefix kunci terkompromi, pola kunci Groq,
dan placeholder pada empat `.env.example`; exit code 0.

### 2. Test suite

`make test` dijalankan dari root; Go test dijalankan ulang tanpa cache
(`go clean -testcache`) agar hitungan bukan hasil cached.

| Repo | Test lulus | Gagal |
|---|---:|---:|
| `arxiv-research-assistant/go-backend` | 15 | 0 |
| `arxiv-research-assistant/python-ml` | 45 | 0 |
| `mcp-gateway` (`-race`) | 143 | 0 |
| `llm-eval-framework` | 226 | 0 |
| `rag-research` | 469 | 0 |
| **Total** | **898** | **0** |
z
### 3. Clean build

```text
Image ai-infra-workspace-rag-api Built
Image ai-infra-workspace-arxiv-go-backend Built
Image ai-infra-workspace-arxiv-python-ml Built
Image ai-infra-workspace-llm-eval-framework Built
Image ai-infra-workspace-mcp-gateway Built
```

Ukuran image hasil build bersih:

| Image | Ukuran |
|---|---|
| `arxiv-go-backend` | 40,5 MB |
| `arxiv-python-ml` | **2,86 GB** (sebelumnya 10,1 GB) |
| `llm-eval-framework` | 387 MB |
| `mcp-gateway` | 32,9 MB |
| `rag-api` | 2,41 GB |

`--no-cache` tidak memakai layer cache untuk `RUN`/`COPY`; baris `CACHED` yang
muncul hanya pada `WORKDIR` (metadata tanpa layer) dan resolusi base image.
Percobaan build pertama gagal karena toolchain Go 1.23; setelah perbaikan
`2a6b393`, build penuh diulang dari awal dan berhasil.

### 4. Kesehatan stack

```text
ws-arxiv-go-backend     Up (healthy)
ws-arxiv-python-ml      Up (healthy)
ws-llm-eval-framework   Up (healthy)
ws-mcp-gateway          Up (healthy)
ws-postgres             Up (healthy)
ws-qdrant               Up (healthy)
ws-ollama               Up (healthy)
ws-rag-api              Up (healthy)
```

Seluruh endpoint `/health` (8090, 8080, 8001, 8002, 8000) mengembalikan HTTP 200.

### 5. Readiness evaluator dan gateway

`ollama list` memuat `nomic-embed-text:latest` (274 MB). Warmup embedding
melalui `http://ollama:11434/api/embed` mencetak `embedding warmed`;
`http://127.0.0.1:8002/ready` mengembalikan `200`.

```json
{"status":"ready",
 "capabilities":{"answers":true,"arxiv":true,"evaluation":true,"research_rag":true},
 "services":{"arxiv":"up","evaluator":"up","rag":"up"}}
```

Catatan: `ollama pull nomic-embed-text` gagal pada resolusi DNS registry
rootless (`registry.ollama.ai` timeout), tetapi model sudah tersedia lokal.
Yang terbukti adalah readiness model yang ada, bukan kemampuan pull ulang.

### 6. Idempotensi seed Qdrant

```text
before=796
after run 1=796
after run 2=796
```

Tidak ada duplikasi. `make seed-rag` menulis ulang dua artefak corpus
(`data/processed/chunks_semantic_v3.json`, `documents.json`); keduanya
dikembalikan ke HEAD setelah verifikasi karena di luar lingkup Task 7.

### 7. Smoke fresh-run

| Run | RUN_ID | Gateway arxiv | Gateway rag | Arxiv `query_logs` |
|---|---|---:|---:|---:|
| 1 | `20261024T151344Z-110361` | 1 baris | 1 baris | 1 baris |
| 2 | `20261024T151516Z-113050` | 1 baris | 1 baris | 1 baris |

Kedua run memakai header `X-Request-ID` dan query unik, sehingga baris lama
tidak dapat memenuhi assertion. Kontrak RAG kedua run:
`decision=answer`, `evaluation_status=completed`. Jawaban arxiv berhenti pada
abstention 21 karakter ("Not found in context."); ini bukti integrasi, bukan
bukti kualitas jawaban.

### 8. Redis cache

```text
verify-redis: run=20261024T151439Z-111911
verify-redis: first request ... cache_hit=false
verify-redis: second request ... cache_hit=true retrieval_ms=0.0 generation_ms=0.0
verify-redis: redis key=rag:gen:...:3:False ttl=600s
✅ verify-redis: PASS (cache_hit=false → true, ttl=600s)
```

### 9. Monitoring

```text
✓ Prometheus targets: 5/5 up
✓ sum(up)=5
✓ p95 query: 5 series
✓ Grafana dashboard: workspace-overview (5 panels)
✅ verify-monitoring: PASS
```

Kelima job: `go-backend`, `python-ml`, `mcp-gateway`, `llm-eval-framework`,
`rag-api`.

### 10. Persistensi lifecycle

```text
sebelum down: gateway_query_logs=48, query_logs=25, points=796
docker compose down (tanpa -v)  → exit 0
docker compose up -d --wait     → exit 0, 8/8 healthy
sesudah up:   gateway_query_logs=48, query_logs=25, points=796
```

Tidak ada volume yang dihapus. Karena `down` dijalankan tanpa profile
`monitoring`, container Prometheus/Grafana/Redis tetap hidup; network project
sempat dilaporkan "still in use" dan tidak dihapus.

## Known Limitations

1. **Gate operasional, bukan kualitas.** Smoke membuktikan ingest, routing,
   logging, dan kontrak abstain/evaluasi. Dokumen ini tidak membuktikan
   faithfulness, kalibrasi confidence, atau atribusi per kalimat.
2. **MCP belum tersedia.** Fase 3 (JSON-RPC 2.0, tools, interoperabilitas klien)
   belum dimulai.
3. **Cache masih opt-in.** Default `REDIS_ENABLED=false`; Redis hidup di profil
   `monitoring` dan jalur cache diaktifkan dengan `make cache-up`/`verify-redis`.
4. **Build bergantung jaringan.** `--pull` dan instalasi wheel memerlukan akses
   registry/PyPI. Dependency `python-ml` selain torch belum di-pin, sehingga
   build ulang dapat menarik versi baru.
5. **Pull model embedding tidak terbukti di lingkungan ini.** Model sudah ada
   sebelum verifikasi; `ollama pull` gagal karena DNS rootless.
6. **Monitoring opt-in.** `make monitoring-up` harus dijalankan terpisah dari
   `make up`; setelah lifecycle test, kelima target tetap hidup.

## Verdict

**12/12 gate operasional PASS.** Fase 2 dapat ditandai selesai pada level
operasional. Klaim production-ready penuh, kualitas jawaban, dan Fase 3 tetap
terbuka.
