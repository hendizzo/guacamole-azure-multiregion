targetScope = 'subscription'

@description('Array of regions to deploy to')
param regions array

@description('Base domain name (e.g., example.com)')
param domain string

@description('Email for Let\'s Encrypt certificates')
param certbotEmail string

@description('SSH public key for admin user')
param adminPublicKey string

@description('Source IP address for SSH access')
param allowedSourceIP string

@description('Admin username for VMs')
param adminUsername string = 'pawadmin'

@description('VM size')
param vmSize string = 'Standard_B2s'

// Create resource groups for each region
resource resourceGroups 'Microsoft.Resources/resourceGroups@2021-04-01' = [for (region, i) in regions: {
  name: 'RG-${region.shortName}-PAW-Core'
  location: region.location
  tags: {
    Environment: 'Production'
    Application: 'Guacamole'
    ManagedBy: 'Bicep'
  }
}]

// Deploy regional infrastructure
module regionalDeployments 'modules/region.bicep' = [for (region, i) in regions: {
  name: 'regional-deployment-${region.shortName}'
  scope: resourceGroups[i]
  params: {
    location: region.location
    shortName: region.shortName
    subdomain: region.subdomain
    domain: domain
    certbotEmail: certbotEmail
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    allowedSourceIP: allowedSourceIP
    vmSize: vmSize
    vnetAddressPrefix: '172.${18 + i}.0.0/16'
    subnetAddressPrefix: '172.${18 + i}.8.0/22'
  }
}]

// Deploy Front Door (in first region's resource group)
module frontDoor 'modules/frontdoor.bicep' = {
  name: 'frontdoor-deployment'
  scope: resourceGroups[0]
  params: {
    origins: [for (region, i) in regions: {
      name: '${toLower(region.shortName)}-origin'
      hostName: '${region.subdomain}.${domain}'
      priority: 1
      weight: 100
    }]
  }
  dependsOn: regionalDeployments
}

// Outputs
output frontDoorEndpoint string = frontDoor.outputs.frontDoorEndpoint
output resourceGroups array = [for (region, i) in regions: {
  name: resourceGroups[i].name
  location: resourceGroups[i].location
}]
output vmPublicIPs array = [for (region, i) in regions: {
  region: region.shortName
  subdomain: region.subdomain
  publicIP: regionalDeployments[i].outputs.vmPublicIP
}]
