#Requires -Version 5.1
<#
.SYNOPSIS
    Complete multi-region Guacamole deployment with Front Door
.DESCRIPTION
    This script deploys VMs, installs Guacamole via SSH, and configures Front Door
#>

param(
    [switch]$Resume
)

$ErrorActionPreference = "Stop"
$LogFile = "deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$StateFile = ".deployment-state.json"

function Write-Log {
    param($Message, $Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $logMessage
}

function Save-State {
    param($State)
    $State | ConvertTo-Json -Depth 10 | Set-Content $StateFile
}

function Load-State {
    if (Test-Path $StateFile) {
        return Get-Content $StateFile | ConvertFrom-Json
    }
    return @{
        step = 0
        regions = @()
        domain = $null
        email = $null
        sshKeyPath = $null
        myIP = $null
        frontdoorEndpoint = $null
    }
}

function Get-AzureRegions {
    return @(
        @{Name="UK South"; Code="uksouth"; Short="GB"; VNET="172.18.0.0/16"; Subnet="172.18.8.0/22"},
        @{Name="Canada Central"; Code="canadacentral"; Short="CA"; VNET="172.19.0.0/16"; Subnet="172.19.8.0/22"},
        @{Name="East US"; Code="eastus"; Short="US-E"; VNET="172.20.0.0/16"; Subnet="172.20.8.0/22"},
        @{Name="West US"; Code="westus"; Short="US-W"; VNET="172.21.0.0/16"; Subnet="172.21.8.0/22"},
        @{Name="West Europe"; Code="westeurope"; Short="NL"; VNET="172.22.0.0/16"; Subnet="172.22.8.0/22"},
        @{Name="East Asia"; Code="eastasia"; Short="HK"; VNET="172.23.0.0/16"; Subnet="172.23.8.0/22"},
        @{Name="Southeast Asia"; Code="southeastasia"; Short="SG"; VNET="172.24.0.0/16"; Subnet="172.24.8.0/22"},
        @{Name="Australia East"; Code="australiaeast"; Short="AU"; VNET="172.25.0.0/16"; Subnet="172.25.8.0/22"}
    )
}

# Load or initialize state
$state = Load-State

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Multi-Region Guacamole Deployment" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan
Write-Log "Log file: $LogFile"

# STEP 0: Prerequisites
if ($state.step -lt 1) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Step 0: Prerequisites & Configuration" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    # Check Azure login
    Write-Log "Checking Azure login..." Yellow
    $account = az account show 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Not logged in. Please run: az login" Red
        exit 1
    }
    Write-Log "Logged in as: $($account.user.name)" Green
    Write-Log "  Subscription: $($account.name)" Gray

    # Get public IP
    Write-Log "" White
    Write-Log "Getting your public IP..." Yellow
    $state.myIP = (Invoke-WebRequest -Uri 'https://api.ipify.org').Content.Trim()
    Write-Log "Your IP: $($state.myIP)" Green

    # Region Selection
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Region Selection" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
    
    $availableRegions = Get-AzureRegions
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Available Azure Regions:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $availableRegions.Count; $i++) {
        $region = $availableRegions[$i]
        Write-Host "  [$($i+1)] $($region.Name) ($($region.Code)) - Code: $($region.Short)" -ForegroundColor White
    }
    
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Select regions to deploy (comma or space-separated, e.g., 1,2 or 1 2):" -ForegroundColor Cyan
    Write-Host "Minimum: 2 regions required for Front Door" -ForegroundColor Gray
    $selection = Read-Host "Enter numbers"
    
    $selectedIndexes = $selection -split '[,\s]+' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_.Trim() - 1 }
    $state.regions = @()
    
    foreach ($idx in $selectedIndexes) {
        if ($idx -ge 0 -and $idx -lt $availableRegions.Count) {
            $region = $availableRegions[$idx]
            $state.regions += @{
                name = $region.Name
                code = $region.Code
                short = $region.Short
                vnetAddressSpace = $region.VNET
                subnetAddressPrefix = $region.Subnet
                publicIp = $null
                privateIp = $null
                resourceGroup = "RG-$($region.Short)-PAW-Core"
                vmName = "VM-$($region.Short)-PAW-Gateway"
                subdomain = if ($state.regions.Count -eq 0) { "paw" } else { "paw-$($region.Short.ToLower())" }
            }
        }
    }
    
    if ($state.regions.Count -lt 2) {
        Write-Log "At least 2 regions required for Front Door deployment" Red
        exit 1
    }
    
    Write-Host "" -ForegroundColor Green
    Write-Host "Selected Regions:" -ForegroundColor Green
    foreach ($region in $state.regions) {
        Write-Host "  * $($region.name) ($($region.short))" -ForegroundColor White
    }
    
    # Prompt for configuration
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Configuration" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    $state.domain = Read-Host "`nEnter your domain name (e.g., example.com)"
    $state.email = Read-Host "Enter your email for Let's Encrypt (e.g., admin@$($state.domain))"
    
    # Update subdomains with actual domain
    foreach ($region in $state.regions) {
        $region.fqdn = "$($region.subdomain).$($state.domain)"
    }

    # SSH Key
    $defaultKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
    if (-not (Test-Path "$defaultKeyPath.pub")) {
        Write-Log "" Yellow
        Write-Log "SSH key not found" Yellow
        $createKey = Read-Host "Generate SSH key now? (Y/n)"
        if ($createKey -ne 'n') {
            ssh-keygen -t rsa -b 4096 -f $defaultKeyPath -N '""'
        } else {
            Write-Log "SSH key required. Exiting." Red
            exit 1
        }
    }
    $state.sshKeyPath = $defaultKeyPath

    # Summary
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Deployment Configuration" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Regions:        $($state.regions.Count)" -ForegroundColor White
    foreach ($region in $state.regions) {
        Write-Host "  * $($region.name) - $($region.fqdn)" -ForegroundColor Gray
    }
    Write-Host "Email:          $($state.email)" -ForegroundColor White
    Write-Host "SSH Source:     $($state.myIP)" -ForegroundColor White
    Write-Host "SSH Key:        $($state.sshKeyPath)" -ForegroundColor White

    $confirm = Read-Host "`nProceed with deployment? (Y/n)"
    if ($confirm -eq 'n') {
        Write-Log "Deployment cancelled." Yellow
        exit 0
    }

    $state.step = 1
    Save-State $state
}

# STEP 1: Deploy Infrastructure
if ($state.step -lt 2) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Step 1: Deploying VM Infrastructure" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Log "Deploying $($state.regions.Count) regions (~10-15 minutes per region)..." Yellow

    $sshKey = Get-Content "$($state.sshKeyPath).pub" -Raw
    
    foreach ($region in $state.regions) {
        # Skip if already deployed
        if ($region.deployed) {
            Write-Log "$($region.name) ($($region.short)) already deployed - skipping" Green
            continue
        }
        
        Write-Log "" Cyan
        Write-Log "Deploying $($region.name) ($($region.short))..." Cyan
        
        # Create resource group
        Write-Host "  Creating resource group: $($region.resourceGroup)..." -ForegroundColor Gray
        az group create --name $region.resourceGroup --location $region.code --output json | Tee-Object -Append -FilePath $LogFile | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to create resource group $($region.resourceGroup)" Red
            exit 1
        }
        Write-Host "  Resource group created" -ForegroundColor Green
        
        # Deploy VM using Bicep template
        $deploymentName = "vm-$($region.short.ToLower())-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        Write-Host "  Deploying Bicep template: infrastructure/bicep/guacamole-vm.bicep" -ForegroundColor Gray
        Write-Host "  Deployment name: $deploymentName" -ForegroundColor Gray
        Write-Host "  This will take 5-10 minutes..." -ForegroundColor Yellow
        
        $deployResult = az deployment group create `
            --resource-group $region.resourceGroup `
            --template-file infrastructure/bicep/guacamole-vm.bicep `
            --parameters location="$($region.code)" `
            --parameters regionCode="$($region.short)" `
            --parameters vnetAddressSpace="$($region.vnetAddressSpace)" `
            --parameters subnetAddressPrefix="$($region.subnetAddressPrefix)" `
            --parameters sshPublicKey="$sshKey" `
            --parameters sshSourceIp="$($state.myIP)" `
            --parameters vmSize="Standard_B2s" `
            --parameters adminUsername="pawadmin" `
            --name $deploymentName 2>&1

        # Log the output
        $deployResult | Out-File -Append -FilePath $LogFile
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "" -ForegroundColor Red
            Write-Host "DEPLOYMENT FAILED for $($region.name)" -ForegroundColor Red
            Write-Host "Error details:" -ForegroundColor Yellow
            Write-Host $deployResult -ForegroundColor Red
            Write-Host "" -ForegroundColor Red
            Write-Host "Check full log: $LogFile" -ForegroundColor Yellow
            exit 1
        }

        # Get outputs
        Write-Host "  Retrieving deployment outputs..." -ForegroundColor Gray
        $deployment = az deployment group show --resource-group $region.resourceGroup --name $deploymentName | ConvertFrom-Json
        
        if (-not $deployment.properties.outputs) {
            Write-Log "Warning: No outputs found from deployment" Yellow
            continue
        }
        
        $region.publicIp = $deployment.properties.outputs.publicIpAddress.value
        $region.privateIp = $deployment.properties.outputs.privateIpAddress.value
        $region.deployed = $true
        
        Write-Log "$($region.name) deployed successfully!" Green
        Write-Log "  Public IP:  $($region.publicIp)" White
        Write-Log "  Private IP: $($region.privateIp)" Gray
        
        # Save state after each successful deployment
        Save-State $state
        Write-Host "" -ForegroundColor Gray
    }

    Write-Log "" Green
    Write-Log "All infrastructure deployed successfully!" Green

    $state.step = 2
    Save-State $state
}

# STEP 2: DNS Configuration
if ($state.step -lt 3) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Step 2: DNS Configuration Required" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    Write-Host "" -ForegroundColor Yellow
    Write-Host "ACTION REQUIRED: Configure DNS A records:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($region in $state.regions) {
        Write-Host "  $($region.subdomain).$($state.domain) -> $($region.publicIp)" -ForegroundColor White
    }

    Write-Host "" -ForegroundColor Cyan
    Write-Host "In your DNS provider (Cloudflare, etc):" -ForegroundColor Cyan
    $recordNum = 1
    foreach ($region in $state.regions) {
        Write-Host "  $recordNum. Add A record: $($region.subdomain) -> $($region.publicIp)" -ForegroundColor Gray
        $recordNum++
    }

    $dnsConfigured = Read-Host "`nHave you configured DNS? (Y/n)"
    if ($dnsConfigured -eq 'n') {
        Write-Log "Please configure DNS and run the script again with -Resume" Yellow
        exit 0
    }

    # Test DNS propagation
    Write-Log "" Yellow
    Write-Log "Testing DNS propagation..." Yellow
    $maxRetries = 10
    $retry = 0
    $allResolved = $false
    $resolvedRegions = @{}

    while ($retry -lt $maxRetries -and -not $allResolved) {
        $resolvedCount = 0
        
        foreach ($region in $state.regions) {
            if (-not $resolvedRegions[$region.short]) {
                try {
                    $dns = [System.Net.Dns]::GetHostAddresses($region.fqdn) | Select-Object -First 1
                    if ($dns.IPAddressToString -eq $region.publicIp) {
                        $resolvedRegions[$region.short] = $true
                        Write-Log "$($region.name) DNS resolved correctly ($($region.fqdn))" Green
                    }
                } catch {
                    Write-Log "  Waiting for $($region.name) DNS..." Gray
                }
            }
            if ($resolvedRegions[$region.short]) {
                $resolvedCount++
            }
        }
        
        if ($resolvedCount -eq $state.regions.Count) {
            $allResolved = $true
        } else {
            $retry++
            if ($retry -lt $maxRetries) {
                Write-Log "  Retry $retry/$maxRetries - $resolvedCount/$($state.regions.Count) resolved - waiting 30 seconds..." Yellow
                Start-Sleep -Seconds 30
            }
        }
    }

    if (-not $allResolved) {
        Write-Log "" Red
        Write-Log "DNS records are not fully propagated!" Red
        Write-Log "" Yellow
        Write-Log "You MUST configure these DNS A records before continuing:" Yellow
        Write-Log "" White
        foreach ($region in $state.regions) {
            if (-not $resolvedRegions[$region.short]) {
                Write-Log "  $($region.subdomain).$($state.domain) -> $($region.publicIp)" White
            }
        }
        Write-Log "" Yellow
        Write-Log "After configuring DNS, wait 5-10 minutes and run:" Yellow
        Write-Log "  .\deploy-complete.ps1" Cyan
        Write-Log "" Yellow
        exit 1
    }

    Write-Log "" Green
    Write-Log "All DNS records validated successfully!" Green

    $state.step = 3
    Save-State $state
}

# STEP 3: Install Guacamole on All VMs
if ($state.step -lt 4) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Step 3: Installing Guacamole on VMs" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    $regionNum = 1
    foreach ($region in $state.regions) {
        Write-Log "" Cyan
        Write-Log "[$regionNum/$($state.regions.Count)] Installing Guacamole on $($region.name)..." Cyan
        Write-Log "Connecting to: $($region.publicIp)..." Yellow
        
        # Create installation script with proper .env configuration
        $installScript = @"
#!/bin/bash
set -e
cd ~
git clone https://github.com/hendizzo/guacamole-azure-multiregion.git
cd guacamole-azure-multiregion
chmod +x scripts/install-guacamole.sh
./scripts/install-guacamole.sh $($region.fqdn) $($state.email)

# Create .env file with region-specific configuration
echo "DOMAIN=$($region.fqdn)" > .env
echo "CERTBOT_EMAIL=$($state.email)" >> .env
echo "POSTGRES_USER=guacamole_user" >> .env
echo "POSTGRES_PASSWORD=guacpass123" >> .env
echo "POSTGRES_DB=guacamole_db" >> .env
echo "GUACD_HOSTNAME=guacd" >> .env

# Update docker-compose to use environment variables
cd ~/guacamole-azure-multiregion
sed -i 's/your-email@example.com/\${CERTBOT_EMAIL}/' docker-compose.yml
sed -i 's/your-domain\.com/\${DOMAIN}/g' docker-compose.yml

# Restart containers to pick up new configuration
docker compose down
docker compose up -d

echo "Waiting for services to start..."
sleep 60
"@
        
        # Save with Unix line endings (LF only)
        $installScript -replace "`r`n", "`n" | Out-File -FilePath ".\install-temp-$($region.short).sh" -Encoding ASCII -NoNewline
        
        # Copy and execute (allow interactive passphrase entry)
        Write-Host "  Copying installation script..." -ForegroundColor Gray
        scp -i "$($state.sshKeyPath)" -o StrictHostKeyChecking=no ".\install-temp-$($region.short).sh" "pawadmin@$($region.publicIp):~/install.sh"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($region.name) SCP failed" Red
            exit 1
        }
        
        Write-Host "  Running installation script (this will take 10-15 minutes)..." -ForegroundColor Yellow
        ssh -i "$($state.sshKeyPath)" -o StrictHostKeyChecking=no "pawadmin@$($region.publicIp)" "chmod +x ~/install.sh && ~/install.sh"
        
        Remove-Item ".\install-temp-$($region.short).sh" -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$($region.name) installation failed. Check $LogFile" Red
            Write-Log "  You can retry this region manually or continue with -Resume" Yellow
            exit 1
        }
        
        Write-Log "$($region.name) installation complete!" Green
        $regionNum++
    }
    
    Write-Log "" Green
    Write-Log "All Guacamole installations complete!" Green
    
    $state.step = 4
    Save-State $state
}

# STEP 4: Verify Services
if ($state.step -lt 5) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Step 4: Verifying Guacamole Services" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    foreach ($region in $state.regions) {
        Write-Log "Testing $($region.name) endpoint..." Yellow
        try {
            $response = Invoke-WebRequest -Uri "https://$($region.fqdn)/guacamole/" -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                Write-Log "$($region.name) Guacamole responding (HTTP 200)" Green
                $region.verified = $true
            }
        } catch {
            Write-Log "$($region.name) endpoint not responding yet: $($_.Exception.Message)" Yellow
            $region.verified = $false
        }
    }
    
    $verifiedCount = ($state.regions | Where-Object { $_.verified }).Count
    Write-Log "" $(if($verifiedCount -eq $state.regions.Count){'Green'}else{'Yellow'})
    Write-Log "$verifiedCount/$($state.regions.Count) regions verified and responding" $(if($verifiedCount -eq $state.regions.Count){'Green'}else{'Yellow'})

    $state.step = 5
    Save-State $state
}

# STEP 5: Deploy Front Door
if ($state.step -lt 6) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Step 5: Deploying Azure Front Door" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    # Use first region's resource group for Front Door
    $frontdoorRG = $state.regions[0].resourceGroup
    Write-Log "Creating Front Door in resource group: $frontdoorRG" Yellow
    Write-Log "Creating Front Door with $($state.regions.Count) origins (5-10 minutes)..." Yellow
    
    # Create Front Door profile
    Write-Log "  Creating Front Door profile..." Gray
    az afd profile create `
        --profile-name guacamole-frontdoor `
        --resource-group $frontdoorRG `
        --sku Standard_AzureFrontDoor | Out-File -Append $LogFile
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create Front Door profile" Red
        exit 1
    }
    
    # Create endpoint
    Write-Log "  Creating endpoint 'guacamole-global'..." Gray
    az afd endpoint create `
        --resource-group $frontdoorRG `
        --profile-name guacamole-frontdoor `
        --endpoint-name guacamole-global `
        --enabled-state Enabled | Out-File -Append $LogFile
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create endpoint" Red
        exit 1
    }
    
    # Create origin group with health probe for Guacamole
    Write-Log "  Creating origin group with health probes..." Gray
    az afd origin-group create `
        --resource-group $frontdoorRG `
        --profile-name guacamole-frontdoor `
        --origin-group-name guacamole-origins `
        --probe-request-type GET `
        --probe-protocol Https `
        --probe-interval-in-seconds 30 `
        --probe-path "/guacamole/" `
        --sample-size 4 `
        --successful-samples-required 3 `
        --additional-latency-in-milliseconds 50 | Out-File -Append $LogFile
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create origin group" Red
        exit 1
    }
    
    # Add origins
    foreach ($region in $state.regions) {
        Write-Log "  Adding origin: $($region.name) ($($region.fqdn))" Cyan
        az afd origin create `
            --resource-group $frontdoorRG `
            --profile-name guacamole-frontdoor `
            --origin-group-name guacamole-origins `
            --origin-name "$($region.short.ToLower())-origin" `
            --host-name $region.fqdn `
            --origin-host-header $region.fqdn `
            --priority 1 `
            --weight 33 `
            --enabled-state Enabled `
            --http-port 80 `
            --https-port 443 | Out-File -Append $LogFile
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to add origin for $($region.name)" Red
            exit 1
        }
    }
    
    # Create route
    Write-Log "  Creating route..." Gray
    az afd route create `
        --resource-group $frontdoorRG `
        --profile-name guacamole-frontdoor `
        --endpoint-name guacamole-global `
        --route-name guacamole-route `
        --origin-group guacamole-origins `
        --supported-protocols Https Http `
        --link-to-default-domain Enabled `
        --https-redirect Enabled `
        --forwarding-protocol HttpsOnly `
        --patterns-to-match "/*" | Out-File -Append $LogFile

    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create route" Red
        exit 1
    }

    # Get Front Door endpoint
    $fdEndpoint = az afd endpoint list --profile-name guacamole-frontdoor --resource-group $frontdoorRG --query "[0].hostName" -o tsv
    $state.frontdoorEndpoint = $fdEndpoint

    Write-Log "" Green
    Write-Log "Front Door deployed successfully!" Green
    Write-Log "  Endpoint: https://$fdEndpoint/guacamole/" White
    Write-Log "  Origins: $($state.regions.Count)" White
    
    # Prompt for custom domain
    Write-Host "" -ForegroundColor Cyan
    Write-Host "Optional: Configure Custom Domain" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    $addCustomDomain = Read-Host "Do you want to add a custom domain to Front Door? (y/N)"
    
    if ($addCustomDomain -eq 'y') {
        $customDomain = Read-Host "Enter custom domain (e.g., lab.$($state.domain))"
        
        Write-Host "" -ForegroundColor Yellow
        Write-Host "IMPORTANT: Before continuing, add a DNS CNAME record:" -ForegroundColor Yellow
        Write-Host "  Name:   $customDomain" -ForegroundColor White
        Write-Host "  Type:   CNAME" -ForegroundColor White
        Write-Host "  Target: $fdEndpoint" -ForegroundColor White
        Write-Host "  Note:   If using Cloudflare, disable proxy (gray cloud)" -ForegroundColor Gray
        Write-Host "" -ForegroundColor Yellow
        $dnsConfirm = Read-Host "Have you added the CNAME record? (Y/n)"
        
        if ($dnsConfirm -ne 'n') {
            Write-Log "Adding custom domain to Front Door..." Yellow
            
            $customDomainName = $customDomain -replace '\.','-'
            
            az afd custom-domain create `
                --resource-group $frontdoorRG `
                --profile-name guacamole-frontdoor `
                --custom-domain-name $customDomainName `
                --host-name $customDomain `
                --minimum-tls-version TLS12 `
                --certificate-type ManagedCertificate | Out-File -Append $LogFile
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Custom domain added successfully" Green
                
                # Associate with route
                Write-Log "Associating custom domain with route..." Yellow
                az afd route update `
                    --resource-group $frontdoorRG `
                    --profile-name guacamole-frontdoor `
                    --endpoint-name guacamole-global `
                    --route-name guacamole-route `
                    --custom-domains $customDomainName | Out-File -Append $LogFile
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Custom domain associated with route" Green
                    Write-Log "" Yellow
                    Write-Log "SSL certificate provisioning takes 15-30 minutes" Yellow
                    Write-Log "  Custom domain URL: https://$customDomain/guacamole/" White
                    $state.customDomain = $customDomain
                } else {
                    Write-Log "Failed to associate custom domain with route" Red
                }
            } else {
                Write-Log "Failed to add custom domain" Red
                Write-Log "You can add it manually in Azure Portal later" Yellow
            }
        }
    }

    $state.step = 6
    Save-State $state
}

# FINAL: Success
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

Write-Host "" -ForegroundColor Cyan
Write-Host "Access URLs:" -ForegroundColor Cyan
Write-Host "  Front Door (Global): https://$($state.frontdoorEndpoint)/guacamole/" -ForegroundColor Green

if ($state.customDomain) {
    Write-Host "  Custom Domain:       https://$($state.customDomain)/guacamole/" -ForegroundColor Green
    Write-Host "                       (SSL cert provisioning: 15-30 minutes)" -ForegroundColor Yellow
}

Write-Host "" -ForegroundColor White
Write-Host "  Direct Regional Access:" -ForegroundColor White
foreach ($region in $state.regions) {
    Write-Host "    * $($region.name): https://$($region.fqdn)/guacamole/" -ForegroundColor Gray
}

Write-Host "" -ForegroundColor Cyan
Write-Host "Deployment Summary:" -ForegroundColor Cyan
Write-Host "  Total Regions:  $($state.regions.Count)" -ForegroundColor White
Write-Host "  Resource Groups: $($state.regions.Count)" -ForegroundColor White
Write-Host "  Virtual Machines: $($state.regions.Count)" -ForegroundColor White
Write-Host "  Front Door Origins: $($state.regions.Count)" -ForegroundColor White
Write-Host "  Front Door Profile: guacamole-frontdoor (in $($state.regions[0].resourceGroup))" -ForegroundColor White

Write-Host "" -ForegroundColor Cyan
Write-Host "Default Login:" -ForegroundColor Cyan
Write-Host "  Username: guacadmin" -ForegroundColor White
Write-Host "  Password: guacadmin" -ForegroundColor White
Write-Host "  CHANGE PASSWORD IMMEDIATELY!" -ForegroundColor Yellow

Write-Host "" -ForegroundColor Cyan
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Login and change default password" -ForegroundColor White
Write-Host "  2. Create admin user" -ForegroundColor White
Write-Host "  3. Configure connections (RDP/SSH/VNC)" -ForegroundColor White
Write-Host "  4. Optional: Update DNS to CNAME Front Door for geographic routing" -ForegroundColor White

Write-Host "" -ForegroundColor Cyan
Write-Host "Deployed Regions:" -ForegroundColor Cyan
foreach ($region in $state.regions) {
    Write-Host "  * $($region.name) ($($region.short)) - $($region.fqdn)" -ForegroundColor Green
}

Write-Host "" -ForegroundColor Gray
Write-Host "Log file: $LogFile" -ForegroundColor Gray
Write-Host ""

# Clean up state file
Remove-Item $StateFile -ErrorAction SilentlyContinue
