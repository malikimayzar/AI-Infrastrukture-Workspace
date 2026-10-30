# Plan: Hari Ini — Tutup Phase 1 Acceptance + Hygiene Foundational

## Goal
Menutup gap Phase 1 yang memblokir klaim production-ready: smoke E2E root, Phase 1 rag smoke dengan review manusia, model kalibrasi di container, penghapusan binary tracked, revocation Groq key, sinkron submodule, dan refresh status dokumen. Semua perubahan tetap dalam batas repo tanpa menambah fitur baru.

## Scope
- Root workspace + submodule `rag-research`, `mcp-gateway`, `arxiv-research-assistant`, `llm-eval-framework`.
- Fokus hari ini: acceptance & hygiene, bukan Phase 4 UI atau ekspansi dataset besar.

## Preflight (wajib sebelum eksekusi)
1. `make status` (atau `bash scripts/generate_status.sh`) untuk baseline.
2. `git status --short` + `git submodule status` untuk memastikan perubahan existing tidak tertimpa.
3. `make check-secrets` harus CLEAN sebelum commit apa pun.
4. Pastikan stack berjalan (`make up`) dan health semua service OK; jika Mode B aktif, stop dulu (port conflict).
5. Cek kuota Groq dengan satu request kecil; jika 429, tunda smoke full dan kerjakan task hygiene dulu.

## Ordered Tasks

### 1. Sinkronisasi submodule & branch CI
- `git submodule update --init --recursive`
- Verifikasi `git submodule status` (semua hash cocok).
- Samakan trigger CI (`.github/workflows/test.yml`, `check-secrets.yml`) agar tidak mismatch `main` vs `master`.
- Validasi: `git diff --submodule` kosong setelah sync.

### 2. Hapus binary tracked (`server`)
- Temukan path: `git ls-files | grep -E '(^|/)server$'`.
- `git rm --cached <path>` lalu tambahkan path/pattern ke `.gitignore`.
- Pastikan tidak ada file binary lain: `git ls-files | grep -E '\.(bin|exe)$'`.
- Validasi: `make check-secrets` CLEAN + `git status` hanya perubahan yang diharapkan.

### 3. Model kalibrasi tersedia di container (rag-research)
- Inspeksi `rag-research/Dockerfile` dan compose env (`CALIBRATION_METHOD`, `CALIBRATION_MODEL_PATH`).
- Pastikan `models/calibration_isotonic.joblib` disalin ke image (bukan hanya host).
- Rebuild image rag-api dan restart service: `docker compose --env-file .env build rag-api` lalu recreate.
- Verifikasi startup log: `Calibration model loaded`; `docker exec ws-rag-api ls -l $CALIBRATION_MODEL_PATH`.
- Validasi: endpoint `/generate` mengembalikan `is_calibrated=true` (atau log fallback tidak muncul).

### 4. Dokumen revocation Groq key
- Setelah rotasi key via `scripts/rotate_key.sh`, perbarui dokumen insiden (security docs) dengan tanggal, key prefix baru, dan bukti revoke.
- Pastikan `.env` tidak ter-commit; `make check-secrets` CLEAN.
- Validasi: grep insiden tidak lagi menyatakan "revocation pending".

### 5. Root E2E smoke test
- Jalankan `make smoke-e2e` (atau `bash scripts/smoke_e2e.sh`).
- Pastikan semua 4 verifikasi query log PASS (gateway arxiv, gateway rag, arxiv backend, negative check).
- Simpan RUN_ID dari output untuk audit trail.
- Validasi: script exit 0 dan `SMOKE TEST PASSED`.

### 6. Phase 1 smoke rag-research (runtime)
- Jika kuota Groq OK: `cd rag-research && PYTHONPATH=. python scripts/phase1_smoke.py` (20 case, 0 provider error target).
- Arsip otomatis report lama; catat path report baru.
- Jika ada provider error, hentikan, catat, dan tunda review sampai kuota reset (jangan tandai pass).

### 7. Human review Phase 1 (interaktif)
- `PYTHONPATH=. python scripts/phase1_smoke.py --review-report results/metrics/phase1_smoke_v3.json`
- Isi 15 case answerable (answer_correct, grounded, reviewer, failure categories bila gagal).
- Simpan setelah tiap case (script sudah auto-save).
- Validasi: `--check-report` mengembalikan `human_review_complete=true`.

### 8. Phase 1 gate check
- `PYTHONPATH=. python scripts/phase1_smoke.py --check-report results/metrics/phase1_smoke_v3.json`
- Target: `phase1_pass=true`, `quality_pass=true`, `provider_errors=0`, `confident_wrong_answers=0`, `correct_final_decisions>=18`.
- Jika gagal, catat query_id gagal dan kategori; jangan klaim pass.

### 9. SSE runtime verification
- Test endpoint dengan `Accept: text/event-stream` (minimal 1 tool) dan verifikasi stream event + termination.
- Catat hasil di docs/runbook atau status.
- Validasi: tidak hang, event valid, timeout sesuai.

### 10. Refresh status & dokumen
- Jalankan `bash scripts/generate_status.sh` (atau `make status-report`).
- Perbaiki link rusak: `mcp-gateway/docs/workspace-alignment.md` target `../docs/ROADMAP.md` (path relatif) dan `README.md -> docs/ARCHITECTURE.md`.
- Konsolidasikan klaim status: satu source of truth (ROADMAP.md); PROJECT_CONTEXT/STATUS hanya referensi.
- Validasi: status report menunjukkan Phase 1 smoke PASS dan tidak ada gap FAIL baru.

### 11. Release tag (hanya jika semua hijau)
- Setelah smoke root + Phase 1 pass + check-secrets CLEAN: `git tag -a v1.0.0 -m "Phase 1 acceptance complete"` (annotated).
- Push tag hanya jika user meminta (default: lokal saja).
- Validasi: `git describe --tags --always`.

## Validation Gate Hari Ini
- `make check-secrets` = CLEAN.
- `make smoke-e2e` = PASS.
- `phase1_pass=true` dan `human_review_complete=true` (jika kuota Groq memungkinkan).
- Status report tidak menambah FAIL baru; gap yang tersisa didokumentasikan dengan alasan.

## Risks & Blockers
- Kuota Groq habis → smoke full gagal provider error; mitigation: kerjakan hygiene dulu, rerun setelah reset kuota.
- Mode A/B conflict port → preflight wajib.
- Binary path mungkin tersebar di submodule; verifikasi `git ls-files` per repo.
- Review manusia memakan waktu; bisa dilanjutkan bertahap (script auto-save).

## Out of Scope Hari Ini
- Phase 4 UI, multi-tenant, SSO, ekspansi dataset >=500, tuning retrieval, dan perubahan arsitektur.
- Perubahan source code di luar yang diperlukan untuk acceptance/hygiene.

## Open Questions
1. Apakah human review Phase 1 dilakukan hari ini penuh (15 case) atau bertahap? Rekomendasi: penuh jika kuota OK, karena gate utama.
2. Tag rilis dibuat hari ini atau setelah verifikasi independen? Rekomendasi: setelah semua gate hijau + check-secrets CLEAN.
EOF
