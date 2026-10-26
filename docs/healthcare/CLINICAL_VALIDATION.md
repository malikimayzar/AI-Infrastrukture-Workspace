# Clinical Validation Protocol (Proposed)

> **Status:** PROPOSED — belum dijalankan. Tidak ada klaim validasi klinis.
> **Date:** 2026-10-25
> **Reference standard:** koder/clinical reviewer manusia
> **Reporting:** STARD 2015 (akurasi diagnostik) + TRIPOD+AI (model prediksi)

---

## 1. Tujuan

Mengukur apakah sistem dapat mengidentifikasi kode diagnosis/prosedur yang tidak
didukung dokumentasi **sebanding dengan tim CDI manusia**, tanpa menimbulkan beban
query yang berlebihan.

Pertanyaan utama:

> Pada encounter rawat inap dewasa, seberapa akurat sistem mendeteksi kode yang
> tidak didukung dokumentasi, dibandingkan dengan penilaian independen dua koder
> dan satu adjudikator?

---

## 2. Status saat ini

| Item | Status |
|---|---|
| Dataset klinis | Belum ada |
| Protokol disetujui | Belum |
| Persetujuan etik | Belum |
| Validasi dijalankan | **Belum** |
| Klaim validasi | **Tidak boleh dibuat** |

---

## 3. Desain studi

### 3.1 Tipe
Retrospektif, observational, diagnostic accuracy study.

### 3.2 Populasi
- Encounter rawat inap dewasa (≥18 tahun).
- Minimal satu kode diagnosis sekunder.
- Exclude: encounter tanpa catatan discharge summary, data tidak lengkap.

### 3.3 Sampling
- Consecutive sampling, bukan convenience.
- Stratifikasi per departemen dan keluarga kode (mis. kardiovaskular,
  respirasi, infeksi, endokrin).
- Minimal **400 encounter** total, atau hasil power calculation.
- Minimal **100 encounter per keluarga kode** utama.

### 3.4 Reference standard
- Dua koder independen menilai setiap kode: didukung / sebagian / tidak didukung.
- Keduanya **blinded** terhadap output sistem.
- Jika tidak sepakat → adjudikator (CDI lead / dokter) memutuskan.
- Inter-rater agreement reference standard dilaporkan (Cohen's kappa).

### 3.5 Index test
- Sistem dijalankan pada data yang sudah dide-identifikasi.
- Output: verdict + confidence + evidence span.
- Tidak ada tuning setelah data test dibuka.

---

## 4. Metrik

| Metrik | Definisi | Target usulan |
|---|---|---|
| Sensitivity | Proporsi kode tidak didukung yang terdeteksi | ≥ 0.90 |
| Specificity | Proporsi kode didukung yang tidak salah ditandai | ≥ 0.85 |
| PPV | Proporsi temuan yang benar | ≥ 0.85 |
| NPV | Proporsi "didukung" yang benar | ≥ 0.90 |
| F1 | Harmonic mean PPV & sensitivity | ≥ 0.87 |
| Cohen's kappa | Agreement sistem vs reference | ≥ 0.70 |
| Alert burden | Query per 100 encounter | ≤ 5 |
| Time-to-review | Waktu koder meninjau per encounter | Turun ≥ 30% |

Semua target adalah **usulan**, bukan hasil. Wajib disepakati dengan mitra klinis
sebelum studi.

### 4.1 Analisis subgroup
- Departemen
- Keluarga kode
- Tipe catatan (discharge summary vs progress note)
- Panjang dokumentasi
- Ada/tidaknya query sebelumnya

### 4.2 Confidence interval
- 95% CI untuk semua metrik (Wilson / bootstrap).
- Laporkan confusion matrix lengkap.

---

## 5. Error analysis

Setiap false positive dan false negative dikategorikan:

| Kategori | Contoh |
|---|---|
| Negation missed | "Tidak ada sepsis" dianggap sepsis |
| Family history | Riwayat keluarga dianggap diagnosis pasien |
| Temporality | Kondisi lama dianggap aktif |
| Copy-forward | Catatan lama tersalin |
| Section mismatch | Bukti dari section yang salah |
| Abbreviation | "PT" salah diartikan |
| Retrieval failure | Bukti ada tapi tidak terambil |
| Attribution error | Bukti benar, span salah |
| Calibration error | Confidence tinggi pada prediksi salah |

Analisis ini wajib dilaporkan, bukan disembunyikan.

---

## 6. Bias dan ancaman validitas

- **Spectrum bias:** pilih encounter dari berbagai tingkat keparahan.
- **Reader bias:** koder tahu sistem sedang diuji → blinding ketat.
- **Automation bias:** jangan tampilkan output sistem ke reference standard.
- **Data leakage:** pastikan encounter test tidak ada di data training/tuning.
- **Temporal leakage:** pisahkan periode waktu train dan test.
- **Site bias:** idealnya multi-site; minimal satu site dengan case mix beragam.

---

## 7. Prosedur

1. Protokol ditulis dan disetujui **sebelum** akses data.
2. Persetujuan etik dan DPA.
3. De-identifikasi sesuai `DATA_GOVERNANCE.md`.
4. Sistem dijalankan, output dibekukan (*frozen*).
5. Koder menilai secara independen.
6. Adjudikasi.
7. Analisis sesuai protokol.
8. Publikasi hasil, termasuk yang negatif.

---

## 8. Yang tidak boleh dilakukan

- Menuning threshold setelah melihat data test.
- Melaporkan hanya subgroup yang bagus.
- Menghapus false negative dari laporan.
- Menyebut "validated" untuk uji internal kecil.
- Memakai data pasien tanpa etik/DPA.

---

## 9. Hubungan dengan evaluasi yang sudah ada

`llm-eval-framework` saat ini mengukur *faithfulness* generik, bukan akurasi
klinis. Untuk domain healthcare, tambahkan:

- **Clinical accuracy suite** — verdict vs reference standard.
- **Negation/temporality suite** — kasus yang dirancang khusus.
- **Attribution suite** — apakah span yang ditunjuk benar-benar berisi bukti.
- **Abstention suite** — apakah sistem menolak saat bukti tidak cukup.

Jangan memakai ECE sebagai pengganti sensitivitas/spesifisitas. Keduanya mengukur
hal berbeda.

---

## 10. Deliverables

- Protokol final (PDF, bertanggal).
- Dataset statistik (n, karakteristik, exclusion).
- Confusion matrix + metrik + CI.
- Analisis error.
- Laporan STARD/TRIPOD.
- Pernyataan batas dan intended use yang diperbarui.

---

## 11. Definition of done

- [ ] Protokol disetujui
- [ ] Etik/DPA selesai
- [ ] Dataset terkunci dan terverifikasi
- [ ] Output sistem dibekukan sebelum penilaian
- [ ] Metrik + CI dilaporkan
- [ ] Error analysis dilaporkan
- [ ] `INTENDED_USE.md` diperbarui bila perlu
- [ ] Tidak ada klaim di luar hasil
