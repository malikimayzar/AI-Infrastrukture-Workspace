# Safety & Risk Management

> **Status:** DRAFT
> **Date:** 2026-10-25
> **Pendekatan:** ISO 14971-inspired hazard analysis (bukan klaim kepatuhan penuh)
> **Prinsip:** human-in-the-loop, abstention-first, evidence-visible

---

## 1. Prinsip keselamatan

1. **Sistem tidak pernah menjadi pengambil keputusan akhir.**
2. **Setiap temuan harus bisa ditelusuri ke bukti.**
3. **Ketidakpastian ditampilkan, bukan disembunyikan.**
4. **Kesalahan harus mudah dideteksi manusia.**
5. **Lebih baik tidak memberi temuan daripada memberi temuan salah tanpa bukti.**

---

## 2. Hazard analysis

| # | Hazard | Penyebab | Dampak | Severity | Kontrol |
|---|---|---|---|---|---|
| H1 | False negative: kode tidak didukung tidak terdeteksi | Retrieval gagal, negasi terlewat | Klaim berisiko, audit finding | Tinggi | Recall-focused threshold, sampling audit |
| H2 | False positive: kode didukung ditandai tidak didukung | Copy-forward, family history, section mismatch | Query berlebihan, alert fatigue | Sedang | Evidence span wajib, threshold konservatif |
| H3 | Attribution salah | Chunk-level matching, offset hilang | Koder salah menilai | Tinggi | Span-level + quote verbatim |
| H4 | Confidence terlalu tinggi | Kalibrasi tidak ter-load / data leakage | Automation bias | Tinggi | Health check kalibrasi, reliability report |
| H5 | PHI bocor | Prompt ke cloud, log, fixture | Pelanggaran hukum | Kritis | On-prem default, redaksi, DLP |
| H6 | Model drift | Perubahan model/data | Performa turun diam-diam | Sedang | Monitoring, evaluasi berkala |
| H7 | Guideline usang | Korpus tidak diperbarui | Verdict salah | Sedang | Versioning korpus, tanggal berlaku |
| H8 | Automation bias | UI terlalu meyakinkan | Koder berhenti berpikir kritis | Tinggi | Tampilkan ketidakpastian, wajib konfirmasi |
| H9 | Query tidak sesuai standar | Template buruk | Dokter mengabaikan | Sedang | Review CDI lead, template teruji |
| H10 | Ketergantungan vendor | Provider tunggal | Layanan berhenti | Sedang | Fallback on-prem, kontrak |

---

## 3. Kontrol wajib di UI

- Tampilkan **kutipan verbatim** bukti, bukan hanya skor.
- Tampilkan **lokasi** (section, halaman/offset).
- Tampilkan **confidence** dan artinya (bukan angka mentah).
- Tampilkan **coverage statement**: "tidak dapat dinilai karena ..." bila relevan.
- Tombol **Accept / Reject / Edit** wajib; tidak ada auto-apply.
- Setiap keputusan tercatat di audit trail.
- Tidak ada warna hijau/merah yang menyiratkan kepastian mutlak.

---

## 4. Threshold dan abstention

Tiga zona:

| Zona | Perilaku |
|---|---|
| **Supported** | Tampilkan bukti, minta konfirmasi |
| **Uncertain** | Tampilkan bukti terbaik + minta review manusia |
| **Insufficient** | Abstain, tampilkan alasan dan coverage gap |

Aturan:

- Jangan menurunkan threshold untuk mengejar recall tanpa evaluasi.
- Threshold harus berasal dari data validasi, bukan intuisi.
- Setiap perubahan threshold dicatat dan diuji regresi.

---

## 5. Monitoring produksi

| Metrik | Frekuensi | Ambang eskalasi |
|---|---|---|
| Distribusi verdict | Harian | Pergeseran > 10% |
| Accept rate per reviewer | Harian | Perubahan drastis |
| Waktu review | Harian | Naik > 30% |
| Query per 100 encounter | Harian | > 5 |
| Kalibrasi (ECE) | Mingguan | > 0.10 |
| Error yang dilaporkan | Mingguan | Tren naik |
| Akses PHI | Real-time | Anomali |

---

## 6. Eskalasi

1. **Level 1** — reviewer menandai temuan meragukan.
2. **Level 2** — CDI lead meninjau; jika sistem salah, catat sebagai incident.
3. **Level 3** — jika pola error sistemik, hentikan penggunaan fitur dan rollback.
4. **Level 4** — jika melibatkan PHI, aktifkan prosedur insiden data.

---

## 7. Rollback

- Setiap rilis model/threshold harus dapat dikembalikan.
- Simpan versi model, konfigurasi, dan dataset evaluasi.
- Rollback tidak boleh memerlukan rebuild manual.
- Uji rollback sebelum pilot.

---

## 8. Pelatihan pengguna

- Reviewers harus memahami: apa yang sistem lakukan, apa yang tidak.
- Wajib memahami arti confidence dan coverage.
- Wajib memahami bahwa abstention bukan error.
- Simulasi error handling sebelum go-live.

---

## 9. Batas yang harus dikomunikasikan

- Sistem hanya melihat dokumentasi yang tersedia; dokumentasi buruk → hasil buruk.
- Sistem tidak mengetahui kondisi pasien di luar catatan.
- Sistem tidak menggantikan penilaian klinis.
- Sistem dapat salah; manusia bertanggung jawab atas keputusan akhir.

---

## 10. Yang harus diperbaiki sebelum pilot

| Temuan saat ini | Risiko | Tindakan |
|---|---|---|
| Kalibrasi tidak ter-load di container | H4 | Perbaiki Dockerfile + health check |
| Attribution chunk-level | H3 | Span-level + offset |
| Log query tanpa redaksi | H5 | Redaksi + klasifikasi |
| Default Groq untuk semua | H5 | Pisahkan profil research/clinical |
| Tidak ada monitoring drift | H6 | Tambah metrik dan alert |

---

## 11. Definition of done

- [ ] Hazard analysis ditinjau klinisi
- [ ] Kontrol UI diimplementasikan
- [ ] Threshold berasal dari validasi
- [ ] Monitoring dan alert aktif
- [ ] Rollback diuji
- [ ] Pelatihan pengguna selesai
- [ ] Insiden dan eskalasi disimulasikan
