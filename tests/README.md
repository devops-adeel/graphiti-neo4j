# Neo4j Graphiti Test Suite

Comprehensive test suite for validating Graphiti operations on Neo4j, focusing on read-heavy multi-agent workloads.

## Test Categories

### 1. Search Performance (`test_graphiti_search_performance.py`)
- Cold vs warm cache performance
- Entity type filtering
- Repeated query caching
- Scalability with varying result sizes

### 2. Episode Processing (`test_graphiti_episode_processing.py`)
- Text, JSON, and message episode types
- Batch processing
- Large episode handling
- Incremental updates

### 3. Concurrent Agents (`test_graphiti_concurrent_agents.py`)
- Multi-agent simultaneous reads
- Read-write isolation
- Connection pooling efficiency
- Sustained load testing

### 4. Temporal Queries (`test_graphiti_temporal_queries.py`)
- Fact invalidation
- Temporal ordering
- Superseded relationships
- Point-in-time consistency

### 5. Reranking (`test_graphiti_reranking.py`)
- Center node proximity
- Hybrid search (semantic + BM25 + BFS)
- Proximity decay
- Reranking performance overhead

## Running Tests

### Quick Start
```bash
# Run all tests
./test.sh

# Run quick smoke tests
./test.sh quick

# Run specific test category
./test.sh search
./test.sh concurrent
./test.sh temporal
```

### Available Test Suites
- `quick` - Quick smoke tests
- `search` - Search performance tests
- `episode` - Episode processing tests
- `concurrent` - Concurrent agent tests
- `temporal` - Temporal query tests
- `reranking` - Reranking and proximity tests
- `benchmark` - Performance benchmarks only
- `integration` - All integration tests
- `slow` - Long-running tests
- `all` - All tests (default)
- `coverage` - Run with coverage report

## Performance Targets

With optimized Neo4j configuration (4GB heap + 8GB page cache):
- **Search operations**: <100ms with warm cache
- **Episode ingestion**: <500ms including LLM processing
- **Concurrent reads**: Support 10+ agents
- **Cache hit rate**: >95% for repeated queries

## Test Fixtures

### Sample Data (`fixtures/sample_episodes.json`)
- Customer conversations
- Product catalog
- Customer profiles
- Inventory updates
- Product reviews

### Warmup Utilities (`fixtures/warmup_data.py`)
- JVM and cache warming
- Synthetic data generation
- Performance query sets
- Cache effectiveness verification

## Configuration

### Memory Settings (docker-compose.yml)
- Heap: 4GB (initial and max)
- Page Cache: 8GB
- Total Neo4j: ~12GB
- Optimized for 36GB RAM system

### Test Configuration (pytest.ini)
- Async mode: auto
- Benchmarks: 5 rounds minimum
- Timeout: 60 seconds
- Markers: benchmark, integration, concurrent, temporal, slow, warmup

## Dependencies

- `graphiti-core[neo4j]>=0.4.0`
- `neo4j>=5.26.0`
- `pytest>=7.4.0`
- `pytest-asyncio>=0.21.0`
- `pytest-benchmark>=4.0.0`
- `tenacity>=8.2.0`

## Key Differences from FalkorDB Tests

### What We Test
- Graphiti API operations only (no direct database access)
- JVM warmup and page cache effectiveness
- Neo4j ACID properties through episode consistency
- Native graph algorithms via Graphiti's BFS

### What We Don't Test
- Group ID issues (as requested)
- Redis-style connection pooling
- LRU eviction patterns

## Notes

- All tests use Graphiti's API (`search_nodes`, `search_facts`, `add_episode`)
- Focus on read-heavy patterns matching multi-agent workloads
- Validates caching effectiveness for embedding vectors
- Tests episode-based data ingestion as primary input method