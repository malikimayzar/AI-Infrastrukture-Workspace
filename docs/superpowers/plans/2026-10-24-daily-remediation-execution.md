# Daily Remediation Execution Plan — 2026-10-24

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`
> to execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Setiap task harus melewati review fresh subagent sebelum task berikutnya.

**Goal:** Menutup Fase 0 (keamanan + reproduktibilitas) dan menyelesaikan P0 data/failure
semantics ArXiv, RAG provider taxonomy, checkpoint eval, serta pemetaan provider error di
gateway pada hari ini.

**Architecture:** Eksekusi berurutan per workstream di lima repo (root, arxiv, rag, eval,
gateway). Setiap task menghasilkan satu commit yang bisa direview sendiri; submodule
di-push sebelum gitlink root diperbarui. Verifikasi runtime lintas-service dilakukan
setelah kontrak `/ready` dan provider error tersedia.

**Tech Stack:** Go 1.x, Python 3.12, FastAPI, pytest, Qdrant, PostgreSQL, Docker Compose,
Groq/Ollama.

**Spec:** `docs/superpowers/plans/2026-10-24-cross-repo-remediation.md`

---

## Global Constraints

1. Satu task = satu commit. Stage path/hunk eksplisit; dilarang `git add -A`/`git add .`.
2. TDD wajib: test gagal (RED) → implementasi → test hijau (GREEN) → commit.
3. Submodule dulu: commit/push submodule, baru update gitlink root.
4. Jangan commit WIP yang tidak termasuk task. Root `.env.example`, Compose formatting,
   dan 48 file gateway WIP tetap di working tree sampai task yang relevan.
5. Jangan pernah menulis kunci asli ke test, fixture, dokumen, atau log.
6. Provider error → HTTP 502 + `decision="error"` (keputusan disetujui).
7. Corpus production tetap v2 796; v3 642 hanya acceptance in-process.
8. Auth ditunda ke P3; port loopback di P2.
9. Push hanya ke branch `remediation/2026-10-24`, bukan `main`.
10. Jika Docker/build tidak tersedia, catat “belum diverifikasi”; jangan klaim selesai.

## Review Focus

| # | Input / failure mode | Perilaku yang diharapkan | Test owner |
|---|---|---|---|
| 1 | arXiv ID versioned (`2312.10997v2`) masuk ingest/filter/delete | Dinormalisasi ke `2312.10997` di PG, Qdrant payload, point ID, dan filter | A1 |
| 2 | PDF tanpa teks atau chunk kosong | Ditolak sebelum ada tulisan PG/Qdrant; paper lama tidak terhapus | A3 |
| 3 | Groq 429/timeout/invalid JSON/auth | `failure_type="provider_error"` + `provider_error_kind`, bukan abstention | R1/G2 |
| 4 | Checkpoint `faithfulness_result: null` atau field hilang | Dianggap belum selesai, case dijalankan ulang, tidak crash | E1/E2 |
| 5 | Qdrant gagal setelah PG commit | PG di-rollback/kompensasi, vektor lama dipulihkan, tidak ada data hilang | A4 |

## Current State (awal hari)

- **0.1** selesai repo-side (`465abd9`); scanner CLEAN. Revoke key Groq masih milik user.
- **0.2** selesai; branch `remediation/2026-10-24` di lima repo; snapshot di
  `/tmp/ai-infra-remediation/`.
- **0.3** selesai dan lolos review (`c260e0c`).
- **0.5** sedang berjalan di background; **belum boleh diklaim selesai**.
- **0.4** push disetujui, ditunda sampai review 0.5 selesai.
- Ledger: `.superpowers/sdd/2026-10-24-cross-repo-remediation/progress.md`.

## Today's Definition of Done

- [ ] Task 0.5 direview dan diterima; tidak ada `COPY hf-cache/`; build image lolos.
- [ ] Empat branch submodule ter-push; clone bersih + `docker compose config` lolos.
- [ ] A1, A3, A4 hijau dan tercommit di arxiv.
- [ ] R1 hijau dan tercommit di rag.
- [ ] E1, E2, E3 hijau dan tercommit di eval.
- [ ] G2 hijau dan tercommit di gateway; provider error → 502.
- [ ] Ledger diperbarui; tidak ada task file yang tertinggal uncommitted.
- [ ] `check_secrets.sh` tetap CLEAN.

## Todo List

### Blok 0 — Tutup Fase 0 (pagi)

- [ ] Review diff Task 0.5 (spec + quality); jika ada temuan, fix loop.
- [ ] Jalankan ulang `bash scripts/check_docker_inputs.sh` dan build image.
- [ ] Push `remediation/2026-10-24` ke empat submodule.
- [ ] Update gitlink root ke commit yang sudah ter-push; commit.
- [ ] Tambah job CI `submodules`; commit bersama gate clone.
- [ ] Clone bersih + `git submodule status --recursive` + compose config.
- [ ] Catat hasil di ledger.

### Blok 1 — ArXiv P0 (pagi–siang)

- [ ] A1 — normalisasi arXiv ID end-to-end.
- [ ] A3 — tolak zero-chunk sebelum menulis apa pun.
- [ ] A4 — urutan ingest aman + snapshot/restore.

### Blok 2 — RAG provider taxonomy (siang)

- [ ] R1 — taksonomi provider failure eksplisit.
- [ ] Review R1; pastikan tidak ada `insufficient_context` untuk provider error.

### Blok 3 — Eval checkpoint (sore)

- [ ] E1 — schema version + completeness gate.
- [ ] E2 — serialisasi checkpoint lossless.
- [ ] E3 — atomic checkpoint write.

### Blok 4 — Gateway provider error (sore)

- [ ] G2 — petakan `provider_error` ke `decision="error"` + HTTP 502.
- [ ] Update `docs/api-contract.md` dan test golden/contract.

### Blok 5 — Penutupan (sore)

- [ ] Jalankan verifikasi per repo (matriks di bawah).
- [ ] Update ledger + daily plan checkbox.
- [ ] Tulis carry-over untuk task yang belum selesai.

---

## Task Details

### T0.1 — Review dan tutup Task 0.5

**Files:**
- Review: `rag-research/Dockerfile`, `arxiv-research-assistant/python-ml/Dockerfile`,
  `docker-compose.yml`, `scripts/check_docker_inputs.sh`
- Report: `.superpowers/sdd/2026-10-24-cross-repo-remediation/task-0.5-report.md`

**Interfaces:**
- Consumes: implementer report + commit dari Task 0.5.
- Produces: keputusan review (approved/needs fixes) dan commit final 0.5.

- [ ] **Step 1: Baca report dan review package**

```bash
bash .superpowers/sdd/2026-10-24-cross-repo-remediation/extract-task.sh \
  docs/superpowers/plans/2026-10-24-cross-repo-remediation.md 0.5 \
  .superpowers/sdd/2026-10-24-cross-repo-remediation/task-0.5-brief.md
bash ~/.cache/opencode/npm/git-superpowers-*/node_modules/superpowers/skills/subagent-driven-development/scripts/review-package \
  docs/superpowers/plans/2026-10-24-cross-repo-remediation.md <BASE> <HEAD>
```

- [ ] **Step 2: Dispatch reviewer** dengan brief, report, diff, dan global constraints.
- [ ] **Step 3: Jika ❌/Critical/Important, resume implementer; jangan push.**
- [ ] **Step 4: Jika approved, catat commit dan lanjut T0.2.**

**Acceptance:** review spec ✅ dan quality approved; build log menunjukkan model di-bake,
bukan `COPY hf-cache/`.

---

### T0.2 — Push submodule + clone gate + CI gate

**Files:**
- Modify: `.github/workflows/check-secrets.yml` (job `submodules`)
- Modify: gitlink `arxiv-research-assistant`, `mcp-gateway`, `rag-research`,
  `llm-eval-framework`

**Interfaces:**
- Consumes: commit final tiap submodule di branch `remediation/2026-10-24`.
- Produces: gitlink root yang menunjuk commit yang ada di origin; job CI clone gate.

- [ ] **Step 1: Push empat branch**

```bash
for r in arxiv-research-assistant mcp-gateway rag-research llm-eval-framework; do
  git -C "$r" push -u origin remediation/2026-10-24
done
```

- [ ] **Step 2: Update gitlink dan commit**

```bash
git add arxiv-research-assistant mcp-gateway rag-research llm-eval-framework
git commit -m "chore: pin submodules to pushed remediation commits"
```

- [ ] **Step 3: Tambah job CI `submodules`**

```yaml
  submodules:
    name: Clean clone + compose config
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Compose config
        run: docker compose --env-file .env.example config --quiet
```

- [ ] **Step 4: Commit workflow**

```bash
git add .github/workflows/check-secrets.yml
git commit -m "ci: gate clean submodule checkout and compose config"
```

- [ ] **Step 5: Clone gate**

```bash
rm -rf /tmp/ai-infra-clone-check
git clone --recurse-submodules "file://$PWD" /tmp/ai-infra-clone-check
git -C /tmp/ai-infra-clone-check submodule status --recursive
cd /tmp/ai-infra-clone-check
docker compose --env-file .env.example config --quiet
```

Expected: setiap baris `submodule status` diawali spasi (bukan `-`/`+`), compose exit 0.

- [ ] **Step 6: Catat hasil di ledger.**

**Acceptance:** clone bersih berhasil; tidak ada submodule commit yang hanya lokal;
compose config valid tanpa `.env`.

---

### T1.1 — A1 Normalisasi arXiv ID end-to-end

**Files:**
- Create: `arxiv-research-assistant/python-ml/engine/arxiv_id.py`
- Modify: `python-ml/engine/ingestion/arxiv_fetcher.py`,
  `python-ml/routers/ingest.py`, `python-ml/engine/db.py`,
  `python-ml/engine/retrieval/qdrant_client.py`
- Test: `python-ml/tests/test_arxiv_id.py`, `test_validators.py`, `test_qdrant_ids.py`

**Interfaces:**
- Produces: `normalize_arxiv_id(value: str) -> str`; `is_valid_arxiv_id(value: str) -> bool`.
- `compute_point_ids`, `delete_by_arxiv_id`, `search`, `upsert_paper` memanggil normalizer.

- [ ] **Step 1: Tulis test yang gagal**

```python
def test_normalize_strips_version_suffix():
    assert normalize_arxiv_id("2312.10997v2") == "2312.10997"

def test_versioned_and_unversioned_ids_dedupe():
    req = IngestRequest(arxiv_ids=["2312.10997v1", "2312.10997"])
    assert req.arxiv_ids == ["2312.10997"]
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest tests/test_arxiv_id.py tests/test_validators.py tests/test_qdrant_ids.py -q
```

Expected: FAIL karena modul/API belum ada.

- [ ] **Step 3: Implementasi normalizer dan panggil di semua boundary** (fetcher, validator,
  `upsert_paper`, `compute_point_ids`, `delete_by_arxiv_id`, `search`).

- [ ] **Step 4: Jalankan sampai hijau**

```bash
PYTHONPATH=. ../../venv/bin/python -m pytest tests/ -q
```

- [ ] **Step 5: Commit**

```bash
git -C arxiv-research-assistant add python-ml/engine/arxiv_id.py \
  python-ml/engine/ingestion/arxiv_fetcher.py python-ml/routers/ingest.py \
  python-ml/engine/db.py python-ml/engine/retrieval/qdrant_client.py \
  python-ml/tests/test_arxiv_id.py python-ml/tests/test_validators.py \
  python-ml/tests/test_qdrant_ids.py
git -C arxiv-research-assistant commit -m "fix(python-ml): normalize arxiv ids end-to-end"
```

**Acceptance:** ID versioned dan unversioned menghasilkan satu paper, point ID sama, dan
filter/delete memakai bentuk kanonik.

---

### T1.2 — A3 Tolak zero-chunk sebelum menulis

**Files:**
- Modify: `python-ml/engine/ingestion/pdf_parser.py`, `python-ml/routers/ingest.py`
- Test: `python-ml/tests/test_ingest_zero_chunks.py`

**Interfaces:**
- Produces: `PdfParseError(code: str, message: str)`; `MIN_EXTRACTED_CHARS = 50`.

- [ ] **Step 1: Tulis test**

```python
def test_empty_pdf_is_rejected_before_pg_or_qdrant(harness):
    with pytest.raises(PdfParseError):
        harness.run_with_text("")
    assert "pg_commit" not in harness.calls
    assert "delete_by_arxiv_id" not in harness.calls

def test_empty_chunk_list_is_rejected(harness, monkeypatch):
    monkeypatch.setattr(ingest_mod, "chunk_text", lambda *a, **k: [])
    assert harness.run_with_text("teks cukup panjang")["failed"] == ["2312.10997"]
    assert "upsert_paper" not in harness.calls
```

- [ ] **Step 2: Jalankan dan pastikan gagal.**

- [ ] **Step 3: Implementasi:** tolak teks kosong/<50 char di parser; tolak `chunks == []`
  di ingest sebelum `upsert_paper`, `insert_chunks`, `delete_by_arxiv_id`, `upsert_chunks`.

- [ ] **Step 4: Verifikasi**

```bash
PYTHONPATH=. ../../venv/bin/python -m pytest tests/test_ingest_zero_chunks.py tests/test_ingest_compensation.py -q
```

- [ ] **Step 5: Commit** dengan pesan
  `fix(python-ml): reject zero-chunk ingestion before writes`.

**Acceptance:** PDF kosong/pendek dan chunk list kosong tidak menyentuh PG/Qdrant.

---

### T1.3 — A4 Urutan ingest aman + kompensasi snapshot

**Files:**
- Modify: `python-ml/engine/retrieval/qdrant_client.py`, `python-ml/routers/ingest.py`
- Test: `python-ml/tests/test_ingest_compensation.py`, `test_qdrant_ids.py`

**Interfaces:**
- Produces: `snapshot_by_arxiv_id(client, arxiv_id) -> list[dict]`,
  `restore_snapshot(client, arxiv_id, snapshot) -> None`,
  `delete_stale_chunks(client, arxiv_id, keep_ids) -> int`.
- Order: parse → chunk → embed → snapshot → upsert → PG commit → delete stale.

- [ ] **Step 1: Ubah test urutan lama menjadi urutan baru**

```python
assert harness.calls.index("snapshot_by_arxiv_id") < harness.calls.index("upsert_chunks")
assert harness.calls.index("pg_commit") < harness.calls.index("delete_stale_chunks")
```

- [ ] **Step 2: Tambah test kegagalan**

```python
def test_qdrant_failure_rolls_back_pg_and_restores_snapshot(...)
def test_pg_commit_failure_restores_snapshot(...)
def test_stale_delete_failure_does_not_fail_ingest(...)
```

- [ ] **Step 3: Jalankan dan pastikan test baru gagal.**

- [ ] **Step 4: Implementasi** snapshot/restore/delete-stale dan urutan baru. Jangan
  menghapus vektor lama sebelum vektor baru tertulis.

- [ ] **Step 5: Verifikasi**

```bash
PYTHONPATH=. ../../venv/bin/python -m pytest \
  tests/test_ingest_compensation.py tests/test_ingest_zero_chunks.py tests/test_qdrant_ids.py -q
```

- [ ] **Step 6: Commit** `fix(python-ml): make ingest ordering non-destructive`.

**Acceptance:** kegagalan Qdrant/PG tidak menghapus data lama; crash residual didokumentasikan
sebagai risiko P2, bukan diklaim zero-orphan.

---

### T2.1 — R1 Taksonomi provider failure

**Files:**
- Modify: `rag-research/src/generation/generator.py`, `src/api/main.py`
- Test: `tests/test_generation_error_contract.py`, `tests/test_failure_taxonomy.py`,
  `tests/test_api_phase1.py`

**Interfaces:**
- Produces: `FAILURE_PROVIDER_ERROR = "provider_error"`,
  `FAILURE_SANITY_CHECK`, `FAILURE_EMPTY_OUTPUT`;
  `RAGResponse.provider_error_kind: Optional[str]`;
  `GenerateResponse.provider_error_kind: Optional[str]`.

Mapping:
| Jalur | failure_type | provider_error_kind |
|---|---|---|
| RateLimit/Connection/Auth | `provider_error` | `rate_limit`/`connection`/`auth` |
| Invalid JSON fallback gagal | `provider_error` | `invalid_json` |
| Empty output | `empty_output` | `None` |
| Sanity check | `sanity_check` | `None` |
| Abstention kontekstual | `insufficient_context` | `None` |

- [ ] **Step 1: Tulis/ubah test** yang mengunci `failure_type` dan `provider_error_kind`.
- [ ] **Step 2: Jalankan dan pastikan gagal.**
- [ ] **Step 3: Implementasi pemetaan + field response + logging.**
- [ ] **Step 4: Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_generation_error_contract.py \
  tests/test_failure_taxonomy.py tests/test_api_phase1.py -q
```

- [ ] **Step 5: Commit**
  `fix: classify provider failures explicitly`.

**Acceptance:** provider error tidak pernah dilaporkan sebagai `insufficient_context`.

---

### T3.1 — E1 Checkpoint schema + completeness gate

**Files:**
- Modify: `llm-eval-framework/pipeline/runner.py`
- Test: `tests/test_runner_resume.py`, `tests/test_checkpoint_validation.py`

**Interfaces:**
- Produces: `CHECKPOINT_SCHEMA_VERSION = 2`;
  `CheckpointInvalidError`; `_checkpoint_is_complete(data: dict) -> bool`;
  `_checkpoint_to_faithfulness_result(...)`.

- [ ] **Step 1: Tulis test** `test_null_faithfulness_result_is_not_complete`,
  `test_old_schema_checkpoint_is_ignored`, `test_missing_required_field_is_ignored`,
  `test_complete_checkpoint_is_reused`, `test_resume_after_null_checkpoint_reruns_case`.
- [ ] **Step 2: Jalankan dan pastikan gagal.**
- [ ] **Step 3: Implementasi completeness gate; checkpoint lama/incomplete → `None`.**
- [ ] **Step 4: Verifikasi**

```bash
cd llm-eval-framework
../venv/bin/python -m pytest tests/test_runner_resume.py tests/test_checkpoint_validation.py -q
```

- [ ] **Step 5: Commit** `fix: reject incomplete checkpoints instead of crashing`.

---

### T3.2 — E2 Serialisasi checkpoint lossless

**Files:**
- Modify: `pipeline/runner.py`
- Test: `tests/test_checkpoint_roundtrip.py`

**Interfaces:**
- `_faithfulness_to_dict` menulis semua field `FaithfulnessResult`;
  `_checkpoint_to_faithfulness_result` membaca semua field tanpa mengganti provenance.

- [ ] **Step 1: Tulis test roundtrip** untuk `similarity_threshold`, `embedding_model`,
  `evaluator_version`, `timestamp_utc`, `claims`, `evidence_matches`.
- [ ] **Step 2: Jalankan dan pastikan gagal.**
- [ ] **Step 3: Implementasi serialisasi lengkap.**
- [ ] **Step 4: Verifikasi**

```bash
../venv/bin/python -m pytest tests/test_checkpoint_roundtrip.py tests/test_runner_resume.py -q
```

- [ ] **Step 5: Commit** `fix: serialize checkpoints without losing provenance`.

---

### T3.3 — E3 Atomic checkpoint write

**Files:**
- Modify: `pipeline/runner.py`
- Test: `tests/test_checkpoint_atomic_write.py`

**Interfaces:**
- `_save_checkpoint` menulis ke `.tmp`, `flush` + `fsync`, lalu `os.replace`.

- [ ] **Step 1: Tulis test** `test_write_uses_replace`,
  `test_failed_write_leaves_previous_checkpoint_intact`,
  `test_no_tmp_file_remains_after_success`.
- [ ] **Step 2: Jalankan dan pastikan gagal.**
- [ ] **Step 3: Implementasi atomic write; pertahankan `schema_version` dari E1.**
- [ ] **Step 4: Verifikasi**

```bash
../venv/bin/python -m pytest tests/test_checkpoint_atomic_write.py -q
```

- [ ] **Step 5: Commit** `fix: write checkpoints atomically`.

---

### T4.1 — G2 Provider error di gateway

**Files:**
- Modify: `mcp-gateway/internal/api/contract.go`,
  `internal/tools/research_rag_contract.go`, `internal/tools/research_rag.go`,
  `internal/planner/executor.go`, `cmd/server/respond.go`
- Test: `internal/tools/research_rag_test.go`, `cmd/server/router_test.go`,
  `internal/api/contract_test.go`
- Docs: `docs/api-contract.md`

**Interfaces:**
- Produces: `FailureProviderError = "provider_error"`,
  `FailureSanityCheck`, `FailureEmptyOutput`;
  `BackendAnswer.ProviderErrorKind string` (omitempty);
  `ResearchRAGResponse.IsProviderError() bool`.
- `respond()` memetakan `decision="error"` ke HTTP 502.

- [ ] **Step 1: Tulis test**

```go
func TestResearchRAGProviderErrorIsNotAbstention(t *testing.T)
func TestResearchRAGProviderErrorMapsToDecisionError(t *testing.T)
func TestProviderErrorResponseIs502(t *testing.T)
func TestProviderErrorKindIsPreserved(t *testing.T)
func TestInsufficientContextStillAbstains(t *testing.T)
```

- [ ] **Step 2: Jalankan dan pastikan gagal.**

```bash
cd mcp-gateway
go test ./internal/tools/... ./internal/planner/... ./cmd/server/... -race
```

- [ ] **Step 3: Implementasi** urutan `IsAbstention` baru, `IsProviderError`, field
  `ProviderErrorKind`, dan mapping di `respond.go`.

- [ ] **Step 4: Update `docs/api-contract.md`** dan test golden jika perlu.

- [ ] **Step 5: Verifikasi**

```bash
go test ./internal/tools/... ./internal/planner/... ./cmd/server/... ./internal/api/... -race
```

- [ ] **Step 6: Commit**
  `fix: surface rag provider errors as errors, not abstentions`.

**Acceptance:** provider error → 502 + `decision="error"` + `failure_type="provider_error"`;
abstention kontekstual tetap 200 + `decision="abstain"`.

---

## Verification Matrix

| Repo | Command | Expected |
|---|---|---|
| scanner | `bash scripts/check_secrets.sh && bash scripts/test_check_secrets.sh` | CLEAN + pass |
| arxiv Go | `cd arxiv-research-assistant/go-backend && go test ./... -race` | pass |
| arxiv Python | `cd arxiv-research-assistant/python-ml && PYTHONPATH=. ../../venv/bin/python -m pytest tests/ -q` | pass |
| rag | `cd rag-research && ../venv/bin/python -m pytest tests/ -q` | 453+ pass, 0 skip |
| eval | `cd llm-eval-framework && ../venv/bin/python -m pytest tests/ -q` | 208+ pass |
| gateway | `cd mcp-gateway && go test ./... -race` | pass |
| compose | `docker compose --env-file .env.example config --quiet` | valid |
| clone | `git clone --recurse-submodules "file://$PWD" /tmp/ai-infra-clone-check` | submodule status bersih |

## Carry-Over (jika waktu habis)

Pindahkan ke hari berikutnya tanpa mengubah urutan P0:

- A2 — migrasi data arXiv ID lama (dry-run default, `--apply` eksplisit).
- R2 — reranker fallback.
- A5/R4/R3/E4 — readiness split.
- A6/A7/A8/A9 — request ID, prompt evaluate, CORS, Quick Start.
- G1/G3/G4/G5 — readiness body-aware, store reconnect, request ID, timeout budget.
- X1–X5 — Compose lifecycle, smoke E2E, rotate key, migrasi DB, docs.

## Risks

| Risiko | Mitigasi |
|---|---|
| Build HF memakan waktu/long timeout | Jalankan background; review diff sambil menunggu; jangan klaim selesai sebelum log ada |
| Push ditolak/auth | Hentikan 0.4, catat BLOCKED, lanjut task arxiv/eval yang tidak butuh push |
| Review menemukan desain salah | Fix loop maksimal 3 ronde; eskalasi model; jangan lanjut task berikutnya |
| WIP root/gateway tercampur | Stage path/hunk eksplisit; cek `git diff --cached --stat` sebelum commit |
| Revoke key belum dilakukan | Scanner tetap CLEAN, tetapi insiden belum ditutup; ingatkan user di akhir hari |
