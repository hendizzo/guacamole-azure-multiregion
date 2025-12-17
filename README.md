# Multi-Region Apache Guacamole on Azure

Complete infrastructure-as-code deployment for Apache Guacamole with Azure Front Door global load balancing.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Front Door                         │
│              (Global Load Balancer + CDN)                   │
│           guacamole-endpoint.z03.azurefd.net               │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐      ┌────────▼────────┐
│   UK Region    │      │ Canada Region   │
│   (uksouth)    │      │ (canadacentral) │
├────────────────┤      ├─────────────────┤
│ paw.vorlich... │      │ paw-ca.vorlich..│
│ 20.26.236.70   │      │ 4.205.209.241   │
│                │      │                 │
│ VNet:          │      │ VNet:           │
│ 172.18.0.0/16  │      │ 172.19.0.0/16   │
│                │      │                 │
│ VM: Standard_B2s│     │ VM: Standard_B2s│
│ + Guacamole    │      │ + Guacamole     │
│ + Docker       │      │ + Docker        │
└────────────────┘      └─────────────────┘
```

## 📁 Repository Structure

```
.
├── infrastructure/
│   ├── bicep/
│   │   ├── guacamole-vm.bicep          # VM infrastructure template
│   │   └── front-door.bicep            # Azure Front Door template
│   └── parameters/
│       ├── parameters-uk.json          # UK region parameters
│       ├── parameters-canada.json      # Canada region parameters
│       └── parameters-frontdoor.json   # Front Door parameters
├── scripts/
│   └── install-guacamole.sh            # Automated Guacamole installation
├── docs/
│   └── DEPLOYMENT.md                   # Detailed deployment guide
└── README.md                           # This file
```

## 🚀 Quick Start

### Prerequisites

- Azure CLI installed and logged in (`az login`)
- SSH key pair for VM access
- Domain name with DNS access (Cloudflare recommended)
- Email address for Let's Encrypt certificates

### 1. Deploy Infrastructure

**UK Region:**
```bash
# Create resource group
az group create --name RG-UK-PAW-Core --location uksouth

# Deploy infrastructure
az deployment group create \
  --resource-group RG-UK-PAW-Core \
  --template-file infrastructure/bicep/guacamole-vm.bicep \
  --parameters @infrastructure/parameters/parameters-uk.json \
  --parameters sshPublicKey='<your-ssh-public-key>'
```

**Canada Region:**
```bash
# Create resource group
az group create --name RG-CA-PAW-Core --location canadacentral

# Deploy infrastructure
az deployment group create \
  --resource-group RG-CA-PAW-Core \
  --template-file infrastructure/bicep/guacamole-vm.bicep \
  --parameters @infrastructure/parameters/parameters-canada.json \
  --parameters sshPublicKey='<your-ssh-public-key>'
```

### 2. Configure DNS

Create A records pointing to the public IPs returned from deployments:
- `paw.yourdomain.com` → UK Public IP
- `paw-ca.yourdomain.com` → Canada Public IP

### 3. Install Guacamole

SSH to each VM and run the installation script:

```bash
# SSH to VM
ssh -i ~/.ssh/your-key.pem pawadmin@<public-ip>

# Download and run installation script
curl -o install-guacamole.sh https://raw.githubusercontent.com/yourusername/guacamole-infrastructure/main/scripts/install-guacamole.sh
chmod +x install-guacamole.sh

# Install with your domain and email
./install-guacamole.sh paw.yourdomain.com your-email@example.com
```

### 4. Deploy Azure Front Door

```bash
# Deploy Front Door
az deployment sub create \
  --location global \
  --template-file infrastructure/bicep/front-door.bicep \
  --parameters @infrastructure/parameters/parameters-frontdoor.json
```

### 5. Update DNS for Front Door

Update your main domain CNAME or A record to point to Front Door endpoint:
- `paw.yourdomain.com` → `<frontdoor-endpoint>.z03.azurefd.net`

## 🔐 Security Features

- **NSG Restrictions**:
  - SSH (port 22): Only from management IP
  - HTTP/HTTPS (80/443): Only from Azure Front Door Backend
  
- **Network Isolation**:
  - Separate VNets per region (172.18.x for UK, 172.19.x for Canada)
  - Non-overlapping IP ranges for future peering

- **SSL/TLS**:
  - Automatic Let's Encrypt certificates
  - TLS 1.2+ enforced
  - HTTPS redirect

- **SSH Key Authentication**:
  - No password authentication
  - Key-based access only

## 📊 Infrastructure Details

### VM Specifications
- **Size**: Standard_B2s (2 vCPUs, 4 GB RAM)
- **OS**: Ubuntu 22.04 LTS
- **Storage**: 30 GB Premium SSD
- **User**: pawadmin

### Network Configuration
- **UK VNet**: 172.18.0.0/16
  - Guacamole Subnet: 172.18.8.0/22 (1,022 IPs)
- **Canada VNet**: 172.19.0.0/16
  - Guacamole Subnet: 172.19.8.0/22 (1,022 IPs)

### Front Door Configuration
- **SKU**: Standard
- **Health Probe**: HTTP on / every 30 seconds
- **Load Balancing**: Latency-based routing
- **Session Affinity**: Disabled (stateless)

## 🔧 Maintenance

### Update Guacamole

```bash
cd ~/guacamole-docker-compose
docker compose pull
docker compose up -d
```

### Renew SSL Certificates

Certificates auto-renew via certbot container. Manual renewal:
```bash
docker compose run --rm certbot renew
docker compose restart nginx
```

### View Logs

```bash
docker compose logs -f guacamole
docker compose logs -f nginx
```

### Backup Database

```bash
docker exec postgres_guacamole pg_dump -U guacamole_user guacamole_db > backup.sql
```

## 📈 Cost Estimation (per month)

- **2x VMs (Standard_B2s)**: ~$60
- **2x Public IPs**: ~$8
- **2x 30GB Premium SSD**: ~$10
- **Azure Front Door (Standard)**: ~$35 + data transfer
- **Total**: ~$113 + data transfer costs

## 🌍 Adding New Regions

1. Copy `parameters-canada.json` to `parameters-<region>.json`
2. Update:
   - `location`: New Azure region
   - `regionCode`: Region identifier
   - `vnetAddressSpace`: New IP range (e.g., 172.20.0.0/16)
   - `subnetAddressPrefix`: New subnet range (e.g., 172.20.8.0/22)
3. Deploy infrastructure
4. Install Guacamole
5. Add origin to Front Door

## 📝 Default Credentials

**Guacamole:**
- Username: `guacadmin`
- Password: `guacadmin`

**⚠️ IMPORTANT: Change immediately after first login!**

## 🔗 Resources

- [Apache Guacamole Documentation](https://guacamole.apache.org/)
- [Azure Front Door Documentation](https://learn.microsoft.com/en-us/azure/frontdoor/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

## 🐛 Troubleshooting

### Cannot connect to Guacamole
1. Check NSG rules allow Front Door traffic
2. Verify DNS points to correct IP
3. Check nginx logs: `docker compose logs nginx`

### SSL certificate issues
1. Verify domain DNS is propagated
2. Check certbot logs: `docker compose logs certbot`
3. Ensure port 80 is accessible for ACME challenge

### Front Door health probe failing
1. Verify origin hostname resolves correctly
2. Check backend is responding on port 80
3. Ensure NSG allows Front Door service tag

## 📄 License

MIT License - See LICENSE file for details

## 👥 Contributing

Contributions welcome! Please open an issue or submit a pull request.

## 🆘 Support

For issues or questions:
1. Check the troubleshooting section
2. Review Azure resource logs
3. Check Guacamole container logs
