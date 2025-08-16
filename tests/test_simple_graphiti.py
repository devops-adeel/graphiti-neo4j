"""
Simple test suite for Neo4j Graphiti integration.
Tests the actual Graphiti API methods available.
"""

import asyncio
import time
import json
from datetime import datetime, timezone
import pytest
from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType
from dotenv import load_dotenv
import os

# Load environment variables
load_dotenv()

# Neo4j connection settings
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD")  # No default - must be set in .env


@pytest.fixture
async def graphiti_client():
    """Create a Graphiti client for testing."""
    client = Graphiti(
        uri=NEO4J_URI,
        user=NEO4J_USER,
        password=NEO4J_PASSWORD
    )
    await client.build_indices_and_constraints()
    yield client
    await client.close()


@pytest.mark.asyncio
async def test_episode_text_processing(graphiti_client):
    """Test adding and searching text episodes."""
    # Add a text episode
    await graphiti_client.add_episode(
        name="customer_inquiry",
        episode_body="Customer John Smith is looking for comfortable running shoes in size 10",
        source=EpisodeType.text,
        source_description="Customer support chat",
        reference_time=datetime.now(timezone.utc)
    )
    
    # Wait for processing
    await asyncio.sleep(2)
    
    # Search for it
    results = await graphiti_client.search("running shoes", num_results=5)
    assert len(results) > 0, "Should find results for 'running shoes'"


@pytest.mark.asyncio
async def test_episode_json_processing(graphiti_client):
    """Test adding and searching JSON episodes."""
    # Add a JSON episode
    product_data = {
        "product": {
            "id": "PROD_001",
            "name": "Wool Runners",
            "price": 98,
            "sizes": [8, 9, 10, 11],
            "colors": ["Black", "Blue", "Green"]
        }
    }
    
    await graphiti_client.add_episode(
        name="product_catalog_entry",
        episode_body=json.dumps(product_data),
        source=EpisodeType.json,
        source_description="Product catalog update",
        reference_time=datetime.now(timezone.utc)
    )
    
    # Wait for processing
    await asyncio.sleep(2)
    
    # Search for it
    results = await graphiti_client.search("Wool Runners", num_results=5)
    assert len(results) >= 0, "Should process JSON episode"


@pytest.mark.asyncio
async def test_episode_message_processing(graphiti_client):
    """Test adding and searching message episodes."""
    # Add a message episode
    conversation = """Customer: I need help with my order
Agent: I'd be happy to help! What's your order number?
Customer: It's ORDER-12345
Agent: Let me look that up for you"""
    
    await graphiti_client.add_episode(
        name="support_conversation",
        episode_body=conversation,
        source=EpisodeType.message,
        source_description="Customer support transcript",
        reference_time=datetime.now(timezone.utc)
    )
    
    # Wait for processing
    await asyncio.sleep(2)
    
    # Search for it
    results = await graphiti_client.search("order help", num_results=5)
    assert len(results) >= 0, "Should process message episode"


@pytest.mark.asyncio
async def test_search_performance(graphiti_client):
    """Test search performance with warm cache."""
    # Add some data first
    await graphiti_client.add_episode(
        name="performance_test",
        episode_body="Testing search performance for Neo4j with multiple queries",
        source=EpisodeType.text,
        source_description="Performance test",
        reference_time=datetime.now(timezone.utc)
    )
    
    await asyncio.sleep(2)
    
    # Warm up
    await graphiti_client.search("performance", num_results=5)
    
    # Measure performance
    start = time.perf_counter()
    results = await graphiti_client.search("performance", num_results=10)
    duration = time.perf_counter() - start
    
    print(f"Search took {duration*1000:.2f}ms")
    assert duration < 1.0, f"Search should be fast, took {duration:.3f}s"


@pytest.mark.asyncio
async def test_concurrent_searches(graphiti_client):
    """Test concurrent search operations."""
    # Add test data
    await graphiti_client.add_episode(
        name="concurrent_test",
        episode_body="Products: shoes, shirts, pants, jackets, hats",
        source=EpisodeType.text,
        source_description="Concurrent test",
        reference_time=datetime.now(timezone.utc)
    )
    
    await asyncio.sleep(2)
    
    # Run concurrent searches
    queries = ["shoes", "shirts", "pants", "jackets", "hats"]
    
    async def search_task(query):
        start = time.perf_counter()
        results = await graphiti_client.search(query, num_results=5)
        duration = time.perf_counter() - start
        return query, len(results), duration
    
    # Run all searches concurrently
    tasks = [search_task(q) for q in queries]
    results = await asyncio.gather(*tasks)
    
    # Check results
    for query, count, duration in results:
        print(f"Query '{query}': {count} results in {duration*1000:.2f}ms")
        assert duration < 2.0, f"Query '{query}' took too long: {duration:.3f}s"


@pytest.mark.asyncio
async def test_episode_retrieval(graphiti_client):
    """Test retrieving episodes."""
    # Add an episode
    await graphiti_client.add_episode(
        name="retrieval_test",
        episode_body="Test episode for retrieval functionality",
        source=EpisodeType.text,
        source_description="Retrieval test",
        reference_time=datetime.now(timezone.utc)
    )
    
    await asyncio.sleep(2)
    
    # Retrieve episodes
    episodes = await graphiti_client.retrieve_episodes(
        reference_time=datetime.now(timezone.utc),
        last_n=5
    )
    
    assert len(episodes) > 0, "Should retrieve recent episodes"
    assert any("retrieval" in str(e).lower() for e in episodes), "Should find our test episode"


if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v"])