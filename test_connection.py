#\!/usr/bin/env python
"""
Test Neo4j connection and Graphiti initialization.
"""

import asyncio
import os
from dotenv import load_dotenv
from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType

# Load environment variables
load_dotenv()

# Neo4j connection settings
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD")  # No default - must be set in .env

async def test_connection():
    print(f"Connecting to Neo4j at {NEO4J_URI}")
    print(f"User: {NEO4J_USER}")
    
    try:
        # Initialize Graphiti client
        client = Graphiti(
            uri=NEO4J_URI,
            user=NEO4J_USER,
            password=NEO4J_PASSWORD
        )
        
        print("✓ Graphiti client initialized successfully")
        
        # Try a simple operation
        await client.build_indices_and_constraints()
        print("✓ Indices and constraints built")
        
        # Add a test episode
        from datetime import datetime, timezone
        await client.add_episode(
            name="test_episode",
            episode_body="Testing Neo4j connection with Graphiti for searching",
            source=EpisodeType.text,
            source_description="Test connection script",
            reference_time=datetime.now(timezone.utc)
        )
        print("✓ Test episode added successfully")
        
        # Wait for processing
        await asyncio.sleep(2)
        
        # Search for it using the correct method
        results = await client.search("testing", num_results=5)
        print(f"✓ Search completed, found {len(results)} results")
        
        await client.close()
        print("✓ Connection closed successfully")
        print("\n✅ All tests passed\! Neo4j and Graphiti are working correctly.")
        
    except Exception as e:
        print(f"✗ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_connection())
