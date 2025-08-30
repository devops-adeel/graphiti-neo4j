#!/bin/bash

# Neo4j Backup Verification Script
# Comprehensive backup integrity and recovery testing

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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
BACKUP_DIR="${PRIMARY_BACKUP_DIR:-${HOME}/Neo4jBackups}"
VERIFY_MODE="${1:-quick}"
BACKUP_TIER="${2:-daily}"
BACKUP_FILE="${3:-latest}"

# Logging function
log() {
    local level=$1
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# Print header
print_header() {
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}       Neo4j Backup Verification Tool        ${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""
}

# Find latest backup
find_latest_backup() {
    local tier=$1
    local backup_path="${BACKUP_DIR}/${tier}"
    
    if [ ! -d "$backup_path" ]; then
        log "ERROR" "${RED}Backup directory not found: $backup_path${NC}"
        return 1
    fi
    
    local latest=$(ls -t ${backup_path}/*.tar.* 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        log "ERROR" "${RED}No backup files found in $backup_path${NC}"
        return 1
    fi
    
    echo "$latest"
}

# Verify backup checksum
verify_checksum() {
    local backup_file=$1
    local checksum_file="${backup_file}.sha256"
    
    if [ ! -f "$checksum_file" ]; then
        log "WARN" "${YELLOW}No checksum file found for $(basename $backup_file)${NC}"
        return 1
    fi
    
    log "INFO" "Verifying checksum..."
    if sha256sum -c "$checksum_file" > /dev/null 2>&1; then
        log "INFO" "${GREEN}✓ Checksum verification passed${NC}"
        return 0
    else
        log "ERROR" "${RED}✗ Checksum verification failed!${NC}"
        return 1
    fi
}

# Quick verification (tar integrity only)
verify_quick() {
    local backup_file=$1
    
    log "INFO" "Running quick verification on $(basename $backup_file)"
    log "INFO" "File size: $(du -h $backup_file | cut -f1)"
    
    # Check tar integrity
    if tar -tzf "$backup_file" > /dev/null 2>&1; then
        log "INFO" "${GREEN}✓ Tar archive integrity verified${NC}"
    else
        log "ERROR" "${RED}✗ Tar archive is corrupted!${NC}"
        return 1
    fi
    
    # List contents summary
    log "INFO" "Archive contents:"
    tar -tzf "$backup_file" | head -20
    echo "..."
    
    # Count files
    local file_count=$(tar -tzf "$backup_file" | wc -l)
    log "INFO" "Total files in archive: $file_count"
    
    return 0
}

# Full verification (extract and check structure)
verify_full() {
    local backup_file=$1
    local temp_dir="/tmp/neo4j-backup-verify-$$"
    
    log "INFO" "Running full verification on $(basename $backup_file)"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    trap "rm -rf $temp_dir" EXIT
    
    # Extract backup
    log "INFO" "Extracting backup to temporary directory..."
    if ! tar -xzf "$backup_file" -C "$temp_dir"; then
        log "ERROR" "${RED}Failed to extract backup!${NC}"
        return 1
    fi
    
    # Check expected directories
    log "INFO" "Verifying backup structure..."
    local expected_dirs=("data" "logs" "conf")
    local missing_dirs=()
    
    for dir in "${expected_dirs[@]}"; do
        if [ ! -d "$temp_dir/backup/$dir" ]; then
            missing_dirs+=("$dir")
        else
            log "INFO" "${GREEN}✓ Found $dir directory${NC}"
        fi
    done
    
    if [ ${#missing_dirs[@]} -gt 0 ]; then
        log "WARN" "${YELLOW}Missing directories: ${missing_dirs[*]}${NC}"
    fi
    
    # Check Neo4j database files
    if [ -d "$temp_dir/backup/data/databases" ]; then
        log "INFO" "${GREEN}✓ Database files present${NC}"
        
        # Check for neo4j database specifically
        if [ -d "$temp_dir/backup/data/databases/neo4j" ]; then
            log "INFO" "${GREEN}✓ Neo4j database found${NC}"
            
            # Check store files
            local store_files=("neostore" "neostore.counts.db" "neostore.labelscanstore.db")
            for file in "${store_files[@]}"; do
                if [ -f "$temp_dir/backup/data/databases/neo4j/$file" ]; then
                    log "INFO" "${GREEN}  ✓ $file present${NC}"
                else
                    log "WARN" "${YELLOW}  ✗ $file missing${NC}"
                fi
            done
        else
            log "ERROR" "${RED}✗ Neo4j database not found in backup!${NC}"
            return 1
        fi
    else
        log "ERROR" "${RED}✗ No database files in backup!${NC}"
        return 1
    fi
    
    # Check configuration files
    if [ -d "$temp_dir/backup/conf" ]; then
        if [ -f "$temp_dir/backup/conf/neo4j.conf" ]; then
            log "INFO" "${GREEN}✓ Neo4j configuration found${NC}"
        else
            log "WARN" "${YELLOW}✗ Neo4j configuration missing${NC}"
        fi
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    return 0
}

# Test restore (actually restore to test container)
verify_restore() {
    local backup_file=$1
    local test_container="neo4j-restore-test-$$"
    
    log "INFO" "${CYAN}Running restore test...${NC}"
    log "WARN" "${YELLOW}This will start a temporary Neo4j container${NC}"
    
    # Create test network
    docker network create test-restore-$$ 2>/dev/null || true
    
    # Start test container with empty data
    log "INFO" "Starting test container: $test_container"
    docker run -d \
        --name "$test_container" \
        --network "test-restore-$$" \
        -e NEO4J_AUTH=neo4j/testpassword \
        -e NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
        neo4j:5.26.0 > /dev/null
    
    # Wait for container to be ready
    sleep 10
    
    # Stop container for restore
    docker stop "$test_container" > /dev/null
    
    # Extract backup to container volumes
    log "INFO" "Restoring backup to test container..."
    docker run --rm \
        -v ${test_container}-data:/data \
        -v ${backup_file}:/backup.tar.gz:ro \
        alpine sh -c "cd / && tar -xzf /backup.tar.gz backup/data && mv backup/data/* /data/ && rm -rf backup"
    
    # Start container with restored data
    log "INFO" "Starting container with restored data..."
    docker start "$test_container" > /dev/null
    
    # Wait for Neo4j to be ready
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if docker exec "$test_container" cypher-shell -u neo4j -p testpassword "RETURN 1" > /dev/null 2>&1; then
            log "INFO" "${GREEN}✓ Neo4j started successfully with restored data${NC}"
            break
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log "ERROR" "${RED}✗ Neo4j failed to start with restored data${NC}"
        docker logs "$test_container" | tail -20
        docker rm -f "$test_container" > /dev/null
        docker network rm "test-restore-$$" > /dev/null 2>&1
        return 1
    fi
    
    # Run basic queries to verify data
    log "INFO" "Testing database queries..."
    
    # Get node count
    NODE_COUNT=$(docker exec "$test_container" cypher-shell -u neo4j -p testpassword \
        "MATCH (n) RETURN count(n) as count" --format plain 2>/dev/null | tail -1)
    log "INFO" "Node count: $NODE_COUNT"
    
    # Get relationship count
    REL_COUNT=$(docker exec "$test_container" cypher-shell -u neo4j -p testpassword \
        "MATCH ()-[r]->() RETURN count(r) as count" --format plain 2>/dev/null | tail -1)
    log "INFO" "Relationship count: $REL_COUNT"
    
    # Cleanup
    log "INFO" "Cleaning up test container..."
    docker rm -f "$test_container" > /dev/null
    docker network rm "test-restore-$$" > /dev/null 2>&1
    docker volume rm "${test_container}-data" > /dev/null 2>&1
    
    log "INFO" "${GREEN}✓ Restore test completed successfully${NC}"
    return 0
}

# Compare backups
compare_backups() {
    local tier=${1:-daily}
    local backup_path="${BACKUP_DIR}/${tier}"
    
    log "INFO" "${CYAN}Comparing $tier backups...${NC}"
    
    if [ ! -d "$backup_path" ]; then
        log "ERROR" "${RED}Backup directory not found: $backup_path${NC}"
        return 1
    fi
    
    # Get last 5 backups
    local backups=($(ls -t ${backup_path}/*.tar.* 2>/dev/null | head -5))
    
    if [ ${#backups[@]} -lt 2 ]; then
        log "WARN" "${YELLOW}Not enough backups to compare${NC}"
        return 0
    fi
    
    echo ""
    echo "Recent backups:"
    echo "----------------------------------------"
    for backup in "${backups[@]}"; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -f%Sm -t "%Y-%m-%d %H:%M" "$backup" 2>/dev/null || stat -c%y "$backup" | cut -d' ' -f1,2)
        echo "$(basename $backup): $size ($date)"
    done
    echo ""
    
    # Check for size anomalies
    local prev_size=0
    for backup in "${backups[@]}"; do
        local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup")
        if [ $prev_size -gt 0 ]; then
            local diff=$((size - prev_size))
            local percent=$((diff * 100 / prev_size))
            if [ ${percent#-} -gt 20 ]; then
                log "WARN" "${YELLOW}Significant size change detected: ${percent}%${NC}"
            fi
        fi
        prev_size=$size
    done
    
    return 0
}

# Verify all tiers
verify_all_tiers() {
    local tiers=("daily" "weekly" "monthly")
    local failed=0
    
    print_header
    
    for tier in "${tiers[@]}"; do
        echo -e "${CYAN}Verifying $tier backups...${NC}"
        echo "----------------------------------------"
        
        local backup_file=$(find_latest_backup "$tier")
        if [ $? -eq 0 ] && [ -n "$backup_file" ]; then
            log "INFO" "Latest backup: $(basename $backup_file)"
            
            # Verify checksum
            verify_checksum "$backup_file"
            
            # Quick verification
            verify_quick "$backup_file"
            
            echo ""
        else
            log "WARN" "${YELLOW}No $tier backups found${NC}"
            failed=$((failed + 1))
        fi
    done
    
    # Summary
    echo -e "${BLUE}=============================================${NC}"
    if [ $failed -eq 0 ]; then
        log "INFO" "${GREEN}All backup tiers verified successfully${NC}"
    else
        log "WARN" "${YELLOW}$failed tier(s) have no backups${NC}"
    fi
    
    return $failed
}

# Show backup statistics
show_statistics() {
    print_header
    
    echo -e "${CYAN}Backup Statistics${NC}"
    echo "----------------------------------------"
    
    local total_size=0
    local total_count=0
    
    for tier in daily weekly monthly; do
        local tier_path="${BACKUP_DIR}/${tier}"
        if [ -d "$tier_path" ]; then
            local count=$(ls ${tier_path}/*.tar.* 2>/dev/null | wc -l)
            local size=$(du -sh "$tier_path" 2>/dev/null | cut -f1)
            echo "$tier: $count backups, $size total"
            total_count=$((total_count + count))
        fi
    done
    
    echo ""
    echo "Total backups: $total_count"
    echo "Backup directory: $BACKUP_DIR"
    
    # Check external drive
    if [ -d "$EXTERNAL_BACKUP_DIR" ]; then
        echo -e "${GREEN}External drive: Available${NC}"
        local ext_size=$(du -sh "$EXTERNAL_BACKUP_DIR" 2>/dev/null | cut -f1)
        echo "External backup size: $ext_size"
    else
        echo -e "${YELLOW}External drive: Not mounted${NC}"
    fi
    
    echo ""
}

# Main execution
case "$VERIFY_MODE" in
    quick)
        print_header
        BACKUP_FILE="${3:-$(find_latest_backup $BACKUP_TIER)}"
        if [ -f "$BACKUP_FILE" ]; then
            verify_checksum "$BACKUP_FILE"
            verify_quick "$BACKUP_FILE"
        else
            log "ERROR" "${RED}Backup file not found: $BACKUP_FILE${NC}"
            exit 1
        fi
        ;;
        
    full)
        print_header
        BACKUP_FILE="${3:-$(find_latest_backup $BACKUP_TIER)}"
        if [ -f "$BACKUP_FILE" ]; then
            verify_checksum "$BACKUP_FILE"
            verify_full "$BACKUP_FILE"
        else
            log "ERROR" "${RED}Backup file not found: $BACKUP_FILE${NC}"
            exit 1
        fi
        ;;
        
    restore)
        print_header
        BACKUP_FILE="${3:-$(find_latest_backup $BACKUP_TIER)}"
        if [ -f "$BACKUP_FILE" ]; then
            verify_restore "$BACKUP_FILE"
        else
            log "ERROR" "${RED}Backup file not found: $BACKUP_FILE${NC}"
            exit 1
        fi
        ;;
        
    compare)
        print_header
        compare_backups "$BACKUP_TIER"
        ;;
        
    all)
        verify_all_tiers
        ;;
        
    stats|statistics)
        show_statistics
        ;;
        
    help|*)
        print_header
        echo "Usage: $0 [mode] [tier] [backup_file]"
        echo ""
        echo "Modes:"
        echo "  quick    - Quick tar integrity check (default)"
        echo "  full     - Full extraction and structure verification"
        echo "  restore  - Test restore to temporary container"
        echo "  compare  - Compare recent backups for anomalies"
        echo "  all      - Verify all backup tiers"
        echo "  stats    - Show backup statistics"
        echo ""
        echo "Tiers:"
        echo "  daily    - Daily backups (default)"
        echo "  weekly   - Weekly backups"
        echo "  monthly  - Monthly backups"
        echo ""
        echo "Examples:"
        echo "  $0 quick daily"
        echo "  $0 full weekly"
        echo "  $0 restore monthly /path/to/backup.tar.gz"
        echo "  $0 all"
        echo "  $0 stats"
        ;;
esac