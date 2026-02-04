@description('The resource ID of the target scope for role assignments')
param targetResourceId string

@description('Array of role assignments to create')
param roleAssignments array

// Extract resource information for existing resource reference
var resourceInfo = split(targetResourceId, '/')
var resourceName = last(resourceInfo)

resource targetResource 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: resourceName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for assignment in roleAssignments: {
  name: guid(targetResource.id, assignment.principalId, assignment.roleDefinitionId)
  scope: targetResource
  properties: {
    principalId: assignment.principalId
    principalType: assignment.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', assignment.roleDefinitionId)
  }
}]
