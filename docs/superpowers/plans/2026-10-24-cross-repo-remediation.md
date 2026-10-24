# Cross-Repo Remediation Plan — P0/P1 Production Gates

**Tanggal:** 2026-10-24
**Workspace:** `/home/malikimayzar/projects/ai-infra-workspace`
**Status:** Draft untuk review. Belum ada perubahan kode yang dilakukan.
**Basis:** audit statis working tree + targeted test suite pada 2026-10-23/24.

> **PENTING — baca sebelum mengeksekusi task apa pun.**
> Plan ini disusun dari **working tree**, bukan dari `HEAD`. `mcp-gateway` saat ini
> memiliki ~48 file berubah, `rag-research` 8 file, `arxiv-research-assistant` 9 file,
> dan root sendiri dirty. Jangan `git reset`, `git checkout --`, atau `git clean` untuk
> “memulai dari bersih”. Ikuti Task 0.2 untuk membekukan dan menginventarisasi WIP.

---

## 1. Tujuan

Membuat stack lima repo dapat:

1. di-clone dan di-build ulang dari nol tanpa file lokal yang tidak ter-track;
2. menolak data ingest yang rusak tanpa menghapus data lama;
3. membedakan **abstention sah** dari **provider failure**;
4. melaporkan readiness yang benar, bukan false-green;
5. melanjutkan evaluasi yang gagal tanpa crash dan tanpa kehilangan provenance;
6. memverifikasi alur end-to-end lewat `request_id`, bukan hanya hitungan baris.

**Non-goals plan ini:** implementasi MCP wire protocol, redesign UI, auth multi-tenant,
dan perubahan model/provider. Auth/rate-limit tetap ada di backlog P3.

---

## 2. Arsitektur dan kontrak yang dilindungi

```text
UI / klien
  └─ mcp-gateway :8090  (/ask, /plan, /tool, /health, /ready, /metrics)
       ├─ arxiv-go-backend :8080  (/query, /papers, /health, /ready, /metrics)
       │    └─ arxiv-python-ml :8001  (/ingest, /query, /evaluate, /health, /ready)
       │         ├─ Qdrant: arxiv_chunks (384d)
       │         ├─ PostgreSQL: papers, chunks, query_logs
       │         └─ Groq / Ollama
       ├─ rag-api :8000  (/generate, /health, /ready, /metrics)
       │    ├─ Qdrant: rag_research (v2, 796 chunk)
       │    ├─ BM25 + dense + RRF (+ reranker opsional)
       │    └─ Groq openai/gpt-oss-20b
       └─ llm-eval-framework :8002  (/evaluate, /health, /ready, /metrics)
            └─ Ollama nomic-embed-text
```

**Kontrak publik yang tidak boleh berubah tanpa task eksplisit:**

- `POST /ask` di gateway: field `request_id`, `answer`, `evidence`, `backend`, `model`,
  `latency_ms`, `decision`, `failure_type`, `evaluation_status`, `evaluation`, `steps`.
- `POST /generate` di rag-research: enam field wajib (`answer`, `retrieved_chunks`,
  `latency_total_ms`, `model`, `confidence`, `decision`) tetap ada.
- Perubahan status HTTP **hanya** untuk `/ready` (503 saat tidak siap) dan provider error
  di gateway (tetap 200 dengan `decision="error"` sampai kontrak direview; lihat Task G2).
- Semua field baru bersifat **aditif**. Jangan hapus/rename field lama.

**Prinsip health:**

| Endpoint | Arti | Status |
|---|---|---|
| `/health` | liveness proses | selalu 200 selama proses hidup |
| `/ready` | dependency + data siap melayani | 200 hanya jika dependency kritis siap; 503 jika tidak |

---

## 3. Baseline dan temuan

### 3.1 Status verifikasi saat plan dibuat

| Pemeriksaan | Hasil |
|---|---|
| `rag-research` full suite | **453 passed, 0 skipped** (menggantikan klaim 419/1 yang stale) |
| `llm-eval-framework` | **208 passed** |
| `mcp-gateway` `go test ./...` dan `-race` | pass |
| `arxiv-research-assistant` Go | pass |
| `arxiv-research-assistant/python-ml` | 19 passed |
| `make check-secrets` | **FAIL** — lihat P0-0. Hasil “CLEAN” sebelumnya sudah tidak berlaku. |
| Docker stack | **tidak berjalan**; runtime lintas-service belum diverifikasi |

### 3.2 P0 — blocker

| ID | Repo | Temuan | Bukti utama |
|---|---|---|---|
| **P0-0** | root + arxiv | Dua `.env.example` berisi nilai berbentuk kunci Groq; `make check-secrets` exit 1 | `.env.example`, `arxiv-research-assistant/.env.example`, `scripts/check_secrets.sh` |
| **P0-1** | root | Root 2 commit di depan origin; empat commit submodule tidak ada di remote; CI hanya trigger `master` | `git status`, `.github/workflows/check-secrets.yml:3-8` |
| **P0-2** | root + rag + arxiv | `rag-research/Dockerfile:51` `COPY hf-cache/` tetapi `hf-cache/` gitignored; arxiv mount path yang sama dengan `HF_HUB_OFFLINE=1` | `rag-research/Dockerfile:51`, `rag-research/.gitignore:145`, `docker-compose.yml:142-146` |
| **P0-3** | arxiv | `arxiv_id` disimpan versioned (`...v1`) tetapi filter/query/dokumentasi memakai unversioned | `python-ml/engine/ingestion/arxiv_fetcher.py:25`, `engine/retrieval/qdrant_client.py:88-91` |
| **P0-4** | arxiv | Zero-chunk tidak ditolak; ingest commit PG → delete vektor lama → upsert baru; kegagalan menghapus data lama | `python-ml/routers/ingest.py:74-125` |
| **P0-5** | rag | Provider error (429, connection, invalid JSON, sanity) diberi `failure_type="insufficient_context"` | `src/generation/generator.py:529,765-775,819-869` |
| **P0-6** | llm-eval | Checkpoint `faithfulness_result: null` dianggap selesai; resume crash; serialisasi kehilangan field | `pipeline/runner.py:323,339-344,484-496,529-541,650,655` |

### 3.3 P1 — readiness, lifecycle, dan fungsi menyesatkan

| ID | Repo | Temuan |
|---|---|---|
| **P1-1** | gateway + arxiv + rag + eval | `/ready` gateway body-blind; arxiv `/health` selalu 200; evaluator `/health` statis; rag `/health` hanya cek store |
| **P1-2** | gateway | `store.Init` satu kali ping; gagal → logging mati permanen; tidak ada `depends_on: postgres` |
| **P1-3** | rag + root | `GROQ_API_KEY` kosong → container restart loop; `rag-api` masih menunggu Ollama yang tidak dipakai |
| **P1-4** | gateway | Timeout 620s < ArXiv 600s + evaluator 120s; evaluator bisa hanya dapat ~20s |
| **P1-5** | root + rag | `make seed-rag` tidak load `.env`, default ke Qdrant lokal, membaca v2 setelah chunker menghasilkan v3, dan `reset=True` |
| **P1-6** | rag | Reranker diakses di luar `try`; image offline hanya punya cache MiniLM, bukan CrossEncoder |
| **P1-7** | arxiv | `/evaluate` mengirim prompt sebagai context chunk dan memotong 800 karakter; `SCORE:` ada di akhir |
| **P1-8** | arxiv | Quick Start bertabrakan dengan Compose (port 8001/8080); `source` tidak jalan di `/bin/sh`; CORS UI tidak ada |
| **P1-9** | arxiv + gateway | Log query async dan hanya `query_logs`; smoke tidak memverifikasi `gateway_query_logs`/`X-Request-ID` |
| **P1-10** | root | Drift dokumen: test count, smoke fixed-query, `.env.example` kurang tiga variabel, `rotate_key.sh` masih recreate gateway |

---

## 4. Constraint global

1. **Satu task = satu commit.** Jangan gabungkan P0 dan P1 dalam satu commit.
2. **TDD wajib.** Tulis test yang gagal, tunjukkan kegagalannya, baru implementasi.
3. **Stage path eksplisit.** Dilarang `git add -A` atau `git add .` di root/submodule.
4. **Submodule dulu.** Commit dan push submodule, baru update gitlink root. Jangan
   membuat root menunjuk commit yang tidak ada di remote.
5. **Jangan menyentuh file di luar daftar task.** Jika ada perubahan WIP pada file yang
   sama, commit WIP itu terpisah lebih dulu atau hentikan task dan minta keputusan.
6. **Jangan pernah menulis kunci asli** ke test, fixture, dokumentasi, atau log plan.
   Gunakan `test-key-not-real` atau mock client.
7. **Qdrant reset hanya dengan flag eksplisit** (`--force`) dan hanya pada collection
   yang namanya dicetak lebih dulu.
8. **Tidak ada `sleep` sebagai sinkronisasi test.** Gunakan polling dengan deadline.
9. **Semua endpoint baru memakai JSON lowercase** dan field opsional `omitempty`
   (Go) / `Optional` (Python), sesuai kontrak lama.
10. **Verifikasi akhir per workstream**: jalankan full suite repo sebelum pindah
    workstream.

---

## 5. Urutan eksekusi

```text
Fase 0  Keamanan + reproduktibilitas
  0.1  Cabut/rotasi kunci yang terekspos
  0.2  Bekukan & inventarisasi dirty tree
  0.3  CI main + regression scanner
  0.4  Push submodule + gate clone bersih
  0.5  HF cache reproducible

Fase 1  P0 data & failure semantics
  A1  Normalisasi arXiv ID
  A2  Migrasi data ID lama
  A3  Tolak zero-chunk
  A4  Urutan ingest aman + kompensasi
  R1  Taksonomi provider failure
  R2  Reranker fallback
  E1  Checkpoint schema + completeness
  E2  Serialisasi checkpoint lossless
  E3  Atomic checkpoint write
  G2  Gateway memetakan provider_error

Fase 2  P1 readiness & lifecycle
  A5  arxiv /ready + ML /ready
  A6  Request ID + query log
  A7  Prompt /evaluate
  R3  rag /health vs /ready
  R4  Groq key kosong tidak crash
  R5  seed canonical non-destruktif
  E4  evaluator /ready
  E5  /evaluate error semantics
  G1  gateway /ready body-aware
  G3  store reconnect
  G4  request ID response header
  G5  timeout budget

Fase 3  P1 integration & docs
  A8  CORS
  A9  Quick Start
  R6  .env.example rag
  R7  vector dimension
  R8  metrik decision
  X1  Compose lifecycle
  X2  Smoke E2E
  X3  rotate_key
  X4  DB migrations
  X5  Docs truth
```

Setiap fase harus hijau sebelum fase berikutnya. Jika satu task memblokir task lain
(mis. G1 butuh A5/R3/E4), kerjakan dependency lebih dulu, bukan membuat stub permanen.

---

## 6. Fase 0 — Keamanan dan reproduktibilitas

### Task 0.1 — Cabut dan ganti kunci yang terekspos (URGENT)

**Temuan:** `bash scripts/check_secrets.sh` saat ini exit 1 dan melaporkan:

- `./.env.example`
- `arxiv-research-assistant/.env.example`

Keduanya memuat nilai yang cocok dengan pola `gsk_[A-Za-z0-9]{30,}`. Nilai tidak
ditampilkan di plan ini. Anggap keduanya **kompromi** sampai dibuktikan sebaliknya.

**Files**

- Modify `.env.example`
- Modify `arxiv-research-assistant/.env.example`
- Create `docs/security/2026-10-24-groq-key-exposure.md`
- Keep `scripts/check_secrets.sh` (versi working tree yang sudah menangkap pattern)
- Keep `scripts/test_check_secrets.sh` (untracked; akan di-commit di Task 0.3)

**Langkah**

1. **Di luar repo:** buka Groq console → revoke kedua key yang pernah muncul di dua file
   tersebut. Buat key baru; simpan hanya di `.env` root (gitignored). Jangan tempel key
   baru ke chat, plan, atau file contoh.
2. Cek apakah nilai pernah masuk history **tanpa mencetak nilainya**:
   ```bash
   git log --all --oneline -S 'gsk_' -- .env.example
   git -C arxiv-research-assistant log --all --oneline -S 'gsk_' -- .env.example
   ```
   Jika ada output, history dianggap tercemar. Rotasi tetap wajib; rewrite history
   (`git filter-repo`) hanya dilakukan setelah user menyetujui karena mengubah SHA.
3. Ganti nilai di kedua file dengan placeholder yang dikenali scanner:
   ```env
   GROQ_API_KEY=gsk_your_actual_key_here
   ```
4. Tulis incident note `docs/security/2026-10-24-groq-key-exposure.md`:
   - waktu ditemukan, file terdampak (tanpa nilai),
   - status revoke/rotasi,
   - hasil `git log -S` (ada/tidak),
   - tindakan pencegahan (Task 0.3).
5. Jalankan:
   ```bash
   bash scripts/check_secrets.sh
   bash scripts/test_check_secrets.sh
   ```
   Keduanya harus pass. `check_secrets.sh` harus mencetak `CLEAN`.

**Acceptance**

- Tidak ada file tracked yang cocok `gsk_[A-Za-z0-9]{30,}`.
- Kedua key lama sudah revoked; key baru hanya ada di `.env`.
- `make check-secrets` exit 0.

**Commit**

```bash
git add .env.example docs/security/2026-10-24-groq-key-exposure.md
git -C arxiv-research-assistant add .env.example
git commit -m "fix(security): replace tracked Groq keys with placeholders"
git -C arxiv-research-assistant commit -m "fix(security): replace tracked Groq key with placeholder"
```

---

### Task 0.2 — Bekukan dan inventarisasi dirty tree

**Tujuan:** memastikan tidak ada WIP user yang hilang atau tercampur.

**Langkah**

1. Simpan snapshot tanpa mengubah working tree:
   ```bash
   mkdir -p /tmp/ai-infra-remediation
   git status --porcelain > /tmp/ai-infra-remediation/root.status
   git diff > /tmp/ai-infra-remediation/root.diff
   for r in arxiv-research-assistant mcp-gateway rag-research llm-eval-framework; do
     git -C "$r" status --porcelain > "/tmp/ai-infra-remediation/${r}.status"
     git -C "$r" diff > "/tmp/ai-infra-remediation/${r}.diff"
   done
   ```
2. Buat branch kerja di setiap repo (belum push):
   ```bash
   git switch -c remediation/2026-10-24
   git -C arxiv-research-assistant switch -c remediation/2026-10-24
   git -C mcp-gateway switch -c remediation/2026-10-24
   git -C rag-research switch -c remediation/2026-10-24
   git -C llm-eval-framework switch -c remediation/2026-10-24
   ```
3. Tandai file yang sudah dirty dan termasuk target plan. Untuk file itu, buat commit
   `wip:` terpisah **hanya jika user menyetujui**. Jangan commit 48 file gateway
   sekaligus tanpa review.
4. Tulis daftar keputusan di `/tmp/ai-infra-remediation/scope.md`: file mana yang masuk
   P0/P1, mana yang tetap WIP.

**Acceptance:** semua perubahan user ada di snapshot; tidak ada `reset`/`clean`.

---

### Task 0.3 — CI trigger `main` + regression test scanner

**Files**

- Modify `.github/workflows/check-secrets.yml`
- Create `scripts/test_ci_contract.sh`
- Commit `scripts/test_check_secrets.sh` (sudah ada di working tree, untracked)

**Perubahan**

```yaml
name: Workspace hygiene

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  secrets-scan:
    name: Secrets scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Scanner regression fixtures
        run: bash scripts/test_check_secrets.sh
      - name: No leaked Groq keys (root + 4 submodule, tracked)
        run: make check-secrets
```

**Test baru** `scripts/test_ci_contract.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
workflow=".github/workflows/check-secrets.yml"
grep -q 'branches: \[main\]' "$workflow" || {
  echo "workflow must trigger on main" >&2; exit 1;
}
grep -q 'test_check_secrets.sh' "$workflow" || {
  echo "workflow must run scanner regression fixtures" >&2; exit 1;
}
echo "CI contract checks passed"
```

**Verifikasi**

```bash
bash -n scripts/test_ci_contract.sh
bash scripts/test_ci_contract.sh
bash scripts/test_check_secrets.sh
```

**Commit**

```bash
git add .github/workflows/check-secrets.yml scripts/test_ci_contract.sh scripts/test_check_secrets.sh
git commit -m "ci: trigger secret scan on main and test the scanner"
```

---

### Task 0.4 — Push submodule dan gate clone bersih

**Tujuan:** `git clone --recurse-submodules` dan CI tidak gagal checkout.

**Langkah**

1. Untuk setiap submodule, review branch `remediation/2026-10-24`, commit WIP yang
   disetujui, lalu push:
   ```bash
   git -C arxiv-research-assistant push -u origin remediation/2026-10-24
   git -C mcp-gateway push -u origin remediation/2026-10-24
   git -C rag-research push -u origin remediation/2026-10-24
   git -C llm-eval-framework push -u origin remediation/2026-10-24
   ```
2. Update gitlink root ke commit yang sudah ada di remote:
   ```bash
   git add arxiv-research-assistant mcp-gateway rag-research llm-eval-framework
   git commit -m "chore: pin submodules to pushed remediation commits"
   ```
3. Verifikasi dari clone bersih:
   ```bash
   rm -rf /tmp/ai-infra-clone-check
   git clone --recurse-submodules "file://$PWD" /tmp/ai-infra-clone-check
   git -C /tmp/ai-infra-clone-check submodule status --recursive
   ```
   Semua baris harus diawali ` ` (spasi), bukan `-`/`+`.
4. Tambahkan job CI `submodules` yang menjalankan checkout recursive + `docker compose
   config --quiet` tanpa `.env` (gunakan `.env.example`).

**Catatan:** jangan memaksa push ke `main`; gunakan branch remediation dan PR. Root
`main` yang 2 commit di depan origin harus di-push setelah review, bukan sebagai bagian
dari task ini.

**Acceptance:** clone bersih berhasil; tidak ada submodule commit yang hanya ada lokal.

---

### Task 0.5 — HF cache reproducible

**Temuan:** image bergantung pada `rag-research/hf-cache/` yang tidak pernah dibuat
oleh target mana pun dan tidak di-track. Fresh clone gagal di `COPY hf-cache/`.

**Keputusan default:** **download model saat build** ke dalam image, bukan commit cache
biner. Build sudah butuh jaringan untuk PyPI, jadi ini tidak menambah prasyarat baru.

**Files**

- Modify `rag-research/Dockerfile`
- Modify `arxiv-research-assistant/python-ml/Dockerfile`
- Modify `docker-compose.yml` (hapus bind mount cache arxiv)
- Create `scripts/check_docker_inputs.sh`
- Modify `rag-research/.dockerignore` bila perlu

**Perubahan `rag-research/Dockerfile`**

Hapus:

```dockerfile
COPY hf-cache/ /app/hf-hub/
```

Tambahkan setelah `COPY --from=builder /opt/venv /opt/venv` dan sebelum
`ENV HF_HUB_OFFLINE=1`:

```dockerfile
ENV HF_HOME=/app/hf-hub \
    HF_HUB_OFFLINE=0
RUN python - <<'PY'
from sentence_transformers import SentenceTransformer, CrossEncoder

SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")
PY
ENV HF_HUB_OFFLINE=1
```

Model reranker harus ikut karena `use_reranker=true` adalah fitur yang
didokumentasikan (Task R2).

**Perubahan `arxiv-python-ml`**

- Tambahkan langkah build yang mengunduh `sentence-transformers/all-MiniLM-L6-v2` ke
  `HF_HOME` image.
- Hapus dari `docker-compose.yml`:
  ```yaml
  - ./rag-research/hf-cache/hub:/root/.cache/huggingface/hub:ro
  ```
- Tetap set `HF_HUB_OFFLINE=1` **setelah** model di-bake.

**Test baru** `scripts/check_docker_inputs.sh`:

- Parse setiap `COPY`/`ADD` di `rag-research/Dockerfile` dan
  `arxiv-research-assistant/python-ml/Dockerfile`.
- Untuk source path yang bukan dari stage lain, pastikan path itu ada di git
  (`git ls-files --error-unmatch`) **atau** dibuat oleh instruksi sebelumnya.
- Gagal jika menemukan `hf-cache` sebagai build context.

**Verifikasi**

```bash
bash -n scripts/check_docker_inputs.sh
bash scripts/check_docker_inputs.sh
# build dari clone bersih; butuh jaringan
rm -rf /tmp/ai-infra-build-check
git clone --recurse-submodules "file://$PWD" /tmp/ai-infra-build-check
cd /tmp/ai-infra-build-check
docker compose --env-file .env.example build rag-api arxiv-python-ml
```

Jika build tidak bisa dijalankan karena Docker/daemon tidak tersedia, catat sebagai
**belum diverifikasi** dan jangan klaim task selesai.

**Commit**

```bash
git add rag-research/Dockerfile arxiv-research-assistant/python-ml/Dockerfile docker-compose.yml scripts/check_docker_inputs.sh
git commit -m "build: bake HF models instead of copying an ignored cache"
```

---

## 7. Workstream A — `arxiv-research-assistant`

### Task A1 — Normalisasi arXiv ID end-to-end

**Tujuan:** satu bentuk kanonik, unversioned, di metadata, PostgreSQL, Qdrant payload,
filter, delete, dan request API. ID versioned tetap diterima sebagai input lalu
dinormalisasi.

**Files**

- Create `python-ml/engine/arxiv_id.py`
- Modify `python-ml/engine/ingestion/arxiv_fetcher.py`
- Modify `python-ml/routers/ingest.py`
- Modify `python-ml/engine/db.py`
- Modify `python-ml/engine/retrieval/qdrant_client.py`
- Create `python-ml/tests/test_arxiv_id.py`
- Modify `python-ml/tests/test_validators.py`
- Modify `python-ml/tests/test_qdrant_ids.py`

**Interface**

```python
# python-ml/engine/arxiv_id.py
import re

_VERSION_SUFFIX = re.compile(r"v\d+$")
_VALID = re.compile(r"^\d{4}\.\d{4,5}$")

def normalize_arxiv_id(value: str) -> str:
    """Return the unversioned canonical arXiv id.

    Accepts '2312.10997', '2312.10997v1', '2312.10997v12'.
    Raises ValueError for empty/invalid values.
    """

def is_valid_arxiv_id(value: str) -> bool:
    """True if value is a valid unversioned arXiv id."""
```

`routers/ingest.py`:

```python
@field_validator("arxiv_ids")
@classmethod
def _validate_arxiv_ids(cls, value: list[str]) -> list[str]:
    normalized = [normalize_arxiv_id(v) for v in value]
    # preserve order, drop duplicates
    return list(dict.fromkeys(normalized))
```

`engine/db.py`:

```python
def upsert_paper(conn, paper) -> str:
    arxiv_id = normalize_arxiv_id(paper.arxiv_id)
    ...
```

`engine/retrieval/qdrant_client.py`:

```python
def compute_point_ids(arxiv_id: str, count: int) -> list[str]:
    arxiv_id = normalize_arxiv_id(arxiv_id)
    ...

def delete_by_arxiv_id(client: QdrantClient, arxiv_id: str) -> None:
    arxiv_id = normalize_arxiv_id(arxiv_id)
    ...

def search(..., arxiv_id: str | None = None):
    if arxiv_id:
        arxiv_id = normalize_arxiv_id(arxiv_id)
```

**TDD**

1. Tulis `test_arxiv_id.py`:
   - `test_normalize_strips_version_suffix`
   - `test_normalize_is_idempotent`
   - `test_normalize_rejects_empty_and_invalid`
   - `test_is_valid_arxiv_id`
2. Tambah `test_validators.py::test_versioned_and_unversioned_ids_dedupe`:
   request `["2312.10997v1", "2312.10997"]` → satu paper.
3. Tambah `test_qdrant_ids.py`:
   - `test_delete_normalizes_versioned_id`
   - `test_search_filter_normalizes_versioned_id`
   - `test_compute_point_ids_are_same_for_versioned_and_unversioned`
4. Jalankan dan pastikan gagal:
   ```bash
   cd arxiv-research-assistant/python-ml
   PYTHONPATH=. ../../venv/bin/python -m pytest \
     tests/test_arxiv_id.py tests/test_validators.py tests/test_qdrant_ids.py -q
   ```
5. Implementasi.
6. Jalankan lagi sampai hijau.

**Verifikasi penuh**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest tests/ -q
```

**Commit**

```bash
git -C arxiv-research-assistant add python-ml/engine/arxiv_id.py \
  python-ml/engine/ingestion/arxiv_fetcher.py python-ml/routers/ingest.py \
  python-ml/engine/db.py python-ml/engine/retrieval/qdrant_client.py \
  python-ml/tests/test_arxiv_id.py python-ml/tests/test_validators.py \
  python-ml/tests/test_qdrant_ids.py
git -C arxiv-research-assistant commit -m "fix(python-ml): normalize arxiv ids end-to-end"
```

---

### Task A2 — Migrasi data arXiv ID lama (PostgreSQL + Qdrant)

**Tujuan:** data yang sudah terlanjur versioned tidak meninggalkan duplikat atau vektor
yatim. Script default **dry-run**; `--apply` wajib untuk menulis.

**Files**

- Create `arxiv-research-assistant/python-ml/scripts/migrate_arxiv_ids.py`
- Create `arxiv-research-assistant/python-ml/tests/test_migrate_arxiv_ids.py`
- Create `arxiv-research-assistant/infra/postgres/migrations/001_query_logs_request_id.sql`
  (request_id dipakai Task A6; boleh dibuat di sini agar satu jalur migrasi)

**Interface**

```python
@dataclass
class MigrationReport:
    papers_updated: int
    duplicate_papers_merged: int
    qdrant_points_moved: int
    qdrant_points_deleted: int
    skipped: list[str]

def migrate_postgres(conn, *, apply: bool) -> MigrationReport: ...
def migrate_qdrant(client, moves: list[tuple[str, str]], *, apply: bool) -> MigrationReport: ...
def main(argv: list[str] | None = None) -> int:
    """CLI: --apply, --dry-run (default), --qdrant-url, --db-* env."""
```

**Aturan migrasi PostgreSQL**

- Untuk setiap `papers.arxiv_id` yang versioned:
  - hitung `canonical = normalize_arxiv_id(old)`;
  - jika belum ada paper canonical: `UPDATE papers SET arxiv_id = canonical WHERE id = old`;
  - jika sudah ada: pindahkan `chunks.paper_id` ke paper canonical, lalu hapus paper
    duplikat (chunk index di-reindex agar unik).
- Jangan menghapus paper canonical.
- Jalankan dalam satu transaksi per paper; commit hanya jika `--apply`.

**Aturan migrasi Qdrant**

- `scroll` semua point dengan filter `arxiv_id = old`.
- Untuk tiap point, hitung ID baru `compute_point_ids(canonical, count)[index]`.
- `upsert` point baru dengan payload `arxiv_id=canonical` dan vector yang sama.
- Setelah semua point baru tertulis, `delete_by_arxiv_id(old)`.
- Jika `--dry-run`, hanya laporkan jumlah.

**TDD**

- `test_dry_run_does_not_write`
- `test_versioned_paper_is_renamed`
- `test_duplicate_papers_merge_chunks`
- `test_qdrant_points_are_rekeyed_before_old_delete`
- `test_invalid_id_is_skipped_and_reported`

**Verifikasi**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest tests/test_migrate_arxiv_ids.py -q
# setelah approval dan backup:
PYTHONPATH=. ../../venv/bin/python scripts/migrate_arxiv_ids.py --dry-run
```

**Commit**

```bash
git -C arxiv-research-assistant add python-ml/scripts/migrate_arxiv_ids.py \
  python-ml/tests/test_migrate_arxiv_ids.py \
  infra/postgres/migrations/001_query_logs_request_id.sql
git -C arxiv-research-assistant commit -m "feat(python-ml): migrate versioned arxiv ids safely"
```

---

### Task A3 — Tolak zero-chunk sebelum menulis apa pun

**Files**

- Modify `python-ml/engine/ingestion/pdf_parser.py`
- Modify `python-ml/routers/ingest.py`
- Create `python-ml/tests/test_ingest_zero_chunks.py`

**Perubahan**

```python
# pdf_parser.py
class PdfParseError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code

MIN_EXTRACTED_CHARS = 50

def download_and_parse_pdf(pdf_url: str) -> str:
    ...
    if not text.strip():
        raise PdfParseError("no_extractable_text", "PDF yielded no extractable text")
    if len(text.strip()) < MIN_EXTRACTED_CHARS:
        raise PdfParseError(
            "extracted_text_too_short",
            f"PDF yielded only {len(text.strip())} characters",
        )
    return text
```

```python
# routers/ingest.py — di dalam loop, sebelum upsert/commit
text = download_and_parse_pdf(paper.pdf_url)
chunks = chunk_text(text, request.chunk_size, request.overlap)
if not chunks:
    raise ValueError("no_chunks_extracted")
```

Per-paper `except` harus menambahkan `paper.arxiv_id` ke `failed` dan **tidak**
memanggil `upsert_paper`, `insert_chunks`, `delete_by_arxiv_id`, atau `upsert_chunks`.

**TDD**

- `test_empty_pdf_is_rejected_before_pg_or_qdrant`
- `test_short_pdf_is_rejected`
- `test_empty_chunk_list_is_rejected`
- `test_valid_paper_still_ingests`

Gunakan `Harness` pola `tests/test_ingest_compensation.py`; pastikan `FakeConn.commit`
tidak dipanggil untuk kasus gagal.

**Verifikasi**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest tests/test_ingest_zero_chunks.py tests/test_ingest_compensation.py -q
```

**Commit**

```bash
git -C arxiv-research-assistant add python-ml/engine/ingestion/pdf_parser.py \
  python-ml/routers/ingest.py python-ml/tests/test_ingest_zero_chunks.py
git -C arxiv-research-assistant commit -m "fix(python-ml): reject zero-chunk ingestion before writes"
```

---

### Task A4 — Urutan ingest aman + kompensasi berbasis snapshot

**Tujuan:** jangan pernah menghapus vektor lama sebelum vektor baru tertulis; jika
commit PostgreSQL gagal, pulihkan snapshot vektor lama.

**Files**

- Modify `python-ml/engine/retrieval/qdrant_client.py`
- Modify `python-ml/routers/ingest.py`
- Modify `python-ml/tests/test_ingest_compensation.py`
- Modify `python-ml/tests/test_qdrant_ids.py`

**Interface baru**

```python
# qdrant_client.py
def snapshot_by_arxiv_id(client, arxiv_id: str) -> list[dict]:
    """Return every point for this paper: {id, vector, payload}."""

def restore_snapshot(client, arxiv_id: str, snapshot: list[dict]) -> None:
    """Delete current points for the paper, then re-upsert the snapshot."""

def delete_stale_chunks(client, arxiv_id: str, keep_ids: list[str]) -> int:
    """Delete points for the paper whose id is not in keep_ids. Returns count."""
```

**Urutan baru di `routers/ingest.py`**

```text
parse PDF
  → chunk
  → embed
  → qdrant.snapshot_by_arxiv_id(old)
  → qdrant.upsert_chunks(new ids)
  → pg.upsert_paper + pg.insert_chunks (belum commit)
  → pg.commit
  → qdrant.delete_stale_chunks(keep=new ids)
```

Jika `qdrant.upsert_chunks` atau `pg.*`/`commit` gagal:

```text
pg.rollback()
qdrant.restore_snapshot(snapshot)
failed.append(paper.arxiv_id)
```

Jika `delete_stale_chunks` gagal setelah commit: **jangan** gagalkan ingest; log warning
dan biarkan rekonsiliasi P2 membersihkannya.

**Catatan residual risk:** crash proses tepat setelah upsert dan sebelum commit tetap
bisa meninggalkan vektor baru tanpa baris PG. Re-ingest paper yang sama akan
memperbaikinya. Jangan klaim zero-orphan; dokumentasikan di docstring dan plan P2.

**TDD — update `test_ingest_compensation.py`**

Test lama mengunci urutan `pg_commit < qdrant_delete < qdrant_upsert`. Ganti menjadi:

- `test_success_snapshots_then_upserts_then_commits_then_deletes_stale`:
  `snapshot < upsert < insert_chunks < pg_commit < delete_stale`.
- `test_qdrant_failure_rolls_back_pg_and_restores_snapshot`:
  `pg_rollback` dan `restore_snapshot` ada; `delete_paper` tidak ada.
- `test_pg_commit_failure_restores_snapshot`.
- `test_stale_delete_failure_does_not_fail_ingest`.
- `test_zero_chunks_never_touches_qdrant` (dari A3).

**Verifikasi**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest \
  tests/test_ingest_compensation.py tests/test_ingest_zero_chunks.py \
  tests/test_qdrant_ids.py -q
```

**Commit**

```bash
git -C arxiv-research-assistant add python-ml/engine/retrieval/qdrant_client.py \
  python-ml/routers/ingest.py python-ml/tests/test_ingest_compensation.py \
  python-ml/tests/test_qdrant_ids.py
git -C arxiv-research-assistant commit -m "fix(python-ml): make ingest ordering non-destructive"
```

---

### Task A5 — `/ready` di Go backend dan python-ml

**Tujuan:** gateway bisa membedakan liveness dari dependency readiness.

**Files**

- Modify `python-ml/main.py`
- Modify `go-backend/internal/api/health.go`
- Modify `go-backend/internal/client/ml_client.go`
- Modify `go-backend/cmd/server/main.go` (registrasi route)
- Modify `go-backend/internal/api/health_test.go`
- Create `python-ml/tests/test_health_ready.py`

**Perubahan python-ml**

```python
@app.get("/health")
def health():
    return {"status": "ok", "service": "arxiv-python-ml"}

@app.get("/ready")
def ready():
    if state.model is None:
        raise HTTPException(status_code=503, detail="embedding model not loaded")
    try:
        get_client().get_collections()
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"qdrant unavailable: {exc}")
    return {
        "status": "ready",
        "model_loaded": True,
        "model": "all-MiniLM-L6-v2",
        "qdrant": "ok",
    }
```

**Perubahan Go**

```go
func HealthHandler(...) fiber.Handler // tetap 200; body status "ok" | "degraded"
func ReadyHandler(...) fiber.Handler  // 200 hanya jika semua dependency ok, else 503
func (c *MLClient) PingReady() error  // GET /ready, parse {"status":"ready"}
```

`HealthResponse` tetap dipakai; `ReadyHandler` memakai struct yang sama dan mengembalikan
`fiber.StatusServiceUnavailable` saat `overallStatus != "ok"`.

**TDD**

- Python: `test_health_is_liveness_even_without_model`, `test_ready_503_without_model`,
  `test_ready_503_when_qdrant_fails`, `test_ready_200_when_dependencies_ok`.
- Go: `TestReadyHandler_AllOK`, `TestReadyHandler_DBDownReturns503`,
  `TestReadyHandler_MLHealth200ButReady503IsFailure`, `TestHealthHandler_Always200`.

**Verifikasi**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest tests/test_health_ready.py -q
cd ../go-backend
go test ./internal/api/... ./internal/client/... -race
```

**Commit**

```bash
git -C arxiv-research-assistant add python-ml/main.py python-ml/tests/test_health_ready.py \
  go-backend/internal/api/health.go go-backend/internal/api/health_test.go \
  go-backend/internal/client/ml_client.go go-backend/cmd/server/main.go
git -C arxiv-research-assistant commit -m "feat: split arxiv liveness from readiness"
```

---

### Task A6 — Propagasi `X-Request-ID` dan query log yang deterministik

**Tujuan:** satu request ID dari gateway sampai `query_logs`; log ditulis sebelum
response sehingga smoke bisa memverifikasinya.

**Files**

- Modify `go-backend/internal/middleware/request_id.go`
- Modify `go-backend/internal/middleware/request_id_test.go`
- Modify `go-backend/internal/api/query.go`
- Modify `go-backend/internal/api/query_test.go`
- Modify `go-backend/internal/repository/query_logs.go`
- Modify `arxiv-research-assistant/infra/postgres/init.sql`
- Modify `arxiv-research-assistant/infra/postgres/migrations/001_query_logs_request_id.sql`

**Perubahan**

```go
// request_id.go
func RequestID() fiber.Handler {
    return func(c *fiber.Ctx) error {
        requestID := strings.TrimSpace(c.Get("X-Request-ID"))
        if requestID == "" || len(requestID) > 128 {
            requestID = uuid.New().String()
        }
        c.Locals("requestID", requestID)
        c.Response().Header.Set("X-Request-ID", requestID)
        return c.Next()
    }
}
```

`query_logs`:

```sql
ALTER TABLE query_logs ADD COLUMN IF NOT EXISTS request_id VARCHAR(128);
CREATE INDEX IF NOT EXISTS idx_query_logs_request_id ON query_logs(request_id);
```

`repository.CreateQueryLogParams` tambah `RequestID string`; INSERT memakai
`NULLIF($9, '')`.

`api/query.go`:

- Hapus `go func()`.
- Tulis log secara sinkron dengan `context.WithTimeout(c.Context(), 2*time.Second)`.
- Panggil helper yang sama untuk jalur sukses, `insufficient_context`, dan error.
- Jangan gagalkan request jika log gagal; cukup `fmt.Printf`.

**TDD**

- `TestRequestIDMiddleware_HonorsInboundHeader`
- `TestRequestIDMiddleware_GeneratesWhenMissing`
- `TestQueryHandler_LogsBeforeResponse`
- `TestQueryHandler_LogsInsufficientContext`
- `TestQueryHandler_LogsProviderError`
- `TestQueryLogRepository_StoresRequestID`

**Verifikasi**

```bash
cd arxiv-research-assistant/go-backend
go test ./internal/middleware/... ./internal/api/... ./internal/repository/... -race
```

**Commit**

```bash
git -C arxiv-research-assistant add go-backend/internal/middleware/request_id.go \
  go-backend/internal/middleware/request_id_test.go go-backend/internal/api/query.go \
  go-backend/internal/api/query_test.go go-backend/internal/repository/query_logs.go \
  infra/postgres/init.sql infra/postgres/migrations/001_query_logs_request_id.sql
git -C arxiv-research-assistant commit -m "feat: propagate request id and log queries synchronously"
```

---

### Task A7 — Perbaiki prompt `/evaluate` (tanpa truncation 800 karakter)

**Temuan:** `evaluate_faithfulness()` mengirim prompt evaluasi sebagai “context chunk”
ke `generate(query, [prompt])`; `build_prompt` memotong tiap chunk ke 800 karakter dan
hanya mengambil 5 chunk. Instruksi `SCORE:` ada di akhir prompt yang terpotong.

**Files**

- Modify `python-ml/engine/generation/ollama_client.py`
- Modify `python-ml/engine/evaluation/faithfulness.py`
- Create `python-ml/tests/test_evaluation_prompt.py`

**Interface**

```python
# ollama_client.py
def generate_with_prompt(
    prompt: str,
    model: str = DEFAULT_MODEL,
    *,
    max_tokens: int = 512,
    num_ctx: int = 8192,
) -> dict[str, Any]:
    """Send an already-built prompt. No context truncation."""

def generate(query: str, context_chunks: list[str], model: str = DEFAULT_MODEL) -> dict:
    return generate_with_prompt(build_prompt(query, context_chunks), model)
```

`evaluate_faithfulness` membangun prompt penuh:

```text
You are an evaluation system...
Return exactly:
SCORE: <float 0..1>
FAILURE_MODE: <correct|hallucination|insufficient_context|mixed>

Context:
<full context, max 12000 chars>

Question: ...
Answer: ...
```

`SCORE:` dan format output diletakkan di awal **dan** diulang di akhir. Parser:

```python
match = re.search(r"^SCORE:\s*([0-9]*\.?[0-9]+)\s*$", raw, re.MULTILINE)
score = max(0.0, min(1.0, float(match.group(1)))) if match else 0.5
```

Pertahankan `faithfulness: float` agar kontrak response tidak berubah; tambahkan
`parse_status` hanya di log, bukan response.

**TDD**

- `test_evaluate_prompt_is_not_truncated_to_800_chars`: context 5000 char muncul utuh.
- `test_evaluate_uses_generation_prompt_not_context_chunk`: mock `generate_with_prompt`
  menerima prompt yang mengandung `SCORE:`.
- `test_evaluate_parses_score_and_clamps`.
- `test_evaluate_unparseable_score_returns_0_5_and_logs`.

**Verifikasi**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest tests/test_evaluation_prompt.py tests/ -q
```

**Commit**

```bash
git -C arxiv-research-assistant add python-ml/engine/generation/ollama_client.py \
  python-ml/engine/evaluation/faithfulness.py python-ml/tests/test_evaluation_prompt.py
git -C arxiv-research-assistant commit -m "fix(python-ml): evaluate with a full prompt, not a truncated context chunk"
```

---

### Task A8 — CORS untuk ingest dari UI

**Files**

- Modify `python-ml/main.py`
- Create `python-ml/tests/test_cors.py`

**Perubahan**

```python
from fastapi.middleware.cors import CORSMiddleware
import os

_origins = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ALLOW_ORIGINS",
        "http://localhost:3000,http://127.0.0.1:3000,"
        "http://localhost:8080,http://127.0.0.1:8080,null",
    ).split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "X-Request-ID"],
)
```

**TDD**

- `test_preflight_ingest_allows_local_ui_origin`
- `test_preflight_rejects_unknown_origin`

**Verifikasi**

```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. ../../venv/bin/python -m pytest tests/test_cors.py -q
```

**Commit**

```bash
git -C arxiv-research-assistant add python-ml/main.py python-ml/tests/test_cors.py
git -C arxiv-research-assistant commit -m "fix(python-ml): allow the local UI to call ingest"
```

---

### Task A9 — Quick Start dan Makefile submodule

**Files**

- Modify `arxiv-research-assistant/Makefile`
- Modify `arxiv-research-assistant/README.md`

**Perubahan**

- Tambah `SHELL := /bin/bash` di Makefile.
- Ganti `source venv/bin/activate` dengan `. venv/bin/activate`.
- Tambah target `check-ports` yang mendeteksi 8001/8080 dan mencetak:
  “root compose sudah memakai port ini; gunakan `make up` dari root atau hentikan
  stack root dulu”.
- README Quick Start menjelaskan dua mode: root Compose (default) dan submodule
  standalone (butuh port berbeda).

**Verifikasi**

```bash
cd arxiv-research-assistant
make -n run-ml
bash -n Makefile 2>/dev/null || true
```

**Commit**

```bash
git -C arxiv-research-assistant add Makefile README.md
git -C arxiv-research-assistant commit -m "docs: make arxiv quick start shell- and port-safe"
```

---

## 8. Workstream R — `rag-research`

### Task R1 — Taksonomi provider failure yang eksplisit

**Tujuan:** provider error tidak lagi terlihat seperti abstention sah.

**Files**

- Modify `src/generation/generator.py`
- Modify `src/api/main.py`
- Modify `tests/test_generation_error_contract.py`
- Modify `tests/test_api_phase1.py`
- Create `tests/test_failure_taxonomy.py`

**Konstanta dan interface**

```python
FAILURE_INSUFFICIENT_CONTEXT = "insufficient_context"
FAILURE_UNSUPPORTED_CLAIMS = "unsupported_claims"
FAILURE_PROVIDER_ERROR = "provider_error"
FAILURE_SANITY_CHECK = "sanity_check"
FAILURE_EMPTY_OUTPUT = "empty_output"

PROVIDER_RATE_LIMIT = "rate_limit"
PROVIDER_CONNECTION = "connection"
PROVIDER_AUTH = "auth"
PROVIDER_INVALID_JSON = "invalid_json"
PROVIDER_NOT_CONFIGURED = "not_configured"
PROVIDER_UNKNOWN = "provider"
```

`RAGResponse` tambah:

```python
provider_error_kind: Optional[str] = None
```

`_make_abstain_response` tetap default `failure_type="insufficient_context"` untuk
abstention kontekstual, tetapi tambah parameter `provider_error_kind`.

Closure `_abstain`:

```python
def _abstain(
    reason: str,
    *,
    failure_type: str = FAILURE_PROVIDER_ERROR,
    provider_error_kind: str = PROVIDER_UNKNOWN,
) -> RAGResponse:
    return _make_abstain_response(
        ...,
        failure_type=failure_type,
        provider_error_kind=provider_error_kind,
    )
```

**Pemetaan**

| Jalur | `failure_type` | `provider_error_kind` |
|---|---|---|
| `RateLimitError` setelah retry | `provider_error` | `rate_limit` |
| `APIConnectionError` setelah retry | `provider_error` | `connection` |
| `AuthenticationError` | `provider_error` | `auth` |
| JSON validation fallback gagal | `provider_error` | `invalid_json` |
| `GroqError` lain | `provider_error` | `provider` |
| output kosong | `empty_output` | `None` |
| sanity check gagal | `sanity_check` | `None` |
| reflection/evidence gagal | `unsupported_claims` | `None` |
| retrieval/generator abstention biasa | `insufficient_context` | `None` |

`src/api/main.py`:

- `GenerateResponse` tambah `provider_error_kind: str | None = None`.
- Isi dari `getattr(response, "provider_error_kind", None)`.
- `_log_query_event` ikut mencatat `provider_error_kind`.

**TDD**

Ubah tiga test di `test_generation_error_contract.py` agar juga mengunci:

```python
assert result.failure_type == "provider_error"
assert result.provider_error_kind == "rate_limit"   # / connection / invalid_json
```

Tambah:

- `test_empty_output_is_empty_output_not_insufficient_context`
- `test_sanity_check_has_own_failure_type`
- `test_auth_error_is_structured_provider_error`
- `test_api_forwards_provider_error_kind`
- `test_generic_generator_abstention_still_insufficient_context`

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest \
  tests/test_generation_error_contract.py tests/test_api_phase1.py \
  tests/test_failure_taxonomy.py -q
```

**Commit**

```bash
git -C rag-research add src/generation/generator.py src/api/main.py \
  tests/test_generation_error_contract.py tests/test_api_phase1.py \
  tests/test_failure_taxonomy.py
git -C rag-research commit -m "fix: classify provider failures explicitly"
```

---

### Task R2 — Reranker fallback dan health yang jujur

**Files**

- Modify `src/retrieval/hybrid_retriever.py`
- Modify `src/api/main.py` (health fields)
- Create `tests/test_reranker_fallback.py`

**Perubahan `_rerank`**

```python
def _rerank(self, query: str, candidates: list, text_of=None) -> tuple[list, dict]:
    if not candidates:
        return candidates, {... "skipped_reason": "no candidates"}

    try:
        reranker = self.reranker  # property load may raise
        if not reranker:
            return candidates, {... "skipped_reason": "reranker unavailable"}
        ...
    except Exception as exc:
        logger.warning("[Rerank] unavailable (%s): %s", type(exc).__name__, exc)
        return candidates, {
            "attempted": True,
            "succeeded": False,
            "error": f"{type(exc).__name__}: {exc}"[:200],
            "skipped_reason": "reranker_load_failed",
        }
```

`_run_search` sudah memetakan `reranker_status["succeeded"]` ke `rrf_only`, jadi
fallback otomatis. Tambahkan `reranker_error` ke response event log/health.

**TDD**

- `test_reranker_load_failure_falls_back_to_rrf_without_exception`
- `test_reranker_load_failure_sets_ranking_mode_rrf_only`
- `test_health_reports_reranker_unavailable_after_load_failure`
- `test_score_pairs_does_not_load_when_reranker_missing`

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_reranker_fallback.py tests/test_api_phase1.py -q
```

**Commit**

```bash
git -C rag-research add src/retrieval/hybrid_retriever.py src/api/main.py \
  tests/test_reranker_fallback.py
git -C rag-research commit -m "fix: degrade to rrf when the reranker cannot load"
```

---

### Task R3 — Pisahkan `/health` (liveness) dan `/ready` (dependency + index)

**Files**

- Modify `src/api/main.py`
- Modify `rag-research/Dockerfile`
- Create `tests/test_api_readiness.py`

**Perubahan**

```python
CANONICAL_PROBE_QUERY = "How does hybrid retrieval combine dense and sparse search?"

@app.get("/health")
async def health():
    return {"status": "ok", "service": "rag-research"}

@app.get("/ready")
async def ready():
    if not all([store, retriever, generator, confidence_engine]):
        raise HTTPException(status_code=503, detail="engine not initialized")
    try:
        diagnostics = await run_in_threadpool(
            store.require_nonempty_index,
            expected_corpus_chunks=CANONICAL_CORPUS_CHUNKS,
            consumer="readiness",
            query_probe=CANONICAL_PROBE_QUERY,
        )
    except IndexIntegrityError as exc:
        raise HTTPException(status_code=503, detail={
            "status": "not_ready",
            "reason": exc.__class__.__name__,
            "diagnostics": exc.diagnostics,
        })
    if not generator.is_configured:
        raise HTTPException(status_code=503, detail={
            "status": "not_ready",
            "reason": "provider_not_configured",
        })
    return {
        "status": "ready",
        "vectors": diagnostics["vector_count"],
        "expected_vectors": CANONICAL_CORPUS_CHUNKS,
        "provider_configured": True,
        "reranker_model_loaded": retriever.reranker_loaded,
    }
```

`Dockerfile` healthcheck mengganti `/health` menjadi `/ready`. `/health` tetap untuk
liveness Compose bila diperlukan.

**TDD**

- `test_health_200_when_store_missing` (liveness)
- `test_ready_503_when_store_missing`
- `test_ready_503_on_empty_index`
- `test_ready_503_on_count_mismatch`
- `test_ready_503_when_provider_not_configured`
- `test_ready_200_with_matching_index`
- `test_ready_includes_diagnostics_without_secrets`

Gunakan `FakeStore` seperti `tests/test_api_startup.py`.

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_api_readiness.py tests/test_api_startup.py -q
```

**Commit**

```bash
git -C rag-research add src/api/main.py Dockerfile tests/test_api_readiness.py
git -C rag-research commit -m "feat: add dependency-aware readiness to rag api"
```

---

### Task R4 — `GROQ_API_KEY` kosong tidak boleh membuat crash loop

**Files**

- Modify `src/generation/generator.py`
- Modify `src/api/main.py`
- Create `tests/test_generator_not_configured.py`

**Perubahan**

```python
class GroqGenerator:
    def __init__(self, api_key: Optional[str] = None, model: str = DEFAULT_MODEL):
        key = api_key or os.getenv("GROQ_API_KEY")
        self.client = Groq(api_key=key) if key else None
        self.is_configured = bool(key)
        self.model = model
        ...

    def generate(...):
        if not self.is_configured:
            return _make_abstain_response(
                query=query,
                chunks=chunks,
                model=self.model,
                reason="provider_error: GROQ_API_KEY is not configured",
                failure_type="provider_error",
                provider_error_kind="not_configured",
            )
```

Startup:

- Jangan raise; log warning `[STARTUP] GROQ_API_KEY missing — /ready will fail, /generate returns provider_error`.
- `/ready` 503 (Task R3).
- `/generate` tetap HTTP 200 dengan `failure_type=provider_error`, `provider_error_kind=not_configured` agar kontrak gateway tidak berubah.

**TDD**

- `test_generator_without_key_is_constructed_but_unconfigured`
- `test_generate_without_key_returns_provider_error`
- `test_generate_without_key_does_not_call_provider`
- `test_startup_succeeds_without_key`
- `test_ready_503_without_key`

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_generator_not_configured.py tests/test_api_readiness.py -q
```

**Commit**

```bash
git -C rag-research add src/generation/generator.py src/api/main.py \
  tests/test_generator_not_configured.py
git -C rag-research commit -m "fix: start without a groq key and report not_ready"
```

---

### Task R5 — `seed_canonical.py` non-destruktif + Makefile

**Tujuan:** `make seed-rag` mengisi Qdrant Compose dengan corpus v2 kanonik, menolak
collection non-empty, dan tidak pernah reset tanpa `--force`.

**Files**

- Create `rag-research/scripts/seed_canonical.py`
- Create `rag-research/tests/test_seed_canonical.py`
- Modify root `Makefile`

**Interface**

```python
CANONICAL_PATH = Path("data/processed/chunks_semantic_v2.json")
CANONICAL_SHA256 = "4375a266..."  # nilai lengkap di src/api/main.py
CANONICAL_CHUNKS = 796

def main(argv: list[str] | None = None) -> int:
    """Exit codes: 0 success, 1 invalid corpus, 2 non-empty collection without --force."""
```

CLI:

```text
--corpus PATH       default data/processed/chunks_semantic_v2.json
--qdrant-url URL    default $QDRANT_URL or http://localhost:6333
--collection NAME   default $QDRANT_COLLECTION or rag_research
--force             allow reset=True (prints collection + count first)
```

Alur:

1. Load `.env` root via `python-dotenv` (best effort).
2. Validasi file ada, count 796, SHA cocok. Jangan lanjut jika beda.
3. Buat `QdrantVectorStore(qdrant_url=..., collection_name=...)`.
4. `index_diagnostics()`. Jika `vector_count > 0` dan bukan `--force`: cetak alasan dan
   return 2.
5. `index_chunks(chunks, reset=force)`.
6. Verifikasi count == 796; return 0/1.

**Root Makefile**

```make
seed-rag:  ## Seed the canonical v2 corpus into the compose Qdrant (refuses non-empty)
	cd rag-research && QDRANT_URL=$${QDRANT_URL:-http://localhost:6333} \
		$(PYTHON) scripts/seed_canonical.py

seed-rag-force:  ## DESTRUCTIVE: reset rag_research collection, then seed
	cd rag-research && QDRANT_URL=$${QDRANT_URL:-http://localhost:6333} \
		$(PYTHON) scripts/seed_canonical.py --force
```

Hapus tiga baris lama (`document_loader`, `semantic_chunker`, `qdrant_store`).

**TDD**

- `test_refuses_non_empty_collection_without_force` → exit 2, `index_chunks` tidak dipanggil.
- `test_force_resets_and_indexes` → `index_chunks(reset=True)`.
- `test_rejects_wrong_count`
- `test_rejects_wrong_sha`
- `test_uses_qdrant_url_from_argument`
- `test_does_not_read_v3_chunker_output`

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_seed_canonical.py -q
cd ..
make -n seed-rag
```

**Commit**

```bash
git -C rag-research add scripts/seed_canonical.py tests/test_seed_canonical.py
git -C rag-research commit -m "feat: add a non-destructive canonical seed script"
git add Makefile
git commit -m "fix: make seed-rag target the compose qdrant and refuse resets"
```

---

### Task R6 — Samakan `rag-research/.env.example` dengan Settings

**Files**

- Modify `rag-research/.env.example`
- Create `rag-research/tests/test_env_example.py`

**Perubahan**

Ganti nama yang tidak dikenal (`CONFIDENCE_THRESHOLD`, `REJECT_THRESHOLD`, `MAX_TOKENS`,
`TEMPERATURE`, `MAX_CHARS`) dengan nama field/alias yang benar:

```env
RAG_EMBED_MODEL=sentence-transformers/all-MiniLM-L6-v2
RAG_RERANK_MODEL=cross-encoder/ms-marco-MiniLM-L-6-v2
RAG_CONFIDENCE_REJECT_THRESHOLD=0.35
RAG_CONFIDENCE_PARTIAL_THRESHOLD=0.65
RAG_GENERATION_MAX_TOKENS=768
RAG_GENERATION_TEMPERATURE=0.1
RAG_GENERATION_MAX_CHARS=6000
RAG_USE_MULTI_QUERY=false
RAG_USE_HYDE=false
RAG_VECTOR_DIM=384
REDIS_ENABLED=false
REDIS_URL=redis://redis:6379/0
GROQ_API_KEY=gsk_your_actual_key_here
```

**TDD** `test_env_example.py`:

- Parse `.env.example`.
- Assert setiap key non-komentar ada di `Settings.model_fields` atau
  `validation_alias`/`AliasChoices`.
- Assert `GROQ_API_KEY` adalah placeholder yang dikenali scanner.
- Assert `RAG_EMBED_MODEL` sama dengan default `Settings.embed_model`.

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_env_example.py tests/test_settings_fields_are_used.py -q
```

**Commit**

```bash
git -C rag-research add .env.example tests/test_env_example.py
git -C rag-research commit -m "docs: align rag env example with settings fields"
```

---

### Task R7 — Validasi dimensi vektor terhadap collection

**Files**

- Modify `src/retrieval/qdrant_store.py`
- Create `tests/test_vector_dimension.py`

**Perubahan**

```python
class IndexDimensionMismatch(IndexIntegrityError):
    pass

class QdrantVectorStore:
    def __init__(..., vector_dim: Optional[int] = None, ...):
        if vector_dim is None:
            vector_dim = getattr(
                self.embedder, "get_sentence_embedding_dimension", lambda: VECTOR_DIM
            )()
        self.vector_dim = int(vector_dim)
        ...
        self._validate_collection_dim()

    def _validate_collection_dim(self) -> None:
        info = self.client.get_collection(self.collection_name)
        size = info.config.params.vectors.size
        if int(size) != self.vector_dim:
            raise IndexDimensionMismatch(
                f"collection dimension {size} != embedder dimension {self.vector_dim}"
            )

    def index_chunks(self, chunks, reset=False):
        for i, chunk in enumerate(chunks):
            emb = chunk.get("embedding")
            if emb is not None and len(emb) != self.vector_dim:
                raise ValueError(
                    f"chunk {i} embedding has {len(emb)} dims; expected {self.vector_dim}"
                )
        ...

    def search(self, query_vector, ...):
        if len(query_vector) != self.vector_dim:
            raise ValueError(
                f"query vector has {len(query_vector)} dims; expected {self.vector_dim}"
            )
```

**TDD**

- `test_dimension_derived_from_embedder`
- `test_existing_collection_dimension_mismatch_raises`
- `test_index_rejects_wrong_embedding_dimension_before_upsert`
- `test_search_rejects_wrong_query_dimension`
- `test_env_override_is_validated_against_embedder`

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_vector_dimension.py tests/test_qdrant_store.py -q
```

**Commit**

```bash
git -C rag-research add src/retrieval/qdrant_store.py tests/test_vector_dimension.py
git -C rag-research commit -m "fix: validate embedding and collection dimensions"
```

---

### Task R8 — Metrik memakai decision publik

**Files**

- Modify `src/api/main.py`
- Create `tests/test_api_metrics_decision.py`

**Perubahan**

Di kedua cabang (`PARTIAL_TRUST` dan `GENERATE`), hitung:

```python
public_decision = "REJECT" if generation_abstained else decision
```

lalu:

```python
_record_metrics(
    decision=public_decision,
    failure_type=result.failure_type,
    latency_ms=result.latency_total_ms,
    confidence=confidence,
)
```

**TDD**

- `test_generation_abstention_increments_reject_decision_metric`
- `test_successful_answer_increments_generate_decision_metric`
- `test_partial_trust_abstention_increments_reject`

Gunakan `prometheus_client.REGISTRY.get_sample_value`.

**Verifikasi**

```bash
cd rag-research
../venv/bin/python -m pytest tests/test_api_metrics_decision.py tests/test_api_phase1.py -q
```

**Commit**

```bash
git -C rag-research add src/api/main.py tests/test_api_metrics_decision.py
git -C rag-research commit -m "fix: record the public decision in rag metrics"
```

---

## 9. Workstream E — `llm-eval-framework`

### Task E1 — Checkpoint schema version + completeness gate

**Files**

- Modify `pipeline/runner.py`
- Modify `tests/test_runner_resume.py`
- Create `tests/test_checkpoint_validation.py`

**Konstanta/interface**

```python
CHECKPOINT_SCHEMA_VERSION = 2

REQUIRED_FAITHFULNESS_FIELDS = {
    "case_id", "model", "question", "answer",
    "faithfulness_score", "supported_count", "total_claims",
    "similarity_threshold", "embedding_model", "evaluator_version",
    "timestamp_utc",
}

class CheckpointInvalidError(ValueError):
    pass

def _checkpoint_is_complete(data: dict) -> bool: ...
def _checkpoint_to_faithfulness_result(data: dict | None, ...) -> FaithfulnessResult: ...
```

`_load_checkpoint`:

```python
data = json.load(f)
if not _checkpoint_is_complete(data):
    logger.warning(
        "Incomplete/stale checkpoint ignored | case_id=%s | schema=%s",
        case_id, data.get("schema_version"),
    )
    return None
return data
```

`_save_checkpoint` menambahkan `"schema_version": CHECKPOINT_SCHEMA_VERSION` ke root
checkpoint (bukan ke `faithfulness_result`).

`_checkpoint_to_faithfulness_result`:

```python
if not isinstance(data, dict) or not data:
    raise CheckpointInvalidError("faithfulness_result is missing")
missing = REQUIRED_FAITHFULNESS_FIELDS - set(data)
if missing:
    raise CheckpointInvalidError(f"faithfulness_result missing fields: {sorted(missing)}")
```

Caller hanya memanggil untuk checkpoint yang sudah lolos completeness; guard tetap ada.

**TDD**

- `test_null_faithfulness_result_is_not_complete`
- `test_old_schema_checkpoint_is_ignored`
- `test_missing_required_field_is_ignored`
- `test_corrupt_json_is_ignored`
- `test_complete_checkpoint_is_reused`
- `test_checkpoint_to_result_none_raises_checkpoint_invalid`
- `test_resume_after_null_checkpoint_reruns_case` (integration dengan `run_evaluation`)

**Verifikasi**

```bash
cd llm-eval-framework
../venv/bin/python -m pytest tests/test_runner_resume.py tests/test_checkpoint_validation.py -q
```

**Commit**

```bash
git -C llm-eval-framework add pipeline/runner.py tests/test_runner_resume.py \
  tests/test_checkpoint_validation.py
git -C llm-eval-framework commit -m "fix: reject incomplete checkpoints instead of crashing"
```

---

### Task E2 — Serialisasi checkpoint lossless

**Files**

- Modify `pipeline/runner.py`
- Create `tests/test_checkpoint_roundtrip.py`

**Perubahan**

`_faithfulness_to_dict` harus menulis **semua** field `FaithfulnessResult`:

```python
return {
    "case_id": result.case_id,
    "model": result.model,
    "question": result.question,
    "answer": result.answer,
    "context_preview": result.context_preview,
    "total_claims": result.total_claims,
    "claims": result.claims,
    "evidence_matches": result.evidence_matches,
    "supported_count": result.supported_count,
    "unsupported_count": result.unsupported_count,
    "skipped_count": result.skipped_count,
    "faithfulness_score": result.faithfulness_score,
    "is_insufficient_context_response": result.is_insufficient_context_response,
    "has_failure": result.has_failure,
    "failure_cases": result.failure_cases,
    "similarity_threshold": result.similarity_threshold,
    "embedding_model": result.embedding_model,
    "evaluator_version": result.evaluator_version,
    "timestamp_utc": result.timestamp_utc,
    "evaluation_path": result.evaluation_path,
}
```

`_checkpoint_to_faithfulness_result` membaca semua field dengan default yang aman, tetapi
**tidak** mengganti `similarity_threshold`, `embedding_model`, `evaluator_version`, atau
`timestamp_utc` dengan nilai sekarang bila field tersedia.

`_dict_to_query_output` harus mengembalikan `model`, `question`,
`context_length_chars`, `timestamp_utc` dari checkpoint.

**TDD**

- `test_faithfulness_roundtrip_preserves_all_fields`
- `test_query_output_roundtrip_preserves_provenance`
- `test_resume_does_not_rewrite_threshold_or_timestamp`
- `test_claims_and_evidence_matches_survive_resume`

**Verifikasi**

```bash
cd llm-eval-framework
../venv/bin/python -m pytest tests/test_checkpoint_roundtrip.py tests/test_runner_resume.py -q
```

**Commit**

```bash
git -C llm-eval-framework add pipeline/runner.py tests/test_checkpoint_roundtrip.py
git -C llm-eval-framework commit -m "fix: serialize checkpoints without losing provenance"
```

---

### Task E3 — Atomic checkpoint write

**Files**

- Modify `pipeline/runner.py`
- Create `tests/test_checkpoint_atomic_write.py`

**Perubahan**

```python
def _save_checkpoint(model, dataset, case_id, result):
    path = _checkpoint_path(model, dataset, case_id)
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()
```

**TDD**

- `test_write_uses_replace`
- `test_failed_write_leaves_previous_checkpoint_intact`
- `test_no_tmp_file_remains_after_success`

**Verifikasi**

```bash
cd llm-eval-framework
../venv/bin/python -m pytest tests/test_checkpoint_atomic_write.py -q
```

**Commit**

```bash
git -C llm-eval-framework add pipeline/runner.py tests/test_checkpoint_atomic_write.py
git -C llm-eval-framework commit -m "fix: write checkpoints atomically"
```

---

### Task E4 — `/health` dan `/ready`

**Files**

- Modify `api.py`
- Modify `Dockerfile` (healthcheck)
- Modify `tests/test_api.py`
- Create `tests/test_ready.py`

**Perubahan**

```python
@app.get("/health")
def health():
    return {"status": "ok", "service": "llm-eval-framework"}

@app.get("/ready")
async def ready():
    if evaluator is None:
        raise HTTPException(status_code=503, detail={
            "status": "not_ready", "reason": "evaluator_not_initialized",
        })
    ok = await run_in_threadpool(evaluator.health_check)
    if not ok:
        raise HTTPException(status_code=503, detail={
            "status": "not_ready",
            "reason": "embedding_unavailable",
            "embedding_model": evaluator.embedding_model,
        })
    return {
        "status": "ready",
        "embedding_model": evaluator.embedding_model,
        "evaluator_version": evaluator.VERSION,
    }
```

Docker healthcheck mengganti `/health` menjadi `/ready`.

**TDD**

- `test_health_200_without_evaluator`
- `test_ready_503_when_evaluator_missing`
- `test_ready_503_when_embedding_health_false`
- `test_ready_200_when_health_true`
- `test_ready_includes_model_and_version`

**Verifikasi**

```bash
cd llm-eval-framework
../venv/bin/python -m pytest tests/test_ready.py tests/test_api.py -q
```

**Commit**

```bash
git -C llm-eval-framework add api.py Dockerfile tests/test_ready.py tests/test_api.py
git -C llm-eval-framework commit -m "feat: add embedding-aware readiness endpoint"
```

---

### Task E5 — `/evaluate` error semantics

**Files**

- Modify `api.py`
- Modify `tests/test_api.py`

**Perubahan**

- `evaluator.evaluate` exception yang merupakan connection/timeout → HTTP 503 dengan
  `detail={"status":"not_ready","reason":"embedding_unavailable"}`.
- Input kosong tetap 400.
- Exception tak terduga tetap 500.
- Tambah `failure_mode` untuk provider/evaluator error? Jangan ubah `EvalResponse`
  kecuali perlu; gunakan HTTP status.

**TDD**

- `test_evaluate_returns_503_when_ollama_unreachable`
- `test_evaluate_returns_400_on_empty_answer`
- `test_evaluate_returns_500_on_unexpected_error`
- `test_evaluate_success_shape_unchanged`

**Verifikasi**

```bash
cd llm-eval-framework
../venv/bin/python -m pytest tests/test_api.py -q
```

**Commit**

```bash
git -C llm-eval-framework add api.py tests/test_api.py
git -C llm-eval-framework commit -m "fix: distinguish evaluator unavailability from bad input"
```

---

## 10. Workstream G — `mcp-gateway`

### Task G1 — `/ready` body-aware, `not_ready`, dan capabilities lengkap

**Files**

- Modify `cmd/server/router.go`
- Modify `cmd/server/ready_test.go`
- Modify `internal/api/contract.go` (jika perlu tipe status)

**Perubahan**

```go
type dependencyCheck struct {
    Status     string // up | degraded | down | not_ready
    HTTPStatus int
    BodyStatus string
    Error      string
}

func checkService(ctx context.Context, baseURL, path string) dependencyCheck {
    endpoint := strings.TrimRight(baseURL, "/") + path
    req, _ := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
    resp, err := (&http.Client{Timeout: 3 * time.Second}).Do(req)
    if err != nil { return dependencyCheck{Status: "down", Error: err.Error()} }
    defer resp.Body.Close()

    var body struct{ Status string `json:"status"` }
    _ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&body)

    switch {
    case resp.StatusCode == http.StatusOK && (body.Status == "ok" || body.Status == "ready"):
        return dependencyCheck{Status: "up", HTTPStatus: resp.StatusCode, BodyStatus: body.Status}
    case resp.StatusCode == http.StatusServiceUnavailable && body.Status == "not_ready":
        return dependencyCheck{Status: "not_ready", HTTPStatus: resp.StatusCode, BodyStatus: body.Status}
    case resp.StatusCode == http.StatusOK:
        return dependencyCheck{Status: "degraded", HTTPStatus: resp.StatusCode, BodyStatus: body.Status}
    default:
        return dependencyCheck{Status: "degraded", HTTPStatus: resp.StatusCode, BodyStatus: body.Status}
    }
}
```

`handleReady`:

- Probe `arxiv`, `rag`, `evaluator` di `/ready`.
- `answersReady := arxiv.Status == "up" || rag.Status == "up"`.
- `evaluationReady := evaluator.Status == "up"`.
- HTTP:
  - `all up` → 200 `status=ready`
  - `answersReady && !all up` → 200 `status=degraded`
  - `!answersReady` → 503 `status=not_ready`
- Body:
  - `services` tetap `map[string]string` untuk kompatibilitas.
  - `details` baru: `map[string]dependencyCheck`.
  - `capabilities`: `answers`, `arxiv`, `research_rag`, `evaluation`, `logging`.
- `answers` hanya true jika arxiv/rag benar-benar `up`.
- Jangan pernah melaporkan `answers=true` saat keduanya `degraded`/`not_ready`.

**TDD — update `ready_test.go`**

- Ganti `serviceWithHealthStatus` agar menerima path dan body.
- `TestReady_AllDependenciesUp`: `/ready` dipanggil untuk ketiga service; capabilities
  `evaluation=true`.
- `TestReady_Arxiv200ButBodyDegradedReturns503`: arxiv body `{"status":"degraded"}` →
  503 `not_ready`, `answers=false`.
- `TestReady_Arxiv503NotReadyReturns503`.
- `TestReady_EvaluatorDownAnswersStillReady`: 200 `degraded`, `evaluation=false`.
- `TestReady_OneAnswerBackendDownStillServesOther`: tetap 200 `degraded`.
- `TestReady_NoAnswerBackendAvailableReturns503`: status `not_ready` (bukan `degraded`).
- `TestReady_ProbesUseReadyPath`.

**Verifikasi**

```bash
cd mcp-gateway
go test ./cmd/server -run TestReady -race -v
go test ./... -race
```

**Commit**

```bash
git -C mcp-gateway add cmd/server/router.go cmd/server/ready_test.go internal/api/contract.go
git -C mcp-gateway commit -m "fix: make gateway readiness body-aware and honest"
```

---

### Task G2 — Petakan `provider_error` tanpa menyamarkannya sebagai abstention

**Files**

- Modify `internal/api/contract.go`
- Modify `internal/tools/research_rag_contract.go`
- Modify `internal/tools/research_rag.go`
- Modify `internal/planner/executor.go`
- Modify `cmd/server/respond.go`
- Modify `internal/tools/research_rag_test.go`
- Modify `cmd/server/router_test.go`

**Perubahan kontrak**

```go
const (
    FailureProviderError = "provider_error"
    FailureSanityCheck   = "sanity_check"
    FailureEmptyOutput   = "empty_output"
)

type BackendAnswer struct {
    ...
    ProviderErrorKind string `json:"provider_error_kind,omitempty"`
}
```

`ResearchRAGResponse` tambah `ProviderErrorKind string`.

`IsAbstention()` urutan baru:

```go
func (r ResearchRAGResponse) IsAbstention() bool {
    switch r.FailureType {
    case api.FailureProviderError, api.FailureSanityCheck, api.FailureEmptyOutput:
        return false
    }
    if strings.TrimSpace(r.Decision) == "REJECT" {
        return true
    }
    if r.FailureType == api.FailureInsufficientContext ||
        r.FailureType == api.FailureUnsupportedClaims {
        return true
    }
    return strings.TrimSpace(r.Answer) == api.RAGAbstainText
}

func (r ResearchRAGResponse) IsProviderError() bool {
    return r.FailureType == api.FailureProviderError
}
```

`ToolData()` ikut menulis `provider_error_kind`.

`planner.ExecutionResult` tambah:

```go
FailureType       string
ProviderErrorKind string
```

Interface ad-hoc di `executor.go` tambah method `FailureType() string` dan
`ProviderErrorKind() string`, atau gunakan type switch ke `ResearchRAGResponse`.
Setelah step sukses:

```go
result.FailureType = typed.FailureType()
result.ProviderErrorKind = typed.ProviderErrorKind()
```

`respond.go`:

```go
case result.FailureType == api.FailureProviderError:
    resp.Decision = api.DecisionError
    resp.FailureType = api.FailureProviderError
    resp.ProviderErrorKind = result.ProviderErrorKind
```

`respond()` sudah memetakan `decision=error` ke HTTP 502. **Ini perubahan kontrak
publik**: provider error menjadi 502, bukan 200 abstain. Task ini eksplisit mengubah
perilaku; update `docs/api-contract.md` dan smoke.

**TDD**

- `TestResearchRAGProviderErrorIsNotAbstention`
- `TestResearchRAGProviderErrorMapsToDecisionError`
- `TestProviderErrorResponseIs502`
- `TestSanityCheckIsNotAbstention`
- `TestEmptyOutputIsNotAbstention`
- `TestProviderErrorKindIsPreserved`
- `TestInsufficientContextStillAbstains`

**Verifikasi**

```bash
cd mcp-gateway
go test ./internal/tools/... ./internal/planner/... ./cmd/server/... -race
```

**Commit**

```bash
git -C mcp-gateway add internal/api/contract.go \
  internal/tools/research_rag_contract.go internal/tools/research_rag.go \
  internal/planner/executor.go cmd/server/respond.go \
  internal/tools/research_rag_test.go cmd/server/router_test.go \
  docs/api-contract.md
git -C mcp-gateway commit -m "fix: surface rag provider errors as errors, not abstentions"
```

---

### Task G3 — Store reconnect dan readiness logging

**Files**

- Modify `internal/store/postgres.go`
- Modify `internal/store/postgres_test.go`
- Modify `cmd/server/main.go`
- Modify `cmd/server/router.go` (logging capability)
- Modify `docker-compose.yml` (depends_on postgres)

**Interface**

```go
func Init(dsn string) error
func StartReconnectLoop(ctx context.Context, dsn string, interval time.Duration)
func LogEval(ctx context.Context, e EvalLog) error
func Ready(ctx context.Context) error
```

- `db` dilindungi `sync.RWMutex`.
- `Init` mengembalikan error, tidak menelan.
- `StartReconnectLoop` mencoba `connect` setiap `interval` selama `db == nil`.
- `LogEval` mengembalikan error; caller tetap tidak menggagalkan request.
- `Ready` melakukan `PingContext` dengan timeout 2s.

`main.go`:

```go
if err := store.Init(cfg.PostgresDSN); err != nil {
    log.Printf("[store] initial connect failed: %v; retrying in background", err)
}
store.StartReconnectLoop(ctx, cfg.PostgresDSN, 5*time.Second)
```

Router `/ready` menambahkan `logging` capability dari `store.Ready`.

**TDD**

- `TestInitReturnsErrorWhenPingFails`
- `TestLogEvalReturnsErrorWhenDBUnavailable`
- `TestStartReconnectLoopRecovers`
- `TestReadyReportsLoggingUnavailable`
- `TestReadyReportsLoggingAvailable`

Gunakan `connectFn` variable yang bisa di-inject test.

**Verifikasi**

```bash
cd mcp-gateway
go test ./internal/store/... ./cmd/server/... -race
```

**Commit**

```bash
git -C mcp-gateway add internal/store/postgres.go internal/store/postgres_test.go \
  cmd/server/main.go cmd/server/router.go
git commit -m "fix: retry gateway postgres logging instead of disabling it forever"
```

---

### Task G4 — `X-Request-ID` di response dan downstream

**Files**

- Modify `cmd/server/router.go`
- Modify `cmd/server/router_test.go`

**Perubahan**

Ganti `middleware.RequestID` dengan middleware lokal:

```go
func requestIDMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        id := strings.TrimSpace(r.Header.Get("X-Request-ID"))
        if id == "" || len(id) > 128 {
            id = generateRequestID()
        }
        ctx := context.WithValue(r.Context(), requestIDKey{}, id)
        w.Header().Set("X-Request-ID", id)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

`requestID(req)` membaca context value; fallback ke `middleware.GetReqID` untuk
kompatibilitas test lama.

**TDD**

- `TestRequestID_HonorsInboundHeaderAndEchoesIt`
- `TestRequestID_GeneratesWhenMissing`
- `TestRequestID_RejectsOverlongHeader`
- `TestAskResponseRequestIDMatchesHeader`

**Verifikasi**

```bash
cd mcp-gateway
go test ./cmd/server -run TestRequestID -race -v
go test ./... -race
```

**Commit**

```bash
git -C mcp-gateway add cmd/server/router.go cmd/server/router_test.go
git -C mcp-gateway commit -m "fix: echo and propagate X-Request-ID"
```

---

### Task G5 — Budget timeout yang konsisten

**Files**

- Modify `internal/config/config.go`
- Modify `internal/config/config_test.go`
- Modify `internal/planner/executor.go` (jika perlu remaining budget)
- Modify `docker-compose.yml` env defaults

**Keputusan default**

- `DefaultArxivTimeout = 480 * time.Second` (turun dari 600s).
- `DefaultEvaluatorTimeout = 120 * time.Second`.
- `DefaultRAGTimeout = 120 * time.Second` (naik dari 60s agar konsisten dengan
  kebutuhan generation).
- `DefaultRequestTimeout = 650 * time.Second` (max answer + evaluator + reserve).
- Dokumentasikan bahwa plan adalah satu answer step + satu evaluator step.

**TDD**

- `TestDefaultTimeoutsLeaveEvaluatorBudget`:
  ```go
  if cfg.RequestTimeout < cfg.Arxiv.Timeout+cfg.Evaluator.Timeout+10*time.Second {
      t.Fatal("request timeout leaves no evaluator budget")
  }
  ```
- `TestEnvOverridesRespectRequestBudget`
- `TestPlannerUsesRemainingDeadline` (fake executor mencatat deadline).

**Verifikasi**

```bash
cd mcp-gateway
go test ./internal/config/... ./internal/planner/... -race
```

**Commit**

```bash
git -C mcp-gateway add internal/config/config.go internal/config/config_test.go \
  internal/planner/executor.go
git commit -m "fix: align gateway timeout budget with downstream steps"
```

---

## 11. Workstream X — integrasi, Compose, dan operasi

### Task X1 — Compose lifecycle dan healthcheck

**Files**

- Modify `docker-compose.yml`
- Modify `README.md` (health semantics)

**Perubahan**

- `rag-api`:
  - hapus `OLLAMA_HOST`.
  - hapus `depends_on: ollama`.
  - healthcheck → `/ready`.
- `arxiv-python-ml`:
  - healthcheck → `/ready`.
  - hapus bind mount `./rag-research/hf-cache/hub` (sudah di Task 0.5).
- `arxiv-go-backend`:
  - healthcheck → `/ready`.
- `llm-eval-framework`:
  - healthcheck → `/ready`.
- `mcp-gateway`:
  - tambah `depends_on: postgres: condition: service_healthy`.
  - healthcheck tetap `/health` (liveness) agar dependency down tidak memicu restart
    loop; `/ready` dipakai orchestrator/operator.
- `rag-api` port:
  - ubah menjadi `${RAG_BIND_ADDRESS:-127.0.0.1}:8000:8000` (P2 hardening; lihat X6).

**Verifikasi**

```bash
docker compose --env-file .env.example config --quiet
docker compose --env-file .env.example config | grep -A3 healthcheck
```

**Commit**

```bash
git add docker-compose.yml README.md
git commit -m "fix: align compose healthchecks and remove unused ollama coupling"
```

---

### Task X2 — Smoke E2E yang memverifikasi request ID dan gateway log

**Files**

- Modify `scripts/smoke_e2e.sh`
- Create `scripts/test_smoke_dry_run.sh`

**Perubahan**

1. Baca kredensial DB dari `.env` bila ada; fallback ke default Compose. Jangan
   hardcode password di perintah `psql`.
2. Generate:
   ```bash
   RUN_ID="$(date +%s)-$$"
   REQUEST_ID="smoke-$RUN_ID"
   UNIQUE_QUERY="What is this paper about? [Run ID: $RUN_ID]"
   ```
3. Kirim `X-Request-ID: $REQUEST_ID` ke `/ask`.
4. Verifikasi:
   - response header `X-Request-ID` sama;
   - `response.request_id` sama;
   - `query_logs` punya baris untuk `UNIQUE_QUERY` dengan `request_id=$REQUEST_ID`;
   - `gateway_query_logs` punya baris untuk `request_id=$REQUEST_ID`, dengan retry
     hingga 10 detik (log gateway ditulis async).
5. Untuk `research_rag`:
   - jika `failure_type` adalah `provider_error`, `sanity_check`, atau `empty_output`
     → **gagal**, bukan diterima sebagai abstain;
   - jika `decision=abstain` dan `failure_type=insufficient_context` → sah.
6. Tambah `SMOKE_DRY_RUN=1`: cetak semua request yang akan dikirim, tidak memanggil
   jaringan, exit 0.

**TDD/verifikasi**

```bash
bash -n scripts/smoke_e2e.sh
SMOKE_DRY_RUN=1 bash scripts/smoke_e2e.sh
```

Untuk runtime penuh, stack harus berjalan:
```bash
docker compose --env-file .env up -d
make smoke-e2e
```

**Commit**

```bash
git add scripts/smoke_e2e.sh scripts/test_smoke_dry_run.sh
git commit -m "test: verify request ids and gateway logs in smoke"
```

---

### Task X3 — `rotate_key.sh` hanya recreate konsumen Groq

**Files**

- Modify `scripts/rotate_key.sh`
- Modify `README.md`/`PROJECT_CONTEXT.md` bila menyebut tiga service

**Perubahan**

- Recreate hanya `rag-api arxiv-python-ml`.
- Verifikasi hanya `ws-rag-api ws-arxiv-python-ml`.
- Update komentar “tiga service” → “dua service”.
- Tambah catatan bahwa gateway tidak lagi memakai Groq planner.

**Verifikasi**

```bash
bash -n scripts/rotate_key.sh
grep -n 'mcp-gateway' scripts/rotate_key.sh && exit 1 || true
```

**Commit**

```bash
git add scripts/rotate_key.sh README.md
git commit -m "fix: stop recreating mcp-gateway on groq key rotation"
```

---

### Task X4 — Migrasi DB dari root

**Files**

- Create `scripts/migrate_db.sh`
- Modify `Makefile`
- Modify `arxiv-research-assistant/infra/postgres/init.sql` (bila perlu)

**Perubahan**

- `make migrate-db` menjalankan semua `infra/postgres/migrations/*.sql` lewat
  `docker compose exec -T postgres psql`.
- Script menolak jalan jika container tidak sehat.
- Untuk volume baru, `init.sql` tetap membuat skema dasar; migrasi idempoten memakai
  `IF NOT EXISTS`.

**Verifikasi**

```bash
bash -n scripts/migrate_db.sh
docker compose --env-file .env.example config --quiet
# runtime:
make migrate-db
```

**Commit**

```bash
git add scripts/migrate_db.sh Makefile arxiv-research-assistant/infra/postgres/init.sql
git commit -m "feat: add an idempotent database migration target"
```

---

### Task X5 — Samakan dokumen dengan perilaku aktual

**Files**

- Modify `README.md`
- Modify `PROJECT_CONTEXT.md`
- Modify `PROJECT_GOALS.md`
- Modify `docs/ai-taskboard.md` (jika ada)
- Modify `rag-research/README.md` (test count, Python version, chunker count)

**Perubahan**

- Test count: `rag-research` **453 passed, 0 skipped**; jangan tulis 419/1 atau 449.
- Smoke: memakai `RUN_ID` unik dan memverifikasi `gateway_query_logs` +
  `X-Request-ID`; hapus klaim “fixed query”.
- `/health` vs `/ready` dijelaskan.
- `provider_error`/`decision=error` dijelaskan di kontrak gateway.
- Python runtime: container 3.12, bukan 3.14.4.
- Chunker: default v3 642; corpus deployed v2 796; jelaskan perbedaannya.
- `.env.example` memuat `GATEWAY_LISTEN_ADDRESS`, `REDIS_ENABLED`, `REDIS_URL`.

**Verifikasi**

```bash
grep -R "419 passed\|1 skipped\|fixed query\|query tetap" README.md PROJECT_CONTEXT.md PROJECT_GOALS.md docs/ || true
grep -R "3.14.4\|449 passed" rag-research/README.md || true
```

**Commit**

```bash
git add README.md PROJECT_CONTEXT.md PROJECT_GOALS.md docs/ai-taskboard.md rag-research/README.md
git commit -m "docs: align documented behavior with the remediated stack"
```

---

## 12. P2 — backlog operasional (detail ringkas)

| ID | Repo | Task | Acceptance |
|---|---|---|---|
| P2-1 | rag + root | Tambah `cache_hit: bool` ke `GenerateResponse`; isi true/false di cache path | test API + `make verify-redis` |
| P2-2 | root | `make cache-up` (profile monitoring redis) dan `make verify-redis`; script `scripts/verify_redis_cache.sh` | Redis PONG; request kedua `cache_hit=true` |
| P2-3 | rag | Cache key menyertakan fingerprint corpus/model/collection | test key berubah saat env berubah |
| P2-4 | rag | Pindahkan Qdrant/Redis sync calls ke `run_in_threadpool` | test event loop tidak blocked |
| P2-5 | rag | Corpus profile v2/v3 eksplisit (`RAG_CORPUS_PROFILE`) + validasi SHA/count per profil | startup menolak profile tidak konsisten |
| P2-6 | rag | Perbaiki `API_HOST`/`API_PORT` Docker CMD atau hapus setting yang tidak dipakai | env override benar-benar berpengaruh |
| P2-7 | arxiv | Rekonsiliasi vektor yatim setelah crash ingest | script `reconcile_orphans.py` + test |
| P2-8 | arxiv | Hapus `OLLAMA_HOST` dari compose arxiv bila provider default Groq | compose config bersih |
| P2-9 | gateway | Trace ID ke RAG/evaluator (bukan hanya arxiv) | downstream menerima header |
| P2-10 | gateway | Metrics readiness/logging; dashboard alert | panel `gateway_ready` |
| P2-11 | root | Ganti mount `init.sql` dengan migrasi versioned | `make migrate-db` idempoten |
| P2-12 | root | Bind service internal ke `127.0.0.1` secara default | `docker compose config` |
| P2-13 | eval | `scripts/check_reproducibility.py` membandingkan README dengan artefak dan `git_dirty` | test fixture gagal saat angka beda |
| P2-14 | eval | Update angka README ke artefak terbaru | `make verify` pass |
| P2-15 | root | Hapus drift `PROJECT_GOALS.md` context budget 3000 vs 6000 | grep test |
| P2-16 | arxiv | `/evaluate` mengembalikan `parse_status` tanpa mengubah tipe `faithfulness` | test kontrak |

---

## 13. P3 — backlog kualitas/keamanan

| ID | Task | Catatan |
|---|---|---|
| P3-1 | Auth API key + rate limit untuk gateway/rag/arxiv | Jangan publish port publik sebelum ini |
| P3-2 | MCP wire protocol | Saat ini HTTP/JSON; di luar scope |
| P3-3 | Deploy corpus v3 di API atau tegaskan v2 sebagai production | Butuh keputusan produk |
| P3-4 | Ganti heuristik evidence/reflection dengan NLI | Bukan blocker |
| P3-5 | Dashboard Grafana untuk `provider_error`, `not_ready`, `cache_hit` | Setelah metrik stabil |
| P3-6 | History rewrite bila key terekspos di commit lama | Hanya dengan persetujuan user |

---

## 14. Verifikasi per repo

Jalankan dari root workspace.

| Repo | Command | Expected |
|---|---|---|
| arxiv Go | `cd arxiv-research-assistant/go-backend && go test ./... -race` | pass |
| arxiv python | `cd arxiv-research-assistant/python-ml && PYTHONPATH=. ../../venv/bin/python -m pytest tests/ -q` | pass |
| rag | `cd rag-research && ../venv/bin/python -m pytest tests/ -q` | 453+ pass, 0 skip |
| eval | `cd llm-eval-framework && ../venv/bin/python -m pytest tests/ -q` | 208+ pass |
| gateway | `cd mcp-gateway && go test ./... -race` | pass |
| scanner | `bash scripts/check_secrets.sh && bash scripts/test_check_secrets.sh` | CLEAN + pass |
| compose | `docker compose --env-file .env.example config --quiet` | valid |
| smoke dry-run | `SMOKE_DRY_RUN=1 bash scripts/smoke_e2e.sh` | exit 0 tanpa jaringan |
| smoke runtime | `make smoke-e2e` (stack hidup) | PASS + request_id/logs |

**Gate akhir Fase 0:** clone bersih + `docker compose build` sukses.
**Gate akhir Fase 1:** semua test P0 hijau; `check_secrets` CLEAN.
**Gate akhir Fase 2:** `/ready` benar untuk setiap service; smoke runtime PASS.
**Gate akhir Fase 3:** dokumen tidak memuat klaim stale; `make test` hijau.

---

## 15. Peta commit yang disarankan

Urutan commit lokal (satu per task), belum push sampai review:

```text
fix(security): replace tracked Groq keys with placeholders
ci: trigger secret scan on main and test the scanner
chore: freeze remediation branches and inventory dirty trees
chore: pin submodules to pushed remediation commits
build: bake HF models instead of copying an ignored cache

fix(python-ml): normalize arxiv ids end-to-end
feat(python-ml): migrate versioned arxiv ids safely
fix(python-ml): reject zero-chunk ingestion before writes
fix(python-ml): make ingest ordering non-destructive
feat: split arxiv liveness from readiness
feat: propagate request id and log queries synchronously
fix(python-ml): evaluate with a full prompt, not a truncated context chunk
fix(python-ml): allow the local UI to call ingest
docs: make arxiv quick start shell- and port-safe

fix: classify provider failures explicitly
fix: degrade to rrf when the reranker cannot load
feat: add dependency-aware readiness to rag api
fix: start without a groq key and report not_ready
feat: add a non-destructive canonical seed script
fix: make seed-rag target the compose qdrant and refuse resets
docs: align rag env example with settings fields
fix: validate embedding and collection dimensions
fix: record the public decision in rag metrics

fix: reject incomplete checkpoints instead of crashing
fix: serialize checkpoints without losing provenance
fix: write checkpoints atomically
feat: add embedding-aware readiness endpoint
fix: distinguish evaluator unavailability from bad input

fix: make gateway readiness body-aware and honest
fix: surface rag provider errors as errors, not abstentions
fix: retry gateway postgres logging instead of disabling it forever
fix: echo and propagate X-Request-ID
fix: align gateway timeout budget with downstream steps

fix: align compose healthchecks and remove unused ollama coupling
test: verify request ids and gateway logs in smoke
fix: stop recreating mcp-gateway on groq key rotation
feat: add an idempotent database migration target
docs: align documented behavior with the remediated stack
```

---

## 16. Keputusan yang telah disetujui (2026-10-24)

1. **Provider error di gateway:** **HTTP 502 + `decision="error"`** (Task G2). Ini
   perubahan kontrak `/ask` yang eksplisit dan akan didokumentasikan.
2. **HF cache:** **download saat build** (Task 0.5), bukan commit cache biner.
3. **Corpus production:** **v2 796 tetap production**, v3 642 tetap acceptance
   in-process sampai keputusan produk (P2-5/P3-3).
4. **Auth:** **ditunda ke P3**; port internal di-bind ke loopback di P2.
5. **History rewrite:** **tidak dilakukan**. Rotasi key tetap wajib. Verifikasi
   `git grep` atas seluruh revisi menunjukkan `.env.example` hanya pernah memuat
   placeholder, jadi tidak ada key nyata di history. Task 0.1 tidak boleh menjalankan
   `git filter-repo`.
6. **Metode eksekusi:** **subagent-driven per workstream**, dengan review dan
   verifikasi oleh controller di antara task.

Jika salah satu keputusan berubah, update task terkait **sebelum** implementasi, bukan
setelah test ditulis.
