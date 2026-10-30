# Plan: Hari Ini — Rust Inference Service (Task 1–4, offline-safe)

## Goal
Menyelesaikan Task 1–4 dari plan Rust inference service (`2026-10-28-rust-inference-service.md`): scaffold crate, worker pool, kontrak `/embed`, dan ONNX embedding — tanpa menyentuh rag-api/produksi. Safe offline (crates.io diblokir, gunakan cargo cache).

## Context / Network Findings (2026-10-28)
- HuggingFace: HTTP 200 → model export Task 7 (jika waktu) feasible.
- GitHub: HTTP 200 → unduh tarball ORT (Task 10) feasible.
- crates.io: HTTP 403 → crate baru tidak boleh diunduh; pakai cache lokal `~/.cargo/registry`. `ort-2.0.0-rc.15` sudah ada di cache.
- Working tree kotor (root + 4 submodule modified/untracked) → bersihkan sebelum task baru.

## Preflight (wajib sebelum Task 1)
1. Bersihkan working tree: commit/stash perubahan existing per repo; git status scoped.
2. `make check-secrets` → CLEAN.
3. `make status` → baseline layanan.
4. Verifikasi cached deps di `~/.cargo/registry/cache/*/`: tokio, serde, axum, tokenizers, ndarray, ort (ort sudah confirmed). Jika salah satu hilang, hindari crate baru / tunda Task 1.

## Scope Hari Ini (in)
### Task 1: Scaffold crate
`rag-research/services/inference/Cargo.toml`, `src/main.rs`, `src/lib.rs`, `src/config.rs`, `src/error.rs`, router dengan `/health`, `/ready`, `/metrics`, error envelope JSON.

### Task 2: Worker pool
`BatchModel<R, T>` trait, bounded queue, dynamic batching window 3 ms, 503 `queue_full` ketika penuh.

### Task 3: Kontrak `/embed`
DTO (`EmbedRequest`/`EmbedResponse`), validasi (query kosong/whitespace → 400, too many texts → 413), timeout, `X-Request-ID`, single string vs list → `(1, d)` vs `(n, d)`.

### Task 4: ONNX embedding
Mean-pool + L2-normalize, truncation ke `max_length`, deteksi `truncated`, Unicode (naïve café 日本語) tidak panic.

Task 7 opsional hanya jika waktu & deps cache mencukupi: export model ONNX di host, validasi parity cosine ≥ 0.9999, tulis manifest.json SHA256.

## Out of Scope Hari Ini
Task 5–6, 8–15 (rerank contract, Python client, registry integrasi, Docker image, Compose, cutover). Tidak menghapus torch dari runtime rag-api. Tidak mengubah `.env`/secrets.

## Rollout / Rollback (hari ini belum diterapkan)
Rollout shadow → embedding → reranker → hapus torch (Task 8–15). Rollback lewat `INFERENCE_BACKEND=local` + image tag lama. Default saat ini: `local`.

## Validation Gate
- `cargo fmt -- --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test --locked` lulus di `rag-research/services/inference`.
- Setiap task: test gagal dulu (red), implementasi, test lulus (green), commit atomik.
- Tidak `git add -A`/`git add .`; tidak commit `models/*.onnx`; `make check-secrets` CLEAN.

## Risks
- crates.io 403: Task 1 gagal jika crate yang dibutuhkan tidak ada di cache → verifikasi preflight wajib.
- Working tree kotor: diff task tercampur → bersihkan dulu.

## Open Questions (sebelum mulai)
- Konfirmasi prioritas: kerjakan Rust Task 1–4 hari ini (disarankan, tidak butuh Groq) atau tutup Phase 1 acceptance dulu (butuh kuota Groq)? Default rencana: Rust Task 1–4.
