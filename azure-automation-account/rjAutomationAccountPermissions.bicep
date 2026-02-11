extension microsoftGraphV1

// Parameters
@description('The principal ID of the managed identity to assign permissions to')
param principalId string

// Load permissions from JSON file
var permissionsConfig = loadJsonContent('./RJAutomationAccountPermissionsManifest.json')

// Extract permissions for each resource application
var graphPermissions = filter(permissionsConfig, app => app.Id == '00000003-0000-0000-c000-000000000000')[0].AppRoleAssignments
var exchangePermissions = filter(permissionsConfig, app => app.Id == '00000002-0000-0ff1-ce00-000000000000')[0].AppRoleAssignments
var defenderPermissions = filter(permissionsConfig, app => app.Id == 'fc780465-2017-40d4-a0c5-307022471b92')[0].AppRoleAssignments
var sharePointPermissions = filter(permissionsConfig, app => app.Id == '00000003-0000-0ff1-ce00-000000000000')[0].AppRoleAssignments

// Reference existing resource service principals
resource microsoftGraph 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

resource exchangeOnline 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000002-0000-0ff1-ce00-000000000000'
}

resource defenderAtp 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: 'fc780465-2017-40d4-a0c5-307022471b92'
}

resource sharePointOnline 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0ff1-ce00-000000000000'
}

// App Role Assignments - Microsoft Graph
resource graphAppRoleAssignments 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for permission in graphPermissions: {
  appRoleId: first(filter(microsoftGraph.appRoles, role => role.value == permission))!.id
  principalId: principalId
  resourceId: microsoftGraph.id
}]

// App Role Assignments - Office 365 Exchange Online
resource exchangeAppRoleAssignments 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for permission in exchangePermissions: {
  appRoleId: first(filter(exchangeOnline.appRoles, role => role.value == permission))!.id
  principalId: principalId
  resourceId: exchangeOnline.id
}]

// App Role Assignments - Windows Defender ATP
resource defenderAppRoleAssignments 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for permission in defenderPermissions: {
  appRoleId: first(filter(defenderAtp.appRoles, role => role.value == permission))!.id
  principalId: principalId
  resourceId: defenderAtp.id
}]

// App Role Assignments - Office 365 SharePoint Online
resource sharePointAppRoleAssignments 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for permission in sharePointPermissions: {
  appRoleId: first(filter(sharePointOnline.appRoles, role => role.value == permission))!.id
  principalId: principalId
  resourceId: sharePointOnline.id
}]

// Outputs
@description('Number of Microsoft Graph permissions assigned')
output graphPermissionsCount int = length(graphPermissions)

@description('Number of Exchange Online permissions assigned')
output exchangePermissionsCount int = length(exchangePermissions)

@description('Number of Defender ATP permissions assigned')
output defenderPermissionsCount int = length(defenderPermissions)

@description('Number of SharePoint Online permissions assigned')
output sharePointPermissionsCount int = length(sharePointPermissions)
