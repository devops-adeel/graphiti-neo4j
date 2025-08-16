"""
Pytest configuration and fixtures for Neo4j Graphiti tests.
"""

import asyncio
import os
import time
import logging
from typing import AsyncGenerator, Dict, Any, List
from datetime import datetime, timezone
from pathlib import Path

import pytest
import pytest_asyncio
from dotenv import load_dotenv
from tenacity import retry, stop_after_attempt, wait_exponential
from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType
from graphiti_core.edges import EntityEdge
from graphiti_core.utils.maintenance.graph_data_operations import clear_data

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Neo4j connection settings
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD")  # No default - must be set in .env
# Neo4j database is specified at connection, not at client init

# Test configuration
WARMUP_ITERATIONS = 3
BENCHMARK_ROUNDS = 5
MAX_RETRIES = 3
RETRY_WAIT_MIN = 1
RETRY_WAIT_MAX = 5


@pytest.fixture(scope="session")
def event_loop():
    """Create an event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(scope="session")
async def graphiti_client() -> AsyncGenerator[Graphiti, None]:
    """
    Create a Graphiti client connected to Neo4j.
    Session-scoped to reuse across tests.
    """
    logger.info(f"Connecting to Neo4j at {NEO4J_URI}")
    
    @retry(
        stop=stop_after_attempt(MAX_RETRIES),
        wait=wait_exponential(multiplier=1, min=RETRY_WAIT_MIN, max=RETRY_WAIT_MAX)
    )
    async def connect():
        client = Graphiti(
            uri=NEO4J_URI,
            user=NEO4J_USER,
            password=NEO4J_PASSWORD
        )
        # Verify connectivity
        await client.build_indices_and_constraints()
        return client
    
    client = await connect()
    logger.info("Successfully connected to Neo4j via Graphiti")
    
    yield client
    
    # Cleanup
    await client.close()
    logger.info("Closed Graphiti connection")


@pytest_asyncio.fixture
async def clean_graphiti(graphiti_client: Graphiti):
    """
    Provides a clean Graphiti instance for each test.
    Clears data before and after test execution.
    """
    # Clear before test
    logger.info("Clearing graph data before test")
    await clear_data(graphiti_client.driver)
    await graphiti_client.build_indices_and_constraints()
    
    yield graphiti_client
    
    # Clear after test
    logger.info("Clearing graph data after test")
    await clear_data(graphiti_client.driver)


@pytest_asyncio.fixture
async def warmed_graphiti(graphiti_client: Graphiti):
    """
    Provides a Graphiti instance with warmed cache.
    Performs warmup queries to ensure JVM and caches are hot.
    """
    logger.info("Warming up Neo4j caches")
    
    # Add sample data for warmup
    warmup_episodes = [
        "User John is interested in comfortable walking shoes",
        "Product ManyBirds Wool Runners are made from merino wool",
        "Customer service handled John's return request"
    ]
    
    for i, episode in enumerate(warmup_episodes):
        await graphiti_client.add_episode(
            name=f"warmup_{i}",
            episode_body=episode,
            source=EpisodeType.text,
            reference_time=datetime.now(timezone.utc),
            source_description="warmup"
        )
    
    # Perform warmup searches
    for _ in range(WARMUP_ITERATIONS):
        await graphiti_client.search_nodes("shoes", max_nodes=10)
        await graphiti_client.search_facts("comfortable", max_facts=10)
    
    logger.info("Cache warmup complete")
    
    yield graphiti_client


@pytest.fixture
def sample_episodes() -> List[Dict[str, Any]]:
    """
    Provides sample episode data for testing.
    """
    return [
        {
            "name": "Customer Inquiry",
            "body": "John: I'm looking for running shoes in size 10",
            "source": EpisodeType.message,
            "description": "Customer support chat"
        },
        {
            "name": "Product Info",
            "body": '{"product": {"name": "Wool Runners", "sizes": [8, 9, 10, 11], "price": 98}}',
            "source": EpisodeType.json,
            "description": "Product catalog"
        },
        {
            "name": "Purchase Decision",
            "body": "John purchased Wool Runners in size 10 for $98",
            "source": EpisodeType.text,
            "description": "Transaction record"
        }
    ]


@pytest.fixture
def performance_metrics() -> Dict[str, float]:
    """
    Performance targets for Neo4j with Graphiti on M3 Pro.
    """
    return {
        "search_nodes_max_ms": 100,
        "search_facts_max_ms": 150,
        "add_episode_max_ms": 500,
        "concurrent_read_max_ms": 200,
        "cache_hit_rate_min": 0.95,
        "concurrent_agents_min": 10
    }


@pytest_asyncio.fixture
async def populated_graphiti(clean_graphiti: Graphiti, sample_episodes: List[Dict[str, Any]]):
    """
    Provides a Graphiti instance populated with sample data.
    """
    logger.info("Populating graph with sample episodes")
    
    for episode in sample_episodes:
        await clean_graphiti.add_episode(
            name=episode["name"],
            episode_body=episode["body"],
            source=episode["source"],
            reference_time=datetime.now(timezone.utc),
            source_description=episode["description"]
        )
    
    # Allow time for processing
    await asyncio.sleep(1)
    
    logger.info("Sample data population complete")
    
    yield clean_graphiti


@pytest.fixture
def benchmark_config() -> Dict[str, Any]:
    """
    Configuration for pytest-benchmark.
    """
    return {
        "warmup": True,
        "warmup_iterations": WARMUP_ITERATIONS,
        "min_rounds": BENCHMARK_ROUNDS,
        "max_time": 10.0,
        "disable_gc": True,
        "timer": time.perf_counter
    }


async def get_user_node_uuid(client: Graphiti, user_name: str) -> str:
    """
    Helper to get a user's node UUID.
    """
    from graphiti_core.search.search_config_recipes import NODE_HYBRID_SEARCH_EPISODE_MENTIONS
    
    result = await client._search(user_name, NODE_HYBRID_SEARCH_EPISODE_MENTIONS)
    if result and result.nodes:
        return result.nodes[0].uuid
    return None


async def wait_for_processing(client: Graphiti, max_wait: float = 5.0):
    """
    Wait for episode processing to complete.
    Useful after add_episode operations.
    """
    await asyncio.sleep(0.5)  # Initial delay
    
    start = time.time()
    while time.time() - start < max_wait:
        # Check if processing is complete by attempting a search
        results = await client.search_nodes("test", max_nodes=1)
        if results:
            break
        await asyncio.sleep(0.1)


@pytest.fixture
def assert_performance():
    """
    Helper fixture for performance assertions.
    """
    def _assert(duration: float, max_ms: float, operation: str):
        assert duration * 1000 < max_ms, \
            f"{operation} took {duration*1000:.2f}ms, expected <{max_ms}ms"
    return _assert


# Test markers
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "benchmark: Performance benchmarking tests"
    )
    config.addinivalue_line(
        "markers", "integration: Integration tests requiring Neo4j"
    )
    config.addinivalue_line(
        "markers", "concurrent: Concurrent access pattern tests"
    )
    config.addinivalue_line(
        "markers", "temporal: Temporal query and fact invalidation tests"
    )
    config.addinivalue_line(
        "markers", "slow: Tests that take more than 5 seconds"
    )
    config.addinivalue_line(
        "markers", "warmup: Tests requiring cache warmup"
    )