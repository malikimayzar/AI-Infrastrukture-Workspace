#!/usr/bin/env bash
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/scripts" "$tmp/gitdirs"
cp "$workspace_root/scripts/check_secrets.sh" "$tmp/scripts/check_secrets.sh"
git -C "$tmp" init -q
git -C "$tmp" config user.name "Secret Scanner Test"
git -C "$tmp" config user.email "scanner-test@example.invalid"

printf '%s\n' 'GROQ_API_KEY=gsk_your_actual_key_here' > "$tmp/.env.example"
git -C "$tmp" add scripts/check_secrets.sh .env.example
git -C "$tmp" commit -qm "initialize scanner fixture"

for repo in arxiv-research-assistant mcp-gateway rag-research llm-eval-framework; do
  mkdir -p "$tmp/$repo"
  git init -q --separate-git-dir="$tmp/gitdirs/$repo.git" "$tmp/$repo"
  git -C "$tmp/$repo" config user.name "Secret Scanner Test"
  git -C "$tmp/$repo" config user.email "scanner-test@example.invalid"
  printf '%s\n' 'GROQ_API_KEY=gsk_your_actual_key_here' > "$tmp/$repo/.env.example"
  git -C "$tmp/$repo" add .env.example
  git -C "$tmp/$repo" commit -qm "initialize submodule fixture"
done

clean_output=$(cd "$tmp" && bash scripts/check_secrets.sh)
case "$clean_output" in
  *"CLEAN"*) ;;
  *) printf 'clean fixture did not pass scanner\n%s\n' "$clean_output" >&2; exit 1 ;;
esac

test_key="gsk_$(printf 'A%.0s' {1..32})"
printf 'credential=%s\n' "$test_key" > "$tmp/rag-research/leak.txt"
git -C "$tmp/rag-research" add leak.txt

set +e
leak_output=$(cd "$tmp" && bash scripts/check_secrets.sh 2>&1)
leak_status=$?
set -e

if [ "$leak_status" -eq 0 ]; then
  echo "scanner missed a tracked submodule credential" >&2
  exit 1
fi
case "$leak_output" in
  *"rag-research/leak.txt"*) ;;
  *) printf 'scanner did not identify the submodule file\n%s\n' "$leak_output" >&2; exit 1 ;;
esac
case "$leak_output" in
  *"$test_key"*) echo "scanner output exposed the fixture value" >&2; exit 1 ;;
esac

echo "secret scanner fixture checks passed"
