# Claim Audit UI — design

> **Date:** 2026-10-28
> **Status:** Proposed — awaiting approval
> **Scope:** Phase 4 — Claim Audit UI & Formal Reporting (MVP)
> **Repo:** `mcp-gateway` (static UI di `web/audit/`)
> **Pengguna pertama:** tim CDI/koding di rumah sakit
> **Referensi:** `docs/healthcare/INTENDED_USE.md`, `docs/healthcare/SAFETY.md`,
> `docs/confidence-calibration.md`, `mcp-gateway/docs/api-contract.md`,
> `docs/ROADMAP.md`

---

## 1. Intent

Phase 4 membutuhkan antarmuka yang membuat hasil audit dapat **diperiksa manusia**,
bukan sekadar jawaban chat. Pengguna pertama adalah tim Clinical Documentation
Integrity (CDI) dan koding rumah sakit: mereka perlu melihat apakah sebuah kode
diagnosis/prosedur didukung oleh dokumentasi klinis, di mana buktinya, seberapa
kuat keyakinan sistem, dan apa yang harus dilakukan jika bukti tidak cukup.

UI ini adalah **audit workbench**, bukan chatbot. Fokusnya:

1. Menampilkan klaim/kode, zona keyakinan, dan bukti verbatim secara berdampingan.
2. Menjaga manusia tetap memegang keputusan akhir (Accept / Reject / Edit).
3. Menjadikan abstention sebagai hasil yang sah dan dapat dijelaskan, bukan error.
4. Menyediakan ekspor JSON untuk kebutuhan audit dan otomasi lanjutan.

Backend sudah menyediakan sebagian besar data yang dibutuhkan: rute `/audit`,
`calibrated_confidence`, `calibrated_decision`, `calibration_method`, dan
`span_level_attribution[]`. UI saat ini masih prototype minimal di
`mcp-gateway/web/audit/` dan belum memenuhi kebutuhan di atas.

---

## 2. Goals

- Menyediakan satu halaman audit di `http://localhost:8090/audit/` yang:
  - menerima satu klaim/pertanyaan;
  - memanggil backend `research_rag` (melalui `/audit` atau `/ask`);
  - menampilkan zona keyakinan (merah/kuning/hijau) beserta label dan penjelasan;
  - menampilkan daftar klaim dan bukti verbatim secara side-by-side;
  - memungkinkan pengguna menandai **Terima / Tolak / Edit** tanpa auto-apply;
  - mengekspor hasil audit ke JSON.
- Menyediakan mode demo dengan data sintetis sehingga UI dapat diuji tanpa
  backend hidup dan tanpa data pasien asli.
- Menjaga UI tetap **tanpa build step**: HTML, CSS, dan JavaScript statis yang
  disajikan langsung oleh gateway.
- Menjadi fondasi untuk pemisahan ke repo UI terpisah jika ritme rilis UI
  benar-benar berbeda dari gateway.

---

## 3. Non-goals

- **Bukan chatbot.** Tidak ada percakapan multi-turn, riwayat chat, atau
  personality.
- **Tidak menghitung verdict CDI sendiri.** UI hanya menampilkan zona keyakinan
  dari backend; manusia yang menentukan `SUPPORTED`, `PARTIALLY_SUPPORTED`,
  `NOT_DOCUMENTED`, `CONTRADICTED`, atau `INSUFFICIENT_EVIDENCE`.
- **Tidak membuat draf physician query.** UI hanya menampilkan bukti; pengguna
  menulis query di luar sistem.
- **Tidak ada case queue/riwayat multi-kasus** di MVP. Satu klaim per audit.
- **Tidak ada export Markdown/PDF** di MVP. Hanya JSON.
- **Tidak ada auth/RBAC** di MVP. Untuk produksi, UI harus berada di belakang
  reverse proxy same-origin yang menangani API key.
- **Tidak ada perhitungan confidence atau evaluasi di browser.** Backend adalah
  sumber kebenaran.
- **Tidak ada PHI di repo, fixture, log, atau prompt.** Data uji harus sintetis.

---

## 4. Anti-goals

Hal-hal berikut membuat UI dianggap gagal meskipun secara teknis berjalan:

- Menampilkan warna hijau/merah tanpa label sehingga menyiratkan kepastian mutlak.
- Menyembunyikan abstention atau menampilkan jawaban kosong tanpa penjelasan.
- Mengubah kode/klaim secara otomatis tanpa persetujuan manusia.
- Menampilkan skor mentah tanpa arti atau konteks.
- Mengirim data ke CDN, analytics, atau layanan cloud dari browser.
- Menjadi lapisan business logic kedua yang menduplikasi keputusan backend.
- Menampilkan bukti yang tidak verbatim atau kehilangan lokasi sumber.

---

## 5. Constraints

- **Lokasi MVP:** `mcp-gateway/web/audit/` — sudah disajikan oleh rute
  `GET /audit/*` dan `POST /audit` yang ada.
- **Tanpa build step:** tidak ada Node.js, bundler, atau framework di MVP.
  Ini menjaga deployment tetap satu binary/container gateway.
- **Kontrak yang tersedia:**
  - `decision` (`answer` / `abstain` / `error`)
  - `failure_type`
  - `evaluation_status`
  - `calibrated_confidence`, `calibrated_decision`, `calibration_method`
  - `span_level_attribution[]` dengan `claim_span`, `chunk_id`, `doc_id`,
    `score`, `text`, `unverified`
  - `evidence[]` dengan `text`, `source_id`, `chunk_id`, `score`
  - `request_id`, `model`, `latency_ms`
- **Keterbatasan kontrak saat ini:**
  - `abstain_reason` dan `coverage_gap` belum tersedia; MVP memakai
    `failure_type` dan jumlah bukti.
  - `span_level_attribution` masih heuristik Jaccard, bukan skor terkalibrasi.
    UI wajib menandai `unverified`.
  - `POST /audit` saat ini memetakan ke `handleAsk`; kontrak respons harus
    diverifikasi sebelum UI bergantung padanya.
- **PHI:** tidak ada data pasien asli di repo. Fixture memakai encounter fiktif.
- **On-prem:** seluruh font/asset di-bundle lokal; tidak ada request eksternal
  pada mode produksi.
- **AGENTS.md:** perubahan di `mcp-gateway` memakai prefix commit `opencode:`;
  root workspace hanya untuk integrator.

---

## 6. Approaches considered

### A. UI statis di `mcp-gateway/web/audit/` (dipilih untuk MVP)

**Keuntungan:** tidak ada repo/pipeline baru; deployment tetap satu gateway;
cocok untuk memvalidasi alur dengan data nyata; tidak ada CORS.

**Kerugian:** UI/UX terbatas; tes frontend bercampur dengan Go; ritme rilis UI
terikat gateway.

### B. Repo frontend terpisah sekarang (Vite + React/TS + Tailwind)

**Keuntungan:** stack dan ritme rilis terpisah; ekosistem komponen dan tes
frontend lebih kaya.

**Kerugian:** kontrak audit belum sepenuhnya stabil; menambah compose service,
CORS, auth browser, dan pipeline CI baru; risiko rework tinggi.

### C. Hybrid: prototype statis sekarang, repo terpisah nanti (dipilih)

**Keuntungan:** validasi cepat dengan biaya rendah; tidak menunda pekerjaan
backend; keputusan repo diambil setelah alur terbukti.

**Kerugian:** ada kemungkinan menulis ulang saat pindah framework. Mitigasinya:
prototype diperlakukan sebagai **spike**, bukan produk final, dan struktur
HTML/CSS dibuat cukup rapi agar mudah dipindahkan.

**Keputusan:** mulai dengan C. Repo UI terpisah hanya dipertimbangkan setelah
MVP terbukti dipakai, kontrak audit stabil, dan `make demo` + refusal suite
tersedia.

---

## 7. Decision log

| Keputusan | Pilihan | Status |
|---|---|---|
| Pengguna pertama | Tim CDI/koding rumah sakit | Disepakati |
| Bentuk UI | Audit workbench tiga panel, bukan chat | Usulan desain |
| Verdict CDI terpisah | Tidak; cukup zona keyakinan, manusia menentukan verdict | Disepakati |
| Label verdict di UI | Dihapus dari wireframe; UI hanya menampilkan zona | Disepakati (builder-check) |
| Physician query draft | Tidak; cukup tampilkan bukti | Disepakati |
| Unit review | Klaim/kode input, bukan kalimat jawaban | Usulan default |
| Aksi manusia | Terima / Tolak / Edit (bukan lima verdict CDI) | Usulan default |
| Sumber panel bukti | `span_level_attribution` utama; `evidence[]` kandidat | Usulan default |
| Penjelasan zona | Template dari `calibrated_decision` + `failure_type` + jumlah bukti | Usulan default |
| Export MVP | JSON | Usulan default |
| Export Markdown/PDF | Ditunda | Usulan default |
| Case queue/riwayat | Ditunda | Usulan default |
| Lokasi MVP | `mcp-gateway/web/audit/` | Disepakati |
| Repo UI terpisah | Ditunda sampai MVP stabil | Disepakati |
| Data uji | Sintetis, tanpa PHI | Disepakati (data belum dibuat) |
| Cakupan MVP | Demo-only dengan data sintetis | Usulan default (pending) |
| Perluasan kontrak gateway | Minimal: `calibration_method`, `is_calibrated`, `abstain_reason`, `generation_chunk_ids`/`context_chunk_ids` | Usulan default (pending) |
| Provenance bukti | Teks verbatim + `source_id`/`chunk_id`; metadata halaman menyusul | Usulan default (pending) |
| Identitas reviewer di export | Opsional di demo; wajib di produksi | Usulan default (pending) |
| Bahasa | Indonesia dulu, Inggris menyusul | Usulan default |
| Tema | Gelap default, light mode opsional | Usulan default |

---

## 8. UI design

### 8.1 Wireframe

```text
┌─────────────────────────────────────────────────────────────────────┐
│  Audit Dokumentasi Klinis   [Input klaim/kode]        [Audit]       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  KIRI: INPUT / KONTEKS                                              │
│  ─────────────────────                                              │
│  Klaim atau kode:                                                   │
│  [____________________________________________________________]     │
│                                                                     │
│  Backend: research_rag (tetap, tidak ditampilkan sebagai pilihan)   │
│                                                                     │
│  Contoh: "J18.9 Pneumonia"                                          │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  TENGAH: HASIL AUDIT                                                │
│  ───────────────────                                                │
│  Zona: 🟡 KUNING — PARTIAL TRUST (0.58)                             │
│  Penjelasan: "Bukti cukup, tetapi tidak konsisten di semua sumber.  │
│  Maksimal 3 catatan dipakai. Periksa ulang sebelum disetujui."      │
│                                                                     │
│  Klaim: "J18.9 Pneumonia"                                           │
│  (UI hanya menampilkan zona; manusia menentukan verdict.)           │
│                                                                     │
│  [ Terima ]  [ Tolak ]  [ Edit ]                                    │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  KANAN: BUKTI (SPAN CATATAN KLINIS)                                 │
│  ─────────────────────────────────                                  │
│  Span 1 — "Assessment: pneumonia, likely community-acquired"        │
│  Sumber: Catatan poli, 15 Okt 2026, halaman 2                       │
│  Skor: 0.72 — [belum terverifikasi]                                 │
│                                                                     │
│  Span 2 — "Chest X-ray: no consolidation"                           │
│  Sumber: Radiologi, 15 Okt 2026                                     │
│  Skor: 0.31 — [belum terverifikasi]                                 │
│                                                                     │
│  Klik klaim untuk menyorot bukti; klik bukti untuk menyorot klaim.  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  BAWAH: AUDIT TRAIL + EXPORT                                        │
│  ────────────────────────────                                       │
│  Request ID: req-... | Waktu: ... | Evaluasi: completed             │
│  Keputusan manusia: [belum ditentukan]                               │
│  [ Export JSON ]                                                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.2 Komponen

1. **Header/input:** satu field klaim/kode, tombol Audit, indikator loading.
2. **Zone banner:** warna + label + skor kalibrasi + penjelasan singkat.
3. **Claim panel:** teks klaim input dan tombol Terima/Tolak/Edit. Tidak ada
   verdict CDI otomatis; UI hanya menampilkan zona.
4. **Evidence panel:** render `span_level_attribution[]` sebagai bukti yang
   dipetakan ke klaim (utama). Tampilkan `evidence[]` sebagai kandidat/fallback,
   dan jangan menyajikan chunk yang tidak dipetakan sebagai bukti pendukung
   tanpa label **kandidat**. Tampilkan teks verbatim, sumber, skor, dan badge
   `belum terverifikasi` bila `unverified=true`.
5. **Audit trail strip:** `request_id`, timestamp, `evaluation_status`,
   `failure_type`, dan keputusan manusia.
6. **Export button:** mengunduh JSON berisi respons backend + keputusan manusia.

### 8.3 States

| State | Tampilan |
|---|---|
| Idle | Form kosong + contoh klaim |
| Loading | Tombol disabled, spinner/teks "Mengaudit..." |
| Answer (hijau) | Zone banner hijau, klaim + bukti |
| Partial (kuning) | Zone banner kuning, peringatan bukti terbatas |
| Abstain (merah) | Zone banner merah, alasan `failure_type`, coverage gap, tidak ada jawaban palsu |
| Error | Pesan error yang dapat ditindaklanjuti (bukan stack trace) |
| Empty | "Tidak ada bukti yang ditemukan" + saran input ulang |

### 8.4 Interaksi

- Klik klaim → highlight span bukti yang terkait; klik span → highlight klaim.
- Tombol **Terima/Tolak/Edit** mengubah state lokal dan mencatat baris audit
  trail; tidak mengirim perubahan ke backend pada MVP.
- **Edit** membuka textarea untuk mengubah teks klaim/kode; perubahan hanya
  lokal sampai diekspor.
- Export JSON menyertakan `request_id`, respons backend, timestamp, dan
  keputusan manusia.
- **Penjelasan zona** memakai template yang diturunkan dari
  `calibrated_decision`, `failure_type`, dan jumlah bukti. Jangan mengarang
  alasan seperti "tidak konsisten di semua sumber" kecuali backend benar-benar
  menyediakannya. Copy klinis final harus ditinjau clinical/compliance sebelum
  produksi.

### 8.5 Visual language

- Dark mode default untuk workstation audit; light mode opsional untuk review
  panjang.
- Font sistem atau font yang di-bundle lokal; tidak ada Google Fonts/CDN.
- Warna zona:
  - merah `#b42318` (REJECT)
  - kuning `#b54708` (PARTIAL_TRUST)
  - hijau `#067647` (GENERATE)
- Warna selalu disertai label teks dan ikon; tidak pernah warna saja.
- Kontras memenuhi WCAG 2.1 AA.
- Layout desktop-first (min-width ~1024px); pada layar kecil panel ditumpuk.

---

## 9. Data contract

### 9.1 Request

MVP memakai `POST /audit` (atau `POST /ask` bila `/audit` belum stabil):

```json
{
  "backend": "research_rag",
  "query": "J18.9 Pneumonia",
  "top_k": 5
}
```

`backend` tidak ditampilkan sebagai pilihan di UI MVP; nilainya tetap
`research_rag` agar audit berjalan di korpus riset/klinis yang sesuai.

### 9.2 Response fields yang dipakai

| Field | Penggunaan di UI |
|---|---|
| `request_id` | Audit trail, export |
| `decision` | Menentukan state answer/abstain/error |
| `failure_type` | Alasan abstention/error |
| `evaluation_status` | Audit trail |
| `calibrated_confidence` | Skor di zone banner (dengan label) |
| `calibrated_decision` | Zona: `GENERATE` / `PARTIAL_TRUST` / `REJECT` |
| `calibration_method` | **Belum tersedia di `GatewayResponse`**; hanya ada di adapter RAG. Tampilkan "tidak tersedia" sampai kontrak diperluas. |
| `span_level_attribution[]` | Daftar klaim + mapping ke chunk |
| `evidence[]` | Teks bukti verbatim + sumber |
| `model`, `latency_ms` | Audit trail/export |

### 9.3 Mapping zona

| `calibrated_decision` | Zona | Label | Perilaku |
|---|---|---|---|
| `REJECT` | Merah | Bukti tidak cukup | Tampilkan alasan; tidak ada jawaban |
| `PARTIAL_TRUST` | Kuning | Bukti terbatas | Tampilkan peringatan; maksimal 3 bukti |
| `GENERATE` | Hijau | Bukti cukup | Tampilkan jawaban + atribusi penuh |
| tidak ada | Abu-abu | Tidak terkalibrasi | Tampilkan `decision` mentah + peringatan |

### 9.4 Keterbatasan yang harus terlihat di UI

- `span_level_attribution` masih heuristik Jaccard; setiap item dengan
  `unverified=true` diberi badge **belum terverifikasi**.
- Bila `span_level_attribution` kosong tetapi `decision=answer`, tampilkan
  catatan "atribusi klaim tidak tersedia" — jangan mengarang.
- Bila `decision=abstain`, jangan tampilkan jawaban; tampilkan `failure_type`,
  jumlah bukti, dan coverage statement.
- Bila `calibrated_confidence` tidak ada, tampilkan "tidak terkalibrasi" dan
  jangan memberi warna hijau.
- `calibration_method`, `is_calibrated`, `abstain_reason`, `coverage_gap`,
  `generation_chunk_ids`, dan `context_chunk_ids` **belum diekspos** oleh
  `GatewayResponse`. MVP menampilkan "tidak tersedia" atau memakai
  `failure_type` + jumlah bukti; jangan mengarang nilai.
- `span_level_attribution[].text` dipotong 200 karakter oleh
  `rag-research/src/utils/attribution.py`. Tampilkan teks penuh dari
  `evidence[]` bila `chunk_id` cocok; jika tidak, tandai **teks terpotong**.
- `evidence[]` berasal dari `retrieved_chunks` (kandidat top-k), bukan hanya
  chunk yang dipakai saat generation. Jangan menampilkan kandidat sebagai bukti
  pendukung tanpa label **kandidat**.
- `span_level_attribution[].claim_span` adalah kalimat dari jawaban yang
  dihasilkan, bukan klaim/kode input. UI harus membedakan keduanya.

### 9.5 Unit review dan aksi manusia (MVP)

- **Unit review MVP:** klaim/kode yang diinput pengguna, bukan setiap kalimat
  jawaban. Ini sesuai alur CDI: satu kode ditinjau terhadap dokumentasi.
- **Aksi manusia:** `Terima`, `Tolak`, `Edit` — bukan lima verdict CDI.
  `Terima` berarti pengguna menyetujui temuan/zona untuk klaim input; `Tolak`
  berarti menolak; `Edit` menyunting teks klaim/kode secara lokal.
- **Audit trail:** simpan `request_id`, timestamp, aksi, teks klaim sebelum/
  sesudah edit, dan `calibrated_decision`/`calibrated_confidence` yang
  ditampilkan. Tidak ada auto-apply ke backend pada MVP.
- Jika nanti dibutuhkan verdict CDI formal (`SUPPORTED`,
  `PARTIALLY_SUPPORTED`, `NOT_DOCUMENTED`, `CONTRADICTED`,
  `INSUFFICIENT_EVIDENCE`), itu menjadi field backend/terpisah, bukan
  perhitungan UI.

---

## 10. Synthetic test data

Karena data pengujian belum ada, MVP menyertakan fixture sintetis. Tidak boleh
mengandung PHI; gunakan encounter dan catatan fiktif.

### 10.1 Skenario

| # | Klaim/kode | `calibrated_decision` | Zona | Tujuan uji |
|---|---|---|---|---|
| 1 | "Hipertensi essential" | `GENERATE` | Hijau | Bukti lengkap + atribusi |
| 2 | "Pneumonia tanpa kultur" | `PARTIAL_TRUST` | Kuning | Bukti parsial + peringatan |
| 3 | "Diagnosis X tidak ada di catatan" | `REJECT` | Merah | Abstention + coverage gap |
| 4 | "Obat Y diberikan tanpa dokumentasi" | `REJECT` | Merah | Bukti kosong/`unverified` |

### 10.2 Contoh fixture

```json
{
  "request_id": "dummy-001",
  "query": "Hipertensi essential",
  "answer": "Kode hipertensi didokumentasikan dalam catatan assessment.",
  "decision": "answer",
  "failure_type": "none",
  "evaluation_status": "completed",
  "calibrated_confidence": 0.82,
  "calibrated_decision": "GENERATE",
  "calibration_method": "isotonic",
  "span_level_attribution": [
    {
      "claim_span": "Hipertensi essential",
      "chunk_id": "chunk-001",
      "doc_id": "catatan-poli-001",
      "score": 0.82,
      "text": "Assessment: Hipertensi essential, tidak terkontrol.",
      "unverified": false
    }
  ],
  "evidence": [
    {
      "text": "Assessment: Hipertensi essential, tidak terkontrol.",
      "source_id": "catatan-poli-001",
      "chunk_id": "chunk-001",
      "score": 0.82
    }
  ]
}
```

Fixture disimpan di `mcp-gateway/web/audit/fixtures/` dan dimuat melalui tombol
**Muat contoh** atau fallback otomatis saat backend tidak tersedia. Pilihan
mekanisme diserahkan ke builder.

---

## 11. Security, PHI, accessibility, i18n

### Security/PHI

- **MVP bersifat demo-only dengan data sintetis.** Live mode terhadap korpus
  riset yang ada adalah uji wiring, bukan demo CDI yang valid secara klinis.
  Penggunaan data klinis nyata memerlukan fase produksi terpisah: auth/RBAC,
  BFF same-origin, persistensi audit, identitas reviewer, retensi/redaksi, dan
  model on-prem.
- Tidak ada data pasien asli di repo, fixture, log, atau issue tracker.
- Tidak ada request ke CDN, analytics, atau layanan eksternal pada mode produksi.
- Font dan asset di-bundle lokal.
- API key tidak boleh disimpan di JavaScript statis. Untuk deployment dengan
  auth aktif, UI harus dilayani melalui reverse proxy same-origin/BFF yang
  menyisipkan header auth.
- Middleware auth gateway melindungi `/audit/` dan `POST /audit` bila API key
  dikonfigurasi. Demo lokal memakai konfigurasi auth-disabled; jangan
  mengeksposnya ke jaringan bersama.
- Jangan mencatat isi catatan klinis ke console/log browser.
- Korpus RAG saat ini berisi PDF riset, bukan catatan klinis. Jangan
  mengklaim live mode sebagai validasi CDI sampai ada korpus klinis sintetis
  dan evaluasi terpisah.

### Accessibility

- WCAG 2.1 AA: kontras, focus visible, label form, aria-live untuk hasil.
- Keyboard-first: Tab/Enter untuk audit, Terima/Tolak/Edit, dan export.
- Warna zona selalu disertai teks dan ikon.
- Ukuran font minimum 14px; target klik minimum 44px.

### i18n

- String UI di file `messages.js` (atau objek `messages` di `app.js`).
- Bahasa Indonesia default; Inggris menyusul tanpa mengubah struktur.
- Istilah klinis mengikuti glosarium CDI (`docs/healthcare/DOMAIN.md`).

---

## 12. Implementation outline (untuk plan berikutnya)

Ini bukan rencana tugas rinci; rencana rinci dibuat melalui
`superpowers:writing-plans` setelah desain ini disetujui.

1. **Fixture:** buat 4 respons dummy JSON + skenario di `web/audit/fixtures/`.
2. **Layout:** ganti prototype dengan struktur tiga panel + zone banner + audit
   trail strip.
3. **Demo mode:** tombol "Muat contoh" dan fallback saat backend tidak tersedia.
4. **Live mode:** panggil `POST /audit` (fallback `/ask`), tangani loading,
   answer, abstain, error, empty.
5. **Interaksi:** klik klaim/bukti untuk highlight; Terima/Tolak/Edit lokal.
6. **Export:** unduh JSON berisi respons + keputusan manusia.
7. **A11y/responsive:** keyboard, kontras, light mode, layout sempit.
8. **Verifikasi:** perluas `scripts/smoke_audit_ui.sh` dan checklist manual.

---

## 13. Acceptance criteria (MVP)

- [ ] `http://localhost:8090/audit/` memuat UI tiga panel tanpa error console.
- [ ] Pengguna dapat mengaudit klaim dengan backend hidup dan melihat zona
      keyakinan + label + penjelasan.
- [ ] Mode demo menampilkan 4 skenario tanpa backend hidup.
- [ ] Daftar klaim dan bukti tampil side-by-side; klik klaim menyorot bukti dan
      sebaliknya.
- [ ] Abstention menampilkan `failure_type` dan coverage statement; tidak ada
      jawaban palsu.
- [ ] Tombol Terima/Tolak/Edit mengubah state lokal dan tercatat di audit trail.
- [ ] Export JSON mengunduh file yang berisi respons backend + keputusan manusia.
- [ ] Tidak ada request eksternal pada mode produksi (diverifikasi via DevTools).
- [ ] Tidak ada PHI di fixture, log, atau repo.
- [ ] Keyboard navigation dan kontras AA lolos checklist manual.
- [ ] `scripts/smoke_audit_ui.sh` diperluas dan lulus.

---

## 14. Keputusan yang masih pending

### 14.1 Perlu keputusan Anda (hasil builder-check)

| # | Pertanyaan | Rekomendasi | Mengapa penting |
|---|---|---|---|
| 1 | **Cakupan MVP:** demo-only dengan data sintetis, atau boleh memproses data klinis ter-de-identifikasi? | **Demo-only.** Data klinis nyata butuh auth/RBAC, BFF, persistensi audit, identitas reviewer, retensi, dan model on-prem. | Menentukan apakah UI ini alat demo atau sistem yang menyentuh PHI. |
| 2 | **Perluasan kontrak gateway:** boleh menambah field, atau UI harus tetap UI-only? | **Boleh minimal:** `calibration_method`, `is_calibrated`, `abstain_reason`, `generation_chunk_ids`/`context_chunk_ids`. | Tanpa field ini, audit trail dan panel bukti harus menampilkan "tidak tersedia" dan tidak bisa membedakan kandidat vs bukti yang dipakai. |
| 3 | **Unit review & aksi manusia:** per kode input atau per kalimat jawaban? | **Per kode input.** Tombol Terima/Tolak/Edit; bukan lima verdict CDI. | Menentukan data model, tombol, dan skema export. |
| 4 | **Provenance bukti:** cukup teks verbatim + `source_id`/`chunk_id`, atau perlu judul/tanggal/halaman/offset? | **Teks + ID untuk MVP.** Metadata halaman ditambahkan saat ada korpus klinis nyata. | `SAFETY.md` meminta lokasi; UI demo tidak boleh mengklaim lebih dari data yang ada. |
| 5 | **Export audit:** apakah perlu identitas reviewer, rationale, dan schema version? | **Opsional di demo; wajib di produksi.** Sertakan `schema_version`, timestamp, aksi, dan field reviewer opsional. | Menentukan skema export dan kontrol PHI. |

### 14.2 Diserahkan ke builder

1. **`/audit` vs `/ask`:** gunakan `/audit` bila kontraknya sudah mengembalikan
   field audit; jika belum, gunakan `/ask` dan catat sebagai gap.
2. **Demo mode:** fallback otomatis saat fetch gagal, atau tombol eksplisit?
   (Disarankan tombol eksplisit agar mode live vs demo tidak ambigu.)
3. **Penyimpanan keputusan manusia:** MVP hanya di memori/lokal; belum ada
   endpoint persist. Jika nanti perlu audit trail server-side, tambahkan
   endpoint gateway.
4. **`abstain_reason`/`coverage_gap`:** belum ada di kontrak. MVP memakai
   `failure_type` + jumlah bukti. Usulkan penambahan field di iterasi backend
   berikutnya.
5. **Multi-klaim:** MVP satu klaim per audit. Jika CDI membutuhkan satu
   encounter dengan banyak kode, desain ulang input menjadi daftar kode.

---

## 15. Risks

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Kontrak `/audit` berubah | UI rusak | Fixture + contract test; verifikasi sebelum rilis |
| Atribusi heuristik lemah | Bukti tidak akurat | Tandai `unverified`; tampilkan teks verbatim; manusia memutuskan |
| PHI bocor lewat fixture/log | Kepatuhan | Data sintetis; review sebelum commit; no telemetry |
| UI terlalu ambisius | MVP terlambat | Batasi pada satu klaim, JSON export, tanpa case queue |
| Auth di browser | API key bocor | Reverse proxy same-origin/BFF; jangan simpan key di JS |
| Warna disalahartikan | Automation bias | Label + penjelasan + tombol keputusan manusia |

---

## 16. Referensi

- `docs/healthcare/INTENDED_USE.md`
- `docs/healthcare/SAFETY.md`
- `docs/healthcare/DOMAIN.md`
- `docs/confidence-calibration.md`
- `mcp-gateway/docs/api-contract.md`
- `mcp-gateway/web/audit/` — prototype saat ini
- `docs/ROADMAP.md` — Phase 4
- `docs/superpowers/specs/2026-10-25-mcp-stdio-bridge-design.md` — format spec
