@description('The name of the Log Analytics workspace')
param workspaceName string

var dcrName = 'dcr-auditlogs-${uniqueString(resourceGroup().id)}'
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
