#!/bin/bash

# Neo4j Backup Hooks for Graphiti
# Pre and post backup operations for data integrity and optimization

set -e  # Exit on error

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/backup/backup.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

# Get memory stats from Neo4j
get_memory_stats() {
    docker exec ${CONTAINER_NAME} cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
        "CALL dbms.queryJmx('org.neo4j:instance=kernel#0,name=Transactions') YIELD attributes 
         RETURN attributes" 2>/dev/null || echo "{}"
}

# Check if Neo4j is running
is_neo4j_running() {
    docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

# Pre-backup operations
pre_backup() {
    local backup_tier=${1:-daily}
    log "INFO" "${GREEN}Starting pre-backup operations for $backup_tier backup${NC}"
    
    # Check if Neo4j is running (it will be stopped by offen/docker-volume-backup)
    if is_neo4j_running; then
        log "INFO" "Neo4j is running, preparing for backup..."
        
        # 1. Force checkpoint to flush transactions
        log "INFO" "Forcing checkpoint..."
        docker exec ${CONTAINER_NAME} cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
            "CALL db.checkpoint()" 2>/dev/null || true
        
        # 2. Clear query caches
        log "INFO" "Clearing query caches..."
        docker exec ${CONTAINER_NAME} cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
            "CALL db.clearQueryCaches()" 2>/dev/null || true
        
        # 3. Get current memory usage for forensics
        if [ "$BACKUP_METRICS" = "true" ]; then
            log "INFO" "Capturing memory metrics..."
            MEMORY_STATS=$(get_memory_stats)
            echo "$MEMORY_STATS" > "/tmp/neo4j-memory-pre-backup-$(date +%Y%m%d-%H%M%S).json"
        fi
        
        # 4. Create neo4j-admin dump for portability (if configured)
        if [ "$NEO4J_ADMIN_DUMP" = "true" ] && [ "$backup_tier" != "manual" ]; then
            log "INFO" "Creating neo4j-admin dump..."
            DUMP_FILE="/dumps/neo4j-${backup_tier}-$(date +%Y%m%d-%H%M%S).dump"
            
            # Note: This will be executed while Neo4j is stopped by offen/docker-volume-backup
            # We're just preparing the command here
            echo "neo4j-admin database dump --to-path=/dumps --overwrite-destination=true neo4j" \
                > /tmp/neo4j-dump-command.sh
            chmod +x /tmp/neo4j-dump-command.sh
        fi
        
        # 5. Check heap usage and warn if high
        HEAP_USAGE=$(docker exec ${CONTAINER_NAME} sh -c \
            "jcmd 1 GC.heap_info 2>/dev/null | grep -E 'used.*%' | sed 's/.*(\([0-9]*\)%.*/\1/'" || echo "0")
        
        if [ "$HEAP_USAGE" -gt "${NEO4J_HEAP_THRESHOLD:-85}" ]; then
            log "WARN" "${YELLOW}High heap usage detected: ${HEAP_USAGE}%${NC}"
            log "WARN" "Consider running emergency GC before backup"
        fi
        
        # 6. Record Graphiti session metadata (if applicable)
        if [ "$GRAPHITI_SESSION_METADATA" = "true" ]; then
            log "INFO" "Recording Graphiti session metadata..."
            docker exec ${CONTAINER_NAME} cypher-shell -u neo4j -p "${NEO4J_PASSWORD}" \
                "MATCH (n) RETURN count(n) as node_count, 
                 count(distinct labels(n)) as label_count" \
                > /tmp/graphiti-metadata-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null || true
        fi
    else
        log "WARN" "${YELLOW}Neo4j is not running, skipping pre-backup operations${NC}"
    fi
    
    log "INFO" "${GREEN}Pre-backup operations completed${NC}"
}

# Post-backup operations
post_backup() {
    local backup_tier=${1:-daily}
    local archive_path=${2:-/archive}
    
    log "INFO" "${GREEN}Starting post-backup operations for $backup_tier backup${NC}"
    
    # 1. Verify backup was created
    LATEST_BACKUP=$(ls -t ${archive_path}/${backup_tier}/*.tar.* 2>/dev/null | head -1)
    if [ -z "$LATEST_BACKUP" ]; then
        log "ERROR" "${RED}No backup file found in ${archive_path}/${backup_tier}${NC}"
        exit 1
    fi
    
    log "INFO" "Latest backup: $(basename $LATEST_BACKUP)"
    BACKUP_SIZE=$(du -h "$LATEST_BACKUP" | cut -f1)
    log "INFO" "Backup size: $BACKUP_SIZE"
    
    # 2. Generate checksum (if configured)
    if [ "$BACKUP_CHECKSUM" = "true" ]; then
        log "INFO" "Generating SHA256 checksum..."
        sha256sum "$LATEST_BACKUP" > "${LATEST_BACKUP}.sha256"
        log "INFO" "Checksum saved to ${LATEST_BACKUP}.sha256"
    fi
    
    # 3. Verify backup integrity (if configured)
    if [ "$BACKUP_VERIFY" = "true" ]; then
        log "INFO" "Verifying backup integrity..."
        if tar -tzf "$LATEST_BACKUP" > /dev/null 2>&1; then
            log "INFO" "${GREEN}Backup integrity verified successfully${NC}"
        else
            log "ERROR" "${RED}Backup integrity check failed!${NC}"
            exit 1
        fi
    fi
    
    # 4. Sync to external drive (if available)
    if [ "$SYNC_ON_BACKUP" = "true" ] && [ -d "$EXTERNAL_BACKUP_DIR" ]; then
        log "INFO" "Syncing to external drive: $EXTERNAL_BACKUP_DIR"
        
        # Create tier directory on external drive
        mkdir -p "${EXTERNAL_BACKUP_DIR}/${backup_tier}"
        
        # Sync with rsync
        rsync ${SYNC_RSYNC_OPTIONS} \
            "${archive_path}/${backup_tier}/" \
            "${EXTERNAL_BACKUP_DIR}/${backup_tier}/"
        
        if [ $? -eq 0 ]; then
            log "INFO" "${GREEN}Successfully synced to external drive${NC}"
        else
            log "WARN" "${YELLOW}External sync failed, backup is safe locally${NC}"
        fi
    elif [ "$SYNC_ON_BACKUP" = "true" ]; then
        log "INFO" "External drive not mounted at $EXTERNAL_BACKUP_DIR, skipping sync"
    fi
    
    # 5. Clean up old dumps (if configured)
    if [ "$CLEANUP_OLD_DUMPS" = "true" ] && [ -d "/dumps" ]; then
        log "INFO" "Cleaning up old neo4j-admin dumps..."
        find /dumps -name "*.dump" -type f -mtime +${BACKUP_RETENTION_DAILY} -delete
    fi
    
    # 6. Export metrics for Prometheus
    if [ "$BACKUP_METRICS" = "true" ]; then
        TIMESTAMP=$(date +%s)
        cat > /metrics/backup-${backup_tier}.prom <<EOF
# HELP neo4j_backup_last_success Last successful backup timestamp
# TYPE neo4j_backup_last_success gauge
neo4j_backup_last_success{tier="${backup_tier}"} ${TIMESTAMP}

# HELP neo4j_backup_size_bytes Backup file size in bytes
# TYPE neo4j_backup_size_bytes gauge
neo4j_backup_size_bytes{tier="${backup_tier}"} $(stat -f%z "$LATEST_BACKUP" 2>/dev/null || stat -c%s "$LATEST_BACKUP")

# HELP neo4j_backup_duration_seconds Backup duration
# TYPE neo4j_backup_duration_seconds gauge
neo4j_backup_duration_seconds{tier="${backup_tier}"} $(($(date +%s) - ${BACKUP_START_TIME:-0}))
EOF
        log "INFO" "Metrics exported to /metrics/backup-${backup_tier}.prom"
    fi
    
    # 7. Send notification (if configured)
    if [ -n "$NOTIFICATION_WEBHOOK" ]; then
        curl -X POST "$NOTIFICATION_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"Neo4j backup completed: ${backup_tier} (${BACKUP_SIZE})\"}" \
            2>/dev/null || true
    fi
    
    # 8. Clean up orphaned lock files
    if [ "$CLEANUP_ORPHANED_LOCKS" = "true" ] && [ -f "$BACKUP_LOCK_FILE" ]; then
        LOCK_AGE=$(($(date +%s) - $(stat -f%m "$BACKUP_LOCK_FILE" 2>/dev/null || stat -c%Y "$BACKUP_LOCK_FILE")))
        if [ $LOCK_AGE -gt ${BACKUP_LOCK_TIMEOUT:-7200} ]; then
            log "INFO" "Removing orphaned lock file (age: ${LOCK_AGE}s)"
            rm -f "$BACKUP_LOCK_FILE"
        fi
    fi
    
    log "INFO" "${GREEN}Post-backup operations completed successfully${NC}"
}

# Emergency backup function
emergency_backup() {
    log "WARN" "${YELLOW}Starting emergency backup procedure${NC}"
    
    # Create emergency dump directory
    EMERGENCY_DIR="${PRIMARY_BACKUP_DIR}/emergency"
    mkdir -p "$EMERGENCY_DIR"
    
    # Stop Neo4j if running
    if is_neo4j_running; then
        log "INFO" "Stopping Neo4j for emergency backup..."
        docker stop ${CONTAINER_NAME}
        sleep 5
    fi
    
    # Create tar backup of data directory
    EMERGENCY_FILE="${EMERGENCY_DIR}/neo4j-emergency-$(date +%Y%m%d-%H%M%S).tar.gz"
    log "INFO" "Creating emergency backup: $EMERGENCY_FILE"
    
    docker run --rm \
        -v neo4j-data:/data:ro \
        -v ${EMERGENCY_DIR}:/backup \
        alpine tar czf /backup/$(basename $EMERGENCY_FILE) -C / data
    
    if [ $? -eq 0 ]; then
        log "INFO" "${GREEN}Emergency backup created successfully${NC}"
        log "INFO" "Backup location: $EMERGENCY_FILE"
    else
        log "ERROR" "${RED}Emergency backup failed!${NC}"
        exit 1
    fi
    
    # Restart Neo4j
    log "INFO" "Restarting Neo4j..."
    docker start ${CONTAINER_NAME}
}

# Main execution
case "${1:-help}" in
    pre-backup)
        BACKUP_START_TIME=$(date +%s)
        export BACKUP_START_TIME
        pre_backup "$2"
        ;;
    post-backup)
        post_backup "$2" "$3"
        ;;
    emergency)
        emergency_backup
        ;;
    test)
        log "INFO" "Testing backup hooks..."
        log "INFO" "Configuration loaded from: $CONFIG_FILE"
        log "INFO" "Container name: ${CONTAINER_NAME}"
        log "INFO" "Backup directory: ${PRIMARY_BACKUP_DIR}"
        if is_neo4j_running; then
            log "INFO" "${GREEN}Neo4j is running${NC}"
        else
            log "WARN" "${YELLOW}Neo4j is not running${NC}"
        fi
        ;;
    *)
        echo "Usage: $0 {pre-backup|post-backup|emergency|test} [tier] [archive_path]"
        echo ""
        echo "Commands:"
        echo "  pre-backup [tier]     - Run pre-backup operations"
        echo "  post-backup [tier] [path] - Run post-backup operations"
        echo "  emergency            - Create emergency backup"
        echo "  test                - Test configuration and connectivity"
        exit 1
        ;;
esac