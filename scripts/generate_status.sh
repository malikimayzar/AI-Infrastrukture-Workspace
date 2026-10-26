#!/usr/bin/env bash
# Generate STATUS.md from executed checks.
#
# Read-only by design:
#   - does not start/stop containers
#   - does not read .env contents
#   - does not commit or push
#   - writes only STATUS.md (and optional JSON)
#
# Usage:
#   bash scripts/generate_status.sh                # fast checks (collect-only)
#   bash scripts/generate_status.sh --full         # also run the test suites
#   bash scripts/generate_status.sh --no-network   # skip HTTP health probes
#   bash scripts/generate_status.sh --json out.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/STATUS.md"
JSON_OUT=""
FULL=0
NETWORK=1
STRICT=0

usage() {
  cat <<'EOF'
Generate STATUS.md from executed checks.

Options:
  --full         Also run the four test suites (slower)
  --no-network   Skip HTTP health probes
  --out PATH     Output Markdown path (default: STATUS.md)
  --json PATH    Also write a machine-readable JSON report
  --strict       Exit 1 when any check is FAIL (useful for CI)
  -h, --help     Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --full)       FULL=1; shift ;;
    --no-network) NETWORK=0; shift ;;
    --out)        OUT="$2"; shift 2 ;;
    --json)       JSON_OUT="$2"; shift 2 ;;
    --strict)     STRICT=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROWS="$(mktemp)"
cleanup() { rm -f "$ROWS"; }
trap cleanup EXIT

row() {
  local section="$1" check="$2" status="$3" evidence="${4:-}"
  evidence="${evidence//$'\t'/ }"
  evidence="${evidence//$'\n'/ }"
  printf '%s\t%s\t%s\t%s\n' "$section" "$check" "$status" "$evidence" >> "$ROWS"
}

have() { command -v "$1" >/dev/null 2>&1; }

PYTHON_BIN="python3"
if [ -x "$ROOT/venv/bin/python" ]; then
  PYTHON_BIN="$ROOT/venv/bin/python"
fi

count_pytest() {
  local dir="$1"
  local out n
  out=$(cd "$ROOT/$dir" && timeout 240 env PYTHONPATH=. "$PYTHON_BIN" -m pytest tests/ -q --collect-only 2>&1) || true
  n=$(printf '%s\n' "$out" | grep -oE '[0-9]+ tests? collected' | grep -oE '[0-9]+' | tail -1)
  if [ -n "${n:-}" ]; then
    printf '%s' "$n"
  else
    printf '?'
  fi
}

count_go_tests() {
  local dir="$1"
  local out n
  out=$(cd "$ROOT/$dir" && timeout 300 go test ./... -list '.*' 2>&1) || true
  n=$(printf '%s\n' "$out" | grep -cE '^Test' || true)
  printf '%s' "$n"
}

run_make_target() {
  local target="$1" label="$2"
  local log summary
  log="$(mktemp)"
  if timeout 1200 make -s "$target" >"$log" 2>&1; then
    summary=$(grep -oE '[0-9]+ passed[^)]*' "$log" | tail -1 || true)
    row "Build & Tests" "$label" "PASS" "make $target ${summary:-ok}"
  else
    summary=$(grep -E 'FAILED|Error|error:' "$log" | tail -1 || true)
    row "Build & Tests" "$label" "FAIL" "make $target gagal ${summary:-}"
  fi
  rm -f "$log"
}

# ──────────────────────────────────────────────────────────────────────
# Metadata
# ──────────────────────────────────────────────────────────────────────

row "_meta" "generated_at" "INFO" "$(date -Iseconds)"
row "_meta" "commit" "INFO" "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
row "_meta" "branch" "INFO" "$(git branch --show-current 2>/dev/null || echo unknown)"
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
row "_meta" "working_tree" "INFO" "${dirty} perubahan"
row "_meta" "generator" "INFO" "scripts/generate_status.sh"

# ──────────────────────────────────────────────────────────────────────
# Repository
# ──────────────────────────────────────────────────────────────────────

tags=$(git tag 2>/dev/null | wc -l | tr -d ' ')
if [ "$tags" -gt 0 ]; then
  row "Repository" "Release tags" "PASS" "$tags tag"
else
  row "Repository" "Release tags" "WARN" "0 tag — hasil tidak dapat direproduksi dari rilis"
fi

default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@')
if [ -z "${default_branch:-}" ]; then
  default_branch=$(git config --get init.defaultBranch 2>/dev/null || echo master)
fi
row "Repository" "Default branch" "INFO" "$default_branch"

ci_branches=$(grep -rhoE 'branches:[[:space:]]*\[[^]]+\]' .github/workflows 2>/dev/null | sort -u | tr '\n' ' ' || true)
if [ -n "${ci_branches:-}" ]; then
  if printf '%s' "$ci_branches" | grep -q "$default_branch"; then
    row "Repository" "CI trigger cocok dengan default branch" "PASS" "$ci_branches"
  else
    row "Repository" "CI trigger cocok dengan default branch" "FAIL" "CI: $ci_branches | default: $default_branch"
  fi
else
  row "Repository" "CI trigger" "SKIP" "tidak ada workflow"
fi

subs=$(git submodule status 2>/dev/null | wc -l | tr -d ' ')
if [ "$subs" -gt 0 ]; then
  dirty_subs=$(git submodule status 2>/dev/null | grep -cE '^[+-]' || true)
  if [ "$dirty_subs" -eq 0 ]; then
    row "Repository" "Submodule sinkron" "PASS" "$subs submodule"
  else
    row "Repository" "Submodule sinkron" "WARN" "$subs submodule, $dirty_subs belum sinkron"
  fi
else
  row "Repository" "Submodule" "SKIP" "tidak ada .gitmodules"
fi

# ──────────────────────────────────────────────────────────────────────
# Build & Tests
# ──────────────────────────────────────────────────────────────────────

if have go; then
  n=$(count_go_tests "arxiv-research-assistant/go-backend")
  if [ "$n" = "?" ] || [ "$n" = "0" ]; then
    row "Build & Tests" "arxiv Go — collected" "WARN" "tidak dapat menghitung test"
  else
    row "Build & Tests" "arxiv Go — collected" "PASS" "$n test"
  fi
  n=$(count_go_tests "mcp-gateway")
  if [ "$n" = "?" ] || [ "$n" = "0" ]; then
    row "Build & Tests" "mcp-gateway — collected" "WARN" "tidak dapat menghitung test"
  else
    row "Build & Tests" "mcp-gateway — collected" "PASS" "$n test"
  fi
else
  row "Build & Tests" "Go" "SKIP" "go tidak tersedia"
fi

if have "$PYTHON_BIN" || have python3; then
  n=$(count_pytest "arxiv-research-assistant/python-ml")
  if [ "$n" = "?" ]; then
    row "Build & Tests" "arxiv python-ml — collected" "WARN" "collect gagal"
  else
    row "Build & Tests" "arxiv python-ml — collected" "PASS" "$n test"
  fi
  n=$(count_pytest "llm-eval-framework")
  if [ "$n" = "?" ]; then
    row "Build & Tests" "llm-eval — collected" "WARN" "collect gagal"
  else
    row "Build & Tests" "llm-eval — collected" "PASS" "$n test"
  fi
  n=$(count_pytest "rag-research")
  if [ "$n" = "?" ]; then
    row "Build & Tests" "rag-research — collected" "WARN" "collect gagal"
  else
    row "Build & Tests" "rag-research — collected" "PASS" "$n test"
  fi
else
  row "Build & Tests" "Python" "SKIP" "python tidak tersedia"
fi

if [ "$FULL" -eq 1 ]; then
  run_make_target test-arxiv "arxiv Go — run"
  run_make_target test-arxiv-ml "arxiv python-ml — run"
  run_make_target test-mcp "mcp-gateway — run"
  run_make_target test-eval "llm-eval — run"
  run_make_target test-rag "rag-research — run"
else
  row "Build & Tests" "Test suite penuh" "SKIP" "jalankan dengan --full untuk mengeksekusi"
fi

# ──────────────────────────────────────────────────────────────────────
# Runtime (compose only; never start/stop)
# ──────────────────────────────────────────────────────────────────────

if have docker; then
  if docker compose config --quiet >/dev/null 2>&1; then
    services=$(docker compose config --services 2>/dev/null | wc -l | tr -d ' ')
    profile_services=$(docker compose --profile monitoring --profile mcp-stdio config --services 2>/dev/null | wc -l | tr -d ' ')
    row "Runtime" "Compose valid" "PASS" "$services core; $profile_services dengan profile"
  else
    row "Runtime" "Compose valid" "FAIL" "docker compose config gagal"
  fi
else
  row "Runtime" "Docker" "SKIP" "docker tidak tersedia"
fi

if [ "$NETWORK" -eq 1 ] && have curl; then
  check_health() {
    local name="$1" url="$2"
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      row "Runtime" "$name" "PASS" "$url"
    else
      row "Runtime" "$name" "INFO" "$url tidak merespons (mungkin tidak berjalan)"
    fi
  }
  check_health "mcp-gateway" "http://localhost:8090/health"
  check_health "arxiv-go-backend" "http://localhost:8080/health"
  check_health "arxiv-python-ml" "http://localhost:8001/health"
  check_health "llm-eval-framework" "http://localhost:8002/health"
  check_health "rag-api" "http://localhost:8000/health"
else
  row "Runtime" "Health probe" "SKIP" "--no-network atau curl tidak tersedia"
fi

# ──────────────────────────────────────────────────────────────────────
# Calibration
# ──────────────────────────────────────────────────────────────────────

model="$ROOT/rag-research/models/calibration_isotonic.joblib"
if [ -f "$model" ]; then
  size=$(stat -c%s "$model" 2>/dev/null || echo 0)
  row "Calibration" "Model file" "PASS" "calibration_isotonic.joblib (${size} bytes)"
  info=$("$PYTHON_BIN" - "$model" <<'PY' 2>/dev/null || true
import sys
try:
    import joblib
except Exception as exc:
    print(f"joblib_unavailable={type(exc).__name__}")
    raise SystemExit(0)
try:
    obj = joblib.load(sys.argv[1])
except Exception as exc:
    print(f"load_error={type(exc).__name__}")
    raise SystemExit(0)
if isinstance(obj, dict):
    print(f"method={obj.get('method')} fitted={obj.get('fitted')} samples={len(obj.get('samples', []))}")
else:
    print(f"loaded_type={type(obj).__name__}")
PY
)
  case "${info:-}" in
    method=*) row "Calibration" "Model dapat dimuat" "PASS" "$info" ;;
    "")       row "Calibration" "Model dapat dimuat" "WARN" "loader tidak mengembalikan info" ;;
    *)        row "Calibration" "Model dapat dimuat" "WARN" "$info" ;;
  esac
else
  row "Calibration" "Model file" "FAIL" "rag-research/models/calibration_isotonic.joblib tidak ditemukan"
fi

if grep -qE '^COPY .*models|fit_calibration\.py' rag-research/Dockerfile 2>/dev/null; then
  if grep -qE '^COPY .*models' rag-research/Dockerfile 2>/dev/null; then
    row "Calibration" "Image menyediakan models/" "PASS" "COPY models/ ditemukan"
  else
    row "Calibration" "Image menyediakan models/" "PASS" "model di-fit saat build (fit_calibration.py)"
  fi
else
  row "Calibration" "Image menyediakan models/" "FAIL" "tidak ada COPY models/ atau fit saat build — container akan fallback"
fi

if grep -qE 'CALIBRATION_METHOD|CALIBRATION_MODEL_PATH' docker-compose.yml 2>/dev/null; then
  names=$(grep -oE 'CALIBRATION_[A-Z_]+' docker-compose.yml | sort -u | tr '\n' ' ')
  row "Calibration" "Compose punya env kalibrasi" "PASS" "$names"
else
  row "Calibration" "Compose punya env kalibrasi" "FAIL" "tidak ada variabel CALIBRATION_*"
fi

if [ -f .env.example ] && grep -qE 'CALIBRATION_METHOD|CALIBRATION_MODEL_PATH' .env.example 2>/dev/null; then
  names=$(grep -oE 'CALIBRATION_[A-Z_]+' .env.example | sort -u | tr '\n' ' ')
  row "Calibration" ".env.example punya variabel kalibrasi" "PASS" "$names"
else
  row "Calibration" ".env.example punya variabel kalibrasi" "FAIL" "tidak ada variabel CALIBRATION_*"
fi

"$PYTHON_BIN" - "$ROOT" "$ROWS" <<'PY'
import json
import os
import sys

root, rows_path = sys.argv[1], sys.argv[2]

def add(check, status, evidence):
    evidence = str(evidence).replace("\t", " ").replace("\n", " ")
    with open(rows_path, "a", encoding="utf-8") as handle:
        handle.write(f"Calibration\t{check}\t{status}\t{evidence}\n")

model_path = os.path.join(root, "rag-research/models/calibration_isotonic.joblib")
data_path = os.path.join(root, "rag-research/data/evaluation/calibration_dataset.json")
if not (os.path.exists(model_path) and os.path.exists(data_path)):
    add("Model vs dataset", "SKIP", "model atau dataset tidak ada")
    raise SystemExit(0)

try:
    import joblib

    payload = joblib.load(model_path)
    model_samples = len(payload.get("samples", []))
except Exception as exc:
    add("Model vs dataset", "WARN", f"model tidak dapat dibaca: {type(exc).__name__}")
    raise SystemExit(0)

try:
    dataset_rows = json.load(open(data_path, encoding="utf-8")).get("total_samples")
except Exception as exc:
    add("Model vs dataset", "WARN", f"dataset tidak dapat dibaca: {type(exc).__name__}")
    raise SystemExit(0)

if model_samples == dataset_rows:
    add("Model vs dataset", "PASS", f"{model_samples} sampel = {dataset_rows} baris dataset")
else:
    add(
        "Model vs dataset",
        "FAIL",
        f"model dilatih pada {model_samples} sampel, dataset punya {dataset_rows} baris — refit diperlukan",
    )
PY

if have docker && docker inspect ws-rag-api >/dev/null 2>&1; then
  if docker exec ws-rag-api test -f /app/models/calibration_isotonic.joblib >/dev/null 2>&1; then
    row "Calibration" "Container punya model" "PASS" "/app/models/calibration_isotonic.joblib ada"
  else
    row "Calibration" "Container punya model" "FAIL" "file tidak ada di container — runtime fallback"
  fi
  container_logs=$(docker logs ws-rag-api 2>&1 || true)
  if [ "$(printf '%s\n' "$container_logs" | grep -c 'Calibration model loaded')" -gt 0 ]; then
    row "Calibration" "Container memuat model" "PASS" "log startup: Calibration model loaded"
  else
    row "Calibration" "Container memuat model" "WARN" "tidak ada log 'Calibration model loaded'"
  fi
else
  row "Calibration" "Container memuat model" "SKIP" "ws-rag-api tidak berjalan"
fi

# ──────────────────────────────────────────────────────────────────────
# Datasets
# ──────────────────────────────────────────────────────────────────────

"$PYTHON_BIN" - "$ROOT" "$ROWS" <<'PY'
import json
import os
import sys

root, rows_path = sys.argv[1], sys.argv[2]

def add(check, status, evidence):
    evidence = str(evidence).replace("\t", " ").replace("\n", " ")
    with open(rows_path, "a", encoding="utf-8") as handle:
        handle.write(f"Datasets\t{check}\t{status}\t{evidence}\n")

path = os.path.join(root, "rag-research/data/evaluation/calibration_dataset.json")
if not os.path.exists(path):
    add("Calibration dataset", "FAIL", "file tidak ditemukan")
    raise SystemExit(0)

try:
    data = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    add("Calibration dataset", "FAIL", f"JSON tidak valid: {type(exc).__name__}")
    raise SystemExit(0)

samples = data.get("samples", [])
queries = [str(item.get("query", "")).strip().lower() for item in samples]
unique = len(set(queries))
duplicates = len(samples) - unique
missing_label = sum(1 for item in samples if not isinstance(item.get("is_supported"), bool))
errors = sum(1 for item in samples if str(item.get("raw_decision", "")).upper() == "ERROR")
declared = data.get("total_samples")
excluded = data.get("excluded_samples", [])
missing_reason = sum(1 for item in excluded if not str(item.get("exclusion_reason", "")).strip())
gt_present = sum(1 for item in samples if str(item.get("ground_truth", "")).strip())

# Repeated queries are expected in a calibration set; what matters is whether
# the repeats agree on the label. Count queries whose repeats disagree.
by_query = {}
for item in samples:
    key = str(item.get("query", "")).strip().lower()
    by_query.setdefault(key, set()).add(bool(item.get("is_supported")))
label_conflicts = [key for key, labels in by_query.items() if len(labels) > 1]

# Off-domain patterns are deliberate negative probes. They are only a problem
# when the dataset labels one of them as supported.
off_domain_probes = [
    str(item.get("query", ""))
    for item in samples
    if any(
        word in str(item.get("query", "")).lower()
        for word in ("weather", "harry potter", "faucet", "world cup", "capital of")
    )
]
off_domain_supported = [
    str(item.get("query", ""))
    for item in samples
    if item.get("is_supported") is True
    and any(
        word in str(item.get("query", "")).lower()
        for word in ("weather", "harry potter", "faucet", "world cup", "capital of")
    )
]

add("Rows", "INFO", f"{len(samples)} baris (declared {declared})")

if declared == len(samples):
    add("Jumlah baris cocok", "PASS", f"{len(samples)} = declared {declared}")
else:
    add("Jumlah baris cocok", "FAIL", f"{len(samples)} baris != declared {declared}")

if excluded:
    status = "PASS" if missing_reason == 0 else "WARN"
    evidence = f"{len(excluded)} baris dikeluarkan dari fitting"
    if missing_reason:
        evidence += f", {missing_reason} tanpa exclusion_reason"
    add("Baris dikeluarkan", status, evidence)
else:
    add("Baris dikeluarkan", "INFO", "tidak ada")

if missing_label:
    add("Label is_supported", "FAIL", f"{missing_label}/{len(samples)} baris tanpa label boolean")
else:
    add("Label is_supported", "PASS", f"{len(samples)}/{len(samples)} berlabel")

if duplicates == 0:
    add("Unique queries", "PASS", f"{unique} unik")
elif label_conflicts:
    add(
        "Unique queries",
        "FAIL",
        f"{unique} unik, {duplicates} duplikat, {len(label_conflicts)} query berlabel bertentangan",
    )
else:
    add(
        "Unique queries",
        "WARN",
        f"{unique} unik, {duplicates} duplikat, 0 konflik label (bias kalibrasi)",
    )

if errors == 0:
    add("Baris ERROR", "PASS", "0")
else:
    add("Baris ERROR", "FAIL", f"{errors} baris ERROR — bug pipeline, bukan label")

if not off_domain_probes:
    add("Probe negatif off-domain", "INFO", "tidak ada")
elif off_domain_supported:
    sample = "; ".join(off_domain_supported[:3])
    add(
        "Probe negatif off-domain",
        "FAIL",
        f"{len(off_domain_supported)} probe berlabel supported — periksa: {sample}",
    )
else:
    add(
        "Probe negatif off-domain",
        "PASS",
        f"{len(off_domain_probes)} probe, semuanya is_supported=false (disengaja)",
    )

add(
    "ground_truth (opsional)",
    "INFO",
    f"{gt_present}/{len(samples)} baris punya teks referensi; label utama = is_supported",
)
PY

# ──────────────────────────────────────────────────────────────────────
# MCP
# ──────────────────────────────────────────────────────────────────────

if [ -f mcp-gateway/internal/mcp/handler.go ]; then
  row "MCP" "HTTP handler" "PASS" "internal/mcp/handler.go ada"
else
  row "MCP" "HTTP handler" "FAIL" "internal/mcp/handler.go tidak ditemukan"
fi

if [ -d mcp-gateway/cmd/mcp-stdio-adapter ]; then
  if git -C mcp-gateway ls-files --error-unmatch cmd/mcp-stdio-adapter/main.go >/dev/null 2>&1; then
    row "MCP" "stdio adapter" "PASS" "ada dan tracked"
  else
    row "MCP" "stdio adapter" "WARN" "ada di working tree tetapi belum tracked"
  fi
else
  row "MCP" "stdio adapter" "FAIL" "cmd/mcp-stdio-adapter tidak ditemukan"
fi

if grep -q "not implemented yet" mcp-gateway/README.md 2>/dev/null && \
   grep -qi "stdio transport implemented" docs/mcp-integration-guide.md 2>/dev/null; then
  row "MCP" "Konsistensi dokumen" "FAIL" "README bilang belum, integration guide bilang sudah"
else
  row "MCP" "Konsistensi dokumen" "PASS" "tidak ada kontradiksi terdeteksi"
fi

if grep -rq "text/event-stream" mcp-gateway/internal/mcp 2>/dev/null; then
  row "MCP" "SSE (kode)" "WARN" "kode ada; perilaku streaming belum diverifikasi"
else
  row "MCP" "SSE (kode)" "FAIL" "text/event-stream tidak ditemukan"
fi

# ──────────────────────────────────────────────────────────────────────
# Security
# ──────────────────────────────────────────────────────────────────────

if [ -f scripts/check_secrets.sh ]; then
  if bash scripts/check_secrets.sh >/dev/null 2>&1; then
    row "Security" "Secret scan" "PASS" "scripts/check_secrets.sh bersih"
  else
    row "Security" "Secret scan" "FAIL" "temuan — jalankan make check-secrets"
  fi
else
  row "Security" "Secret scan" "SKIP" "scripts/check_secrets.sh tidak ditemukan"
fi

if git check-ignore -q .env 2>/dev/null; then
  row "Security" ".env di-gitignore" "PASS" ".env tidak akan ter-commit"
else
  row "Security" ".env di-gitignore" "FAIL" ".env tidak di-ignore"
fi

if [ -f docs/security/2026-10-24-groq-key-exposure.md ]; then
  if grep -qi "revocation pending" docs/security/2026-10-24-groq-key-exposure.md; then
    row "Security" "Groq key revocation" "FAIL" "dokumen insiden masih menyatakan revocation pending"
  else
    row "Security" "Groq key revocation" "PASS" "tidak ada status pending di dokumen insiden"
  fi
else
  row "Security" "Groq key revocation" "SKIP" "dokumen insiden tidak ditemukan"
fi

bins=""
if git -C mcp-gateway ls-files --error-unmatch server >/dev/null 2>&1; then
  size=$(stat -c%s mcp-gateway/server 2>/dev/null || echo 0)
  bins="$bins server=$((size / 1024 / 1024))MB"
fi
if [ -n "$bins" ]; then
  row "Security" "Binary tracked" "FAIL" "tracked:$bins"
else
  row "Security" "Binary tracked" "PASS" "tidak ada binary besar yang tracked"
fi

if [ -f mcp-gateway/server_new ] && ! git -C mcp-gateway check-ignore -q server_new 2>/dev/null; then
  size=$(stat -c%s mcp-gateway/server_new 2>/dev/null || echo 0)
  row "Security" "Binary untracked" "WARN" "server_new=$((size / 1024 / 1024))MB, tidak di-ignore"
fi

# ──────────────────────────────────────────────────────────────────────
# Documentation
# ──────────────────────────────────────────────────────────────────────

"$PYTHON_BIN" - "$ROOT" "$ROWS" <<'PY'
import os
import re
import sys

root, rows_path = sys.argv[1], sys.argv[2]

def add(check, status, evidence):
    evidence = str(evidence).replace("\t", " ").replace("\n", " ")
    with open(rows_path, "a", encoding="utf-8") as handle:
        handle.write(f"Documentation\t{check}\t{status}\t{evidence}\n")

skip_dirs = {
    ".git", "node_modules", "venv", ".venv", "hf-cache", "__pycache__",
    ".pytest_cache", "archive", "dist", "build", ".next", ".mypy_cache",
}
link_re = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
broken = []
count = 0

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [name for name in dirnames if name not in skip_dirs]
    for filename in filenames:
        if not filename.endswith(".md"):
            continue
        count += 1
        path = os.path.join(dirpath, filename)
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for match in link_re.finditer(text):
            target = match.group(1).strip()
            if not target or target.startswith(("http://", "https://", "mailto:", "#", "tel:")):
                continue
            target = target.split(" ")[0].strip("<>").split("#")[0]
            if not target:
                continue
            if target.startswith("/"):
                resolved = os.path.join(root, target.lstrip("/"))
            else:
                resolved = os.path.normpath(os.path.join(dirpath, target))
            if not os.path.exists(resolved):
                broken.append(f"{os.path.relpath(path, root)} -> {target}")

add("Jumlah file .md", "INFO", str(count))
if broken:
    sample = "; ".join(broken[:8])
    add("Link internal rusak", "WARN", f"{len(broken)} link; contoh: {sample}")
else:
    add("Link internal rusak", "PASS", "0 link rusak")

readme = os.path.join(root, "README.md")
architecture = os.path.join(root, "docs/ARCHITECTURE.md")
if os.path.exists(architecture):
    add("README -> docs/ARCHITECTURE.md", "PASS", "target ada")
elif os.path.exists(readme) and "docs/ARCHITECTURE.md" in open(readme, encoding="utf-8", errors="ignore").read():
    add("README -> docs/ARCHITECTURE.md", "FAIL", "dirujuk tetapi file tidak ada")
else:
    add("README -> docs/ARCHITECTURE.md", "PASS", "tidak dirujuk")

status_docs = [
    path for path in (
        "PROJECT_CONTEXT.md",
        "docs/ROADMAP.md",
        "docs/IMPLEMENTATION_STATUS.md",
        "STATUS.md",
    )
    if os.path.exists(os.path.join(root, path))
]
if len(status_docs) > 1:
    add("Dokumen status ganda", "WARN", ", ".join(status_docs))
else:
    add("Dokumen status tunggal", "PASS", ", ".join(status_docs) or "tidak ada")
PY

# ──────────────────────────────────────────────────────────────────────
# Quality gates
# ──────────────────────────────────────────────────────────────────────

"$PYTHON_BIN" - "$ROOT" "$ROWS" <<'PY'
import glob
import json
import os
import sys

root, rows_path = sys.argv[1], sys.argv[2]

def add(check, status, evidence):
    evidence = str(evidence).replace("\t", " ").replace("\n", " ")
    with open(rows_path, "a", encoding="utf-8") as handle:
        handle.write(f"Quality Gates\t{check}\t{status}\t{evidence}\n")

pattern = os.path.join(root, "rag-research/results/metrics/archive/phase1_smoke_v3_*.json")
files = sorted(glob.glob(pattern), key=os.path.getmtime)
if not files:
    add("Phase 1 smoke (v3)", "SKIP", "tidak ada artefak")
else:
    latest = files[-1]
    try:
        data = json.load(open(latest, encoding="utf-8"))
        summary = data.get("summary", {})
        passed = summary.get("phase1_pass") is True and summary.get("human_review_complete") is True
        evidence = (
            f"{os.path.basename(latest)} "
            f"phase1_pass={summary.get('phase1_pass')} "
            f"human_review_complete={summary.get('human_review_complete')}"
        )
        add("Phase 1 smoke (v3)", "PASS" if passed else "FAIL", evidence)
    except Exception as exc:
        add("Phase 1 smoke (v3)", "WARN", f"gagal parse: {type(exc).__name__}")

calibration_reports = glob.glob(
    os.path.join(root, "rag-research/results/**/*calibrat*"), recursive=True
)
report_path = os.path.join(root, "rag-research/models/calibration_report.json")
if os.path.exists(report_path):
    try:
        report = json.load(open(report_path, encoding="utf-8"))
        methods = ", ".join(sorted(report.get("methods", {})))
        add(
            "Laporan kalibrasi",
            "PASS",
            f"models/calibration_report.json n={report.get('n_samples')} ({methods})",
        )
    except Exception as exc:
        add("Laporan kalibrasi", "WARN", f"report tidak dapat dibaca: {type(exc).__name__}")
elif calibration_reports:
    add("Laporan kalibrasi", "PASS", f"{len(calibration_reports)} artefak di results/")
else:
    add("Laporan kalibrasi", "WARN", "tidak ada artefak laporan terpisah")
PY

# ──────────────────────────────────────────────────────────────────────
# Render
# ──────────────────────────────────────────────────────────────────────

"$PYTHON_BIN" - "$ROWS" "$OUT" "$JSON_OUT" <<'PY'
import json
import sys

rows_path, out_path, json_path = sys.argv[1], sys.argv[2], sys.argv[3]

meta = {}
rows = []
for line in open(rows_path, encoding="utf-8"):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 4:
        continue
    section, check, status, evidence = parts[0], parts[1], parts[2], parts[3]
    if section == "_meta":
        meta[check] = evidence
    else:
        rows.append((section, check, status, evidence))

order = [
    "Repository",
    "Build & Tests",
    "Runtime",
    "Calibration",
    "Datasets",
    "MCP",
    "Security",
    "Documentation",
    "Quality Gates",
]
sections = [name for name in order if any(row[0] == name for row in rows)]
for row in rows:
    if row[0] not in sections:
        sections.append(row[0])

icons = {
    "PASS": "✅ PASS",
    "WARN": "⚠️ WARN",
    "FAIL": "❌ FAIL",
    "SKIP": "⏭️ SKIP",
    "INFO": "ℹ️ INFO",
}
counts = {key: 0 for key in icons}
for row in rows:
    counts[row[2]] = counts.get(row[2], 0) + 1

def esc(value):
    return str(value).replace("|", "\\|")

lines = []
lines.append("# Project Status\n")
lines.append(f"> **Generated:** {meta.get('generated_at', '?')}  ")
lines.append(f"> **Commit:** {meta.get('commit', '?')}  ")
lines.append(f"> **Branch:** {meta.get('branch', '?')}  ")
lines.append(f"> **Working tree:** {meta.get('working_tree', '?')}\n")
lines.append("> File ini di-generate oleh `scripts/generate_status.sh` dari eksekusi nyata.")
lines.append("> Jangan edit manual — jalankan ulang generatornya.\n")
lines.append("## Ringkasan\n")
lines.append("| Status | Jumlah |")
lines.append("|---|---:|")
for key in ("PASS", "WARN", "FAIL", "SKIP", "INFO"):
    lines.append(f"| {icons[key]} | {counts.get(key, 0)} |")
lines.append("")
lines.append(
    "**Cara membaca:** PASS = diverifikasi oleh eksekusi; WARN = perlu perhatian; "
    "FAIL = klaim belum didukung; SKIP = prasyarat tidak tersedia; INFO = konteks.\n"
)
lines.append(
    "**Build & Tests** secara default hanya menghitung test yang terkumpul; "
    "jalankan `--full` untuk benar-benar mengeksekusi suite.\n"
)

for section in sections:
    lines.append(f"## {section}\n")
    lines.append("| Check | Status | Evidence |")
    lines.append("|---|---|---|")
    for row in rows:
        if row[0] != section:
            continue
        evidence = esc(row[3]) if row[3] else "—"
        lines.append(f"| {esc(row[1])} | {icons.get(row[2], row[2])} | {evidence} |")
    lines.append("")

gaps = [row for row in rows if row[2] in ("FAIL", "WARN")]
lines.append("## Gap yang perlu ditutup\n")
if gaps:
    for row in gaps:
        lines.append(f"- **{row[0]} / {row[1]}** ({row[2]}): {row[3]}")
else:
    lines.append("- Tidak ada.")
lines.append("")
lines.append("---")
lines.append("*Regenerate: `make status-report` atau `bash scripts/generate_status.sh`.*")

with open(out_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")

if json_path:
    payload = {
        "meta": meta,
        "counts": counts,
        "rows": [
            {"section": row[0], "check": row[1], "status": row[2], "evidence": row[3]}
            for row in rows
        ],
    }
    with open(json_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
PY

if [ -t 1 ]; then
  echo "STATUS.md generated: $OUT"
  [ -n "$JSON_OUT" ] && echo "JSON generated: $JSON_OUT"
fi

if [ "$STRICT" -eq 1 ]; then
  fails=$(grep -c $'\tFAIL\t' "$ROWS" 2>/dev/null || true)
  if [ "${fails:-0}" -gt 0 ]; then
    echo "STRICT: ${fails} FAIL ditemukan" >&2
    exit 1
  fi
fi
