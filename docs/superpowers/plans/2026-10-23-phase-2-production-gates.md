# Fase 2 — Production Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menutup seluruh gate Fase 2 yang masih terbuka — kebocoran secret, verifikasi runtime Redis cache, readiness per kapabilitas, smoke run yang membuktikan baris log baru, monitoring 5 target + Grafana, dan build bersih — sehingga Fase 3 (MCP) punya baseline yang dapat dipercaya.

**Architecture:** Perubahan dibagi menjadi tiga lapisan: (1) kontrak respons `rag-research` agar cache hit dapat diamati, (2) kesiapan gateway yang memisahkan backend jawaban wajib dari evaluator opsional, dan (3) skrip verifikasi operasional yang mengikat hasil ke run ID unik. Tidak ada perubahan pada kontrak publik `/ask`, tidak ada MCP transport di fase ini, dan tidak ada klaim kualitas yang belum diukur.

**Tech Stack:** Go 1.22 + Chi (mcp-gateway), Python 3.12 + FastAPI (rag-research), Python 3.11 + FastAPI (llm-eval-framework), Redis 7, Docker Compose, Prometheus, Grafana, Bash.

**Spec:** `PROJECT_GOALS.md` §8 Fase 2 dan §9 Production Readiness Checklist; gate operasional di `mcp-gateway/IMPLEMENTATION_TODO.md` P0; batas bukti di `PROJECT_CONTEXT.md` §2–§3.

## Global Constraints

- **Secret hanya boleh hidup di `.env` root yang git-ignored.** Semua `*.env.example` yang tracked wajib memakai placeholder; `make check-secrets` harus exit 0. Key baru dibaca dengan `read -s`, tidak ditulis di command line, shell history, issue, atau commit.
- **Jangan pernah memakai `git add -A` atau `git add .`** saat commit. Working tree saat ini memuat perubahan pengguna yang tidak terkait (`rag-research/results/metrics/phase1_smoke.json`, `.env.example`, dan pointer submodule). Stage path eksplisit saja.
- **Gateway tetap HTTP/JSON pada fase ini.** Jangan menulis klaim kompatibilitas MCP di README atau dokumen sampai transport MCP diimplementasikan dan diuji.
- **Satu request = satu backend.** Jangan menggabungkan evidence dari `arxiv` dan `research_rag`.
- **Evaluator bersifat opsional untuk menjawab.** Kegagalan evaluator tidak boleh mengubah jawaban valid menjadi error atau skor 0; gunakan `evaluation_status: "unavailable"`.
- **Redis cache bersifat opt-in pada Fase 2.** Default `.env.example` tetap `REDIS_ENABLED=false`; jalur aktif hanya lewat `make cache-up`. Kegagalan Redis saat runtime tidak boleh menggagalkan `/generate`.
- **Jangan menghapus volume.** Verifikasi lifecycle hanya memakai `docker compose down` tanpa `-v`; data PostgreSQL/Qdrant harus terbukti persisten.
- **Jangan menyentuh model Ollama berat.** Rute default tetap Groq; Ollama hanya dipakai evaluator embedding dan demo lokal.
- **Submodule adalah repo git terpisah.** Commit di submodule lebih dulu, lalu bump pointer di root. Jangan mengubah commit submodule yang tidak terkait.
- **Angka kualitas (faithfulness, abstention accuracy, recall) tidak boleh diklaim dari unit test atau smoke.** Fase 2 hanya membuktikan gate operasional.

## Review Focus

Lima kondisi yang paling mungkin membuat Fase 2 terlihat lulus padahal belum:

1. **Redis mati saat `REDIS_ENABLED=true`** — `/generate` harus tetap menjawab lewat jalur normal, bukan 500. Cache dinonaktifkan dengan peringatan.
2. **Cache hit berisi abstention** (`decision=REJECT`, `failure_type!=none`, atau `generator_status=INSUFFICIENT_CONTEXT`) — entri lama tidak boleh disajikan; harus dihapus dan pipeline dijalankan ulang.
3. **Evaluator/Ollama mati** — `/ready` harus `degraded` (HTTP 200) selama salah satu backend jawaban hidup, dan `/ask` tetap menjawab dengan `evaluation_status=unavailable` tanpa key `score`.
4. **Satu backend jawaban mati** — `/ready` tetap 200 `degraded` dengan `capabilities.answers=true`; request ke backend yang hidup sukses, request ke backend yang mati menghasilkan 502, bukan abstain palsu.
5. **Baris log lama/duplikat** — smoke harus membuktikan baris baru lewat `request_id` unik dan query unik; hitungan baris lama tidak boleh meloloskan verifikasi.

Setiap baris di atas punya test yang ditambahkan ke task pemilik kodenya.

## Roadmap Setelah Fase 2 (ringkas, bukan rencana detail)

### Fase 3 — MCP wire protocol

- **Prasyarat:** seluruh task Fase 2 di bawah PASS dan tercatat di `docs/acceptance/phase-2-verification.md`.
- Gunakan **MCP spec 2026-07-28**: transport yang relevan adalah **stdio** dan **Streamable HTTP**. SSE adalah transport legacy; jangan mengklaim SSE sebagai target baru.
- Official Go SDK `github.com/modelcontextprotocol/go-sdk` v1.8.0 membutuhkan **Go 1.25**; gateway saat ini Go 1.22. Rencana Fase 3 harus mencakup upgrade toolchain dan Dockerfile.
- Tambah endpoint `/mcp` (Streamable HTTP) dan entrypoint `cmd/mcp-stdio`; pertahankan `/ask`, `/plan`, `/tool` agar klien HTTP lama tidak rusak.
- Tools yang didaftarkan: `search_scientific_literature`, `verify_factual_claim`, `generate_audit_dossier`.
- Gate Fase 3: conformance test dengan SDK client, uji interoperabilitas Claude Desktop/Cursor, auth + rate limit untuk `/mcp`, dan bukti bahwa setiap tool mempertahankan provenance backend/evidence.
- Rencana detail ditulis terpisah: `docs/superpowers/plans/<tanggal>-phase-3-mcp.md`.

### Fase 4 — Claim Audit UI

- UI audit dua sisi (klaim vs evidence) dan ekspor dossier Markdown/PDF.
- Fase 4 bergantung pada kontrak claim-level yang belum ada di `/ask`; `generate_audit_dossier` dari Fase 3 adalah kandidat sumber datanya.
- Jangan mengeklaim span-level attribution sampai pemetaan klaim→chunk diimplementasikan dan diuji.
- Rencana detail ditulis terpisah setelah kontrak claim-level disepakati.

---

## Task 1: Remediasi dan Rotasi Secret

**Files:**
- Modify: `.env.example` (root)
- Modify: `arxiv-research-assistant/.env.example`
- Modify: `scripts/check_secrets.sh`
- Verify: `scripts/check_secrets.sh`

**Interfaces:**
- Consumes: tidak ada.
- Produces: kontrak env `GROQ_API_KEY=gsk_your_actual_key_here` di semua `*.env.example` tracked; `REDIS_ENABLED=false`, `REDIS_URL=redis://redis:6379/0`, `GATEWAY_LISTEN_ADDRESS=:8090` kembali terdokumentasi di root `.env.example`.

- [ ] **Step 1: Cabut key yang terpapar**

Key yang sekarang ada di `.env.example` root dan `arxiv-research-assistant/.env.example` harus dianggap kompromi. Buka Groq Console, revoke key tersebut, lalu buat key baru. Catat waktu revoke di catatan eksekusi. Jangan menyalin key ke dokumen, issue, atau commit.

Sebelum menghapus, cek apakah key pernah masuk history tanpa mencetak nilai penuh:

```bash
ROOT_PREFIX=$(grep '^GROQ_API_KEY=' .env.example | cut -d= -f2 | cut -c1-16)
ARXIV_PREFIX=$(grep '^GROQ_API_KEY=' arxiv-research-assistant/.env.example | cut -d= -f2 | cut -c1-16)
git log --oneline -S "$ROOT_PREFIX" -- .env.example
git -C arxiv-research-assistant log --oneline -S "$ARXIV_PREFIX" -- .env.example
```

Jika ada commit yang memuat key, revoke tetap wajib; bersihkan history sebelum push ke remote publik.

- [ ] **Step 2: Kembalikan placeholder di kedua file**

Di `.env.example` root, baris gateway harus kembali menjadi:

```dotenv
# ── Gateway ────────────────────────────────────────────────────────────
GATEWAY_LISTEN_ADDRESS=:8090
GROQ_API_KEY=gsk_your_actual_key_here
```

Di `arxiv-research-assistant/.env.example`, baris yang sama harus menjadi:

```dotenv
GROQ_API_KEY=gsk_your_actual_key_here
```

Jangan mengubah nilai non-secret lain di file tersebut.

- [ ] **Step 3: Dokumentasikan Redis opt-in di root `.env.example`**

Tambahkan kembali blok berikut setelah bagian `rag-research`:

```dotenv
# Optional response cache. Redis dijalankan oleh profile monitoring:
#   make cache-up
# Default false agar `make up` tidak bergantung pada Redis.
REDIS_ENABLED=false
REDIS_URL=redis://redis:6379/0
```

- [ ] **Step 4: Perbaiki scanner, lalu jalankan dan pastikan bersih**

`scripts/check_secrets.sh` punya empat bug yang membuat gate ini tidak bisa dipercaya:

1. **False negative submodule:** `git -C "$r" ls-files` mengembalikan path relatif submodule, lalu `xargs grep` berjalan dari root, sehingga isi submodule tidak pernah benar-benar dipindai.
2. **False positive submodule:** bila ada path bernama sama di root (mis. `.env.example`), hasilnya dilaporkan sebagai milik submodule dengan isi file root.
3. **False negative `leak=1`:** `leak=1` di dalam `printf ... | while ...` berjalan di subshell dan hilang; kebocoran di file non-`.env.example` bisa dicetak tetapi tetap `exit 0`.
4. **Submodule standar dilewati:** submodule hasil clone punya `.git` berupa **file** (`gitdir: ...`), bukan directory; `[ -d "$r/.git" ]` membuat seluruh submodule dilewati.

Ganti seluruh loop bagian `[B]` dengan `git grep` yang selalu dijalankan di repo yang benar:

```bash
for r in "${repos[@]}"; do
  if [ "$r" != "." ] && [ ! -e "$r/.git" ]; then
    continue
  fi
  found=$(git -C "$r" grep -lE "$pat" -- . 2>/dev/null || true)
  if [ -n "$found" ]; then
    leak=1
    while IFS= read -r f; do
      echo "   ❌ $r/$f"
      git -C "$r" grep -nE "$pat" -- "$f" 2>/dev/null |
        sed 's/gsk_[A-Za-z0-9]\{6\}[A-Za-z0-9]*/gsk_****REDACTED****/g' | head -3
    done <<< "$found"
  fi
done
```

`leak=1` harus di luar loop, dan `while` memakai here-string (bukan pipeline) agar berjalan di shell yang sama. `git grep` hanya memindai file tracked, sesuai batas scanner. Ganti juga `[ -d "$r/.git" ]` menjadi `[ -e "$r/.git" ]` di bagian `[C]` agar `*.env.example` submodule tetap diperiksa pada clone standar.

Verifikasi perbaikan dengan repo sementara yang `.git`-nya berupa file (jangan membuat file palsu di repo utama):

```bash
TMP=$(mktemp -d)
mkdir "$TMP/repo"
git init -q --separate-git-dir="$TMP/repo.git" "$TMP/repo"
printf 'gsk_%s\n' "$(printf 'A%.0s' {1..32})" > "$TMP/repo/leak.txt"
git -C "$TMP/repo" add leak.txt
sed 's/^repos=(.*/repos=("repo")/' scripts/check_secrets.sh > "$TMP/check.sh"
( cd "$TMP" && bash check.sh ) >/dev/null 2>&1
rc=$?
rm -rf "$TMP"
[ "$rc" -eq 1 ] || { echo "scanner gagal mendeteksi leak di submodule"; exit 1; }
```

Lalu jalankan:

```bash
make check-secrets
```

Expected:

```text
✅ CLEAN — tidak ada rahasia di file yang di-track
```

Exit code harus `0`. Jika masih gagal, cari file yang dilaporkan dan ulangi Step 2; jangan menambahkan pengecualian ke scanner.

- [ ] **Step 5: Rotasi key ke `.env` dan container**

Pastikan stack hidup lebih dulu (`make up`). Jangan menulis key baru langsung di command line karena akan tersimpan di shell history. Bacalah secara tersembunyi, lalu validasi tanpa menulis apa pun:

```bash
read -rsp "Groq API key baru: " GROQ_KEY; echo
KEY="$GROQ_KEY" make rotate-key DRY=1
```

Expected: `✅ key valid (HTTP 200)` dan `DRY-RUN`.

Kemudian jalankan rotasi penuh:

```bash
KEY="$GROQ_KEY" make rotate-key
unset GROQ_KEY
```

Expected: `.env` ditulis ulang, tiga service (`ws-mcp-gateway`, `ws-rag-api`, `ws-arxiv-python-ml`) direcreate, dan langkah konfirmasi menampilkan prefix ter-mask dengan panjang yang sama.

- [ ] **Step 6: Commit eksplisit**

Di submodule ArXiv:

```bash
cd arxiv-research-assistant
git add .env.example
git commit -m "chore(security): restore env example placeholder"
cd ..
```

Di root:

```bash
git add .env.example scripts/check_secrets.sh arxiv-research-assistant
git commit -m "chore(security): remove leaked key, fix scanner, document redis env"
```

Jangan stage `rag-research` atau file hasil evaluasi pada langkah ini.

---

## Task 2: Kontrak Cache Hit dan Ketahanan Cache di `rag-research`

**Files:**
- Modify: `rag-research/src/api/main.py`
- Test: `rag-research/tests/test_api_phase1.py`
- Test: `rag-research/tests/test_cache.py` (create)

**Interfaces:**
- Consumes: `RedisCache` di `rag-research/src/api/cache.py`; `GenerateResponse` di `main.py`.
- Produces:
  - `GenerateResponse.cache_hit: bool = False` — field publik JSON yang bernilai `true` hanya saat respons disajikan dari Redis.
  - `RedisCache.get(key: str) -> Any | None`, `.set(key: str, value: Any, ttl_seconds: int = 300) -> None`, `.delete(key: str) -> None` tetap sama; test baru tidak mengubah signature.
  - `RAG_CACHE` tidak ditambahkan pada task ini; observabilitas runtime memakai field `cache_hit` dan inspeksi Redis key.

- [ ] **Step 1: Tulis test yang gagal untuk kontrak respons**

Tambahkan ke `rag-research/tests/test_api_phase1.py`:

```python
def test_cache_hit_response_exposes_cache_hit(monkeypatch):
    # Reuse the fixture setup from test_cache_hit_records_metrics_and_query_log.
    # The cached payload is a successful GenerateResponse model_dump().
    response = asyncio.run(main.generate_answer(main.GenerateRequest(query="test query")))

    assert response.cache_hit is True
    assert response.latency_retrieval_ms == 0.0
    assert response.latency_generation_ms == 0.0


def test_cache_miss_response_exposes_cache_hit_false(monkeypatch):
    # FakeCache returns None; retriever/generator/confidence fakes return a normal answer.
    response = asyncio.run(main.generate_answer(main.GenerateRequest(query="test query")))

    assert response.cache_hit is False
```

Tambahkan test abstention yang tidak boleh disajikan dari cache:

```python
def test_cached_abstention_is_not_served(monkeypatch):
    cached = main.GenerateResponse(
        query="test query",
        answer="INSUFFICIENT_CONTEXT",
        retrieved_chunks=[],
        retrieval_method="cache",
        latency_retrieval_ms=1.0,
        latency_generation_ms=1.0,
        latency_total_ms=2.0,
        model="test-model",
        confidence=0.0,
        decision="REJECT",
        failure_type="low_confidence",
        generator_status="INSUFFICIENT_CONTEXT",
    ).model_dump()

    fake_cache = FakeCache(cached)
    retriever = FakeRetriever([_single_chunk()])
    monkeypatch.setattr(main, "cache", fake_cache)
    monkeypatch.setattr(main, "retriever", retriever)
    monkeypatch.setattr(main, "generator", FakeGenerator())
    monkeypatch.setattr(
        main,
        "confidence_engine",
        FakeConfidenceEngine([
            {"confidence_score": 0.8, "decision": "GENERATE", "signals": {}},
        ]),
    )
    monkeypatch.setattr(main, "run_in_threadpool", _run_inline)

    asyncio.run(main.generate_answer(main.GenerateRequest(query="test query")))

    assert fake_cache.delete_calls == ["rag:gen:test query:None:False"]
    assert retriever.calls != []
```

Jika setup fake yang ada membutuhkan penyesuaian, ikuti pola `test_cache_hit_records_metrics_and_query_log`; jangan mengubah helper produksi.

- [ ] **Step 2: Jalankan test dan pastikan gagal**

Run: `cd rag-research && ../venv/bin/python -m pytest tests/test_api_phase1.py -k 'cache' -v`

Expected: test baru gagal karena `GenerateResponse` belum punya atribut `cache_hit` (Pydantic mengabaikan field ekstra), dan test abstention belum menghapus cache.

- [ ] **Step 3: Implementasikan field `cache_hit`**

Di `rag-research/src/api/main.py`, tambahkan field ke `GenerateResponse`:

```python
class GenerateResponse(BaseModel):
    # ... field yang sudah ada ...
    cache_hit: bool = False
```

Lalu set field itu pada respons yang benar-benar dikembalikan dari cabang cache hit. Saat ini cabang tersebut memakai `model_copy`; tambahkan `"cache_hit": True` ke `update`:

```python
cached_result = cached_result.model_copy(
    update={
        "latency_retrieval_ms": 0.0,
        "latency_generation_ms": 0.0,
        "latency_total_ms": cache_latency_ms,
        "cache_hit": True,
    }
)
```

`cache_hit=True` yang sudah ada di `_log_query_event` hanya mengisi log, bukan respons HTTP. Jangan mengandalkan nilai itu untuk field publik.

- [ ] **Step 4: Tulis test RedisCache yang gagal**

Buat `rag-research/tests/test_cache.py`:

```python
from src.api import cache as cache_module


class FakeRedis:
    def __init__(self):
        self.store = {}

    def ping(self):
        return True

    def get(self, key):
        return self.store.get(key)

    def setex(self, key, ttl, value):
        self.store[key] = value.encode("utf-8")

    def delete(self, key):
        self.store.pop(key, None)


def test_redis_cache_round_trip(monkeypatch):
    fake = FakeRedis()
    monkeypatch.setenv("REDIS_ENABLED", "true")
    monkeypatch.setattr(cache_module.redis.Redis, "from_url", lambda *a, **k: fake)

    c = cache_module.RedisCache()
    c.set("k", {"answer": "ok"}, ttl_seconds=60)

    assert c.get("k") == {"answer": "ok"}
    c.delete("k")
    assert c.get("k") is None


def test_redis_connection_failure_disables_cache(monkeypatch):
    monkeypatch.setenv("REDIS_ENABLED", "true")

    def fail(*args, **kwargs):
        raise cache_module.redis.exceptions.ConnectionError("redis down")

    monkeypatch.setattr(cache_module.redis.Redis, "from_url", fail)
    c = cache_module.RedisCache()

    assert c.client is None
    assert c.get("k") is None
    c.set("k", {"answer": "ok"})  # must not raise


def test_redis_invalid_json_is_a_miss(monkeypatch):
    fake = FakeRedis()
    fake.store["bad"] = b"not-json"
    monkeypatch.setenv("REDIS_ENABLED", "true")
    monkeypatch.setattr(cache_module.redis.Redis, "from_url", lambda *a, **k: fake)

    assert cache_module.RedisCache().get("bad") is None
```

- [ ] **Step 5: Jalankan test RedisCache sebagai regression lock**

Run: `cd rag-research && ../venv/bin/python -m pytest tests/test_cache.py -v`

Expected: PASS. Test ini mengunci perilaku `RedisCache` yang sudah ada (round-trip, fallback saat koneksi gagal, JSON rusak). Jika gagal karena fake client tidak kompatibel, perbaiki setup test dengan monkeypatch yang sama seperti produksi; jangan mengubah perilaku produksi hanya untuk test.

- [ ] **Step 6: Jalankan seluruh test terkait**

Run: `cd rag-research && ../venv/bin/python -m pytest tests/test_api_phase1.py tests/test_cache.py -v`

Expected: PASS. Test abstention membuktikan cache tidak menyajikan `REJECT`/`INSUFFICIENT_CONTEXT`.

- [ ] **Step 7: Commit di submodule dan root**

```bash
cd rag-research
git add src/api/main.py tests/test_api_phase1.py tests/test_cache.py
git commit -m "feat(api): expose cache_hit and lock cache fallback"
cd ..
git add rag-research
git commit -m "chore(rag): bump cache contract"
```

Jangan stage `rag-research/results/metrics/phase1_smoke.json`.

---

## Task 3: Verifikasi Runtime Redis Cache

**Files:**
- Create: `scripts/verify_redis_cache.sh`
- Modify: `Makefile`
- Modify: `.env.example` (root) — hanya komentar/petunjuk, default tetap `false`
- Modify: `README.md` — bagian monitoring/cache

**Interfaces:**
- Consumes: `GenerateResponse.cache_hit` dari Task 2; Redis container `ws-redis`; `ws-rag-api`.
- Produces:
  - Target Make `cache-up` — menyalakan Redis (`--profile monitoring`) dan recreate `rag-api` dengan `REDIS_ENABLED=true`.
  - Target Make `verify-redis` — menjalankan `scripts/verify_redis_cache.sh`.
  - Env kontrak: `RAG_URL` (default `http://localhost:8000`), `REDIS_CONTAINER` (default `ws-redis`), `SMOKE_RUN_ID` (opsional).

- [ ] **Step 1: Tulis skrip verifikasi yang gagal sebelum cache aktif**

Buat `scripts/verify_redis_cache.sh` dengan alur:

```bash
#!/usr/bin/env bash
set -euo pipefail

RAG_URL="${RAG_URL:-http://localhost:8000}"
REDIS_CONTAINER="${REDIS_CONTAINER:-ws-redis}"
RUN_ID="${SMOKE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
QUERY="How does RAG combine retrieval with generation? [cache-verify:$RUN_ID]"

fail() { echo "❌ verify-redis: $*" >&2; exit 1; }
```

Assertions yang wajib ada:

1. `docker exec "$REDIS_CONTAINER" redis-cli ping` menghasilkan `PONG`.
2. `docker exec ws-rag-api printenv REDIS_ENABLED` menghasilkan `true`; jika tidak, gagal dengan petunjuk `make cache-up`.
3. Tunggu `ws-rag-api` berstatus `healthy` (maksimum 300 detik) sebelum memanggil `/generate`.
4. Panggilan pertama ke `POST /generate` dengan body `{"query":"$QUERY","top_k":3}`: `decision` bukan `REJECT`, `failure_type == "none"`, dan `cache_hit == false`.
5. Panggilan kedua dengan body identik: `cache_hit == true`, `answer` sama, `latency_retrieval_ms == 0`, `latency_generation_ms == 0`.
6. Key Redis `rag:gen:*` yang memuat `$QUERY` ada; `redis-cli ttl <key>` > 0.
7. Hapus key tersebut di akhir agar run berikutnya tidak terpengaruh.

Gunakan `jq` untuk parsing JSON dan `docker inspect -f '{{.State.Health.Status}}' ws-rag-api` untuk menunggu health. Jika panggilan pertama abstain, keluar dengan pesan `INCONCLUSIVE: query abstained; pilih query korpus yang answerable`; jangan dianggap PASS.

- [ ] **Step 2: Jalankan skrip dan pastikan gagal sebelum `cache-up`**

Run: `bash scripts/verify_redis_cache.sh`

Expected: FAIL dengan pesan `REDIS_ENABLED` bukan `true` atau Redis tidak berjalan. Ini membuktikan skrip tidak memberi lulus palsu.

- [ ] **Step 3: Tambahkan target Make**

Di `Makefile`:

```make
cache-up:  ## Start Redis and recreate rag-api with response cache enabled
	$(COMPOSE) --env-file $(ENV_FILE) --profile monitoring up -d redis
	REDIS_ENABLED=true $(COMPOSE) --env-file $(ENV_FILE) up -d --no-deps --force-recreate rag-api

verify-redis: cache-up  ## Verify Redis cache hit path end-to-end
	bash scripts/verify_redis_cache.sh
```

Tambahkan `cache-up` dan `verify-redis` ke `.PHONY`. Jangan mengubah target `monitoring-up`/`monitoring-down` pada task ini.

- [ ] **Step 4: Jalankan verifikasi penuh**

Run:

```bash
docker compose --env-file .env build rag-api
make up
make verify-redis
```

Expected: `verify-redis` PASS; output menampilkan `cache_hit=false` pada panggilan pertama, `cache_hit=true` pada panggilan kedua, dan TTL > 0. Build eksplisit diperlukan karena `cache_hit` baru ada di image `rag-api` setelah Task 2.

- [ ] **Step 5: Dokumentasikan urutan dan batasnya**

Di `README.md`, tambahkan:

```bash
make cache-up       # Redis + rag-api dengan REDIS_ENABLED=true
make verify-redis   # bukti cache hit + TTL
```

Jelaskan bahwa Redis tetap opt-in, `make down` mematikan semuanya, dan `make monitoring-down` akan mematikan Redis sehingga cache kembali disabled secara graceful. Karena `.env` default `false`, `make up` berikutnya mengembalikan `rag-api` ke cache disabled; jalankan `make cache-up` lagi bila ingin cache aktif.

- [ ] **Step 6: Commit root**

```bash
git add Makefile scripts/verify_redis_cache.sh .env.example README.md
git commit -m "feat(ops): verify redis cache runtime"
```

---

## Task 4: Readiness per Kapabilitas dan Readiness Evaluator

**Files:**
- Modify: `mcp-gateway/cmd/server/router.go`
- Test: `mcp-gateway/cmd/server/ready_test.go`
- Modify: `llm-eval-framework/api.py`
- Test: `llm-eval-framework/tests/test_api.py`
- Modify: `mcp-gateway/README.md`
- Modify: `mcp-gateway/docs/api-contract.md`
- Modify: `mcp-gateway/PROJECT_CONTEXT.md`
- Modify: `mcp-gateway/PROJECT_GOALS.md`

**Interfaces:**
- Consumes: `checkService` di `cmd/server/router.go`; global `evaluator` di `llm-eval-framework/api.py`.
- Produces:
  - `llm-eval-framework` `GET /ready` → 200 `{"status":"ready","service":"llm-eval-framework","check":"readiness"}` hanya jika `evaluator` ada dan `evaluator.health_check()` berhasil; 503 jika tidak.
  - Gateway `GET /ready` → JSON `{"check":"readiness","status":"ready|degraded|not_ready","services":{...},"capabilities":{"answers":bool,"evaluation":bool}}`.
  - HTTP 200 jika minimal satu backend jawaban (`arxiv` atau `rag`) up; HTTP 503 hanya jika keduanya down.
  - Gateway memprobe evaluator di `/ready`, bukan `/health`.

- [ ] **Step 1: Tulis test evaluator `/ready` yang gagal**

Di `llm-eval-framework/tests/test_api.py`, tambahkan:

```python
class TestReadyEndpoint:
    def test_ready_when_evaluator_and_embedding_are_ready(self, stub_evaluator):
        evaluator = stub_evaluator(_fake_result())
        evaluator.health_check.return_value = True

        assert api_module.ready() == {
            "status": "ready",
            "service": "llm-eval-framework",
            "check": "readiness",
        }

    def test_not_ready_when_embedding_dependency_is_down(self, stub_evaluator):
        evaluator = stub_evaluator(_fake_result())
        evaluator.health_check.return_value = False

        with pytest.raises(HTTPException) as exc:
            api_module.ready()
        assert exc.value.status_code == 503

    def test_not_ready_when_evaluator_is_not_initialized(self, monkeypatch):
        monkeypatch.setattr(api_module, "evaluator", None)

        with pytest.raises(HTTPException) as exc:
            api_module.ready()
        assert exc.value.status_code == 503
```

- [ ] **Step 2: Jalankan test dan pastikan gagal**

Run: `cd llm-eval-framework && ../venv/bin/python -m pytest tests/test_api.py -k ready -v`

Expected: FAIL karena `api_module.ready` belum ada.

- [ ] **Step 3: Implementasikan `/ready` dan `health_check` dengan timeout**

Di `llm-eval-framework/evaluators/faithfulness.py`, ubah `OllamaEmbedder.health_check` menjadi:

```python
def health_check(self, timeout: float = 5.0) -> bool:
    try:
        response = requests.post(
            self._endpoint,
            json={"model": self.model, "input": "health check"},
            timeout=timeout,
        )
        response.raise_for_status()
        return True
    except Exception as e:
        logger.error(f"Embedder health check FAILED | {e}")
        return False
```

Ubah `FaithfulnessEvaluator.health_check` menjadi `def health_check(self, timeout: float = 5.0) -> bool: return self.embedder.health_check(timeout=timeout)`.

Di `llm-eval-framework/api.py`, tambahkan setelah `health()`:

```python
@app.get("/ready")
def ready():
    if evaluator is None:
        raise HTTPException(status_code=503, detail="FaithfulnessEvaluator not initialized")
    if not evaluator.health_check(timeout=2.0):
        raise HTTPException(status_code=503, detail="Ollama embedding dependency unavailable")
    return {"status": "ready", "service": "llm-eval-framework", "check": "readiness"}
```

Jangan mengubah healthcheck Compose menjadi `/ready`; healthcheck Compose tetap liveness agar `depends_on` gateway tidak memblokir startup saat model Ollama dingin. Gateway yang melaporkan degradasi.

- [ ] **Step 4: Tulis test gateway readiness yang gagal**

Di `mcp-gateway/cmd/server/ready_test.go`, ubah helper agar menerima path yang diharapkan:

```go
func healthyService(t *testing.T, wantPath string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != wantPath {
			t.Errorf("unexpected readiness path: %s, want %s", r.URL.Path, wantPath)
		}
		w.WriteHeader(http.StatusOK)
	}))
}
```

Tambahkan/ubah test:

| Test | Setup | Assertion |
|---|---|---|
| `TestReady_AllDependenciesUp` | arxiv `/health` 200, evaluator `/ready` 200, rag `/health` 200 | HTTP 200; `status=ready`; `capabilities.answers=true`; `capabilities.evaluation=true`; ketiga service `up` |
| `TestReady_EvaluatorDownIsDegraded` | arxiv 200, evaluator `/ready` 503, rag 200 | HTTP 200; `status=degraded`; `answers=true`; `evaluation=false`; evaluator `degraded` |
| `TestReady_OneAnswerBackendDownIsDegraded` | arxiv 200, evaluator 200, rag `http://127.0.0.1:1` | HTTP 200; `status=degraded`; `answers=true`; rag `down` |
| `TestReady_NoAnswerBackendIsNotReady` | arxiv `http://127.0.0.1:1`, evaluator 200, rag `http://127.0.0.1:1` | HTTP 503; `status=not_ready`; `answers=false` |
| `TestReady_EvaluatorProbeUsesReadyPath` | evaluator menolak `/health` tetapi menerima `/ready` | HTTP 200; evaluator `up` |

- [ ] **Step 5: Jalankan test gateway dan pastikan gagal**

Run: `cd mcp-gateway && go test ./cmd/server -run TestReady -v`

Expected: FAIL karena handler masih memakai `/health` untuk semua dependency dan mengembalikan 503 saat evaluator down.

- [ ] **Step 6: Implementasikan readiness per kapabilitas**

Di `cmd/server/router.go`, ubah `checkService` menjadi:

```go
func checkService(ctx context.Context, baseURL, path string) string
```

`handleReady` memakai daftar:

```go
dependencies := []dependency{
	{name: "arxiv", apiURL: cfg.Arxiv.BaseURL, path: "/health"},
	{name: "evaluator", apiURL: cfg.Evaluator.BaseURL, path: "/ready"},
	{name: "rag", apiURL: cfg.RAG.BaseURL, path: "/health"},
}
```

Hitung:

```go
answersAvailable := checks["arxiv"] == "up" || checks["rag"] == "up"
evaluationAvailable := checks["evaluator"] == "up"
allUp := checks["arxiv"] == "up" && checks["evaluator"] == "up" && checks["rag"] == "up"
```

Status HTTP: `200` jika `answersAvailable`, else `503`. Status body: `ready` jika `allUp`, `degraded` jika `answersAvailable && !allUp`, `not_ready` jika `!answersAvailable`. Sertakan `capabilities` seperti di Interfaces.

- [ ] **Step 7: Jalankan test dan pastikan lulus**

Run:

```bash
cd mcp-gateway && go test ./cmd/server -run TestReady -v
cd llm-eval-framework && ../venv/bin/python -m pytest tests/test_api.py -k ready -v
```

Expected: PASS.

- [ ] **Step 8: Perbarui dokumentasi kontrak**

Di `mcp-gateway/README.md` bagian `GET /ready`, ganti contoh menjadi bentuk `degraded` dengan `capabilities`. Di `mcp-gateway/docs/api-contract.md` §4, ganti baris “Kebijakan wajib/opsional per backend masih perlu diperjelas” dengan penjelasan: evaluator opsional, minimal satu backend jawaban wajib, `capabilities` membedakan keduanya. Di `mcp-gateway/PROJECT_CONTEXT.md` baris 43 dan 73, jelaskan bahwa `/ready` memprobe evaluator di `/ready` dan bahwa `degraded` berarti minimal satu backend jawaban hidup. Di `mcp-gateway/PROJECT_GOALS.md` butir 8, ganti “Clarify which dependencies are mandatory...” dengan kebijakan yang sudah diputuskan.

- [ ] **Step 9: Commit di dua submodule dan root**

```bash
cd llm-eval-framework
git add api.py evaluators/faithfulness.py tests/test_api.py
git commit -m "feat(health): add embedding-aware readiness probe"
cd ../mcp-gateway
git add cmd/server/router.go cmd/server/ready_test.go README.md docs/api-contract.md PROJECT_CONTEXT.md PROJECT_GOALS.md
git commit -m "feat(ready): separate answer and evaluation capabilities"
cd ..
git add llm-eval-framework mcp-gateway
git commit -m "chore(workspace): bump capability-aware readiness"
```

---

## Task 5: Smoke Run yang Membuktikan Baris Log Baru

**Files:**
- Modify: `scripts/smoke_e2e.sh`
- Modify: `README.md` — hapus batasan lama setelah verifikasi

**Interfaces:**
- Consumes: `gateway_query_logs` (tabel milik gateway) dan `query_logs` (tabel milik arxiv go-backend); `GatewayResponse.request_id`.
- Produces:
  - Env `SMOKE_RUN_ID` (opsional; default timestamp+PID).
  - Header `X-Request-ID: smoke-<RUN_ID>` dan `X-Request-ID: smoke-rag-<RUN_ID>`.
  - Query unik `What is this paper about? [smoke:<RUN_ID>]`.
  - Assertion: tepat satu baris `gateway_query_logs` untuk request ID tersebut, dan minimal satu baris `query_logs` untuk query unik tersebut.

- [ ] **Step 1: Tambahkan run ID dan query unik**

Di awal `scripts/smoke_e2e.sh`:

```bash
RUN_ID="${SMOKE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
GATEWAY_REQUEST_ID="smoke-$RUN_ID"
GATEWAY_REQUEST_ID_RAG="smoke-rag-$RUN_ID"
ARXIV_QUERY="What is this paper about? [smoke:$RUN_ID]"
RAG_QUERY="How does RAG combine retrieval with generation? [smoke:$RUN_ID]"

if ! [[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "[smoke ERROR] SMOKE_RUN_ID contains unsafe characters" >&2
  exit 1
fi
```

Ganti body panggilan `/ask` arxiv agar memakai `$ARXIV_QUERY`, dan tambahkan header:

```bash
-H "X-Request-ID: $GATEWAY_REQUEST_ID"
```

Lakukan hal yang sama untuk panggilan `research_rag` dengan `$RAG_QUERY` dan `$GATEWAY_REQUEST_ID_RAG`.

- [ ] **Step 2: Verifikasi request ID di respons**

Setelah respons arxiv di-parse:

```bash
RESPONSE_REQUEST_ID=$(echo "$QUERY_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('request_id',''))")
[ "$RESPONSE_REQUEST_ID" = "$GATEWAY_REQUEST_ID" ] || err "gateway request_id mismatch: $RESPONSE_REQUEST_ID"
```

Lakukan hal yang sama untuk respons RAG dan `$GATEWAY_REQUEST_ID_RAG`.

- [ ] **Step 3: Pindahkan helper `run_psql` dan tambahkan `wait_for_count`**

Definisikan `run_psql` sebelum Step 3 (sebelum dipakai), lalu:

```bash
wait_for_count() {
  local sql="$1" expected="$2" label="$3"
  local deadline=$((SECONDS + 20))
  while [ "$SECONDS" -lt "$deadline" ]; do
    count=$(run_psql "$sql") || err "psql failed for $label"
    if [ "$count" -ge "$expected" ]; then
      log "$label: $count row(s) ✓"
      return 0
    fi
    sleep 1
  done
  err "$label: expected >=$expected row(s), got $count"
}
```

- [ ] **Step 4: Ganti pemeriksaan log lama dengan assertion baru**

Hapus query `SELECT COUNT(*) FROM query_logs WHERE query = 'What is this paper about?';` yang lama. Ganti dengan:

```bash
wait_for_count \
  "SELECT COUNT(*) FROM gateway_query_logs WHERE request_id = '$GATEWAY_REQUEST_ID' AND backend = 'arxiv';" \
  1 "gateway arxiv log"

wait_for_count \
  "SELECT COUNT(*) FROM gateway_query_logs WHERE request_id = '$GATEWAY_REQUEST_ID_RAG' AND backend = 'research_rag';" \
  1 "gateway rag log"

wait_for_count \
  "SELECT COUNT(*) FROM query_logs WHERE query = '$ARXIV_QUERY';" \
  1 "arxiv backend query log"

for pair in "arxiv:$GATEWAY_REQUEST_ID" "research_rag:$GATEWAY_REQUEST_ID_RAG"; do
  backend="${pair%%:*}"
  rid="${pair#*:}"
  exact=$(run_psql "SELECT COUNT(*) FROM gateway_query_logs WHERE request_id = '$rid' AND backend = '$backend';") \
    || err "psql failed for gateway $backend log"
  [ "$exact" -eq 1 ] || err "gateway $backend log: expected exactly 1 row, got $exact"
done
```

Jika query arxiv menghasilkan insufficient context, backend tidak menulis `query_logs`; smoke harus FAIL, bukan meloloskan run.

- [ ] **Step 5: Perbarui ringkasan akhir**

Tambahkan `RUN_ID`, `GATEWAY_REQUEST_ID`, dan `GATEWAY_REQUEST_ID_RAG` ke blok ringkasan akhir. Pastikan semua pesan error menyebut run ID agar baris lama tidak bisa tertukar.

- [ ] **Step 6: Cek sintaks dan jalankan**

Run:

```bash
bash -n scripts/smoke_e2e.sh
make smoke-e2e
```

Expected: PASS; output menunjukkan request ID yang sama dengan header, `gateway arxiv log: 1 row(s)`, `gateway rag log: 1 row(s)`, dan `arxiv backend query log: >=1 row(s)`.

- [ ] **Step 7: Commit root**

```bash
git add scripts/smoke_e2e.sh README.md
git commit -m "test(smoke): bind verification to unique request ids"
```

---

## Task 6: Verifikasi Monitoring 5 Target dan Grafana

**Files:**
- Create: `scripts/verify_monitoring.sh`
- Modify: `infra/prometheus/prometheus.yml`
- Modify: `Makefile`
- Modify: `README.md`

**Interfaces:**
- Consumes: Prometheus `http://localhost:9090`, Grafana `http://localhost:3000`, lima endpoint `/metrics`.
- Produces:
  - Target Make `verify-monitoring`.
  - Env `PROM_URL`, `GRAFANA_URL`, `GRAFANA_AUTH` (default `admin:admin`).
  - Assertion: lima job (`go-backend`, `python-ml`, `mcp-gateway`, `llm-eval-framework`, `rag-api`) berstatus `up`; query p95 dan request rate mengembalikan data; dashboard `workspace-overview` ter-provision dengan 5 panel.

- [ ] **Step 1: Samakan nama job dan tulis skrip verifikasi**

Ubah `infra/prometheus/prometheus.yml` dari `job_name: 'rag-research'` menjadi `job_name: 'rag-api'` agar label job cocok dengan nama service di `PROJECT_GOALS.md` dan output `docker compose ps`. Dashboard tidak memfilter job ini secara eksplisit, jadi tidak ada panel yang perlu diubah.

Buat `scripts/verify_monitoring.sh` dengan assertion:

1. Setiap endpoint mengembalikan metrik yang diharapkan:

| Service | URL | Needle |
|---|---|---|
| go-backend | `http://localhost:8080/metrics` | `http_requests_total` |
| python-ml | `http://localhost:8001/metrics` | `http_requests_total` |
| mcp-gateway | `http://localhost:8090/metrics` | `gateway_http_requests_total` |
| llm-eval-framework | `http://localhost:8002/metrics` | `http_request_duration_seconds` |
| rag-api | `http://localhost:8000/metrics` | `rag_requests_total` |

2. Prometheus targets:

```bash
curl -sf "$PROM_URL/api/v1/targets?state=active" |
  jq -e '[.data.activeTargets[] | select(.health == "up") | .labels.job] | sort == ["go-backend","llm-eval-framework","mcp-gateway","python-ml","rag-api"]'
```

3. `sum(up)` bernilai `5`:

```bash
curl -sf "$PROM_URL/api/v1/query?query=sum(up)" |
  jq -e '.data.result[0].value[1] == "5"'
```

4. Query p95 dari dashboard mengembalikan minimal satu series setelah smoke dijalankan:

```bash
expr='histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]) or rate(gateway_http_request_duration_seconds_bucket[5m]) or rate(rag_latency_seconds_bucket[5m])))'
curl -sfG "$PROM_URL/api/v1/query" --data-urlencode "query=$expr" |
  jq -e '.data.result | length > 0'
```

5. Grafana hidup dan dashboard ter-provision:

```bash
curl -sf -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/health" | jq -e '.database == "ok"'
curl -sf -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/dashboards/uid/workspace-overview" |
  jq -e '.dashboard.title == "Workspace Overview" and (.dashboard.panels | length) == 5'
```

Jika p95 kosong karena belum ada traffic, jalankan `make smoke-e2e` lebih dulu; skrip harus gagal dengan pesan itu, bukan diam-diam lulus. Poll target dan dashboard hingga 60 detik karena Grafana provisioning dan scrape pertama tidak instan.

- [ ] **Step 2: Tambahkan target Make**

```make
verify-monitoring:  ## Verify Prometheus targets, p95 data, and Grafana dashboard
	bash scripts/verify_monitoring.sh
```

Tambahkan ke `.PHONY`.

- [ ] **Step 3: Jalankan verifikasi**

Run:

```bash
docker compose --env-file .env --profile monitoring up -d --force-recreate prometheus
make monitoring-up
make smoke-e2e
make verify-monitoring
```

`--force-recreate prometheus` diperlukan karena `prometheus.yml` di-bind-mount dan Prometheus tidak otomatis memuat ulang config saat file berubah.

Expected: PASS; output mencantumkan kelima job `up`, `sum(up)=5`, minimal satu series p95, dan dashboard dengan 5 panel.

- [ ] **Step 4: Dokumentasikan**

Di `README.md` bagian Monitoring, tambahkan `make verify-monitoring` dan jelaskan bahwa verifikasi membutuhkan minimal satu request (smoke) agar histogram p95 punya data.

- [ ] **Step 5: Commit root**

```bash
git add Makefile scripts/verify_monitoring.sh infra/prometheus/prometheus.yml README.md
git commit -m "test(monitoring): verify targets, p95, and grafana dashboard"
```

---

## Task 7: Acceptance Build Bersih, Idempotensi Seed, dan Sinkronisasi Dokumen

**Files:**
- Create: `docs/acceptance/phase-2-verification.md`
- Modify: `PROJECT_GOALS.md`
- Modify: `PROJECT_CONTEXT.md`
- Modify: `README.md`
- Modify: `docs/ai-taskboard.md`
- Modify: `mcp-gateway/IMPLEMENTATION_TODO.md`
- Modify: `mcp-gateway/PROJECT_CONTEXT.md`
- Modify: `mcp-gateway/PROJECT_GOALS.md`

**Interfaces:**
- Consumes: seluruh target dan skrip dari Task 1–6.
- Produces: satu catatan acceptance bertanggal yang mengikat setiap gate ke command, output, commit SHA, dan verdict; checklist Fase 2/Production Readiness hanya dicentang jika output mendukung.

- [ ] **Step 1: Catat baseline commit dan working tree**

Run:

```bash
git rev-parse HEAD
git submodule status
git status --short
```

Simpan output di `docs/acceptance/phase-2-verification.md` bagian `Baseline`. Jangan lanjut jika ada perubahan tak terkait yang akan tercampur; stage hanya path yang direncanakan.

- [ ] **Step 2: Jalankan seluruh test suite**

Run: `make test`

Expected: semua suite PASS. Catat jumlah test per repo (`go test`, `pytest`) dan exit code. Jika ada kegagalan, tulis `BLOCKED` dengan nama test; jangan centang gate.

- [ ] **Step 3: Verifikasi secret dan konfigurasi Compose**

Run:

```bash
make check-secrets
docker compose --env-file .env config >/dev/null
```

Expected: `CLEAN` dan exit 0. Catat output ringkas di acceptance doc.

- [ ] **Step 4: Build bersih tanpa cache**

Run:

```bash
docker compose --env-file .env build --no-cache --pull
docker compose --env-file .env images
```

Expected: build sukses tanpa memakai cache layer dan dengan base image yang di-pull ulang; catat ukuran image dari `docker compose images`. Jangan memakai image lokal prapasang sebagai bukti.

- [ ] **Step 5: Nyalakan stack dan verifikasi health**

Run:

```bash
docker compose --env-file .env up -d --wait --wait-timeout 600
docker compose --env-file .env ps
```

Expected: seluruh service inti `healthy` (atau `running` untuk service tanpa healthcheck). Catat snapshot.

- [ ] **Step 5b: Pastikan dependency embedding evaluator tersedia**

Run:

```bash
docker compose --env-file .env exec -T ollama ollama pull nomic-embed-text
docker compose --env-file .env exec -T llm-eval-framework python -c "import requests; r=requests.post('http://ollama:11434/api/embed', json={'model':'nomic-embed-text','input':'warmup'}, timeout=60); r.raise_for_status(); print('embedding warmed')"
docker compose --env-file .env exec -T llm-eval-framework python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8002/ready', timeout=10).status)"
```

Expected: model tersedia dan `/ready` mengembalikan `200`. Jika `/ready` masih 503, tunggu inisialisasi/embedding selesai lalu ulangi; jangan menganggap monitoring PASS jika evaluator tidak pernah ready.

Setelah evaluator `/ready` 200, verifikasi kontrak readiness gateway hidup:

```bash
curl -s http://localhost:8090/ready | jq -e '.status == "ready" and .capabilities.answers == true and .capabilities.evaluation == true'
```

- [ ] **Step 6: Buktikan seed Qdrant idempoten**

Run dua kali:

```bash
QDRANT_URL=http://localhost:6333 make seed-rag
curl -s http://localhost:6333/collections/rag_research | jq '.result.points_count'
QDRANT_URL=http://localhost:6333 make seed-rag
curl -s http://localhost:6333/collections/rag_research | jq '.result.points_count'
```

Expected: kedua nilai `points_count` sama; tidak ada duplikasi. Catat angka sebelum/sesudah. Jika `make seed-rag` memerlukan Qdrant hidup, pastikan Step 5 selesai.

- [ ] **Step 7: Jalankan smoke, cache, dan monitoring**

Run:

```bash
make smoke-e2e
make verify-redis
make monitoring-up
make smoke-e2e
make verify-monitoring
```

Expected:

- Smoke pertama dan kedua PASS dengan `RUN_ID` berbeda.
- `gateway_query_logs` bertambah tepat satu baris per request ID.
- Redis: `cache_hit=false` lalu `cache_hit=true`, TTL > 0.
- Monitoring: 5 target up, `sum(up)=5`, p95 series > 0, dashboard 5 panel.

Catat output aktual, bukan hanya “PASS”.

- [ ] **Step 8: Verifikasi lifecycle dan persistensi**

Run:

```bash
docker compose --env-file .env down
docker compose --env-file .env up -d --wait --wait-timeout 600
curl -s http://localhost:6333/collections/rag_research | jq '.result.points_count'
docker exec ws-postgres psql -U arxiv -d arxiv_db -t -A -c "SELECT COUNT(*) FROM gateway_query_logs;"
```

Expected: `points_count` dan jumlah baris `gateway_query_logs` tidak hilang setelah `down`/`up`. Jangan memakai `down -v`.

- [ ] **Step 9: Tulis acceptance doc**

Buat `docs/acceptance/phase-2-verification.md` dengan tabel:

| Gate | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| Secrets | `make check-secrets` + scanner regression test | CLEAN, exit 0 | ... | PASS/FAIL |
| Tests | `make test` | 0 failed; skip yang disengaja dicatat | ... | PASS/FAIL |
| Clean build | `docker compose build --no-cache --pull` | sukses | ... | PASS/FAIL |
| Stack health | `docker compose --env-file .env up -d --wait --wait-timeout 600` | semua healthy | ... | PASS/FAIL |
| Evaluator readiness | `ollama pull nomic-embed-text` + warmup + `/ready` | HTTP 200 | ... | PASS/FAIL |
| Seed idempotent | `QDRANT_URL=http://localhost:6333 make seed-rag` ×2 | points_count sama | ... | PASS/FAIL |
| Smoke fresh log | `make smoke-e2e` | request ID & row count benar | ... | PASS/FAIL |
| Redis cache | `make verify-redis` | cache_hit false→true, TTL > 0 | ... | PASS/FAIL |
| Monitoring | `make verify-monitoring` | 5 target, p95, dashboard | ... | PASS/FAIL |
| Persistence | `down`/`up` | data bertahan | ... | PASS/FAIL |

Sertakan `Baseline` (commit SHA, submodule SHA, tanggal, operator) dan bagian `Known Limitations` yang menyatakan: Fase 2 membuktikan gate operasional, bukan kualitas jawaban; MCP belum tersedia; cache masih opt-in.

- [ ] **Step 10: Sinkronkan dokumen hanya untuk gate yang PASS**

Jika semua gate PASS:

- `PROJECT_GOALS.md` baris status: gate operasional Fase 2 selesai dengan tanggal dan tautan acceptance doc; Fase 3 belum dimulai. Jangan menulis “production-ready penuh” — klaim kualitas jawaban, kalibrasi confidence, dan atribusi per kalimat tetap terbuka.
- `PROJECT_GOALS.md` §8 Fase 2: ubah heading menjadi “gate operasional selesai”, centang item Redis, dan tambahkan sub-item runtime monitoring, smoke fresh-run, readiness per kapabilitas.
- `PROJECT_GOALS.md` §9: centang `Kemandirian Build`, `Kelulusan Uji 100%` (0 failed; skip yang disengaja dicatat), `Nol Kebocoran Kunci`, `Monitoring Aktif`; pertahankan catatan bahwa smoke bukan acceptance kualitas.
- `PROJECT_CONTEXT.md` §2: perbarui jumlah layanan inti, status Redis (masih opt-in), dan hapus batasan smoke lama; ganti dengan mekanisme request ID/query unik.
- `README.md`: perbarui quickstart, bagian monitoring, dan daftar target Make.
- `docs/ai-taskboard.md`: tandai #3 (`make seed-rag`) dan #6 (monitoring) selesai dengan tautan acceptance doc; tambahkan baris Task 1–6 dengan commit hash.
- `mcp-gateway/IMPLEMENTATION_TODO.md` P0: centang verifikasi Prometheus/Grafana, smoke request ID, readiness per kapabilitas, dan evaluator readiness.
- `mcp-gateway/PROJECT_CONTEXT.md` baris 56: ganti “Runtime verification ... tracked separately” dengan tautan ke acceptance doc dan tanggal verifikasi.
- `mcp-gateway/PROJECT_GOALS.md` baris 4: catat bahwa verifikasi runtime/monitoring Fase 2 sudah tercatat di acceptance doc; gate lain (trace propagation, `/tool` security, legacy retrieval) tetap terbuka.

Jika ada gate FAIL, jangan centang apa pun; tulis `BLOCKED` beserta command dan error di acceptance doc, lalu perbaiki sebelum memperbarui status.

- [ ] **Step 11: Commit dokumentasi**

```bash
cd mcp-gateway
git add IMPLEMENTATION_TODO.md PROJECT_CONTEXT.md PROJECT_GOALS.md
git commit -m "docs: record phase 2 operational gates"
cd ..
git add docs/acceptance/phase-2-verification.md PROJECT_GOALS.md PROJECT_CONTEXT.md README.md docs/ai-taskboard.md mcp-gateway
git commit -m "docs: record phase 2 acceptance evidence"
```

---

## Self-Review Checklist (dijalankan sebelum eksekusi)

- **Spec coverage:** Fase 2 `PROJECT_GOALS.md` §8 mencakup Prometheus metrics (sudah ada; diverifikasi Task 6), leakage (sudah ada; tidak diubah), auto-seed (diverifikasi Task 7), Redis (Task 2–3). §9 mencakup clean build (Task 7), test (Task 7), secrets (Task 1), smoke (Task 5), monitoring (Task 6). Gate P0 gateway: build reproducible (Task 7), monitoring (Task 6), smoke fresh run (Task 5), readiness (Task 4), evaluator readiness (Task 4).
- **Security gate:** scanner `check_secrets.sh` diperbaiki untuk false positive/negative submodule dan diuji dengan repo sementara (Task 1 Step 4); `make check-secrets` harus exit 0 sebelum commit.
- **Step scan:** setiap langkah memiliki command/assertion atau signature exact; tidak ada “handle edge cases” tanpa test.
- **Type consistency:** `cache_hit` konsisten antara `GenerateResponse`, test, dan `verify_redis_cache.sh`; `checkService(ctx, baseURL, path)` konsisten di test dan implementasi; status readiness `ready/degraded/not_ready` konsisten; tabel `gateway_query_logs` vs `query_logs` tidak tertukar.
- **Review Focus:** lima kondisi masing-masing punya test — Redis down (Task 2 `test_redis_connection_failure_disables_cache`), cached abstention (Task 2 `test_cached_abstention_is_not_served`), evaluator down (Task 4 `TestReady_EvaluatorDownIsDegraded` + acceptance evaluator failure yang sudah ada), satu backend down (Task 4 `TestReady_OneAnswerBackendDownIsDegraded`; respons 502 sudah dikunci `router_test.go`/`acceptance_test.go`), log lama (Task 5 unique request ID/query).
- **Proportion:** rencana berisi kontrak dan assertion, bukan transkrip implementasi; script shell memberi alur dan nilai yang harus diperiksa, bukan seluruh isi file.
