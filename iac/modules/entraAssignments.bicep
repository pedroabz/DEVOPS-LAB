// App role assignments — who is allowed to do what.
//
// Separate from entraApps.bicep because these depend on the BFF web app existing (for its managed
// identity's principal ID), while the app registrations must exist before the web app can be
// configured. Splitting them lets the dependency chain resolve in a single deployment.
targetScope = 'subscription'

extension microsoftGraphV1

@description('Object ID of the Orders API service principal — the resource granting the role.')
param ordersApiServicePrincipalId string

@description('Object ID of the BFF service principal.')
param bffServicePrincipalId string

@description('Principal ID of the BFF web app managed identity.')
param bffManagedIdentityPrincipalId string

@description('Object ID of the admin user who keeps direct API access.')
param adminUserObjectId string

@description('Object ID of the test user who should only be able to read orders.')
param readerTestUserObjectId string

@description('Object ID of the test user who should be able to read and create orders.')
param adminTestUserObjectId string

// Must match entraApps.bicep exactly. An assignment references its role by ID, so a mismatch
// produces a deployment error rather than a silently wrong grant.
var ordersFullAccessRoleId = '314e6088-8588-404d-b643-de8532efc3fa'
var ordersAdminDirectRoleId = 'c7f9f8a3-45e2-43e9-8f98-f41a36ae17f8'
var ordersReaderRoleId = 'b8d8e445-c110-44d7-8b25-c56eeb9c3cdd'
var ordersAdminRoleId = 'bfcab847-3096-4c88-a446-6715140e74b7'

// appRoleAssignedTo has no name or uniqueName. Its identity is the triple
// (principalId, resourceId, appRoleId), and resourceId is the resource app's SERVICE PRINCIPAL
// object ID — not its appId, and not the application object ID.

// The BFF calling the Orders API. This is the only way the API can be reached by the application.
resource bffCanCallApi 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: bffManagedIdentityPrincipalId
  resourceId: ordersApiServicePrincipalId
  appRoleId: ordersFullAccessRoleId
}

// Pedro calling the Orders API directly, bypassing the BFF. Deliberate, and the only reason it
// works is this assignment — an ordinary user has no equivalent.
resource adminCanCallApiDirectly 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: adminUserObjectId
  resourceId: ordersApiServicePrincipalId
  appRoleId: ordersAdminDirectRoleId
}

resource readerCanUseBff 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: readerTestUserObjectId
  resourceId: bffServicePrincipalId
  appRoleId: ordersReaderRoleId
}

resource adminTestUserCanUseBff 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: adminTestUserObjectId
  resourceId: bffServicePrincipalId
  appRoleId: ordersAdminRoleId
}

// Pedro also uses the SPA, so he needs a BFF role as well as his direct-API one.
resource adminCanUseBff 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: adminUserObjectId
  resourceId: bffServicePrincipalId
  appRoleId: ordersAdminRoleId
}
