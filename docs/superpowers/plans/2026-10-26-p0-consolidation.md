# P0 Consolidation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menyatukan jalur produk ke `gateway → rag-research → llm-eval`, menghapus kontradiksi LLM-judge, memperbaiki korelasi audit, dan mendokumentasikan jalur legacy — tanpa menghentikan pilot medical writing.

**Architecture:** Tidak ada merge repo dan tidak ada rewrite. `arxiv-research-assistant` diturunkan menjadi layanan ingestion/metadata; jalur jawabannya menjadi legacy. `rag-research` menjadi satu-satunya mesin jawaban produk. `llm-eval-framework` menjadi satu-satunya evaluator produk. `mcp-gateway` tetap satu-satunya pintu masuk. Perubahan dibagi per repo agar commit atomik dan mudah di-revert.

**Tech Stack:** Go 1.25 (Fiber), Go 1.22 (Chi), Python 3.12 (FastAPI), PostgreSQL, Docker Compose, pytest, Bash.

**Spec:** `PROJECT_GOALS.md` §2/§6/§8, `STATUS.md`, `docs/ROADMAP.md`, dan hasil audit P0 sesi ini: dua stack RAG, tiga implementasi faithfulness, dua audit log, dua planner, serta kontrak MCP yang tidak sesuai perilaku.

---

## Ringkasan Keputusan

| Item | Keputusan | Alasan | Task |
|---|---|---|---|
| `arxiv/python-ml` `POST /evaluate` + `engine/evaluation/faithfulness.py` | **Hapus** | Dead code (tidak dipanggil go-backend), memakai `phi3:mini` sebagai LLM judge — melanggar prinsip “zero LLM-as-judge” | 5 |
| Jalur jawaban `arxiv /query` | **Demote** | Hanya untuk paper-scoped legacy; bukan jalur produk claim-audit | 1 |
| `rag-research/src/evaluation/ragas_evaluator.py` | **Demote** | Masih dipakai `scripts/eval_ci.py`; jadikan offline/CI-only, jangan hapus | 6 |
| `search_scientific_literature` | **Dokumentasikan** | Mengembalikan jawaban + sources, bukan daftar paper; rename ditunda ke P1 | 7 |
| `generate_audit_dossier` | **Dokumentasikan** | Mengembalikan skor faithfulness, bukan dossier; rename ditunda ke P1 | 7 |
| `gateway/cmd/server/respond.go` `applyDecision` | **Dokumentasikan** | Hanya penerjemah `REJECT/GENERATE` → `abstain/answer/error`; bukan mesin keputusan kedua | 1 |
| `query_logs` vs `gateway_query_logs` | **Dokumentasikan + perbaiki korelasi** | Dua tabel boleh ada, tapi harus bisa di-join lewat `request_id` | 3, 4 |
| Gap `chunk_id` di evidence arxiv | **Dokumentasikan** | Arxiv tidak bisa memberi `chunk_id`; tidak boleh masuk jalur produk claim-audit | 1 |
| Threshold 0.35/0.70 di spec vs 0.35/0.65 di kode | **Dokumentasikan** | Kode 0.65 sudah diuji; yang salah adalah dokumen. Jangan ubah kode | 1 |
| Status Phase 3, jumlah test, jumlah service | **Dokumentasikan** | `ROADMAP.md` dan `PROJECT_GOALS.md` saling bertentangan; `STATUS.md` yang di-generate adalah bukti | 1 |
| RAGAS module + dependencies | **Pertahankan** | `scripts/eval_ci.py` dan `tests/test_eval_ci_contract.py` bergantung padanya | 6 |
| Arxiv ingestion/metadata | **Pertahankan** | Unik; tidak ada duplikasi | — |
| Qdrant collection & Postgres table ownership | **Pertahankan** | Sudah dipisah dengan benar; tidak ada tabrakan | — |
| Rename tool MCP | **Tunda ke P1** | Butuh persetujuan kontrak; P0 cukup memperbaiki deskripsi | 7 |

---

## Global Constraints

- Jangan `make down`, `docker compose down`, `docker rm`, atau stop/kill container tanpa konfirmasi eksplisit.
- Jangan membaca atau menulis `.env`; jangan mencetak nilai secret.
- Jangan `git add -A` atau `git add .`; commit per path; jangan push.
- Commit submodule: prefix `opencode:`. Commit root: conventional (`fix:`, `docs:`, `chore:`).
- Jangan mengubah threshold `0.35/0.65` di kode. Yang diperbaiki adalah dokumen yang menulis `0.70`.
- Jangan menghapus modul atau dependency RAGAS. Modul itu masih dipakai `scripts/eval_ci.py`.
- Jangan rename tool MCP di P0. Itu perubahan kontrak dan masuk P1.
- Jangan mengubah Qdrant collection (`arxiv_chunks`, `rag_research`) atau ownership tabel Postgres.
- Pilot path (`rag-research POST /generate` + `llm-eval-framework POST /evaluate`) harus tetap hijau setelah setiap task.
- Jika working tree kotor, berhenti dan minta konfirmasi manusia; commit/stash per path, bukan global.

---

## Review Focus

- `X-Request-ID` bisa kosong atau berisi string sembarang; middleware harus memakai nilai masuk hanya jika tidak kosong, dan tetap menghasilkan UUID jika kosong.
- Penulisan `query_logs` berjalan asynchronous; test yang mengassert parameter log harus memakai channel/fake repo, bukan membaca variabel bersama tanpa sinkronisasi.
- Menghapus `routers/evaluate.py` bisa meninggalkan import di `main.py`; import basi akan membuat service gagal start, bukan gagal test.
- RAGAS masih diimpor `scripts/eval_ci.py` dan dijaga `tests/test_ragas_importable.py`; “demote” tidak boleh berarti menghapus modul atau dependency.
- README root diuji `mcp-gateway/cmd/server/readme_test.go`; link baru harus menunjuk file yang ada, dan env var baru harus benar-benar dibaca config.
- Smoke test bergantung pada stack hidup dan Groq; jika stack mati, catat SKIP sebagai lingkungan, jangan mengubah kode untuk “memperbaikinya”.

---

## Task 0: Preflight & baseline

**Files:** none.

**Interfaces:**
- Consumes: current working tree.
- Produces: baseline test log, baseline status report, branch per repo.

- [ ] **Step 1: Periksa working tree root dan submodule**

Run:
```bash
git status --short
for d in arxiv-research-assistant mcp-gateway rag-research llm-eval-framework; do
  echo "== $d =="; git -C "$d" status --short; git -C "$d" branch --show-current
done
```

Expected: daftar perubahan terlihat. Jika ada perubahan yang bukan milik task ini, **berhenti dan tanyakan** mau di-commit, di-stash, atau dibiarkan.

- [ ] **Step 2: Commit atau stash per path (hanya setelah konfirmasi)**

Jangan gunakan `git add -A`. Contoh:
```bash
git add PROJECT_GOALS.md STATUS.md docs/ROADMAP.md
git commit -m "chore: checkpoint before P0 consolidation"
```
Untuk submodule, commit di repo masing-masing dengan prefix `opencode:`.

- [ ] **Step 3: Buat branch kerja di setiap repo yang akan diubah**

Run:
```bash
git switch -c remediation/2026-10-26-p0-consolidation
git -C arxiv-research-assistant switch -c opencode/p0-consolidation
git -C mcp-gateway switch -c opencode/p0-consolidation
git -C rag-research switch -c opencode/p0-consolidation
```
Expected: branch aktif di root dan submodule. Jika branch sudah ada, gunakan branch itu.

- [ ] **Step 4: Catat baseline test dan runtime**

Run:
```bash
mkdir -p /tmp/opencode
make test > /tmp/opencode/p0-baseline-tests.log 2>&1; echo "exit=$?"
make status-report
docker ps --format '{{.Names}}\t{{.Status}}' > /tmp/opencode/p0-baseline-containers.txt
```

Expected: log baseline tersimpan; `STATUS.md` ter regenerasi; container yang sudah mati **tidak** dinyalakan.

- [ ] **Step 5: Catat commit hash awal**

Run:
```bash
git rev-parse HEAD
for d in arxiv-research-assistant mcp-gateway rag-research llm-eval-framework; do
  printf "%s " "$d"; git -C "$d" rev-parse HEAD
done
```
Expected: lima hash tercatat di catatan eksekusi.

**Done when:** working tree bersih atau perubahan yang tersisa sudah disetujui, baseline log ada, branch siap.

---

## Task 1: ADR-003 jalur produk kanonik + koreksi dokumen

**Files:**
- Create: `docs/adr/003-canonical-product-path.md`
- Modify: `README.md:15,37`
- Modify: `PROJECT_GOALS.md:196-204,248-258`
- Modify: `docs/ROADMAP.md:13,31-53,91`
- Modify: `PROJECT_CONTEXT.md:27-50`

**Interfaces:**
- Consumes: hasil audit P0; `STATUS.md`.
- Produces: satu ADR yang menjadi rujukan semua dokumen; tidak ada perubahan kode.

- [ ] **Step 1: Tulis ADR-003**

Isi wajib:
- **Context:** empat repo, dua stack RAG, tiga implementasi evaluasi, dua audit log.
- **Decision:** jalur produk `gateway → rag-research → llm-eval`; arxiv = ingestion/metadata; RAGAS = offline/CI-only.
- **Legacy:** `arxiv POST /query` hanya paper-scoped; `arxiv POST /evaluate` dihapus; evidence arxiv tidak punya `chunk_id`.
- **Audit:** `gateway_query_logs` = audit produk; `query_logs` = telemetri backend; korelasi lewat `request_id`.
- **Threshold:** `0.35/0.65` adalah default yang diuji; `0.70` di spec adalah kesalahan dokumen.
- **MCP:** `search_scientific_literature` mengembalikan jawaban + sources; `generate_audit_dossier` mengembalikan metrik, bukan laporan; rename di P1.
- **Consequences:** arxiv tidak boleh dipakai untuk claim audit; RAGAS tidak boleh masuk runtime API; setiap backend produk wajib memberi `chunk_id`.

- [ ] **Step 2: Perbaiki `PROJECT_GOALS.md`**

- Ganti zona kuning/hijau `0.35–0.70` / `≥0.70` menjadi `0.35–0.65` / `≥0.65`.
- Tambah satu baris: “Threshold 0.35/0.65 adalah default yang diuji di `tests/test_confidence_thresholds.py`.”
- Di §8 Phase 3, ganti checklist yang bertentangan dengan `STATUS.md`: HTTP MCP selesai; stdio “kode ada, belum di-track”; SSE “kode ada, perilaku streaming belum diverifikasi”; interoperabilitas eksternal belum.
- Tambah tautan ke `docs/adr/003-canonical-product-path.md`.

- [ ] **Step 3: Perbaiki `docs/ROADMAP.md`**

- Phase 3: tandai HTTP selesai; stdio/SSE sebagai “code exists, unverified” sampai bukti eksternal ada.
- Hapus angka test hardcoded `921`; ganti dengan “lihat `STATUS.md` (di-generate)”.
- Ganti “11 services” menjadi “8 core + profile monitoring + stdio adapter” atau tautkan ke `docker-compose.yml`.
- Tambah tautan ke ADR-003.

- [ ] **Step 4: Perbaiki `README.md` dan `PROJECT_CONTEXT.md`**

- README baris 15: jelaskan bahwa MCP HTTP adalah jalur produk; stdio/SSE belum diverifikasi eksternal.
- README baris 37: hapus angka `921`; arahkan ke `make status-report`.
- `PROJECT_CONTEXT.md`: samakan jumlah service dan status Phase 3 dengan ADR-003.

- [ ] **Step 5: Verifikasi link dan README contract**

Run:
```bash
cd mcp-gateway && go test ./cmd/server -run 'TestReadme' -v
cd ..
grep -R "docs/adr/003-canonical-product-path.md" README.md PROJECT_GOALS.md docs/ROADMAP.md PROJECT_CONTEXT.md
```
Expected: test README PASS; ADR dirujuk di keempat dokumen.

- [ ] **Step 6: Commit**

```bash
git add docs/adr/003-canonical-product-path.md README.md PROJECT_GOALS.md docs/ROADMAP.md PROJECT_CONTEXT.md
git commit -m "docs: define canonical product path and reconcile status"
```

**Test impact:** `TestReadme_ReferencesOnlyExistingPaths` dan `TestReadme_DocumentsOnlyRealEnvVars` harus tetap PASS. Jangan menambah env var baru ke README. `rag-research/tests/test_ci_contracts.py` tidak memeriksa dokumen, jadi tidak terpengaruh.

---

## Task 2: Propagasi `X-Request-ID` di arxiv middleware

**Files:**
- Modify: `arxiv-research-assistant/go-backend/internal/middleware/request_id.go:8-15`
- Test: `arxiv-research-assistant/go-backend/internal/middleware/request_id_test.go`

**Interfaces:**
- Consumes: incoming header `X-Request-ID`.
- Produces: `RequestID() fiber.Handler` yang mempertahankan ID masuk; jika kosong, membuat UUID; selalu menulis response header dan `c.Locals("requestID")`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan di `request_id_test.go`:
```go
func TestRequestID_HonorsIncomingHeader(t *testing.T) {
    app := fiber.New()
    app.Use(RequestID())
    app.Get("/", func(c *fiber.Ctx) error {
        return c.SendString(c.Locals("requestID").(string))
    })

    req := httptest.NewRequest("GET", "/", nil)
    req.Header.Set("X-Request-ID", "trace-abc-123")
    resp, err := app.Test(req)
    if err != nil { t.Fatal(err) }
    defer resp.Body.Close()

    body, _ := io.ReadAll(resp.Body)
    if string(body) != "trace-abc-123" {
        t.Fatalf("locals = %q, want trace-abc-123", body)
    }
    if got := resp.Header.Get("X-Request-ID"); got != "trace-abc-123" {
        t.Fatalf("response header = %q, want trace-abc-123", got)
    }
}

func TestRequestID_GeneratesWhenHeaderEmpty(t *testing.T) {
    app := fiber.New()
    app.Use(RequestID())
    app.Get("/", func(c *fiber.Ctx) error {
        return c.SendString(c.Locals("requestID").(string))
    })

    req := httptest.NewRequest("GET", "/", nil)
    req.Header.Set("X-Request-ID", "")
    resp, err := app.Test(req)
    if err != nil { t.Fatal(err) }
    defer resp.Body.Close()

    body, _ := io.ReadAll(resp.Body)
    if _, err := uuid.Parse(string(body)); err != nil {
        t.Fatalf("generated id %q is not a UUID: %v", body, err)
    }
}
```
Tambahkan import `io` dan `github.com/google/uuid` bila belum ada.

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run:
```bash
cd arxiv-research-assistant/go-backend
go test ./internal/middleware -run 'TestRequestID_HonorsIncomingHeader|TestRequestID_GeneratesWhenHeaderEmpty' -v
```
Expected: `HonorsIncomingHeader` FAIL karena middleware selalu membuat UUID baru.

- [ ] **Step 3: Implementasi minimal**

Ubah `RequestID()`:
```go
requestID := c.Get("X-Request-ID")
if requestID == "" {
    requestID = uuid.New().String()
}
```
Pertahankan `c.Set`, `c.Locals`, dan response header yang sudah ada.

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run:
```bash
cd arxiv-research-assistant/go-backend
go test ./internal/middleware -v
```
Expected: ketiga test `RequestID` PASS (termasuk test lama).

- [ ] **Step 5: Commit**

```bash
git -C arxiv-research-assistant add go-backend/internal/middleware/request_id.go go-backend/internal/middleware/request_id_test.go
git -C arxiv-research-assistant commit -m "opencode: fix(middleware): honor incoming X-Request-ID"
```

**Test impact:** hanya `internal/middleware` yang berubah. Test lama `TestRequestID_SetsResponseHeader` tetap PASS karena tidak mengirim header masuk.

---

## Task 3: Simpan `request_id` di `query_logs`

**Files:**
- Create: `arxiv-research-assistant/go-backend/migrations/004_query_logs_request_id.up.sql`
- Modify: `arxiv-research-assistant/infra/postgres/init.sql:28-40`
- Modify: `arxiv-research-assistant/go-backend/internal/repository/query_logs.go:14-38,47-66,75-86`
- Modify: `arxiv-research-assistant/go-backend/internal/api/query.go:86-100`
- Test: `arxiv-research-assistant/go-backend/internal/api/query_test.go`

**Interfaces:**
- Consumes: `requestID` dari `c.Locals("requestID")` (Task 2).
- Produces: `CreateQueryLogParams.RequestID string`; `QueryLog.RequestID *string`; kolom `query_logs.request_id`; index `idx_query_logs_request_id`.

- [ ] **Step 1: Tulis test yang gagal**

Ubah `fakeLogRepo` menjadi pointer dan tangkap parameter:
```go
type fakeLogRepo struct {
    created chan repository.CreateQueryLogParams
}

func (r *fakeLogRepo) Create(_ context.Context, p repository.CreateQueryLogParams) (*repository.QueryLog, error) {
    if r.created != nil {
        select { case r.created <- p: default: }
    }
    return &repository.QueryLog{}, nil
}
func (r *fakeLogRepo) List(_ context.Context, _ int) ([]repository.QueryLog, error) {
    return []repository.QueryLog{}, nil
}
```
Tambahkan test:
```go
func TestQueryHandler_SuccessPersistsRequestID(t *testing.T) {
    mlSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        _, _ = w.Write([]byte(`{"answer":"ok","sources":[],"retrieval_ms":1,"generation_ms":2,"model":"test-model"}`))
    }))
    defer mlSrv.Close()

    repo := &fakeLogRepo{created: make(chan repository.CreateQueryLogParams, 1)}
    app := fiber.New(fiber.Config{ErrorHandler: api.ErrorHandler})
    app.Use(fixedRequestIDMiddleware())
    app.Post("/query", api.QueryHandler(client.NewMLClient(mlSrv.URL), repo))

    req := httptest.NewRequest("POST", "/query", strings.NewReader(`{"query":"hello"}`))
    req.Header.Set("Content-Type", "application/json")
    resp, err := app.Test(req)
    if err != nil { t.Fatal(err) }
    defer resp.Body.Close()

    select {
    case p := <-repo.created:
        if p.RequestID != testRequestID {
            t.Fatalf("request_id = %q, want %q", p.RequestID, testRequestID)
        }
    case <-time.After(2 * time.Second):
        t.Fatal("query log was not written")
    }
}
```
Perbarui pemanggilan `fakeLogRepo{}` yang ada menjadi `&fakeLogRepo{}`.

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run:
```bash
cd arxiv-research-assistant/go-backend
go test ./internal/api -run TestQueryHandler_SuccessPersistsRequestID -v
```
Expected: FAIL — `CreateQueryLogParams` belum punya `RequestID`.

- [ ] **Step 3: Tambah migrasi**

`migrations/004_query_logs_request_id.up.sql`:
```sql
ALTER TABLE query_logs ADD COLUMN IF NOT EXISTS request_id TEXT;
CREATE INDEX IF NOT EXISTS idx_query_logs_request_id ON query_logs(request_id);
```
Tambahkan baris yang sama ke `infra/postgres/init.sql` setelah kolom `session_id`.

- [ ] **Step 4: Implementasi repository dan handler**

`query_logs.go`:
- Tambah `RequestID *string` ke `QueryLog` dengan tag `db:"request_id" json:"request_id,omitempty"`.
- Tambah `RequestID string` ke `CreateQueryLogParams`.
- Isi `RequestID: params.RequestID` pada struct `QueryLog`.
- INSERT menjadi:
```sql
INSERT INTO query_logs
  (id, query, answer, retrieval_ms, generation_ms, faithfulness, failure_mode, model, request_id)
VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
RETURNING created_at
```
- SELECT `List` menambahkan `request_id`.

`query.go`:
```go
RequestID: requestID,
```

- [ ] **Step 5: Jalankan test, pastikan lulus**

Run:
```bash
cd arxiv-research-assistant/go-backend
go test ./... -v
```
Expected: semua test PASS, termasuk test baru.

- [ ] **Step 6: Commit**

```bash
git -C arxiv-research-assistant add go-backend/migrations/004_query_logs_request_id.up.sql infra/postgres/init.sql go-backend/internal/repository/query_logs.go go-backend/internal/api/query.go go-backend/internal/api/query_test.go
git -C arxiv-research-assistant commit -m "opencode: fix(audit): persist request_id in query_logs"
```

**Test impact:** `internal/api/query_test.go` berubah (fake repo pointer + channel); tiga test lama tetap PASS. Tidak ada test repository DB, jadi migrasi diverifikasi lewat smoke test Task 4.

---

## Task 4: Verifikasi korelasi audit di smoke test

**Files:**
- Modify: `scripts/smoke_e2e.sh:218-232`

**Interfaces:**
- Consumes: `query_logs.request_id` (Task 3), `GATEWAY_REQUEST_ID`.
- Produces: smoke test yang membuktikan baris `query_logs` terikat ke request ID gateway, bukan ke teks query.

- [ ] **Step 1: Ubah query verifikasi**

Ganti:
```bash
"SELECT COUNT(*) FROM query_logs WHERE query = '$ARXIV_QUERY';"
```
dengan:
```bash
"SELECT COUNT(*) FROM query_logs WHERE request_id = '$GATEWAY_REQUEST_ID';"
```

- [ ] **Step 2: Tambah negative check**

Setelah pengecekan positif:
```bash
MISSING=$(run_psql "SELECT COUNT(*) FROM query_logs WHERE request_id = 'missing-$RUN_ID';")
if [ "$MISSING" != "0" ]; then
  err "query_logs request_id negative check failed: got $MISSING rows"
fi
```

- [ ] **Step 3: Verifikasi sintaks**

Run:
```bash
bash -n scripts/smoke_e2e.sh
```
Expected: tidak ada output (exit 0).

- [ ] **Step 4: Jalankan smoke jika stack sehat**

Run:
```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'ws-(postgres|qdrant|mcp-gateway|arxiv-go-backend|arxiv-python-ml|rag-api|llm-eval-framework)'
make smoke-e2e
```
Expected: PASS dan baris `query_logs` ditemukan lewat `request_id`. Jika stack tidak lengkap, catat SKIP sebagai batasan lingkungan; jangan mengubah kode untuk menutupinya.

- [ ] **Step 5: Commit**

```bash
git add scripts/smoke_e2e.sh
git commit -m "test(smoke): bind query_logs verification to request id"
```

**Test impact:** hanya script. Tidak ada unit test yang berubah.

---

## Task 5: Hapus LLM-judge arxiv yang yatim

**Files:**
- Delete: `arxiv-research-assistant/python-ml/routers/evaluate.py`
- Delete: `arxiv-research-assistant/python-ml/engine/evaluation/faithfulness.py`
- Delete: `arxiv-research-assistant/python-ml/engine/evaluation/__init__.py` jika direktori menjadi kosong
- Modify: `arxiv-research-assistant/python-ml/main.py:8,33`
- Test: `arxiv-research-assistant/python-ml/tests/test_no_llm_judge.py` (baru)

**Interfaces:**
- Consumes: tidak ada.
- Produces: service python-ml tanpa route `/evaluate`; tidak ada prompt `phi3:mini` sebagai juri.

- [ ] **Step 1: Tulis guard test yang gagal**

`tests/test_no_llm_judge.py`:
```python
from pathlib import Path
import ast

ROOT = Path(__file__).resolve().parents[1]

def test_legacy_evaluate_router_is_gone():
    assert not (ROOT / "routers" / "evaluate.py").exists()
    assert not (ROOT / "engine" / "evaluation" / "faithfulness.py").exists()

def test_main_does_not_import_evaluate_router():
    tree = ast.parse((ROOT / "main.py").read_text())
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "routers":
            imported.update(alias.name for alias in node.names)
    assert "evaluate" not in imported
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

Run:
```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. python -m pytest tests/test_no_llm_judge.py -v
```
Expected: FAIL karena file dan import masih ada.

- [ ] **Step 3: Hapus file dan import**

- Hapus `routers/evaluate.py`.
- Hapus `engine/evaluation/faithfulness.py`; hapus `engine/evaluation/__init__.py` jika direktori kosong.
- Di `main.py`, ubah import menjadi `from routers import chunk, embed, ingest, papers, query`.
- Hapus `app.include_router(evaluate.router)`.

- [ ] **Step 4: Verifikasi tidak ada referensi tersisa**

Run:
```bash
cd arxiv-research-assistant
grep -R "evaluate_faithfulness\|routers.evaluate\|routers import.*evaluate" . --include='*.py' --include='*.md' || echo CLEAN
```
Expected: `CLEAN` (atau hanya dokumentasi legacy yang sudah ditandai).

- [ ] **Step 5: Jalankan test python-ml**

Run:
```bash
cd arxiv-research-assistant/python-ml
PYTHONPATH=. python -m pytest tests/ -v
```
Expected: semua test PASS; jumlah naik dari 45 menjadi 47 (dua guard test baru).

- [ ] **Step 6: Commit**

```bash
git -C arxiv-research-assistant add -u python-ml/main.py python-ml/routers/evaluate.py python-ml/engine/evaluation/faithfulness.py python-ml/tests/test_no_llm_judge.py
git -C arxiv-research-assistant commit -m "opencode: refactor(eval): remove orphaned phi3 faithfulness judge"
```

**Test impact:** tidak ada test lama yang mengimpor `routers.evaluate`; `make test-arxiv-ml` hanya bertambah dua guard test. Jika `README` arxiv menyebut `/evaluate`, perbarui di commit yang sama.

---

## Task 6: Demote RAGAS menjadi offline/CI-only

**Files:**
- Modify: `rag-research/src/evaluation/ragas_evaluator.py:1-2`
- Modify: `rag-research/README.md:459`
- Test: `rag-research/tests/test_ragas_not_in_product_path.py` (baru)

**Interfaces:**
- Consumes: `scripts/eval_ci.py` yang tetap memakai `RAGASEvaluator`.
- Produces: docstring “OFFLINE/CI ONLY”; guard test yang memastikan `src/api/main.py` tidak mengimpor RAGAS.

- [ ] **Step 1: Tulis test docstring yang gagal**

`tests/test_ragas_not_in_product_path.py`:
```python
from pathlib import Path
import ast

ROOT = Path(__file__).resolve().parents[1]

def test_ragas_module_is_marked_offline_only():
    src = (ROOT / "src" / "evaluation" / "ragas_evaluator.py").read_text()
    assert "OFFLINE/CI ONLY" in src

def test_api_main_does_not_import_ragas():
    tree = ast.parse((ROOT / "src" / "api" / "main.py").read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            assert "ragas" not in node.module
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert "ragas" not in alias.name

def test_eval_ci_still_uses_ragas():
    assert "RAGASEvaluator" in (ROOT / "scripts" / "eval_ci.py").read_text()
```

- [ ] **Step 2: Jalankan test, pastikan satu gagal**

Run:
```bash
cd rag-research
python -m pytest tests/test_ragas_not_in_product_path.py -v
```
Expected: `test_ragas_module_is_marked_offline_only` FAIL; dua lainnya PASS (karakterisasi).

- [ ] **Step 3: Tambah docstring dan perbarui README**

Di baris pertama `ragas_evaluator.py`:
```python
"""OFFLINE/CI ONLY — not imported by the product API; used by scripts/eval_ci.py."""
```
Di `README.md` baris 459, ubah komentar menjadi `# Offline/CI only — not part of the product path`.

- [ ] **Step 4: Jalankan test, pastikan lulus**

Run:
```bash
cd rag-research
python -m pytest tests/test_ragas_not_in_product_path.py tests/test_ragas_importable.py tests/test_ci_contracts.py -v
```
Expected: semua PASS. RAGAS tetap bisa diimpor untuk `scripts/eval_ci.py`.

- [ ] **Step 5: Jalankan suite rag penuh**

Run:
```bash
make test-rag
```
Expected: semua PASS; jumlah naik dari 492 menjadi 495 (tiga guard test baru).

- [ ] **Step 6: Commit**

```bash
git -C rag-research add src/evaluation/ragas_evaluator.py README.md tests/test_ragas_not_in_product_path.py
git -C rag-research commit -m "opencode: docs(eval): mark RAGAS as offline/CI-only"
```

**Test impact:** `test_ragas_importable.py` dan `test_ci_contracts.py` tetap PASS. `test_embedding_model_single_source.py` tetap PASS karena modul tidak dipindahkan dan tetap menurunkan konstanta dari `settings.embed_model`.

---

## Task 7: Perbaiki deskripsi tool MCP (tanpa rename)

**Files:**
- Modify: `mcp-gateway/internal/mcp/tools.go:16-17,96-97`
- Modify: `scripts/mcp_e2e_smoke_test.sh:90-136`
- Modify: `mcp-gateway/README.md` (bagian tools, jika ada)

**Interfaces:**
- Consumes: registry tool `search_arxiv`, `research_rag`, `evaluate_answer`.
- Produces: deskripsi `tools/list` yang jujur; nama tool tidak berubah.

- [ ] **Step 1: Ubah deskripsi**

`search_scientific_literature`:
```go
Description: "Answer a scientific question using arXiv papers. Returns a generated answer and source passages; it does not return a ranked paper list. Use verify_factual_claim for claim-level evidence.",
```
`generate_audit_dossier`:
```go
Description: "Evaluate an answer against evidence and return faithfulness metrics (score, failure mode, claim counts). It does not generate a report.",
```
Jangan ubah `Name`, `InputSchema`, atau handler.

- [ ] **Step 2: Perbarui label smoke test**

Di `scripts/mcp_e2e_smoke_test.sh`, ubah label pada baris 90-136 agar menyebut “answer + sources” dan “faithfulness metrics”; nama tool tetap.

- [ ] **Step 3: Verifikasi build dan test**

Run:
```bash
cd mcp-gateway
go test ./... -race
bash -n ../scripts/mcp_e2e_smoke_test.sh
```
Expected: semua test PASS; script valid.

- [ ] **Step 4: Verifikasi output `tools/list` jika stack hidup**

Run:
```bash
curl -s -X POST http://localhost:8090/mcp \
  -H 'Content-Type: application/json' \
  -H 'Mcp-Method: tools/list' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | python3 -m json.tool | grep -A2 'search_scientific_literature'
```
Expected: deskripsi baru terlihat. Jika gateway mati, catat SKIP.

- [ ] **Step 5: Commit**

```bash
git -C mcp-gateway add internal/mcp/tools.go README.md
git -C mcp-gateway commit -m "opencode: docs(mcp): describe tool behavior accurately"
git add scripts/mcp_e2e_smoke_test.sh
git commit -m "docs(mcp): align smoke labels with tool behavior"
```

**Test impact:** tidak ada Go test yang mengassert string deskripsi (dicek dengan `grep -R "Search arXiv for scientific papers" mcp-gateway --include='*_test.go'`). `make test-mcp` tetap 156 test. Smoke script hanya berubah label.

---

## Dampak ke Test yang Ada

| Task | Test/berkas terdampak | Tindakan | Baseline |
|---|---|---|---|
| 1 | `mcp-gateway/cmd/server/readme_test.go` | Link baru harus ada; env var baru tidak boleh | PASS |
| 2 | `internal/middleware/request_id_test.go` | +2 test; test lama tetap | 3 test |
| 3 | `internal/api/query_test.go` | Fake repo jadi pointer + channel; +1 test | 15 test Go |
| 4 | `scripts/smoke_e2e.sh` | SQL verifikasi diganti ke `request_id`; +negative check | Manual |
| 5 | `arxiv python-ml/tests` | +2 guard test; tidak ada test lama yang dihapus | 45 → 47 |
| 6 | `rag-research/tests` | +3 guard test; RAGAS tetap dapat diimpor | 492 → 495 |
| 7 | `mcp-gateway` tests | Tidak ada assertion deskripsi; smoke label berubah | 156 |
| 8 (P1) | — | CI belum termasuk P0 | — |

**Catatan:** angka test di dokumen (`921`, `926`, `492`) tidak konsisten. Gunakan output `make test` di Task 0 sebagai baseline, bukan angka dokumen.

---

## Definition of Done

- [ ] `make test` PASS; jumlah test sesuai baseline + guard test baru.
- [ ] `make smoke-e2e` PASS (atau SKIP lingkungan tercatat) dan `query_logs` diverifikasi lewat `request_id`.
- [ ] `grep -R "evaluate_faithfulness\|routers.evaluate" arxiv-research-assistant` bersih.
- [ ] `grep -R "ragas" rag-research/src/api/main.py` bersih; `scripts/eval_ci.py` masih bisa mengimpor RAGAS.
- [ ] `tools/list` MCP memuat deskripsi baru; nama tool tidak berubah.
- [ ] `docs/adr/003-canonical-product-path.md` ada dan dirujuk README, PROJECT_GOALS, ROADMAP, PROJECT_CONTEXT.
- [ ] Pilot path tetap bekerja: `rag /health`, `llm-eval /ready`, satu `/generate` + `/evaluate` manual.
- [ ] Tidak ada `.env` yang dibaca/ditulis; tidak ada container yang dihentikan; tidak ada push.

---

## Rollback

- Setiap task adalah commit terpisah; revert dengan urutan terbalik.
- Migrasi `004` bersifat aditif (`ADD COLUMN IF NOT EXISTS`), jadi rollback aman tanpa kehilangan data.
- Penghapusan `routers/evaluate.py` reversibel dari git; tidak ada pemanggil eksternal.
- Perubahan dokumen reversibel; ADR-003 dapat diganti tanpa menyentuh kode.

---

## P1 Follow-up (di luar rencana ini)

1. Rename `search_scientific_literature` → `ask_scientific_literature` dan `generate_audit_dossier` → `evaluate_answer_faithfulness`, lalu perbarui klien/smoke.
2. Tegakkan `chunk_id` wajib untuk semua evidence di jalur produk (gateway validation + test fixture).
3. Tambah CI test workflow (Go + Python) di `.github/workflows/test.yml`.
4. Satukan dataset evaluasi dan skema `should_abstain` antara `rag-research` dan `llm-eval-framework`.
5. Pertimbangkan merge deployable setelah pilot: `gateway` + `rag-api` + `eval` tetap tiga proses, arxiv ingestion menjadi worker.
