# AI Taskboard — 2026-10-24

Protokol: **klaim tugas → tulis LOCK → kerja → lapor commit hash → integrator
review/push**. Satu penulis per file/repo. Lihat `CONVENTIONS.md`.

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

## Catatan

- Tugas #1: brief lengkap di `docs/tasks/ragas-optional-dependency.md`.
- `prometheus-client==0.26.0` sudah ter-pin di
  `rag-research/requirements/runtime.txt`.
- 2026-10-22: `/metrics` juga ditambahkan ke `llm-eval-framework`; kelima
  service kini punya scrape job di `infra/prometheus/prometheus.yml`.
- Auto-seed Qdrant dan `make seed-rag` sama-sama memakai `python -m` dari root
  repo agar `import src` bekerja saat volume Qdrant kosong.
