# 5-Minute Chatbot: Your First Graphiti Application

## Why This Matters
In 5 minutes, you'll have a working chatbot with persistent memory that remembers customer preferences, past interactions, and can reason about relationships - something impossible with traditional vector-only RAG.

## The Episode Approach
Your chatbot will ingest conversations as episodes, automatically building a knowledge graph of customers, products, and preferences without writing any graph queries.

## Prerequisites

```bash
# Check Docker is running
docker ps

# Check environment file exists
cat .env
# Should contain:
# NEO4J_USER=neo4j
# NEO4J_PASSWORD=your-password
# OPENAI_API_KEY=sk-...
```

## Step 1: Start Neo4j (30 seconds)

```bash
# Start Neo4j with optimal settings
docker-compose up -d

# Wait for Neo4j to be ready
sleep 40  # JVM warmup time

# Verify it's running
docker logs neo4j-graphiti | grep "Started"
```

## Step 2: Install Dependencies (30 seconds)

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install Graphiti
pip install graphiti-core[neo4j] langfuse
```

## Step 3: Create Your Chatbot (2 minutes)

Create `chatbot.py`:

```python
#!/usr/bin/env python3
"""
5-Minute Chatbot with Graphiti Memory
"""
import asyncio
import os
from datetime import datetime, timezone
from dotenv import load_dotenv
from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType
from langfuse.decorators import observe

# Load environment
load_dotenv()

class MemoryChatbot:
    def __init__(self):
        self.graphiti = Graphiti(
            uri=os.getenv("NEO4J_URI", "bolt://localhost:7687"),
            user=os.getenv("NEO4J_USER", "neo4j"),
            password=os.getenv("NEO4J_PASSWORD")
        )
        self.conversation_count = 0
    
    async def initialize(self):
        """Set up the knowledge graph"""
        await self.graphiti.build_indices_and_constraints()
        print("✅ Chatbot initialized with memory!")
    
    @observe(name="chat_interaction")  # Automatic Langfuse tracing
    async def chat(self, user_name: str, message: str):
        """Process user message and respond with context"""
        
        # 1. Store the interaction as an episode
        await self.graphiti.add_episode(
            name=f"chat_{self.conversation_count}",
            episode_body=f"{user_name}: {message}",
            source=EpisodeType.message,
            source_description="Customer chat",
            reference_time=datetime.now(timezone.utc)
        )
        self.conversation_count += 1
        
        # 2. Search for relevant context
        context = await self.graphiti.search(
            query=message,
            num_results=5
        )
        
        # 3. Generate response based on context
        if context:
            context_str = "\n".join([f"- {c.fact}" for c in context])
            response = f"Based on what I know:\n{context_str}\n\nHow can I help you with that?"
        else:
            response = "I'm learning about your preferences. Tell me more!"
        
        # 4. Store the response
        await self.graphiti.add_episode(
            name=f"response_{self.conversation_count}",
            episode_body=f"Assistant: {response}",
            source=EpisodeType.message,
            source_description="Assistant response",
            reference_time=datetime.now(timezone.utc)
        )
        
        return response
    
    async def close(self):
        """Clean up connections"""
        await self.graphiti.close()


async def main():
    # Initialize chatbot
    bot = MemoryChatbot()
    await bot.initialize()
    
    # Seed with some product knowledge
    print("\n📚 Loading product knowledge...")
    await bot.graphiti.add_episode(
        name="product_catalog",
        episode_body="""{
            "products": [
                {"name": "Wool Runners", "sizes": [8,9,10,11,12], "price": 98, "material": "merino wool"},
                {"name": "Tree Dashers", "sizes": [7,8,9,10,11], "price": 135, "material": "eucalyptus"},
                {"name": "Trail Runners", "sizes": [8,9,10,11,12,13], "price": 148, "material": "sugarcane"}
            ]
        }""",
        source=EpisodeType.json,
        source_description="Product database",
        reference_time=datetime.now(timezone.utc)
    )
    
    print("\n🤖 Chatbot ready! Type 'quit' to exit.\n")
    
    # Interactive chat loop
    user_name = input("What's your name? ")
    
    while True:
        message = input(f"\n{user_name}: ")
        
        if message.lower() == 'quit':
            break
        
        response = await bot.chat(user_name, message)
        print(f"\n🤖 Assistant: {response}")
    
    # Clean up
    await bot.close()
    print("\n👋 Goodbye!")


if __name__ == "__main__":
    asyncio.run(main())
```

## Step 4: Run Your Chatbot (1 minute)

```bash
python chatbot.py
```

### Example Conversation

```
What's your name? John

John: I need running shoes

🤖 Assistant: Based on what I know:
- Wool Runners available in sizes 8-12 for $98
- Tree Dashers available in sizes 7-11 for $135  
- Trail Runners available in sizes 8-13 for $148

How can I help you with that?

John: I have wide feet and usually wear size 11

🤖 Assistant: Based on what I know:
- John has wide feet
- John wears size 11
- Trail Runners available in size 11
- Wool Runners available in size 11

How can I help you with that?

John: What did I tell you about my feet?

🤖 Assistant: Based on what I know:
- John has wide feet
- John usually wears size 11

How can I help you with that?
```

## Step 5: View in Langfuse (1 minute)

If you have Langfuse running locally:

```python
# Add to your .env file:
LANGFUSE_PUBLIC_KEY=pk-...
LANGFUSE_SECRET_KEY=sk-...
LANGFUSE_HOST=http://localhost:3000

# View traces at: http://localhost:3000
```

You'll see:
- Each chat interaction traced
- Episode processing time
- LLM costs for entity extraction
- Search performance metrics

## Observability

Your chatbot automatically tracks:

```
Chat Interaction Trace:
┌─ chat_interaction ────────────────────────────────┐
│ Input: "I need running shoes"                     │
│                                                    │
│ ├─ add_episode (523ms)                           │
│ │  ├─ Entity extraction: 3 entities found        │
│ │  └─ Cost: $0.0012                              │
│ │                                                 │
│ ├─ search (89ms)                                 │
│ │  └─ Results: 3 products found                  │
│ │                                                 │
│ └─ Total: 612ms, $0.0012                         │
└───────────────────────────────────────────────────┘
```

## Performance Impact

Your chatbot demonstrates key advantages:

| Feature | Without Graphiti | With Graphiti |
|---------|-----------------|---------------|
| Memory persistence | ❌ Lost on restart | ✅ Permanent |
| Relationship understanding | ❌ No connections | ✅ Full graph |
| Temporal awareness | ❌ No time concept | ✅ Fact invalidation |
| Query speed (after 1000 chats) | 🐌 Linear scan | ⚡ Graph traversal |

## Common Issues

### Neo4j Connection Failed
```bash
# Check Neo4j is running
docker ps | grep neo4j-graphiti

# Check logs
docker logs neo4j-graphiti

# Restart if needed
docker-compose restart
```

### Slow First Response
```python
# This is normal - JVM warmup
# First query: 500-1000ms
# Subsequent queries: 50-100ms

# Pre-warm in production:
async def warmup():
    await graphiti.search("test", num_results=1)
```

### Memory Not Persisting
```python
# Ensure you're using the same graph
# ❌ Creates new instance each time
async def handle_message(msg):
    graphiti = Graphiti(...)  # New instance
    
# ✅ Reuse single instance
class Chatbot:
    def __init__(self):
        self.graphiti = Graphiti(...)  # Single instance
```

## Next Steps

### Enhance Your Bot

1. **Add user preferences tracking:**
```python
await graphiti.add_episode(
    episode_body=f"{user_name} prefers {preference}",
    source=EpisodeType.text
)
```

2. **Implement temporal queries:**
```python
# "What did I ask about last week?"
results = await graphiti.search(
    f"{user_name} questions",
    time_range=(last_week, now)
)
```

3. **Add relationship queries:**
```python
# "Products similar to what I bought"
results = await graphiti.search(
    f"products related to {user_name}'s purchases"
)
```

### Learn More
- [Episode Patterns Cookbook](../episode-patterns-cookbook.md) - Common conversation patterns
- [Customer Support System](../examples/customer-support-system/01-setup.md) - Full production example
- [Search Configurations](../../dev/episodes/search-configurations.md) - Advanced search strategies
- [Monitoring with Langfuse](../guides/monitoring-with-langfuse.md) - Production observability

## Complete Code

The full chatbot code is available at:
- `examples/quickstart_chatbot.py` - This tutorial's code
- `examples/notebooks/chatbot_tutorial.ipynb` - Interactive Jupyter version

Congratulations! You've built an AI chatbot with persistent temporal memory in under 5 minutes! 🎉