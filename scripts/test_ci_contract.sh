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
