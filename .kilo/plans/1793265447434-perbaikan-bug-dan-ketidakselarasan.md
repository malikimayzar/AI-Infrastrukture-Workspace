# Plan: Perbaikan Bug dan Ketidakselarasan Sistem (Sebelum Improve)

## Goal
Mengatasi semua bug konkret dan ketidakselarasan yang tercatat di STATUS.md / STATUS.json serta ditemukan dari review kode, sebelum melakukan improve fitur baru. Target: nol FAIL di status report, smoke E2E lolos, dan dokumen status sinkron.

## Conteks (baseline dari inspeksi)

- **STATUS.md** (2026-10-28): 37 PASS, 3 WARN, **1 FAIL**, 1 SKIP, 4 INFO
- **STATUS.json** (2026-10-26): 29 PASS, 7 WARN, **6 FAIL**, 1 SKIP, 4 INFO
- Kedua dokumen status tidak sinkron (STATUS.md lebih baru tapi kurang FAIL; STATUS.json lebih lama tapi lebih banyak FAIL)
- `docker-compose.yml` sudah diubah (`git status`: modified) dan ada `docker-compose.yml.bak` tidak terlacak
- 4 submodule: arxiv-research-assistant, mcp-gateway, rag-research, llm-eval-framework
- Stack: Docker Compose Mode A (root), host ports 8090/8080/8001/8002/8000/5432/6333/11435

## Bug & Ketidakselarasan yang Ditemukan (diurutkan prioritas)

### P0 — Keamanan & Integritas Repo (harus dulu)

| # | Masalah | Lokasi | Bukti |
|---|---------|--------|-------|
| P0-1 | `maskDSN()` tidak memaskir password — DSN (termasuk password) ditulis ke log plaintext | `mcp-gateway/cmd/server/main.go:142-149` | Fungsi mengembalikan `dsn` tanpa perubahan |
| P0-2 | Binary `server` (19MB) terlacak di git; `server_new` tidak di-.gitignore | Root workspace | `STATUS.json` Security FAIL / WARN |
| P0-3 | Revokasi kunci Groq masih tertunda di dokumen insiden | Dokumen security | `STATUS.json` Security FAIL |
| P0-4 | Mismatch branch CI vs default: CI `main`, default `master` | `.github/workflows/` | `STATUS.json` Repository FAIL |

### P1 — Status Report & Dokumentasi (sinkronisasi)

| # | Masalah | Lokasi | Bukti |
|---|---------|--------|-------|
| P1-1 | STATUS.md dan STATUS.json tidak sinkron (jumlah FAIL berbeda) | Root | STATUS.md 1 FAIL vs STATUS.json 6 FAIL |
| P1-2 | Fase 1 smoke gagal: `phase1_pass=false`, `human_review_complete=false` | `scripts/generate_status.sh`, `results/metrics/` | Keduanya FAIL |
| P1-3 | Konsistensi dokumen MCP: README bilang belum, integration guide bilang sudah | `mcp-gateway/README.md`, `mcp-gateway/docs/` | `STATUS.json` MCP FAIL |
| P1-4 | SSE streaming kode ada tapi perilaku tidak diverifikasi | `mcp-gateway/internal/mcp/handler.go` | `STATUS.json` SSE WARN |
| P1-5 | Link internal rusak: `README.md -> docs/ARCHITECTURE.md` (tidak ada); `mcp-gateway/docs/workspace-alignment.md -> ../WORKSPACE_DIRECTION.md` (tidak ada) | Root + mcp-gateway | `STATUS.json` Documentasi WARN/FAIL |
| P1-6 | Dokumen status ganda (PROJECT_CONTEXT.md, docs/ROADMAP.md, STATUS.md) berisiko divergen | Root | `STATUS.md` Documentation WARN |

### P2 — Bug Fungsional (perilaku sistem)

| # | Masalah | Lokasi | Bukti |
|---|---------|--------|-------|
| P2-1 | Deteksi abstensi RAG tidak cocok: gateway cek `ArxivAbstainText="Not found in context."` tapi RAG API mengembalikan `"The available information is not sufficient to provide a reliable answer."`; `RAGAbstainText="INSUFFICIENT_CONTEXT"` didefinisikan tapi **tidak pernah digunakan** | `mcp-gateway/internal/api/contract.go:30-31`, `respond.go:64-66`; `rag-research/src/api/main.py:377` | Abstensi RAG mungkin ditandai sebagai jawaban sukses |
| P2-2 | Ambang kalibrasi tidak konsisten: PROJECT_GOALS.md §6 bilang reject=0.35, partial=0.70; tapi `config.py` default 0.25/0.65 dan `confidence_engine.py` 0.35/0.65 | `PROJECT_GOALS.md:196-204`; `rag-research/src/api/config.py:76-77,81-82`; `rag-research/src/controller/confidence_engine.py:37-46` | Zona kepercayaan tidak sesuai spesifikasi |
| P2-3 | `docker-compose.yml` dimodifikasi tapi belum di-commit; ada `.bak` | Root `git status` | `M docker-compose.yml`, `?? docker-compose.yml.bak` |

### P3 — Reliabilitas Infra (rendah prioritas, setelah P0-P2)

| # | Masalah | Lokasi |
|---|---------|--------|
| P3-1 | `REDIS_URL` menunjuk ke `redis:6379` meski Redis opt-in (`REDIS_ENABLED=false`); jika kode mencoba konek saat Redis mati bisa error startup | `docker-compose.yml:302`, `rag-research/src/api/cache.py` |
| P3-2 | `rag-api` dan `llm-eval-framework` bergantung pada `ollama` `service_healthy` meski Groq adalah provider utama | `docker-compose.yml:311-315, 212-214` |

## Ordered Tasks

### Fase A: Perbaikan P0 (Keamanan & Repo) — Sebelum apa pun

1. **Selesaikan mismatch branch CI**
   - Periksa `.github/workflows/test.yml` dan `check-secrets.yml`; samakan trigger branch dengan default branch (`master` atau ganti default menjadi `main` — pilih satu dan konsisten di semua workflow)
   - Validasi: `git diff` workflow tidak ada mismatch `main` vs `master`

2. **Hapus binary `server` dari pelacakan git**
   - `git ls-files | grep -E '(^|/)server$'` untuk menemukan path
   - `git rm --cached <path>`; tambahkan pattern ke `.gitignore`
   - Cek binary lain: `git ls-files | grep -E '\.(bin|exe)$'`
   - Validasi: `git status` hanya perubahan yang diinginkan; tidak ada binary baru terlacak

3. **Perbaiki `maskDSN()` agar memaskir password**
   - Ubah fungsi di `mcp-gateway/cmd/server/main.go:142-149` untuk mengganti password dengan `***`
   - Validasi: log startup tidak mencakup password asli (cek output log atau unit test)

4. **Selesaikan revokasi kunci Groq di dokumen insiden**
   - Jalankan `scripts/rotate_key.sh` (atau validasi saja dengan `DRY=1`) jika key perlu diganti
   - Perbarui dokumen insiden/security: tanggal, prefix kunci baru, bukti revoke
   - Validasi: grep dokumen tidak lagi menyatakan "revocation pending"; `make check-secrets` CLEAN

### Fase B: Perbaikan P1 (Status & Dokumen)

5. **Sinkronkan STATUS.md dengan STATUS.json**
   - Jalankan `bash scripts/generate_status.sh` (atau `make status-report`) untuk menghasilkan STATUS.md terbaru dari eksekusi nyata
   - Pastikan jumlah FAIL/WARN di kedua dokumen konsisten (STATUS.json harus di-regenerate atau diarkip)
   - Validasi: `make status-report` exit 0; STATUS.md mencerminkan kondisi nyata

6. **Perbaiki Fase 1 smoke agar PASS**
   - Identifikasi penyebab `phase1_pass=false` dan `human_review_complete=false` dari `results/metrics/phase1_smoke_v3.json`
   - Jalankan `make smoke-e2e` dan perbaiki query yang gagal
   - Lakukan human review 15 case answerable jika kuota Groq cukup
   - Validasi: `phase1_pass=true`, `human_review_complete=true`, smoke E2E PASS

7. **Selesaikan konsistensi dokumen MCP**
   - Tentukan sumber kebenaran: apakah MCP JSON-RPC 2.0 sudah selesai atau belum (TODO.md dan PROJECT_GOALS.md bilang completed; README bilang belum)
   - Perbarui README atau integration guide agar tidak bertentangan
   - Validasi: tidak ada pernyataan bertentangan tentang status MCP di dokumen

8. **Verifikasi SSE streaming runtime**
   - Uji endpoint MCP dengan header `Accept: text/event-stream` pada minimal 1 tool
   - Verifikasi event valid dan tidak hang; catat hasil
   - Validasi: respons SSE valid, termination tepat waktu

9. **Perbaiki link internal rusak**
   - Buat `docs/ARCHITECTURE.md` atau perbaiki target link di `README.md`
   - Perbaiki target `mcp-gateway/docs/workspace-alignment.md` ke path yang benar
   - Validasi: `make check-secrets` dan pengecekan link internal tidak menemukan link rusak

10. **Konsolidasikan dokumen status**
    - Tetapkan satu source of truth (docs/ROADMAP.md); PROJECT_CONTEXT.md dan STATUS.md jadi referensi saja
    - Validasi: tidak ada klaim status bertentangan di antara ketiga dokumen

### Fase C: Perbaikan P2 (Bug Fungsional)

11. **Perbaiki deteksi abstensi RAG di gateway**
    - Di `mcp-gateway/cmd/server/respond.go`, tambah pemeriksaan untuk teks abstensi RAG asli (`"The available information is not sufficient to provide a reliable answer."`) dan gunakan `RAGAbstainText` yang sudah didefinisikan tapi belum dipakai
    - Validasi: request ke RAG dengan konteks tidak cukup menghasilkan `decision="abstain"` dan `failure_type="insufficient_context"` di gateway

12. **Sinkronkan ambang kalibrasi dengan dokumentasi**
    - Pilih satu nilai: ikuti PROJECT_GOALS.md §6 (reject=0.35, partial=0.70) atau perbarui dokumentasi agar cocok dengan `config.py` (0.25/0.65)
    - Perbarui `config.py`, `confidence_engine.py`, dan `calibrated_confidence_engine.py` agar konsisten
    - Validasi: endpoint `/generate` mengembalikan `calibrated_decision` sesuai zona yang diharapkan

13. **Commit perubahan `docker-compose.yml` dan hapus `.bak`**
    - Review `git diff docker-compose.yml`; pastikan perubahan sengaja
    - `git add docker-compose.yml` dan commit; hapus `docker-compose.yml.bak` atau tambahkan ke `.gitignore`
    - Validasi: `git status` bersih dari file yang tidak terkait

### Fase D: Perbaikan P3 (Infra) — Opsional, setelah P0-P2 selesai

14. **Opsi: keluarkan `ollama` dari `depends_on` layanan yang menggunakan Groq utama** (atau ubah ke `condition: service_started` bukan `service_healthy`)
    - Validasi: stack masih naik meski ollama lama siap

15. **Opsi: jaga `REDIS_URL` hanya diakses saat `REDIS_ENABLED=true`**
    - Validasi: rag-api startup tidak error saat Redis tidak berjalan

## Validation Gate (Definisi Selesai)

- `make check-secrets` = CLEAN (exit 0)
- `make smoke-e2e` = PASS
- STATUS report tidak memiliki FAIL baru; semua P0-P2 teratasi
- `git status` hanya berisi perubahan yang disengaja (tidak ada binary terlacak, tidak ada `.bak`)
- Semua link internal valid (0 link rusak)
- MCP dokumen tidak berselisih tentang status implementasi

## Risks & Blockers

- Kuota Groq habis → smoke E2E gagal provider error; mitigation: kerjakan P0 dan P1 dulu, rerun smoke setelah kuota reset
- Mode A/B port conflict → pastikan tidak ada Mode B berjalan sebelum `make up`
- Human review Fase 1 memakan waktu; script auto-save sehingga bisa bertahap
- Ubah ambang kalibrasi dapat mengubah perilaku abstensi; perlu uji ulang query setelah perubahan

## Out of Scope (tidak dalam rencana ini)

- Phase 4 UI (Claim Audit UI), multi-tenant, SSO
- Ekspansi dataset >= 500 baris, tuning retrieval/RRF
- Perubahan arsitektur atau fitur baru di luar perbaikan bug

## Open Questions (perlu konfirmasi pengguna)

1. Default branch yang diinginkan: `master` (kini) atau `main`? Rekomendasi: pilih satu dan samakan semua workflow CI.
2. Apakah kunci Groq perlu rotasi segera, atau cukup memperbarui dokumen insiden? Rekomendasi: rotasi jika ada indikasi kompromi, else update dokumen saja.
3. Ambang kalibrasi yang diadopsi: 0.35/0.70 (dokumen) atau 0.25/0.65 (kode)? Rekomendasi: ikuti PROJECT_GOALS.md §6 (0.35/0.70) karena merupakan spesifikasi resmi.
4. Apakah rencana ini boleh dieksekusi oleh agent implementasi, atau hanya untuk review pengguna terlebih dahulu?

EOF
