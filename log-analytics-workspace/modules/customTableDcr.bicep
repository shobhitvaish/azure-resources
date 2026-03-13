@description('The name of the Log Analytics workspace')
param workspaceName string

@description('The name of the custom table (must end with _CL)')
param tableName string

@description('The name of the DCR')
param dcrName string

@description('The name of the stream (e.g., Custom-RJAuditLogs_CL)')
param streamName string

@description('The columns for the custom table (Pascal case: DateTime, String, Dynamic)')
param tableColumns array

@description('The columns for the DCR stream (lowercase: datetime, string, dynamic)')
param dcrColumns array

@description('The service principal ID for role assignments')
param servicePrincipalId string

@description('Azure region')
param location string

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var logsDestinationName = 'RJLogAnalyticsDestination'

// Reference existing workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: workspaceName
}

// Create custom table
resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2025-07-01' = {
  name: tableName
  parent: workspace
  properties: {
    schema: {
      name: tableName
      columns: tableColumns
    }
  }
}

// Create DCR
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dcrName
  location: location
  kind: 'Direct'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    streamDeclarations: {
      '${streamName}': {
        columns: dcrColumns
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspace.id
          name: logsDestinationName
        }
      ]
    }
    dataFlows: [
      {
        streams: [streamName]
        destinations: [logsDestinationName]
        outputStream: streamName
      }
    ]
  }
}

// Grant service principal permissions to DCR
resource spToDcrRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRule.id, servicePrincipalId, monitoringMetricsPublisherRoleId)
  scope: dataCollectionRule
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: servicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

@description('The resource ID of the DCR')
output dcrId string = dataCollectionRule.id

@description('The immutable ID of the DCR')
output dcrImmutableId string = dataCollectionRule.properties.immutableId

@description('The logs ingestion endpoint')
output logsIngestionEndpoint string = dataCollectionRule.properties.endpoints.logsIngestion

@description('The stream name for the DCR')
output streamName string = streamName
