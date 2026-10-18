# Ops Postmortem — Workspace AI-Infra (2026-10-18)

Seri insiden serius yang terjadi pada malam yang berliku — masing-masing bisa dibaca ulang
lengkap dengan akar masalah, cara diagnosis, dan langkah preventifnya. Format mengikuti gaya
`arxiv-research-assistant/docs/postmortem/` (scenario-2-postgres-down.md).

---

## Scenario-3: `phi3:mini` OOM saat `make up` — LLM lokal mati, stack tak boleh mati

**Gejala**
- `/query` (arxiv) → `HTTP 500` di python-ml: `OllamaError("ollama_http_error")`
- Log ollama: `llama-server process has terminated: signal: killed` → container exit.

**Akar**
- Host RAM 15.7 GB: desktop GUI (browser + Qt/Electron) menghabiskan ~4 GB, torch/MiniLM kontainer ~1–2 GB — sisa ~3 GB; cold load `phi3:mini` (weights ~2.2 GB / KV context 1.5 GB / buffer compute) butuh ~4.5–5 GB peak → OOM killer.
- Terjadi bersamaan dengan proses embedding (`nomic`).

**Diagnosis**
```bash
free -m                                   # lihat "available"
docker stats --no-stream | sort -k2 -h -r
curl -s localhost:11434/api/ps            # daemon HOST sering memegang model lama
```

**Obat (tahap berjalan)**
- Ganti rute generasi ke **Groq** (`LLM_PROVIDER: groq`, key tervalidasi; `/query` 118 s → 3.1 s).
- Muat ulang dengan RAM bebas (tutup GUI / unload daemon host lewat `keep_alive=0`):
  `curl -X POST localhost:11434/api/generate -d '{"model":"phi3:mini","keep_alive":0}'`
- `OLLAMA_KEEP_ALIVE: 30m` di compose — model tidak unload tiap 5 menit.

**Preventif**
- Untuk stack demo ini, **jangan menjadikan load model 2+ GB sebagai default** di host ⩽16 GB RAM: gunakan Groq untuk dev/review, dan phi3 hanya untuk demo lokal saat memori host lapang (cek `free -m` lebih dulu).

---

## Scenario-4: DNS rootless berubah-ubah "bentuk" — `NameResolutionError` internal

**Gejala**
- Python/qdrant/ollama call: `[Errno -3] Temporary failure in name resolution` / `[Errno -5]` → `ws-qdrant`/`ws-postgres` tak teresolve.
- Go gateway: `lookup ws-postgres on 8.8.8.8:53: connect: network is unreachable`.
- Bersifat ephemeral: kadang container OK (bentuk embedded), recreate berikutnya error (bentuk eksternal).

**Akar**
Rootless Docker (RootlessKit/slirp) + cara dockerd menulis `/etc/resolv.conf`:
- **Bentuk-A (baik):** `nameserver 127.0.0.11` (Docker embedded DNS; nama internal resolve langsung).
- **Bentuk-B (rusak):** nameserver publik (1.1.1.1/8.8.8.8) — nama INTERNAL tidak di-zonasi; bila server UDP eksternal tak terhubung dari netns → resolusi gagal.
HostConfig identik antar container, namun hasil render bisa berbeda-beda (quirk dockerd); tidak deterministik.

**Diagnosis**
```bash
docker exec <container> cat /etc/resolv.conf   # bentuk-A atau B?
```

**Obat**
```bash
docker compose --env-file .env up -d --force-recreate --no-deps --no-build <service>
```
re-render → biasanya kembali ke bentuk-A. Untuk DNS eksternal yang tetap flaky
(export.arxiv.org, registry.ollama.ai), cukup ulangi ingest/pull — sifatnya retry-able.

**Preventif**
- Setiap kali big-recreate: cek `cat /etc/resolv.conf` dulu; kalau bentuk-B, force-recreate sekali lagi.
- Jangan menembak IP langsung di compose sebagai "solusi" — di-recreate akan kembali ke akar masalah.

---

## Scenario-5: Image `rag-api` kehilangan dependensi — `FROM` menunjuk tag yang bergerak

**Gejala**
- `ws-rag-api` exit (1): `ModuleNotFoundError: pydantic_settings` (+ `rank_bm25`, `multipart`).
- Build `rag-api` yang seharusnya berisi kolam paket penuh (sebelumnya lolos uji) mendadak kehilangan paketnya.

**Akar**
Dockerfile rag-research memakai `FROM <tag-name-lain>:latest` (tag yang bisa di-rebuild oleh stack lain tanpa paket RAG-spesifik). Saat tag tsb di-renew oleh stack lain, rebuild rag-api ikut mundur ke layer lama yang tak memuat paket RAG. Tambahan: `docker compose up --build` pada satu layanan juga memicu **build silang dependensi**.

**Diagnosis**
```bash
docker run --rm --entrypoint python <img> -c "import pydantic_settings, rank_bm25, multipart, torch, sentence_transformers"
```

**Obat (permanen)**
1. Fix-up saat kejadian + **freeze base**: `docker tag <img-id> ai-infra-workspace-rag-base:v1`.
2. Dockerfile rag-research: `FROM ai-infra-workspace-rag-base:v1` + pin wheel server/RAG dari `requirements/wheels-server/` + bake `hf-cache/` + `HF_HUB_OFFLINE=1` → **hermetic** (`docker build --network none`).
3. Tambahkan `--no-build` pada `scripts/rotate_key.sh` — rotasi kunci tidak boleh memicu build silang.

**Preventif**
- Dockerfile **tidak boleh mereferensikan tag `:latest` milik service LAIN** — gunakan tag beku yang di-bump eksplisit saat base diperbarui (docs: rag-research/Dockerfile).
- Perhatikan output build: `docker compose up --build` memang selalu menyentuh layer build-chain — itu wajar, bukan tanda kerusakan.

---

## Rantai insiden (satu malam)

1. Timeout 141 s saat phi lambat → `ml_client.go` dinaikkan ke 180 s + `OLLAMA_KEEP_ALIVE=30m`.
2. Rute /generate mengembalikan frame abstain (sentinel + failure_type padahal `decision=GENERATE`) → patch `IsAbstention()` + fallback data-map + regression test.
3. `DefaultRAGTimeout` 10 s → 60 s (untuk retry saat Groq rate-limit).
4. Gateway dapat resolv bentuk-B saat recreate → force-recreate.
5. phi3 OOM → `LLM_PROVIDER=groq` + dokumentasi RAM.
6. rag-api kehilangan dependensi + resolv bentuk-B → **frozen base + hermetic Dockerfile + `--no-build`**.
7. smoke-e2e menuntut "ingest ulang paper" → dibuat toleran/idempoten + retry 2x.

Semuanya ter-regresi di: `go test -race ./...` (mcp-gateway 8 paket OK), `make smoke-e2e` PASSED, `make check-secrets` CLEAN.

---

## Scenario-6: CI GitHub Actions "0 run" selama 2 hari — gerbang approval FORK

**Gejala**
- `gh run list` kosong dan `actions/runs → total_count = 0` di keempat repo, padahal workflow terdaftar **active** (`gh workflow list --all`), file workflow ada di remote, dan push sukses.
- `actions_enabled = true` untuk semua repo; `PushEvent` TERCATAT di API events (mis. arxiv `2026-10-18T16:57:10Z`) tetapi tidak ada run yang dibuat.

**Akar**
- Keempat repo adalah **fork** (ForkEvent 2026-10-16). Untuk fork, workflow **tidak berjalan otomatis (push/PR) sampai pemilik meng-klik "I understand my workflows, go ahead and enable them"** di tab Actions repo tersebut.
- Sebelum approval: run otomatis TIDAK dibuat, tetapi `workflow_dispatch` manual **tetap jalan** — terkonfirmasi: dispatch llm-eval/arxiv/rag langsung memproduksi run hijau, sementara push ke repo yang sama tidak menghasilkan apa-apa.
- mcp-gateway adalah satu-satunya yang sudah di-enable pemilik (saat pengecekan banner sebelumnya) → hanya push-trigger mcp yang hidup.

**Diagnosis**
```bash
gh run list --repo <owner>/<repo> --limit 3        # kosong?
gh api repos/<owner>/<repo>/events --jq '.[].type' # PushEvent ada → event diterima, run tidak dibuat
gh workflow list --repo <owner>/<repo> --all       # active (bukan disabled_manually)
```

**Obat (satu klik per repo + kode)**
1. Actions tab → `arxiv-research-assistant`, `rag-research`, `llm-eval-framework` → klik **"I understand my workflows, go ahead and enable them"** (mcp-gateway sudah).
2. Sisi kode: `workflow_dispatch:` ditambahkan ke semua workflow (kanal darurat), job `secrets-scan` (grep `gsk_[A-Za-z0-9]{30,}`), langkah pytest di llm-eval, dan **`gofmt -s`** 4 file mcp yang membuat Lint merah di run pertama (`cmd/server/stub_test.go`, `internal/config/config.go`, `internal/tools/research_rag_contract.go`, `internal/tools/research_rag_test.go`).
3. Hardening searah P1: smoke Step 3b (kontrak `research_rag`: `decision ∈ {answer,abstain}`, `evaluation_status ∈ {skipped,unavailable,completed}`; uji negatif rag-mati → `502 backend_error/skipped`), README mcp memuat tabel makna `evaluation_status`.

**Bukti (semua hijau)**
- mcp-gateway `39148533651`: 4/4 job (Lint, Build & Test + postgres, Docker, Secrets) ✓
- arxiv `39148331309`: 3/3 ✓ · rag `39148563073`: 5/5 (pytest 3.12+3.14, contracts ×2, secrets) ✓
- llm-eval `39147548575`: 2/2 (pytest 199 tes) ✓

**Preventif**
- Setelah mem-fork repo: approve workflow di Actions tab SEBELUM mendebug "0 run"; `workflow_dispatch` = jalur verifikasi cepat.
- Jangan menyimpulkan "CI rusak" dari `total_count=0` saja — bedakan: (a) gate fork, (b) `disabled_manually`, (c) file invalid, (d) filter branch di trigger.
