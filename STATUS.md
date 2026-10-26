# Project Status

> **Generated:** 2026-10-26T02:40:31+07:00
> **Commit:** 1d39765
> **Branch:** remediation/2026-10-24
> **Working tree:** 24 perubahan

> File ini di-generate oleh `scripts/generate_status.sh` dari eksekusi nyata.
> Jangan edit manual — jalankan ulang generatornya.

## Ringkasan

| Status | Jumlah |
|---|---:|
| ✅ PASS | 24 |
| ⚠️ WARN | 7 |
| ❌ FAIL | 6 |
| ⏭️ SKIP | 2 |
| ℹ️ INFO | 4 |

**Cara membaca:** PASS = diverifikasi oleh eksekusi; WARN = perlu perhatian; FAIL = klaim belum didukung; SKIP = prasyarat tidak tersedia; INFO = konteks.

**Build & Tests** secara default hanya menghitung test yang terkumpul; jalankan `--full` untuk benar-benar mengeksekusi suite.

## Repository

| Check | Status | Evidence |
|---|---|---|
| Release tags | ⚠️ WARN | 0 tag — hasil tidak dapat direproduksi dari rilis |
| Default branch | ℹ️ INFO | master |
| CI trigger cocok dengan default branch | ❌ FAIL | CI: branches: [main]  \| default: master |
| Submodule sinkron | ✅ PASS | 4 submodule |

## Build & Tests

| Check | Status | Evidence |
|---|---|---|
| arxiv Go — collected | ✅ PASS | 15 test |
| mcp-gateway — collected | ✅ PASS | 156 test |
| arxiv python-ml — collected | ✅ PASS | 45 test |
| llm-eval — collected | ✅ PASS | 228 test |
| rag-research — collected | ✅ PASS | 482 test |
| Test suite penuh | ⏭️ SKIP | jalankan dengan --full untuk mengeksekusi |

## Runtime

| Check | Status | Evidence |
|---|---|---|
| Compose valid | ✅ PASS | 8 core; 12 dengan profile |
| Health probe | ⏭️ SKIP | --no-network atau curl tidak tersedia |

## Calibration

| Check | Status | Evidence |
|---|---|---|
| Model file | ✅ PASS | calibration_isotonic.joblib (17689 bytes) |
| Model dapat dimuat | ✅ PASS | method=isotonic fitted=True samples=194 |
| Image menyediakan models/ | ✅ PASS | model di-fit saat build (fit_calibration.py) |
| Compose punya env kalibrasi | ✅ PASS | CALIBRATION_METHOD CALIBRATION_MODEL_PATH  |
| .env.example punya variabel kalibrasi | ✅ PASS | CALIBRATION_METHOD CALIBRATION_MODEL_PATH  |
| Model vs dataset | ✅ PASS | 194 sampel = 194 baris dataset |
| Container punya model | ✅ PASS | /app/models/calibration_isotonic.joblib ada |
| Container memuat model | ✅ PASS | log startup: Calibration model loaded |

## Datasets

| Check | Status | Evidence |
|---|---|---|
| Rows | ℹ️ INFO | 194 baris (declared 194) |
| Jumlah baris cocok | ✅ PASS | 194 = declared 194 |
| Baris dikeluarkan | ✅ PASS | 6 baris dikeluarkan dari fitting |
| Label is_supported | ✅ PASS | 194/194 berlabel |
| Unique queries | ⚠️ WARN | 137 unik, 57 duplikat, 0 konflik label (bias kalibrasi) |
| Baris ERROR | ✅ PASS | 0 |
| Probe negatif off-domain | ✅ PASS | 21 probe, semuanya is_supported=false (disengaja) |
| ground_truth (opsional) | ℹ️ INFO | 13/194 baris punya teks referensi; label utama = is_supported |

## MCP

| Check | Status | Evidence |
|---|---|---|
| HTTP handler | ✅ PASS | internal/mcp/handler.go ada |
| stdio adapter | ⚠️ WARN | ada di working tree tetapi belum tracked |
| Konsistensi dokumen | ❌ FAIL | README bilang belum, integration guide bilang sudah |
| SSE (kode) | ⚠️ WARN | kode ada; perilaku streaming belum diverifikasi |

## Security

| Check | Status | Evidence |
|---|---|---|
| Secret scan | ✅ PASS | scripts/check_secrets.sh bersih |
| .env di-gitignore | ✅ PASS | .env tidak akan ter-commit |
| Groq key revocation | ❌ FAIL | dokumen insiden masih menyatakan revocation pending |
| Binary tracked | ❌ FAIL | tracked: server=19MB |
| Binary untracked | ⚠️ WARN | server_new=19MB, tidak di-ignore |

## Documentation

| Check | Status | Evidence |
|---|---|---|
| Jumlah file .md | ℹ️ INFO | 195 |
| Link internal rusak | ⚠️ WARN | 2 link; contoh: README.md -> docs/ARCHITECTURE.md; mcp-gateway/docs/workspace-alignment.md -> ../WORKSPACE_DIRECTION.md |
| README -> docs/ARCHITECTURE.md | ❌ FAIL | dirujuk tetapi file tidak ada |
| Dokumen status ganda | ⚠️ WARN | PROJECT_CONTEXT.md, docs/ROADMAP.md, docs/IMPLEMENTATION_STATUS.md, STATUS.md |

## Quality Gates

| Check | Status | Evidence |
|---|---|---|
| Phase 1 smoke (v3) | ❌ FAIL | phase1_smoke_v3_20261024T164559.452903Z.json phase1_pass=False human_review_complete=False |
| Laporan kalibrasi | ✅ PASS | models/calibration_report.json n=194 (isotonic, platt) |

## Gap yang perlu ditutup

- **Repository / Release tags** (WARN): 0 tag — hasil tidak dapat direproduksi dari rilis
- **Repository / CI trigger cocok dengan default branch** (FAIL): CI: branches: [main]  | default: master
- **Datasets / Unique queries** (WARN): 137 unik, 57 duplikat, 0 konflik label (bias kalibrasi)
- **MCP / stdio adapter** (WARN): ada di working tree tetapi belum tracked
- **MCP / Konsistensi dokumen** (FAIL): README bilang belum, integration guide bilang sudah
- **MCP / SSE (kode)** (WARN): kode ada; perilaku streaming belum diverifikasi
- **Security / Groq key revocation** (FAIL): dokumen insiden masih menyatakan revocation pending
- **Security / Binary tracked** (FAIL): tracked: server=19MB
- **Security / Binary untracked** (WARN): server_new=19MB, tidak di-ignore
- **Documentation / Link internal rusak** (WARN): 2 link; contoh: README.md -> docs/ARCHITECTURE.md; mcp-gateway/docs/workspace-alignment.md -> ../WORKSPACE_DIRECTION.md
- **Documentation / README -> docs/ARCHITECTURE.md** (FAIL): dirujuk tetapi file tidak ada
- **Documentation / Dokumen status ganda** (WARN): PROJECT_CONTEXT.md, docs/ROADMAP.md, docs/IMPLEMENTATION_STATUS.md, STATUS.md
- **Quality Gates / Phase 1 smoke (v3)** (FAIL): phase1_smoke_v3_20261024T164559.452903Z.json phase1_pass=False human_review_complete=False

---
*Regenerate: `make status-report` atau `bash scripts/generate_status.sh`.*
