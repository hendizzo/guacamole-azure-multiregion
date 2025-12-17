// Azure Front Door Infrastructure
// This template creates the Azure Front Door for global load balancing
// 
// PREREQUISITES:
// 1. Regional VMs must be deployed and running
// 2. DNS A records must be configured and propagated
// 3. Guacamole must be installed and responding on HTTPS
// 4. Origins must be accessible via their hostnames

@description('Front Door name')
param frontDoorName string = 'guacamole-frontdoor'

@description('Front Door SKU')
@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
param frontDoorSku string = 'Standard_AzureFrontDoor'

@description('Custom domain name (e.g., paw.vorlichmedia.com)')
param customDomain string = 'paw.vorlichmedia.com'

@description('UK origin hostname (e.g., paw.vorlichmedia.com)')
param ukOriginHostname string

@description('Canada origin hostname (e.g., paw-ca.vorlichmedia.com)')
param canadaOriginHostname string

// Front Door Profile
resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: frontDoorName
  location: 'global'
  sku: {
    name: frontDoorSku
  }
}

// Endpoint
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: frontDoorProfile
  name: 'guacamole-endpoint'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: frontDoorProfile
  name: 'guacamole-origins'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// UK Origin
resource ukOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'uk-origin'
  properties: {
    hostName: ukOriginHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: ukOriginHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Canada Origin
resource canadaOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'canada-origin'
  properties: {
    hostName: canadaOriginHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: canadaOriginHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
  }
}

// Route
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: endpoint
  name: 'guacamole-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [
    ukOrigin
    canadaOrigin
  ]
}

// Outputs
output frontDoorEndpointHostName string = endpoint.properties.hostName
output frontDoorId string = frontDoorProfile.id
output profileName string = frontDoorProfile.name
