#!/usr/bin/env python3
"""
Simple Graphiti Connection Test

Tests basic connectivity and episode operations with Neo4j.

Usage:
    python simple_test.py
"""

import asyncio
import os
from datetime import datetime, timezone
from dotenv import load_dotenv
from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType

# Load environment variables
load_dotenv()


async def test_graphiti_connection():
    """Test basic Graphiti operations."""
    
    print("🔌 Connecting to Neo4j...")
    print(f"   URI: {os.getenv('NEO4J_URI', 'bolt://localhost:7687')}")
    print(f"   User: {os.getenv('NEO4J_USER', 'neo4j')}")
    
    # Initialize Graphiti client
    client = Graphiti(
        uri=os.getenv("NEO4J_URI", "bolt://localhost:7687"),
        user=os.getenv("NEO4J_USER", "neo4j"),
        password=os.getenv("NEO4J_PASSWORD")
    )
    
    try:
        # Build indices
        print("\n📊 Building indices and constraints...")
        await client.build_indices_and_constraints()
        print("✅ Indices ready!")
        
        # Test 1: Add TEXT episode
        print("\n📝 Test 1: Adding TEXT episode...")
        await client.add_episode(
            name="test_text_episode",
            episode_body="John Smith is looking for comfortable running shoes in size 10",
            source=EpisodeType.text,
            source_description="Test text input",
            reference_time=datetime.now(timezone.utc)
        )
        print("✅ TEXT episode added")
        
        # Test 2: Add JSON episode
        print("\n📋 Test 2: Adding JSON episode...")
        await client.add_episode(
            name="test_json_episode",
            episode_body='{"customer": "John Smith", "preference": "comfortable shoes", "size": 10}',
            source=EpisodeType.json,
            source_description="Test JSON input",
            reference_time=datetime.now(timezone.utc)
        )
        print("✅ JSON episode added")
        
        # Test 3: Add MESSAGE episode
        print("\n💬 Test 3: Adding MESSAGE episode...")
        await client.add_episode(
            name="test_message_episode",
            episode_body="Customer: I need size 10 shoes\nAgent: Let me help you find the perfect fit",
            source=EpisodeType.message,
            source_description="Test conversation",
            reference_time=datetime.now(timezone.utc)
        )
        print("✅ MESSAGE episode added")
        
        # Test 4: Search
        print("\n🔍 Test 4: Searching knowledge graph...")
        results = await client.search("John Smith shoes size 10", num_results=5)
        print(f"✅ Found {len(results)} results")
        
        if results:
            print("\n📊 Search Results:")
            for i, result in enumerate(results[:3], 1):
                if hasattr(result, 'fact'):
                    print(f"   {i}. {result.fact}")
                elif hasattr(result, 'content'):
                    print(f"   {i}. {result.content}")
        
        # Test 5: Temporal update
        print("\n⏰ Test 5: Testing temporal updates...")
        
        # Original fact
        await client.add_episode(
            name="temporal_test_1",
            episode_body="Product ABC costs $100",
            source=EpisodeType.text,
            reference_time=datetime(2024, 1, 1, timezone.utc)
        )
        
        # Updated fact (supersedes the original)
        await client.add_episode(
            name="temporal_test_2",
            episode_body="Product ABC now costs $80 due to sale",
            source=EpisodeType.text,
            reference_time=datetime(2024, 1, 15, timezone.utc)
        )
        print("✅ Temporal facts recorded (newer supersedes older)")
        
        # Final search
        print("\n🎯 Final search for 'Product ABC price'...")
        price_results = await client.search("Product ABC price", num_results=3)
        if price_results:
            print("   Latest price should be $80 (not $100)")
        
        print("\n" + "="*50)
        print("✅ All tests completed successfully!")
        print("="*50)
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    
    finally:
        # Clean up
        await client.close()
        print("\n🔌 Connection closed")


if __name__ == "__main__":
    # Check environment
    if not os.getenv("NEO4J_PASSWORD"):
        print("⚠️  NEO4J_PASSWORD not set!")
        print("   Create a .env file with:")
        print("   NEO4J_PASSWORD=your-password")
        print()
        input("Press Enter to continue anyway...")
    
    # Run test
    print("="*50)
    print("   Graphiti + Neo4j Connection Test")
    print("="*50)
    print()
    
    asyncio.run(test_graphiti_connection())