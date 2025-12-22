#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
STATE_FILE=".deployment-state.json"
LOG_FILE="deployment-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${!level}[$timestamp] $message${NC}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log CYAN "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log RED "Azure CLI is not installed. Please install it first."
        log YELLOW "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log RED "jq is not installed. Please install it first."
        log YELLOW "Install: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log RED "Not logged in to Azure. Please run: az login"
        exit 1
    fi
    
    local account_name=$(az account show --query name -o tsv)
    local account_user=$(az account show --query user.name -o tsv)
    log GREEN "Logged in as: $account_user"
    log GREEN "Subscription: $account_name"
}

# Get user inputs
get_configuration() {
    echo ""
    log CYAN "=========================================="
    log CYAN "Deployment Configuration"
    log CYAN "=========================================="
    echo ""
    
    # Get domain
    read -p "Enter your domain name (e.g., example.com): " DOMAIN
    
    # Get email for Let's Encrypt
    read -p "Enter your email for Let's Encrypt (e.g., admin@$DOMAIN): " EMAIL
    
    # Region selection
    echo ""
    log YELLOW "Available Azure Regions:"
    echo "  1. UK South (uksouth)"
    echo "  2. East US (eastus)"
    echo "  3. East Asia (eastasia)"
    echo "  4. West Europe (westeurope)"
    echo "  5. Canada Central (canadacentral)"
    echo "  6. West US (westus)"
    echo "  7. Southeast Asia (southeastasia)"
    echo "  8. Australia East (australiaeast)"
    echo ""
    read -p "Select regions (e.g., 1,2,3 for minimum 2 regions): " REGION_SELECTION
    
    # Parse regions
    IFS=',' read -ra REGION_INDICES <<< "$REGION_SELECTION"
    REGIONS=()
    REGION_CODES=()
    REGION_SHORTS=()
    
    declare -A REGION_MAP=(
        [1]="UK South:uksouth:GB:172.18.0.0/16:172.18.8.0/22"
        [2]="East US:eastus:US-E:172.20.0.0/16:172.20.8.0/22"
        [3]="East Asia:eastasia:HK:172.23.0.0/16:172.23.8.0/22"
        [4]="West Europe:westeurope:NL:172.22.0.0/16:172.22.8.0/22"
        [5]="Canada Central:canadacentral:CA:172.19.0.0/16:172.19.8.0/22"
        [6]="West US:westus:US-W:172.21.0.0/16:172.21.8.0/22"
        [7]="Southeast Asia:southeastasia:SG:172.24.0.0/16:172.24.8.0/22"
        [8]="Australia East:australiaeast:AU:172.25.0.0/16:172.25.8.0/22"
    )
    
    for idx in "${REGION_INDICES[@]}"; do
        if [[ -n "${REGION_MAP[$idx]}" ]]; then
            IFS=':' read -ra REGION_INFO <<< "${REGION_MAP[$idx]}"
            REGIONS+=("${REGION_INFO[0]}")
            REGION_CODES+=("${REGION_INFO[1]}")
            REGION_SHORTS+=("${REGION_INFO[2]}")
        fi
    done
    
    if [ ${#REGIONS[@]} -lt 2 ]; then
        log RED "At least 2 regions are required for Front Door deployment"
        exit 1
    fi
    
    # Get public IP
    MY_IP=$(curl -s https://api.ipify.org)
    
    echo ""
    log GREEN "Configuration Summary:"
    log GREEN "  Domain: $DOMAIN"
    log GREEN "  Email: $EMAIL"
    log GREEN "  Regions: ${REGIONS[*]}"
    log GREEN "  Your IP: $MY_IP"
    echo ""
    read -p "Continue with this configuration? (y/n): " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log YELLOW "Deployment cancelled"
        exit 0
    fi
    
    # Save state
    cat > "$STATE_FILE" <<EOF
{
    "domain": "$DOMAIN",
    "email": "$EMAIL",
    "regions": $(printf '%s\n' "${REGION_CODES[@]}" | jq -R . | jq -s .),
    "regionShorts": $(printf '%s\n' "${REGION_SHORTS[@]}" | jq -R . | jq -s .),
    "myIP": "$MY_IP",
    "timestamp": "$(date -Iseconds)"
}
EOF
}

# Deploy infrastructure using Bicep
deploy_infrastructure() {
    log CYAN "=========================================="
    log CYAN "Deploying Infrastructure"
    log CYAN "=========================================="
    echo ""
    
    # Generate SSH key if not exists
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        log YELLOW "Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
    fi
    
    SSH_PUBLIC_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
    
    # Create deployment parameters
    local deployment_name="guacamole-deployment-$(date +%s)"
    local params_file="deployment-params-$(date +%s).json"
    
    # Build regions array for Bicep
    local regions_json="["
    for i in "${!REGION_CODES[@]}"; do
        local subdomain="paw"
        if [ $i -gt 0 ]; then
            subdomain="paw-${REGION_SHORTS[$i],,}"
        fi
        
        regions_json+="{\"location\":\"${REGION_CODES[$i]}\",\"shortName\":\"${REGION_SHORTS[$i]}\",\"subdomain\":\"$subdomain\"},"
    done
    regions_json="${regions_json%,}]"
    
    cat > "$params_file" <<EOF
{
    "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "regions": {
            "value": $regions_json
        },
        "domain": {
            "value": "$DOMAIN"
        },
        "certbotEmail": {
            "value": "$EMAIL"
        },
        "adminPublicKey": {
            "value": "$SSH_PUBLIC_KEY"
        },
        "allowedSourceIP": {
            "value": "$MY_IP"
        }
    }
}
EOF
    
    log YELLOW "Starting deployment..."
    log YELLOW "This will take approximately 10-15 minutes..."
    
    az deployment sub create \
        --name "$deployment_name" \
        --location "${REGION_CODES[0]}" \
        --template-file main.bicep \
        --parameters "@$params_file" \
        --output json > deployment-output.json
    
    if [ $? -eq 0 ]; then
        log GREEN "✓ Infrastructure deployment completed successfully"
        
        # Extract outputs
        FRONT_DOOR_ENDPOINT=$(jq -r '.properties.outputs.frontDoorEndpoint.value' deployment-output.json)
        
        log GREEN "Front Door Endpoint: $FRONT_DOOR_ENDPOINT"
        
        # Update state
        jq --arg endpoint "$FRONT_DOOR_ENDPOINT" \
           '.frontDoorEndpoint = $endpoint' \
           "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        log RED "✗ Infrastructure deployment failed"
        exit 1
    fi
    
    # Cleanup temp files
    rm -f "$params_file"
}

# Wait for VMs and Front Door to be ready
wait_for_readiness() {
    log CYAN "=========================================="
    log CYAN "Waiting for Services"
    log CYAN "=========================================="
    echo ""
    
    log YELLOW "Waiting for VMs to complete installation (this may take 10-15 minutes)..."
    log YELLOW "The VMs are installing Docker, Guacamole, and Let's Encrypt certificates..."
    
    sleep 60
    
    local max_attempts=30
    local attempt=0
    local all_ready=false
    
    while [ $attempt -lt $max_attempts ] && [ "$all_ready" = false ]; do
        attempt=$((attempt + 1))
        log YELLOW "Check attempt $attempt/$max_attempts..."
        
        all_ready=true
        for i in "${!REGION_SHORTS[@]}"; do
            local subdomain="paw"
            if [ $i -gt 0 ]; then
                subdomain="paw-${REGION_SHORTS[$i],,}"
            fi
            
            local fqdn="$subdomain.$DOMAIN"
            
            if curl -k -s -o /dev/null -w "%{http_code}" "https://$fqdn/guacamole/" | grep -q "200"; then
                log GREEN "✓ $fqdn is ready"
            else
                log YELLOW "⏳ $fqdn not ready yet..."
                all_ready=false
            fi
        done
        
        if [ "$all_ready" = false ]; then
            sleep 30
        fi
    done
    
    if [ "$all_ready" = true ]; then
        log GREEN "✓ All services are ready!"
    else
        log YELLOW "⚠ Some services may still be initializing. Check logs on VMs if needed."
    fi
}

# Display final information
show_summary() {
    log CYAN "=========================================="
    log GREEN "Deployment Complete!"
    log CYAN "=========================================="
    echo ""
    
    local state=$(cat "$STATE_FILE")
    local endpoint=$(echo "$state" | jq -r '.frontDoorEndpoint // empty')
    
    log GREEN "Access URLs:"
    if [ -n "$endpoint" ]; then
        log CYAN "  Front Door: https://$endpoint/guacamole/"
    fi
    
    for i in "${!REGION_SHORTS[@]}"; do
        local subdomain="paw"
        if [ $i -gt 0 ]; then
            subdomain="paw-${REGION_SHORTS[$i],,}"
        fi
        log CYAN "  ${REGIONS[$i]}: https://$subdomain.$DOMAIN/guacamole/"
    done
    
    echo ""
    log YELLOW "Default Credentials:"
    log YELLOW "  Username: guacadmin"
    log YELLOW "  Password: guacadmin"
    log RED "  ⚠ CHANGE PASSWORD IMMEDIATELY AFTER FIRST LOGIN!"
    echo ""
    log GREEN "DNS Records to Configure:"
    for i in "${!REGION_SHORTS[@]}"; do
        local subdomain="paw"
        if [ $i -gt 0 ]; then
            subdomain="paw-${REGION_SHORTS[$i],,}"
        fi
        local rg="RG-${REGION_SHORTS[$i]}-PAW-Core"
        local vm_name="VM-${REGION_SHORTS[$i]}-PAW-Gateway"
        local public_ip=$(az vm show -d -g "$rg" -n "$vm_name" --query publicIps -o tsv 2>/dev/null || echo "N/A")
        log CYAN "  $subdomain.$DOMAIN → $public_ip (A record)"
    done
    
    echo ""
    log GREEN "Deployment log saved to: $LOG_FILE"
}

# Main execution
main() {
    clear
    echo ""
    log CYAN "=========================================="
    log CYAN "Multi-Region Guacamole Deployment"
    log CYAN "=========================================="
    echo ""
    
    check_prerequisites
    get_configuration
    deploy_infrastructure
    wait_for_readiness
    show_summary
}

# Run main function
main
