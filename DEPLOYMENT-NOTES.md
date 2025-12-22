# Guacamole Multi-Region Azure Deployment - Notes

## Deployment Summary
This infrastructure deploys Apache Guacamole across 3 Azure regions with Azure Front Door for global load balancing.

### Regions
- **UK South (uksouth)** - Primary region (GB)
- **East US (eastus)** - Secondary region (US-E)
- **East Asia (eastasia)** - Tertiary region (HK)

### Key Lessons Learned

#### 1. Docker Compose Command (Ubuntu 22.04+)
- **Issue**: Ubuntu 22.04 uses `docker compose` (with space) instead of `docker-compose`
- **Fix**: Updated all docker-compose commands to use `docker compose` in deploy-complete.ps1

#### 2. Front Door Profile Location
- **Issue**: Initial script created Front Door in non-existent RG-Global-PAW-Core
- **Fix**: Changed to create Front Door in first region's resource group (RG-GB-PAW-Core)
- **Note**: Front Door is a global service but profile must be in a valid resource group

#### 3. Front Door Endpoint Naming
- **Issue**: Endpoint name conflicts globally across Azure
- **Fix**: Use unique names (e.g., guacamole-global) and note the generated FQDN differs from endpoint name

#### 4. Custom Domain Configuration
- **Requires TWO DNS records**:
  1. **TXT Record**: `_dnsauth.<subdomain>` with validation token (for domain ownership)
  2. **CNAME Record**: `<subdomain>` pointing to Front Door endpoint FQDN
- **Validation Process**: TXT validation (2-10 min) → SSL cert provisioning (15-30 min)
- **Important**: Disable Cloudflare proxy (gray cloud) for CNAME during validation

#### 5. Front Door Components Required
All must exist and be properly linked:
- **Profile**: Top-level container
- **Endpoint**: Creates the *.azurefd.net URL
- **Origin Group**: Defines health probes and load balancing
- **Origins**: Backend servers (3 regions)
- **Route**: **CRITICAL** - connects endpoint → origin group → origins
- **Custom Domain**: Associated with route after validation

Without a route, origins show as "unassociated" and Front Door won't work.

#### 6. Health Probe Configuration
- **Protocol**: HTTPS (not HTTP)
- **Method**: HEAD or GET
- **Path**: `/guacamole/` (must match app path)
- **Interval**: 30 seconds recommended

#### 7. NSG Security Rules
- Origins should only allow traffic from `AzureFrontDoor.Backend` service tag
- This prevents direct internet access, forcing all traffic through Front Door
- Rule priority: 130 (allows before default deny rules)

#### 8. Routing Configuration
For latency-based routing (closest origin to client):
- Set all origins to **same priority** (e.g., Priority=1)
- Set equal or similar **weights** (e.g., Weight=100)
- Configure **additionalLatencyInMilliseconds** (50ms recommended)

This ensures:
- UK/Europe clients → UK South origin
- US/Americas clients → East US origin
- Asia/Pacific clients → East Asia origin

#### 9. Let's Encrypt SSL Certificates
- Regional FQDNs use Let's Encrypt certificates
- Certbot auto-renewal via cron (twice daily)
- Certificates stored in `/etc/letsencrypt/`
- Nginx configured for HTTPS on port 443

#### 10. Resource Deployment Order
Correct sequence prevents errors:
1. Resource Groups (per region)
2. VNets, Subnets, NSGs
3. Public IPs
4. VMs
5. Install scripts (Guacamole, Docker, Nginx, Let's Encrypt)
6. Front Door Profile
7. Front Door Endpoint
8. Front Door Origin Group
9. Front Door Origins
10. Front Door Route (connects everything)
11. Custom Domain (validate, then associate with route)

### Working URLs
After successful deployment:

- **Custom Domain**: https://lab.example.com/guacamole/ (your configured custom domain)
- **Front Door**: https://<endpoint-name>-<unique-id>.z03.azurefd.net/guacamole/
- **Primary Region**: https://paw.example.com/guacamole/
- **Secondary Regions**: https://paw-<region-code>.example.com/guacamole/

Replace `example.com` with your actual domain configured during deployment.

### Default Credentials
- **Username**: guacadmin
- **Password**: guacadmin (change immediately after first login)

### Deployment Script
Use `deploy-complete.ps1` for full automated deployment with all fixes applied.

### Cost Considerations
- 3x Standard_B2s VMs (~$60/month total)
- Azure Front Door Standard (~$35/month + data transfer)
- Bandwidth charges vary by usage
- Let's Encrypt certificates are free

**Total estimated cost**: ~$100-150/month depending on traffic

### Support
Repository: https://github.com/hendizzo/guacamole-azure-multiregion
