# Changelog

All notable changes to Neo4j infrastructure for Graphiti agents will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### 🚨 Critical Security & Memory Fixes




### ⚡ Features

- Add Neo4j infrastructure for Graphiti instances (- Docker Compose setup with OrbStack domains (neo4j.graphiti.local)
- Optimized Neo4j 5.26 configuration for 36GB RAM system
- Automated backup script with 7-day retention
- Security-focused .gitignore and .env.example templates
- Memory configuration: 2GB heap + 2GB page cache

🤖 Generated with Claude Code)
- Enhance backup system and monitoring (Backup improvements:
- Integrate offen/docker-volume-backup for automated backups
- Add multi-tier retention (daily/weekly/monthly)
- Create verification and restore procedures
- Add emergency recovery scripts

Monitoring enhancements:
- Add Prometheus metrics endpoint (port 2004)
- Configure JVM heap dumps for OOM forensics
- Add memory monitoring and analysis scripts
- Include Graphiti compatibility patches)



### 📚 Documentation

- Add setup documentation and connection test (- Comprehensive README with quick start guide
- Memory optimization details for 36GB RAM system
- Python test script for Neo4j connectivity verification
- Troubleshooting guide and integration instructions

🤖 Generated with Claude Code)
- Add test documentation and update connection validator (- Document test categories and performance targets
- Update connection test to use Graphiti client
- Add usage examples and configuration guide
- Include prerequisites and setup instructions

🤖 Generated with [Claude Code](https://claude.ai/code))
- Refactor to episode-first architecture (Complete restructuring from Neo4j-centric to Graphiti episode-first approach:
- Add 5-minute chatbot quickstart guide
- Create episode patterns cookbook with copy-paste examples
- Add conceptual guides (episodes-first, temporal knowledge, graph vs vector)
- Include working chatbot and test examples
- Update README with streamlined episode focus
- Document 50x performance advantage over vector RAG

The documentation now targets AI/ML developers building Graphiti applications
without requiring graph database knowledge.)



### 🔧 Miscellaneous Tasks

- Add development tooling and configuration (- Add CLAUDE.md for AI-assisted development guidance
- Create Makefile for common operations
- Configure git-cliff for changelog generation
- Setup pre-commit hooks (Gitleaks, TruffleHog, detect-secrets)
- Add conventional commits configuration)
- Add backup configuration template (Add backup.conf template for customizing backup behavior)



### 🚀 Performance

- Optimize Neo4j memory for 36GB M3 Pro system (- Increase heap memory from 2GB to 4GB
- Increase page cache from 2GB to 8GB
- Optimized for read-heavy multi-agent workloads
- Total memory usage: ~12GB of available 36GB

🤖 Generated with [Claude Code](https://claude.ai/code))



### 🧪 Testing

- Add Graphiti integration test suite for Neo4j (- Add working integration tests using correct Graphiti API
- Test episode processing (text, JSON, message types)
- Validate search performance and concurrent access
- Include test fixtures with e-commerce sample data
- Add test runner script with multiple suite options)

---
Generated with [git-cliff](https://github.com/orhun/git-cliff)
