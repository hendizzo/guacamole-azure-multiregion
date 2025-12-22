# Bicep-Based Deployment Guide

## Overview
This is a fully Infrastructure-as-Code deployment using **Bash** orchestration and **Azure Bicep** templates.

## Architecture
- **deploy.sh**: Main bash script for user interaction and orchestration
- **main.bicep**: Root Bicep template (subscription-level deployment)
- **modules/region.bicep**: Regional infrastructure (VM, networking, NSG)
- **modules/frontdoor.bicep**: Azure Front Door configuration
- **scripts/install-guacamole.sh**: VM installation script (pulled from GitHub)

## Prerequisites

### Required Tools
```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# jq (JSON processor)
sudo apt-get install jq    # Ubuntu/Debian
brew install jq            # macOS

# SSH client (usually pre-installed)
```

### Azure Login
```bash
az login
az account set --subscription "Your Subscription Name"
```

## Deployment Steps

### 1. Clone Repository
```bash
git clone https://github.com/hendizzo/guacamole-azure-multiregion.git
cd guacamole-azure-multiregion
```

### 2. Make Scripts Executable
```bash
chmod +x deploy.sh
chmod +x scripts/install-guacamole.sh
```

### 3. Run Deployment
```bash
./deploy.sh
```

### 4. Follow Prompts
The script will ask for:
- **Domain name** (e.g., example.com)
- **Email address** (for Let's Encrypt certificates)
- **Regions** (select at least 2, e.g., 1,2,3 for UK South, East US, East Asia)

### 5. Wait for Completion
- Infrastructure deployment: ~5-10 minutes
- VM installation & SSL certificates: ~10-15 minutes
- Total time: ~20-25 minutes

## What Gets Deployed

### Per Region:
- Resource Group (`RG-{REGION}-PAW-Core`)
- Virtual Network with subnet
- Network Security Group (SSH from your IP, HTTPS from Front Door)
- Public IP address
- Standard_B2s Ubuntu 22.04 VM
- Custom Script Extension (installs Guacamole from GitHub)

### Global:
- Azure Front Door (Standard SKU)
- Front Door Endpoint
- Origin Group with health probes
- Origins (one per region)
- Route for load balancing

### On Each VM:
- Docker & Docker Compose
- Nginx reverse proxy
- Apache Guacamole (PostgreSQL, guacd, web app)
- Let's Encrypt SSL certificate
- Automatic certificate renewal (certbot timer)

## DNS Configuration

After deployment, configure DNS A records for each region:

```
paw.example.com         → [IP from first region]
paw-us-e.example.com    → [IP from second region]  
paw-hk.example.com      → [IP from third region]
```

The deployment script will display the IPs at the end.

## Access URLs

After deployment completes:

- **Front Door**: `https://{endpoint}.z03.azurefd.net/guacamole/`
- **Regional URLs**: `https://paw[-{region}].example.com/guacamole/`

## Default Credentials

```
Username: guacadmin
Password: guacadmin
```

**⚠️ CRITICAL**: Change the password immediately after first login!

## Bicep Template Structure

### main.bicep (Subscription Scope)
```bicep
- Creates resource groups for each region
- Calls region.bicep module for each region
- Calls frontdoor.bicep module once
- Outputs Front Door endpoint and VM IPs
```

### modules/region.bicep
```bicep
- Network Security Group (NSG)
- Virtual Network (VNet) with subnet
- Public IP
- Network Interface
- Virtual Machine (Ubuntu 22.04)
- Custom Script Extension (runs install-guacamole.sh)
```

### modules/frontdoor.bicep
```bicep
- Front Door profile
- Front Door endpoint
- Origin group with health probes
- Origins (backend servers)
- Route configuration
```

## Customization

### Change VM Size
Edit `main.bicep`:
```bicep
param vmSize string = 'Standard_B2s'  // Change to desired size
```

### Modify Network Ranges
The script uses `172.18-25.0.0/16` ranges. Edit in `main.bicep`:
```bicep
vnetAddressPrefix: '172.${18 + i}.0.0/16'
subnetAddressPrefix: '172.${18 + i}.8.0/22'
```

### Add More Regions
Simply select additional regions during deployment - the Bicep templates handle arrays dynamically.

## Troubleshooting

### View Deployment Status
```bash
az deployment sub show \
  --name guacamole-deployment-{timestamp} \
  --query properties.provisioningState
```

### Check VM Extension Status
```bash
az vm extension show \
  --resource-group RG-GB-PAW-Core \
  --vm-name VM-GB-PAW-Gateway \
  --name InstallGuacamole
```

### View Extension Logs (SSH to VM)
```bash
ssh pawadmin@{vm-ip}
sudo cat /var/log/azure/custom-script/handler.log
sudo journalctl -u docker
sudo docker compose -f /home/pawadmin/guacamole-azure-multiregion/docker-compose.yml logs
```

### Test Regional Endpoints
```bash
curl -k https://paw.example.com/guacamole/
```

## Cleanup

To delete all resources:

```bash
# Delete all resource groups
az group list --query "[?contains(name, 'PAW')].name" -o tsv | \
  xargs -I {} az group delete --name {} --yes --no-wait
```

## Benefits of Bicep Approach

✅ **Infrastructure as Code**: All resources defined in version-controlled templates  
✅ **Idempotent**: Can re-run deployments safely  
✅ **Modular**: Separate modules for regions and Front Door  
✅ **Declarative**: Describe what you want, not how to create it  
✅ **Type-safe**: Bicep validates parameters and resource properties  
✅ **Parallel**: Bicep deploys resources in parallel when possible  
✅ **No State Files**: Azure tracks resource state, not local files  
✅ **GitHub Integration**: VM pulls latest code from repository  

## Comparison: PowerShell vs Bash+Bicep

| Aspect | PowerShell (Old) | Bash+Bicep (New) |
|--------|------------------|------------------|
| Orchestration | PowerShell | Bash |
| Infrastructure | Azure CLI imperatively | Bicep declaratively |
| State Management | JSON file | Azure resource state |
| VM Installation | SSH + bash script | Custom Script Extension + GitHub |
| Idempotency | Manual tracking | Built-in (Bicep) |
| Portability | Windows-focused | Linux/Mac-native |
| Maintainability | Procedural | Declarative |

## Cost Estimate

- **VMs**: 3× Standard_B2s ~ $60/month
- **Front Door**: Standard SKU ~ $35/month + data transfer
- **Networking**: Minimal (standard egress rates)
- **Storage**: Minimal (OS disks only)

**Total**: ~$100-150/month depending on traffic

## Support

- **Repository**: https://github.com/hendizzo/guacamole-azure-multiregion
- **Issues**: Use GitHub Issues for questions/problems
- **Documentation**: See other .md files in repository

## License

See LICENSE file in repository.
