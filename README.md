# AI Infra Workspace — 4 Proyek, 1 Orkestrasi

Root Compose adalah jalur yang disarankan untuk menjalankan integrasi empat repo dan
infrastruktur bersama. Compose per repo tetap tersedia untuk pengembangan terisolasi;
konfigurasinya bukan sumber topologi lintas-repo.

## Struktur

- `PROJECT_GOALS.md` — spesifikasi rekayasa sistem, kriteria keberhasilan & visi produk.
- `PROJECT_CONTEXT.md` — batas arsitektur & snapshot runtime ekosistem saat ini.
- `docker-compose.yml` — topologi lengkap (11 service `ws-*`).
- `Makefile` — `up`, `down`, `status`, `logs`, `smoke-e2e`, `seed-rag`, `rotate-key`, `check-secrets`, `prune-builder`, `df`, `test`, `monitoring-up`, `monitoring-down`.
- `scripts/` — `rotate_key.sh`, `check_secrets.sh`, `smoke_e2e.sh`.
- `infra/grafana/` — provisioning datasource Prometheus + dashboard monitoring (opt-in).
- `docs/ops-postmortem.md` — insiden & pola pemulihan.
- Submodul: `arxiv-research-assistant`, `mcp-gateway`, `rag-research`, `llm-eval-framework`.

## Kontrak antar layanan (jaring antar folder)

```
mcp-gateway :8090 ─┬─ ARXIV_SERVICE_URL → arxiv-go-backend :8080
                   │                        └─ ML_SERVICE_URL → arxiv-python-ml :8001
                   ├─ EVAL_SERVICE_URL  → llm-eval-framework :8002 (evaluator lokal via ollama)
                   └─ RAG_SERVICE_URL   → rag-api :8000
semua service → qdrant :6333 / ollama :11434 / postgres :5432
GROQ_MODEL = openai/gpt-oss-20b  (untuk python-ml dan rag-api)
```

Gateway saat ini menyediakan HTTP/JSON (`/ask`, `/plan`, `/tool`). Dukungan wire
protocol MCP belum tersedia; nama repo tidak berarti klien MCP sudah kompatibel.
Pilih `backend: "arxiv"` untuk korpus paper yang di-ingest melalui ArXiv Assistant,
atau `backend: "research_rag"` untuk korpus tetap milik RAG Research. Kedua korpus
dan indeksnya terpisah.

## Quickstart

```bash
cp .env.example .env          # isi GROQ_API_KEY
make up
make smoke-e2e                # alur: ingest → query /ask → verifikasi query_logs di DB
```

Smoke test adalah pemeriksaan integrasi dasar, bukan evaluasi kualitas jawaban atau
acceptance produksi. Pemeriksaan log ArXiv saat ini mencari teks query tetap sehingga
baris dari run sebelumnya dapat ikut terhitung; lihat batasan ini sebelum memakai
hasil smoke sebagai bukti eksekusi terbaru.

Port di host: **8090** mcp-gateway, **8080** go-backend arxiv, **8001** python-ml, **8002** llm-eval,
**8000** rag-api, **11435** ollama (11434 = daemon host), **5432** postgres, **6333/6334** qdrant,
**6379** redis, **9090** prometheus, **3000** grafana.

## Monitoring (opt-in)

Redis/prometheus/grafana **tidak ikut `make up`** (profil `monitoring`).
Nyalakan saat butuh: `make monitoring-up` → Prometheus `:9090`, Grafana `:3000`.
Kredensial default Grafana dan kredensial fallback database hanya untuk pengembangan lokal;
ganti dengan nilai rahasia sebelum mengekspos port ke jaringan lain.
Matikan: `make monitoring-down` (stack inti tetap jalan). Prometheus men-scrape `/metrics`
go-backend, python-ml, mcp-gateway, llm-eval-framework, dan rag-api; datasource
prometheus & dashboard ter-provision otomatis di grafana.

## Mode A/B — aturan kepemilikan

| | **Mode A — root compose (KANONIK)** | **Mode B — compose per proyek** |
|---|---|---|
| Jalur | `make up` dari root | `docker compose up -d` dari folder proyek |
| Container | `ws-*` | `rag-api` / `arxiv-*` |
| Key Groq | otomatis dari `.env` root | **WAJIB** `--env-file ../.env`, kalau tidak key kosong |
| Healthcheck | python-urllib / bash /dev/tcp (image slim tanpa curl) | sama (selaras dgn Mode A) |

Aturan:
1. **A dan B tidak boleh hidup bersamaan** — bentrok port aplikasi (8000/8080/8001) dan,
   untuk stack arxiv penuh, juga port infra (5432/6333/6379/9090/3000).
2. Sebelum Mode B: `docker compose down` di folder proyek. Kembali ke Mode A: `make up`.
3. Rotasi key HANYA via root: `KEY=gsk_... make rotate-key` — key tidak pernah ditulis di `*.env.example`.
4. Verifikasi rutin: `make check-secrets` (0 rahasia di file tracked) + `make smoke-e2e`.

## Troubleshooting cepat

- **502 `backend_timeout`/EOF saat `/ask`** — rag-api baru di-recreate di tengah generasi;
  tunggu healthy (~1 mnt) lalu ulangi.
- **`GROQ_API_KEY` kosong di container** — compose dari folder proyek dijalankan tanpa
  `--env-file ../.env`. Kembali ke Mode A (`make up`) atau ulangi dengan env-file.
- **rag-api exit 137** — OOM RAM (host 15 GB + GUI) atau SIGKILL saat recreate.
  Cek `free -m` dan `docker logs ws-rag-api | tail`. Groq sebagai provider utama menghindari OOM.
- **Internal DNS gagal** (`NameResolutionError` ke `ws-qdrant`/`ws-postgres`) — container
  mendapat resolv.conf "bentuk-B" (nameserver eksternal); force-recreate sekali untuk
  memulihkan embedded DNS (`127.0.0.11`). Lihat postmortem S-4.

Detail insiden: [`docs/ops-postmortem.md`](docs/ops-postmortem.md).
