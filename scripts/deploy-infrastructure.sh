#!/bin/bash
# Complete Infrastructure Deployment Script
# This script orchestrates the entire multi-region Guacamole deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARAMETERS_FILE="${REPO_DIR}/infrastructure/parameters/parameters-main.json"
SSH_KEY_PATH="${HOME}/.ssh/guacamole_key"

echo -e "${BLUE}=========================================="
echo "Multi-Region Guacamole Deployment"
echo "==========================================${NC}"

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI not found. Please install: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Azure CLI installed${NC}"

# Check login
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Not logged into Azure. Please run: az login${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Azure CLI logged in${NC}"

# Check SSH key
if [ ! -f "${SSH_KEY_PATH}.pub" ]; then
    echo -e "${YELLOW}⚠️  SSH key not found at ${SSH_KEY_PATH}${NC}"
    read -p "Generate new SSH key pair? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N ""
        echo -e "${GREEN}✓ SSH key generated${NC}"
    else
        echo -e "${RED}❌ SSH key required. Exiting.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ SSH key found${NC}"

# Get user inputs
echo -e "\n${YELLOW}Configuration:${NC}"
read -p "Enter your domain (e.g., vorlichmedia.com): " DOMAIN
read -p "Enter your email for Let's Encrypt: " EMAIL

# Get public IP
echo -e "\n${YELLOW}Detecting your public IP...${NC}"
PUBLIC_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}Your IP: ${PUBLIC_IP}${NC}"
read -p "Use this IP for SSH access? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter your management IP: " PUBLIC_IP
fi

# Update parameters file
echo -e "\n${YELLOW}Updating parameters...${NC}"
SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")

# Create temporary parameters file
cat > /tmp/deployment-params.json << EOF
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

echo -e "${GREEN}✓ Parameters configured${NC}"

# Deploy infrastructure
echo -e "\n${BLUE}=========================================="
echo "Step 1: Deploying VM Infrastructure"
echo "==========================================${NC}"

DEPLOYMENT_NAME="guacamole-$(date +%Y%m%d-%H%M%S)"

az deployment sub create \
  --location uksouth \
  --template-file "${REPO_DIR}/infrastructure/bicep/main.bicep" \
  --parameters @/tmp/deployment-params.json \
  --name "${DEPLOYMENT_NAME}"

# Get outputs
echo -e "\n${YELLOW}Retrieving deployment outputs...${NC}"
OUTPUTS=$(az deployment sub show --name "${DEPLOYMENT_NAME}" --query properties.outputs -o json)

UK_IP=$(echo $OUTPUTS | jq -r '.ukPublicIp.value')
CA_IP=$(echo $OUTPUTS | jq -r '.canadaPublicIp.value')

echo -e "${GREEN}✓ Infrastructure deployed${NC}"
echo -e "  UK VM Public IP: ${UK_IP}"
echo -e "  Canada VM Public IP: ${CA_IP}"

# DNS Configuration
echo -e "\n${BLUE}=========================================="
echo "Step 2: DNS Configuration Required"
echo "==========================================${NC}"
echo -e "${YELLOW}Please configure the following DNS records:${NC}"
echo -e "  A Record: paw.${DOMAIN} -> ${UK_IP}"
echo -e "  A Record: paw-ca.${DOMAIN} -> ${CA_IP}"
echo ""
read -p "Press ENTER when DNS records are configured and propagated..."

# Verify DNS
echo -e "\n${YELLOW}Verifying DNS propagation...${NC}"
for i in {1..30}; do
    UK_DNS=$(dig +short paw.${DOMAIN} | tail -n1)
    CA_DNS=$(dig +short paw-ca.${DOMAIN} | tail -n1)
    
    if [ "$UK_DNS" == "$UK_IP" ] && [ "$CA_DNS" == "$CA_IP" ]; then
        echo -e "${GREEN}✓ DNS propagated successfully${NC}"
        break
    fi
    
    echo "Waiting for DNS propagation... ($i/30)"
    sleep 10
done

# Install Guacamole on UK
echo -e "\n${BLUE}=========================================="
echo "Step 3: Installing Guacamole on UK VM"
echo "==========================================${NC}"

ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no pawadmin@${UK_IP} << EOSSH
git clone https://github.com/hendizzo/guacamole-letsencrypt-docker.git
cd guacamole-letsencrypt-docker
git checkout Multi-Region_With_FrontDoor
./scripts/install-guacamole.sh paw.${DOMAIN} ${EMAIL}
EOSSH

echo -e "${GREEN}✓ UK Guacamole installed${NC}"

# Install Guacamole on Canada
echo -e "\n${BLUE}=========================================="
echo "Step 4: Installing Guacamole on Canada VM"
echo "==========================================${NC}"

ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no pawadmin@${CA_IP} << EOSSH
git clone https://github.com/hendizzo/guacamole-letsencrypt-docker.git
cd guacamole-letsencrypt-docker
git checkout Multi-Region_With_FrontDoor
./scripts/install-guacamole.sh paw-ca.${DOMAIN} ${EMAIL}
EOSSH

echo -e "${GREEN}✓ Canada Guacamole installed${NC}"

# Verify installations
echo -e "\n${YELLOW}Verifying Guacamole installations...${NC}"
sleep 30  # Wait for services to fully start

UK_STATUS=$(curl -ks -o /dev/null -w "%{http_code}" https://paw.${DOMAIN}/guacamole/ || echo "000")
CA_STATUS=$(curl -ks -o /dev/null -w "%{http_code}" https://paw-ca.${DOMAIN}/guacamole/ || echo "000")

if [ "$UK_STATUS" == "302" ] || [ "$UK_STATUS" == "200" ]; then
    echo -e "${GREEN}✓ UK Guacamole responding${NC}"
else
    echo -e "${RED}✗ UK Guacamole not responding (HTTP ${UK_STATUS})${NC}"
fi

if [ "$CA_STATUS" == "302" ] || [ "$CA_STATUS" == "200" ]; then
    echo -e "${GREEN}✓ Canada Guacamole responding${NC}"
else
    echo -e "${RED}✗ Canada Guacamole not responding (HTTP ${CA_STATUS})${NC}"
fi

# Deploy Front Door
echo -e "\n${BLUE}=========================================="
echo "Step 5: Deploying Azure Front Door"
echo "==========================================${NC}"

az deployment group create \
  --resource-group RG-Global-PAW-Core \
  --template-file "${REPO_DIR}/infrastructure/bicep/front-door.bicep" \
  --parameters frontDoorName=guacamole-frontdoor \
  --parameters customDomain=paw.${DOMAIN} \
  --parameters ukOriginHostname=paw.${DOMAIN} \
  --parameters canadaOriginHostname=paw-ca.${DOMAIN}

FRONTDOOR_ENDPOINT=$(az deployment group show \
  --resource-group RG-Global-PAW-Core \
  --name front-door \
  --query properties.outputs.frontDoorEndpointHostName.value -o tsv)

echo -e "${GREEN}✓ Front Door deployed${NC}"
echo -e "  Endpoint: ${FRONTDOOR_ENDPOINT}"

# Final DNS update
echo -e "\n${BLUE}=========================================="
echo "Step 6: Final DNS Configuration"
echo "==========================================${NC}"
echo -e "${YELLOW}Update your DNS one more time:${NC}"
echo -e "  Change A record for paw.${DOMAIN}"
echo -e "  To CNAME: paw.${DOMAIN} -> ${FRONTDOOR_ENDPOINT}"
echo ""
echo -e "${YELLOW}Or keep A record and add CNAME:${NC}"
echo -e "  CNAME: paw.${DOMAIN} -> ${FRONTDOOR_ENDPOINT}"

# Summary
echo -e "\n${GREEN}=========================================="
echo "✓ DEPLOYMENT COMPLETE!"
echo "==========================================${NC}"
echo -e "UK Region:       https://paw.${DOMAIN}/guacamole/"
echo -e "Canada Region:   https://paw-ca.${DOMAIN}/guacamole/"
echo -e "Front Door:      https://${FRONTDOOR_ENDPOINT}/guacamole/"
echo ""
echo -e "${YELLOW}Default Credentials:${NC}"
echo -e "  Username: guacadmin"
echo -e "  Password: guacadmin"
echo -e "  ${RED}⚠️  CHANGE IMMEDIATELY!${NC}"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "1. Login and change default password"
echo "2. Create admin user account"
echo "3. Add your remote connections"
echo "4. Test multi-region routing"
echo ""
echo -e "${BLUE}Happy remote accessing! 🚀${NC}"
