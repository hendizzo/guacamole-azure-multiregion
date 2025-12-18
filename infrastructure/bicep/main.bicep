// Main orchestration template for multi-region Guacamole deployment
// This deploys the complete infrastructure in the correct order

targetScope = 'subscription'

@description('Deployment regions')
param regions array = [
  {
    name: 'uksouth'
    code: 'uk'
    vnetAddressSpace: '172.18.0.0/16'
    subnetAddressPrefix: '172.18.8.0/22'
  }
  {
    name: 'canadacentral'
    code: 'ca'
    vnetAddressSpace: '172.19.0.0/16'
    subnetAddressPrefix: '172.19.8.0/22'
  }
]

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('Source IP address allowed for SSH')
param sshSourceIp string

@description('Admin username for VMs')
param adminUsername string = 'pawadmin'

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('Environment name')
param environment string = 'prd'

@description('Custom domain for Front Door (e.g., paw.example.com)')
param customDomain string

@description('UK origin hostname (must be DNS resolvable)')
param ukOriginHostname string

@description('Canada origin hostname (must be DNS resolvable)')
param canadaOriginHostname string

@description('Front Door name')
param frontDoorName string = 'guacamole-frontdoor'

// Deploy resource groups for each region
resource ukResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'RG-${toUpper(regions[0].code)}-PAW-Core'
  location: regions[0].name
}

resource canadaResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'RG-${toUpper(regions[1].code)}-PAW-Core'
  location: regions[1].name
}

resource frontDoorResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'RG-Global-PAW-Core'
  location: regions[0].name // Front Door is global, but RG needs a location
}

// Deploy UK VM infrastructure
module ukVm './guacamole-vm.bicep' = {
  scope: ukResourceGroup
  name: 'uk-vm-deployment'
  params: {
    location: regions[0].name
    regionCode: regions[0].code
    vnetAddressSpace: regions[0].vnetAddressSpace
    subnetAddressPrefix: regions[0].subnetAddressPrefix
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    sshSourceIp: sshSourceIp
    environment: environment
  }
}

// Deploy Canada VM infrastructure
module canadaVm './guacamole-vm.bicep' = {
  scope: canadaResourceGroup
  name: 'canada-vm-deployment'
  params: {
    location: regions[1].name
    regionCode: regions[1].code
    vnetAddressSpace: regions[1].vnetAddressSpace
    subnetAddressPrefix: regions[1].subnetAddressPrefix
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    sshSourceIp: sshSourceIp
    environment: environment
  }
}

// Note: Front Door deployment is separated because it requires:
// 1. VMs to be deployed and running
// 2. DNS A records configured (paw.domain.com -> UK IP, paw-ca.domain.com -> CA IP)
// 3. Guacamole installed and responding on those domains
// Deploy Front Door separately after above requirements are met using front-door.bicep

// Outputs
output ukPublicIp string = ukVm.outputs.publicIpAddress
output ukPrivateIp string = ukVm.outputs.privateIpAddress
output ukVmName string = ukVm.outputs.vmName
output ukResourceGroup string = ukResourceGroup.name

output canadaPublicIp string = canadaVm.outputs.publicIpAddress
output canadaPrivateIp string = canadaVm.outputs.privateIpAddress
output canadaVmName string = canadaVm.outputs.vmName
output canadaResourceGroup string = canadaResourceGroup.name

output nextSteps string = '''
DEPLOYMENT SUCCESSFUL! Next steps:

1. Configure DNS:
   - Create A record: ${ukOriginHostname} -> ${ukVm.outputs.publicIpAddress}
   - Create A record: ${canadaOriginHostname} -> ${canadaVm.outputs.publicIpAddress}
   - Wait for DNS propagation (verify with: dig ${ukOriginHostname} +short)

2. Install Guacamole on UK VM:
   ssh -i ~/.ssh/your-key ${adminUsername}@${ukVm.outputs.publicIpAddress}
   git clone https://github.com/hendizzo/guacamole-azure-multiregion.git
   cd guacamole-azure-multiregion && git checkout Multi-Region_With_FrontDoor
   ./scripts/install-guacamole.sh ${ukOriginHostname} your-email@example.com

3. Install Guacamole on Canada VM:
   ssh -i ~/.ssh/your-key ${adminUsername}@${canadaVm.outputs.publicIpAddress}
   git clone https://github.com/hendizzo/guacamole-azure-multiregion.git
   cd guacamole-azure-multiregion && git checkout Multi-Region_With_FrontDoor
   ./scripts/install-guacamole.sh ${canadaOriginHostname} your-email@example.com

4. Verify both sites respond:
   curl -I https://${ukOriginHostname}/guacamole/
   curl -I https://${canadaOriginHostname}/guacamole/

5. Deploy Front Door:
   az deployment group create \\
     --resource-group RG-Global-PAW-Core \\
     --template-file infrastructure/bicep/front-door.bicep \\
     --parameters @infrastructure/parameters/parameters-frontdoor.json

6. Update DNS to point to Front Door:
   - Change ${customDomain} to CNAME -> Front Door endpoint
'''
