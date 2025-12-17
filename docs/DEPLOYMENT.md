# Detailed Deployment Guide

This guide provides step-by-step instructions for deploying the multi-region Guacamole infrastructure.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Infrastructure Deployment](#infrastructure-deployment)
4. [DNS Configuration](#dns-configuration)
5. [Guacamole Installation](#guacamole-installation)
6. [Azure Front Door Setup](#azure-front-door-setup)
7. [Post-Deployment Configuration](#post-deployment-configuration)
8. [Verification](#verification)

## Prerequisites

### Required Tools

- **Azure CLI**: Version 2.50.0 or later
  ```bash
  # Check version
  az --version
  
  # Install/upgrade
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  ```

- **SSH Key Pair**: For VM authentication
  ```bash
  # Generate if you don't have one
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/guacamole_key
  ```

### Required Information

Before starting, gather:
- ✅ Azure subscription ID
- ✅ SSH public key (contents of `~/.ssh/your-key.pub`)
- ✅ Management IP address (for SSH access)
- ✅ Domain name (e.g., `yourdomain.com`)
- ✅ Email address (for Let's Encrypt)

## Initial Setup

### 1. Login to Azure

```bash
# Login
az login

# Set subscription (if you have multiple)
az account set --subscription "<subscription-id>"

# Verify
az account show
```

### 2. Clone Repository

```bash
git clone https://github.com/yourusername/guacamole-infrastructure.git
cd guacamole-infrastructure
```

### 3. Customize Parameters

Edit parameter files with your values:

**UK Parameters** (`infrastructure/parameters/parameters-uk.json`):
```json
{
  "sshSourceIp": {
    "value": "YOUR.MANAGEMENT.IP.HERE"
  }
}
```

**Canada Parameters** (`infrastructure/parameters/parameters-canada.json`):
```json
{
  "sshSourceIp": {
    "value": "YOUR.MANAGEMENT.IP.HERE"
  }
}
```

**Front Door Parameters** (`infrastructure/parameters/parameters-frontdoor.json`):
```json
{
  "customDomain": {
    "value": "paw.yourdomain.com"
  },
  "ukOriginHostname": {
    "value": "paw.yourdomain.com"
  },
  "canadaOriginHostname": {
    "value": "paw-ca.yourdomain.com"
  }
}
```

## Infrastructure Deployment

### UK Region Deployment

```bash
# 1. Create resource group
az group create \
  --name RG-UK-PAW-Core \
  --location uksouth

# 2. Validate template
az deployment group validate \
  --resource-group RG-UK-PAW-Core \
  --template-file infrastructure/bicep/guacamole-vm.bicep \
  --parameters @infrastructure/parameters/parameters-uk.json \
  --parameters sshPublicKey="$(cat ~/.ssh/guacamole_key.pub)"

# 3. Deploy
az deployment group create \
  --resource-group RG-UK-PAW-Core \
  --template-file infrastructure/bicep/guacamole-vm.bicep \
  --parameters @infrastructure/parameters/parameters-uk.json \
  --parameters sshPublicKey="$(cat ~/.ssh/guacamole_key.pub)" \
  --name uk-deployment-$(date +%Y%m%d-%H%M%S)

# 4. Get outputs
az deployment group show \
  --resource-group RG-UK-PAW-Core \
  --name uk-deployment-<timestamp> \
  --query properties.outputs
```

**Expected Output:**
```json
{
  "publicIpAddress": "20.26.236.70",
  "privateIpAddress": "172.18.8.4",
  "vmName": "VM-UK-PAW-Gateway",
  "vnetName": "VNET-UK-uksouth"
}
```

### Canada Region Deployment

```bash
# 1. Create resource group
az group create \
  --name RG-CA-PAW-Core \
  --location canadacentral

# 2. Deploy
az deployment group create \
  --resource-group RG-CA-PAW-Core \
  --template-file infrastructure/bicep/guacamole-vm.bicep \
  --parameters @infrastructure/parameters/parameters-canada.json \
  --parameters sshPublicKey="$(cat ~/.ssh/guacamole_key.pub)" \
  --name canada-deployment-$(date +%Y%m%d-%H%M%S)

# 3. Get outputs
az deployment group show \
  --resource-group RG-CA-PAW-Core \
  --name canada-deployment-<timestamp> \
  --query properties.outputs
```

**Expected Output:**
```json
{
  "publicIpAddress": "4.205.209.241",
  "privateIpAddress": "172.19.8.4",
  "vmName": "VM-CA-PAW-Gateway",
  "vnetName": "VNET-CA-canadacentral"
}
```

## DNS Configuration

### Step 1: Create Initial A Records

In your DNS provider (e.g., Cloudflare), create:

| Type | Name | Content | Proxy Status |
|------|------|---------|--------------|
| A | paw | 20.26.236.70 (UK IP) | DNS Only (gray cloud) |
| A | paw-ca | 4.205.209.241 (Canada IP) | DNS Only (gray cloud) |

**Important**: Set to "DNS Only" (not proxied) for Let's Encrypt validation.

### Step 2: Verify DNS Propagation

```bash
# Check UK
dig paw.yourdomain.com +short
# Should return: 20.26.236.70

# Check Canada
dig paw-ca.yourdomain.com +short
# Should return: 4.205.209.241

# Wait if not propagated (can take up to 1 hour)
```

## Guacamole Installation

### UK Region

```bash
# 1. SSH to UK VM
ssh -i ~/.ssh/guacamole_key pawadmin@20.26.236.70

# 2. Download installation script
curl -o install-guacamole.sh \
  https://raw.githubusercontent.com/yourusername/guacamole-infrastructure/main/scripts/install-guacamole.sh
chmod +x install-guacamole.sh

# 3. Run installation
./install-guacamole.sh paw.yourdomain.com your-email@example.com

# 4. Save the PostgreSQL password displayed!

# 5. Verify services are running
docker ps

# 6. Test locally (should see Guacamole login)
curl -I http://localhost/guacamole/

# 7. Exit SSH
exit
```

### Canada Region

```bash
# 1. SSH to Canada VM
ssh -i ~/.ssh/guacamole_key pawadmin@4.205.209.241

# 2. Download installation script
curl -o install-guacamole.sh \
  https://raw.githubusercontent.com/yourusername/guacamole-infrastructure/main/scripts/install-guacamole.sh
chmod +x install-guacamole.sh

# 3. Run installation
./install-guacamole.sh paw-ca.yourdomain.com your-email@example.com

# 4. Save the PostgreSQL password displayed!

# 5. Verify services are running
docker ps

# 6. Exit SSH
exit
```

### Verify Direct Access

Test each region directly:
```bash
# UK
curl -I https://paw.yourdomain.com/guacamole/
# Should return: 302 Found

# Canada
curl -I https://paw-ca.yourdomain.com/guacamole/
# Should return: 302 Found
```

## Azure Front Door Setup

### Option 1: Deploy with Bicep (Recommended)

```bash
# Deploy Front Door
az deployment sub create \
  --location global \
  --template-file infrastructure/bicep/front-door.bicep \
  --parameters @infrastructure/parameters/parameters-frontdoor.json \
  --name frontdoor-deployment-$(date +%Y%m%d-%H%M%S)

# Get Front Door endpoint
az deployment sub show \
  --name frontdoor-deployment-<timestamp> \
  --query properties.outputs.frontDoorEndpointHostName
```

### Option 2: Manual Configuration via Portal

If you already have Front Door created:

1. **Add Origins:**
   - Go to Front Door → Origin groups
   - Add UK origin: `paw.yourdomain.com`
   - Add Canada origin: `paw-ca.yourdomain.com`

2. **Configure Health Probes:**
   - Path: `/`
   - Protocol: HTTP
   - Method: HEAD
   - Interval: 30 seconds

3. **Update Route:**
   - Pattern: `/*`
   - Forwarding protocol: HTTPS Only
   - HTTPS redirect: Enabled

### Update DNS for Front Door

Update your DNS to point main domain to Front Door:

**Cloudflare:**
1. Delete or modify A record for `paw`
2. Add CNAME: `paw` → `<frontdoor-endpoint>.z03.azurefd.net`
3. Set to "DNS Only" (gray cloud)

**Other DNS:**
1. Change A record for `paw.yourdomain.com`
2. Point to Front Door's IP or use CNAME

## Post-Deployment Configuration

### 1. Change Default Credentials

Access Guacamole via Front Door:
```
https://paw.yourdomain.com/guacamole/
```

Login with defaults:
- Username: `guacadmin`
- Password: `guacadmin`

**Immediately:**
1. Go to Settings (top right) → Preferences
2. Change password to strong password
3. Store securely (e.g., password manager)

### 2. Create Admin User (Optional)

1. Go to Settings → Users → New User
2. Create user with:
   - Username: your-username
   - Password: strong-password
   - Permissions: Administer system
3. Logout and test new account
4. Optionally disable `guacadmin`

### 3. Configure Connections

Add your remote desktop connections:
1. Settings → Connections → New Connection
2. Configure protocol (RDP/VNC/SSH)
3. Set hostname, credentials
4. Test connection

### 4. Verify NSG Rules

Confirm direct access is blocked:
```bash
# This should timeout (Front Door only access)
curl -m 10 http://20.26.236.70

# This should work (via Front Door)
curl -I https://paw.yourdomain.com/guacamole/
```

## Verification

### Health Check Script

Create a verification script:

```bash
#!/bin/bash
# verify-deployment.sh

echo "Checking UK VM..."
ssh -i ~/.ssh/guacamole_key pawadmin@20.26.236.70 "docker ps | grep -c running" || echo "UK VM unreachable"

echo "Checking Canada VM..."
ssh -i ~/.ssh/guacamole_key pawadmin@4.205.209.241 "docker ps | grep -c running" || echo "Canada VM unreachable"

echo "Checking Front Door..."
curl -sSf -I https://paw.yourdomain.com/guacamole/ > /dev/null && echo "Front Door OK" || echo "Front Door FAILED"

echo "Checking UK origin..."
curl -sSf -I https://paw.yourdomain.com/guacamole/ > /dev/null && echo "UK origin OK" || echo "UK origin FAILED"

echo "Checking Canada origin..."
curl -sSf -I https://paw-ca.yourdomain.com/guacamole/ > /dev/null && echo "Canada origin OK" || echo "Canada origin FAILED"

echo "Verification complete!"
```

### Manual Verification Checklist

- [ ] UK VM accessible via SSH
- [ ] Canada VM accessible via SSH
- [ ] UK Guacamole responds on HTTPS
- [ ] Canada Guacamole responds on HTTPS
- [ ] Front Door endpoint working
- [ ] Direct IP access blocked (timeout)
- [ ] SSL certificates valid
- [ ] Health probes succeeding
- [ ] Can login to Guacamole
- [ ] Can create connections
- [ ] Default password changed

### Monitoring

View Front Door metrics:
```bash
# Get health probe status
az afd endpoint list \
  --profile-name guacamole-frontdoor \
  --resource-group <resource-group> \
  --query "[].{name:name, enabledState:enabledState}"

# View origin health
az afd origin show \
  --profile-name guacamole-frontdoor \
  --origin-group-name guacamole-origins \
  --origin-name uk-origin \
  --resource-group <resource-group> \
  --query "{name:name, enabledState:enabledState, healthProbeSettings:originGroup.healthProbeSettings}"
```

## Common Issues

### Issue: SSL Certificate Not Working

**Symptoms:** HTTPS shows certificate error

**Solution:**
```bash
ssh pawadmin@<vm-ip>
cd ~/guacamole-docker-compose

# Check certbot logs
docker compose logs certbot

# Verify DNS is correct
dig paw.yourdomain.com +short

# Re-run certbot manually
docker compose run --rm certbot certonly --webroot \
  --webroot-path=/var/www/certbot \
  --email your-email@example.com \
  --agree-tos \
  -d paw.yourdomain.com

# Restart nginx
docker compose restart nginx
```

### Issue: Front Door Health Probe Failing

**Symptoms:** Origin showing unhealthy

**Solution:**
```bash
# 1. Test origin directly
curl -I https://paw.yourdomain.com/

# 2. Check NSG allows Front Door
az network nsg rule show \
  --resource-group RG-UK-PAW-Core \
  --nsg-name VM-UK-PAW-Gateway-nsg \
  --name AllowHTTPFromFrontDoor

# 3. Verify nginx is running
ssh pawadmin@<vm-ip> "docker ps | grep nginx"
```

### Issue: Cannot Login to Guacamole

**Symptoms:** Invalid credentials or 404 error

**Solution:**
```bash
ssh pawadmin@<vm-ip>
cd ~/guacamole-docker-compose

# Check all containers running
docker ps

# View guacamole logs
docker compose logs guacamole

# Restart services
docker compose restart

# Verify database initialized
docker exec postgres_guacamole psql -U guacamole_user -d guacamole_db -c "\dt"
```

## Next Steps

After successful deployment:

1. **Backup Configuration**: Save passwords, SSH keys securely
2. **Document Connections**: Record what servers you add
3. **Set Up Monitoring**: Configure Azure Monitor alerts
4. **Plan Maintenance**: Schedule update windows
5. **Test Failover**: Verify multi-region works correctly

## Support

For deployment issues:
1. Check logs: `docker compose logs <service>`
2. Verify NSG rules: `az network nsg rule list`
3. Test connectivity: `curl` commands above
4. Review Azure Portal for resource status
