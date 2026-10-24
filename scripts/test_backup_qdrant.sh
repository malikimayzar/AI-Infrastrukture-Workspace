#!/usr/bin/env bash
# Regression test for scripts/backup_qdrant.sh.
#
# The script previously called the non-existent
# /collections/_all/snapshots endpoint and copied from a path Qdrant does not
# use. This fixture stubs docker/curl so the API calls and copy source are
# asserted without touching a live database.
set -euo pipefail

workspace_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/backups"
snapshot_name="full-snapshot-2026-10-24-17-00-00.snapshot"
old_snapshot_name="full-snapshot-2026-10-01-03-00-00.snapshot"
printf 'snapshot payload\n' > "$tmp/snapshot_payload"
checksum=$(sha256sum "$tmp/snapshot_payload" | awk '{print $1}')

cat > "$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
case "$1" in
  ps)
    echo "ws-qdrant"
    ;;
  cp)
    src=$2
    dest=$3
    case "$src" in
      "ws-qdrant:/qdrant/snapshots/"*) ;;
      *)
        echo "unexpected docker cp source: $src" >&2
        exit 1
        ;;
    esac
    cp "$FAKE_SNAPSHOT_PAYLOAD" "$dest"
    ;;
  *)
    echo "unexpected docker command: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin/docker"

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_CURL_LOG"

method=GET
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X)
      method=$2
      shift 2
      ;;
    -H)
      shift 2
      ;;
    -s|-sS|-f|-sf|-sSf)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done

case "$method $url" in
  "POST http://localhost:6333/snapshots")
    printf '{"result":{"name":"%s","creation_time":"2026-10-24T17:00:00","size":17,"checksum":"%s"},"status":"ok"}\n' \
      "$FAKE_SNAPSHOT_NAME" "$FAKE_SNAPSHOT_CHECKSUM"
    ;;
  "GET http://localhost:6333/snapshots")
    printf '{"result":[{"name":"%s","creation_time":"2026-10-24T17:00:00"},{"name":"%s","creation_time":"2026-10-01T03:00:00"}],"status":"ok"}\n' \
      "$FAKE_SNAPSHOT_NAME" "$FAKE_OLD_SNAPSHOT_NAME"
    ;;
  "DELETE http://localhost:6333/snapshots/"*)
    printf '{"status":"ok"}\n'
    ;;
  *)
    echo "unexpected curl call: $method $url" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/bin/curl"

export PATH="$tmp/bin:$PATH"
export FAKE_DOCKER_LOG="$tmp/docker.log"
export FAKE_CURL_LOG="$tmp/curl.log"
export FAKE_SNAPSHOT_PAYLOAD="$tmp/snapshot_payload"
export FAKE_SNAPSHOT_NAME="$snapshot_name"
export FAKE_OLD_SNAPSHOT_NAME="$old_snapshot_name"
export FAKE_SNAPSHOT_CHECKSUM="$checksum"
export BACKUP_DIR="$tmp/backups"
export RETENTION_DAYS=7

if ! bash "$workspace_root/scripts/backup_qdrant.sh" --local > "$tmp/backup.log" 2>&1; then
  echo "backup script failed:" >&2
  cat "$tmp/backup.log" >&2
  exit 1
fi

backup_file=$(find "$tmp/backups" -name 'qdrant_backup_*.snapshot.gz' -print -quit)
if [ -z "$backup_file" ]; then
  echo "no compressed backup was produced" >&2
  cat "$tmp/backup.log" >&2
  exit 1
fi

gzip -t "$backup_file"
if ! gzip -dc "$backup_file" | cmp -s - "$tmp/snapshot_payload"; then
  echo "compressed backup does not match the snapshot payload" >&2
  exit 1
fi

if ! grep -q 'POST http://localhost:6333/snapshots' "$tmp/curl.log"; then
  echo "full-storage snapshot endpoint was not called" >&2
  cat "$tmp/curl.log" >&2
  exit 1
fi
if grep -q 'collections/_all' "$tmp/curl.log"; then
  echo "legacy /collections/_all snapshot endpoint was called" >&2
  cat "$tmp/curl.log" >&2
  exit 1
fi
if ! grep -q "ws-qdrant:/qdrant/snapshots/$snapshot_name" "$tmp/docker.log"; then
  echo "snapshot was not copied from the Qdrant snapshot directory" >&2
  cat "$tmp/docker.log" >&2
  exit 1
fi
if ! grep -q "DELETE http://localhost:6333/snapshots/$old_snapshot_name" "$tmp/curl.log"; then
  echo "expired Qdrant snapshot was not deleted" >&2
  cat "$tmp/curl.log" >&2
  exit 1
fi
if grep -q "DELETE http://localhost:6333/snapshots/$snapshot_name" "$tmp/curl.log"; then
  echo "fresh Qdrant snapshot was deleted" >&2
  cat "$tmp/curl.log" >&2
  exit 1
fi

echo "qdrant backup fixture checks passed"
