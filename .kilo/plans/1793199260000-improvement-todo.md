# Plan: Improvement & Addition Todo List (Sistem Saat Ini)

## Goal
Menyusun daftar kerja (todo list) yang bisa dieksekusi bertahap untuk meningkatkan kualitas, keandalan, keamanan, dan nilai produk dari Scientific Claim & Prior-Art Auditor, tanpa mengubah scope menjadi fitur spekulatif.

## Context
- Phase 1 smoke runtime PASS, tetapi `phase1_pass=false` karena semua 15 case answerable di-reject pre-gen confidence gate dan human review belum selesai.
- Full test suite PASS (228 + 193 + 48 + 500).
- Root E2E smoke PASS, SSE runtime terverifikasi.
- Gap yang tersisa: kualitas jawaban, dataset dedup/ekspansi, Phase 4 UI, enterprise readiness.

## Todo List (Prioritas)

### P0 — Stabilisasi Kualitas (blokir acceptance)
- [ ] Diagnosa pre-gen confidence gate: log `confidence_score`, threshold, top-k, overlap untuk 15 case answerable.
- [ ] Tuning retrieval/chunking (top_k, rerank threshold, chunk size) dan dokumentasikan eksperimen.
- [ ] Re-run Phase 1 smoke (20 case, 0 provider error).
- [ ] Lakukan human review 15 case answerable + check report (`phase1_pass=true`).
- [ ] Tambah regression test untuk kasus yang sebelumnya false-abstain.

### P1 — Kualitas Data & Evaluasi
- [ ] Dedup dataset kalibrasi (151 unik → hapus 63 duplikat).
- [ ] Ekspansi dataset ke ≥500 labeled (tanpa synthetic duplication).
- [ ] Refit kalibrasi (isotonic) + update ECE report.
- [ ] Tambah metrik: abstention precision/recall, citation accuracy, groundedness.
- [ ] Adversarial test: prompt injection, off-domain, contradictory evidence.

### P2 — Phase 4 Claim Audit UI (MVP)
- [ ] Input claim → evidence side-by-side.
- [ ] Zone warna confidence (red/yellow/green).
- [ ] Export laporan JSON/Markdown (PDF opsional).
- [ ] Audit trail view (request_id, evidence chain, model version, timestamp, hash).
- [ ] SSE streaming untuk progress audit.

### P3 — Enterprise Readiness
- [ ] Multi-tenant: koleksi Qdrant per tenant + API key per tenant + quota.
- [ ] RBAC (admin/analyst/viewer) + SSO (OIDC minimal).
- [ ] Audit log immutable (append-only/WORM) + hash chain.
- [ ] PII redaction ingest & query; TLS + encryption at rest.
- [ ] Fallback chain Groq → Ollama → abstain + drill.

### P4 — Konektor & Ekosistem
- [ ] Tambah sumber: PubMed, IEEE, USPTO/EPO, internal docs.
- [ ] SDK Python/JS berbasis OpenAPI.
- [ ] Webhook/callback (Slack/Teams/Notion) saat audit selesai.
- [ ] White-label UI (logo/warna/domain).

### P5 — Operasional & Keamanan
- [ ] Container hardening (non-root, read-only FS, resource limits).
- [ ] Security scan CI (Trivy, govulncheck, pip-audit) + SBOM.
- [ ] Backup/restore drill + RTO/RPO terdokumentasi.
- [ ] SLO dashboard + alert test + status page.
- [ ] Cost accounting (token per request, quota per tier).

### P6 — Developer Experience
- [ ] Contract tests antar repo (OpenAPI/JSON schema).
- [ ] Load test (k6/locust) + P95 report.
- [ ] Mutation testing untuk logika kritis.
- [ ] Local dev seed data + mock provider offline.
- [ ] Make targets: `lint`, `fmt`, `bench`, `chaos`.

## Risks
- Tuning confidence bisa menurunkan abstention precision; wajib re-run smoke + human review.
- Ekspansi dataset membutuhkan kuota Groq dan Qdrant; blokir jika quota habis.
- Multi-tenant mengubah skema DB/Qdrant; butuh migrasi dan backup.

## Validation
- `make test` PASS.
- `make smoke-e2e` PASS.
- `phase1_pass=true` dan `human_review_complete=true`.
- `make check-secrets` CLEAN.
- Status report tidak menambah FAIL baru.

## Out of Scope
- Perubahan arsitektur besar di luar batas repo.
- Fitur yang tidak terkait audit trail/abstention/attribution.

## Open Questions
1. Apakah tuning confidence dilakukan sebelum atau setelah ekspansi dataset? Rekomendasi: tuning dulu pada dataset v3, lalu ekspansi.
2. Apakah Phase 4 UI dibangun sebagai service terpisah atau di gateway? Rekomendasi: service terpisah dengan API kontrak stabil.
EOF
