# Ops Postmortem — Workspace AI-Infra (2026-10-18)

Seri insiden serius yang final terjadi pada hari berliku — tiga yang Fenomen Kamu bisa ulang baca, lengkap dengan akar, petunjuk, dan motion preventif. Berindikasi masing sesuai gaya `arxiv-research-assistant/docs/postmortem/` (scenario-2-postgres-down.md).

---

## Scenario-3: `phi3:mini` OOM saat `make up` — LLM lokal mati, stack tak boleh mati

**Gejala**
- `/query` (arxiv) → `HTTP 500` di python-ml: `OllamaError("ollama_http_error")`
- Log ollama: `llama-server process has terminated: signal: killed` → container exit.

**Akar**
- Host RAM 15.7 GB: desktop GUI (browser + Qt/Electron) menghabiskan ~4 GB, torch/MiniLM kontainer ~1–2 GB — sisa ~3 GB; cold load `phi3:mini` (weights ~2.2 GB / KV context 1.5 GB / buffer compute) butuh ~4.5–5 GB peak → OOM killer.
- Terjadi PAS paralel dengan embedding (`nomic`).

**Diagnosis**
```bash
free -m                                   # lihat "available"
docker stats --no-stream | sort -k2 -h -r
curl -s localhost:11434/api/ps            # daemon HOST sering memegang model lama
```

**Obat (tahap berjalan)**
- Ganti rute generasi ke **Groq** (`LLM_PROVIDER: groq`, key tervalidasi; `/query` 118 s → 3.1 s).
- Muat ulang dgn RAM bebas (tutup GUI / `keep_alive=0` unload daemon host):
  `curl -X POST localhost:11434/api/generate -d '{"model":"phi3:mini","keep_alive":0}'`
- `OLLAMA_KEEP_ALIVE: 30m` di compose — model tidak unload tiap 5 mnt.

**Preventif**
- Untuk stack demo ini, **jangan menargetkan load-model 2+ GB sebagai default** di host ⩽16 GB RAM; gunakan Groq untuk dev/review, phi3 untuk demo lokal dengan kegelapan memory-free tercetak.

---

## Scenario-4: DNS rootless "bentuk" ganti-ganti — `NameResolutionError` internal

**Gejala**
- Python/qdrant/ollama call: `[Errno -3] Temporary failure in name resolution` / `[Errno -5]` → `ws-qdrant`/`ws-postgres` tak teresolve.
- Go gateway: `lookup ws-postgres on 8.8.8.8:53: connect: network is unreachable`.
- Ephemeral: kadang container OK (bentuk embedded), recreate berikutnya error (bentuk eksternal).

**Akar**
Rootless Docker (RootlessKit/slirp) + caranya dockerd menulis `/etc/resolv.conf`:
- **Bentuk-A (baik):** `nameserver 127.0.0.11` (Docker embedded DNS; nama internal resolve langsung).
- **Bentuk-B (rus):** nameserver publik (1.1.1.1/8.8.8.8) — nama INTERNAL tidak di-zonasi; kalau server UDP eksternal tidak jalar dari netns → gugus.
Konfigurasi HostConfig identik antar container — hasil bayangan render berbeda-beda (quirk dockerd); tidak deterministik.

**Diagnosis**
```bash
docker exec <container> cat /etc/resolv.conf   # bentuk-A atau B?
```

**Obat**
```bash
docker compose --env-file .env up -d --force-recreate --no-deps --no-build <service>
```
re-render → biasanya kembali bentuk-A. Filter aman: `options use-vc` (TCP) untuk` external; DNS_ext UDP tetap bisa flaky (export.arxiv.org, registry.ollama.ai) — ingest/pull ulang bersifat-ret

**Preventif**
- Setelah api big-recreate: `cat resolv.conf` sebagai warm-up; kalau bentuk-B: force-recreate lagi.
- Jangan tembak IP di compose sebagai "solve" — di-recreate akan mesin ke akar.

---

## Scenario-5: Image `rag-api` menjadi kehilangan dependensi — FROM menghint tag yang bergerak

**Gejala**
- `ws-rag-api` exit (1): `ModuleNotFoundError: pydantic_settings` (+ `rank_bm25`, `multipart`).
- Build `rag-api` yang "menemos" kolam paket FULL yang sebelumnya disertifiktasi usai tes.

**Akar**
Dockerfile rag-research memakai `FROM <tag-name-lain>:latest` (tag yang bisa di-rebuild tanpa paket RAG-spesifik). Saat tag tsb di-renew oleh cmp stack lain, seluruh `docker rebuild` rag-api ikut mundur (pokok dockers layers dg paket sadar-diri). Tambahan akses ngged: `docker compose up --build` satu layanan ikut memicu **build silang dependensi** silang alias.

**Diagnosis**
```bash
docker run --rm --entrypoint python <img> -c "import pydantic_settings, rank_bm25, multipart, torch, sentence_transformers"
```

**Obat (permanan/ui)**
1. Fix-up sat-off + **freeze base**: `docker tag <img-id> ai-infra-workspace-rag-base:v1`.
2. Dockerfile rag-research: `FROM ai-infra-workspace-rag-base:v1` + pin wheel server/RAG dari `requirements/wheels-server/` + bake `hf-cache/` + `HF_HUB_OFFLINE=1` → **hermetic** (`docker build --network none`).
3. `strip --no-build` pada `scripts/rotate_key.sh` — rotasi tidak boleh mencaitarkan build salam-silang.

**Preventif**
- **Dockerfile build-tag-unadonis never references** tag `:latest` milik service LAIN — gunakan tag beku yang secara eksplisit bertengger ketika base diperbarui (docs: rag-research/Dockerfile).
- `check-hist_reason` build output: jangan let waktu dibutuhkannya welcome (
  `docker compose up` yang "kemenaughiny" memang selalu alami: `up --build` di layer build-chain).

---

## Chain-linkting insiden (satu malam)

1. Timeout 141-s old phi dissolving → naik `ml_client.go` 180-s + `OLLAMA_KEEP_ALIVE=30m`.
2. Rag e /generate frame absten (sentinel + failure_type padahal `decision=GENERATE`) → patched `IsAbstention()` + fallback Data-map + regression test.
3. `DefaultRAGTimeout` 10-s ke 60-s (Groq rate-limit retry).
4. Gateway resolv bentuk-B saat recreate → force-recreate.
5. phi3 OOM → `LLM_PROVIDER=groq` + dokumentasi RAM.
6. rag-api dependensi年第 unthai & resolv → **frozen base + hermetic Dockerfile + --no-build**.
7. smoke-e2e keras di "ingest ulang paper" → tolerans/idempotent + retry 2x.

Semuanya ter-regresi di: `go test -race ./...` (mcp-gateway 8 paket OK), `make smoke-e2e` PASSED, `make check-secrets` CLEAN.
