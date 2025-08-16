# Neo4j for Graphiti on OrbStack

Optimized Neo4j setup for multiple Graphiti-powered AI agents running locally on macOS.

## Quick Start

```bash
# Start Neo4j
docker-compose up -d

# Check health
docker-compose ps
docker logs neo4j-graphiti

# Access Neo4j Browser
open http://localhost:7474
# or via OrbStack domain
open http://neo4j.graphiti.local:7474
```

## Connection Details

- **Bolt URI**: `bolt://localhost:7687`
- **OrbStack Domain**: `bolt://neo4j.graphiti.local:7687`
- **Username**: `neo4j`
- **Password**: See `.env` file

## Features

- ✅ Optimized for personal use (4GB heap + 6GB page cache)
- ✅ OrbStack custom domains for reliable networking
- ✅ Persistent data with named volumes
- ✅ Automatic health checks and restarts
- ✅ Query logging for debugging
- ✅ Simple backup script

## Backup & Restore

```bash
# Run backup
./scripts/backup.sh

# Backups are stored in ./backups/
# Automatically keeps last 7 days
```

## Memory Configuration

Optimized for 36GB RAM system:
- **Heap**: 4GB (initial and max)
- **Page Cache**: 6GB
- **Total Neo4j**: ~10GB
- **Remaining for OS/Apps**: ~26GB

## Monitoring

```bash
# View logs
docker logs -f neo4j-graphiti

# Check memory usage
docker stats neo4j-graphiti

# Access metrics
curl http://localhost:7474/db/neo4j/cluster/overview
```

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs neo4j-graphiti

# Verify OrbStack is running
orbctl status

# Reset if needed
docker-compose down -v
docker-compose up -d
```

### Connection issues
- Use `localhost:7687` for local connections
- Use `neo4j.graphiti.local:7687` for OrbStack domain
- Ensure firewall allows ports 7474 and 7687

### Memory issues
- Adjust heap/pagecache in `docker-compose.yml`
- Monitor with `docker stats`

## Integration with Graphiti

Your Graphiti configuration should use:
```python
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=<your-password>
```

## Notes

- Single shared database for all agents (no group_id separation)
- No APOC/GDS plugins (not needed for Graphiti)
- Data persists in Docker named volumes
- OrbStack provides optimized performance on macOS