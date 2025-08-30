# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🚨 CRITICAL MEMORY & SECURITY CHECKS

**ALWAYS RUN BEFORE MAJOR OPERATIONS:**
```bash
# Memory health check
./scripts/monitor_neo4j.sh

# Security scan (pre-commit hooks)
pre-commit run --all-files
```

**Neo4j THREE Memory Regions (ALL can cause OOM):**
1. **Heap Memory** (4GB) - Query execution
2. **Page Cache** (8GB) - File caching  
3. **Transaction Memory** (512MB) - Query state

See `docs/MEMORY_FORENSICS.md` for forensic analysis and troubleshooting.

## Project Context

This is **Neo4j infrastructure for Graphiti-powered AI agents**, not a Graphiti implementation itself. Graphiti is a framework for building temporally-aware knowledge graphs that integrate with Neo4j for graph storage. This setup provides an optimized Neo4j instance for multiple Graphiti agents running locally on macOS with OrbStack.

## Essential Commands

### Docker Operations
```bash
# Start Neo4j with health monitoring
docker-compose up -d
docker logs -f neo4j-graphiti  # Monitor startup (JVM warmup takes ~40s)

# Check health and memory usage
docker stats neo4j-graphiti
docker exec neo4j-graphiti neo4j status

# Access Neo4j Browser
open http://localhost:7474  # or http://neo4j.graphiti.local:7474 (OrbStack)

# Backup database (keeps 7 days retention)
./scripts/backup.sh

# Reset database completely
docker-compose down -v && docker-compose up -d
```

### Testing Commands
```bash
# Test suite with different focuses
./test.sh quick      # Smoke tests: warm cache + basic episode processing
./test.sh search     # Search performance with cold/warm cache comparison
./test.sh concurrent # Multi-agent simultaneous access patterns
./test.sh temporal   # Fact invalidation and temporal ordering
./test.sh reranking  # Proximity-based reranking and BFS algorithms
./test.sh benchmark  # Performance benchmarks only (uses pytest-benchmark)
./test.sh coverage   # Generate coverage report

# Single test run
pytest tests/test_simple_graphiti.py::test_search_performance -v

# Connection validation
python test_connection.py
```

### Development Commands
```bash
# Install test dependencies
pip install -r tests/requirements.txt

# Run specific test categories with markers
pytest tests -m integration -v
pytest tests -m slow -v
pytest tests -m warmup -v
```

## Architecture & Integration

### Neo4j + Graphiti Relationship
- **Neo4j**: JVM-based graph database requiring warmup for optimal performance
- **Graphiti**: Temporal knowledge graph framework that uses Neo4j as storage backend
- **Connection**: Graphiti connects via Bolt protocol (port 7687) to Neo4j
- **Data Model**: Episodes → LLM Processing → Entities & Relationships → Graph Storage

### Episode Processing Types
```python
from graphiti_core.nodes import EpisodeType

# Three episode types with different processing:
EpisodeType.text     # Natural language processing
EpisodeType.json     # Structured data extraction  
EpisodeType.message  # Conversation/dialogue parsing
```

### Search Configuration Recipes
```python
from graphiti_core.search.search_config_recipes import (
    NODE_HYBRID_SEARCH_RRF,              # Reciprocal Rank Fusion
    NODE_HYBRID_SEARCH_EPISODE_MENTIONS  # Episode-weighted search
)

# Use for different search strategies:
await client._search('query', NODE_HYBRID_SEARCH_RRF)  # Better for general search
await client._search('entity', NODE_HYBRID_SEARCH_EPISODE_MENTIONS)  # Better for entity lookup
```

## Memory Configuration

### Current Settings (Optimized for 36GB M3 Pro)
```yaml
# docker-compose.yml
NEO4J_server_memory_heap_initial__size: 4g  # JVM heap (same as max to avoid GC pauses)
NEO4J_server_memory_heap_max__size: 4g      
NEO4J_server_memory_pagecache_size: 8g      # Page cache for graph data
# Total Neo4j: ~12GB, Remaining for OS/Apps: ~24GB
```

### JVM Warmup Characteristics
- **Cold Start**: First queries take 500-1000ms (JVM compilation + cache loading)
- **Warm Cache**: Subsequent queries <100ms (target: >95% cache hit rate)
- **Warmup Strategy**: tests/fixtures/warmup_data.py provides synthetic data for cache priming

### Memory Tuning Guidelines
- **Heap**: Keep at 4GB to avoid long GC pauses (16GB max for systems >56GB RAM)
- **Page Cache**: Size = Store size + expected growth + 10%
- **Formula**: Total RAM = Heap + Page Cache + OS (1-2GB) + Other Apps

## Testing Strategy

### Test Categories & Performance Targets
| Category | Focus | Target Performance | When to Use |
|----------|-------|--------------------|-------------|
| search | Cache performance | <100ms warm cache | Optimizing query performance |
| episode | Data ingestion | <500ms including LLM | Testing data processing |
| concurrent | Multi-agent access | 10+ simultaneous agents | Load testing |
| temporal | Fact invalidation | Consistency guaranteed | Testing temporal logic |
| reranking | Proximity algorithms | <200ms overhead | Tuning result relevance |

### Test Fixtures
- `fixtures/sample_episodes.json`: Real-world episode examples (customers, products, reviews)
- `fixtures/warmup_data.py`: JVM warmup utilities and synthetic data generation
- `conftest.py`: Shared fixtures for Graphiti client initialization

### Integration Test Pattern
```python
# All tests use Graphiti API, never direct Neo4j access
client = Graphiti(uri=NEO4J_URI, user=NEO4J_USER, password=NEO4J_PASSWORD)
await client.build_indices_and_constraints()
await client.add_episode(...)  # Primary data input method
results = await client.search(...)  # Primary retrieval method
```

## OrbStack-Specific Configuration

### Custom Domains
```yaml
# docker-compose.yml
labels:
  dev.orbstack.domains: "neo4j.graphiti.local,graphiti-db.local"
```

### Network Configuration
- Bolt: `bolt://neo4j.graphiti.local:7687` (alternative to localhost)
- Browser: `http://neo4j.graphiti.local:7474`
- Subnet: `172.28.0.0/16` (isolated network for Graphiti services)

### Volume Optimization
- Named volumes used for performance (OrbStack-optimized)
- Data persists in `neo4j_data` volume
- Backups stored in host `./backups/` directory

## Environment Variables

Required in `.env`:
```bash
NEO4J_USER=neo4j
NEO4J_PASSWORD=<secure-password>  # Must be set, no default

# Optional for tests
OPENAI_API_KEY=<key>  # If using OpenAI with Graphiti
```

## Important Implementation Notes

1. **No Group ID Separation**: Single shared database for all agents (architectural decision)
2. **No APOC/GDS Plugins**: Not required for Graphiti operations
3. **Query Logging**: Enabled for queries >100ms (see Docker logs)
4. **Health Checks**: Automatic restarts on failure (40s startup period)
5. **Backup Retention**: 7 days automatic cleanup in `./scripts/backup.sh`

## Debugging Performance Issues

```bash
# Check if JVM is warmed up
docker logs neo4j-graphiti | grep "Started"  # Should see "Started." after ~40s

# Monitor memory usage
docker stats neo4j-graphiti  # Should show stable memory after warmup

# Check query performance
docker logs neo4j-graphiti | grep "ms"  # Shows slow queries >100ms

# Verify cache effectiveness
curl http://localhost:7474/db/neo4j/cluster/overview  # Check cache hit rates
```

## Common Pitfalls

1. **Cold Start Performance**: Always warm up Neo4j before benchmarking
2. **Memory Pressure**: If seeing OOM, reduce heap before reducing page cache
3. **Connection Refused**: Neo4j takes ~40s to start, check health before connecting
4. **Test Isolation**: Each test clears data - use fixtures for consistent state
5. **Async/Sync Sessions**: Graphiti issue #848 - always use sync sessions with Neo4j driver
6. **Episode Batching**: Large batches cause OOM - use SEMAPHORE_LIMIT=1 (issue #787)

## Memory Forensics & Monitoring

### Quick Health Check
```bash
# Full system monitoring
./scripts/monitor_neo4j.sh

# Check for heap dumps (indicates OOM)
docker exec neo4j-graphiti ls -la /data/dumps/

# Monitor GC activity
docker exec neo4j-graphiti tail -f /logs/gc.log | grep "Pause"

# Emergency recovery
docker exec neo4j-graphiti jcmd 1 GC.run  # Force GC
docker restart neo4j-graphiti              # If unresponsive
```

### Critical Thresholds
| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Heap Usage | >70% | >85% | Increase heap or optimize queries |
| GC Overhead | >50% | >98% | Restart imminent |
| Page Cache Hit | <98% | <95% | Increase page cache |
| Transaction Memory | >80% | >95% | Reduce batch sizes |

## Security Configuration

### Pre-commit Hooks Installed
- **Gitleaks**: Comprehensive secret scanning
- **TruffleHog**: Deep entropy-based detection
- **Detect-secrets**: Additional secret detection layer
- **Custom checks**: Neo4j credentials, .env files, heap dumps

### Running Security Checks
```bash
# Install pre-commit hooks
pre-commit install

# Manual security scan
pre-commit run --all-files

# Check specific files
pre-commit run gitleaks --files docker-compose.yml
```

## Graphiti Compatibility Patches

### Apply Patches for Known Issues
```bash
# Fix async/sync sessions and episode batching
python scripts/graphiti_patches.py

# Validate Neo4j driver compatibility
python scripts/graphiti_patches.py --check-only

# Use memory-safe wrapper
python scripts/memory_safe_graphiti.py
```

### Configuration for Graphiti
```bash
# config/graphiti_config.env
SEMAPHORE_LIMIT=1           # Prevent concurrent episodes
EPISODE_BATCH_SIZE=100      # Limit batch size
MAX_CONCURRENT_EPISODES=5   # Control parallelism
TRANSACTION_TIMEOUT=30s     # Prevent runaway queries
```

## Release Management

### Generate Changelog
```bash
# Generate changelog for new version
git cliff --tag v1.0.0

# Update existing changelog
git cliff --unreleased --prepend CHANGELOG.md

# Preview changes
git cliff --unreleased
```

## Prometheus Metrics

Neo4j exposes metrics on port 2004:
```bash
# Check metrics endpoint
curl http://localhost:2004/metrics

# Key metrics to monitor:
# - neo4j_vm_heap_used
# - neo4j_page_cache_hits
# - neo4j_transaction_active
# - neo4j_bolt_connections
```

## Emergency Procedures

### Out of Memory Recovery
```bash
# 1. Generate heap dump for analysis
docker exec neo4j-graphiti jcmd 1 GC.heap_dump /data/dumps/emergency.hprof

# 2. Kill long-running queries
docker exec neo4j-graphiti cypher-shell -u neo4j -p password \
  "CALL dbms.listQueries() YIELD queryId, elapsedTimeMillis 
   WHERE elapsedTimeMillis > 60000 
   CALL dbms.killQuery(queryId) YIELD message RETURN message"

# 3. Force restart with memory cleanup
docker-compose down
docker system prune -f
docker-compose up -d
```

### Analyzing Heap Dumps
```bash
# Copy heap dump locally
docker cp neo4j-graphiti:/data/dumps/emergency.hprof ./heap_dumps/

# Analyze with Eclipse MAT or jhat
jhat -J-Xmx4G ./heap_dumps/emergency.hprof
# Open browser to http://localhost:7000
```

## Network Configuration (OrbStack)

Using `orbstack-shared` network for inter-container communication:
- All containers can reach each other by name
- No port conflicts with host services
- Automatic DNS resolution via OrbStack

Access points:
- Neo4j Browser: http://neo4j.graphiti.local:7474
- Bolt: bolt://neo4j.graphiti.local:7687
- Prometheus: http://neo4j.graphiti.local:2004/metrics