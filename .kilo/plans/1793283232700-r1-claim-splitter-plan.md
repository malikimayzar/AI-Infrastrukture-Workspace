# Plan: R-1 claim splitter (verifikasi) + urutan pelaksanaan P0 berikutnya

## Tujuan
Verifikasi bahwa R-1 claim splitter (deterministik, non-LLM) sudah lengkap sesuai `docs/vertical-1/GOALS-PER-REPO.md` §2, lalu tentukan tugas konkret berikutnya dalam urutan dependensi P0 (T1→T5).

## Status saat ini — R-1 sudah SELESAI
Berkas berikut sudah ada dan sudah di-commit (tidak ada perubahan yang perlu dilakukan):
- `rag-research/src/utils/claim_splitter.py` — `split_claims(text)`: deterministik, non-LLM, batas kalimat pada tanda baca `.!?`, normalisasi whitespace, input kosong/`None` → `[]`.
- `rag-research/tests/test_claim_splitter.py` — 6 uji: empty, single sentence, determinisme (input identik → output identik), multiple sentences, no-terminator (satu claim), whitespace normalized.

Ketergantungan R-1: tidak ada (boleh dibangun paling awal). ✅ Terpenuhi.

## Urutan pelaksanaan P0 (per GOALS-PER-REPO §7)
```
T1: rag-research R-1..R-4   (fondasi; tanpa ini evaluator & gateway buta)
T2: arxiv A-1..A-2          (paralel aman, kecil)
T3: eval E-1..E-2           (terkunci ke R; E-3 offline boleh mendampingi)
T4: gateway G-1..G-3        (persistensi + REST, terkunci ke R/E/A)
T5: gateway G-4..G-6        (share link + dossier sungguhan + smoke)
```

Status T1 rag-research:
- R-1 claim splitter ✅ selesai
- R-2 `POST /verify_claim` ✅ selesai (kontrak terkunci, commit `a6e2eb2`)
- R-3 `POST /verify_claims` batch ✅ selesai (concurrency + isolasi kegagalan, belum di-commit di working tree)
- R-4 kontrak test schema ✅ selesai (17 test, belum di-commit di working tree)
→ T1 rag-research secara fungsional sudah tuntas, namun perubahan `src/api/main.py` dan `tests/test_verify_claim_contract.py` masih belum di-commit.

## Tugas konkret selanjutnya (disarankan)
Karena R-1 sudah selesai, tugas berikutnya dalam urutan dependensi adalah **T2 arxiv A-1: `GET /papers/source/{arxiv_id}`** (§4.7) — mengembalikan `{source_id, title, authors[], year, url}`, 404 untuk id tak dikenal, batch stage ≤ 100 id.

### Bentrok yang perlu diatasi sebelum mulai A-1
`arxiv-research-assistant/go-backend/internal/api/papers_test.go` sedang diubah (belum di-commit, terlihat di `git status` root sebagai submodule `m`). Ini kemungkinan merupakan pekerjaan dalam proses agen lain. Sebelum menyentuh A-1:
1. Konfirmasikan ke pemilik perubahan apakah `papers_test.go` sedang dikerjakan.
2. Jika iya → jangan sentuh `arxiv-research-assistant`; pilih tugas P0 lain yang tidak bentrok (mis. `G-3 export.md` render per-klaim di `mcp-gateway/cmd/server/reports.go`, atau `E-1/E-2/E-3` eval di `llm-eval-framework`).
3. Jika bukan → commit atau reset `papers_test.go` terlebih dahulu, baru implementasi A-1.

### Alternatif jika A-1 diblokir bentrok
- **G-3** `export.md` render per-klaim (zona, evidence, sitasi, blok evaluasi) — masih stub 1-baris di `mcp-gateway/cmd/server/reports.go`. Catatan: `reports.go` sudah memiliki perubahan +72 baris yang belum di-commit (belum diketahui siapa pemilik), periksa kepemilikan sebelum edit.
- **W-1** `make smoke-reports` — target sudah ada di `Makefile`, perlu verifikasi jalur POST `/reports` → export → `/r/{token}` secara live.

## Validasi (gate R-1 & P0)
- Jalankan `python -m pytest tests/test_claim_splitter.py -q` di `rag-research` (harus 6/6 pass); pastikan determinisme & batas tanda baca terpenuhi.
- Pastikan suite rag-research tidak berkurang dari baseline 492 (targeted test saat iterasi; `make test-rag` saat tuntas).
- `make check-secrets` harus CLEAN sebelum setiap commit.
- Tidak ada file `.env` yang dibaca/ditulis; tidak ada container yang dihentikan; tidak ada push (commit lokasi, lapor hash ke integrator).

## Keputusan yang belum terpecahkan
1. Siapa pemilik perubahan uncommitted di `arxiv-research-assistant` (`papers_test.go`) dan `mcp-gateway` (`reports.go`, migrasi 005/006, `audit_test.go`)? Perlu di-resolve sebelum overlapped edit.
2. Apakah tugas berikutnya difokuskan ke A-1 (arxiv), G-3 (export.md), atau E (eval)?

Jika A-1 diblokir karena bentrok, ganti ke G-3 atau E tanpa mengubah struktur plan ini.
