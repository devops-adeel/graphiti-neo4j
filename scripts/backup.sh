#!/bin/bash

# Neo4j Backup Script for Graphiti
# Performs automated backups with retention policy

set -e  # Exit on error

# Configuration
BACKUP_BASE_DIR="/Users/adeel/Documents/1_projects/neo4j/graphiti-neo4j/backups"
CONTAINER_NAME="neo4j-graphiti"
DATABASE_NAME="neo4j"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="neo4j_backup_${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Neo4j backup...${NC}"

# Check if container is running
if ! docker ps | grep -q ${CONTAINER_NAME}; then
    echo -e "${RED}Error: Container ${CONTAINER_NAME} is not running${NC}"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_BASE_DIR}"

# Perform backup using neo4j-admin
echo -e "${YELLOW}Creating backup: ${BACKUP_NAME}${NC}"
docker exec ${CONTAINER_NAME} neo4j-admin database backup \
    --to-path=/backups \
    --compress=true \
    ${DATABASE_NAME}

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Backup completed successfully${NC}"
    
    # List backup size
    docker exec ${CONTAINER_NAME} ls -lh /backups/ | grep ${DATABASE_NAME}
    
    # Clean up old backups (older than RETENTION_DAYS)
    echo -e "${YELLOW}Cleaning up backups older than ${RETENTION_DAYS} days...${NC}"
    find "${BACKUP_BASE_DIR}" -name "*.backup" -mtime +${RETENTION_DAYS} -delete
    
    # Show current backups
    echo -e "${GREEN}Current backups:${NC}"
    ls -lht "${BACKUP_BASE_DIR}" | head -10
else
    echo -e "${RED}Backup failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Backup process completed${NC}"