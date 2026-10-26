# Data Governance — PHI & Clinical Data

> **Status:** DRAFT — requires legal and compliance review
> **Date:** 2026-10-25
> **Berlaku untuk:** semua komponen yang memproses data klinis, termasuk
> `rag-research`, `mcp-gateway`, `llm-eval-framework`, dan `arxiv-*`.

---

## 1. Prinsip dasar

1. **Minimum necessary.** Hanya data yang diperlukan untuk tujuan audit.
2. **Purpose limitation.** Data tidak dipakai untuk tujuan lain tanpa dasar baru.
3. **Privacy by default.** PHI tidak keluar dari batas kendali organisasi.
4. **Human accountability.** Setiap akses dapat ditelusuri ke orang dan alasan.
5. **No PHI in development artifacts.** Repo, prompt, log, fixture, dan issue
   tracker bukan tempat data pasien.

---

## 2. Klasifikasi data

| Kelas | Contoh | Penanganan |
|---|---|---|
| **PHI langsung** | Nama, NIK, No. RM, alamat, tanggal lahir, nomor telepon | Tidak boleh masuk sistem pengembangan |
| **PHI klinis** | Catatan dokter, hasil lab, diagnosis, obat | Hanya di lingkungan terkendali, terenkripsi |
| **Pseudonim** | ID acak per encounter | Boleh untuk pengembangan |
| **Agregat** | Statistik kohort | Boleh, jika tidak dapat dire-identifikasi |
| **Publik** | Guideline, literatur | Bebas |

---

## 3. Dasar hukum (Indonesia)

| Regulasi | Relevansi |
|---|---|
| **UU No. 27/2022 — Pelindungan Data Pribadi** | Data kesehatan termasuk data pribadi spesifik; butuh dasar hukum kuat |
| **Permenkes No. 24/2022 — Rekam Medis Elektronik** | Kewajiban RME, interoperabilitas, kerahasiaan |
| **PP No. 71/2019 — PSTE** | Penyelenggaraan sistem elektronik |
| **UU No. 17/2023 — Kesehatan** | Kerahasiaan data kesehatan |

Catatan penting:

- Persetujuan (*consent*) untuk data kesehatan harus **eksplisit** dan
  terinformasi.
- Notifikasi kebocoran data: **3×24 jam** kepada subjek data dan otoritas.
- Transfer lintas negara memerlukan penilaian kecukupan dan perlindungan yang
  setara.
- Peran sebagai **pengendali data** vs **prosesor data** harus ditetapkan
  kontraktual sebelum pilot.

> Ini ringkasan teknis, bukan nasihat hukum. Tim legal wajib memverifikasi.

---

## 4. De-identifikasi

### 4.1 Identifier yang harus dihapus/di-pseudonimisasi

Mengacu pada praktik umum (analog HIPAA Safe Harbor):

- nama, inisial, NIK, nomor rekam medis, nomor asuransi;
- alamat lengkap, kode pos, nomor telepon, email;
- tanggal lahir, tanggal kunjungan (geser tanggal bila perlu);
- nama fasilitas (bila mengidentifikasi);
- nama dokter/perawat;
- nomor perangkat, nomor klaim;
- foto, sidik jari, dan biometrik lain;
- elemen unik lain yang dapat mengidentifikasi.

### 4.2 Prosedur

1. Ekstraksi dari EHR.
2. Penghapusan identifier langsung.
3. Pseudonimisasi encounter (hash + salt, salt disimpan terpisah).
4. Pemeriksaan otomatis (regex + NER) untuk sisa identifier.
5. Sampling manual oleh dua reviewer.
6. Penilaian risiko re-identifikasi (kombinasi tanggal + kode pos + usia, dll.).
7. Pencatatan versi dataset dan checksum.

### 4.3 Larangan

- Tidak boleh melakukan de-identifikasi "seadanya" lalu mengirim ke API publik.
- Tidak boleh menyimpan mapping pseudonim ↔ identitas di repo atau laptop pribadi.
- Tidak boleh memakai data pasien sebagai contoh di dokumentasi.

---

## 5. Penyimpanan dan pemrosesan

| Aspek | Kewajiban |
|---|---|
| Lokasi | On-premise atau private cloud organisasi |
| Enkripsi | At rest (AES-256) dan in transit (TLS 1.2+) |
| Kunci | Dikelola KMS organisasi, bukan di `.env` developer |
| Backup | Terenkripsi, terpisah dari data produksi |
| Retensi | Mengikuti ketentuan rekam medis yang berlaku; konfirmasi ke compliance |
| Penghapusan | Ada prosedur dan bukti penghapusan |
| Log | Tidak memuat isi catatan; hanya metadata dan ID pseudonim |

---

## 6. Penyedia LLM

Ini bagian paling berisiko pada platform saat ini.

| Provider | Boleh untuk PHI? | Syarat |
|---|---|---|
| **Ollama lokal** | Ya, dengan kontrol infrastruktur | Model dan container di lingkungan sendiri |
| **Groq (cloud)** | **Tidak**, kecuali ada perjanjian dan dasar hukum | Data harus de-identified; DPA; review legal |
| **Penyedia lain** | Kasus per kasus | DPA, lokasi data, retensi, subprocessors |

**Aturan default:** untuk PHI, gunakan model on-prem. Penyedia cloud hanya untuk
data yang sudah de-identified dan disetujui.

Konfigurasi saat ini (`LLM_PROVIDER=groq` default) **tidak boleh** dipakai untuk
data klinis tanpa perubahan.

---

## 7. Kontrol akses

- RBAC: CDI specialist, koder, admin, auditor — hak berbeda.
- MFA wajib untuk akses produksi.
- Prinsip *minimum necessary* per peran.
- *Break-glass access* dicatat dan ditinjau.
- Sesi memiliki batas waktu.
- Akses ke data mentah dibatasi dan di-log.

---

## 8. Audit trail

Setiap kejadian berikut wajib dicatat:

- siapa membuka encounter;
- kapan dan dari mana;
- data apa yang ditampilkan;
- temuan sistem apa yang dilihat;
- keputusan manusia (accept/reject/edit);
- query yang dikirim dan jawabannya.

Log harus **append-only**, memiliki retensi, dan tidak dapat diubah pengguna biasa.

---

## 9. Insiden dan kebocoran

1. Deteksi dan containment.
2. Penilaian dampak dan jumlah subjek data.
3. Notifikasi internal ke DPO/legal.
4. Notifikasi eksternal dalam **3×24 jam** bila memenuhi kriteria.
5. Postmortem dan perbaikan kontrol.

Latihan tabletop wajib sebelum pilot.

---

## 10. Checklist sebelum memproses data nyata

- [ ] Peran pengendali/prosesor data ditetapkan tertulis
- [ ] DPA / perjanjian kerahasiaan ditandatangani
- [ ] Dataset sudah melalui prosedur de-identifikasi
- [ ] Penilaian risiko re-identifikasi selesai
- [ ] Lingkungan on-prem/VPC siap
- [ ] KMS dan enkripsi aktif
- [ ] RBAC dan MFA aktif
- [ ] Audit trail aktif dan diuji
- [ ] Rencana insiden dan kontak darurat tersedia
- [ ] Persetujuan etik (bila penelitian) diperoleh

---

## 11. Yang harus segera diperbaiki di repo

| Temuan | Risiko | Tindakan |
|---|---|---|
| `.env.example` pernah memuat key nyata | Kredensial bocor | Revoke key (masih pending) |
| Default provider Groq | PHI bisa keluar | Pisahkan konfigurasi "research" vs "clinical" |
| Log query di Postgres | Bisa memuat isi query | Tambah redaksi dan klasifikasi |
| Dataset kalibrasi berisi query off-domain | Bukan PHI, tapi kualitas | Bersihkan sebelum dipakai ulang |

> Temuan di atas berasal dari audit dokumentasi 2026-10-25; verifikasi ulang
> sebelum menyatakan selesai.
