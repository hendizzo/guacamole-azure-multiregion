#!/bin/bash
# Complete Infrastructure Deployment Script
# This script orchestrates the entire multi-region Guacamole deployment

# Exit on error, but we'll handle errors explicitly
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARAMETERS_FILE="${REPO_DIR}/infrastructure/parameters/parameters-main.json"
SSH_KEY_PATH="${HOME}/.ssh/guacamole_key"
STATE_FILE="${REPO_DIR}/.deployment-state"
LOG_FILE="${REPO_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    echo -e "$1" | tee -a "${LOG_FILE}"
}

# Error handler
error_exit() {
    log "${RED}❌ ERROR: $1${NC}"
    log "${YELLOW}Check log file: ${LOG_FILE}${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}✓ $1${NC}"
}

# Warning message
warn() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Save state
save_state() {
    echo "$1=$2" >> "${STATE_FILE}"
}

# Load state
load_state() {
    if [ -f "${STATE_FILE}" ]; then
        source "${STATE_FILE}"
    fi
}

# Check if step completed
is_step_complete() {
    if [ -f "${STATE_FILE}" ]; then
        grep -q "^$1=complete" "${STATE_FILE}"
        return $?
    fi
    return 1
}

# Check if step completed
is_step_complete() {
    if [ -f "${STATE_FILE}" ]; then
        grep -q "^$1=complete" "${STATE_FILE}"
        return $?
    fi
    return 1
}

# Cleanup on exit
cleanup() {
    if [ $? -ne 0 ]; then
        warn "Deployment failed. State saved to ${STATE_FILE}"
        warn "Run script again to resume from last successful step"
    fi
}
trap cleanup EXIT

log "${BLUE}=========================================="
log "Multi-Region Guacamole Deployment"
log "==========================================${NC}"
log "Log file: ${LOG_FILE}"

# Load previous state if exists
load_state

# Resume prompt
if [ -f "${STATE_FILE}" ]; then
    warn "Previous deployment state found"
    read -p "Resume from last successful step? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        rm -f "${STATE_FILE}"
        info "Starting fresh deployment"
    else
        info "Resuming previous deployment"
    fi
fi

# ============================================
# STEP 0: Prerequisites Check
# ============================================
if ! is_step_complete "prerequisites"; then
    log "\n${CYAN}=========================================="
    log "Checking Prerequisites"
    log "==========================================${NC}"

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI not found. Install: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    fi
    success "Azure CLI installed ($(az version --query '\"azure-cli\"' -o tsv))"

    # Check Azure CLI login
    if ! az account show &> /dev/null 2>&1; then
        error_exit "Not logged into Azure. Run: az login"
    fi
    
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    success "Logged into Azure"
    info "Subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq not found, installing..."
        sudo apt-get update &>> "${LOG_FILE}" && sudo apt-get install -y jq &>> "${LOG_FILE}" || error_exit "Failed to install jq"
        success "jq installed"
    else
        success "jq installed"
    fi

    # Check dig for DNS verification
    if ! command -v dig &> /dev/null; then
        warn "dig not found, installing..."
        sudo apt-get update &>> "${LOG_FILE}" && sudo apt-get install -y dnsutils &>> "${LOG_FILE}" || error_exit "Failed to install dnsutils"
        success "dnsutils installed"
    else
        success "dnsutils installed"
    fi

    # Check SSH key
    if [ ! -f "${SSH_KEY_PATH}.pub" ]; then
        warn "SSH key not found at ${SSH_KEY_PATH}"
        read -p "Generate new SSH key pair? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" >> "${LOG_FILE}" 2>&1 || error_exit "Failed to generate SSH key"
            success "SSH key generated at ${SSH_KEY_PATH}"
        else
            error_exit "SSH key required for VM access"
        fi
    else
        success "SSH key found at ${SSH_KEY_PATH}"
    fi

    save_state "prerequisites" "complete"
fi

    save_state "prerequisites" "complete"
fi

# ============================================
# STEP 1: Configuration
# ============================================
if ! is_step_complete "configuration"; then
    log "\n${CYAN}=========================================="
    log "Configuration"
    log "==========================================${NC}"

    # Load previous values if resuming
    if [ -n "${DOMAIN}" ] && [ -n "${EMAIL}" ] && [ -n "${PUBLIC_IP}" ]; then
        info "Using previous configuration:"
        info "  Domain: ${DOMAIN}"
        info "  Email: ${EMAIL}"
        info "  SSH IP: ${PUBLIC_IP}"
        read -p "Use these values? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            unset DOMAIN EMAIL PUBLIC_IP
        fi
    fi

    # Get domain
    if [ -z "${DOMAIN}" ]; then
        while true; do
            read -p "Enter your domain (e.g., vorlichmedia.com): " DOMAIN
            if [[ "${DOMAIN}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                warn "Invalid domain format. Please try again."
            fi
        done
        save_state "DOMAIN" "${DOMAIN}"
    fi

    # Get email
    if [ -z "${EMAIL}" ]; then
        while true; do
            read -p "Enter your email for Let's Encrypt: " EMAIL
            if [[ "${EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                warn "Invalid email format. Please try again."
            fi
        done
        save_state "EMAIL" "${EMAIL}"
    fi

    # Get public IP
    if [ -z "${PUBLIC_IP}" ]; then
        info "Detecting your public IP..."
        PUBLIC_IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 icanhazip.com 2>/dev/null || curl -s --max-time 10 api.ipify.org 2>/dev/null)
        
        if [ -z "${PUBLIC_IP}" ]; then
            warn "Could not auto-detect public IP"
            read -p "Enter your public IP address for SSH access: " PUBLIC_IP
        else
            info "Detected IP: ${PUBLIC_IP}"
            read -p "Use this IP for SSH access? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                read -p "Enter your management IP: " PUBLIC_IP
            fi
        fi
        
        # Validate IP format
        if ! [[ "${PUBLIC_IP}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            error_exit "Invalid IP address format: ${PUBLIC_IP}"
        fi
        save_state "PUBLIC_IP" "${PUBLIC_IP}"
    fi

    success "Configuration complete"
    info "  Domain: paw.${DOMAIN}"
    info "  Email: ${EMAIL}"
    info "  SSH IP: ${PUBLIC_IP}"
    
    save_state "configuration" "complete"
fi

    save_state "configuration" "complete"
fi

# ============================================
# STEP 2: Deploy VM Infrastructure
# ============================================
if ! is_step_complete "infrastructure"; then
    log "\n${CYAN}=========================================="
    log "Step 1: Deploying VM Infrastructure"
    log "==========================================${NC}"

    # Read SSH public key
    SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub" 2>/dev/null) || error_exit "Failed to read SSH public key"

    # Create temporary parameters file
    TEMP_PARAMS="/tmp/deployment-params-$$.json"
    cat > "${TEMP_PARAMS}" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "sshPublicKey": {
      "value": "${SSH_PUBLIC_KEY}"
    },
    "sshSourceIp": {
      "value": "${PUBLIC_IP}"
    },
    "customDomain": {
      "value": "paw.${DOMAIN}"
    },
    "ukOriginHostname": {
      "value": "paw.${DOMAIN}"
    },
    "canadaOriginHostname": {
      "value": "paw-ca.${DOMAIN}"
    }
  }
}
EOF

    info "Starting infrastructure deployment..."
    DEPLOYMENT_NAME="guacamole-$(date +%Y%m%d-%H%M%S)"
    save_state "DEPLOYMENT_NAME" "${DEPLOYMENT_NAME}"

    # Deploy with error handling
    if ! az deployment sub create \
        --location uksouth \
        --template-file "${REPO_DIR}/infrastructure/bicep/main.bicep" \
        --parameters @"${TEMP_PARAMS}" \
        --name "${DEPLOYMENT_NAME}" \
        --output json &>> "${LOG_FILE}"; then
        rm -f "${TEMP_PARAMS}"
        error_exit "Infrastructure deployment failed. Check log for details."
    fi

    # Clean up temp file
    rm -f "${TEMP_PARAMS}"

    # Get outputs with retry logic
    info "Retrieving deployment outputs..."
    RETRY_COUNT=0
    MAX_RETRIES=5
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        OUTPUTS=$(az deployment sub show --name "${DEPLOYMENT_NAME}" --query properties.outputs -o json 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "${OUTPUTS}" ]; then
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        warn "Waiting for deployment outputs... (${RETRY_COUNT}/${MAX_RETRIES})"
        sleep 10
    done

    if [ -z "${OUTPUTS}" ]; then
        error_exit "Failed to retrieve deployment outputs"
    fi

    # Parse outputs
    UK_IP=$(echo "${OUTPUTS}" | jq -r '.ukPublicIp.value' 2>/dev/null)
    CA_IP=$(echo "${OUTPUTS}" | jq -r '.canadaPublicIp.value' 2>/dev/null)
    UK_RESOURCE_GROUP=$(echo "${OUTPUTS}" | jq -r '.ukResourceGroup.value' 2>/dev/null)
    CA_RESOURCE_GROUP=$(echo "${OUTPUTS}" | jq -r '.canadaResourceGroup.value' 2>/dev/null)

    # Validate outputs
    if [ -z "${UK_IP}" ] || [ -z "${CA_IP}" ] || [ "${UK_IP}" == "null" ] || [ "${CA_IP}" == "null" ]; then
        error_exit "Failed to parse deployment outputs. Check deployment in Azure Portal."
    fi

    save_state "UK_IP" "${UK_IP}"
    save_state "CA_IP" "${CA_IP}"
    save_state "UK_RESOURCE_GROUP" "${UK_RESOURCE_GROUP}"
    save_state "CA_RESOURCE_GROUP" "${CA_RESOURCE_GROUP}"

    success "Infrastructure deployed"
    info "  UK VM Public IP: ${UK_IP}"
    info "  Canada VM Public IP: ${CA_IP}"
    info "  UK Resource Group: ${UK_RESOURCE_GROUP}"
    info "  Canada Resource Group: ${CA_RESOURCE_GROUP}"

    save_state "infrastructure" "complete"
fi

    save_state "infrastructure" "complete"
fi

# ============================================
# STEP 3: DNS Configuration
# ============================================
if ! is_step_complete "dns"; then
    log "\n${CYAN}=========================================="
    log "Step 2: DNS Configuration"
    log "==========================================${NC}"
    
    log "${YELLOW}Please configure the following DNS A records:${NC}"
    log "  ${CYAN}paw.${DOMAIN}${NC} -> ${UK_IP}"
    log "  ${CYAN}paw-ca.${DOMAIN}${NC} -> ${CA_IP}"
    log ""
    log "DNS Configuration Steps:"
    log "1. Login to your DNS provider (Cloudflare, GoDaddy, etc.)"
    log "2. Create/Update A record: ${CYAN}paw.${DOMAIN}${NC} -> ${UK_IP}"
    log "3. Create A record: ${CYAN}paw-ca.${DOMAIN}${NC} -> ${CA_IP}"
    log "4. Save changes"
    log ""
    read -p "Press ENTER when DNS records are configured..."

    # Verify DNS with retries
    info "Verifying DNS propagation (this may take a few minutes)..."
    DNS_VERIFIED=false
    MAX_DNS_ATTEMPTS=60
    DNS_ATTEMPT=0
    
    while [ $DNS_ATTEMPT -lt $MAX_DNS_ATTEMPTS ] && [ "$DNS_VERIFIED" = false ]; do
        DNS_ATTEMPT=$((DNS_ATTEMPT + 1))
        
        UK_DNS=$(dig +short paw.${DOMAIN} @8.8.8.8 2>/dev/null | grep -E '^[0-9.]+$' | tail -n1)
        CA_DNS=$(dig +short paw-ca.${DOMAIN} @8.8.8.8 2>/dev/null | grep -E '^[0-9.]+$' | tail -n1)
        
        if [ "${UK_DNS}" == "${UK_IP}" ] && [ "${CA_DNS}" == "${CA_IP}" ]; then
            success "DNS propagated successfully"
            info "  paw.${DOMAIN} -> ${UK_DNS}"
            info "  paw-ca.${DOMAIN} -> ${CA_DNS}"
            DNS_VERIFIED=true
        else
            if [ $((DNS_ATTEMPT % 10)) -eq 0 ]; then
                warn "Waiting for DNS propagation... (${DNS_ATTEMPT}/${MAX_DNS_ATTEMPTS})"
                info "  Current: paw.${DOMAIN} -> ${UK_DNS:-not found}"
                info "  Expected: paw.${DOMAIN} -> ${UK_IP}"
                info "  Current: paw-ca.${DOMAIN} -> ${CA_DNS:-not found}"
                info "  Expected: paw-ca.${DOMAIN} -> ${CA_IP}"
            fi
            sleep 10
        fi
    done

    if [ "$DNS_VERIFIED" = false ]; then
        warn "DNS verification incomplete, but continuing..."
        warn "You may need to verify manually: dig paw.${DOMAIN} +short"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error_exit "Deployment cancelled. Re-run script when DNS is ready."
        fi
    fi

    save_state "dns" "complete"
fi

    save_state "dns" "complete"
fi

# ============================================
# STEP 4: Install Guacamole on UK VM
# ============================================
if ! is_step_complete "uk_guacamole"; then
    log "\n${CYAN}=========================================="
    log "Step 3: Installing Guacamole on UK VM"
    log "==========================================${NC}"

    info "Connecting to UK VM (${UK_IP})..."
    
    # Test SSH connectivity first
    if ! ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o BatchMode=yes pawadmin@${UK_IP} "echo 'SSH OK'" &>> "${LOG_FILE}"; then
        error_exit "Cannot connect to UK VM via SSH. Check NSG rules allow your IP (${PUBLIC_IP})"
    fi
    success "SSH connection to UK VM successful"

    info "Installing Guacamole on UK VM (this may take 10-15 minutes)..."
    
    if ! ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no pawadmin@${UK_IP} bash << EOSSH 2>&1 | tee -a "${LOG_FILE}"
set -e
cd ~
if [ ! -d "guacamole-letsencrypt-docker" ]; then
    git clone https://github.com/hendizzo/guacamole-letsencrypt-docker.git
fi
cd guacamole-letsencrypt-docker
git checkout Multi-Region_With_FrontDoor
git pull
chmod +x scripts/install-guacamole.sh
./scripts/install-guacamole.sh paw.${DOMAIN} ${EMAIL}
EOSSH
    then
        error_exit "Failed to install Guacamole on UK VM. Check log file."
    fi

    success "Guacamole installed on UK VM"
    save_state "uk_guacamole" "complete"
fi

# ============================================
# STEP 5: Install Guacamole on Canada VM
# ============================================
if ! is_step_complete "canada_guacamole"; then
    log "\n${CYAN}=========================================="
    log "Step 4: Installing Guacamole on Canada VM"
    log "==========================================${NC}"

    info "Connecting to Canada VM (${CA_IP})..."
    
    # Test SSH connectivity first
    if ! ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o BatchMode=yes pawadmin@${CA_IP} "echo 'SSH OK'" &>> "${LOG_FILE}"; then
        error_exit "Cannot connect to Canada VM via SSH. Check NSG rules allow your IP (${PUBLIC_IP})"
    fi
    success "SSH connection to Canada VM successful"

    info "Installing Guacamole on Canada VM (this may take 10-15 minutes)..."
    
    if ! ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no pawadmin@${CA_IP} bash << EOSSH 2>&1 | tee -a "${LOG_FILE}"
set -e
cd ~
if [ ! -d "guacamole-letsencrypt-docker" ]; then
    git clone https://github.com/hendizzo/guacamole-letsencrypt-docker.git
fi
cd guacamole-letsencrypt-docker
git checkout Multi-Region_With_FrontDoor
git pull
chmod +x scripts/install-guacamole.sh
./scripts/install-guacamole.sh paw-ca.${DOMAIN} ${EMAIL}
EOSSH
    then
        error_exit "Failed to install Guacamole on Canada VM. Check log file."
    fi

    success "Guacamole installed on Canada VM"
    save_state "canada_guacamole" "complete"
fi

    save_state "canada_guacamole" "complete"
fi

# ============================================
# STEP 6: Verify Guacamole Installations
# ============================================
if ! is_step_complete "verification"; then
    log "\n${CYAN}=========================================="
    log "Step 5: Verifying Installations"
    log "==========================================${NC}"

    info "Waiting for services to fully start (30 seconds)..."
    sleep 30

    # Verify UK
    info "Testing UK Guacamole (https://paw.${DOMAIN}/guacamole/)..."
    UK_STATUS=$(curl -ks -o /dev/null -w "%{http_code}" --max-time 30 https://paw.${DOMAIN}/guacamole/ 2>/dev/null || echo "000")
    
    if [ "$UK_STATUS" == "302" ] || [ "$UK_STATUS" == "200" ] || [ "$UK_STATUS" == "301" ]; then
        success "UK Guacamole responding (HTTP ${UK_STATUS})"
    else
        error_exit "UK Guacamole not responding correctly (HTTP ${UK_STATUS}). Check logs on VM."
    fi

    # Verify Canada
    info "Testing Canada Guacamole (https://paw-ca.${DOMAIN}/guacamole/)..."
    CA_STATUS=$(curl -ks -o /dev/null -w "%{http_code}" --max-time 30 https://paw-ca.${DOMAIN}/guacamole/ 2>/dev/null || echo "000")
    
    if [ "$CA_STATUS" == "302" ] || [ "$CA_STATUS" == "200" ] || [ "$CA_STATUS" == "301" ]; then
        success "Canada Guacamole responding (HTTP ${CA_STATUS})"
    else
        error_exit "Canada Guacamole not responding correctly (HTTP ${CA_STATUS}). Check logs on VM."
    fi

    save_state "verification" "complete"
fi

    save_state "verification" "complete"
fi

# ============================================
# STEP 7: Deploy Azure Front Door
# ============================================
if ! is_step_complete "frontdoor"; then
    log "\n${CYAN}=========================================="
    log "Step 6: Deploying Azure Front Door"
    log "==========================================${NC}"

    # Check if Front Door resource group exists
    if ! az group show --name RG-Global-PAW-Core &>> "${LOG_FILE}"; then
        info "Creating Front Door resource group..."
        az group create --name RG-Global-PAW-Core --location uksouth &>> "${LOG_FILE}" || error_exit "Failed to create Front Door resource group"
    fi

    info "Deploying Azure Front Door (this may take 5-10 minutes)..."
    
    if ! az deployment group create \
        --resource-group RG-Global-PAW-Core \
        --template-file "${REPO_DIR}/infrastructure/bicep/front-door.bicep" \
        --parameters frontDoorName=guacamole-frontdoor \
        --parameters customDomain=paw.${DOMAIN} \
        --parameters ukOriginHostname=paw.${DOMAIN} \
        --parameters canadaOriginHostname=paw-ca.${DOMAIN} \
        --output json &>> "${LOG_FILE}"; then
        error_exit "Front Door deployment failed. Check log file."
    fi

    # Get Front Door endpoint with retry
    info "Retrieving Front Door endpoint..."
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt 5 ]; do
        FRONTDOOR_ENDPOINT=$(az deployment group show \
            --resource-group RG-Global-PAW-Core \
            --name front-door \
            --query properties.outputs.frontDoorEndpointHostName.value -o tsv 2>/dev/null)
        
        if [ -n "${FRONTDOOR_ENDPOINT}" ] && [ "${FRONTDOOR_ENDPOINT}" != "null" ]; then
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        warn "Waiting for Front Door endpoint... (${RETRY_COUNT}/5)"
        sleep 10
    done

    if [ -z "${FRONTDOOR_ENDPOINT}" ] || [ "${FRONTDOOR_ENDPOINT}" == "null" ]; then
        warn "Could not retrieve Front Door endpoint automatically"
        FRONTDOOR_ENDPOINT="<check Azure Portal>"
    else
        save_state "FRONTDOOR_ENDPOINT" "${FRONTDOOR_ENDPOINT}"
    fi

    success "Front Door deployed"
    info "  Endpoint: ${FRONTDOOR_ENDPOINT}"

    save_state "frontdoor" "complete"
fi

    save_state "frontdoor" "complete"
fi

# ============================================
# STEP 8: Final DNS Configuration
# ============================================
log "\n${CYAN}=========================================="
log "Step 7: Final DNS Configuration"
log "==========================================${NC}"

log "${YELLOW}Update your DNS one final time:${NC}"
log ""
log "Option 1 - CNAME (Recommended):"
log "  Change ${CYAN}paw.${DOMAIN}${NC} from A record to:"
log "  ${GREEN}CNAME: paw.${DOMAIN} -> ${FRONTDOOR_ENDPOINT}${NC}"
log ""
log "Option 2 - Keep A records and add alias:"
log "  Keep existing A records, add:"
log "  ${GREEN}CNAME: guacamole.${DOMAIN} -> ${FRONTDOOR_ENDPOINT}${NC}"
log ""

# ============================================
# Deployment Summary
# ============================================
log "\n${GREEN}=========================================="
log "✓ DEPLOYMENT COMPLETE!"
log "==========================================${NC}"
log ""
log "${CYAN}Region URLs:${NC}"
log "  UK Direct:      ${GREEN}https://paw.${DOMAIN}/guacamole/${NC}"
log "  Canada Direct:  ${GREEN}https://paw-ca.${DOMAIN}/guacamole/${NC}"
log "  Front Door:     ${GREEN}https://${FRONTDOOR_ENDPOINT}/guacamole/${NC}"
log ""
log "${CYAN}Azure Resources:${NC}"
log "  UK Resource Group:     ${UK_RESOURCE_GROUP}"
log "  Canada Resource Group: ${CA_RESOURCE_GROUP}"
log "  Front Door RG:         RG-Global-PAW-Core"
log "  Deployment Name:       ${DEPLOYMENT_NAME}"
log ""
log "${YELLOW}⚠️  Default Credentials:${NC}"
log "  Username: ${GREEN}guacadmin${NC}"
log "  Password: ${GREEN}guacadmin${NC}"
log "  ${RED}CHANGE IMMEDIATELY AFTER FIRST LOGIN!${NC}"
log ""
log "${CYAN}Next Steps:${NC}"
log "1. Update DNS to point to Front Door (instructions above)"
log "2. Wait 5-10 minutes for Front Door to become active"
log "3. Browse to https://paw.${DOMAIN}/guacamole/"
log "4. Login with default credentials"
log "5. ${RED}Change password immediately${NC} (Settings → Preferences)"
log "6. Create your admin user account"
log "7. Add remote desktop connections"
log "8. Test multi-region routing"
log ""
log "${CYAN}Useful Commands:${NC}"
log "  SSH to UK VM:      ssh -i ${SSH_KEY_PATH} pawadmin@${UK_IP}"
log "  SSH to Canada VM:  ssh -i ${SSH_KEY_PATH} pawadmin@${CA_IP}"
log "  View UK logs:      ssh -i ${SSH_KEY_PATH} pawadmin@${UK_IP} 'cd ~/guacamole-letsencrypt-docker && docker compose logs'"
log "  View Canada logs:  ssh -i ${SSH_KEY_PATH} pawadmin@${CA_IP} 'cd ~/guacamole-letsencrypt-docker && docker compose logs'"
log ""
log "${GREEN}Deployment log saved to: ${LOG_FILE}${NC}"
log "${GREEN}Deployment state saved to: ${STATE_FILE}${NC}"
log ""

# Clean up state file on successful completion
if [ -f "${STATE_FILE}" ]; then
    info "Deployment completed successfully, cleaning up state file..."
    rm -f "${STATE_FILE}"
fi

log "${BLUE}Happy remote accessing! 🚀${NC}"
