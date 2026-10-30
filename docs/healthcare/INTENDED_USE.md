# Intended Use Statement — Clinical Documentation Audit

> **Status:** DRAFT v0.1 — requires legal, compliance, and clinical review
> **Date:** 2026-10-25
> **Owner:** (to be assigned)
> **Reviewers:** legal, compliance, clinical advisor, product owner

---

## 1. Statement of intended use

> **Indonesian.** Perangkat lunak ini menganalisis dokumentasi klinis elektronik
> yang telah dide-identifikasi untuk mengidentifikasi kode diagnosis dan prosedur
> yang **tidak didukung**, **hanya sebagian didukung**, atau **bertentangan**
> dengan isi dokumentasi, lalu menyusun **draf pertanyaan klarifikasi**
> (*physician query*) untuk ditinjau oleh tenaga kesehatan terlatih. Perangkat
> lunak ini adalah alat bantu administratif untuk tim *Clinical Documentation
> Integrity* (CDI) dan koding.
>
> **English.** This software analyzes de-identified electronic clinical
> documentation to identify diagnosis and procedure codes that are **unsupported**,
> **partially supported**, or **contradicted** by the documentation, and drafts
> clarification queries for review by trained clinical staff. It is an
> administrative support tool for Clinical Documentation Integrity (CDI) and
> coding teams.

---

## 2. Intended users

| User | Peran terhadap sistem |
|---|---|
| CDI specialist | Meninjau temuan, mengirim query ke dokter |
| Koder (coding officer) | Menggunakan temuan sebagai bahan verifikasi |
| Case manager / casemixer | Meninjau dampak terhadap grup DRG/INA-CBG |
| CDI lead / compliance | Mengawasi kualitas, audit trail, dan eskalasi |

Sistem **tidak** digunakan langsung oleh pasien.

---

## 3. Intended setting

- Rumah sakit, klinik, atau organisasi layanan kesehatan.
- Proses **retrospektif atau concurrent review**, bukan real-time monitoring.
- Deployment **on-premise atau private cloud** di lingkungan organisasi.
- Input berupa catatan klinis yang sudah dide-identifikasi atau diproses di dalam
  batas kendali organisasi.

---

## 4. Clinical function

Sistem melakukan **documentation support**, bukan keputusan klinis:

1. Mengekstrak klaim kode (diagnosis/prosedur) dari encounter.
2. Mencari bukti pendukung di span catatan klinis.
3. Memberi verdict: `SUPPORTED`, `PARTIALLY_SUPPORTED`, `NOT_DOCUMENTED`,
   `CONTRADICTED`, atau `INSUFFICIENT_EVIDENCE`.
4. Menampilkan kutipan bukti dan lokasinya.
5. Menyusun draf *physician query* bila bukti tidak cukup.
6. Mencatat setiap temuan dan tindakan manusia dalam audit trail.

Keputusan akhir selalu berada pada tenaga terlatih.

---

## 5. Not intended for

Sistem ini **bukan** dan **tidak boleh** diposisikan sebagai:

- alat diagnosis atau penegakan diagnosis;
- alat rekomendasi terapi, dosis, atau manajemen klinis;
- alat triage atau prioritas pasien;
- pemantauan pasien real-time atau peringatan dini;
- pengganti koder, CDI specialist, atau dokter;
- sistem yang mengubah kode/klaim secara otomatis tanpa persetujuan manusia;
- alat komunikasi pasien;
- alat yang memproses PHI tanpa perjanjian dan dasar hukum yang sah.

---

## 6. Regulatory positioning

Berdasarkan kerangka IMDRF *Software as a Medical Device* (SaMD), perangkat lunak
yang tujuannya **administratif, keuangan, atau dokumentasi** — dan tidak digunakan
untuk membuat keputusan klinis — umumnya **tidak** diklasifikasikan sebagai SaMD.

Namun:

- Penetapan akhir bergantung pada **intended use yang dipublikasikan** dan
  yurisdiksi.
- Jika sistem nantinya menyarankan diagnosis, terapi, atau tindakan klinis,
  klasifikasi dapat berubah menjadi SaMD dan memerlukan jalur regulasi penuh.
- Perubahan intended use **wajib** melalui ADR baru dan review regulator.

**Status saat ini:** belum ada penetapan regulasi. Jangan menyatakan "bukan alat
medis" sebagai fakta legal sebelum review.

---

## 7. Claims we may make

| Boleh | Tidak boleh |
|---|---|
| "Membantu menemukan kode yang tidak didukung dokumentasi" | "Mendeteksi kesalahan diagnosis" |
| "Menyusun draf query untuk ditinjau koder/dokter" | "Menggantikan koder" |
| "Menampilkan kutipan bukti dari catatan" | "Menjamin akurasi klaim" |
| "Belum divalidasi secara klinis" | "Tervalidasi klinis" |

---

## 8. Open questions (harus dijawab sebelum pilot)

1. Siapa yang menandatangani intended use ini secara formal?
2. Apakah organisasi mitra akan memberikan data retrospektif ter-de-identifikasi?
3. Apakah sistem akan dijalankan di dalam VPC rumah sakit atau di-host vendor?
4. Siapa yang bertanggung jawab atas false negative yang lolos ke klaim?
5. Apakah output akan dianggap bagian dari rekam medis (dan karenanya tunduk pada
   aturan retensi serta audit)?
6. Bagaimana jalur eskalasi jika sistem menemukan kontradiksi pada dokumentasi?

---

## 9. Change control

Setiap perubahan pada bagian 1 (statement of intended use) wajib:

- disetujui pemilik produk dan penasihat klinis;
- dicatat dalam ADR;
- disertai pembaruan `SAFETY.md` dan `CLINICAL_VALIDATION.md`;
- diberi tanggal dan versi baru.

| Versi | Tanggal | Perubahan | Disetujui oleh |
|---|---|---|---|
| 0.1 | 2026-10-25 | Draf awal | — |
