# Healthcare Domain Pack

> **Status:** DRAFT — belum ditinjau legal, compliance, atau klinisi.
> **Created:** 2026-10-25
> **Scope:** Mengarahkan platform ke audit dokumentasi klinis (Clinical Documentation Integrity / CDI), bukan diagnosis atau terapi.
> **Repo:** root workspace + `rag-research` + `mcp-gateway`

---

## Kenapa paket ini ada

Platform ini dibangun sebagai *Scientific Claim & Prior-Art Auditor*. Pola intinya —
**klaim → bukti → verdict → abstention** — bisa dipindahkan ke domain lain tanpa
mengubah arsitektur. Healthcare dipilih karena pola itu sudah dipakai setiap hari
secara manual oleh tim CDI dan koder:

- **Klaim** = kode diagnosis / prosedur yang akan ditagihkan
- **Bukti** = span di catatan klinis (HPI, assessment, lab, imaging, meds)
- **Verdict** = didukung / sebagian / tidak didokumentasikan / bertentangan
- **Abstention** = sistem tidak mengubah kode; ia menyusun pertanyaan untuk dokter

Yang berubah bukan kode, tapi **posisi, batas, dan bukti validasi**.

---

## Urutan baca

| # | Dokumen | Fungsi |
|---|---|---|
| 1 | [`INTENDED_USE.md`](INTENDED_USE.md) | Menentukan status regulasi. **Baca ini dulu.** |
| 2 | [`DOMAIN.md`](DOMAIN.md) | Kosakata, alur kerja, dan aktor CDI |
| 3 | [`DATA_GOVERNANCE.md`](DATA_GOVERNANCE.md) | PHI, de-identifikasi, UU PDP, retensi |
| 4 | [`CLINICAL_VALIDATION.md`](CLINICAL_VALIDATION.md) | Protokol uji vs koder manusia |
| 5 | [`SAFETY.md`](SAFETY.md) | Hazard, kontrol, human-in-the-loop |
| 6 | [`../adr/002-positioning-documentation-audit.md`](../adr/002-positioning-documentation-audit.md) | Keputusan posisi: administratif, bukan SaMD |

---

## Prinsip yang tidak boleh dilanggar

1. **Intended use menentukan segalanya.** Satu kata "diagnosis" di README bisa
   mengubah status produk dari administratif menjadi *Software as a Medical Device*.
2. **Human-in-the-loop wajib.** Sistem tidak pernah mengubah kode, klaim, atau
   dokumentasi secara otomatis.
3. **Abstention adalah fitur, bukan kegagalan.** Jika bukti tidak cukup, output
   yang benar adalah pertanyaan klarifikasi — bukan tebakan.
4. **Tidak ada PHI di repo.** Tidak di git, tidak di prompt ke penyedia cloud,
   tidak di log, tidak di fixture test.
5. **Tidak ada klaim "tervalidasi klinis" sebelum ada hasil vs koder manusia.**
   Tulis "belum divalidasi" — itu menaikkan kepercayaan, bukan menurunkannya.

---

## Daftar edit minimal (5 file)

File-file ini **tidak diubah** oleh paket ini. Berikut perubahan yang diperlukan
agar positioning healthcare konsisten. Semua perubahan bersifat aditif; jangan
hapus isi lama yang masih benar.

### 1. `README.md`

- Perbaiki link rusak ke `docs/ARCHITECTURE.md` (file tidak ada).
- Tambah bagian **"What this is / What this is not"**:
  - *is*: audit administratif atas dukungan dokumentasi terhadap klaim/kode
  - *is not*: diagnosis, terapi, triage, atau pengganti koder/dokter
- Tambah link ke `docs/healthcare/INTENDED_USE.md`.
- Tambah satu baris status: **"Clinical validation: not performed."**

### 2. `PROJECT_GOALS.md`

- Tambah bagian **"Domain 2 — Healthcare CDI (Phase 5, proposed)"**.
- Tambah **non-goals**: diagnosis, rekomendasi terapi, autonomous coding,
  klaim SaMD, pemrosesan PHI tanpa perjanjian.
- Tambah success criteria domain healthcare:
  - sensitivitas ≥ 0.90, spesifisitas ≥ 0.85 vs koder manusia (target, belum diukur)
  - Cohen's kappa ≥ 0.70
  - alert burden ≤ 5 query per 100 encounter (target, belum diukur)
- Jangan mengubah goal engineering yang sudah ada.

### 3. `PROJECT_CONTEXT.md`

- Tambah **"Healthcare readiness"**: `docs only — no PHI processed, no clinical
  validation, no FHIR integration`.
- Tambah **"What is NOT ready"** agar tidak ada klaim berlebih.
- Cantumkan tanggal dan commit saat status ini ditulis.

### 4. `AGENTS.md`

Tambah bagian **"Healthcare domain rules"** di bawah §4 (Strict Prohibitions):

- Dilarang menaruh PHI di repo, prompt, log, fixture, atau issue tracker.
- Dilarang memakai penyedia LLM cloud untuk data yang dapat diidentifikasi;
  default untuk PHI adalah on-prem (Ollama/local).
- Dilarang menulis klaim klinis tanpa merujuk `CLINICAL_VALIDATION.md`.
- Setiap perubahan yang menyentuh logika domain wajib menyebut intended use
  di deskripsi PR.
- Dataset baru wajib melewati checklist `DATA_GOVERNANCE.md`.

### 5. `docs/business/product-strategy.md`

- Ganti dua wedge (MCP tools + patent auditor) menjadi **satu wedge: CDI audit**.
- Tambah bagian **"Why healthcare, why now"** yang merujuk `INTENDED_USE.md`,
  bukan angka pasar yang belum diverifikasi.
- Pindahkan strategi lain ke lampiran berlabel **"Parked — revisit after
  clinical validation"**.
- Jangan mencantumkan proyeksi pendapatan tanpa sumber.

---

## Yang tidak boleh dirombak

| Path | Alasan |
|---|---|
| `docs/architecture/*` | Domain-agnostic; tetap valid |
| `docs/adr/001-*` | Keputusan provider masih berlaku |
| `docs/runbooks/*` | Operasional, bukan domain |
| `docs/ops-postmortem.md` | Bukti kematangan |
| `docs/backup-guide.md`, `health-check-guide.md` | Infrastruktur |
| `docs/acceptance/*` | Bukti gate operasional |
| `docs/threat_model.md` (arxiv repo) | Perlu tambahan, bukan ganti |

---

## Definition of done untuk paket ini

- [ ] `INTENDED_USE.md` disetujui pemilik produk
- [ ] Review legal/compliance dijadwalkan (UU PDP, Permenkes 24/2022)
- [ ] Penasihat klinis / koder senior diidentifikasi
- [ ] Tidak ada dokumen yang menyatakan validasi klinis
- [ ] Semua link internal valid
- [ ] `STATUS.md` tunggal dibuat; `ROADMAP.md` dan `IMPLEMENTATION_STATUS.md`
      diarsipkan (jangan dipelihara ganda)

---

## Catatan

Dokumen di folder ini adalah **draf teknis**, bukan nasihat hukum atau medis.
Setiap angka target adalah usulan yang harus disepakati dengan mitra klinis
sebelum dijadikan acceptance criteria.
