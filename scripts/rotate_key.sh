#!/usr/bin/env bash
# scripts/rotate_key.sh — safe Groq API-key rotation for this workspace.
#
# Alur (dilengkapi langsung dari TODO P0):
#   1. Validasi kunci SECARA LANGSUNG ke Groq (list models) — kunci buruk tidak pernah
#      menyentuh .env.
#   2. Tulis ulang `GROQ_API_KEY=` di .env (tanpa kutip; idempotent).
#   3. Recreate HANYA tiga service yang mengkonsumsi kunci (mcp-gateway, rag-api,
#      arxiv-python-ml) — infrastruktur (postgres/qdrant/ollama/…) tidak diganggu.
#   4. Konfirmasi per-container dengan prefix yang di-mask.
#
# Pemakaian:
#   KEY=gsk_xxx make rotate-key          # rotasi penuh
#   KEY=gsk_xxx make rotate-key DRY=1    # validasi sahaja, .env tidak diubah
#
# Satu-satunya tempat kunci adalah .env (root) — gitignored sengaja, tidak di-commit.
# File *.env.example hanya boleh memuat placeholder (dipaksa scripts/check_secrets.sh).
set -euo pipefail

KEY="${KEY:-}"
DRY="${DRY:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"

fail() { echo "❌ rotate-key: $*" >&2; exit 1; }

[ -n "$KEY" ] || fail "KEY tidak diisi — pemakaian: KEY=gsk_xxx make rotate-key"
[[ "$KEY" =~ ^gsk_[A-Za-z0-9]{30,}$ ]] || fail \
  "format key salah — harus ^gsk_[A-Za-z0-9]{30,}\$ (tanpa kutip, tanpa whitespace)"

[ -f "$ENV_FILE" ] || fail "$ENV_FILE tidak ditemukan"

echo "─ [1/4] Validasi live kunci ke Groq …"
code=$(curl -s --max-time 20 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $KEY" https://api.groq.com/openai/v1/models)
[ "$code" = "200" ] || fail "key ditolak Groq (HTTP $code) — cek nilai/kutipan/kadaluwarsa"
echo "       ✅ key valid (HTTP 200)"

if [ "$DRY" = "1" ]; then
  echo "DRY-RUN: .env dan container tidak diubah. Jalankan lagi tanpa DRY=1 untuk rotasi nyata."
  exit 0
fi

echo "─ [2/4] Tulis ulang .env …"
if grep -q '^GROQ_API_KEY=' "$ENV_FILE"; then
  sed -i "s|^GROQ_API_KEY=.*|GROQ_API_KEY=$KEY|" "$ENV_FILE"
else
  printf '\nGROQ_API_KEY=%s\n' "$KEY" >> "$ENV_FILE"
fi
mask=$(echo "gsk_$(echo "$KEY" | cut -c5-8)***")
echo "       ✅ ditulis: GROQ_API_KEY=$mask (tanpa kutip)"

echo "─ [3/4] Recreate konsumen kunci (tanpa menyentuh infrastruktur) …"
cd "$ROOT"
docker compose --env-file "$ENV_FILE" up -d --force-recreate --no-deps --no-build \
  mcp-gateway rag-api arxiv-python-ml >/dev/null \
  || fail "compose recreate gagal — jalankan manual: docker compose --env-file .env up -d --force-recreate mcp-gateway rag-api arxiv-python-ml"
echo "       ✅ 3 service direcreate"

echo "─ [4/4] Konfirmasi injeksi di dalam container (ter-mask) …"
sleep 3
for c in ws-mcp-gateway ws-rag-api ws-arxiv-python-ml; do
  if v=$(docker exec "$c" sh -c 'printf %s "${GROQ_API_KEY:0:8}"' 2>/dev/null); then
    l=$(docker exec "$c" sh -c 'echo ${#GROQ_API_KEY}')
    echo "       $c → ${v}… len=$l (window diharapkan len=${#KEY})"
  else
    echo "       $c → (exec belum siap) — cek manual: docker exec $c sh -c 'echo \${#GROQ_API_KEY}'"
  fi
done

echo "🎉 rotasi selesai. Verifikasi penuh: make smoke-e2e"
