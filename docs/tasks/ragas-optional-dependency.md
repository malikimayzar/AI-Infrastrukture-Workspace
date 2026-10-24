# Arsip Tugas: Perbaikan dependensi opsional `ragas` di `rag-research`

> **Status:** Selesai menurut `docs/ai-taskboard.md` pada 2026-10-22
> (419 passed, 1 skipped). Dokumen ini mempertahankan brief dan prosedur historis;
> bukan tugas aktif. Buka kembali hanya jika kegagalan dependensi yang sama muncul lagi.

**Repo:** `rag-research` (submodule)
**Branch:** `ai/ragas-optional`
**Owner:** Aider
**Timebox:** 90 menit
**Integrator:** OpenCode (review + gate akhir + push)

---

## 1. Kondisi awal (terverifikasi 2026-10-20)

```
8 failed, 411 passed, 1 skipped (~2 mnt)
```

Kedelapan kegagalan berakar pada `ModuleNotFoundError: No module named 'ragas'`:

- `tests/test_ragas_importable.py` — 6 test
- `tests/test_ci_contracts.py::test_every_src_module_imports`
- `tests/test_scripts_load_env.py::test_run_eval_works_standalone`

Fakta environment:

- Test memakai venv root: `/home/malikimayzar/projects/ai-infra-workspace/venv`
  (Python **3.14.8**).
- `ragas` **tidak ter-pin** di file requirements mana pun.
- `langchain_core` juga **belum terpasang** di venv tersebut.
- `requirements/llm.txt` memuat pin: `langchain-community==0.4.1`,
  `langchain-core==1.6.6`, `langchain-groq==1.1.3`,
  `langchain-huggingface==1.2.2` (plus `langgraph` yang **tidak** dipakai kode).
- `requirements.txt` (root repo) mencatat kombinasi yang sudah terbukti:
  **ragas 0.2.15 + langchain-community 0.4.1 + langchain-core 1.6.6** — jangan
  mengubah pin ini tanpa bukti.
- Modul yang mengimpor ragas: `src/evaluation/ragas_evaluator.py`.

## 2. Tujuan

`python -m pytest tests/ -q` menghasilkan **0 failed**.

## 3. Pendekatan

### Opsi A — diutamakan: pasang & pin `ragas`

1. Baca `requirements.txt`, `requirements/llm.txt`, dan
   `requirements/dev.txt` untuk memahami pin yang ada.
2. Tambahkan `ragas==0.2.15` ke `requirements/llm.txt` (bagian evaluasi/LLM),
   dengan komentar singkat alasan pin.
3. Install ke venv root **tanpa menyentuh `langgraph`**:
   ```
   python -m pip install "ragas==0.2.15" \
     "langchain-community==0.4.1" "langchain-core==1.6.6" \
     "langchain-groq==1.1.3" "langchain-huggingface==1.2.2"
   ```
   Jika pip mencoba meng-upgrade/menurunkan pin lain secara bertentangan,
   **berhenti dan laporkan** — jangan paksa dengan `--force-reinstall`.
4. Verifikasi: `python -m pip check`.
5. Jalankan targeted test, lalu suite penuh.

### Opsi B — fallback (hanya jika Opsi A gagal karena konflik Python 3.14)

- Tambahkan skip terkelola (`pytest.importorskip("ragas")` atau setara) pada
  test yang membutuhkan `ragas`, termasuk guard di `test_ci_contracts` dan
  `test_scripts_load_env`.
- **Jangan** menghapus assertion inti; jangan membuat test selalu pass diam-diam.
- Dokumentasikan alasan + cara mengaktifkan kembali di komentar test dan di
  laporan akhir.
- Suite harus **0 failed** (skip diperbolehkan dan dihitung transparan).

## 4. Batasan

- Jangan mengubah kode produksi di `src/` kecuali benar-benar diperlukan.
- **Jangan menyentuh** `scripts/audit_k710_coverage.py` (sedang dirty milik
  pengguna).
- Jangan `git add -A`; tambahkan path eksplisit.
- Jangan push; commit lokal dengan prefix `aider:`.
- Jangan menjalankan Docker / `make down`.
- Jangan membaca `.env`.
- Timebox 90 menit: jika macet, berhenti dan laporkan temuan.

## 5. Perintah uji

Targeted:

```bash
python -m pytest \
  tests/test_ragas_importable.py \
  tests/test_ci_contracts.py::test_every_src_module_imports \
  tests/test_scripts_load_env.py::test_run_eval_works_standalone -q
```

Full suite (±2 menit):

```bash
python -m pytest tests/ -q
```

## 6. Definition of Done

- `0 failed` pada suite penuh.
- Pin `ragas` tercatat di `requirements/llm.txt` (Opsi A) **atau** skip
  terkelola terdokumentasi (Opsi B).
- `git status` hanya memuat file yang relevan.
- Satu commit lokal `aider: ...` (sebutkan hash-nya).
- Laporan akhir berisi:
  1. Pendekatan yang dipilih + alasan.
  2. Versi `ragas`/`langchain` yang terpasang.
  3. Output ringkas suite (jumlah pass/fail/skip).
  4. Commit hash.
  5. Risiko / catatan (mis. perilaku di Python 3.14 atau CI bersih).
