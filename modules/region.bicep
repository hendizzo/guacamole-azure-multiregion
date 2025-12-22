@description('Azure region')
param location string

@description('Short name for the region (e.g., GB, US-E)')
param shortName string

@description('Subdomain for this region (e.g., paw, paw-us-e)')
param subdomain string

@description('Base domain name')
param domain string

@description('Email for Let\'s Encrypt')
param certbotEmail string

@description('Admin username')
param adminUsername string

@description('SSH public key')
param adminPublicKey string

@description('Allowed source IP for SSH')
param allowedSourceIP string

@description('VM size')
param vmSize string

@description('Virtual network address prefix')
param vnetAddressPrefix string

@description('Subnet address prefix')
param subnetAddressPrefix string

// Variables
var vmName = 'VM-${shortName}-PAW-Gateway'
var nicName = '${vmName}-nic'
var publicIPName = '${vmName}-pip'
var nsgName = '${vmName}-nsg'
var vnetName = 'VNet-${shortName}-PAW'
var subnetName = 'Subnet-${shortName}-PAW'
var fqdn = '${subdomain}.${domain}'

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSHFromMyIP'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSourceIP
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowHTTPSFromFrontDoor'
        properties: {
          priority: 130
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
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
        vnetAddressPrefix
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
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIPName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id)}')
    }
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
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
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
              keyData: adminPublicKey
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
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
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

// Custom Script Extension to install Guacamole
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vm
  name: 'InstallGuacamole'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/hendizzo/guacamole-azure-multiregion/main/scripts/install-guacamole.sh'
      ]
    }
    protectedSettings: {
      commandToExecute: 'bash install-guacamole.sh ${fqdn} ${certbotEmail}'
    }
  }
}

// Outputs
output vmPublicIP string = publicIP.properties.ipAddress
output vmName string = vm.name
output fqdn string = fqdn
