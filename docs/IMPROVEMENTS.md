# Value Proposition & Improvement Roadmap

> **Workspace:** ai-infra-workspace
> **Produk:** Scientific Claim & Prior-Art Auditor
> **Tujuan:** meningkatkan nilai jual (B2B/B2C) dan kesiapan enterprise.

## 1. Posisi & Diferensiasi (Core Value)
- **Grounded + hard abstention + span-level attribution** — jawaban selalu punya bukti; tanpa bukti → abstain.
- **No-LLM-judge evaluation** (faithfulness evaluator deterministik) → reproducible & auditable untuk regulasi.
- **Confidence calibration (ECE 0.0368)** → confidence yang bisa dipercaya, bukan skor kosmetik.

## 2. Fitur yang Meningkatkan Willingness-to-Pay (P1–P2)
- Claim Audit UI (Phase 4): side-by-side claim vs evidence, highlight span merah/kuning/hijau, ekspor laporan (PDF/Markdown/JSON).
- Audit trail & reproducibility: request_id, evidence chain, model version, timestamp, hash dokumen.
- Multi-tenant + per-tenant corpus: koleksi Qdrant per tenant, API key per tenant, quota.
- Role-based access (admin/analyst/viewer) + SSO (OIDC/SAML) untuk enterprise.
- Webhook/callback ke Slack/Teams/Notion saat audit selesai.

## 3. Kualitas & Keandalan (Menaikkan Harga Kontrak)
- Dataset ≥ 1000 labeled queries (saat ini 194, 137 unik) + dedup.
- Latency SLO (P95 ≤ 3.5s) terukur & terdokumentasi + benchmark page publik.
- Fallback chain: Groq → Ollama → abstain; SLA jelas saat provider down.
- Rate limit per-key tier (free/pro/enterprise) → monetisasi langsung.

## 4. Enterprise Readiness
- SSO + RBAC + audit log immutable (append-only / WORM).
- Data residency: on-prem / VPC; image hermetic (sudah ada) memudahkan.
- PII redaction pada ingest & query; encryption at rest + TLS.
- SLO/SLA dashboard (Grafana + alerting) + status page.
- Backup/restore drill (script sudah ada) → disaster recovery included.

## 5. Monetisasi & Packaging
- Tiering: Free (N query/bulan, 1 corpus) → Pro (quota lebih tinggi, export, API) → Enterprise (SSO, on-prem, SLA, support).
- Usage-based: charge per claim audited / per 1k tokens / per dokumen ingested.
- Marketplace connectors: arXiv (sudah), tambah PubMed, IEEE, patent (USPTO/EPO), internal docs (Confluence/SharePoint).
- White-label: UI bisa di-brand per customer (logo, warna, domain).

## 6. GTM & Bukti (Menaikkan Harga)
- Case study + benchmark: “X% reduction in manual fact-checking”, “abstention precision Y%”.
- Demo dataset (paper publik) + 1-click trial (Docker) → onboarding cepat.
- OpenAPI + SDK (Python/JS) untuk developer adoption.

## 7. Risiko yang Harus Di-mitigasi
- Kunci Groq jangan di-commit (sudah ada check-secrets) → pastikan CI gate aktif.
- Binary 19MB ter-track (STATUS FAIL) → hapus dari index + .gitignore.
- CI branch mismatch main vs master → perbaiki agar pipeline kredibel.
- Release tag → buat v1.0.0 setelah smoke PASS untuk sinyal stabilitas.

## 8. Prioritas 30 Hari (Urut)
1. Smoke test PASS + mode auth dev/prod jelas.
2. Phase 4 UI MVP (input claim + evidence + confidence zone + export JSON/MD).
3. Multi-tenant collection + per-tenant API key.
4. Dataset ≥ 500 labeled + laporan kalibrasi publik.
5. SSO (minimal OIDC) + audit log.
6. Tag v1.0.0 + case study.

> Fokus pada audit trail + abstention + attribution sebagai core value; UI dan enterprise features adalah multiplier harga.

## Appendix — Rate Limit per-Key Tier (Task 5)
Lihat detail implementasi di `mcp-gateway/internal/middleware/per_key_rate_limit.go` dan `internal/config/config.go`.
Tier: free (10 RPM, burst 5), pro (60 RPM, burst 20), enterprise (300 RPM, burst 100).
Mapping via env `GATEWAY_KEY_TIERS=key:tier,...`.
MD
