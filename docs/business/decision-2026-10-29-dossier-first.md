# Decision Record — Arah Produk: SaaS Dossier-First (MCP sebagai Kanal)

> **Tanggal keputusan:** 2026-10-29
> **Status:** DECIDED — dikonfirmasi owner dalam sesi arah produk 2026-10-29
> (pemilihan "Commit dulu perubahan tertunda" lalu instruksi "rebuild dokumennya
> agar sesuai dengan saran-saran di atas" adalah tindak lanjut resmi keputusan ini).
> Eksekusi kode mengikuti gerbang `writing-plans` (desain disetujui → rencana tugas
> per repo → implementasi per taskboard).
> **Supersedes:** ranking utama di [`product-strategy.md`](product-strategy.md) (MCP-primary) untuk keputusan arah produk.
> **Konteks:** debat arah "agentic vs SaaS", kemudian kriteria eksplisit dari owner:
> nilai jual tinggi **sekarang**, bisa dikembangkan **berkala**, dan **tidak mudah
> tergantikan** oleh tool yang terus diperbarui.
> **Turunan berikutnya:** goals per-repo + urut bangun: [`docs/vertical-1/GOALS-PER-REPO.md`](../vertical-1/GOALS-PER-REPO.md).

---

## 1. Dua sumbu yang sering tertukar

| Sumbu | Pertanyaan | Pilihannya |
|---|---|---|
| Bentuk antarmuka | manusia-di-browser, atau tool bagi agen AI? | App UI ↔ API/MCP tool ↔ keduanya |
| Model bisnis & pengiriman | self-host, atau cloud berlangganan? | self-host ↔ SaaS ↔ hybrid |

"Agentic vs SaaS" bukan pilihan biner. Produknya disusun: **antarmuka utama laporan
manusia (SaaS-shaped), distribusi tetap via MCP** — satu pipeline, dua permukaan.

## 2. Evaluasi ketiga kriteria owner

1. **Nilai jual sekarang** → SaaS. Pembeli (tim R&D, konsultan paten, editor jurnal)
   punya anggaran dan urgensi hari ini (WTP HIGH; ROI vs audit manual `$500/jam`).
   Pasar MCP masih edukasi + billing per-call tipis.
2. **Pengembangan berkala** → SaaS. Ekspansi vertikal hampir tak berujung
   (connector korpus, integrasi workflow, format ekspor) dan dibiayai arus kas langganan.
3. **Anti tergantikan** → bukan UI/tool-nya, melainkan **aset vertikal yang
   terakumulasi**: data audit berlabel → refit kalibrasi isotonik (ECE kini 0.0576,
   194 sampel), audit-trail kepatuhan (tabel log existing), kunci workflow.
   Tool-API tipis paling mudah diganti (Risk 1 di strategy doc); model generatif makin
   pintar justru meng-komoditisasi *jawaban* dan menaikkan nilai *verifikasi*.

## 3. Output per repo (korrek menurut ownership PROJECT_GOALS §2)

| Repositori | Output yang harus dihasilkan | Peran |
|---|---|---|
| `rag-research` | `POST /verify_claim` + `POST /verify_claims` (batch): `decision`, `calibrated_confidence`, `confidence_zone`, `evidence`, `span_level_attribution`; pemecah klaim deterministik (non-LLM) | Otak audit per klaim |
| `llm-eval-framework` | `POST /evaluate_batch`: hasil per klaim + `summary` ringkasan; dataset berlabel klaim-manuskrip untuk refit (ECE < 0.10) | Kredibilitas per klaim |
| `mcp-gateway` | REST: `POST /reports`, `GET /reports/{id}`, `export.md/.json` (P0), `export.pdf` (P1), `GET /r/{share_token}`; tabel `audit_reports` + `audit_report_claims`; MCP: `generate_audit_dossier` menjadi dossier sungguhan (+ `report_url` opsional) | Pintu SaaS + kanal MCP |
| `arxiv-research-assistant` | Enrich sitasi: `GET /papers/source/{arxiv_id}` → author/title/year/url untuk bibliografi; korpus tumbuh terus | Bahan bukti & sitasi |
| Root workspace | `make smoke-reports` (atau perluasan `smoke_e2e`); antara P0 tak ada jasa baru (render MD berada di gateway; PDF di P1) | Orkestrasi & gate |

Alur: `POST /reports` (gateway) → batch `verify_claims` + `evaluate_batch` + enrich
sitasi → persist → render report + share link. Jalur MCP memanggil tool langsung
tanpa menyimpan manuskrip user.

## 4. Tahapan & gerbang

- **P0 (MVP):** paste-klaim → laporan browser + `export.md/.json` + share link.
  Tanpa billing / unggah file. Prasyarat: benahi `generate_audit_dossier`
  (addendum di [`p0-consolidation`](../superpowers/plans/2026-10-26-p0-consolidation.md)).
- **P1:** `export.pdf`, unggah DOCX, riwayat per org, fondasi multi-tenancy
  (`api_keys → org_id`), refit kalibrasi dari audit terkumpul, `report_url` di MCP.
- **P2:** connector korpus paten USPTO/EPO (**prasyarat** niche patent-firm),
  billing, SSO, format ekspor USPTO/EPO, tier $100/audit → $1.000/bln tim.

Gerbang tetap: `make test` 921+ PASS, `check-secrets` CLEAN, P95 ≤ 4.5 s per klaim,
ownership repo tidak dilanggar, tanpa membaca/mengubah `.env`.

## 5. Gap enabler sebelum membangun permukaan laporan

B1 dossier sungguhan (gateway) · B2 `verify_claim(s)` + splitter (rag-research) ·
B3 `/evaluate_batch` (eval) · B4 persistensi + share token + scoping (gateway) ·
B5 enrich sitasi (arxiv). Tidak ada yang perlu dioverhaul: monitoring, auth/tier,
circuit breaker, transport MCP, modul `attribution.py`, dan modul kalibrasi
terpakai apa adanya. `rag-research/archive/dead_scripts_2026_10/` tidak relevan.

## 6. Rekonsiliasi dokumen yang menyertai keputusan ini (A1–A5)

A1 status basi di `PROJECT_GOALS.md`/`AGENTS.md` → dirapikan, 2026-10-29.
A2 addendum keputusan di `product-strategy.md` — selesai.
A3 addendum `p0-consolidation.md` (item 7 digabung ke Vertical 1 P0) — selesai.
A4 kontrak baru §4.4–§4.7 di `PROJECT_GOALS.md` (status *planned*) — selesai.
A5 dokumen ini + seksi Vertical 1 di `docs/ROADMAP.md` — selesai.

## 7. Referensi

- `PROJECT_GOALS.md` §2 (ownership), §4 (kontrak), §6 (zona keyakinan)
- `docs/ROADMAP.md` (seksi Vertical 1)
- `docs/business/product-strategy.md` (analisis pasar; ranking lama)
- `docs/superpowers/plans/2026-10-26-p0-consolidation.md` (gabungan item 7)
