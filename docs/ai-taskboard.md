# AI Taskboard — 2026-10-24

Protokol: **klaim tugas → tulis LOCK → kerja → lapor commit hash → integrator
review/push**. Satu penulis per file/repo. Lihat `CONVENTIONS.md`.

| # | Tugas | Owner | Branch | Scope file | DoD | Status |
|---|---|---|---|---|---|---|
| 8 | Goals per-repo Vertical 1 (spec anchor P0) | opencode | root | `docs/vertical-1/GOALS-PER-REPO.md`, `docs/ROADMAP.md`, `docs/business/decision-2026-10-29-dossier-first.md` | dokumen goals per repo konsisten dgn decision record + kontrak §4.4–4.7 | ✅ 2026-10-29 (root scope, integrator) |

## Status

| # | Tugas | Owner | Branch | Scope file | DoD | Status |
|---|---|---|---|---|---|---|
| 1 | Handling `ragas` (8 test gagal) | **aider** | `ai/ragas-optional` | `rag-research/requirements/llm.txt`, `tests/test_ragas_importable.py`, `tests/test_ci_contracts.py`, `tests/test_scripts_load_env.py` | suite 0 failed | ✅ 2026-10-22: 419 pass, 1 skip |
| 2 | Centang item leakage Fase 2 | opencode | `main` | `PROJECT_GOALS.md` | checkbox + bukti | ✅ sudah tercentang + bukti `test_query_leakage.py` |
| 3 | `make seed-rag` | opencode | `main` | `Makefile`, `README.md`, `PROJECT_CONTEXT.md` | idempoten | ✅ 2026-10-24: `points_count` 796 → 796 → 796; lihat `docs/acceptance/phase-2-verification.md` |
| 4 | Prometheus metrics `rag-research` | aider (setelah #1) | `ai/metrics-rag` | `rag-research/src/api/`, `tests/` | `/metrics` valid | ✅ endpoint + job scrape ditambahkan |
| 5 | Prometheus metrics `mcp-gateway` | aider (setelah #1) | `ai/metrics-gw` | `mcp-gateway/` | target UP | ✅ endpoint + job scrape ditambahkan |
| 6 | Verifikasi monitoring Prometheus/Grafana | opencode | `main` | `infra/`, `docs/` | targets UP | ✅ 2026-10-24: 5/5 target, `sum(up)=5`, p95 5 series, dashboard 5 panel; lihat `docs/acceptance/phase-2-verification.md` |
| 7 | Harmonisasi dokumentasi lintas-repo | Codex | `main` + branch repo aktif | dokumen Markdown utama | status, roadmap, kontrak, dan batas klaim saling konsisten | ✅ 2026-10-22: status/roadmap/kontrak diklarifikasi; gate runtime dan kualitas tetap terbuka |

## Track A — Gate Operasional Fase 2 (2026-10-24)

| Task | Commit | Bukti |
|---|---|---|
| 1 — Audit rahasia | sudah ada sebelum Track A | `make check-secrets` CLEAN |
| 2 — Kontrak cache | rag `6b96bcf`, root `bb9b527` | `GenerateResponse.cache_hit`; 469 test rag PASS |
| 3 — Verifikasi Redis | `bd5d7a1` | `cache_hit=false → true`, TTL 600 s |
| 4 — Readiness per kapabilitas | eval `3281d36`, gateway `3391b18`, root `8d5764e` | `/ready` + `capabilities.evaluation` |
| 5 — Smoke fresh-run | `34eed0b` | request ID/query unik; baris log terikat |
| 6 — Monitoring runtime | `4ca77d9` | 5/5 target, p95, dashboard 5 panel |
| 7 — Acceptance & docs | `2610010` (build fixes) + commit docs ini | `docs/acceptance/phase-2-verification.md` |

Rincian command, output, dan verdict ada di
`docs/acceptance/phase-2-verification.md`.

## LOCK

- Tidak ada lock aktif per 2026-10-22. Lock Codex untuk #7 dilepas setelah
  dokumentasi utama diselaraskan; tidak ada perubahan runtime.
- Lock `aider` untuk #1 dilepas setelah suite `rag-research` berjalan 419 pass / 1 skip.

## Saran & Masukan (Feedback) — 2026-10-29

> Masukan untuk pengerjaan berikutnya agar lebih terstruktur dan tidak asal. Tambahkan baris baru di sini saat ada temuan.

### A. Konsolidasi Dokumentasi (P1)
1. **Satu sumber status:** `docs/ROADMAP.md` sudah jadi SSoT. `STATUS.md`/`STATUS.json`/`PROJECT_CONTEXT.md` sering duplikat → jadikan `STATUS.json` auto-generated (lihat `scripts/generate_status.sh`) dan `STATUS.md` hanya pointer ke ROADMAP, hindari drift.
2. **Indeks docs:** `docs/README.md` (baru) menjadi navigasi; tambahkan entri setiap dokumen baru.
3. **Naming konsisten:** gunakan kebab-case untuk file baru; hindari campur UPPER/lower. Jangan rename file yang sudah direferensi tanpa update semua link.

### B. Prioritas Pengerjaan (Vertical 1 P0)
4. **Selesaikan P0 dossier** sebelum fitur lain: benahi `generate_audit_dossier` menjadi dossier sungguhan (prasyarat Vertical 1). Lihat `docs/vertical-1/GOALS-PER-REPO.md`.
5. **Jangan blokir rilis dengan Rust reranker** (bukan gate rilis) — cukup targeted test.
6. **Phase 1 smoke quality** masih `human_review_complete: false` → selesaikan review manusia sebelum klaim phase1 pass.

### C. Operasional & Gate
7. **Resource lock:** sebelum `docker compose build/up` atau `make test` penuh, tulis `RESOURCE: docker|test` di LOCK dan hapus setelah selesai (hindari dua proses berat bersamaan).
8. **Calibration container stopped** (2 FAIL di status-report) → jalankan build+recreate saat lock tersedia, verifikasi `/app/models` dan log `Calibration model loaded`.
9. **Secret scan:** selalu `make check-secrets` CLEAN; jangan commit `.env`; gunakan `scripts/rotate_key.sh`.
10. **Mode A/B:** jangan jalankan bersamaan; verifikasi port sebelum start.

### D. Disiplin Perubahan
11. **Ownership:** jangan edit file di luar scope repo; untuk perubahan di file integrator (Makefile, docker-compose, AGENTS, PROJECT_*.md, docs/* root) tulis baris `REQUEST` di taskboard, jangan edit langsung.
12. **Satu penulis per file:** klaim tugas + LOCK sebelum kerja; lapor commit hash; integrator review/push.
13. **Cross-repo:** jangan panggil repo lain untuk menyelesaikan core path (lihat ownership table AGENTS.md §3).
14. **Test:** `make test` 100% PASS sebelum klaim selesai; targeted test saat iterasi.

### E. Kualitas Kode & Observability
15. **Trace propagation** & `/tool` security masih open gate (mcp-gateway) → prioritaskan.
16. **Kalibrasi:** ECE 0.0576 (holdout, 194 sampel) — refit dari audit terkumpul di P1.
17. **Abstention:** jaga hard abstention; jangan bypass threshold tanpa bukti.

## Backlog yang Disarankan (Next)
| Prioritas | Item | Owner saran | Referensi |
|---|---|---|---|
| P0 | Benahi `generate_audit_dossier` → dossier sungguhan | opencode/kilo | `docs/superpowers/plans/2026-10-26-p0-consolidation.md` |
| P0 | Tutup bukti phase1 smoke (human review) | opencode | `rag-research/PROJECT_GOALS.md` |
| P1 | Vertical 1 P0 MVP (paste-klaim → report) | kilo | `docs/vertical-1/GOALS-PER-REPO.md` |
| P1 | Refit kalibrasi dari audit terkumpul | opencode | `docs/confidence-calibration.md` |
| P2 | Connector korpus paten USPTO/EPO | TBD | `docs/business/decision-2026-10-29-dossier-first.md` |
| Ops | Perbaiki 2 FAIL status-report (calibration container, phase1 smoke) | integrator | `scripts/generate_status.sh` |

## Struktur Dokumentasi (ringkas)
Lihat [`docs/README.md`](README.md) untuk indeks lengkap. Kategori: Status/Roadmap, Operasional, Arsitektur, MCP, Bisnis, Domain, Runbook/Acceptance, Tugas, Superpowers.

## Catatan Tambahan
- Tambahkan saran/masukan baru di section **Saran & Masukan** di atas, bukan di chat, agar terlacak.
- Setiap saran sebaiknya punya bukti (file/commit/test) agar bisa ditindaklanjuti.

---

*Terakhir diperbarui: 2026-10-29 (organisasi docs + feedback).*


## Catatan (historis, dipertahankan)
- Tugas #1: brief lengkap di `docs/tasks/ragas-optional-dependency.md`.
- `prometheus-client==0.26.0` sudah ter-pin di `rag-research/requirements/runtime.txt`.
- 2026-10-22: `/metrics` juga ditambahkan ke `llm-eval-framework`; kelima service kini punya scrape job di `infra/prometheus/prometheus.yml`.
- Auto-seed Qdrant dan `make seed-rag` sama-sama memakai `python -m` dari root repo agar `import src` bekerja saat volume Qdrant kosong.

---

## 2026-10-26 — Kalibrasi build-time & track Rust (Kilo)

| # | Tugas | Owner | Branch | Scope file | DoD | Status |
|---|---|---|---|---|---|---|
| 8 | Kalibrasi ikut image + dataset ERROR dibersihkan + `STATUS.md` generator | **opencode** | `remediation/2026-10-24` | `rag-research/Dockerfile`, `rag-research/requirements/runtime.txt`, `rag-research/scripts/fit_calibration.py`, `rag-research/data/evaluation/calibration_dataset.json`, `rag-research/tests/test_calibration_dataset_integrity.py`, `docker-compose.yml`, `.env.example`, `scripts/generate_status.sh`, `docs/confidence-calibration.md` | build sukses, `/app/models` ada, log `Calibration model loaded`, `make status-report` kalibrasi PASS | 🟡 berjalan (build image) |
| 9 | Rust cross-encoder reranker (Cargo, ONNX, PyO3, benchmark) | **kilo** | `kilo/rust-reranker` | `rag-research/rust/**` (baru), `rag-research/src/retrieval/hybrid_retriever.py`, `rag-research/scripts/benchmark_reranker*.py` | benchmark vs Python + targeted test; **bukan** gate rilis | 📋 diusulkan |

**Batas file yang tidak boleh ditulis Kilo** (milik integrator): `Makefile`,
`docker-compose.yml`, `rag-research/Dockerfile`,
`rag-research/requirements/*`, `.env.example`, `STATUS.md`, `AGENTS.md`,
`PROJECT_*.md`, `docs/*` di root. Butuh perubahan di sana → tulis baris
`REQUEST` di bawah, jangan edit langsung.

**Resource lock:** hanya satu agen boleh menjalankan `docker compose build`,
`docker compose up`, atau `make test` penuh pada satu waktu. Tulis
`RESOURCE: docker|test` di LOCK sebelum mulai, hapus setelah selesai.

## LOCK

- **opencode** (aktif 2026-10-26): file scope #8 di atas. Dilepas setelah
  build + recreate + `make status-report` terverifikasi.
- **kilo**: belum aktif. Menunggu track kalibrasi di-commit lebih dulu —
  `rag-research/HEAD` belum memuat `src/controller/calibration.py` dan
  dataset, sehingga worktree/branch baru akan kehilangan fitur tersebut.

## Catatan koordinasi

- Todo milik Kilo yang menyebut "fit calibration / expand 200 / verify ECE"
  **sudah selesai di track opencode**; jangan dijalankan ulang. Kondisi nyata:
  194 sampel fit (6 baris ERROR masuk `excluded_samples`), model di-fit saat
  build image, ECE 0.0576 (holdout).
- Kilo cukup menjalankan targeted test selama bekerja; `make test` penuh dan
  `make status-report` dijalankan integrator agar tidak ada dua proses berat
  bersamaan.

## 2026-10-29 — Tutup bukti mcp-gateway (opencode, Fase 0)

| # | Tugas | Owner | Branch | Scope file | DoD | Status |
|---|---|---|---|---|---|---|
| 10 | Tutup bukti mcp-gateway (maskDSN + RAG abstain) | **opencode** | `remediation/2026-10-24` | `mcp-gateway/cmd/server/main.go`, `mcp-gateway/cmd/server/respond.go`, `mcp-gateway/internal/api/contract.go`, `mcp-gateway/internal/planner/executor.go`, `mcp-gateway/cmd/server/p0_p2_regression_test.go` | test bukti merah→hijau, suite race hijau, pointer bump | ✅ selesai |

**Bukti terukur:**
- Test baru: `TestMaskDSN_HidesPassword`, `TestMaskDSN_Empty`, `TestToResponse_RAGSentinelAnswerIsAbstention`, `TestToResponse_RAGSentinelAnswerTextOnlyIsAbstention` — disaksikan merah (maskDSN leak password; abstain → answer) lalu hijau setelah fix.
- `go test ./... -race -count=1` (mcp-gateway): semua 11 package PASS.
- `make check-secrets`: CLEAN.
- Commit submodule: `b538155` (opencode: fix maskDSN masking + RAG abstain text detection).
- Commit root pointer bump: `285ed72` (chore: bump mcp-gateway pointer).
- `make status-report`: 2 FAIL tersisa (calibration container stopped; phase1 smoke quality) — sesuai rencana, bukan bug kode. Security (Binary tracked/Secret scan) PASS.

**Risiko:** perubahan threshold config rag-research (0.25→0.35) ditanggung di track terpisah (commit `a2256ea`, pointer `5ef5144`).

**Yang tidak diubah:** tidak ada fitur vertical-1 baru; docker-compose tidak disentuh; hanya file scope di atas + test file.

## 2026-10-29 — Runtime validation + phase1 smoke runtime_pass (opencode)

| # | Tugas | Owner | Branch | Scope file | DoD | Status |
|---|---|---|---|---|---|---|
| 11 | Tutup gerbang runtime: smoke phase1 runtime_pass + gate hijau | **opencode** | `remediation/2026-10-24` | `rag-research/Makefile`, `rag-research/results/metrics/phase1_smoke_v3.json`, `scripts/generate_status.sh`, root pointer | smoke 20/20 runtime_pass, suite rag 0 failed, check-secrets CLEAN, smoke-e2e PASS, migration 004 live | ✅ selesai (runtime); ⏳ kualitas menunggu anotasi manusia |

**Bukti terukur:**
- **Akar mismatch 642 vs 796 tuntas ditutup:** resep `phase1-smoke` di `rag-research/Makefile:29` mengunci hardcode `BM25_CHUNKS_PATH=chunks_semantic_v3.json` (642) di atas env-override; indeks `rag_research_phase1_v3` (796, dibangun dari v2) vs BM25 642 = selalu `IndexCountMismatchError`. Fix: baris makefile → `chunks_semantic_v2.json` (796) = indeks + `settings.bm25_chunks_path` default. Korpus beku (`chunks_semantic_v3.json`, sha `f3068…`) TIDAK disentuh — guard sha tetap kunci v3.
- **Smoke penuh 20/20**: `runtime_pass=true`, `runtime_failed_query_ids=[]`, `provider_errors=0` — retrieval + generasi + abstain semua jalan penuh via target resmi (`QDRANT_URL=http://localhost:6333` dari host).
- **Suite rag**: `536 passed, 0 failed` (pertama kali hijau penuh; milestone dari 529/7 di awal hari).
- **`make check-secrets`**: CLEAN, exit 0.
- **`make smoke-e2e`**: PASSED — RUN_ID `20261029T144434Z-75876`, gateway + arxiv query-logs verified, RAG contract `decision=answer eval=completed`.
- **Stack live**: 8/8 healthy; migrasi `004_audit_reports` tereksekusi (tabel `audit_reports`+`audit_report_claims` di `arxiv_db`); buster auth Postgres `28P01` ditumpang alias langsung (`ALTER ROLE arxiv` lewat env di dalam container — password tidak pernah tampil).
- **Commit**: rag `933fcb6` (Makefile + artefak smoke), root pointer `2e36dcb`; pembetulan generator status (baca artefak kanonik, bukan salinan arsip basi).
- **Index eksplisit**: `rag_research_phase1_v3` = 796 points (rebuild dari korpus kanonik v2; koleksi `rag_research` juga 796).

**Open (untuk operator, bukan kode):**
- `phase1_pass=false` + `human_review_complete=false` — anotasi review manusia harus dijalankan sendiri: `make -C rag-research phase1-review` (interaktif, tanpa LLM) → `make -C rag-research phase1-check` → regen `make status-report`. Target: 0 FAIL penuh di STATUS.
- 2 WARN per STATUS (lihat bagian WARN STATUS.md terbaru).
