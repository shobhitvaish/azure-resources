extension microsoftGraphV1

// Parameters
@description('The name of the Log Analytics workspace')
param workspaceName string = 'law-${uniqueString(resourceGroup().id)}'

@secure()
@description('The API token for RealmJoin notification (optional)')
param realmJoinApiToken string = ''

// Variables
var realmJoinAzureResourcesServicePrincipalId = 'fd16fa73-df36-4809-8676-05108225827b'

// Existing service principal
resource realmJoinAzureResourcesServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: realmJoinAzureResourcesServicePrincipalId
}

// Module: Log Analytics Workspace (Workspace, Table, DCR, Role Assignments)
module logIngestion 'modules/logAnalyticsWorkspace.bicep' = {
  params: {
    workspaceName: workspaceName
    servicePrincipalId: realmJoinAzureResourcesServicePrincipal.id
    realmJoinApiToken: realmJoinApiToken
  }
}

// Outputs - Service Principal
@description('The object ID of the service principal')
output servicePrincipalId string = realmJoinAzureResourcesServicePrincipal.id

@description('The display name of the service principal')
output servicePrincipalDisplayName string = realmJoinAzureResourcesServicePrincipal.displayName

// Outputs - Log Ingestion
@description('The resource ID of the Log Analytics workspace')
output workspaceId string = logIngestion.outputs.workspaceId

@description('The workspace customer ID (used for querying)')
output workspaceCustomerId string = logIngestion.outputs.customerId

@description('The name of the custom audit logs table')
output tableName string = logIngestion.outputs.tableName

@description('The logs ingestion endpoint URL from the DCR')
output logsIngestionEndpoint string = logIngestion.outputs.logsIngestionEndpoint

@description('The immutable ID of the Data Collection Rule (required for Logs Ingestion API)')
output dcrImmutableId string = logIngestion.outputs.dcrImmutableId

@description('The resource ID of the Data Collection Rule')
output dcrId string = logIngestion.outputs.dcrId
