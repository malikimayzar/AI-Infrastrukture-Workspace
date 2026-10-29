# Project Status

> **Generated:** 2026-10-29T17:39:17+07:00
> **Commit:** dd44e70
> **Branch:** remediation/2026-10-24
> **Working tree:** 2 perubahan

> File ini di-generate oleh `scripts/generate_status.sh` dari eksekusi nyata.
> Jangan edit manual — jalankan ulang generatornya.

## Ringkasan

| Status | Jumlah |
|---|---:|
| ✅ PASS | 32 |
| ⚠️ WARN | 2 |
| ❌ FAIL | 2 |
| ⏭️ SKIP | 1 |
| ℹ️ INFO | 9 |

**Cara membaca:** PASS = diverifikasi oleh eksekusi; WARN = perlu perhatian; FAIL = klaim belum didukung; SKIP = prasyarat tidak tersedia; INFO = konteks.

**Build & Tests** secara default hanya menghitung test yang terkumpul; jalankan `--full` untuk benar-benar mengeksekusi suite.

## Repository

| Check | Status | Evidence |
|---|---|---|
| Release tags | ✅ PASS | 1 tag |
| Default branch | ℹ️ INFO | master |
| CI trigger cocok dengan default branch | ✅ PASS | branches: [main, master] branches: [main, master, remediation/2026-10-24, "remediation/**"]  |
| Submodule sinkron | ✅ PASS | 4 submodule |

## Build & Tests

| Check | Status | Evidence |
|---|---|---|
| arxiv Go — collected | ✅ PASS | 22 test |
| mcp-gateway — collected | ✅ PASS | 197 test |
| arxiv python-ml — collected | ✅ PASS | 48 test |
| llm-eval — collected | ✅ PASS | 228 test |
| rag-research — collected | ✅ PASS | 526 test |
| Test suite penuh | ⏭️ SKIP | jalankan dengan --full untuk mengeksekusi |

## Runtime

| Check | Status | Evidence |
|---|---|---|
| Compose valid | ✅ PASS | 8 core; 12 dengan profile |
| mcp-gateway | ℹ️ INFO | http://localhost:8090/health tidak merespons (mungkin tidak berjalan) |
| arxiv-go-backend | ℹ️ INFO | http://localhost:8080/health tidak merespons (mungkin tidak berjalan) |
| arxiv-python-ml | ℹ️ INFO | http://localhost:8001/health tidak merespons (mungkin tidak berjalan) |
| llm-eval-framework | ℹ️ INFO | http://localhost:8002/health tidak merespons (mungkin tidak berjalan) |
| rag-api | ℹ️ INFO | http://localhost:8000/health tidak merespons (mungkin tidak berjalan) |

## Calibration

| Check | Status | Evidence |
|---|---|---|
| Model file | ✅ PASS | calibration_isotonic.joblib (14550 bytes) |
| Model dapat dimuat | ✅ PASS | method=isotonic fitted=True samples=151 |
| Image menyediakan models/ | ✅ PASS | model di-fit saat build (fit_calibration.py) |
| Compose punya env kalibrasi | ✅ PASS | CALIBRATION_METHOD CALIBRATION_MODEL_PATH  |
| .env.example punya variabel kalibrasi | ✅ PASS | CALIBRATION_METHOD CALIBRATION_MODEL_PATH  |
| Model vs dataset | ✅ PASS | 151 sampel = 151 baris dataset |
| Container punya model | ❌ FAIL | file tidak ada di container — runtime fallback |
| Container memuat model | ✅ PASS | log startup: Calibration model loaded |

## Datasets

| Check | Status | Evidence |
|---|---|---|
| Rows | ℹ️ INFO | 151 baris (declared 151) |
| Jumlah baris cocok | ✅ PASS | 151 = declared 151 |
| Baris dikeluarkan | ✅ PASS | 6 baris dikeluarkan dari fitting |
| Label is_supported | ✅ PASS | 151/151 berlabel |
| Unique queries | ✅ PASS | 151 unik |
| Baris ERROR | ✅ PASS | 0 |
| Probe negatif off-domain | ✅ PASS | 10 probe, semuanya is_supported=false (disengaja) |
| ground_truth (opsional) | ℹ️ INFO | 13/151 baris punya teks referensi; label utama = is_supported |

## MCP

| Check | Status | Evidence |
|---|---|---|
| HTTP handler | ✅ PASS | internal/mcp/handler.go ada |
| stdio adapter | ✅ PASS | ada dan tracked |
| Konsistensi dokumen | ✅ PASS | tidak ada kontradiksi terdeteksi |
| SSE (kode) | ⚠️ WARN | kode ada; perilaku streaming belum diverifikasi |

## Security

| Check | Status | Evidence |
|---|---|---|
| Secret scan | ✅ PASS | scripts/check_secrets.sh bersih |
| .env di-gitignore | ✅ PASS | .env tidak akan ter-commit |
| Groq key revocation | ✅ PASS | tidak ada status pending di dokumen insiden |
| Binary tracked | ✅ PASS | tidak ada binary besar yang tracked |

## Documentation

| Check | Status | Evidence |
|---|---|---|
| Jumlah file .md | ℹ️ INFO | 217 |
| Link internal rusak | ✅ PASS | 0 link rusak |
| README -> docs/ARCHITECTURE.md | ✅ PASS | tidak dirujuk |
| Dokumen status ganda | ⚠️ WARN | PROJECT_CONTEXT.md, docs/ROADMAP.md, STATUS.md |

## Quality Gates

| Check | Status | Evidence |
|---|---|---|
| Phase 1 smoke (v3) | ❌ FAIL | phase1_smoke_v3_20261028T193637.907257Z.json phase1_pass=False human_review_complete=True |
| Laporan kalibrasi | ✅ PASS | models/calibration_report.json n=151 (isotonic, platt) |

## Gap yang perlu ditutup

- **Calibration / Container punya model** (FAIL): file tidak ada di container — runtime fallback
- **MCP / SSE (kode)** (WARN): kode ada; perilaku streaming belum diverifikasi
- **Documentation / Dokumen status ganda** (WARN): PROJECT_CONTEXT.md, docs/ROADMAP.md, STATUS.md
- **Quality Gates / Phase 1 smoke (v3)** (FAIL): phase1_smoke_v3_20261028T193637.907257Z.json phase1_pass=False human_review_complete=True

---
*Regenerate: `make status-report` atau `bash scripts/generate_status.sh`.*
