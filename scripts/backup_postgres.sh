#!/bin/bash
# Backup PostgreSQL database from ws-postgres container
#
# Usage:
#   ./scripts/backup_postgres.sh [--local] [--s3]
#   --local: Save to local backup directory (default: ./backups/postgres/)
#   --s3: Upload to S3 (requires AWS credentials)
#
# Cron example (daily at 2 AM):
#   0 2 * * * cd /path/to/ai-infra-workspace && ./scripts/backup_postgres.sh >> /var/log/postgres-backup.log 2>&1

set -e

# Configuration
CONTAINER_NAME="ws-postgres"
DB_USER="${POSTGRES_USER:-arxiv}"
DB_NAME="${POSTGRES_DB:-arxiv_db}"
BACKUP_DIR="${BACKUP_DIR:-./backups/postgres}"
LOCAL_BACKUP="${LOCAL_BACKUP:-true}"
S3_BACKUP="${S3_BACKUP:-false}"
S3_BUCKET="${S3_BUCKET:-ai-infra-backups}"
S3_PREFIX="postgres"
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
BACKUP_FILE="${BACKUP_DIR}/postgres_backup_${TIMESTAMP}.sql"

echo "[$(date)] Starting PostgreSQL backup..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[$(date)] ERROR: Container ${CONTAINER_NAME} is not running"
    exit 1
fi

# Perform backup
echo "[$(date)] Dumping database to ${BACKUP_FILE}..."
docker exec "${CONTAINER_NAME}" pg_dump -U "${DB_USER}" "${DB_NAME}" > "${BACKUP_FILE}"

# Compress backup
echo "[$(date)] Compressing backup..."
gzip "${BACKUP_FILE}"
BACKUP_FILE="${BACKUP_FILE}.gz"

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
find "${BACKUP_DIR}" -name "postgres_backup_*.sql.gz" -mtime +${RETENTION_DAYS} -delete

# Cleanup old backups (S3)
if [ "$S3_BACKUP" = "true" ] && command -v aws &> /dev/null; then
    echo "[$(date)] Cleaning up S3 backups older than ${RETENTION_DAYS} days..."
    CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y%m%d)
    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" | \
        awk '{print $4}' | \
        while read -r file; do
            FILE_DATE=$(echo "$file" | grep -oP 'postgres_backup_\K\d{8}')
            if [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
                aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/${file}"
                echo "[$(date)] Deleted old S3 backup: ${file}"
            fi
        done
fi

echo "[$(date)] PostgreSQL backup process completed successfully"
