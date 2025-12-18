#!/usr/bin/env pwsh
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

Write-Host "`n=========================================="
Write-Host "Multi-Region Guacamole Deployment (Complete)"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Log "Log file: $LogFile"

# STEP 0: Prerequisites
if ($state.step -lt 1) {
    Write-Host "`n=========================================="
    Write-Host "Step 0: Prerequisites & Configuration"
    Write-Host "==========================================" -ForegroundColor Cyan

    # Check Azure login
    Write-Log "Checking Azure login..." Yellow
    $account = az account show 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Log "✗ Not logged in. Please run: az login" Red
        exit 1
    }
    Write-Log "✓ Logged in as: $($account.user.name)" Green
    Write-Log "  Subscription: $($account.name)" Gray

    # Get public IP
    Write-Log "`nGetting your public IP..." Yellow
    $state.myIP = (Invoke-WebRequest -Uri 'https://api.ipify.org').Content.Trim()
    Write-Log "✓ Your IP: $($state.myIP)" Green

    # Region Selection
    Write-Host "`n=========================================="
    Write-Host "Region Selection"
    Write-Host "==========================================" -ForegroundColor Cyan
    
    $availableRegions = Get-AzureRegions
    Write-Host "`nAvailable Azure Regions:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $availableRegions.Count; $i++) {
        $region = $availableRegions[$i]
        Write-Host "  [$($i+1)] $($region.Name) ($($region.Code)) - Code: $($region.Short)" -ForegroundColor White
    }
    
    Write-Host "`nSelect regions to deploy (comma-separated numbers, e.g., 1,2):" -ForegroundColor Cyan
    Write-Host "Minimum: 2 regions required for Front Door" -ForegroundColor Gray
    $selection = Read-Host "Enter numbers"
    
    $selectedIndexes = $selection -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
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
        Write-Log "✗ At least 2 regions required for Front Door deployment" Red
        exit 1
    }
    
    Write-Host "`n✓ Selected Regions:" -ForegroundColor Green
    foreach ($region in $state.regions) {
        Write-Host "  • $($region.name) ($($region.short)) - $($region.subdomain).$($state.domain)" -ForegroundColor White
    }
    
    # Prompt for configuration
    Write-Host "`n=========================================="
    Write-Host "Configuration"
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
        Write-Log "`n⚠️  SSH key not found" Yellow
        $createKey = Read-Host "Generate SSH key now? (Y/n)"
        if ($createKey -ne 'n') {
            ssh-keygen -t rsa -b 4096 -f $defaultKeyPath -N '""'
        } else {
            Write-Log "✗ SSH key required. Exiting." Red
            exit 1
        }
    }
    $state.sshKeyPath = $defaultKeyPath

    # Summary
    Write-Host "`n=========================================="
    Write-Host "Deployment Configuration"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Regions:        $($state.regions.Count)" -ForegroundColor White
    foreach ($region in $state.regions) {
        Write-Host "  • $($region.name) - $($region.fqdn)" -ForegroundColor Gray
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
    Write-Host "`n=========================================="
    Write-Host Deploying $($state.regions.Count) regions (~10-15 minutes per region)..." Yellow

    $sshKey = Get-Content "$($state.sshKeyPath).pub" -Raw
    
    foreach ($region in $state.regions) {
        Write-Log "`nDeploying $($region.name) ($($region.short))..." Cyan
        
        # Create resource group
        az group create --name $region.resourceGroup --location $region.code | Out-File -Append $LogFile
        
        # Deploy VM
        $deploymentName = "vm-$($region.short.ToLower())-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        az deployment group create `
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
            --name $deploymentName | Out-File -Append $LogFile

        if ($LASTEXITCODE -ne 0) {
            Write-Log "✗ $($region.name) deployment failed. Check $LogFile" Red
            exit 1
        }

        # Get outputs
        $deployment = az deployment group show --resource-group $region.resourceGroup --name $deploymentName | ConvertFrom-Json
        $region.publicIp = $deployment.properties.outputs.publicIpAddress.value
        $region.privateIp = $deployment.properties.outputs.privateIpAddress.value
        
        Write-Log "✓ $($region.name) deployed" Green
        Write-Log "  Public IP:  $($region.publicIp)" White
        Write-Log "  Private IP: $($region.privateIp)" Gray
    }

    Write-Log "`n✓ All infrastructure deployed successfully!" Green
    Write-Log "  UK Public IP:     $($state.ukPublicIp)" White
    Write-Log " "
    foreach ($region in $state.regions) {
        Write-Host "  $($region.subdomain).$($state.domain) → $($region.publicIp)" -ForegroundColor White
    }

    Write-Host "`nIn your DNS provider (e.g., Cloudflare):" -ForegroundColor Cyan
    $recordNum = 1
    foreach ($region in $state.regions) {
        Write-Host "  $recordNum. Add A record: $($region.subdomain) → $($region.publicIp)" -ForegroundColor Gray
        $recordNum++
    }

    $dnsConfigured = Read-Host "`nHave you configured DNS? (Y/n)"
    if ($dnsConfigured -eq 'n') {
        Write-Log "Please configure DNS and run the script again with -Resume" Yellow
        exit 0
    }

    # Test DNS propagation
    Write-Log "`nTesting DNS propagation..." Yellow
    $maxRetries = 10
    $retry = 0
    $allResolved = $false

    while ($retry -lt $maxRetries -and -not $allResolved) {
        $resolvedCount = 0
        
        foreach ($region in $state.regions) {
            if (-not $region.dnsResolved) {
                try {
                    $dns = [System.Net.Dns]::GetHostAddresses($region.fqdn) | Select-Object -First 1
                    if ($dns.IPAddressToString -eq $region.publicIp) {
                        $region.dnsResolved = $true
                        Write-Log "✓ $($region.name) DNS resolved correctly ($($region.fqdn))" Green
                    }
                } catch {
                    Write-Log "  Waiting for $($region.name) DNS..." Gray
                }
            }
            if ($region.dnsResolved) {
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
        Write-Log "`n⚠️  DNS not fully propagated yet ($resolvedCount/$($state.regions.Count) resolved)ray
        }

        if (-not $ukResolved -or -not $caResolved) {
            $retry++
            if ($retry -lt $maxRetries) {
                Write-Log "  Retry $retry/$maxRetries - waiting 30 seconds..." Yellow
                Start-Sleep -Seconds 30
            }
        }
    }

    if (-not $ukResolved -or -not $caResolved) {
        Write-Log "`n⚠️  DNS not fully propagated yet. You can:" Yellow
        Write-Log "  1. Wait longer and run: .\deploy-complete.ps1 -Resume" White
        Write-Log "  2. Continue anyway (may cause issues)" White
        $continue = Read-Host "`nContinue anyway? (y/N)"
        if ($continue -ne 'y') {
            exit 0
        }
    }
All VMs
if ($state.step -lt 4) {
    Write-Host "`n=========================================="
    Write-Host "Step 3: Installing Guacamole on VMs"
    Write-Host "==========================================" -ForegroundColor Cyan

    $regionNum = 1
    foreach ($region in $state.regions) {
        Write-Log "`n[$regionNum/$($state.regions.Count)] Installing Guacamole on $($region.name)..." Cyan
        Write-Log "Connecting to: $($region.publicIp)..." Yellow
        
        # Create installation script
        $installScript = @"
#!/bin/bash
set -e
cd ~
git clone https://github.com/hendizzo/guacamole-azure-multiregion.git
cd guacamole-azure-multiregion
chmod +x scripts/install-guacamole.sh
./scripts/install-guacamole.sh $($region.fqdn) $($state.email)
"@
        
        $installScript | Out-File -FilePath ".\install-temp-$($region.short).sh" -Encoding ASCII -NoNewline
        
        # Copy and execute
        scp -i "$($state.sshKeyPath)" -o StrictHostKeyChecking=no ".\install-temp-$($region.short).sh" "pawadmin@$($region.publicIp):~/install.sh" 2>&1 | Out-File -Append $LogFile
        ssh -i "$($state.sshKeyPath)" -o StrictHostKeyChecking=no "pawadmin@$($region.publicIp)" "chmod +x ~/install.sh && ~/install.sh" 2>&1 | Out-File -Append $LogFile
        
        Remove-Item ".\install-temp-$($region.short).sh" -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "✗ $($region.name) installation failed. Check $LogFile" Red
            Write-Log "  You can retry this region manually or continue with -Resume" Yellow
            exit 1
        }
        
        Write-Log "✓ $($region.name) installation complete!" Green
        $regionNum++
    }
    
    Write-Log "`n✓ All Guacamole installations complete!" Green
    
    $state.step = 4
    }
    
    Write-Log "✓ Canada VM installation complete!" Green
    
    $state.step = 5
    Save-State $state
}

# STEP 5: Verify Services
if ($state.step -lt 6) {
    Write-Host "`n=========================================="
    Write-Host "Step 5: Verifying Guacamole Services"
    Write-Host "==========================================" -ForegroundColor Cyan

    Write-Log "Testing UK endpoint..." Yellow
    try {
        $ukResponse = Invoke-WebRequest -Uri "https://paw.$($state.domain)/guacamole/" -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10
        if ($ukResponse.StatusCode -eq 200) {
            Write-Log "✓ UK Guacamole responding (HTTP 200)" Green
        }
    } catch {
        Write-Log "⚠️  UK endpoint not responding yet: $($_.Exception.Message)" Yellow
    }

    Write-Log "Testing Canada endpoint..." Yellow
    try {
        $caResponse = Invoke-WebRequest -Uri "https://paw-ca.$($state.domain)/guacamole/" -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10
        if ($caResponse.StatusCode -eq 200) {
            Write-Log "✓ Canada Guacamole responding (HTTP 200)" Green
        }
    } catch {
        Write-Log "⚠️  Canada endpoint not responding yet: $($_.Exception.Message)" Yellow
    }

    $state.step = 6
    Save-State $state
}4: Verify Services
if ($state.step -lt 5) {
    Write-Host "`n=========================================="
    Write-Host "Step 4: Verifying Guacamole Services"
    Write-Host "==========================================" -ForegroundColor Cyan

    foreach ($region in $state.regions) {
        Write-Log "Testing $($region.name) endpoint..." Yellow
        try {
            $response = Invoke-WebRequest -Uri "https://$($region.fqdn)/guacamole/" -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                Write-Log "✓ $($region.name) Guacamole responding (HTTP 200)" Green
                $region.verified = $true
            }
        } catch {
            Write-Log "⚠️  $($region.name) endpoint not responding yet: $($_.Exception.Message)" Yellow
            $region.verified = $false
        }
    }
    
    $verifiedCount = ($state.regions | Where-Object { $_.verified }).Count
    Write-Log "`n$verifiedCount/$($state.regions.Count) regions verified and responding" $(if($verifiedCount -eq $state.regions.Count){'Green'}else{'Yellow'})

    $state.step = 5z afd endpoint list --profile-name guacamole-frontdoor --resource-group RG-Global-PAW-Core --query "[0].hostName" -o tsv
    $state.frontdoorEndpoint = $fdEndpoint

    Write-Log "`n✓ Front Door deployed successfully!" Green
    Write-Log "  Endpoint: $fdEndpoint" White

    $state.step = 7
    Save-State $state
}

# FINAL: Success
Write-Host "`n=========================================="
Write-Host "✓ DEPLOYMENT COMPLETE!"
Write-Host "==========================================" -ForegroundColor Green

Write-Host "`n🌐 Access URLs:" -ForegroundColor Cyan
Write-Host "  Front Door (Global): https://$($state.frontdoorEndpoint)/guacamole/" -ForegroundColor Green
Write-Host "`n  Direct Access:" -ForegroundColor White
foreach ($region in $state.regions) {
    Write-Host "    • $($region.name): https://$($region.fqdn)/guacamole/" -ForegroundColor Gray
}

Write-Host "`n📊 Deployment Summary:" -ForegroundColor Cyan
Write-Host "  Total Regions:  $($state.regions.Count)" -ForegroundColor White
Write-Host "  Resource Groups: $($state.regions.Count + 1) (regions + Front Door)" -ForegroundColor White
Write-Host "  Virtual Machines: $($state.regions.Count)" -ForegroundColor White
Write-Host "  Front Door Origins: $($state.regions.Count)" -ForegroundColor White

Write-Host "`n🔐 Default Login:" -ForegroundColor Cyan
Write-Host "  Username: guacadmin" -ForegroundColor White
Write-Host "  Password: guacadmin" -ForegroundColor White
Write-Host "  ⚠️  CHANGE PASSWORD IMMEDIATELY!" -ForegroundColor Yellow

Write-Host "`n📋 Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Login and change default password" -ForegroundColor White
Write-Host "  2. Create admin user" -ForegroundColor White
Write-Host "  3. Configure connections (RDP/SSH/VNC)" -ForegroundColor White
Write-Host "  4. Optional: Update DNS to CNAME Front Door for geographic routing" -ForegroundColor White

Write-Host "`n🌍 Deployed Regions:" -ForegroundColor Cyan
foreach ($region in $state.regions) {
    Write-Host "  ✓ $($region.name) ($($region.short)) - $($region.fqdn)" -ForegroundColor Green
}

Write-Host "`n📄 Log file: $LogFile" -ForegroundColor Gray
Write-Host ""

# Clean up state file
Remove-Item $StateFile -ErrorAction SilentlyContinue
