# Neo4j Backup System Architecture

## Why This Matters
Neo4j Community Edition requires complete database shutdown for consistent backups, making sophisticated orchestration critical for production Graphiti deployments.

## The Episode Approach
Backups capture the complete temporal state of your knowledge graph, including all episodes, extracted entities, relationships, and temporal metadata required for fact invalidation.

## Architecture Deep Dive

### Three-Tier Backup Strategy
```yaml
# docker-compose.backup.yml structure
services:
  backup-daily:
    image: offen/docker-volume-backup:v2.43.0
    environment:
      BACKUP_STOP_DURING_BACKUP_LABEL: neo4j-graphiti  # Graceful shutdown
      BACKUP_STOP_SERVICE_TIMEOUT: 20m                  # Episode processing time
      
  backup-weekly:
    profiles: [backup]  # Activated via --profile flag
    environment:
      BACKUP_COMPRESSION: zst  # Better compression for longer retention
      
  backup-monthly:
    environment:
      BACKUP_ARCHIVE_DELETE_IF_OLDER_THAN_DAYS: 365
      BACKUP_PRUNING_PREFIX: neo4j-monthly-
```

### Memory Forensics Integration
```bash
# Pre-backup hook captures heap state
if [ $(check_heap_usage) -gt 85 ]; then
    docker exec neo4j-graphiti jcmd 1 GC.heap_dump /data/dumps/pre-backup.hprof
fi

# Post-backup verification
verify_backup_includes_episodes() {
    tar -tzf $BACKUP | grep "databases/neo4j/transactions" || alert "Missing episode data!"
}
```

### Episode Data Preservation

Critical paths in backups:
```
backup.tar.gz/
├── data/
│   ├── databases/
│   │   └── neo4j/
│   │       ├── store/           # Entity and relationship storage
│   │       ├── schema/          # Graphiti indices
│   │       └── transactions/    # Episode processing state
│   ├── dumps/                   # Heap dumps for forensics
│   └── dbms/                    # Authentication and metadata
└── logs/
    ├── debug.log                # Episode processing logs
    └── gc.log                   # Memory pressure indicators
```

## Observability

### Langfuse Correlation
```python
# Track backup operations in Langfuse
from langfuse.decorators import observe

@observe(name="backup_operation")
async def backup_with_tracing(backup_type: str):
    # Capture pre-backup episode count
    episode_count = await graphiti.get_episode_count()
    
    # Perform backup
    result = subprocess.run(["./scripts/backup.sh", backup_type])
    
    # Log to Langfuse
    langfuse.score(
        name="backup_success",
        value=1 if result.returncode == 0 else 0,
        metadata={
            "episode_count": episode_count,
            "backup_size_mb": get_backup_size() / 1024 / 1024,
            "duration_seconds": result.duration
        }
    )
```

### Prometheus Metrics
```prometheus
# Key backup metrics exposed on :2004
neo4j_backup_last_success_timestamp{tier="daily"} 1708934400
neo4j_backup_size_bytes{tier="weekly"} 536870912
neo4j_backup_duration_seconds{tier="monthly"} 45.2
neo4j_backup_episodes_count{tier="daily"} 15234
```

## Performance Impact

### Backup Duration Analysis
| Episodes | Shutdown | Compression | Total Time |
|----------|----------|-------------|------------|
| 1,000    | 5s       | 10s         | 15s        |
| 10,000   | 15s      | 30s         | 45s        |
| 100,000  | 45s      | 120s        | 165s       |
| 1,000,000| 120s     | 600s        | 720s       |

### Memory Considerations
```bash
# Pre-backup memory optimization
docker exec neo4j-graphiti cypher-shell -u neo4j -p $PASSWORD \
  "CALL db.checkpoint()" # Flush to disk

# Episode batch processing pause
BACKUP_PAUSE_EPISODE_PROCESSING=true  # Prevent OOM during backup
```

## Common Issues

### Episode Loss During Backup
```bash
# Verify episode preservation
docker run --rm -v backup.tar.gz:/backup.tar.gz:ro alpine \
  tar -tzf /backup.tar.gz | grep -c "episode" || echo "WARNING: No episodes found"

# Check transaction logs
tar -xzf backup.tar.gz --to-stdout data/databases/neo4j/transactions/
```

### Restore Performance Optimization
```bash
# Warm cache after restore
docker exec neo4j-graphiti cypher-shell -u neo4j -p $PASSWORD \
  "MATCH (e:Episode) RETURN count(e)" # Force episode loading

# Rebuild Graphiti indices
python -c "
from graphiti_core import Graphiti
client = Graphiti('bolt://localhost:7687', 'neo4j', password)
await client.build_indices_and_constraints()
"
```

### External Drive Sync Strategy
```bash
# Intelligent sync with deduplication
rsync -av --link-dest=$PREV_BACKUP \
  ~/Neo4jBackups/daily/latest.tar.gz \
  /Volumes/SanDisk/Neo4jBackups/daily/

# Verify episode integrity on external
diff <(tar -tzf ~/Neo4jBackups/daily/latest.tar.gz | grep Episode) \
     <(tar -tzf /Volumes/SanDisk/Neo4jBackups/daily/latest.tar.gz | grep Episode)
```

## Advanced Recovery Procedures

### Partial Episode Recovery
```python
# Recover specific episode range
async def recover_episodes(start_date, end_date, backup_file):
    # Extract only episode data
    subprocess.run([
        "tar", "-xzf", backup_file,
        "--wildcards", "*/Episode*",
        "--after-date", start_date,
        "--before-date", end_date
    ])
    
    # Re-process through Graphiti
    for episode in extracted_episodes:
        await graphiti.add_episode(
            episode_body=episode.content,
            source=episode.type,
            reference_time=episode.timestamp
        )
```

### Disaster Recovery Matrix
| Scenario | Recovery Method | Episode Loss | Downtime |
|----------|----------------|--------------|----------|
| Corrupt store files | Restore from daily | <24 hours | 5 min |
| OOM crash | Restore + heap analysis | None | 10 min |
| Disk failure | External drive restore | <1 hour | 15 min |
| Complete loss | Monthly archive | <30 days | 30 min |

## Next Steps
- [Memory Forensics Guide](../performance/memory-forensics-guide.md)
- [Episode Engineering Patterns](../episodes/episode-design-patterns.md)
- [Performance Tuning](../performance/jvm-for-python-developers.md)