#!/usr/bin/env python3
"""
5-Minute Chatbot with Graphiti Memory

This example demonstrates:
- Episode ingestion (text, json, message types)
- Temporal knowledge persistence
- Relationship-based search
- Langfuse observability integration

Requirements:
    pip install graphiti-core[neo4j] langfuse python-dotenv

Usage:
    python quickstart_chatbot.py
"""

import asyncio
import os
from datetime import datetime, timezone
from dotenv import load_dotenv
from graphiti_core import Graphiti
from graphiti_core.nodes import EpisodeType

# Optional: Enable Langfuse tracing
try:
    from langfuse.decorators import observe
except ImportError:
    # Fallback if Langfuse not installed
    def observe(name=None):
        def decorator(func):
            return func
        return decorator

# Load environment variables
load_dotenv()


class MemoryChatbot:
    """A simple chatbot with persistent episodic memory using Graphiti."""
    
    def __init__(self):
        """Initialize the chatbot with Graphiti connection."""
        self.graphiti = Graphiti(
            uri=os.getenv("NEO4J_URI", "bolt://localhost:7687"),
            user=os.getenv("NEO4J_USER", "neo4j"),
            password=os.getenv("NEO4J_PASSWORD")
        )
        self.conversation_count = 0
        self.user_name = None
    
    async def initialize(self):
        """Set up the knowledge graph indices and constraints."""
        print("🔧 Initializing knowledge graph...")
        await self.graphiti.build_indices_and_constraints()
        print("✅ Chatbot initialized with memory!\n")
    
    async def load_product_knowledge(self):
        """Load initial product catalog as JSON episode."""
        print("📚 Loading product knowledge...")
        
        product_catalog = {
            "products": [
                {
                    "name": "Wool Runners",
                    "category": "running shoes",
                    "sizes": [8, 9, 10, 11, 12],
                    "colors": ["Natural Black", "Tree Green", "Mist"],
                    "price": 98.00,
                    "material": "merino wool",
                    "features": ["comfortable", "breathable", "machine washable"]
                },
                {
                    "name": "Tree Dashers",
                    "category": "running shoes", 
                    "sizes": [7, 8, 9, 10, 11],
                    "colors": ["Thunder", "Flame", "Aurora"],
                    "price": 135.00,
                    "material": "eucalyptus tree fiber",
                    "features": ["lightweight", "responsive", "sustainable"]
                },
                {
                    "name": "Trail Runners SWT",
                    "category": "trail shoes",
                    "sizes": [8, 9, 10, 11, 12, 13],
                    "colors": ["Rock", "Thrive", "Moonrise"],
                    "price": 148.00,
                    "material": "sugarcane-based foam",
                    "features": ["grip", "water-repellent", "all-terrain"]
                }
            ]
        }
        
        await self.graphiti.add_episode(
            name="product_catalog_initial",
            episode_body=str(product_catalog),
            source=EpisodeType.json,
            source_description="Product database import",
            reference_time=datetime.now(timezone.utc)
        )
        
        print("✅ Product knowledge loaded!\n")
    
    @observe(name="chat_interaction")
    async def process_message(self, message: str) -> str:
        """
        Process user message and generate response with context.
        
        Args:
            message: User's input message
            
        Returns:
            Assistant's response based on knowledge graph context
        """
        # Store user message as episode
        await self.graphiti.add_episode(
            name=f"user_message_{self.conversation_count}",
            episode_body=f"{self.user_name}: {message}",
            source=EpisodeType.message,
            source_description="User chat input",
            reference_time=datetime.now(timezone.utc)
        )
        
        # Search for relevant context
        context_results = await self.graphiti.search(
            query=message,
            num_results=5
        )
        
        # Generate response based on context
        if context_results:
            # Format context as bullet points
            context_items = []
            for result in context_results:
                # Extract the fact from the result
                if hasattr(result, 'fact'):
                    context_items.append(f"• {result.fact}")
                elif hasattr(result, 'content'):
                    context_items.append(f"• {result.content}")
            
            if context_items:
                context_str = "\n".join(context_items)
                response = f"Based on what I know:\n{context_str}\n\nHow else can I help you?"
            else:
                response = "I'm still learning about your preferences. Could you tell me more?"
        else:
            response = "I'm here to help! Tell me what you're looking for."
        
        # Store assistant response as episode
        await self.graphiti.add_episode(
            name=f"assistant_response_{self.conversation_count}",
            episode_body=f"Assistant: {response}",
            source=EpisodeType.message,
            source_description="Assistant response",
            reference_time=datetime.now(timezone.utc)
        )
        
        self.conversation_count += 1
        return response
    
    async def demonstrate_temporal_update(self):
        """Show how Graphiti handles temporal fact updates."""
        print("\n📅 Demonstrating temporal updates...")
        
        # Monday: Original price
        await self.graphiti.add_episode(
            name="price_update_monday",
            episode_body="Wool Runners are on sale for $79 this week only",
            source=EpisodeType.text,
            source_description="Marketing promotion",
            reference_time=datetime(2024, 3, 4, timezone.utc)  # Monday
        )
        
        # Wednesday: Price change
        await self.graphiti.add_episode(
            name="price_update_wednesday", 
            episode_body="Wool Runners sale extended - now $69 for clearance",
            source=EpisodeType.text,
            source_description="Clearance update",
            reference_time=datetime(2024, 3, 6, timezone.utc)  # Wednesday
        )
        
        print("✅ Temporal updates recorded - latest facts will supersede old ones\n")
    
    async def close(self):
        """Clean up Graphiti connection."""
        await self.graphiti.close()


async def interactive_chat_loop(bot: MemoryChatbot):
    """Run the interactive chat interface."""
    print("🤖 Chatbot ready! Type 'quit' to exit.")
    print("💡 Try asking about:")
    print("   - 'I need running shoes'")
    print("   - 'What shoes do you have in size 11?'")
    print("   - 'I have wide feet'")
    print("   - 'What's on sale?'\n")
    
    # Get user name
    bot.user_name = input("What's your name? ")
    print(f"\nHello {bot.user_name}! How can I help you today?\n")
    
    while True:
        # Get user input
        message = input(f"{bot.user_name}: ").strip()
        
        if message.lower() in ['quit', 'exit', 'bye']:
            print("\n👋 Thanks for chatting! Your conversation has been saved.")
            break
        
        if not message:
            continue
        
        # Process message and get response
        response = await bot.process_message(message)
        print(f"\n🤖 Assistant: {response}\n")


async def main():
    """Main entry point for the chatbot application."""
    print("=" * 60)
    print("   Graphiti Memory Chatbot - Quickstart Example")
    print("=" * 60)
    print()
    
    # Create and initialize chatbot
    bot = MemoryChatbot()
    
    try:
        # Initialize knowledge graph
        await bot.initialize()
        
        # Load initial knowledge
        await bot.load_product_knowledge()
        
        # Optional: Demonstrate temporal updates
        # await bot.demonstrate_temporal_update()
        
        # Run interactive chat
        await interactive_chat_loop(bot)
        
    finally:
        # Clean up
        await bot.close()
        print("\n✅ Connection closed. Goodbye!")


if __name__ == "__main__":
    # Check for required environment variables
    if not os.getenv("NEO4J_PASSWORD"):
        print("⚠️  Warning: NEO4J_PASSWORD not set in environment")
        print("   Please create a .env file with:")
        print("   NEO4J_PASSWORD=your-password")
        print()
    
    # Run the async main function
    asyncio.run(main())