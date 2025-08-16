#!/usr/bin/env python3
"""Test Neo4j connection"""

import asyncio
from neo4j import AsyncGraphDatabase
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

async def test_connection():
    """Test Neo4j connection"""
    uri = "bolt://localhost:7687"
    user = os.getenv("NEO4J_USER", "neo4j")
    password = os.getenv("NEO4J_PASSWORD")
    
    if not password:
        print("❌ No password found in .env file")
        return False
    
    driver = AsyncGraphDatabase.driver(uri, auth=(user, password))
    
    try:
        # Verify connectivity
        await driver.verify_connectivity()
        print(f"✅ Connected to Neo4j at {uri}")
        
        # Get server info
        async with driver.session() as session:
            result = await session.run("CALL dbms.components() YIELD name, versions")
            records = await result.single()
            print(f"   Server: Neo4j {records['versions'][0]}")
            
            # Check database
            result = await session.run("SHOW DATABASE neo4j")
            record = await result.single()
            print(f"   Database: {record['name']} (status: {record['currentStatus']})")
            
        print("✅ Neo4j is ready for Graphiti!")
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False
        
    finally:
        await driver.close()

if __name__ == "__main__":
    asyncio.run(test_connection())