"""
Warmup data and utilities for Neo4j cache warming.
"""

import asyncio
import json
from pathlib import Path
from datetime import datetime, timezone
from typing import List, Dict, Any
from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType


async def load_sample_episodes() -> Dict[str, Any]:
    """Load sample episodes from JSON file."""
    fixtures_dir = Path(__file__).parent
    episodes_file = fixtures_dir / "sample_episodes.json"
    
    with open(episodes_file, 'r') as f:
        return json.load(f)


async def warmup_neo4j_cache(client: Graphiti, iterations: int = 3):
    """
    Warm up Neo4j JVM and caches with representative queries.
    
    Args:
        client: Graphiti client instance
        iterations: Number of warmup iterations
    """
    # Load sample data
    data = await load_sample_episodes()
    
    # Add some episodes for warmup
    warmup_episodes = [
        ("Product catalog", json.dumps(data["products"][:2]), EpisodeType.json),
        ("Customer profile", json.dumps(data["customers"][0]), EpisodeType.json),
        ("Support chat", "\n".join(data["conversations"][0]["messages"]), EpisodeType.message)
    ]
    
    for name, body, source in warmup_episodes:
        await client.add_episode(
            name=f"warmup_{name}",
            episode_body=body,
            source=source,
            reference_time=datetime.now(timezone.utc),
            source_description="Cache warmup"
        )
    
    # Wait for processing
    await asyncio.sleep(2)
    
    # Perform warmup queries
    warmup_queries = [
        "comfortable shoes",
        "customer preferences",
        "product prices",
        "size 10",
        "wool material",
        "running athletic",
        "sustainable products"
    ]
    
    for _ in range(iterations):
        for query in warmup_queries:
            # Search nodes
            await client.search_nodes(query, max_nodes=5)
            # Search facts
            await client.search_facts(query, max_facts=5)
        
        # Small delay between iterations
        await asyncio.sleep(0.1)


def generate_test_episodes(count: int = 10) -> List[Dict[str, Any]]:
    """
    Generate synthetic test episodes for performance testing.
    
    Args:
        count: Number of episodes to generate
    
    Returns:
        List of episode dictionaries
    """
    episodes = []
    
    for i in range(count):
        episode_type = i % 3
        
        if episode_type == 0:
            # Text episode
            episodes.append({
                "name": f"text_episode_{i}",
                "body": f"Customer {i} is interested in product {i % 5} with preference for color {i % 3}",
                "source": "text",
                "description": "Synthetic text"
            })
        elif episode_type == 1:
            # JSON episode
            episodes.append({
                "name": f"json_episode_{i}",
                "body": json.dumps({
                    "customer_id": f"CUST_{i:03d}",
                    "action": "viewed",
                    "product": f"Product_{i % 5}",
                    "timestamp": datetime.now(timezone.utc).isoformat()
                }),
                "source": "json",
                "description": "Synthetic JSON"
            })
        else:
            # Message episode
            episodes.append({
                "name": f"message_episode_{i}",
                "body": f"User: Question about product {i % 5}\nAgent: Here's information about product {i % 5}",
                "source": "message",
                "description": "Synthetic conversation"
            })
    
    return episodes


def get_performance_queries() -> List[str]:
    """
    Get a list of queries for performance testing.
    
    Returns:
        List of query strings
    """
    return [
        # Simple queries
        "shoes",
        "customer",
        "product",
        "price",
        "size",
        
        # Medium complexity
        "comfortable running shoes",
        "customer preferences",
        "product recommendations",
        "available sizes",
        "wool material",
        
        # Complex queries
        "sustainable running shoes size 10 under $150",
        "customer John purchase history returns",
        "product inventory status availability",
        "wide fit shoes for running",
        "merino wool athletic footwear"
    ]


async def populate_graph_for_testing(client: Graphiti, episode_count: int = 50):
    """
    Populate the graph with test data for performance testing.
    
    Args:
        client: Graphiti client instance
        episode_count: Number of episodes to add
    """
    episodes = generate_test_episodes(episode_count)
    
    # Add episodes in batches for efficiency
    batch_size = 10
    for i in range(0, len(episodes), batch_size):
        batch = episodes[i:i+batch_size]
        
        tasks = []
        for episode in batch:
            task = client.add_episode(
                name=episode["name"],
                episode_body=episode["body"],
                source=EpisodeType[episode["source"]],
                reference_time=datetime.now(timezone.utc),
                source_description=episode["description"]
            )
            tasks.append(task)
        
        await asyncio.gather(*tasks)
        
        # Small delay between batches
        await asyncio.sleep(0.5)


async def verify_cache_effectiveness(client: Graphiti) -> Dict[str, float]:
    """
    Verify that cache warming is effective.
    
    Args:
        client: Graphiti client instance
    
    Returns:
        Dictionary with timing metrics
    """
    import time
    
    test_query = "comfortable wool shoes"
    
    # First search (potentially cold)
    start = time.perf_counter()
    await client.search_nodes(test_query, max_nodes=5)
    first_time = time.perf_counter() - start
    
    # Second search (should be cached)
    start = time.perf_counter()
    await client.search_nodes(test_query, max_nodes=5)
    second_time = time.perf_counter() - start
    
    # Third search (definitely cached)
    start = time.perf_counter()
    await client.search_nodes(test_query, max_nodes=5)
    third_time = time.perf_counter() - start
    
    return {
        "first_search_ms": first_time * 1000,
        "second_search_ms": second_time * 1000,
        "third_search_ms": third_time * 1000,
        "cache_speedup": first_time / third_time if third_time > 0 else 0
    }