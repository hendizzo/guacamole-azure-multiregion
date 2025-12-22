@description('Array of origin configurations')
param origins array

var profileName = 'guacamole-frontdoor'
var endpointName = 'guacamole-global'
var originGroupName = 'guacamole-origins'
var routeName = 'guacamole-route'

// Front Door Profile
resource profile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: profileName
  location: 'global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
}

// Front Door Endpoint
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: profile
  name: endpointName
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: profile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/guacamole/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origins
resource frontDoorOrigins 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = [for (origin, i) in origins: {
  parent: originGroup
  name: origin.name
  properties: {
    hostName: origin.hostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: origin.hostName
    priority: origin.priority
    weight: origin.weight
    enabledState: 'Enabled'
  }
}]

// Route
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: endpoint
  name: routeName
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: frontDoorOrigins
}

// Outputs
output frontDoorEndpoint string = endpoint.properties.hostName
output profileName string = profile.name
output endpointName string = endpoint.name
output originGroupName string = originGroup.name
