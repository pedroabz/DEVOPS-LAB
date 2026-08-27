// Entra app registrations and their service principals.
//
// Entra objects are TENANT-scoped, not resource-group scoped. This module therefore uses
// targetScope 'subscription' and main.bicep calls it with no `scope:` — the difference from
// every other module is the visible signal that these do not live in the resource group.
//
// Consequence for teardown: `az group delete` removes NONE of this. See scripts/teardown-entra.sh.
targetScope = 'subscription'

extension microsoftGraphV1

@description('Entra tenant ID. Part of the identifier URIs, which cannot reference appId.')
param tenantId string

@description('Default hostname of the Static Web App, used as the SPA redirect URI.')
param staticWebAppHostname string

// Role and scope IDs are literals generated once with uuidgen. They must never change: an app
// role assignment references its role by ID, so regenerating one orphans every assignment.
var ordersFullAccessRoleId = '314e6088-8588-404d-b643-de8532efc3fa'
var ordersAdminDirectRoleId = 'c7f9f8a3-45e2-43e9-8f98-f41a36ae17f8'
var ordersApiUserImpersonationScopeId = '43d9b38c-63dc-4129-bec0-95fdeb7ed07f'
var ordersReaderRoleId = 'b8d8e445-c110-44d7-8b25-c56eeb9c3cdd'
var ordersAdminRoleId = 'bfcab847-3096-4c88-a446-6715140e74b7'
var bffAccessAsUserScopeId = '18f9f914-848e-41be-84ea-7e3e662f7d5e'

// The Azure CLI's first-party client ID, the same in every tenant. Pre-authorising it is what
// lets `az account get-access-token --scope api://.../user_impersonation` work without hitting
// a consent prompt — which is how Pedro keeps direct admin access to the API after M6.
var azureCliClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'

// ---------------------------------------------------------------------------
// Orders API — the resource server the BFF and Pedro call
// ---------------------------------------------------------------------------

resource ordersApiApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'devopslab-api-dev'
  displayName: 'sp-devopslab-api-dev'
  signInAudience: 'AzureADMyOrg'

  // Cannot be 'api://${ordersApiApp.appId}': appId is ReadOnly on this type, so referencing it
  // here is a self-reference and will not compile. api://<tenantId>/<name> is a documented
  // alternative that needs no generated value.
  identifierUris: [
    'api://${tenantId}/orders-api'
  ]

  api: {
    // v2 tokens, which pairs with the API validating against a /v2.0 authority. Left at the
    // default, tokens carry iss=https://sts.windows.net/{tid}/ which never matches metadata
    // from a /v2.0 authority — producing a 401 with nothing useful in the logs.
    requestedAccessTokenVersion: 2

    // A delegated scope has to exist for a human to request a token at all. Without it,
    // `az account get-access-token --scope ...` has nothing to ask for and direct admin
    // access dies the moment M6 locks the API down.
    oauth2PermissionScopes: [
      {
        id: ordersApiUserImpersonationScopeId
        value: 'user_impersonation'
        type: 'Admin'
        adminConsentDisplayName: 'Access the Orders API as the signed-in user'
        adminConsentDescription: 'Allows the caller to act on orders as the signed-in user.'
        userConsentDisplayName: 'Access the Orders API on your behalf'
        userConsentDescription: 'Allows the app to act on orders on your behalf.'
        isEnabled: true
      }
    ]

    preAuthorizedApplications: [
      {
        appId: azureCliClientId
        delegatedPermissionIds: [
          ordersApiUserImpersonationScopeId
        ]
      }
    ]
  }

  // Two roles answering one question: "are you an allowed caller?" Neither says anything about
  // which user is behind the request — by design, the API never learns that.
  appRoles: [
    {
      id: ordersFullAccessRoleId
      value: 'Orders.FullAccess'
      allowedMemberTypes: [
        'Application'
      ]
      displayName: 'Orders.FullAccess'
      description: 'Full access to orders. Assigned to the BFF managed identity.'
      isEnabled: true
    }
    {
      id: ordersAdminDirectRoleId
      value: 'Orders.Admin.Direct'
      allowedMemberTypes: [
        'User'
      ]
      displayName: 'Orders.Admin.Direct'
      description: 'Direct administrative access, bypassing the BFF.'
      isEnabled: true
    }
  ]
}

resource ordersApiServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: ordersApiApp.appId

  // Entra refuses to mint a token at all for a principal with no assignment, so an unassigned
  // caller is stopped before the API's own policy ever runs.
  appRoleAssignmentRequired: true
}

// ---------------------------------------------------------------------------
// BFF — resource server for the SPA, and the thing that knows about users
// ---------------------------------------------------------------------------

resource bffApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'devopslab-bff-dev'
  displayName: 'sp-devopslab-bff-dev'
  signInAudience: 'AzureADMyOrg'

  identifierUris: [
    'api://${tenantId}/orders-bff'
  ]

  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: [
      {
        id: bffAccessAsUserScopeId
        value: 'access_as_user'
        type: 'User'
        adminConsentDisplayName: 'Access the Orders BFF as the signed-in user'
        adminConsentDescription: 'Allows the SPA to call the BFF as the signed-in user.'
        userConsentDisplayName: 'Access the Orders app on your behalf'
        userConsentDescription: 'Allows the app to act on your behalf.'
        isEnabled: true
      }
    ]
  }

  // These two answer a different question from the API's roles: "what may this person do?"
  appRoles: [
    {
      id: ordersReaderRoleId
      value: 'Orders.Reader'
      allowedMemberTypes: [
        'User'
      ]
      displayName: 'Orders.Reader'
      description: 'May list orders.'
      isEnabled: true
    }
    {
      id: ordersAdminRoleId
      value: 'Orders.Admin'
      allowedMemberTypes: [
        'User'
      ]
      displayName: 'Orders.Admin'
      description: 'May list and create orders.'
      isEnabled: true
    }
  ]
}

resource bffServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: bffApp.appId

  // Deliberately NOT appRoleAssignmentRequired. A user with no role must still receive a token
  // so the BFF can reject them with a 403 — which is the behaviour the PRD asks to demonstrate.
  // Requiring assignment here would turn that into a failed sign-in instead.
}

// ---------------------------------------------------------------------------
// SPA — public client, no credentials
// ---------------------------------------------------------------------------

resource spaApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'devopslab-spa-dev'
  displayName: 'sp-devopslab-spa-dev'
  signInAudience: 'AzureADMyOrg'

  spa: {
    redirectUris: [
      'https://${staticWebAppHostname}'
      // Vite's dev server, so the SPA can be developed against the deployed BFF.
      'http://localhost:5173'
    ]
  }

  requiredResourceAccess: [
    {
      resourceAppId: bffApp.appId
      resourceAccess: [
        {
          id: bffAccessAsUserScopeId
          type: 'Scope'
        }
      ]
    }
  ]
}

resource spaServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: spaApp.appId
}

@description('Client ID of the Orders API app. This is the audience the API validates, and with v2 tokens it is the GUID rather than the identifier URI.')
output ordersApiAppId string = ordersApiApp.appId

@description('Object ID of the Orders API service principal. App role assignments target this, not the application object.')
output ordersApiServicePrincipalId string = ordersApiServicePrincipal.id

@description('Client ID of the BFF app. The audience the BFF validates on inbound user tokens.')
output bffAppId string = bffApp.appId

@description('Object ID of the BFF service principal.')
output bffServicePrincipalId string = bffServicePrincipal.id

@description('Client ID of the SPA app, baked into the frontend build.')
output spaAppId string = spaApp.appId

@description('Scope the SPA requests to call the BFF.')
output bffScope string = 'api://${tenantId}/orders-bff/access_as_user'

@description('Scope the BFF requests to call the Orders API, using client credentials.')
output ordersApiScope string = 'api://${tenantId}/orders-api/.default'
