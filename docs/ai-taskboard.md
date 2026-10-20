# AI Taskboard — 2026-10-20

Protokol: **klaim tugas → tulis LOCK → kerja → lapor commit hash → integrator
review/push**. Satu penulis per file/repo. Lihat `CONVENTIONS.md`.

## Status

| # | Tugas | Owner | Branch | Scope file | DoD | Status |
|---|---|---|---|---|---|---|
| 1 | Handling `ragas` (8 test gagal) | **aider** | `ai/ragas-optional` | `rag-research/requirements/llm.txt`, `tests/test_ragas_importable.py`, `tests/test_ci_contracts.py`, `tests/test_scripts_load_env.py` | suite 0 failed | 🔄 dikerjakan |
| 2 | Centang item leakage Fase 2 | opencode | `main` | `PROJECT_GOALS.md` | checkbox + bukti | ⬜ |
| 3 | `make seed-rag` | opencode | `main` | `Makefile`, `README.md`, `PROJECT_CONTEXT.md` | idempoten | ⬜ |
| 4 | Prometheus metrics `rag-research` | aider (setelah #1) | `ai/metrics-rag` | `rag-research/src/api/`, `tests/` | `/metrics` valid | ⬜ |
| 5 | Prometheus metrics `mcp-gateway` | aider (setelah #1) | `ai/metrics-gw` | `mcp-gateway/` | target UP | ⬜ |
| 6 | Verifikasi monitoring Prometheus/Grafana | opencode | `main` | `infra/`, `docs/` | targets UP | ⬜ |

## LOCK

- `aider` → `rag-research` (requirements + 3 file test), sejak 2026-10-20.
  **Jangan edit file yang sama dari sisi OpenCode.**

## Catatan

- Tugas #1: brief lengkap di `docs/tasks/ragas-optional-dependency.md`.
- `prometheus-client==0.26.0` sudah ter-pin di
  `rag-research/requirements/runtime.txt` — tugas #4 tidak perlu menambah
  dependency baru.
