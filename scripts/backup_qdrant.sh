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
CONTAINER_NAME="ws-qdrant"
QDRANT_PORT="${QDRANT_PORT:-6333}"
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

# Create backup via Qdrant API
echo "[$(date)] Creating Qdrant snapshot..."
BACKUP_RESPONSE=$(curl -s -X PUT "http://localhost:${QDRANT_PORT}/collections/_all/snapshots" \
    -H "Content-Type: application/json")

# Extract snapshot name from response
SNAPSHOT_NAME=$(echo "$BACKUP_RESPONSE" | jq -r '.name // empty')

if [ -z "$SNAPSHOT_NAME" ]; then
    echo "[$(date)] ERROR: Failed to create snapshot"
    echo "Response: $BACKUP_RESPONSE"
    exit 1
fi

echo "[$(date)] Snapshot created: ${SNAPSHOT_NAME}"

# Copy snapshot from container to local
echo "[$(date)] Copying snapshot from container..."
docker cp "${CONTAINER_NAME}:/qdrant/storage/collections/_snapshots/${SNAPSHOT_NAME}" \
    "${BACKUP_DIR}/${BACKUP_NAME}.snapshot"

# Compress backup
echo "[$(date)] Compressing backup..."
gzip "${BACKUP_DIR}/${BACKUP_NAME}.snapshot"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.snapshot.gz"

# Get file size
FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)

echo "[$(date)] Backup completed: ${BACKUP_FILE} (${FILE_SIZE})"

# Upload to S3 if enabled
if [ "$S3_BACKUP" = "true" ]; then
    echo "[$(date)] Uploading to S3..."
    if command -v aws &> /dev/null; then
        aws s3 cp "${BACKUP_FILE}" "s3://${S3_BUCKET}/${S3_PREFIX}/$(basename ${BACKUP_FILE})"
        echo "[$(date)] Upload to S3 completed"
    else
        echo "[$(date)] WARNING: AWS CLI not found, skipping S3 upload"
    fi
fi

# Cleanup old backups (local)
echo "[$(date)] Cleaning up local backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "qdrant_backup_*.snapshot.gz" -mtime +${RETENTION_DAYS} -delete

# Cleanup old snapshots in Qdrant
echo "[$(date)] Cleaning up old Qdrant snapshots..."
CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%s)
SNAPSHOTS=$(curl -s "http://localhost:${QDRANT_PORT}/collections/_all/snapshots" | jq -r '.[] | select(.creation_time < '$CUTOFF_DATE') | .name')

for SNAPSHOT in $SNAPSHOTS; do
    echo "[$(date)] Deleting old snapshot: ${SNAPSHOT}"
    curl -s -X DELETE "http://localhost:${QDRANT_PORT}/collections/_all/snapshots/${SNAPSHOT}"
done

# Cleanup old backups (S3)
if [ "$S3_BACKUP" = "true" ] && command -v aws &> /dev/null; then
    echo "[$(date)] Cleaning up S3 backups older than ${RETENTION_DAYS} days..."
    CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y%m%d)
    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | \
        awk '{print $4}' | \
        while read -r file; do
            FILE_DATE=$(echo "$file" | grep -oP 'qdrant_backup_\K\d{8}')
            if [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
                aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/${file}"
                echo "[$(date)] Deleted old S3 backup: ${file}"
            fi
        done
fi

echo "[$(date)] Qdrant backup process completed successfully"
