#!/bin/bash
# Backup Qdrant vector database from ws-qdrant container
#
# Usage:
#   ./scripts/backup_qdrant.sh [--local] [--s3]
#   --local: Save to local backup directory (default: ./backups/qdrant/)
#   --s3: Upload to S3 (requires AWS credentials)
#
# Cron example (daily at 3 AM):
#   0 3 * * * cd /path/to/ai-infra-workspace && ./scripts/backup_qdrant.sh >> /var/log/qdrant-backup.log 2>&1

set -e

# Configuration
CONTAINER_NAME="${CONTAINER_NAME:-ws-qdrant}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
QDRANT_URL="${QDRANT_URL:-http://localhost:${QDRANT_PORT}}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/qdrant/snapshots}"
BACKUP_DIR="${BACKUP_DIR:-./backups/qdrant}"
LOCAL_BACKUP="${LOCAL_BACKUP:-true}"
S3_BACKUP="${S3_BACKUP:-false}"
S3_BUCKET="${S3_BUCKET:-ai-infra-backups}"
S3_PREFIX="qdrant"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_BACKUP="true"
            shift
            ;;
        --s3)
            S3_BACKUP="true"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

for cmd in docker curl jq gzip sha256sum; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: required command not found: $cmd"
        exit 1
    fi
done

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="qdrant_backup_${TIMESTAMP}"

echo "[$(date)] Starting Qdrant backup..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[$(date)] ERROR: Container ${CONTAINER_NAME} is not running"
    exit 1
fi

# Create a full-storage snapshot. The /collections/_all endpoint does not
# exist; full snapshots are created and listed at /snapshots.
echo "[$(date)] Creating Qdrant snapshot..."
if ! BACKUP_RESPONSE=$(curl -sSf -X POST "${QDRANT_URL}/snapshots" \
    -H "Content-Type: application/json"); then
    echo "[$(date)] ERROR: Failed to create snapshot"
    exit 1
fi

# Extract snapshot name and checksum from the response
SNAPSHOT_NAME=$(echo "$BACKUP_RESPONSE" | jq -r '.result.name // empty')
SNAPSHOT_CHECKSUM=$(echo "$BACKUP_RESPONSE" | jq -r '.result.checksum // empty')

if [ -z "$SNAPSHOT_NAME" ]; then
    echo "[$(date)] ERROR: Failed to create snapshot"
    echo "Response: $BACKUP_RESPONSE"
    exit 1
fi

echo "[$(date)] Snapshot created: ${SNAPSHOT_NAME}"

# Copy snapshot from container to local
echo "[$(date)] Copying snapshot from container..."
docker cp "${CONTAINER_NAME}:${SNAPSHOT_DIR}/${SNAPSHOT_NAME}" \
    "${BACKUP_DIR}/${BACKUP_NAME}.snapshot"

# Verify the copied bytes before compressing. Qdrant returns a SHA-256 of the
# snapshot file; a truncated docker cp must not become a silent backup.
if [ -n "$SNAPSHOT_CHECKSUM" ]; then
    ACTUAL_CHECKSUM=$(sha256sum "${BACKUP_DIR}/${BACKUP_NAME}.snapshot" | awk '{print $1}')
    if [ "$ACTUAL_CHECKSUM" != "$SNAPSHOT_CHECKSUM" ]; then
        echo "[$(date)] ERROR: Snapshot checksum mismatch"
        echo "Expected: ${SNAPSHOT_CHECKSUM}"
        echo "Actual:   ${ACTUAL_CHECKSUM}"
        rm -f "${BACKUP_DIR}/${BACKUP_NAME}.snapshot"
        exit 1
    fi
    echo "[$(date)] Checksum verified"
fi

# Compress backup
echo "[$(date)] Compressing backup..."
gzip "${BACKUP_DIR}/${BACKUP_NAME}.snapshot"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.snapshot.gz"

# Verify the archive is readable before reporting success
gzip -t "${BACKUP_FILE}"

# Get file size
FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)

echo "[$(date)] Backup completed: ${BACKUP_FILE} (${FILE_SIZE})"

# Upload to S3 if enabled
if [ "$S3_BACKUP" = "true" ]; then
    echo "[$(date)] Uploading to S3..."
    if command -v aws &> /dev/null; then
        aws s3 cp "${BACKUP_FILE}" "s3://${S3_BUCKET}/${S3_PREFIX}/$(basename "${BACKUP_FILE}")"
        echo "[$(date)] Upload to S3 completed"
    else
        echo "[$(date)] WARNING: AWS CLI not found, skipping S3 upload"
    fi
fi

# Cleanup old backups (local)
echo "[$(date)] Cleaning up local backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "qdrant_backup_*.snapshot.gz" -mtime +"${RETENTION_DAYS}" -delete

# Cleanup old full-storage snapshots in Qdrant. /snapshots returns
# {"result": [{"name": ..., "creation_time": "..."}]}; creation_time is ISO,
# not an epoch, so compare parsed timestamps.
echo "[$(date)] Cleaning up old Qdrant snapshots..."
CUTOFF_EPOCH=$(date -d "${RETENTION_DAYS} days ago" +%s)
if ! SNAPSHOTS_JSON=$(curl -sSf "${QDRANT_URL}/snapshots"); then
    echo "[$(date)] WARNING: Could not list Qdrant snapshots, skipping cleanup"
else
    echo "$SNAPSHOTS_JSON" | jq -r '.result[]? | [.name, .creation_time] | @tsv' |
        while IFS=$'\t' read -r SNAPSHOT CREATED_AT; do
            [ -n "$SNAPSHOT" ] || continue
            CREATED_EPOCH=$(date -d "$CREATED_AT" +%s 2>/dev/null || true)
            if [ -z "$CREATED_EPOCH" ]; then
                echo "[$(date)] WARNING: Could not parse creation_time '${CREATED_AT}' for ${SNAPSHOT}"
                continue
            fi
            if [ "$CREATED_EPOCH" -lt "$CUTOFF_EPOCH" ]; then
                echo "[$(date)] Deleting old snapshot: ${SNAPSHOT}"
                if ! curl -sSf -X DELETE "${QDRANT_URL}/snapshots/${SNAPSHOT}" > /dev/null; then
                    echo "[$(date)] WARNING: Failed to delete snapshot: ${SNAPSHOT}"
                fi
            fi
        done
fi

# Cleanup old backups (S3)
if [ "$S3_BACKUP" = "true" ] && command -v aws &> /dev/null; then
    echo "[$(date)] Cleaning up S3 backups older than ${RETENTION_DAYS} days..."
    CUTOFF_DATE_S3=$(date -d "${RETENTION_DAYS} days ago" +%Y%m%d)
    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | \
        awk '{print $4}' | \
        while read -r file; do
            FILE_DATE=$(echo "$file" | grep -oP 'qdrant_backup_\K\d{8}' || true)
            if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF_DATE_S3" ]; then
                aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/${file}"
                echo "[$(date)] Deleted old S3 backup: ${file}"
            fi
        done
fi

echo "[$(date)] Qdrant backup process completed successfully"
