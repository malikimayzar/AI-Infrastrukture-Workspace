# AI Taskboard — 2026-10-22

Protokol: **klaim tugas → tulis LOCK → kerja → lapor commit hash → integrator
review/push**. Satu penulis per file/repo. Lihat `CONVENTIONS.md`.

## Status

| # | Tugas | Owner | Branch | Scope file | DoD | Status |
|---|---|---|---|---|---|---|
| 1 | Handling `ragas` (8 test gagal) | **aider** | `ai/ragas-optional` | `rag-research/requirements/llm.txt`, `tests/test_ragas_importable.py`, `tests/test_ci_contracts.py`, `tests/test_scripts_load_env.py` | suite 0 failed | ✅ 2026-10-22: 419 pass, 1 skip |
| 2 | Centang item leakage Fase 2 | opencode | `main` | `PROJECT_GOALS.md` | checkbox + bukti | ✅ sudah tercentang + bukti `test_query_leakage.py` |
| 3 | `make seed-rag` | opencode | `main` | `Makefile`, `README.md`, `PROJECT_CONTEXT.md` | idempoten | 🔄 kode fixed (`python -m`); uji runtime butuh Qdrant hidup |
| 4 | Prometheus metrics `rag-research` | aider (setelah #1) | `ai/metrics-rag` | `rag-research/src/api/`, `tests/` | `/metrics` valid | ✅ endpoint + job scrape ditambahkan |
| 5 | Prometheus metrics `mcp-gateway` | aider (setelah #1) | `ai/metrics-gw` | `mcp-gateway/` | target UP | ✅ endpoint + job scrape ditambahkan |
| 6 | Verifikasi monitoring Prometheus/Grafana | opencode | `main` | `infra/`, `docs/` | targets UP | 🔄 butuh `make monitoring-up` + stack hidup |

## LOCK

- Tidak ada lock aktif per 2026-10-22. Lock `aider` untuk #1 dilepas setelah
  suite `rag-research` berjalan 419 pass / 1 skip.

## Catatan

- Tugas #1: brief lengkap di `docs/tasks/ragas-optional-dependency.md`.
- `prometheus-client==0.26.0` sudah ter-pin di
  `rag-research/requirements/runtime.txt`.
- 2026-10-22: `/metrics` juga ditambahkan ke `llm-eval-framework`; kelima
  service kini punya scrape job di `infra/prometheus/prometheus.yml`.
- Auto-seed Qdrant dan `make seed-rag` sama-sama memakai `python -m` dari root
  repo agar `import src` bekerja saat volume Qdrant kosong.
