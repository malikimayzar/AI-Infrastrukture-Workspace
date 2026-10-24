#!/usr/bin/env bash
# Scan tracked files in the workspace and its submodules for credential leaks.
# Untracked local .env files are intentionally excluded.
set -euo pipefail

repos=(. arxiv-research-assistant mcp-gateway rag-research llm-eval-framework)
leak=0
pat='gsk_[A-Za-z0-9]{30,}'

echo "── [A] Known compromised key prefixes"
known_prefixes=(
  'gsk_Ud7hTCDlhDS26xX'
  'gsk_BGTGwh89Z2GesV'
)
for repo in "${repos[@]}"; do
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  for prefix in "${known_prefixes[@]}"; do
    if [ "$repo" = "." ]; then
      found=$(git -C "$repo" grep -lF "$prefix" -- . ':(exclude)scripts/check_secrets.sh' 2>/dev/null || true)
    else
      found=$(git -C "$repo" grep -lF "$prefix" -- . 2>/dev/null || true)
    fi
    if [ -n "$found" ]; then
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        printf '   ❌ %s/%s contains a known compromised prefix\n' "$repo" "$file"
      done <<< "$found"
      leak=1
    fi
  done
done
[ "$leak" -eq 0 ] && echo "   ✓ no known compromised prefixes"

echo "── [B] Generic Groq key pattern in tracked files"
for repo in "${repos[@]}"; do
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  mapfile -d '' -t found < <(git -C "$repo" grep -IlzE "$pat" -- . 2>/dev/null || true)
  if [ "${#found[@]}" -gt 0 ]; then
    for file in "${found[@]}"; do
      printf '   ❌ %s/%s contains a key-shaped value (value hidden)\n' "$repo" "$file"
    done
    leak=1
  fi
done
[ "$leak" -eq 0 ] && echo "   ✓ no key-shaped values"

echo "── [C] GROQ_API_KEY in tracked *.env.example files"
for repo in "${repos[@]}"; do
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  mapfile -d '' -t examples < <(
    git -C "$repo" ls-files -z -- '*.env.example' '**/*.env.example' 2>/dev/null || true
  )
  for file in "${examples[@]}"; do
    [ -n "$file" ] || continue
    path="$repo/$file"
    value=$(sed -n 's/^GROQ_API_KEY=//p' "$path" 2>/dev/null | head -n 1 || true)
    normalized=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
      ""|*your*|*placeholder*|*changeme*|*change_me*)
        printf '   ✓ %s uses a placeholder\n' "$path"
        ;;
      *)
        printf '   ❌ %s must use a placeholder (value hidden)\n' "$path"
        leak=1
        ;;
    esac
  done
done

echo "──────"
if [ "$leak" -eq 0 ]; then
  echo "✅ CLEAN — no tracked credential leaks found"
  exit 0
fi
echo "❌ LEAK FOUND — revoke exposed keys and replace values before committing"
exit 1
