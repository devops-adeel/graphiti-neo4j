# Episodes First: The Core Abstraction of Graphiti

## Why This Matters
Traditional graph databases force you to think in nodes and edges. Graphiti flips this - you think in **episodes** (conversations, events, updates), and the knowledge graph emerges automatically through AI-powered extraction.

## The Episode Approach
An episode is any temporal unit of information - a customer conversation, a product update, a sensor reading. Graphiti's LLM pipeline transforms these episodes into a living knowledge graph without you writing a single Cypher query.

## What Are Episodes?

Episodes are the **only way** data enters your Graphiti knowledge graph. Think of them as temporal snapshots of reality that get processed into structured knowledge.

### The Three Episode Types

```python
from graphiti_core.nodes import EpisodeType
from datetime import datetime, timezone

# 1. TEXT Episodes - Unstructured natural language
await graphiti.add_episode(
    name="customer_complaint_001",
    episode_body="Customer John Smith called about his wool runners being too tight. He has wide feet and needs a size 11 instead of 10.",
    source=EpisodeType.text,
    source_description="Customer support call transcript",
    reference_time=datetime.now(timezone.utc)
)

# 2. JSON Episodes - Structured data with clear relationships  
await graphiti.add_episode(
    name="product_update_002",
    episode_body='{"product": "Wool Runners", "sizes": [8,9,10,11,12], "colors": ["Natural Black", "Tree Green"], "price": 98.00}',
    source=EpisodeType.json,
    source_description="Product catalog sync",
    reference_time=datetime.now(timezone.utc)
)

# 3. MESSAGE Episodes - Conversational exchanges
await graphiti.add_episode(
    name="support_chat_003",
    episode_body="Agent: How can I help you today?\nCustomer: I need to return my shoes\nAgent: I'll process that return for you",
    source=EpisodeType.message,
    source_description="Live chat interaction",
    reference_time=datetime.now(timezone.utc)
)
```

## How Episodes Become Knowledge

The magic happens automatically through Graphiti's pipeline:

```
Episode Input → LLM Processing → Entity Extraction → Relationship Discovery → Graph Storage
     ↓              ↓                   ↓                    ↓                      ↓
"John needs      GPT-4 analyzes    [John:Person]      [John NEEDS Size11]    Neo4j stores
 size 11"         for entities      [Size11:Size]      [John HAS WideFeet]    permanently
```

### What Happens Under the Hood

1. **Episode Ingestion** (0-100ms)
   - Episode stored with timestamp
   - Queued for processing
   - Assigned unique UUID

2. **LLM Entity Extraction** (500-2000ms)
   - GPT-4/Claude identifies entities
   - Determines entity types
   - Extracts entity properties

3. **Relationship Discovery** (200-500ms)
   - Identifies connections between entities
   - Determines relationship types
   - Adds temporal validity

4. **Graph Construction** (50-200ms)
   - Creates/updates nodes in Neo4j
   - Establishes edges with properties
   - Maintains temporal consistency

## Observability

Monitor episode processing in Langfuse:

```python
from langfuse.decorators import observe

@observe(name="episode_processing")
async def process_customer_interaction(conversation: str):
    # Langfuse automatically traces this
    result = await graphiti.add_episode(
        name=f"conversation_{datetime.now().timestamp()}",
        episode_body=conversation,
        source=EpisodeType.message,
        reference_time=datetime.now(timezone.utc)
    )
    
    # View in Langfuse dashboard:
    # - LLM tokens used for extraction
    # - Processing latency breakdown  
    # - Entities and relationships created
    # - Total cost of episode processing
```

Langfuse trace example:
```
┌─ episode_processing (1,243ms total) ────────────────┐
│ ├─ add_episode (43ms)                               │
│ ├─ llm_entity_extraction (823ms, 1,200 tokens)      │
│ │  ├─ Entities found: 3                             │
│ │  └─ Cost: $0.0024                                 │
│ ├─ relationship_discovery (234ms, 400 tokens)       │
│ │  ├─ Relationships found: 2                        │
│ │  └─ Cost: $0.0008                                 │
│ └─ graph_storage (143ms)                            │
│    ├─ Nodes created: 2                              │
│    ├─ Nodes updated: 1                              │
│    └─ Edges created: 2                              │
└──────────────────────────────────────────────────────┘
```

## Performance Impact

Episode type dramatically affects processing performance:

| Episode Type | LLM Tokens | Processing Time | Best For |
|-------------|------------|-----------------|----------|
| TEXT | 500-2000 | 1-3 seconds | Support transcripts, notes |
| JSON | 200-800 | 0.5-1 second | Product data, structured events |
| MESSAGE | 300-1200 | 0.8-2 seconds | Conversations, chat logs |

### Batch Processing Considerations

```python
# DON'T: Process huge batches (causes OOM)
for episode in massive_list:  # ❌ Can exhaust memory
    await graphiti.add_episode(...)

# DO: Process in controlled batches
from itertools import islice

def batch_episodes(episodes, batch_size=10):
    iterator = iter(episodes)
    while batch := list(islice(iterator, batch_size)):
        yield batch

for batch in batch_episodes(episodes, batch_size=10):
    for episode in batch:
        await graphiti.add_episode(...)
    await asyncio.sleep(0.1)  # Allow memory recovery
```

## Common Issues

### Episode Not Creating Expected Entities
```python
# Problem: Vague episode content
await graphiti.add_episode(
    episode_body="The thing is broken",  # ❌ Too vague
    source=EpisodeType.text
)

# Solution: Provide context
await graphiti.add_episode(
    episode_body="Customer John's Wool Runners size 10 have a torn sole after 2 months of use",  # ✅ 
    source=EpisodeType.text,
    source_description="Product defect report"  # Additional context
)
```

### Temporal Confusion
```python
# Problem: Missing or wrong timestamps
await graphiti.add_episode(
    episode_body="Price increased to $120",
    reference_time=datetime(2023, 1, 1)  # ❌ Old date might not invalidate current price
)

# Solution: Use accurate timestamps
await graphiti.add_episode(
    episode_body="Price increased to $120",
    reference_time=datetime.now(timezone.utc)  # ✅ Properly invalidates old price
)
```

### Choosing the Wrong Episode Type
```python
# Problem: Using TEXT for structured data
await graphiti.add_episode(
    episode_body="product: shoes, price: 98, sizes: 9,10,11",  # ❌ 
    source=EpisodeType.text  # Will be processed as natural language
)

# Solution: Use JSON for structured data
await graphiti.add_episode(
    episode_body='{"product": "shoes", "price": 98, "sizes": [9,10,11]}',  # ✅
    source=EpisodeType.json  # Properly extracts structure
)
```

## Next Steps
- [Temporal Knowledge vs Storage](./temporal-knowledge-vs-storage.md) - Understanding the abstraction layers
- [Episode Design Patterns](../episodes/episode-design-patterns.md) - Common patterns for different use cases
- [Search Configurations](../episodes/search-configurations.md) - Retrieving knowledge from episodes
- [5-Minute Chatbot](../../user/quickstart/5-minute-chatbot.md) - Build your first episode-powered application