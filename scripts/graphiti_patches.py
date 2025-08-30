#!/usr/bin/env python3
"""
Graphiti Compatibility Patches for Neo4j

Fixes known issues with Graphiti when using Neo4j as the backend:
1. Issue #848: Async/sync session incompatibility
2. Issue #787: Rate limiting with concurrent episodes
3. Memory safety for large batch operations
"""

import os
import sys
import logging
from pathlib import Path
from typing import Optional, Dict, Any
import warnings

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class GraphitiNeo4jPatcher:
    """Patches for Graphiti-Neo4j compatibility issues"""
    
    def __init__(self, graphiti_path: Optional[str] = None):
        """
        Initialize patcher with Graphiti installation path
        
        Args:
            graphiti_path: Path to Graphiti installation (auto-detect if None)
        """
        self.graphiti_path = self._find_graphiti_path(graphiti_path)
        self.patches_applied = []
        
    def _find_graphiti_path(self, custom_path: Optional[str] = None) -> Path:
        """Find Graphiti installation path"""
        if custom_path:
            return Path(custom_path)
            
        # Try common locations
        possible_paths = [
            Path.cwd() / "graphiti_core",
            Path.home() / ".local/lib/python*/site-packages/graphiti_core",
            Path("/usr/local/lib/python*/site-packages/graphiti_core"),
            Path("./venv/lib/python*/site-packages/graphiti_core"),
        ]
        
        for path_pattern in possible_paths:
            matches = list(Path("/").glob(str(path_pattern).lstrip("/")))
            if matches:
                logger.info(f"Found Graphiti at: {matches[0]}")
                return matches[0]
                
        raise FileNotFoundError(
            "Could not find Graphiti installation. "
            "Please specify path explicitly."
        )
    
    def patch_async_sync_sessions(self) -> bool:
        """
        Fix Issue #848: Async context manager used with sync driver
        
        The bug is in graph_data_operations.py where async with is used
        on a synchronous Neo4j driver session.
        """
        try:
            operations_file = self.graphiti_path / "utils/maintenance/graph_data_operations.py"
            
            if not operations_file.exists():
                logger.warning(f"File not found: {operations_file}")
                return False
                
            # Read the file
            content = operations_file.read_text()
            original_content = content
            
            # Fix 1: Replace async with in clear_data function
            if "async with driver.session() as session:" in content:
                content = content.replace(
                    "async with driver.session() as session:",
                    "with driver.session() as session:"
                )
                logger.info("Patched: async with -> with in clear_data")
                
            # Fix 2: Check for other async session usages
            if "async with session" in content and "async def" in content:
                logger.warning(
                    "Found additional async session usage. "
                    "Manual review recommended."
                )
                
            # Write back if changed
            if content != original_content:
                # Backup original
                backup_file = operations_file.with_suffix('.py.bak')
                backup_file.write_text(original_content)
                logger.info(f"Backed up original to: {backup_file}")
                
                # Write patched version
                operations_file.write_text(content)
                self.patches_applied.append("async_sync_sessions")
                logger.info("✓ Async/sync session patch applied successfully")
                return True
            else:
                logger.info("No async/sync patches needed")
                return False
                
        except Exception as e:
            logger.error(f"Failed to apply async/sync patch: {e}")
            return False
    
    def create_episode_batching_config(self) -> Dict[str, Any]:
        """
        Create configuration for episode batching to prevent memory issues
        Addresses Issue #787: Rate limiting with concurrent episodes
        """
        config = {
            'SEMAPHORE_LIMIT': 1,  # Prevent concurrent processing
            'EPISODE_BATCH_SIZE': 100,  # Limit batch size
            'MAX_CONCURRENT_EPISODES': 5,  # Max parallel episodes
            'MEMORY_SAFETY_FACTOR': 0.8,  # Use max 80% of available memory
            'TRANSACTION_TIMEOUT': '30s',  # Prevent runaway queries
            'MAX_RETRIES': 3,  # Retry failed episodes
            'RETRY_DELAY': 5,  # Seconds between retries
        }
        
        # Write to config file
        config_path = Path("config/graphiti_config.env")
        config_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(config_path, 'w') as f:
            f.write("# Graphiti Episode Batching Configuration\n")
            f.write("# Prevents memory explosions and rate limiting\n\n")
            
            for key, value in config.items():
                f.write(f"{key}={value}\n")
                
        logger.info(f"✓ Episode batching config written to: {config_path}")
        self.patches_applied.append("episode_batching")
        return config
    
    def validate_neo4j_driver(self) -> bool:
        """
        Validate that Neo4j driver is configured correctly
        """
        try:
            from neo4j import GraphDatabase
            
            # Test if driver supports async
            driver = GraphDatabase.driver("bolt://localhost:7687")
            session = driver.session()
            
            # Check for async context manager support
            has_async = hasattr(session, '__aenter__') and hasattr(session, '__aexit__')
            
            if has_async:
                logger.warning(
                    "Driver has async support. "
                    "Ensure Graphiti uses AsyncGraphDatabase.driver()"
                )
            else:
                logger.info("✓ Driver is synchronous (correct for current Graphiti)")
                
            driver.close()
            return True
            
        except ImportError:
            logger.error("Neo4j driver not installed. Run: pip install neo4j")
            return False
        except Exception as e:
            logger.warning(f"Could not validate driver: {e}")
            return False
    
    def create_memory_safe_wrapper(self) -> None:
        """
        Create a memory-safe wrapper for Graphiti operations
        """
        wrapper_content = '''#!/usr/bin/env python3
"""
Memory-safe wrapper for Graphiti operations with Neo4j
Prevents OOM by monitoring memory before operations
"""

import psutil
import asyncio
from typing import Any, Dict, Optional
from graphiti_core import Graphiti

class MemorySafeGraphiti:
    """Wrapper that checks memory before operations"""
    
    def __init__(self, *args, memory_threshold: float = 0.8, **kwargs):
        self.graphiti = Graphiti(*args, **kwargs)
        self.memory_threshold = memory_threshold
        
    def check_memory(self) -> bool:
        """Check if memory usage is safe"""
        memory = psutil.virtual_memory()
        usage_percent = memory.percent / 100
        
        if usage_percent > self.memory_threshold:
            raise MemoryError(
                f"Memory usage {usage_percent:.1%} exceeds "
                f"threshold {self.memory_threshold:.1%}"
            )
        return True
        
    async def add_episode(self, *args, batch_size: int = 100, **kwargs):
        """Add episode with memory checks"""
        self.check_memory()
        
        # If episode is large, process in batches
        if hasattr(args[0], '__len__') and len(args[0]) > batch_size:
            results = []
            data = args[0]
            
            for i in range(0, len(data), batch_size):
                self.check_memory()  # Check before each batch
                batch = data[i:i+batch_size]
                result = await self.graphiti.add_episode(batch, *args[1:], **kwargs)
                results.append(result)
                
                # Small delay between batches
                await asyncio.sleep(0.1)
                
            return results
        else:
            return await self.graphiti.add_episode(*args, **kwargs)
            
    def __getattr__(self, name):
        """Proxy other methods to underlying Graphiti instance"""
        return getattr(self.graphiti, name)

# Usage example:
if __name__ == "__main__":
    # Use memory-safe wrapper
    graphiti = MemorySafeGraphiti(
        "bolt://localhost:7687",
        "neo4j",
        "password",
        memory_threshold=0.75  # Stop at 75% memory usage
    )
    
    # Now use normally - will raise MemoryError if threshold exceeded
    # await graphiti.add_episode(episode_data)
'''
        
        wrapper_path = Path("scripts/memory_safe_graphiti.py")
        wrapper_path.parent.mkdir(parents=True, exist_ok=True)
        wrapper_path.write_text(wrapper_content)
        wrapper_path.chmod(0o755)
        
        logger.info(f"✓ Memory-safe wrapper created at: {wrapper_path}")
        self.patches_applied.append("memory_safe_wrapper")
    
    def apply_all_patches(self) -> Dict[str, bool]:
        """Apply all compatibility patches"""
        results = {
            'async_sync_sessions': self.patch_async_sync_sessions(),
            'episode_batching': bool(self.create_episode_batching_config()),
            'neo4j_validation': self.validate_neo4j_driver(),
            'memory_wrapper': bool(self.create_memory_safe_wrapper())
        }
        
        logger.info("\n" + "="*50)
        logger.info("Patch Summary:")
        for patch, success in results.items():
            status = "✓" if success else "✗"
            logger.info(f"  {status} {patch}: {'Applied' if success else 'Failed'}")
        logger.info("="*50)
        
        return results


def main():
    """Main entry point for patch application"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Apply Graphiti-Neo4j compatibility patches"
    )
    parser.add_argument(
        '--graphiti-path',
        help='Path to Graphiti installation',
        default=None
    )
    parser.add_argument(
        '--check-only',
        action='store_true',
        help='Only validate, do not apply patches'
    )
    
    args = parser.parse_args()
    
    try:
        patcher = GraphitiNeo4jPatcher(args.graphiti_path)
        
        if args.check_only:
            logger.info("Running validation only...")
            patcher.validate_neo4j_driver()
        else:
            logger.info("Applying Graphiti-Neo4j compatibility patches...")
            results = patcher.apply_all_patches()
            
            # Exit code based on success
            if all(results.values()):
                logger.info("\n✓ All patches applied successfully!")
                sys.exit(0)
            else:
                logger.warning("\n⚠ Some patches failed. Review logs above.")
                sys.exit(1)
                
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(2)


if __name__ == "__main__":
    main()