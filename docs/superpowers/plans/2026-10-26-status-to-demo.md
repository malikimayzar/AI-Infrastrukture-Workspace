# Dari STATUS ke Demo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menutup 6 FAIL yang tersisa di `STATUS.md`, lalu membuktikan produk bekerja lewat satu demo utuh dan satu refusal suite yang terukur.

**Architecture:** Perbaikan dibagi per pemilik repo (root workspace, `mcp-gateway`, `rag-research`) supaya commit tetap atomik. Setiap perubahan diverifikasi oleh `scripts/generate_status.sh`, bukan oleh klaim dokumen.

**Tech Stack:** Docker Compose, Bash, Go (Chi/Fiber), Python 3.12 (FastAPI), pytest, Prometheus.

**Spec:** `STATUS.md` (dibuat oleh `scripts/generate_status.sh`), `PROJECT_GOALS.md` §9, `docs/healthcare/INTENDED_USE.md`.

## Global Constraints

- Jangan `make down`, `docker compose down`, `docker rm`, atau stop/kill container tanpa konfirmasi eksplisit.
- Jangan membaca atau menulis `.env`; jangan mencetak nilai secret. `docker compose config` penuh meresolusi `.env` — pakai `--services`/`--quiet`.
- Jangan `git add -A`/`git add .`; commit per path, tanpa push.
- Submodule: prefix commit `opencode:`; root: conventional commit (`fix:`, `chore:`, `docs:`).
- Status hanya boleh berubah karena eksekusi: jalankan `make status-report` setelah setiap bagian.

## Review Focus

- Build image bisa berhenti lama di unduhan Hugging Face tanpa progress yang terlihat; kegagalan di sini tidak boleh membuat `rag-api` melayani tanpa kalibrasi.
- Recreate `rag-api` memakai image lama akan menghapus kalibrasi tanpa error; `Container punya model` di STATUS harus FAIL, bukan lolos.
- `make demo` yang bergantung pada Groq bisa flaky; demo harus punya output tersimpan agar bisa ditunjukkan tanpa jaringan.
- Refusal suite yang hanya mengukur "menolak" akan mendorong abstention berlebihan; dua arah wajib diukur.
- Perubahan trigger CI bisa mematikan pipeline tanpa disadari; verifikasi dengan `gh workflow view`/run nyata, bukan hanya grep.

---

## Bagian 0 — Menyelesaikan kalibrasi di image (sedang berjalan)

**Files:** `rag-research/Dockerfile`, `docker-compose.yml`

**Interfaces:**
- Consumes: `scripts/fit_calibration.py`, `data/evaluation/calibration_dataset.json`
- Produces: image `ai-infra-workspace-rag-api:latest` berisi `/app/models/calibration_isotonic.joblib`

- [ ] **Step 1: Tunggu build selesai**

Run: `pgrep -af "compose build" || echo FINISHED`
Expected: `FINISHED` dan `tail -3 /tmp/opencode/rag-build.log` menunjukkan `DONE` untuk semua langkah.

- [ ] **Step 2: Recreate hanya rag-api**

Run: `docker compose up -d --no-deps rag-api`
Expected: `Container ws-rag-api Recreated` (bukan `Running`).

- [ ] **Step 3: Verifikasi model di dalam container**

Run: `docker exec ws-rag-api ls -l /app/models && docker logs ws-rag-api 2>&1 | grep "Calibration model loaded"`
Expected: `calibration_isotonic.joblib` ada; satu baris log `Calibration model loaded`.

- [ ] **Step 4: Regenerasi STATUS**

Run: `make status-report`
Expected: `Container punya model` PASS, `Container memuat model` PASS.

**Done when:** keempat check kalibrasi PASS dan `rag-api` tetap healthy.

---

## Bagian 1 — Menutup sisa FAIL (mekanis, 1 sesi)

**Files:** `.github/workflows/*`, `mcp-gateway/README.md`, `mcp-gateway/.gitignore`, `docs/ARCHITECTURE.md`, `docs/security/2026-10-24-groq-key-exposure.md`

### Task 1.1 — CI berjalan di branch yang benar

- [ ] Ubah trigger workflow dari `[main]` ke `[master, remediation/2026-10-24]` (default branch nyata adalah `master`).
- [ ] Run: `git branch -a` → konfirmasi `origin/HEAD -> origin/master`.
- [ ] Verifikasi: buka tab Actions setelah commit, atau `gh run list --limit 3`.
- [ ] Expected: `STATUS.md` → `CI trigger cocok dengan default branch` PASS.

### Task 1.2 — Hapus binary dari index

- [ ] Run: `git -C mcp-gateway rm --cached server`
- [ ] Tambahkan `server` dan `server_new` ke `mcp-gateway/.gitignore`.
- [ ] Run: `git -C mcp-gateway status --short` → tidak ada binary baru.
- [ ] Expected: `Security / Binary tracked` PASS; `Binary untracked` hilang.

### Task 1.3 — `docs/ARCHITECTURE.md`

- [ ] Tulis 1 halaman: 5 service, tanggung jawab, alur request gateway→rag→eval, batas data.
- [ ] Run: `test -f docs/ARCHITECTURE.md && grep -c "mcp-gateway" docs/ARCHITECTURE.md`
- [ ] Expected: `Language / README -> docs/ARCHITECTURE.md` PASS.

### Task 1.4 — Satu kebenaran soal MCP stdio

- [ ] Pilih satu status (sudah ada kode + Makefile target ⇒ dokumentasikan sebagai implemented).
- [ ] Perbarui `mcp-gateway/README.md` agar tidak lagi menulis `not implemented yet`.
- [ ] Track `cmd/mcp-stdio-adapter/` (saat ini untracked).
- [ ] Run: `make mcp-stdio-up && make mcp-stdio-down` (butuh izin: start container baru).
- [ ] Expected: `MCP / Konsistensi dokumen` PASS; `MCP / stdio adapter` PASS.

### Task 1.5 — Revocation key (tindakan pemilik akun)

- [ ] Revoke 2 key lama di Groq console; rotasi key aktif (pernah tercetak di log).
- [ ] Perbarui baris status di dokumen insiden menjadi `revoked <tanggal>`.
- [ ] Run: `bash scripts/check_secrets.sh`
- [ ] Expected: `Security / Groq key revocation` PASS.

### Task 1.6 — Gate Phase 1

- [ ] Ekspor blind review: `cd rag-research && python scripts/export_phase1_blind_review.py`
- [ ] Isi adjudikasi manusia (bukan otomatis), lalu jalankan ulang smoke v3.
- [ ] Expected: artefak terbaru `phase1_pass=true` dan `human_review_complete=true`.
- [ ] Catatan: ini satu-satunya FAIL yang butuh penilaian manusia; jangan diakali dengan mengedit JSON.

**Done when:** `bash scripts/generate_status.sh --strict` → exit 0.

---

## Bagian 2 — Bukti produk (P0)

**Files:** `Makefile`, `scripts/demo.sh`, `rag-research/tests/data/refusal_suite.jsonl`, `docs/DEMO.md`

### Task 2.1 — `make demo`

- [ ] Skrip: ingest 1 paper → 1 query terjawab → 1 query ditolak → tulis `demo_output/dossier.md`.
- [ ] Simpan respons mentah (JSON) agar demo bisa ditunjukkan tanpa Groq hidup.
- [ ] Run: `make demo`
- [ ] Expected: dossier berisi jawaban + span bukti + confidence + zona; query off-domain → `REJECT`.

### Task 2.2 — Refusal suite

- [ ] 30 query harus-ditolak + 30 harus-dijawab, masing-masing dengan `expected_decision`.
- [ ] Skrip mengukur `false_answer_rate` dan `false_refusal_rate`, tulis `demo_output/refusal_report.json`.
- [ ] Run: `make refusal-suite`
- [ ] Expected: dua angka tercetak; target awal `false_answer_rate ≤ 0.10`, `false_refusal_rate ≤ 0.20` (ditetapkan sebelum melihat hasil).

**Done when:** dua artefak ada dan angkanya bisa dikutip di README tanpa kualifikasi.

---

## Bagian 3 — Kesiapan domain healthcare

**Files:** `docs/healthcare/*`, 5 dokumen root

- [ ] Review `INTENDED_USE.md` → apply 5 edit root (`README.md`, `PROJECT_GOALS.md`, `PROJECT_CONTEXT.md`, `AGENTS.md`, `docs/business/product-strategy.md`).
- [ ] Konfirmasi payer mix RS (JKN vs asuransi swasta) → pilih modul pertama.
- [ ] Uji 50 catatan klinis Indonesia: normalisasi singkatan, negasi, OCR PDF scan.
- [ ] Bandingkan `all-MiniLM-L6-v2` vs model multilingual pada 20 query berlabel; catat retrieval hit rate.
- [ ] Tulis `docs/healthcare/PILOT_CHARTER.md` + daftar pertanyaan discovery Casemix Manager.

**Done when:** ada keputusan tertulis modul pertama + baseline retrieval pada teks Indonesia.

---

## Bagian 4 — Rilis

- [ ] `v0.1.0` + `CHANGELOG.md`.
- [ ] CI clone bersih: clone → `make up` → `make demo` < 10 menit.
- [ ] Konsolidasi dokumen: satu `STATUS.md`, satu `ROADMAP.md`; arsipkan plan/report generated.

**Done when:** tag ada dan clone bersih lolos tanpa langkah manual.
