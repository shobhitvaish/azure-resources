@description('The name of the Log Analytics workspace')
param workspaceName string = 'law-${uniqueString(resourceGroup().id)}'

@description('The principal ID of the service principal to grant permissions')
param servicePrincipalId string

@description('Whether to deploy the audit logs DCR and custom table')
param deployAuditLogsDCR bool = true

@description('Whether to deploy the runbook logs DCR and custom table')
param deployRunbookLogsDCR bool = false

var uniqueId = uniqueString(resourceGroup().id)
var logAnalyticsContributorRoleId = '92aaf0da-9dab-42b6-94a3-d43ce8d16293'

// Table and DCR names
var auditLogsTableName = 'RJAuditLogs_CL'
var auditLogsStreamName = 'Custom-${auditLogsTableName}'
var auditLogsDcrName = 'dcr-auditlogs-${uniqueId}'

var runbookLogsTableName = 'RJRunbookLogs_CL'
var runbookLogsStreamName = 'Custom-${runbookLogsTableName}'
var runbookLogsDcrName = 'dcr-runbooklogs-${uniqueId}'

// Audit Logs Schema
var auditLogsColumns = [
  { name: 'TimeGenerated', type: 'datetime' }
  { name: 'Level', type: 'string' }
  { name: 'Message', type: 'string' }
  { name: 'Exception', type: 'string' }
  { name: 'CustomerTenantId', type: 'string' }
  { name: 'Category', type: 'string' }
  { name: 'LogType', type: 'string' }
  { name: 'Subject', type: 'dynamic' }
  { name: 'Target', type: 'dynamic' }
  { name: 'Change', type: 'dynamic' }
  { name: 'Context', type: 'dynamic' }
  { name: 'UserName', type: 'string' }
  { name: 'UserId', type: 'string' }
  { name: 'SourceContext', type: 'string' }
  { name: 'RequestId', type: 'string' }
  { name: 'EnvironmentName', type: 'string' }
  { name: 'Diagnostics', type: 'dynamic' }
]

// Runbook Logs Schema
var runbookLogsColumns = [
  { name: 'TimeGenerated', type: 'datetime' }
  { name: 'JobCreationTime', type: 'datetime' }
  { name: 'JobEndTime', type: 'datetime' }
  { name: 'JobException', type: 'string' }
  { name: 'JobId', type: 'string' }
  { name: 'JobJobId', type: 'guid' }
  { name: 'JobLastModifiedTime', type: 'datetime' }
  { name: 'JobLastStatusModifiedTime', type: 'datetime' }
  { name: 'JobNameGuid', type: 'guid' }
  { name: 'JobName', type: 'string' }
  { name: 'JobOutput', type: 'string' }
  { name: 'JobParametersJson', type: 'string' }
  { name: 'JobPrettyCategory', type: 'string' }
  { name: 'JobPrettyName', type: 'string' }
  { name: 'JobPrettyType', type: 'string' }
  { name: 'JobProvisioningState', type: 'string' }
  { name: 'JobRunbookName', type: 'string' }
  { name: 'JobRunOn', type: 'string' }
  { name: 'JobStartedBy', type: 'string' }
  { name: 'JobStartTime', type: 'datetime' }
  { name: 'JobStatus', type: 'string' }
  { name: 'JobStatusDetails', type: 'string' }
  { name: 'JobStreamsJson', type: 'string' }
  { name: 'JobType', type: 'string' }
]

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: workspaceName
  location: resourceGroup().location
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

// Module: Audit Logs DCR
module auditLogsDcr 'modules/customTableDcr.bicep' = if (deployAuditLogsDCR) {
  name: 'auditLogsDcr'
  params: {
    workspaceName: logAnalyticsWorkspace.name
    tableName: auditLogsTableName
    dcrName: auditLogsDcrName
    streamName: auditLogsStreamName
    columns: auditLogsColumns
    servicePrincipalId: servicePrincipalId
    location: resourceGroup().location
  }
}

// Module: Runbook Logs DCR
module runbookLogsDcr 'modules/customTableDcr.bicep' = if (deployRunbookLogsDCR) {
  name: 'runbookLogsDcr'
  params: {
    workspaceName: logAnalyticsWorkspace.name
    tableName: runbookLogsTableName
    dcrName: runbookLogsDcrName
    streamName: runbookLogsStreamName
    columns: runbookLogsColumns
    servicePrincipalId: servicePrincipalId
    location: resourceGroup().location
  }
}

@description('The name of the Log Analytics workspace')
output workspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the Log Analytics workspace')
output workspaceId string = logAnalyticsWorkspace.id

@description('The workspace customer ID (used for API calls)')
output customerId string = logAnalyticsWorkspace.properties.customerId

// Audit Logs DCR Outputs
@description('The name of the audit logs custom table')
output tableName string = deployAuditLogsDCR ? auditLogsTableName : ''

@description('The stream name for the audit logs DCR')
output streamName string = auditLogsStreamName

@description('The logs ingestion endpoint URL from the audit logs DCR')
output logsIngestionEndpoint string = deployAuditLogsDCR ? auditLogsDcr!.outputs.logsIngestionEndpoint : ''

@description('The immutable ID of the audit logs Data Collection Rule (needed for API calls)')
output dcrImmutableId string = deployAuditLogsDCR ? auditLogsDcr!.outputs.dcrImmutableId : ''

@description('The resource ID of the audit logs Data Collection Rule')
output dcrId string = deployAuditLogsDCR ? auditLogsDcr!.outputs.dcrId : ''

// Runbook Logs DCR Outputs
@description('The name of the runbook logs custom table')
output runbookLogsTableName string = deployRunbookLogsDCR ? runbookLogsTableName : ''

@description('The stream name for the runbook logs DCR')
output runbookLogsStreamName string = runbookLogsStreamName

@description('The logs ingestion endpoint URL from the runbook logs DCR')
output runbookLogsIngestionEndpoint string = deployRunbookLogsDCR ? runbookLogsDcr!.outputs.logsIngestionEndpoint : ''

@description('The immutable ID of the runbook logs Data Collection Rule (needed for API calls)')
output runbookLogsDcrImmutableId string = deployRunbookLogsDCR ? runbookLogsDcr!.outputs.dcrImmutableId : ''

@description('The resource ID of the runbook logs Data Collection Rule')
output runbookLogsDcrId string = deployRunbookLogsDCR ? runbookLogsDcr!.outputs.dcrId : ''
