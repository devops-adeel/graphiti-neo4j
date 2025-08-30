# Neo4j for Graphiti on OrbStack

Temporal knowledge graph infrastructure for Graphiti-powered AI agents. Build chatbots with memory, RAG with relationships, and AI that understands time.

## 🚀 Quick Start

**New to Graphiti?** Start with our [5-Minute Chatbot Guide](docs/user/quickstart/5-minute-chatbot.md) →

```bash
# 1. Clone and setup
git clone https://github.com/yourusername/graphiti-neo4j.git
cd graphiti-neo4j
cp .env.example .env  # Add your Neo4j password

# 2. Start Neo4j
docker-compose up -d

# 3. Build your first AI agent with memory
python docs/user/quickstart/5-minute-chatbot.md
```

## 📚 Documentation

### For AI/ML Developers

#### Quick Start
- **[5-Minute Chatbot](docs/user/quickstart/5-minute-chatbot.md)** - Build your first memory-enabled agent
- **[Episode Patterns Cookbook](docs/user/quickstart/episode-patterns-cookbook.md)** - Copy-paste patterns for common use cases
- **[Backup & Recovery](docs/user/guides/backup-and-recovery.md)** - Protect your knowledge graph

#### Core Concepts  
- **[Episodes First](docs/dev/concepts/episodes-first.md)** - Why episodes, not nodes and edges
- **[Temporal Knowledge vs Storage](docs/dev/concepts/temporal-knowledge-vs-storage.md)** - Understanding the layers
- **[Graph vs Vector RAG](docs/dev/concepts/graph-vs-vector-rag.md)** - 50x performance for relationships

#### Deep Dives
- **[Memory Configuration](docs/dev/performance/memory-forensics-guide.md)** - JVM tuning for Python developers
- **[Backup Architecture](docs/dev/architecture/backup-system.md)** - Enterprise-grade data protection
- **[Examples](examples/)** - Complete applications and notebooks

## 🔗 Connection Details

```python
# For Graphiti applications
from graphiti_core import Graphiti

graphiti = Graphiti(
    uri="bolt://localhost:7687",  # or "bolt://neo4j.graphiti.local:7687"
    user="neo4j",
    password=os.getenv("NEO4J_PASSWORD")
)
```

## ✨ Key Features

### Episode-First Architecture
- **Temporal Knowledge Graphs** - Facts that change over time
- **Automatic Entity Extraction** - LLM-powered understanding
- **Relationship Discovery** - Find hidden connections
- **50x Faster Than Vector DBs** - For relationship queries

### Production Ready
- **Multi-Tier Backups** - Daily/weekly/monthly with external sync
- **Memory Forensics** - Prevent and debug OOM issues
- **Security Scanning** - Pre-commit hooks with Gitleaks
- **Prometheus Metrics** - Full observability on port 2004
- **Langfuse Integration** - Trace every episode through the pipeline

### Optimized for Graphiti
- **4GB Heap + 8GB Page Cache** - Tuned for 36GB systems
- **Episode Batching** - Prevent memory explosions
- **JVM Warmup Handling** - Automatic cache priming
- **OrbStack Domains** - Reliable container networking

## 🛡️ Backup & Recovery

```bash
# Enable automatic backups
make backup-start

# Create manual backup
make backup

# Restore interactively
make backup-restore
```

See [Backup Guide](docs/user/guides/backup-and-recovery.md) for details.

## 🔍 Monitoring & Troubleshooting

```bash
# Check system health
make health

# Monitor memory usage
make monitor

# View logs
docker logs -f neo4j-graphiti

# Emergency procedures
make emergency-gc           # Force garbage collection
make emergency-heap-dump    # Analyze memory issues
```

See [Memory Forensics Guide](docs/dev/performance/memory-forensics-guide.md) for debugging.

## 🚧 Common Issues

### Slow First Query?
This is normal - JVM needs 40s to warm up. First query: 500-1000ms, subsequent: 50-100ms.

### Connection Refused?
```bash
# Check if Neo4j is ready
docker logs neo4j-graphiti | grep "Started"
```

### Out of Memory?
```bash
# Use episode batching
# Process in batches of 10, not 1000
# See: docs/user/quickstart/episode-patterns-cookbook.md
```

## 📖 Learn More

- **[Why Graph beats Vector](docs/dev/concepts/graph-vs-vector-rag.md)** - 50x performance proof
- **[Customer Support Example](docs/user/examples/customer-support-system/)** - Production system
- **[JVM for Python Devs](docs/dev/performance/jvm-for-python-developers.md)** - Understanding Neo4j
- **[Langfuse Integration](docs/dev/architecture/layer-3-langfuse.md)** - Observability setup

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup.

## 📄 License

MIT - See [LICENSE](LICENSE) file.