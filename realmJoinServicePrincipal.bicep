extension microsoftGraphV1

// Variables
var realmJoinAzureResourcesAppId = 'fd16fa73-df36-4809-8676-05108225827b'

// Create or reference the RealmJoin Azure Resources service principal
// If the SP doesn't exist in the tenant, it will be created
// If it exists, it will be referenced (idempotent via appId)
resource realmJoinServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: realmJoinAzureResourcesAppId
}

// Outputs
@description('The object ID of the RealmJoin service principal')
output servicePrincipalId string = realmJoinServicePrincipal.id

@description('The display name of the RealmJoin service principal')
output displayName string = realmJoinServicePrincipal.displayName

@description('The app ID of the RealmJoin service principal')
output appId string = realmJoinServicePrincipal.appId
