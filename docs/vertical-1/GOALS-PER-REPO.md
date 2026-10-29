# Vertical 1 — Goals per Repositori (spec anchor implementasi P0)

> **Tanggal:** 2026-10-29 · **Owner keputusan:** owner workspace (DECIDED — lihat
> [`decision-2026-10-29-dossier-first.md`](../business/decision-2026-10-29-dossier-first.md))
> **Rantai sumber kebenaran:** decision record (kenapa) → **dokumen ini (apa & penerimaan)**
> → task per repo di [`ai-taskboard.md`](../ai-taskboard.md) (siapa & kapan) → plan eksekusi (bagaimana).
> **Kontrak rujukan:** `PROJECT_GOALS.md` §4.4–§4.7 (status *planned* — dokumen ini yang menaikkan mereka menjadi deliverable P0).

---

## 0. Aturan global (berlaku untuk SEMUA repo)

1. **Gate yang sama & tidak bisa dinegosiasi:**
   - Full suite tiap repo tetap hijau (baseline 921: arxiv-go 15, python-ml 45, gateway 143 `-race`, eval 226, rag 492).
   - `make check-secrets` CLEAN sebelum setiap commit.
   - Latensi: P95 ≤ 4.5 s per klaim; batch N klaim ≤ N × 1,2× latensi satu klaim.
   - Zona keyakinan **0.35 / 0.65** tidak boleh berubah (kode sudah teruji; lihat p0-consolidation).
   - Tanpa LLM-as-judge, tanpa jawaban tanpa bukti (hard abstention tetap identitas produk).
2. **Ownership** mengikuti `PROJECT_GOALS.md` §2 tanpa pengecualian; tidak ada repo memanggil repo lain di luar kontrak §4.
3. **Eksekusi per repo di branch sendiri**, commit prefix `opencode:`, tanpa push, lapor hash ke taskboard. Integrator menjalankan `make test` / `smoke-e2e` di root.
4. Semua deliverable baru berstatus **additive** — kecuali satu benahan eksplisit: `generate_audit_dossier` (dossier sungguhan).

## 1. Daftar antarmuka bersama (bahan pre-flight skema plan eksekusi)

| Produsen → Artefak | Konsumen | Rangkaian kontrak |
|---|---|---|
| rag-research → `verify_claims` (batch, per klaim: keputusan, zona, evidence, attribution) | gateway (rapat laporan), llm-eval (pasangan klaim-konteks dari evidence) | §4.4 |
| llm-eval → `evaluate_batch` (per klaim + summary) | gateway (blok kredibilitas laporan) | §4.5 |
| arxiv-go → `papers/source/{arxiv_id}` (metadata sitasi) | gateway (bibliografi laporan) | §4.7 |
| gateway → `audit_reports`/`audit_report_claims` + export + share token | browser manusia; jalur MCP (`report_url`) | §4.6 |

Catatan pre-flight: B3 (eval batch) menerima **konteks dari hasil retrieval** rag — bukan teks bebas;
draft kontrak §4.5 perlu disahkan ulang saat plan eksekusi ditulis (field `context` berasal dari evidence
terpilih, bukan input user) agar tidak ada jalur halusinasi evaluator.

## 2. `rag-research` — "Otak audit per klaim"

**Goal satu kalimat:** manuskrip user berubah menjadi putusan per-klaim yang terkalibrasi, teratribusi, dan bisa diabstainsi — tanpa mengubah perilaku pipeline `/generate` yang ada.

**P0 deliverable & penerimaan:**

| ID | Deliverable | Kriteria penerimaan (terukur) |
|---|---|---|
| R-1 | Pemecah klaim deterministik (`claim splitter`, non-LLM) | Input identik → pecahan identik (uji determinisme); batas antar kalimat mengikuti tanda baca; unit `tests/test_claim_splitter.py` |
| R-2 | `POST /verify_claim` (kontrak §4.4) | Respons berisi `decision`, `calibrated_confidence`, `confidence_zone`, `evidence`, `span_level_attribution`; `decision=abstain` saat evidence di bawah zona merah (mirror F-01); TIDAK memanggil generator saat abstain |
| R-3 | `POST /verify_claims` (batch, kontrak §4.4) | N klaim → N hasil; **default cap 50 klaim/request** (angka ini akan dikukuhkan di plan eksekusi); status batch + latensi diamortisasi |
| R-4 | Kontrak test: schema request/response di-contract-test | Gagal cepat saat field hilang; suite 492 tetap hijau + test baru |

**MUST NOT:** simpan manuskrip user (kondisi staging opsional tak lebih dari TTL cache), render laporan, memanggil arxiv/eval/gateway di inti loop.
**Ketergantungan:** tidak ada (paling awal boleh dibangun).
**Test:** `python -m pytest tests/ -q` (iterasi: targeted).

## 3. `llm-eval-framework` — "Kredibilitas per klaim"

**Goal satu kalimat:** tiap klaim yang dijawab dapat skor kesetiaan deterministik (tanpa LLM-judge) plus ringkasan batch yang bisa ditempel ke laporan.

| ID | Deliverable | Kriteria penerimaan |
|---|---|---|
| E-1 | `POST /evaluate_batch` (kontrak §4.5) | N pasangan klaim-konteks → `results[]` + `summary{avg_faithfulness, supported_% / partial_% / unsupported_%}`; deterministik (input sama → skor sama) |
| E-2 | Integrasi sumber konteks: field `context` = evaluasi terhadap bukti yang diambil rag (bukan kalimat bebas dari user) | Kontrak disahkan saat plan; kasus timeout & abstain masuk `failure_mode` |
| E-3 | Dataset berlabel klaim-manuskrip (offline, tanpa layanan) | ≥ 50 sampel seed dari ulasan internal; menandai jalur refit isotonic P1 (ECE < 0.10 tetap) |

**MUST NOT:** jadi oracle kebenaran; memanggil LLM judge; mengubah `/evaluate` single agar tidak kompatibel mundur (jalur pilot harus tetap hijau).
**Ketergantungan:** tahan-henti penuh dari R-2/R-3 (field evidence).
**Test:** `python -m pytest tests/ -v` (baseline 226 + baru).

**Catatan ketegasan (E-2):** grader penerimaan "didukung konteks apa" ikut narasi. Konversi dari `evidence` ke `context` **diputuskan sendiri saat pembangunan**, bukan sesudahnya.

## 4. `mcp-gateway` — "Pintu SaaS + kanal MCP"

**Goal satu kalimat:** satu pintu masuk untuk dua permukaan — REST laporan manusia (browser + export + share link) dan MCP tools untuk agen — dengan persistensi audit yang bisa di-join via `request_id`.

| ID | Deliverable | Kriteria penerimaan |
|---|---|---|
| G-1 | Persistensi: tabel `audit_reports` + `audit_report_claims` (kontrak §4.6) | Migrasi additive; baris join-able ke `gateway_query_logs` via `request_id`; tak mengubah tabel existing |
| G-2 | `POST /reports` → `{report_id, status}` | Klaim paste (array), scoping per API key tanpa full multi-tenancy; rate limit tier existing berlaku |
| G-3 | `GET /reports/{id}` + `export.md`/`export.json` | Konten report = *persisted rows* (bukan re-render live from scratch); zona, evidence, sitasi, blok evaluasi |
| G-4 | `GET /r/{share_token}` read-only publik | Token tidak dapat ditebak (`crypto/rand` ≥ 128 bit); tanpa login; TTL default 30 hari; dapat dicabut oleh pemilik API key |
| G-5 | `generate_audit_dossier` → dossier sungguhan | Mengembalikan metrik + per-klaim + opsi `report_url`; deskripsi tool & output terdokumentasi (penutup item 7 p0-consolidation) |
| G-6 | Kontrak test + perluasan `smoke_e2e` | Path `/reports` + share link masuk smoke; `gateway_query_logs` baru terverifikasi per request; `-race` hijau |

**MUST NOT:** parsing PDF raw, indexing vector, keputusan kualitas jawaban (tetap delegasi §4.4/§4.5).
**Ketergantungan:** R-3 (hasil batch), E-1 (blok evaluasi), A-1 (metadata sitasi).
**Test:** `go test ./... -v -race` (baseline 143 + baru).

**Catatan komposisi (G-5):** renaman tool adalah perubahan kontrak publik — jika didilakukan, dokumentasikan di `docs/mcp-integration-guide.md` dan README root pada commit yang sama; outbreak saat masih pakai nama lama di P0.

## 5. `arxiv-research-assistant` — "Bahan bukti & sitasi resmi"

**Goal satu kalimat:** setiap `arxiv:<id>` di evidence bisa bergeser menjadi sitasi resmi (author/title/year/url) untuk bibliografi laporan — korpus terus tumbuh tanpa dijam.

| ID | Deliverable | Kriteria penerimaan |
|---|---|---|
| A-1 | `GET /papers/source/{arxiv_id}` (kontrak §4.7) | `arxiv:1706.03762` → `{source_id, title, authors[], year, url}`; 404 untuk id tak dikenal; batch stage ≤ 100 id |
| A-2 | Jalur ingestion & `/query` existing tanpa regresi | Test 15 + 45 tidak berkurang; TIDAK membuka jalur legacy `/query` ke produk claim-audit (tetap demote sesuai p0-consolidation task 1) |

**MUST NOT:** routing lintas-repo; evaluasi di luar domain paper.
**Ketergantungan:** tidak ada; bisa paralel dengan R/E.
**Test:** `go test ./... -v` + `PYTHONPATH=. python -m pytest tests/ -v`.

## 6. Root workspace — "Orkestrasi & gerbang"

| ID | Deliverable | Kriteria penerimaan |
|---|---|---|
| W-1 | `make smoke-reports` (atau perluasan `scripts/smoke_e2e.sh`) | POST /reports → poll status → GET export.md → GET /r/… 200; request ID unik; baris `audit_reports` baru terikat run id |
| W-2 | TIDAK ada service baru di P0 | Render MD di dalam gateway; PDF & service render = P1; topologi 11 tetap |

**Gate root per integrator:** `make test` → `make smoke-e2e` → `make check-secrets`.

## 7. Urut bangun (keputusan dependensi; perbarui di taskboard)

```
T1: rag-research R-1..R-4        (fondasi; tanpa ini evaluator & gateway buta)
T2: arxiv A-1..A-2               (paralel aman, kecil)
T3: eval E-1..E-2                (terkunci ke R; E-3 offline boleh mendampingi)
T4: gateway G-1..G-3             (persistensi + REST, terkunci ke R/E/A)
T5: gateway G-4..G-6             (share link + dossier sungguhan + smoke)
```

## 8. P1/P2 (pencegahan creep — sebut, jangan bangun)

- **P1:** `export.pdf`, unggah DOCX→teks, workspace riwayat per org, fondasi multi-tenancy (`api_keys → org_id`), refit kalibrasi dari audit terkumpul, `report_url` di jalur MCP.
- **P2:** connector korpus paten USPTO/EPO (prasyarat niche patent firm), billing (tier $100/audit → $1.000/bln tim), SSO, format ekspor USPTO/EPO.

## 9. Definition of Done (dari CONVENTIONS §5, diulang di sini agar tidak terlupakan)

1. Perubahan hanya di file scope tugas; tidak menyentuh file dirty milik lain.
2. Targeted test hijau; full suite saat tuntas; output test dicantumkan di laporan.
3. `git status` bersih dari file tak relevan; commit atomik `opencode:`.
4. Laporan: apa yang diubah, perintah test, hasil, risiko, hash commit.
5. Timebox/ambiguitas → berhenti dan lapor, jangan improvisasi.
