# Insiden: Groq API key di dua `.env.example`

**Tanggal ditemukan:** 2026-10-24
**Status repo:** containment selesai
**Status kredensial:** **revocation required — tindakan pemilik akun (belum dikonfirmasi)**

## Ringkasan

Dua file contoh environment memuat nilai yang cocok dengan pola kunci Groq
(`gsk_` + karakter alfanumerik):

- `.env.example` (root workspace)
- `arxiv-research-assistant/.env.example`

Nilai lengkap tidak dicatat di dokumen ini dan tidak dicetak selama remediasi.

## Dampak danhistory

- Nilai nyata hanya ada di **working tree** kedua file tersebut.
- `HEAD` kedua repo sudah memuat placeholder `gsk_your_actual_key_here`.
- Pemeriksaan `git grep` atas seluruh revisi untuk pola kunci nyata pada
  `.env.example` tidak menemukan kecocokan. Tidak ada key nyata di git history.
- Karena itu, history rewrite **tidak diperlukan** dan tidak dilakukan.

## Tindakan yang sudah dilakukan

1. Kedua baris `GROQ_API_KEY=` diganti kembali dengan placeholder
   `gsk_your_actual_key_here` tanpa mencetak nilai lama.
2. `bash scripts/check_secrets.sh` sekarang exit 0 dan mencetak `CLEAN`.
3. `arxiv-research-assistant/.env.example` kembali identik dengan `HEAD`
   (tidak ada diff).
4. Root `.env.example` masih memiliki perubahan WIP lain yang tidak terkait
   insiden ini; perubahan itu sengaja tidak di-commit di sini.

## Tindakan yang masih harus dilakukan pemilik akun

1. Buka Groq console dan **revoke** kedua key yang pernah ada di file tersebut.
2. Buat key baru dan simpan hanya di `.env` root (gitignored).
3. Jangan menempel key baru ke chat, issue, plan, atau file contoh.
4. Konfirmasi revocation agar insiden ini bisa ditutup.

## Pencegahan

- `scripts/check_secrets.sh` memindai root dan empat submodule untuk pola kunci.
- `scripts/test_check_secrets.sh` menguji scanner agar bisa gagal.
- CI dipindahkan ke branch `main` dan menjalankan scanner (Task 0.3).
- Jangan pernah mengisi nilai asli di `*.env.example`; gunakan placeholder yang
  dikenali scanner.
- Jangan menjalankan `docker compose config` tanpa filter: perintah itu
  meresolusi seluruh `.env` ke stdout, termasuk `GROQ_API_KEY`. Untuk daftar
  service gunakan `docker compose config --services`; untuk inspeksi penuh,
  saring dulu dengan `sed`/`grep -v`.
- `make status-report` hanya memakai `docker compose config --quiet` dan
  `--services`, sehingga tidak mencetak nilai rahasia.
