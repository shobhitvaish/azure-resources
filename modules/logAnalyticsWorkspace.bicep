@description('The name of the Log Analytics workspace')
param workspaceName string

@description('The principal ID of the service principal to grant permissions')
param servicePrincipalId string

@secure()
@description('The API token for RealmJoin notification (optional)')
param realmJoinApiToken string = ''

var dcrName = 'dcr-auditlogs-${uniqueString(resourceGroup().id)}'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var logAnalyticsContributorRoleId = '92aaf0da-9dab-42b6-94a3-d43ce8d16293'
var tableName = 'RJAuditLogs_CL'
var streamName = 'Custom-${tableName}'
var logsDestinationName = 'RJLogAnalyticsDestination'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: workspaceName
  location: resourceGroup().location
}

// Custom Table
resource auditLogsTable 'Microsoft.OperationalInsights/workspaces/tables@2025-07-01' = {
  parent: logAnalyticsWorkspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      columns: [
        {
          name: 'TimeGenerated'
          type: 'DateTime'
        }
        {
          name: 'Level'
          type: 'String'
        }
        {
          name: 'Message'
          type: 'String'
        }
        {
          name: 'Exception'
          type: 'String'
        }
        {
          name: 'CustomerTenantId'
          type: 'String'
        }
        {
          name: 'LogType'
          type: 'String'
        }
        {
          name: 'Actor'
          type: 'Dynamic'
        }
        {
          name: 'Target'
          type: 'Dynamic'
        }
      ]
    }
  }
}

// Data Collection Rule
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dcrName
  kind: 'Direct'
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    streamDeclarations: {
      '${streamName}': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'Level'
            type: 'string'
          }
          {
            name: 'Message'
            type: 'string'
          }
          {
            name: 'Exception'
            type: 'string'
          }
          {
            name: 'CustomerTenantId'
            type: 'string'
          }
          {
            name: 'LogType'
            type: 'string'
          }
          {
            name: 'Actor'
            type: 'dynamic'
          }
          {
            name: 'Target'
            type: 'dynamic'
          }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: logsDestinationName
        }
      ]
    }
    dataFlows: [
      {
        streams: [ streamName ]
        destinations: [ logsDestinationName ]
        outputStream: streamName
      }
    ]
  }
}

// Role Assignment: Service Principal -> Log Analytics Contributor -> Workspace
resource spToWorkspaceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, servicePrincipalId, logAnalyticsContributorRoleId)
  scope: logAnalyticsWorkspace
  properties: {
    principalId: servicePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsContributorRoleId)
  }
}

// Role Assignment: Service Principal -> Monitoring Metrics Publisher -> DCR
resource spToDcrRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRule.id, servicePrincipalId, monitoringMetricsPublisherRoleId)
  scope: dataCollectionRule
  properties: {
    principalId: servicePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
  }
}

// RealmJoin Notification (conditional)
module realmJoinNotification 'realmJoinNotification.bicep' = if (!empty(realmJoinApiToken)) {
  name: 'realmJoinNotification'
  params: {
    apiUrl: 'https://api.realmjoin.com/v1/workspace-registration'
    authToken: realmJoinApiToken
    payloadJson: string({
      tenantId: tenant().tenantId
      subscriptionId: subscription().subscriptionId
      resourceGroupName: resourceGroup().name
      workspaceName: workspaceName
      workspaceId: logAnalyticsWorkspace.id
      customerId: logAnalyticsWorkspace.properties.customerId
      tableName: auditLogsTable.name
      dcrImmutableId: dataCollectionRule.properties.immutableId
      logsIngestionEndpoint: dataCollectionRule.properties.endpoints.logsIngestion
    })
  }
  dependsOn: [
    spToWorkspaceRole
    spToDcrRole
  ]
}

@description('The resource ID of the Log Analytics workspace')
output workspaceId string = logAnalyticsWorkspace.id

@description('The workspace customer ID (used for API calls)')
output customerId string = logAnalyticsWorkspace.properties.customerId

@description('The name of the custom table')
output tableName string = auditLogsTable.name

@description('The logs ingestion endpoint URL from the DCR')
output logsIngestionEndpoint string = dataCollectionRule.properties.endpoints.logsIngestion

@description('The immutable ID of the Data Collection Rule (needed for API calls)')
output dcrImmutableId string = dataCollectionRule.properties.immutableId

@description('The resource ID of the Data Collection Rule')
output dcrId string = dataCollectionRule.id

@description('The principal ID of the DCR managed identity')
output dcrPrincipalId string = dataCollectionRule.identity.principalId
