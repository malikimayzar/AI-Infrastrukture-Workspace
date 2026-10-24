# Backup & Restore Guide

## Overview

This workspace provides automated backup scripts for PostgreSQL and Qdrant databases. Backups can be stored locally or uploaded to S3 for offsite storage.

## Quick Start

### Manual Backup

```bash
# Backup PostgreSQL only
make backup-postgres

# Backup Qdrant only
make backup-qdrant

# Backup both databases
make backup-all
```

### Automated Backup (Cron)

Add to crontab (`crontab -e`):

```bash
# Daily PostgreSQL backup at 2 AM
0 2 * * * cd /path/to/ai-infra-workspace && ./scripts/backup_postgres.sh >> /var/log/postgres-backup.log 2>&1

# Daily Qdrant backup at 3 AM
0 3 * * * cd /path/to/ai-infra-workspace && ./scripts/backup_qdrant.sh >> /var/log/qdrant-backup.log 2>&1

# Full backup daily at 4 AM
0 4 * * * cd /path/to/ai-infra-workspace && ./scripts/backup_all.sh >> /var/log/full-backup.log 2>&1
```

## Configuration

### Environment Variables

Set these in `.env` or export before running:

```bash
# Backup directory (default: ./backups/)
BACKUP_DIR=/path/to/backups

# Retention policy in days (default: 7)
RETENTION_DAYS=30

# S3 configuration (optional)
S3_BACKUP=true
S3_BUCKET=ai-infra-backups
```

### Script Options

```bash
# Local backup only
./scripts/backup_postgres.sh --local

# S3 upload only
./scripts/backup_postgres.sh --s3

# Both local and S3
./scripts/backup_postgres.sh --local --s3
```

## Backup Locations

### Local Storage

- PostgreSQL: `./backups/postgres/postgres_backup_YYYYMMDD_HHMMSS.sql.gz`
- Qdrant: `./backups/qdrant/qdrant_backup_YYYYMMDD_HHMMSS.snapshot.gz`

### S3 Storage

- PostgreSQL: `s3://ai-infra-backups/postgres/postgres_backup_YYYYMMDD_HHMMSS.sql.gz`
- Qdrant: `s3://ai-infra-backups/qdrant/qdrant_backup_YYYYMMDD_HHMMSS.snapshot.gz`

## Restore Procedures

### PostgreSQL Restore

```bash
# Stop the service
docker compose stop arxiv-go-backend arxiv-python-ml

# Drop existing database (WARNING: destructive)
docker exec -i ws-postgres psql -U arxiv -d arxiv_db -c "DROP DATABASE arxiv_db;"
docker exec -i ws-postgres psql -U arxiv -d postgres -c "CREATE DATABASE arxiv_db;"

# Restore from backup
gunzip -c backups/postgres/postgres_backup_YYYYMMDD_HHMMSS.sql.gz | \
    docker exec -i ws-postgres psql -U arxiv -d arxiv_db

# Restart services
docker compose start arxiv-go-backend arxiv-python-ml
```

### Qdrant Restore

```bash
# Copy snapshot to container
docker cp backups/qdrant/qdrant_backup_YYYYMMDD_HHMMSS.snapshot.gz \
    ws-qdrant:/tmp/snapshot.gz

# Restore via API (replace with your collection name)
curl -X PUT "http://localhost:6333/collections/{collection_name}/snapshots/recover" \
    -H "Content-Type: application/json" \
    -d '{"location": "/tmp/snapshot.gz"}'
```

## Backup Script Details

### backup_postgres.sh

- Uses `pg_dump` to create SQL dump
- Compresses with gzip
- Supports local and S3 storage
- Automatic cleanup of old backups (configurable retention)
- Checks container health before backup

### backup_qdrant.sh

- Uses Qdrant snapshot API
- Copies snapshot from container
- Compresses with gzip
- Supports local and S3 storage
- Automatic cleanup of old snapshots
- Checks container health before backup

### backup_all.sh

- Wrapper script that runs both backup_postgres.sh and backup_qdrant.sh
- Passes all arguments to child scripts
- Useful for unified backup scheduling

## Monitoring

### Check Backup Status

```bash
# List recent backups
ls -lht backups/postgres/
ls -lht backups/qdrant/

# Check backup logs
tail -f /var/log/postgres-backup.log
tail -f /var/log/qdrant-backup.log
```

### Verify Backup Integrity

```bash
# PostgreSQL: test SQL dump validity
gunzip -t backups/postgres/postgres_backup_YYYYMMDD_HHMMSS.sql.gz

# Qdrant: verify snapshot format
file backups/qdrant/qdrant_backup_YYYYMMDD_HHMMSS.snapshot.gz
```

## Disaster Recovery Checklist

In case of data loss:

1. **Stop all services**: `make down`
2. **Restore PostgreSQL**: Follow restore procedure above
3. **Restore Qdrant**: Follow restore procedure above
4. **Verify data**: Run smoke test `make smoke-e2e`
5. **Start services**: `make up`
6. **Monitor logs**: `make logs`

## Best Practices

1. **Schedule regular backups**: Daily minimum, hourly for critical data
2. **Test restores regularly**: Verify backup integrity monthly
3. **Use offsite storage**: S3 or similar for disaster recovery
4. **Monitor backup logs**: Set up alerts for backup failures
5. **Document restore procedures**: Keep this guide accessible
6. **Encrypt backups**: Use S3 server-side encryption or local encryption
7. **Version control backup scripts**: Track changes to backup procedures

## Troubleshooting

### Backup fails with "container not running"

```bash
# Check service status
make status

# Start services if needed
make up
```

### S3 upload fails

```bash
# Check AWS credentials
aws s3 ls

# Verify bucket exists
aws s3 ls s3://ai-infra-backups

# Check IAM permissions
```

### Disk space issues

```bash
# Check disk usage
make df

# Clean up old backups manually
find backups/ -name "*.gz" -mtime +30 -delete

# Prune Docker cache
make prune-builder
```

### PostgreSQL restore fails

```bash
# Check database exists
docker exec ws-postgres psql -U arxiv -l

# Check connection
docker exec ws-postgres pg_isready -U arxiv

# Check logs
docker logs ws-postgres
```

## Security Considerations

1. **Backups contain sensitive data**: Encrypt at rest and in transit
2. **Restrict backup directory permissions**: `chmod 700 backups/`
3. **Use IAM roles for S3**: Avoid hardcoded AWS credentials
4. **Audit backup access**: Log who accesses backup files
5. **Secure .env file**: Contains database credentials
