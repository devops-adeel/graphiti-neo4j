# Backup & Recovery Guide

## Why This Matters
Your Graphiti knowledge graph contains valuable temporal data about customer interactions, product information, and business insights. Regular backups ensure you never lose this critical information.

## The Episode Approach
Backups preserve your entire episode history - every conversation, product update, and temporal fact that your AI agents have learned.

## Quick Start

### Enable Automatic Backups
```bash
# Start automated backup services (runs daily at 2 AM)
make backup-start

# Check backup status
make backup-status
```

### Create Manual Backup
```bash
# Create an immediate backup
make backup

# The backup will be saved to ~/Neo4jBackups/manual/
```

### Restore from Backup
```bash
# Interactive restore wizard
make backup-restore

# Follow the prompts to:
# 1. Select backup tier (daily/weekly/monthly)
# 2. Choose specific backup or latest
# 3. Confirm restoration
```

## Backup Schedule

Your system automatically creates:
- **Daily backups**: Every night at 2 AM (kept for 7 days)
- **Weekly backups**: Sunday at 3 AM (kept for 4 weeks)  
- **Monthly backups**: 1st of month at 4 AM (kept for 1 year)

## Observability
Monitor your backups in real-time:
```bash
# View backup logs
docker logs neo4j-backup-daily

# Check backup metrics
curl http://localhost:2004/metrics | grep backup
```

## Performance Impact
- Backups require brief Neo4j shutdown (typically 30-60 seconds)
- Scheduled during low-activity hours (2-4 AM)
- External drive sync happens automatically when available

## Common Issues

### Backup Failed
```bash
# Check disk space
df -h ~/Neo4jBackups

# Verify Neo4j is running
docker ps | grep neo4j-graphiti

# Run emergency backup if needed
make backup-emergency
```

### Restore Not Working
```bash
# Verify backup integrity first
./scripts/verify-backup.sh quick daily

# Check Neo4j logs after restore
docker logs neo4j-graphiti
```

## Next Steps
- [Memory Configuration Guide](../dev/performance/memory-configuration.md)
- [Disaster Recovery Procedures](../dev/architecture/backup-system.md)
- [Monitoring with Langfuse](./monitoring-with-langfuse.md)