# Infrastructure Replication Checklist

Use this checklist to replicate the entire multi-region Guacamole infrastructure from scratch.

## ✅ Prerequisites

- [ ] Azure subscription with appropriate permissions
- [ ] Azure CLI installed (`az --version` shows 2.50.0+)
- [ ] SSH key pair generated (`~/.ssh/your-key.pub`)
- [ ] Two domains or subdomains available (e.g., `paw.domain.com`, `paw-ca.domain.com`)
- [ ] DNS provider access (to create A records)
- [ ] Email address for Let's Encrypt notifications
- [ ] Management IP address for SSH access

## 📥 Repository Setup

- [ ] Clone repository: `git clone https://github.com/hendizzo/guacamole-azure-multiregion.git`
- [ ] Switch to branch: `git checkout main`
- [ ] Review README.md for overview
- [ ] Review INFRASTRUCTURE.md for detailed architecture

## 🔧 Configuration

### Parameter Files

- [ ] Edit `infrastructure/parameters/parameters-uk.json`:
  - [ ] Set `sshSourceIp` to your management IP
  - [ ] Verify `location`, `regionCode`, `vnetAddressSpace`, `subnetAddressPrefix`
  - [ ] Set `adminUsername` and `sshPublicKey`

- [ ] Edit `infrastructure/parameters/parameters-canada.json`:
  - [ ] Set `sshSourceIp` to your management IP
  - [ ] Verify `location`, `regionCode`, `vnetAddressSpace`, `subnetAddressPrefix`
  - [ ] Set `adminUsername` and `sshPublicKey`

- [ ] Edit `infrastructure/parameters/parameters-main.json`:
  - [ ] Verify resource group names
  - [ ] Verify VM size (Standard_B2s recommended)

- [ ] Edit `infrastructure/parameters/parameters-frontdoor.json`:
  - [ ] Set `ukOriginHostname` (e.g., `paw.yourdomain.com`)
  - [ ] Set `canadaOriginHostname` (e.g., `paw-ca.yourdomain.com`)

### Domain Configuration

- [ ] Copy `.env.example` to `.env` (for reference only, not used by automation)
- [ ] Note your domains:
  - UK Region: `_________________`
  - Canada Region: `_________________`

## 🚀 Deployment

### Option 1: Automated Deployment (Recommended)

- [ ] Run: `./scripts/deploy-infrastructure.sh`
- [ ] Follow prompts:
  - [ ] Confirm Azure login
  - [ ] Select subscription
  - [ ] Verify parameters
- [ ] Wait for deployment to complete (~30-45 minutes)
- [ ] Review deployment log file
- [ ] Save Front Door endpoint hostname

### Option 2: Manual Deployment

- [ ] Login to Azure: `az login`
- [ ] Set subscription: `az account set --subscription "<ID>"`
- [ ] Deploy infrastructure: `az deployment sub create ...` (see INFRASTRUCTURE.md)
- [ ] Wait for deployment (~10 minutes)
- [ ] Note VM public IPs
- [ ] Configure DNS A records
- [ ] SSH to each VM and install Guacamole (see INFRASTRUCTURE.md)
- [ ] Deploy Front Door (see INFRASTRUCTURE.md)

## 🌐 DNS Configuration

- [ ] Create A record for UK: `paw.domain.com` → UK VM Public IP
- [ ] Create A record for Canada: `paw-ca.domain.com` → Canada VM Public IP
- [ ] Wait for DNS propagation (5-10 minutes)
- [ ] Verify with `dig paw.domain.com` and `dig paw-ca.domain.com`

### Optional: CNAME to Front Door (for geographic routing)

- [ ] Change A record to CNAME: `paw.domain.com` → Front Door endpoint
- [ ] Keep backend A records for health checks

## 🔐 Security Verification

- [ ] Test direct VM access (should timeout):
  ```bash
  curl -I https://paw.domain.com/guacamole/  # Should timeout
  curl -I https://paw-ca.domain.com/guacamole/  # Should timeout
  ```

- [ ] Test Front Door access (should work):
  ```bash
  curl -I https://<frontdoor-endpoint>/guacamole/  # Should return HTTP 200
  ```

- [ ] Verify NSG rules:
  - [ ] UK NSG allows SSH from management IP only
  - [ ] UK NSG allows HTTP/HTTPS from AzureFrontDoor.Backend only
  - [ ] Canada NSG allows SSH from management IP only
  - [ ] Canada NSG allows HTTP/HTTPS from AzureFrontDoor.Backend only

## 🎯 Post-Deployment Configuration

### Both Regions (UK and Canada)

For each region:

- [ ] Login to Guacamole: `https://<frontdoor-endpoint>/guacamole/`
  - Username: `guacadmin`
  - Password: `guacadmin`

- [ ] **IMMEDIATELY** change default password:
  - [ ] Click Settings (⚙️) → Preferences
  - [ ] Change password
  - [ ] Save

- [ ] Create admin user:
  - [ ] Settings (⚙️) → Users → New User
  - [ ] Set username and password
  - [ ] Grant "Administer system" permission
  - [ ] Save

- [ ] Logout and test new admin account

- [ ] Add connections (RDP/SSH/VNC):
  - [ ] Settings → Connections → New Connection
  - [ ] Configure protocol and target
  - [ ] Save

### Region-Specific Notes

**Important**: Each region has an **independent database**. User accounts and connections must be configured separately in each region.

## 📊 Verification

- [ ] Check VM status: `az vm list --output table`
- [ ] Check Front Door status: `az afd profile list`
- [ ] Check origin health:
  ```bash
  az afd origin show --profile-name guacamole-frontdoor \
    --resource-group RG-UK-PAW-Core \
    --origin-group-name guacamole-origins \
    --origin-name vm-uksouth
  ```

- [ ] Test routing from UK location
- [ ] Test routing from Canada location (if possible)

## 🔍 Troubleshooting

If issues occur, check:

- [ ] Docker containers running on VMs: `sudo docker ps`
- [ ] Nginx logs: `sudo docker logs nginx_guacamole_compose`
- [ ] Guacamole logs: `sudo docker logs guacamole_compose`
- [ ] Let's Encrypt certificates obtained: `sudo docker exec nginx_guacamole_compose ls -la /etc/letsencrypt/live/`
- [ ] NSG rules configured correctly: `az network nsg rule list`
- [ ] Front Door origins enabled: `az afd origin list`

## 📝 Documentation

- [ ] Document custom configuration changes
- [ ] Save VM credentials securely
- [ ] Save Front Door endpoint URL
- [ ] Document user accounts created
- [ ] Document RDP/SSH connections configured

## 🎉 Deployment Complete!

Your multi-region Guacamole infrastructure is now ready for production use.

### Key Information to Save

- **Front Door Endpoint**: `_________________________________`
- **UK VM Public IP**: `_________________________________`
- **Canada VM Public IP**: `_________________________________`
- **UK Domain**: `_________________________________`
- **Canada Domain**: `_________________________________`
- **Resource Groups**: 
  - UK: `RG-UK-PAW-Core`
  - Canada: `RG-CA-PAW-Core`
  - Front Door: `RG-UK-PAW-Core` (shared with UK)

### Next Steps

1. Configure backup strategy for PostgreSQL databases
2. Set up Azure Monitor alerts
3. Configure additional connections as needed
4. Test failover by stopping one VM
5. Review INFRASTRUCTURE.md for scaling to additional regions

## 🔄 Updates and Maintenance

- SSL certificates auto-renew every 90 days (managed by certbot)
- Monitor VM resources and scale as needed
- Regularly update Docker images
- Review NSG rules periodically
- Test backups regularly

---

For detailed information, see:
- [README.md](README.md) - Overview and quick start
- [INFRASTRUCTURE.md](INFRASTRUCTURE.md) - Detailed architecture and deployment
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) - Step-by-step deployment guide
