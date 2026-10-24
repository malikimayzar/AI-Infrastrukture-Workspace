#!/bin/bash
# Backup all databases (PostgreSQL and Qdrant)
#
# Usage:
#   ./scripts/backup_all.sh [--local] [--s3]
#
# This script runs both backup_postgres.sh and backup_qdrant.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[$(date)] Starting full workspace backup..."

# Backup PostgreSQL
echo "[$(date)] === PostgreSQL Backup ==="
"$SCRIPT_DIR/backup_postgres.sh" "$@"

# Backup Qdrant
echo "[$(date)] === Qdrant Backup ==="
"$SCRIPT_DIR/backup_qdrant.sh" "$@"

echo "[$(date)] Full workspace backup completed successfully"
