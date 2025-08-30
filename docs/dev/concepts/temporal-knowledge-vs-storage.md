# Temporal Knowledge vs Storage: Understanding the Layers

## Why This Matters
Developers often confuse Graphiti (the temporal knowledge layer) with Neo4j (the storage layer). This confusion leads to writing Cypher queries, managing nodes directly, and missing Graphiti's powerful abstractions. Understanding this separation is crucial for building effective AI agents.

## The Episode Approach
You interact with Graphiti's episode API. Graphiti handles all the complexity of temporal reasoning, entity extraction, and graph operations. Neo4j is just the storage engine - you never touch it directly.

## The Three-Layer Architecture

```
┌─────────────────────────────────────────────────────┐
│             Your Application                         │
│         (Episodes In → Knowledge Out)                │
└─────────────────────────────────────────────────────┘
                         ↕
┌─────────────────────────────────────────────────────┐
│          Layer 1: GRAPHITI (Knowledge)               │
│                                                      │
│  • Episode Processing      • Temporal Reasoning      │
│  • Entity Extraction       • Fact Invalidation       │
│  • Search Strategies       • Relationship Discovery  │
│                                                      │
│  You work here: add_episode(), search()             │
└─────────────────────────────────────────────────────┘
                         ↕
┌─────────────────────────────────────────────────────┐
│          Layer 2: NEO4J (Storage)                    │
│                                                      │
│  • Graph Database          • ACID Transactions       │
│  • Cypher Query Engine     • Index Management        │
│  • JVM Memory Management   • Disk Persistence        │
│                                                      │
│  You never work here directly                        │
└─────────────────────────────────────────────────────┘
                         ↕
┌─────────────────────────────────────────────────────┐
│          Layer 3: LANGFUSE (Observability)           │
│                                                      │
│  • Trace Collection        • Cost Attribution        │
│  • Latency Breakdown       • LLM Token Tracking      │
│  • Error Monitoring        • Performance Metrics     │
│                                                      │
│  You monitor here: traces, costs, performance        │
└─────────────────────────────────────────────────────┘
```

## What Each Layer Does

### Graphiti: The Knowledge Layer

Graphiti provides temporal semantics that don't exist in Neo4j:

```python
# What you write (simple, temporal-aware)
await graphiti.add_episode(
    episode_body="Product price increased to $120",
    reference_time=datetime(2024, 3, 1, timezone.utc)
)

# What Graphiti does automatically:
# 1. Extracts: Product entity, Price property
# 2. Invalidates: Previous price facts before March 1
# 3. Creates: New temporal fact with validity period
# 4. Maintains: Consistency across the knowledge graph
```

### Neo4j: The Storage Layer

Neo4j stores the physical graph structure:

```cypher
# What Graphiti creates in Neo4j (you never write this)
CREATE (p:Product {name: "Wool Runners"})
CREATE (f:Fact {
    content: "Price is $120",
    valid_from: datetime("2024-03-01"),
    confidence: 0.95
})
CREATE (p)-[:HAS_FACT {temporal: true}]->(f)
```

### Langfuse: The Observability Layer

Langfuse reveals what happens across all layers:

```python
# Automatic tracing shows the full pipeline
@observe(name="knowledge_update")
async def update_product_knowledge(product_data):
    # Langfuse trace shows:
    # ├─ Episode ingestion: 23ms
    # ├─ LLM extraction: 1,234ms, $0.0024
    # ├─ Temporal reasoning: 156ms
    # ├─ Neo4j storage: 89ms
    # └─ Total: 1,502ms
    
    await graphiti.add_episode(...)
```

## Temporal Knowledge: Graphiti's Superpower

### Fact Invalidation

Traditional databases can't handle temporal truth:

```python
# Monday: Customer preference recorded
await graphiti.add_episode(
    episode_body="John prefers size 10 shoes",
    reference_time=datetime(2024, 3, 4)  # Monday
)

# Wednesday: Preference updated
await graphiti.add_episode(
    episode_body="John now needs size 11 due to swelling",
    reference_time=datetime(2024, 3, 6)  # Wednesday
)

# Graphiti automatically:
# - Marks Monday's fact as superseded
# - Creates new fact with Wednesday timestamp
# - Maintains history for audit trail

# Searching returns current truth
results = await graphiti.search("What size does John need?")
# Returns: Size 11 (not size 10)
```

### Episode Context Preservation

Episodes maintain full context, unlike raw graph nodes:

```python
# The episode preserves the WHY
episode = await graphiti.get_episode(uuid)
print(episode.body)
# "Customer called angry about delayed shipment. 
#  Order #12345 was supposed to arrive Monday but 
#  tracking shows Thursday. Offered 20% discount."

# The graph only stores the WHAT
# Node: Customer(angry=true)
# Node: Order(id=12345, delayed=true)  
# Node: Discount(amount=20%)
# But loses the narrative connection
```

## Why You Never Write Cypher

### What Happens When You Try

```python
# ❌ WRONG: Bypassing Graphiti
from neo4j import GraphDatabase

driver = GraphDatabase.driver("bolt://localhost:7687")
with driver.session() as session:
    session.run("CREATE (n:Customer {name: 'John'})")
    
# Problems:
# 1. No temporal metadata
# 2. No episode tracking
# 3. No LLM enrichment
# 4. No fact invalidation
# 5. Breaks Graphiti's consistency model
```

```python
# ✅ RIGHT: Using Graphiti's abstractions
await graphiti.add_episode(
    episode_body="New customer John signed up today",
    source=EpisodeType.text,
    reference_time=datetime.now(timezone.utc)
)

# Benefits:
# 1. Automatic temporal tracking
# 2. Episode preservation
# 3. LLM entity extraction
# 4. Relationship discovery
# 5. Maintains consistency
```

## Observability Across Layers

Langfuse shows the complete picture:

```
Episode Addition Trace:
┌─ graphiti.add_episode ──────────────────────────────┐
│                                                      │
│ ├─ GRAPHITI LAYER (1,234ms)                         │
│ │  ├─ Episode validation: 12ms                      │
│ │  ├─ LLM entity extraction: 823ms                  │
│ │  │  └─ GPT-4 call: 1,243 tokens, $0.0024         │
│ │  ├─ Relationship discovery: 234ms                 │
│ │  └─ Temporal reasoning: 165ms                     │
│ │                                                    │
│ ├─ NEO4J LAYER (156ms)                              │
│ │  ├─ Transaction begin: 8ms                        │
│ │  ├─ Node creation: 34ms                           │
│ │  ├─ Edge creation: 28ms                           │
│ │  ├─ Index update: 43ms                            │
│ │  └─ Transaction commit: 43ms                      │
│ │                                                    │
│ └─ TOTAL: 1,390ms, $0.0024                          │
└──────────────────────────────────────────────────────┘
```

## Performance Impact

Understanding layers helps optimize correctly:

| Operation | Graphiti Layer | Neo4j Layer | Total |
|-----------|---------------|-------------|-------|
| Add Episode | 500-2000ms (LLM) | 50-200ms | 550-2200ms |
| Search (cold) | 100-300ms | 200-500ms | 300-800ms |
| Search (warm) | 100-300ms | 10-50ms | 110-350ms |
| Temporal Query | 200-400ms | 50-100ms | 250-500ms |

## Common Issues

### Trying to Optimize the Wrong Layer

```python
# Problem: Slow episode processing
# ❌ Wrong diagnosis: "Neo4j is slow"
# ❌ Wrong solution: Tune Neo4j memory

# ✅ Right diagnosis: Check Langfuse traces
# Shows: 90% time in LLM calls
# ✅ Right solution: Use smaller model for extraction
graphiti = Graphiti(
    llm_client=OpenAIClient(
        config=LLMConfig(
            model="gpt-4o-mini",  # Faster
            small_model="gpt-3.5-turbo"  # Even faster for simple tasks
        )
    )
)
```

### Misunderstanding Data Access

```python
# ❌ WRONG: Trying to query Neo4j directly
results = neo4j_session.run("MATCH (n:Episode) RETURN n")

# ✅ RIGHT: Using Graphiti's search
results = await graphiti.search("recent customer interactions")

# ✅ RIGHT: Getting episodes through Graphiti
episodes = await graphiti.get_episodes(
    start_time=datetime.now() - timedelta(days=7)
)
```

## Next Steps
- [Graph vs Vector RAG](./graph-vs-vector-rag.md) - When relationships beat embeddings
- [Episode Types Deep Dive](../episodes/episode-types-deep-dive.md) - Choosing the right episode type
- [JVM for Python Developers](../performance/jvm-for-python-developers.md) - Understanding Neo4j's runtime
- [Langfuse Observability](../architecture/layer-3-langfuse.md) - Monitoring all layers