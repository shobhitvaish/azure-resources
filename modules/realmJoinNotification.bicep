@description('The API URL to POST to')
param apiUrl string

@secure()
@description('The authentication token for Authorization header')
param authToken string

@description('The JSON payload to POST')
param payloadJson string

param utcValue string = utcNow()

// Deployment script to POST to API
resource notificationScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'notify-realmjoin-${uniqueString(resourceGroup().id)}'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '15.2'
    scriptContent: loadTextContent('./scripts/realmJoinNotification.ps1')
    environmentVariables: [
      {
        name: 'API_URL'
        value: apiUrl
      }
      {
        name: 'AUTH_TOKEN'
        secureValue: authToken
      }
      {
        name: 'PAYLOAD_JSON'
        value: payloadJson
      }
    ]
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
    timeout: 'PT5M'
    forceUpdateTag: utcValue
  }
}

@description('The result of the RealmJoin notification')
output result object = notificationScript.properties.outputs
