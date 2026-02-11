// Parameters
@description('The name of the Automation Account')
param automationAccountName string = 'aa-${uniqueString(resourceGroup().id)}'

@description('The object ID of the RealmJoin service principal')
param rjServicePrincipalId string

// Variables
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Automation Account with System-Assigned Managed Identity
resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: automationAccountName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
  }
}

// Role Assignment: RJ Service Principal as Contributor on Automation Account
resource spContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, rjServicePrincipalId, contributorRoleId)
  scope: automationAccount
  properties: {
    principalId: rjServicePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
  }
}

// Outputs
@description('The resource ID of the Automation Account')
output automationAccountId string = automationAccount.id

@description('The name of the Automation Account')
output automationAccountName string = automationAccount.name

@description('The principal ID of the Automation Account managed identity')
output automationAccountPrincipalId string = automationAccount.identity.principalId
