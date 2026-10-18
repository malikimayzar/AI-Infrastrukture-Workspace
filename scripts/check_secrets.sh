#!/usr/bin/env bash
# scripts/check_secrets.sh — sweep rahasia yang bocor (kotak TODO P0 §4).
#
# Memeriksa, berurutan:
#   A. Prefiks kunci yang diketahui kompromi (riwayat insiden workspace ini —
#      keduanya pernah menyentuh working tree dan WAJIB dianggap terbakar).
#   B. Pola kunci Groq generik `gsk_` + ≥30 alnum di SEMUA file yang di-track
#      (root repo + 4 submodule — mereka adalah repos git terpisah).
#   C. `GROQ_API_KEY=` di setiap `*.env.example` yang di-track hanya boleh
#      berupa placeholder ("your"/"placeholder"/kosong), bukan nil asli.
#
# Catatan desain: file untracked (mis. `.env`) TIDAK ikut di-scan — memang
# itu satu-satunya rumah kunci yang diizinkan, dan git-ignored.
#
# Keluar: 0 = bersih, 1 = ditemukan kebocoran (sinkron untuk CI nanti).
set -uo pipefail

leak=0
repos=(. arxiv-research-assistant mcp-gateway rag-research llm-eval-framework)

echo "── [A] Prefiks kunci yang diketahui kompromi (terpotong, bukan utuh)"
# Dulu kedua kunci disimpan UTUH di sini — ironi "file pembersih berisi rahasia"
# yang membuat scanner menandai dirinya sendiri. Sekarang cukup prefiks panjang
# (~16 char, tidak bisa verifikasi/pakai); file ini dikecualikan dari pencarian.
for k in \
  gsk_Ud7hTCDlhDS26xX \
  gsk_BGTGwh89Z2GesV
do
  hit=$(git grep -n "$k" -- . ':(exclude)scripts/check_secrets.sh' 2>/dev/null || true)
  for r in "${repos[@]}"; do
    [ "$r" != "." ] || continue
    hit="$hit
$(git -C "$r" grep -n "$k" -- . 2>/dev/null | sed "s|^|$r/|" || true)"
  done
  if [ -n "$(echo "$hit" | tr -d '[:space:]')" ]; then
    echo "$hit" | grep -v '^$' | sed 's/^/   ❌ /'
    echo "   ❌ KUNCI KOMPROMI MASIH ADA DI GIT — revoke + hapus dari file + history!"
    leak=1
  fi
done
[ "$leak" = "0" ] && echo "   ✓ bersih"

echo "── [B] Pola generik gsk_<30+alnum> di file yang di-track"
pat='gsk_[A-Za-z0-9]{30,}'
for r in "${repos[@]}"; do
  if [ "$r" = "." ]; then
    found=$(git ls-files -z | xargs -0 -r grep -lE "$pat" -I 2>/dev/null || true)
  else
    [ -d "$r/.git" ] || continue
    found=$(git -C "$r" ls-files -z | xargs -0 -r grep -lE "$pat" -I 2>/dev/null || true)
  fi
  if [ -n "$found" ]; then
    printf '%s\n' "$found" | while IFS= read -r f; do
      echo "   ❌ $r/$f"
      grep -nE "$pat" -I "$f" 2>/dev/null |
        sed 's/gsk_[A-Za-z0-9]\{6\}[A-Za-z0-9]*/gsk_****REDACTED****/g' | head -3
    done
    leak=1
  fi
done
[ "$leak" = "0" ] && echo "   ✓ bersih"

echo "── [C] *.env.example hanya boleh placeholder"
placeholders=$(git ls-files '**/.env.example' '*.env.example' 2>/dev/null || true)
for r in "${repos[@]}"; do
  [ "$r" != "." ] || continue
  [ -d "$r/.git" ] || continue
  p=$(git -C "$r" ls-files '**/.env.example' '*.env.example' 2>/dev/null | sed "s|^|$r/|" || true)
  if [ -n "$p" ]; then
    placeholders="${placeholders:+$placeholders$'\n'}$p"
  fi
done
if [ -z "$placeholders" ]; then
  echo "   ⚠️  tidak ada *.env.example yang di-track"
else
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    val=$(grep -E '^GROQ_API_KEY=' "$f" 2>/dev/null | head -1 | cut -d= -f2-)
    case "$val" in
      *your*|*YOUR*|*placeholder*|*PLACEHOLDER*|"")
        echo "   ✓ $f ($(echo "${val:-empty}" | cut -c1-24))";;
      *)
        echo "   ❌ $f memuat nilai asli → WAJIB di-placeholder"
        leak=1;;
    esac
  done <<< "$placeholders"
fi

echo "──────"
if [ "$leak" = "0" ]; then
  echo "✅ CLEAN — tidak ada rahasia di file yang di-track"
  exit 0
fi
echo "❌ LEAK DITEMUKAN ($leak) — putar/revoke kunci sebelum di-commit"
exit 1
