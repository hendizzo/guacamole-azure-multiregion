# Multi-Region Infrastructure Guide

This guide explains the multi-region deployment architecture using Azure Front Door for global load balancing.

## 🌍 Architecture Overview

```
                                    Internet
                                       │
                                       ▼
                         ┌─────────────────────────┐
                         │   Azure Front Door      │
                         │   (Global Load Balancer)│
                         │   Latency-based Routing │
                         └──────────┬──────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
        ┌───────────────────────┐      ┌───────────────────────┐
        │   UK South Region     │      │  Canada Central        │
        │   paw.domain.com      │      │  paw-ca.domain.com     │
        │                       │      │                        │
        │   ┌───────────────┐   │      │   ┌───────────────┐   │
        │   │ Guacamole VM  │   │      │   │ Guacamole VM  │   │
        │   │ 172.18.0.4    │   │      │   │ 172.19.8.4    │   │
        │   │ + PostgreSQL  │   │      │   │ + PostgreSQL  │   │
        │   │ + nginx+SSL   │   │      │   │ + nginx+SSL   │   │
        │   └───────────────┘   │      │   └───────────────┘   │
        └───────────────────────┘      └───────────────────────┘
```

## 📋 Components

### Azure Front Door
- **SKU**: Standard
- **Routing**: Latency-based with 50ms threshold
- **Health Probes**: HTTPS GET on `/` every 30 seconds
- **Priority**: Equal priority (1) for both origins
- **Weight**: Equal weight (1000) for balanced distribution

### UK Region (uksouth)
- **Resource Group**: RG-UK-PAW-Core
- **VNet**: 172.18.0.0/16
- **Subnet**: 172.18.8.0/22 (guacamole)
- **VM**: Standard_B2s, Ubuntu 22.04
- **Domain**: paw.example.com (or your domain)

### Canada Region (canadacentral)
- **Resource Group**: RG-CA-PAW-Core
- **VNet**: 172.19.0.0/16
- **Subnet**: 172.19.8.0/22 (guacamole)
- **VM**: Standard_B2s, Ubuntu 22.04
- **Domain**: paw-ca.example.com (or your domain)

### Security
- **NSG Rules**:
  - SSH (22): From management IP only
  - HTTP (80): From AzureFrontDoor.Backend service tag only
  - HTTPS (443): From AzureFrontDoor.Backend service tag only
- **Effect**: Direct VM access blocked, only Front Door can reach VMs
- **SSL**: Let's Encrypt certificates on each VM

## 🚀 Automated Deployment

### Prerequisites
```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install jq
sudo apt-get install -y jq

# Install dig (dnsutils)
sudo apt-get install -y dnsutils

# Login to Azure
az login
```

### One-Command Deployment
```bash
./scripts/deploy-infrastructure.sh
```

The script will:
1. ✅ Check prerequisites (Azure CLI, jq, dig)
2. ✅ Prompt for Azure login and subscription selection
3. ✅ Validate all parameters (domain, email, IP formats)
4. ✅ Deploy UK infrastructure (VNet, NSG, VM, Public IP)
5. ✅ Deploy Canada infrastructure (VNet, NSG, VM, Public IP)
6. ✅ Wait for DNS propagation
7. ✅ Install Guacamole on both VMs via SSH
8. ✅ Obtain Let's Encrypt certificates
9. ✅ Deploy Azure Front Door
10. ✅ Configure origin health probes
11. ✅ Verify deployment

### Resume on Failure
If deployment fails, the script saves state to `deployment-state.json` and can resume:
```bash
./scripts/deploy-infrastructure.sh  # Will detect state file and resume
```

## 📝 Manual Deployment Steps

### 1. Deploy Infrastructure
```bash
# Deploy UK and Canada VMs
az deployment sub create \
  --location uksouth \
  --template-file infrastructure/bicep/main.bicep \
  --parameters infrastructure/parameters/parameters-main.json \
  --parameters infrastructure/parameters/parameters-uk.json \
  --parameters infrastructure/parameters/parameters-canada.json
```

### 2. Configure DNS
Create A records pointing to VM public IPs:
```
paw.domain.com      → UK VM Public IP
paw-ca.domain.com   → Canada VM Public IP
```

### 3. Install Guacamole on Each VM
```bash
# SSH to UK VM
ssh -i ~/.ssh/guacamole_key pawadmin@<UK-PUBLIC-IP>

# Clone repository
git clone https://github.com/hendizzo/guacamole-azure-multiregion.git
cd guacamole-azure-multiregion
git checkout main

# Configure domain
echo "DOMAIN=paw.domain.com" > .env

# Update docker-compose.yml
sed -i 's/CERTBOT_EMAIL:.*/CERTBOT_EMAIL: your-email@example.com/' docker-compose.yml

# Update nginx config
sed -i 's/your-domain.com/paw.domain.com/g' nginx/user_conf.d/guacamole.conf

# Start services
sudo docker compose up -d

# Repeat for Canada VM with paw-ca.domain.com
```

### 4. Deploy Front Door
```bash
az deployment group create \
  --resource-group RG-UK-PAW-Core \
  --template-file infrastructure/bicep/front-door.bicep \
  --parameters infrastructure/parameters/parameters-frontdoor.json
```

## 🔧 DNS Configuration for Geographic Routing

### Option 1: CNAME to Front Door (Recommended)
```
paw.domain.com → CNAME → <frontdoor-endpoint>.z03.azurefd.net
```

**Benefits**:
- ✅ Users automatically routed to nearest region
- ✅ Automatic failover if one region is down
- ✅ Better performance through Front Door CDN
- ✅ Additional DDoS protection

### Option 2: Direct A Records (Current Setup)
```
paw.domain.com    → A → UK VM IP
paw-ca.domain.com → A → Canada VM IP
```

**Use case**: Direct access to specific regions for backend health checks

## 📊 Monitoring & Health Checks

### Check Origin Health
```bash
# UK origin
az afd origin show \
  --profile-name guacamole-frontdoor \
  --resource-group RG-UK-PAW-Core \
  --origin-group-name guacamole-origins \
  --origin-name vm-uksouth

# Canada origin
az afd origin show \
  --profile-name guacamole-frontdoor \
  --resource-group RG-UK-PAW-Core \
  --origin-group-name guacamole-origins \
  --origin-name vm-canadacentral
```

### Test Front Door Endpoint
```bash
# Get Front Door hostname
FRONT_DOOR_HOSTNAME=$(az afd endpoint show \
  --profile-name guacamole-frontdoor \
  --resource-group RG-UK-PAW-Core \
  --endpoint-name guacamole-endpoint \
  --query hostName -o tsv)

# Test access
curl -I https://${FRONT_DOOR_HOSTNAME}/guacamole/
```

### Test Geographic Routing
```bash
# Multiple requests to see routing
for i in {1..5}; do
  curl -s -w "\nTime: %{time_total}s\n" https://${FRONT_DOOR_HOSTNAME}/ > /dev/null
done
```

## 🔐 Security Considerations

### Network Security Groups
- Direct VM access is **blocked** by NSG
- Only Front Door Backend can reach VMs on ports 80/443
- SSH only from management IP

### SSL/TLS
- Let's Encrypt certificates on each VM
- Automatic renewal every 90 days
- Front Door enforces HTTPS

### Database Isolation
- Each region has **independent PostgreSQL database**
- No cross-region replication
- User accounts are region-specific
- Session recordings stored locally

## 🎯 Post-Deployment Tasks

### 1. Change Default Password
Login to Guacamole at `https://<frontdoor-endpoint>/guacamole/`:
- Username: `guacadmin`
- Password: `guacadmin`
- **Immediately change password** in Settings → Preferences

### 2. Create Admin Users
Create separate admin users for each region (databases are independent).

### 3. Configure Connections
Add RDP/SSH/VNC connections in each region as needed.

### 4. Set Up Monitoring
Consider adding Azure Monitor alerts for:
- VM CPU/Memory thresholds
- Front Door health probe failures
- Origin response time degradation

## 📚 Parameter Files

### UK Parameters (`infrastructure/parameters/parameters-uk.json`)
```json
{
  "location": "uksouth",
  "regionCode": "UK",
  "vnetAddressSpace": "172.18.0.0/16",
  "subnetAddressPrefix": "172.18.8.0/22",
  "sshSourceIp": "YOUR_MANAGEMENT_IP"
}
```

### Canada Parameters (`infrastructure/parameters/parameters-canada.json`)
```json
{
  "location": "canadacentral",
  "regionCode": "CA",
  "vnetAddressSpace": "172.19.0.0/16",
  "subnetAddressPrefix": "172.19.8.0/22",
  "sshSourceIp": "YOUR_MANAGEMENT_IP"
}
```

### Front Door Parameters (`infrastructure/parameters/parameters-frontdoor.json`)
```json
{
  "ukOriginHostname": "paw.yourdomain.com",
  "canadaOriginHostname": "paw-ca.yourdomain.com"
}
```

## 🔄 Adding Additional Regions

To add more regions (e.g., Australia, Japan):

1. **Create parameter file**:
   ```bash
   cp infrastructure/parameters/parameters-canada.json \
      infrastructure/parameters/parameters-australia.json
   ```

2. **Update values**:
   - Change `location` to target region
   - Change `regionCode` to unique identifier
   - Change `vnetAddressSpace` to non-overlapping range (e.g., 172.20.0.0/16)
   - Change `subnetAddressPrefix` accordingly

3. **Update main.bicep**:
   Add new module call for the region

4. **Deploy**:
   ```bash
   az deployment sub create \
     --location uksouth \
     --template-file infrastructure/bicep/main.bicep \
     --parameters @infrastructure/parameters/parameters-australia.json
   ```

5. **Update Front Door**:
   Add new origin to Front Door origin group

## 🐛 Troubleshooting

### Health Probe Failing
```bash
# Check if guacamole is accessible from VM
ssh pawadmin@<VM-IP>
curl -k https://localhost/

# Check docker containers
sudo docker ps
sudo docker logs nginx_guacamole_compose
```

### DNS Not Resolving
```bash
# Check DNS propagation
dig paw.yourdomain.com
dig paw-ca.yourdomain.com

# May take 5-10 minutes to propagate
```

### Certificate Not Obtained
```bash
# Check certbot logs
ssh pawadmin@<VM-IP>
sudo docker logs nginx_guacamole_compose

# Ensure ports 80 and 443 are open in NSG to Front Door
```

### Geographic Routing Not Working
- Ensure DNS points to Front Door endpoint (CNAME), not VM IP
- Check both origins are healthy in Front Door
- Verify NSG allows Front Door Backend service tag

## 📖 Additional Resources

- [Azure Front Door Documentation](https://learn.microsoft.com/en-us/azure/frontdoor/)
- [Guacamole Documentation](https://guacamole.apache.org/doc/gug/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
