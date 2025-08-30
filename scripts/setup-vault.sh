#!/bin/bash

# Graphiti-Neo4j 1Password Vault Setup Script
# Creates and configures HomeLab vault with Neo4j secrets
# Auto-generates secure Neo4j password

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$PROJECT_ROOT/secrets"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_create() {
    echo -e "${CYAN}[CREATE]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check for 1Password CLI
    if ! command -v op &> /dev/null; then
        log_error "1Password CLI is not installed."
        echo
        echo "To install 1Password CLI:"
        echo "  brew install --cask 1password-cli"
        echo
        echo "Or download from:"
        echo "  https://developer.1password.com/docs/cli/get-started/"
        exit 1
    fi
    
    # Check for required tools
    local missing_tools=()
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if ! command -v uuidgen &> /dev/null; then
        missing_tools+=("uuidgen")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log_info "✓ All prerequisites met"
}

# Check 1Password authentication
check_1password_auth() {
    log_step "Checking 1Password authentication..."
    
    if ! op account list &> /dev/null; then
        log_warn "Not signed in to 1Password."
        echo
        echo "Please sign in to your 1Password account:"
        
        if ! op signin; then
            log_error "Failed to sign in to 1Password."
            exit 1
        fi
    else
        log_info "✓ Signed in to 1Password"
    fi
}

# Create or verify HomeLab vault
ensure_vault() {
    log_step "Setting up HomeLab vault..."
    
    if op vault get HomeLab &> /dev/null; then
        log_info "✓ HomeLab vault already exists"
    else
        log_create "Creating HomeLab vault..."
        
        if op vault create HomeLab &> /dev/null; then
            log_info "✓ HomeLab vault created successfully"
        else
            log_error "Failed to create HomeLab vault"
            exit 1
        fi
    fi
}

# Validate OpenAI key accessibility
validate_openai_key() {
    log_step "Validating OpenAI API key access..."
    
    # Test access to the OpenAI key using the UUID reference
    if op read "op://ywvjwtjo75i2xxb5pol2lzmkmy/toyqxan47kodn5lwhp7zphsdka/credential" &> /dev/null; then
        log_info "✓ OpenAI API key is accessible"
    else
        log_warn "Cannot access OpenAI API key"
        log_info "  This may be expected if the key is in a different vault"
        log_info "  You may need to update the reference in secrets/.env.1password"
    fi
}

# Generate secure password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n'
}

# Create or update Neo4j secrets
setup_neo4j_secrets() {
    log_step "Setting up Neo4j authentication secrets..."
    
    local item_name="Graphiti-Neo4j"
    
    # Check if item already exists
    if op item get "$item_name" --vault=HomeLab &> /dev/null; then
        log_info "✓ $item_name already exists in HomeLab vault"
        
        # Get the item UUID for reference
        local item_uuid=$(op item get "$item_name" --vault=HomeLab --format=json 2>/dev/null | grep -o '"id":"[^"]*' | cut -d'"' -f4)
        if [ -n "$item_uuid" ]; then
            log_info "  Item UUID: $item_uuid"
        fi
        
        echo
        read -p "Do you want to regenerate the Neo4j password? [y/N]: " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            local neo4j_password=$(generate_password 32)
            
            log_info "Updating Neo4j password..."
            if op item edit "$item_name" --vault=HomeLab "password=$neo4j_password" &> /dev/null; then
                log_info "✓ Neo4j password updated"
            else
                log_error "Failed to update Neo4j password"
                return 1
            fi
        else
            log_info "Keeping existing Neo4j password"
        fi
    else
        log_create "Creating $item_name..."
        
        # Generate new password
        local neo4j_password=$(generate_password 32)
        
        # Create new item with username and password fields
        if op item create \
            --vault=HomeLab \
            --category=Database \
            --title="$item_name" \
            "username=neo4j" \
            "password=$neo4j_password" \
            "notes=Auto-generated Neo4j credentials for Graphiti infrastructure" &> /dev/null; then
            
            log_info "✓ Created $item_name with auto-generated password"
            
            # Get the item UUID for reference
            local item_uuid=$(op item get "$item_name" --vault=HomeLab --format=json 2>/dev/null | grep -o '"id":"[^"]*' | cut -d'"' -f4)
            if [ -n "$item_uuid" ]; then
                log_info "  Item UUID: $item_uuid (for reference)"
            fi
        else
            log_error "Failed to create $item_name"
            return 1
        fi
    fi
}

# Verify setup
verify_setup() {
    log_step "Verifying vault setup..."
    
    local all_good=true
    
    # Check Neo4j item
    if op item get "Graphiti-Neo4j" --vault=HomeLab &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Graphiti-Neo4j exists"
    else
        echo -e "  ${RED}✗${NC} Graphiti-Neo4j missing"
        all_good=false
    fi
    
    # Test that we can read the Neo4j password
    if op read "op://HomeLab/Graphiti-Neo4j/password" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Neo4j password is accessible"
    else
        echo -e "  ${RED}✗${NC} Neo4j password not accessible"
        all_good=false
    fi
    
    if [ "$all_good" = "true" ]; then
        log_info "✓ All required items are configured"
    else
        log_error "Some items are missing or inaccessible"
        exit 1
    fi
}

# Show next steps
show_next_steps() {
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}    Graphiti-Neo4j 1Password Setup Complete         ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo
    echo "✅ HomeLab vault is configured with Neo4j secrets"
    echo
    echo "Next steps:"
    echo
    echo "1. Deploy Neo4j with secrets:"
    echo "   ${GREEN}make up${NC}"
    echo
    echo "2. View your Neo4j credentials:"
    echo "   op item get Graphiti-Neo4j --vault=HomeLab"
    echo
    echo "3. Access Neo4j Browser (credentials auto-injected):"
    echo "   ${CYAN}http://neo4j.graphiti.local:7474${NC}"
    echo
    echo "4. Connect via Bolt protocol:"
    echo "   ${CYAN}bolt://neo4j.graphiti.local:7687${NC}"
    echo
    echo -e "${YELLOW}Note: All deployments now require 1Password CLI${NC}"
    echo
}

# Main execution
main() {
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}      Graphiti-Neo4j 1Password Vault Setup          ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo
    
    check_prerequisites
    check_1password_auth
    ensure_vault
    validate_openai_key
    setup_neo4j_secrets
    verify_setup
    show_next_steps
}

# Run main function
main "$@"