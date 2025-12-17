// Guacamole VM Infrastructure - Multi-Region Deployment
// This template creates all infrastructure needed for a Guacamole deployment

@description('Azure region for deployment')
param location string = 'uksouth'

@description('Region identifier for naming (e.g., uk, ca)')
param regionCode string = 'uk'

@description('VNet address space (e.g., 172.18.0.0/16 for UK, 172.19.0.0/16 for Canada)')
param vnetAddressSpace string = '172.18.0.0/16'

@description('Subnet address prefix (e.g., 172.18.8.0/22 for UK, 172.19.8.0/22 for Canada)')
param subnetAddressPrefix string = '172.18.8.0/22'

@description('VM size')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM')
param adminUsername string = 'pawadmin'

@description('SSH public key for authentication')
@secure()
param sshPublicKey string

@description('Source IP address allowed for SSH (your management IP)')
param sshSourceIp string

@description('Environment name')
param environment string = 'prd'

// Variables
var resourcePrefix = 'VM-${toUpper(regionCode)}-PAW'
var vmName = '${resourcePrefix}-Gateway'
var nicName = '${vmName}-nic'
var nsgName = '${vmName}-nsg'
var publicIpName = '${vmName}-ip'
var vnetName = 'VNET-${toUpper(regionCode)}-${location}'
var subnetName = 'guacamole'
var osDiskName = '${vmName}-osdisk'

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSHInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: sshSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Allow SSH from management IP'
        }
      }
      {
        name: 'AllowHTTPFromFrontDoor'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          description: 'Allow HTTP from Azure Front Door only'
        }
      }
      {
        name: 'AllowHTTPSFromFrontDoor'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Allow HTTPS from Azure Front Door only'
        }
      }
    ]
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Public IP
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Network Interface
resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Virtual Machine
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 30
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// Outputs
output vmName string = vm.name
output publicIpAddress string = publicIp.properties.ipAddress
output resourceGroupName string = resourceGroup().name
output location string = location
output nsgName string = nsg.name
output vnetName string = vnet.name
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
