# CONVENTIONS — Kolaborasi AI (Aider + OpenCode)

Dokumen ini adalah aturan main bersama untuk semua agen AI yang bekerja di
workspace ini. Baca sebelum mengubah kode.

## 1. Prinsip dasar

- **Satu penulis per file pada satu waktu.** Klaim tugas di `docs/ai-taskboard.md`
  sebelum mulai; tulis baris `LOCK` selama bekerja.
- **Root workspace** (`Makefile`, `docker-compose.yml`, pointer submodule,
  `PROJECT_*.md`) hanya ditulis oleh integrator (OpenCode).
- **Aider bekerja di dalam satu repo/submodule** dan **tidak push**.
- Perubahan kecil, commit atomik, prefix `aider:` atau `opencode:`.

## 2. Peta repo & perintah test

| Repo | Test | Catatan |
|---|---|---|
| `arxiv-research-assistant/go-backend` | `go test ./... -v` | — |
| `arxiv-research-assistant/python-ml` | `PYTHONPATH=. python -m pytest tests/ -v` | 19 test |
| `mcp-gateway` | `go test ./... -v -race` | — |
| `llm-eval-framework` | `python -m pytest tests/ -v` | — |
| `rag-research` | `python -m pytest tests/ -q` | ±2 menit; pakai targeted test saat iterasi |
| root (gate akhir) | `make test`, `make smoke-e2e`, `make check-secrets` | hanya integrator |

## 3. Larangan

- Jangan membaca/menulis `.env`; jangan pernah commit rahasia.
- Jangan `make down`, `docker compose down`, `docker rm`, atau menghentikan
  container — stack produksi sedang hidup.
- Jangan `git add -A` / `git add .`; sebutkan path secara eksplisit.
- Jangan push. Commit lokal saja, lalu serahkan hash ke integrator.
- Jangan mengubah file di luar scope tugas (termasuk file yang sedang dirty
  milik pengguna).
- Jangan upgrade/downgrade pin dependency global tanpa persetujuan; ikuti pin
  yang sudah ada di `requirements/`.

## 4. Gaya

- Kode & komentar mengikuti gaya file sekitarnya (mayoritas bahasa Inggris).
- Dokumen yang sudah berbahasa Indonesia tetap ditulis dalam bahasa Indonesia.
- Commit: `aider: <ringkas>` / `opencode: <ringkas>`; commit root memakai
  conventional style (`docs:`, `fix:`, `chore:`).

## 5. Definition of Done (setiap tugas)

1. Perubahan hanya di file scope.
2. Targeted test lulus; full suite dijalankan bila diminta.
3. `git status` tidak memuat file tak relevan.
4. Laporan: apa yang diubah, perintah test, hasil ringkas, risiko, commit hash.
5. Timebox habis / ambigu → **berhenti dan lapor**, jangan improvisasi.

## 6. Serah-terima

Aider selesai → laporkan commit hash + output test → OpenCode me-review diff,
menjalankan gate penuh (`make test`, `smoke-e2e` bila relevan), lalu
merge/push dan memperbarui pointer submodule di root.
