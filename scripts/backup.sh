#!/bin/bash

# Neo4j Backup Script for Graphiti
# Integrated backup management with offen/docker-volume-backup support

set -e  # Exit on error

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/backup/backup.conf"

# Load backup configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Configuration (with fallbacks for backward compatibility)
BACKUP_BASE_DIR="${PRIMARY_BACKUP_DIR:-${HOME}/Neo4jBackups}"
CONTAINER_NAME="${CONTAINER_NAME:-neo4j-graphiti}"
DATABASE_NAME="${DATABASE_NAME:-neo4j}"
RETENTION_DAYS="${BACKUP_RETENTION_DAILY:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="neo4j_backup_${TIMESTAMP}"

# Parse command line arguments
ACTION="${1:-manual}"
BACKUP_TIER="${2:-daily}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print header
print_header() {
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}         Neo4j Backup Management             ${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""
}

# Check if new backup system is running
is_backup_system_running() {
    docker ps --format "table {{.Names}}" | grep -q "neo4j-backup-" || return 1
}

# Manual backup using offen/docker-volume-backup
manual_backup_new() {
    echo -e "${CYAN}Starting manual backup using new system...${NC}"
    
    # Run manual backup using docker-compose
    docker compose -f ${PROJECT_ROOT}/docker-compose.yml \
                   -f ${PROJECT_ROOT}/docker-compose.backup.yml \
                   run --rm backup-manual
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Manual backup completed successfully${NC}"
        
        # Run verification
        ${SCRIPT_DIR}/verify-backup.sh quick manual
    else
        echo -e "${RED}Manual backup failed!${NC}"
        exit 1
    fi
}

# Legacy backup method (neo4j-admin)
manual_backup_legacy() {
    echo -e "${YELLOW}Using legacy backup method...${NC}"
    
    # Check if container is running
    if ! docker ps | grep -q ${CONTAINER_NAME}; then
        echo -e "${RED}Error: Container ${CONTAINER_NAME} is not running${NC}"
        exit 1
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "${BACKUP_BASE_DIR}/manual"
    
    # Stop Neo4j for consistent backup (Community Edition requirement)
    echo -e "${YELLOW}Stopping Neo4j for backup...${NC}"
    docker stop ${CONTAINER_NAME}
    
    # Perform backup using neo4j-admin
    echo -e "${YELLOW}Creating backup: ${BACKUP_NAME}${NC}"
    docker run --rm \
        -v neo4j-data:/data \
        -v ${BACKUP_BASE_DIR}/manual:/backups \
        neo4j:5.26.0 \
        neo4j-admin database dump \
            --to-path=/backups/${BACKUP_NAME}.dump \
            --overwrite-destination=true \
            neo4j
    
    # Restart Neo4j
    echo -e "${YELLOW}Restarting Neo4j...${NC}"
    docker start ${CONTAINER_NAME}
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup completed successfully${NC}"
        
        # List backup size
        ls -lh "${BACKUP_BASE_DIR}/manual/" | grep ${BACKUP_NAME}
        
        # Clean up old backups (older than RETENTION_DAYS)
        echo -e "${YELLOW}Cleaning up backups older than ${RETENTION_DAYS} days...${NC}"
        find "${BACKUP_BASE_DIR}/manual" -name "*.dump" -mtime +${RETENTION_DAYS} -delete
        
        # Show current backups
        echo -e "${GREEN}Current backups:${NC}"
        ls -lht "${BACKUP_BASE_DIR}/manual" | head -10
    else
        echo -e "${RED}Backup failed!${NC}"
        exit 1
    fi
}

# Start automated backup services
start_backup_services() {
    echo -e "${CYAN}Starting automated backup services...${NC}"
    
    docker compose -f ${PROJECT_ROOT}/docker-compose.yml \
                   -f ${PROJECT_ROOT}/docker-compose.backup.yml \
                   --profile backup \
                   up -d
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup services started successfully${NC}"
        echo ""
        echo "Active backup schedules:"
        echo "  - Daily:   ${BACKUP_CRON_DAILY:-0 2 * * *} (${BACKUP_RETENTION_DAILY:-7} day retention)"
        echo "  - Weekly:  ${BACKUP_CRON_WEEKLY:-0 3 * * 0} (${BACKUP_RETENTION_WEEKLY:-28} day retention)"
        echo "  - Monthly: ${BACKUP_CRON_MONTHLY:-0 4 1 * *} (${BACKUP_RETENTION_MONTHLY:-365} day retention)"
    else
        echo -e "${RED}Failed to start backup services${NC}"
        exit 1
    fi
}

# Stop backup services
stop_backup_services() {
    echo -e "${CYAN}Stopping backup services...${NC}"
    
    docker compose -f ${PROJECT_ROOT}/docker-compose.yml \
                   -f ${PROJECT_ROOT}/docker-compose.backup.yml \
                   --profile backup \
                   down
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup services stopped${NC}"
    else
        echo -e "${RED}Failed to stop backup services${NC}"
        exit 1
    fi
}

# Show backup status
show_status() {
    print_header
    
    echo -e "${CYAN}Backup System Status${NC}"
    echo "----------------------------------------"
    
    # Check if backup services are running
    if is_backup_system_running; then
        echo -e "Backup services: ${GREEN}Running${NC}"
        echo ""
        echo "Active containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep "neo4j-backup-"
    else
        echo -e "Backup services: ${YELLOW}Not running${NC}"
        echo "Run '$0 start' to enable automated backups"
    fi
    
    echo ""
    echo -e "${CYAN}Backup Storage${NC}"
    echo "----------------------------------------"
    echo "Primary location: ${BACKUP_BASE_DIR}"
    
    # Check external drive
    if [ -d "${EXTERNAL_BACKUP_DIR}" ]; then
        echo -e "External drive: ${GREEN}Available${NC} at ${EXTERNAL_BACKUP_DIR}"
    else
        echo -e "External drive: ${YELLOW}Not mounted${NC}"
    fi
    
    # Show backup statistics
    echo ""
    ${SCRIPT_DIR}/verify-backup.sh stats
}

# Verify backups
verify_backups() {
    local tier=${1:-all}
    ${SCRIPT_DIR}/verify-backup.sh all
}

# Emergency backup
emergency_backup() {
    echo -e "${RED}Starting emergency backup procedure...${NC}"
    ${SCRIPT_DIR}/backup-hooks.sh emergency
}

# Main execution
print_header

case "$ACTION" in
    manual|backup)
        # Check if new backup system is available
        if [ -f "${PROJECT_ROOT}/docker-compose.backup.yml" ]; then
            manual_backup_new
        else
            echo -e "${YELLOW}New backup system not found, using legacy method${NC}"
            manual_backup_legacy
        fi
        ;;
        
    start)
        start_backup_services
        ;;
        
    stop)
        stop_backup_services
        ;;
        
    status)
        show_status
        ;;
        
    verify)
        verify_backups "$BACKUP_TIER"
        ;;
        
    emergency)
        emergency_backup
        ;;
        
    legacy)
        manual_backup_legacy
        ;;
        
    help|--help|-h)
        echo "Usage: $0 [action] [options]"
        echo ""
        echo "Actions:"
        echo "  manual|backup  - Create manual backup (default)"
        echo "  start         - Start automated backup services"
        echo "  stop          - Stop automated backup services"
        echo "  status        - Show backup system status"
        echo "  verify [tier] - Verify backup integrity"
        echo "  emergency     - Create emergency backup"
        echo "  legacy        - Use legacy backup method"
        echo ""
        echo "Examples:"
        echo "  $0              # Create manual backup"
        echo "  $0 start        # Start automated backups"
        echo "  $0 status       # Check backup status"
        echo "  $0 verify daily # Verify daily backups"
        echo ""
        echo "Configuration file: ${CONFIG_FILE}"
        ;;
        
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=============================================${NC}"