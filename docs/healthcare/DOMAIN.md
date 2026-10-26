# Domain Model — Clinical Documentation Integrity (CDI)

> **Status:** DRAFT
> **Date:** 2026-10-25
> **Tujuan:** Menjelaskan kosakata, aktor, alur kerja, dan pemetaan domain ke
> komponen platform yang sudah ada.

---

## 1. Aktor dan alur kerja

```
Pasien dirawat
   │
   ▼
Dokter menulis catatan klinis (HPI, ROS, assessment, plan, discharge summary)
   │
   ▼
Koder memberi kode diagnosis (ICD-10) dan prosedur (ICD-9-CM)
   │
   ▼
CDI specialist meninjau: apakah dokumentasi mendukung kode?
   │
   ├── Cukup ──────────────► kode final ──► klaim (INA-CBG/DRG) ──► pembayaran
   │
   └── Tidak cukup ────────► physician query ──► dokter menjawab
                                │
                                ▼
                          dokumentasi diperbaiki ──► kode ditinjau ulang
```

**Inti masalah:** kode yang tidak didukung dokumentasi menyebabkan klaim ditolak,
turunnya *case mix index*, risiko audit, dan potensi temuan fraud/abuse. Sebaliknya,
query yang berlebihan menyebabkan *alert fatigue* dan mengganggu dokter.

---

## 2. Konsep kunci

| Istilah | Arti |
|---|---|
| **Principal diagnosis** | Kondisi utama yang menyebabkan rawat inap |
| **Secondary diagnosis** | Kondisi lain yang memengaruhi perawatan |
| **CC / MCC** | *Complication/Comorbidity* yang menaikkan severity dan pembayaran |
| **Physician query** | Pertanyaan terstruktur ke dokter untuk melengkapi dokumentasi |
| **CDI** | Clinical Documentation Integrity — proses memastikan dokumentasi akurat dan lengkap |
| **DRG / INA-CBG** | Pengelompokan diagnosis untuk pembayaran (INA-CBG dipakai JKN) |
| **Case mix index** | Rata-rata kompleksitas pasien; memengaruhi pendapatan |
| **Retrospective review** | Tinjauan setelah pasien pulang |
| **Concurrent review** | Tinjauan saat pasien masih dirawat |

---

## 3. Pemetaan ke platform

| Konsep domain | Komponen platform | Catatan |
|---|---|---|
| Klaim | Kode diagnosis/prosedur | Unit atomik audit |
| Bukti | Span catatan klinis | Perlu offset karakter + section |
| Verdict | `SUPPORTED` / `PARTIALLY_SUPPORTED` / `NOT_DOCUMENTED` / `CONTRADICTED` / `INSUFFICIENT_EVIDENCE` | Perluas enum yang ada |
| Confidence | Kalibrasi isotonic/Platt | Harus benar-benar ter-load di runtime |
| Attribution | `src/utils/attribution.py` | Saat ini lexical chunk-level; perlu span + negasi + temporalitas |
| Abstention | `ConfidenceEngine` | Default saat bukti lemah |
| Query generation | Template + LLM | Harus deterministik dan dapat diaudit |
| Audit trail | Postgres + log terstruktur | Wajib immutable untuk PHI |
| Evaluasi | `llm-eval-framework` | Perlu metrik klinis (sensitivitas/spesifisitas) |

---

## 4. Keunikan teks klinis

Teks klinis jauh lebih sulit daripada paper arXiv. Sistem **wajib** menangani:

### 4.1 Negasi
> "Tidak ada nyeri dada." → bukan bukti untuk diagnosis chest pain.

### 4.2 Riwayat keluarga vs pasien
> "Ayah pasien memiliki riwayat diabetes." → bukan diagnosis pasien.

### 4.3 Hipotetikal
> "Jika demam berlanjut, pertimbangkan sepsis." → bukan diagnosis aktif.

### 4.4 Temporalitas
> "Riwayat pneumonia 2023." → bukan kondisi saat ini.

### 4.5 Copy-forward
Catatan yang disalin dari encounter sebelumnya sering memuat kondisi lama yang
sudah resolved. Ini sumber false positive terbesar.

### 4.6 Singkatan ambigu
> "PT" bisa berarti physiotherapy, prothrombin time, atau pulmonary tuberculosis.

### 4.7 Section detection
Bukti untuk diagnosis harus berada di section yang tepat (assessment/plan),
bukan di riwayat keluarga atau instruksi discharge.

### 4.8 Unstated linkage
Lab abnormal tanpa interpretasi dokter bukan otomatis diagnosis.

---

## 5. Ontologi dan standar

| Standar | Fungsi | Status di sistem |
|---|---|---|
| **ICD-10** | Kode diagnosis | Belum terintegrasi |
| **ICD-9-CM** | Kode prosedur (Indonesia) | Belum terintegrasi |
| **SNOMED CT** | Terminologi klinis | Belum terintegrasi |
| **LOINC** | Kode lab | Belum terintegrasi |
| **HL7 FHIR R4** | Pertukaran data | Belum terintegrasi |
| **SATUSEHAT** | Platform interoperabilitas Kemenkes | Belum terintegrasi |
| **INA-CBG** | Grouping klaim JKN | Belum terintegrasi |

Catatan: Indonesia masih memakai ICD-10; transisi ke ICD-11 adalah risiko jangka
panjang yang harus dipantau.

---

## 6. Data yang dibutuhkan

| Data | Sumber | Sensitivitas |
|---|---|---|
| Catatan klinis (free text) | EHR | PHI — tinggi |
| Kode diagnosis/prosedur | Sistem koding | PHI — tinggi |
| Hasil lab | LIS | PHI — tinggi |
| Imaging report | RIS/PACS | PHI — tinggi |
| Obat | Farmasi | PHI — tinggi |
| Metadata encounter | EHR | PHI — sedang |
| Guideline / protokol | Dokumen internal | Rendah |

Untuk pengembangan awal, gunakan **data sintetis** atau **data publik
ter-de-identifikasi** (mis. MIMIC-IV setelah kredensial dan DUA). Jangan memakai
data rumah sakit tanpa perjanjian.

---

## 7. Perluasan yang dibutuhkan di kode

| Komponen | Perubahan |
|---|---|
| `rag-research` ingestion | Dukung PDF guideline, catatan klinis, dan FHIR Bundle |
| Chunking | Section-aware (HPI, ROS, assessment, plan) |
| NER | Entity klinis: problem, medication, lab, procedure |
| Negation/temporality | Modul khusus (mis. rule-based + model) |
| Retrieval | Hybrid tetap; tambah filter per section dan per encounter |
| Verdict | Enum baru + aturan domain |
| Attribution | Span-level dengan offset dan section |
| Evaluasi | Metrik klinis, bukan hanya ECE |

---

## 8. Non-goals domain

- Rekomendasi terapi atau dosis.
- Prediksi risiko klinis.
- Triage atau prioritas perawatan.
- Penentuan klaim asuransi secara otomatis.
- Penilaian kualitas layanan klinis.

---

## 9. Referensi yang perlu dibaca tim

- Permenkes No. 24 Tahun 2022 tentang Rekam Medis Elektronik.
- UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi.
- Panduan SATUSEHAT (HL7 FHIR R4).
- Pedoman koding ICD-10 dan INA-CBG yang berlaku.
- Literatur CDI: physician query, DRG optimization, clinical validation.

> Semua referensi regulasi harus dikonfirmasi ulang oleh tim compliance sebelum
> dijadikan dasar keputusan.
