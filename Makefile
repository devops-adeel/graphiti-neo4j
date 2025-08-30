.PHONY: help up down restart monitor backup test security-check changelog clean

# Default target
help:
	@echo "Neo4j-Graphiti Infrastructure Management"
	@echo "========================================"
	@echo ""
	@echo "Core Operations:"
	@echo "  make up           - Start Neo4j with monitoring"
	@echo "  make down         - Stop Neo4j gracefully"
	@echo "  make restart      - Restart Neo4j (preserves data)"
	@echo "  make reset        - Complete reset (DESTROYS DATA)"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  make backup       - Create manual backup"
	@echo "  make backup-start - Start automated backup services"
	@echo "  make backup-stop  - Stop automated backup services"
	@echo "  make backup-status - Show backup system status"
	@echo "  make backup-verify - Verify backup integrity"
	@echo "  make backup-restore - Interactive restore wizard"
	@echo ""
	@echo "Monitoring & Health:"
	@echo "  make monitor      - Run memory forensics monitor"
	@echo "  make health       - Quick health check"
	@echo "  make logs         - Follow Neo4j logs"
	@echo "  make gc-logs      - Monitor GC activity"
	@echo ""
	@echo "Security & Patches:"
	@echo "  make security     - Run security scans"
	@echo "  make patches      - Apply Graphiti compatibility patches"
	@echo "  make pre-commit   - Install pre-commit hooks"
	@echo ""
	@echo "Testing:"
	@echo "  make test         - Run all tests"
	@echo "  make test-quick   - Quick smoke tests"
	@echo "  make test-memory  - Memory regression tests"
	@echo ""
	@echo "Release Management:"
	@echo "  make changelog    - Generate changelog"
	@echo "  make release      - Prepare new release"

# Core operations
up:
	@echo "Starting Neo4j with memory safety configuration..."
	docker-compose up -d
	@echo "Waiting for Neo4j to be ready (40s JVM warmup)..."
	@sleep 5
	@for i in {1..8}; do \
		if docker exec neo4j-graphiti neo4j status 2>/dev/null | grep -q "is running"; then \
			echo "✓ Neo4j is ready!"; \
			break; \
		fi; \
		echo "  Waiting... ($$((i*5))s)"; \
		sleep 5; \
	done
	@echo ""
	@echo "Access points:"
	@echo "  Browser: http://localhost:7474"
	@echo "  Bolt:    bolt://localhost:7687"
	@echo "  Metrics: http://localhost:2004/metrics"

down:
	@echo "Stopping Neo4j gracefully..."
	docker-compose down

restart: down up

reset:
	@echo "⚠️  WARNING: This will DESTROY all data!"
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	docker-compose down -v
	rm -rf heap_dumps/*.hprof
	docker-compose up -d

# Monitoring
monitor:
	@./scripts/monitor_neo4j.sh

health:
	@docker ps | grep neo4j-graphiti > /dev/null && echo "✓ Container running" || echo "✗ Container not running"
	@docker exec neo4j-graphiti neo4j status 2>/dev/null | grep -q "is running" && echo "✓ Neo4j responding" || echo "✗ Neo4j not responding"
	@docker stats neo4j-graphiti --no-stream

logs:
	docker logs -f neo4j-graphiti

gc-logs:
	@echo "Monitoring GC activity (Ctrl+C to stop)..."
	@docker exec neo4j-graphiti tail -f /logs/gc.log | grep -E "Pause|overhead"

# Backup & Recovery
backup:
	@echo "Creating manual backup..."
	@./scripts/backup.sh manual

backup-start:
	@echo "Starting automated backup services..."
	@./scripts/backup.sh start
	@echo "✓ Backup services started"
	@echo "  Daily:   2 AM (7-day retention)"
	@echo "  Weekly:  3 AM Sundays (4-week retention)"
	@echo "  Monthly: 4 AM on 1st (12-month retention)"

backup-stop:
	@echo "Stopping backup services..."
	@./scripts/backup.sh stop

backup-status:
	@./scripts/backup.sh status

backup-verify:
	@echo "Verifying backup integrity..."
	@./scripts/verify-backup.sh all

backup-verify-quick:
	@./scripts/verify-backup.sh quick daily

backup-verify-full:
	@./scripts/verify-backup.sh full weekly

backup-test-restore:
	@echo "Testing backup restore (will create temporary container)..."
	@./scripts/verify-backup.sh restore daily

backup-emergency:
	@echo "⚠️  Creating emergency backup..."
	@./scripts/backup.sh emergency

backup-restore:
	@echo "==================================="
	@echo "    Neo4j Restore Wizard"
	@echo "==================================="
	@echo ""
	@echo "Available backup tiers:"
	@echo "  1) Daily (last 7 days)"
	@echo "  2) Weekly (last 4 weeks)"
	@echo "  3) Monthly (last 12 months)"
	@echo ""
	@read -p "Select tier [1-3]: " tier && \
	case $$tier in \
		1) tier_name="daily" ;; \
		2) tier_name="weekly" ;; \
		3) tier_name="monthly" ;; \
		*) echo "Invalid selection"; exit 1 ;; \
	esac && \
	echo "" && \
	echo "Available backups in $$tier_name tier:" && \
	ls -lht ~/Neo4jBackups/$$tier_name/*.tar.* | head -10 && \
	echo "" && \
	read -p "Enter backup filename (or 'latest' for most recent): " backup && \
	if [ "$$backup" = "latest" ]; then \
		backup=$$(ls -t ~/Neo4jBackups/$$tier_name/*.tar.* | head -1); \
	else \
		backup=~/Neo4jBackups/$$tier_name/$$backup; \
	fi && \
	echo "" && \
	echo "⚠️  WARNING: This will replace current Neo4j data!" && \
	read -p "Proceed with restore? (y/N): " confirm && \
	if [ "$$confirm" = "y" ]; then \
		echo "Creating safety backup first..." && \
		./scripts/backup.sh emergency && \
		echo "Stopping Neo4j..." && \
		docker-compose stop neo4j && \
		echo "Restoring from $$backup..." && \
		docker run --rm \
			-v neo4j-data:/data \
			-v $$backup:/backup.tar.gz:ro \
			alpine sh -c "cd / && tar -xzf /backup.tar.gz && mv backup/data/* /data/" && \
		echo "Starting Neo4j..." && \
		docker-compose start neo4j && \
		echo "✓ Restore completed successfully"; \
	else \
		echo "Restore cancelled"; \
	fi

backup-clean:
	@echo "Cleaning old backup files..."
	@find ~/Neo4jBackups -name "*.tar.*" -mtime +30 -delete
	@echo "✓ Old backups cleaned"

# Security
security:
	@echo "Running security scans..."
	@if [ ! -f .git/hooks/pre-commit ]; then \
		echo "Installing pre-commit hooks first..."; \
		pre-commit install; \
	fi
	pre-commit run --all-files

patches:
	@echo "Applying Graphiti compatibility patches..."
	python scripts/graphiti_patches.py

pre-commit:
	pre-commit install
	@echo "✓ Pre-commit hooks installed"

# Testing
test:
	@if [ -f tests/requirements.txt ]; then \
		pip install -q -r tests/requirements.txt; \
	fi
	pytest tests/ -v

test-quick:
	./test.sh quick

test-memory:
	@echo "Running memory regression tests..."
	@echo "TODO: Implement memory regression test suite"

# Release management
changelog:
	@if command -v git-cliff > /dev/null; then \
		git cliff --unreleased; \
	else \
		echo "Installing git-cliff..."; \
		cargo install git-cliff || brew install git-cliff; \
		git cliff --unreleased; \
	fi

release:
	@read -p "Version (e.g., v1.0.0): " version && \
	git cliff --tag $$version > CHANGELOG.md && \
	git add CHANGELOG.md && \
	git commit -m "chore(release): prepare $$version" && \
	git tag $$version && \
	echo "✓ Release $$version prepared. Run 'git push --tags' to publish."

# Cleanup
clean:
	@echo "Cleaning up temporary files..."
	rm -rf heap_dumps/*.hprof
	rm -rf __pycache__ .pytest_cache
	find . -name "*.pyc" -delete
	@echo "✓ Cleanup complete"

# Emergency procedures
emergency-gc:
	@echo "Forcing garbage collection..."
	docker exec neo4j-graphiti jcmd 1 GC.run

emergency-kill-queries:
	@echo "Killing all long-running queries..."
	docker exec neo4j-graphiti cypher-shell -u neo4j -p password \
		"CALL dbms.listQueries() YIELD queryId CALL dbms.killQuery(queryId) YIELD message RETURN count(*)"

emergency-heap-dump:
	@echo "Generating heap dump for analysis..."
	docker exec neo4j-graphiti jcmd 1 GC.heap_dump /data/dumps/emergency.hprof
	docker cp neo4j-graphiti:/data/dumps/emergency.hprof ./heap_dumps/
	@echo "✓ Heap dump saved to ./heap_dumps/emergency.hprof"