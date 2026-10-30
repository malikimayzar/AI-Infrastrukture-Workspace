# Dokumentasi — Indeks

> Navigasi terpusat untuk seluruh dokumentasi workspace `ai-infra-workspace`.
> Sumber kebenaran status & roadmap: [`ROADMAP.md`](ROADMAP.md). Konvensi kerja: [`../CONVENTIONS.md`](../CONVENTIONS.md).

## Cara Pakai Indeks Ini
- Mulai dari **Status & Roadmap** untuk tahu posisi proyek.
- Untuk operasional (run/debug/backup) lihat **Operasional**.
- Untuk kontrak & integrasi MCP lihat **MCP**.
- Untuk keputusan arah produk lihat **Bisnis & Produk**.

## Status & Roadmap
- [`ROADMAP.md`](ROADMAP.md) — Single source of truth fase 1–4, status, test results.
- [`../PROJECT_GOALS.md`](../PROJECT_GOALS.md) — Spec engineering & success criteria.
- [`../PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md) — Snapshot runtime & integrasi.
- [`ai-taskboard.md`](ai-taskboard.md) — Taskboard multi-agen, lock, koordinasi.
- [`IMPROVEMENTS.md`](IMPROVEMENTS.md) — Ringkasan quick wins.
- [`ENVIRONMENT_STRUCTURE.md`](ENVIRONMENT_STRUCTURE.md) — Struktur environment.

## Operasional
- [`OPERATIONS.md`](OPERATIONS.md) — Run, debug, troubleshooting.
- [`ops-postmortem.md`](ops-postmortem.md) — Insiden historis & solusi.
- [`backup-guide.md`](backup-guide.md) — Backup/restore Postgres & Qdrant.
- [`health-check-guide.md`](health-check-guide.md) — Deep health check.
- [`structured-logging-guide.md`](structured-logging-guide.md) — Logging terstruktur.
- [`pre-commit-guide.md`](pre-commit-guide.md) — Pre-commit hooks.
- [`tracing-guide.md`](tracing-guide.md) — OpenTelemetry tracing.

## Arsitektur & Desain
- [`architecture/`](architecture/) — Pipeline evaluasi & arsitektur.
- [`adr/`](adr/) — Architecture Decision Records.
- [`confidence-calibration.md`](confidence-calibration.md) — Kalibrasi confidence (isotonic).
- [`llm-provider-fallback.md`](llm-provider-fallback.md) — Fallback provider LLM.
- [`mcp-transport-decision.md`](mcp-transport-decision.md) — Keputusan transport MCP.

## MCP
- [`mcp-integration-guide.md`](mcp-integration-guide.md) — Integrasi MCP.
- [`mcp-claude-desktop-example.md`](mcp-claude-desktop-example.md) — Contoh Claude Desktop.

## Bisnis & Produk
- [`business/`](business/) — Strategi produk & decision dossier-first.
- [`vertical-1/`](vertical-1/) — Goals per-repo Vertical 1 (P0).

## Domain Khusus
- [`healthcare/`](healthcare/) — Validasi klinis, tata kelola data, domain.
- [`security/`](security/) — Insiden keamanan & audit.

## Runbook & Acceptance
- [`runbooks/`](runbooks/) — Runbook insiden.
- [`acceptance/`](acceptance/) — Bukti acceptance fase 2.

## Tugas & Rencana
- [`tasks/`](tasks/) — Brief tugas (ragas, kalibrasi).
- [`superpowers/`](superpowers/) — Plans & specs (phase 2, remediation, claim audit UI).

## Konvensi
- Tidak memindahkan file tanpa update referensi.
- `ROADMAP.md` = satu-satunya sumber status; hindari duplikasi dokumen status (lihat `STATUS.json` auto-generated).
- Tambahkan entri baru di indeks ini saat menambah dokumen.
