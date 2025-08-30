#!/bin/bash

# Graphiti-Neo4j Secure Deployment with 1Password
# This script deploys Neo4j with secrets from 1Password
# Following security best practices with temp file handling

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$PROJECT_ROOT/secrets"
TEMP_ENV=""
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-graphiti-neo4j}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Cleanup function - secure deletion of temporary files
cleanup() {
    if [ -n "$TEMP_ENV" ] && [ -f "$TEMP_ENV" ]; then
        log_info "Cleaning up temporary files..."
        # Use shred for secure deletion if available, otherwise rm
        if command -v shred &> /dev/null; then
            shred -u "$TEMP_ENV" 2>/dev/null || true
        else
            rm -f "$TEMP_ENV"
        fi
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT INT TERM

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check for 1Password CLI
    if ! command -v op &> /dev/null; then
        missing_deps+=("1Password CLI (op)")
        log_error "1Password CLI is not installed."
        log_info "  Install with: brew install --cask 1password-cli"
    fi
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("Docker")
        log_error "Docker is not installed."
    fi
    
    # Check for Docker Compose
    if ! docker compose version &> /dev/null 2>&1; then
        missing_deps+=("Docker Compose")
        log_error "Docker Compose is not available."
    fi
    
    # Exit if any dependencies are missing
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    log_info "✓ All prerequisites met"
}

# Check 1Password authentication
check_1password_auth() {
    log_step "Checking 1Password authentication..."
    
    if ! op account list &> /dev/null; then
        log_warn "Not signed in to 1Password."
        log_info "Please sign in to 1Password:"
        
        if ! op signin; then
            log_error "Failed to sign in to 1Password."
            exit 1
        fi
    else
        log_info "✓ Already signed in to 1Password"
    fi
}

# Verify HomeLab vault exists
verify_vault() {
    log_step "Verifying HomeLab vault..."
    
    if ! op vault get HomeLab &> /dev/null; then
        log_error "HomeLab vault not found."
        log_info "  Create it with: make setup-vault"
        exit 1
    fi
    
    log_info "✓ HomeLab vault exists"
}

# Validate secret accessibility
validate_secrets() {
    log_step "Validating secret accessibility..."
    
    # Test Neo4j password access
    if ! op read "op://HomeLab/Graphiti-Neo4j/password" &> /dev/null; then
        log_error "Cannot access Neo4j password in 1Password."
        log_info "  Run 'make setup-vault' to create Neo4j credentials"
        exit 1
    fi
    
    # Test OpenAI key access (warn if not accessible, don't fail)
    if ! op read "op://ywvjwtjo75i2xxb5pol2lzmkmy/toyqxan47kodn5lwhp7zphsdka/credential" &> /dev/null; then
        log_warn "Cannot access OpenAI API key"
        log_info "  Tests requiring OpenAI may fail"
        log_info "  Continuing with deployment..."
    fi
    
    log_info "✓ Required secrets are accessible"
}

# Inject secrets from 1Password
inject_secrets() {
    log_step "Injecting secrets from 1Password..."
    
    local template_file="$SECRETS_DIR/.env.1password"
    
    # Check if template exists
    if [ ! -f "$template_file" ]; then
        log_error "Template file not found: $template_file"
        exit 1
    fi
    
    # Create temporary file with restricted permissions
    TEMP_ENV=$(mktemp -t neo4j-env.XXXXXX)
    chmod 600 "$TEMP_ENV"
    
    # Inject secrets into temporary file
    if ! op inject -i "$template_file" -o "$TEMP_ENV" 2>/dev/null; then
        log_error "Failed to inject secrets from 1Password."
        log_info "Please ensure all required secrets exist in HomeLab vault."
        log_info "Run 'make setup-vault' to create missing secrets."
        exit 1
    fi
    
    # Verify no unresolved references remain
    if grep -q "op://" "$TEMP_ENV"; then
        log_error "Some secrets were not resolved:"
        grep "op://" "$TEMP_ENV" | head -5
        log_info ""
        log_info "Create missing secrets with: make setup-vault"
        exit 1
    fi
    
    # Verify critical variables exist
    if ! grep -q "NEO4J_PASSWORD=" "$TEMP_ENV" || grep -q "NEO4J_PASSWORD=$" "$TEMP_ENV"; then
        log_error "Neo4j password was not properly injected"
        exit 1
    fi
    
    log_info "✓ Secrets successfully injected"
}

# Deploy Neo4j with secrets
deploy_services() {
    log_step "Deploying Neo4j services..."
    
    cd "$PROJECT_ROOT"
    
    # Check if Neo4j is already running
    if docker compose ps --services --status running 2>/dev/null | grep -q neo4j-graphiti; then
        log_info "Neo4j is already running, restarting with new configuration..."
        docker compose down
        sleep 2
    fi
    
    # Deploy with injected secrets
    log_info "Starting Neo4j with secure configuration..."
    
    if docker compose --env-file "$TEMP_ENV" up -d; then
        log_info "✓ Services started successfully"
    else
        log_error "Failed to start services"
        exit 1
    fi
}

# Wait for services to be healthy
wait_for_health() {
    log_step "Waiting for Neo4j to be healthy..."
    
    local max_wait=60
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker exec neo4j-graphiti neo4j status 2>/dev/null | grep -q "is running"; then
            echo
            log_info "✓ Neo4j is healthy and ready"
            return 0
        fi
        
        echo -n "."
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    echo
    log_warn "Neo4j may not be fully ready. Check with: docker logs neo4j-graphiti"
}

# Show deployment information
show_deployment_info() {
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Graphiti-Neo4j Secure Deployment Complete      ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo
    echo "  Browser UI:      ${GREEN}http://neo4j.graphiti.local:7474${NC}"
    echo "  Bolt Protocol:   ${GREEN}bolt://neo4j.graphiti.local:7687${NC}"
    echo "  Metrics:         ${GREEN}http://neo4j.graphiti.local:2004/metrics${NC}"
    echo "  Project:         $COMPOSE_PROJECT_NAME"
    echo
    echo "  Commands:"
    echo "    View logs:     docker compose logs -f neo4j-graphiti"
    echo "    Check status:  docker compose ps"
    echo "    Monitor:       make monitor"
    echo "    Stop:          make down"
    echo
    echo -e "${GREEN}✅ Deployment successful with 1Password secrets${NC}"
    echo
    echo "  Username: neo4j"
    echo "  Password: (securely stored in 1Password)"
    echo
    echo "  To view credentials:"
    echo "    op item get Graphiti-Neo4j --vault=HomeLab"
    echo
}

# Main execution
main() {
    log_info "Starting Graphiti-Neo4j secure deployment..."
    echo
    
    check_prerequisites
    check_1password_auth
    verify_vault
    validate_secrets
    inject_secrets
    deploy_services
    wait_for_health
    show_deployment_info
}

# Run main function
main "$@"