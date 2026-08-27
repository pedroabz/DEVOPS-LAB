targetScope = 'subscription'

@description('Environment discriminator. Appears in every resource name and tag.')
@allowed([
  'dev'
  'prod'
])
param envName string

@description('Azure region for every resource. Independent of the --location passed to `az deployment sub create`, which only says where the deployment RECORD is stored.')
param location string = 'spaincentral'

@description('Display name of the Entra group that administers SQL.')
param sqlEntraAdminName string

@description('Object ID of the Entra group that administers SQL.')
param sqlEntraAdminObjectId string

@description('''Azure region for the Static Web App. Separate from `location` because Static Web
Apps is only available in five regions and spaincentral is not one of them.''')
param staticWebAppLocation string

@description('Object ID of the admin user who keeps direct access to the Orders API.')
param adminUserObjectId string

@description('Object ID of the test user granted Orders.Reader.')
param readerTestUserObjectId string

@description('Object ID of the test user granted Orders.Admin.')
param adminTestUserObjectId string

@description('Your public IP, so SQL lets you connect from VS Code. Supplied via the CLIENT_IP environment variable — see .env.example.')
param clientIpAddress string

// Names follow docs/prd/v0-foundations.md §7. 'neu' = spaincentral.
// Single-region lab; change this alongside `location`.
var suffix = 'devopslab-${envName}-spc'

// SQL server and Web App names are globally unique across ALL of Azure, so they
// carry an extra token. If either name is ever taken, change this.
var owner = 'pabz'

var names = {
  resourceGroup: 'rg-${suffix}'
  logAnalytics: 'log-${suffix}'
  applicationInsights: 'appi-${suffix}'
  sqlServer: 'sql-${suffix}-${owner}'
  sqlDatabase: 'sqldb-orders-${envName}'
  appServicePlan: 'asp-${suffix}'
  vnet: 'vnet-${suffix}'
  webApp: 'app-${suffix}-${owner}'
  bffWebApp: 'app-bff-${suffix}-${owner}'
  staticWebApp: 'stapp-${suffix}'
}

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: names.resourceGroup
  location: location
}

module OrderObservability './modules/observability.bicep' = {
  name: 'observabilityDeployment'
  scope: rg
  params: {
    location: location
    name: names.logAnalytics
    applicationInsightsName: names.applicationInsights
  }
}

module network './modules/network.bicep' = {
  name: 'networkDeployment'
  scope: rg
  params: {
    location: location
    vnetName: names.vnet
  }
}

module sql './modules/sqlServer.bicep' = {
  name: 'sqlDeployment'
  scope: rg
  params: {
    location: location
    sqlServerName: names.sqlServer
    databaseName: names.sqlDatabase
    sqlEntraAdminName: sqlEntraAdminName
    sqlEntraAdminObjectId: sqlEntraAdminObjectId
    clientIpAddress: clientIpAddress
    appSubnetId: network.outputs.appSubnetId
  }
}

module appService './modules/appService.bicep' = {
  name: 'appServiceDeployment'
  scope: rg
  params: {
    location: location
    appServicePlanName: names.appServicePlan
    webAppName: names.webApp
    appSubnetId: network.outputs.appSubnetId
    applicationInsightsConnectionString: OrderObservability.outputs.applicationInsightsConnectionString
    sqlConnectionString: sql.outputs.connectionString
    tenantId: tenant().tenantId
    ordersApiClientId: entraApps.outputs.ordersApiAppId
  }
}

// The SPA's redirect URI needs this hostname, and the hostname is generated — hence Static Web
// App before the app registrations.
module staticWebApp './modules/staticWebApp.bicep' = {
  name: 'staticWebAppDeployment'
  scope: rg
  params: {
    staticWebAppName: names.staticWebApp
    location: staticWebAppLocation
  }
}

// No `scope:` — Entra objects are tenant-scoped, not resource-group scoped.
module entraApps './modules/entraApps.bicep' = {
  name: 'entraAppsDeployment'
  params: {
    tenantId: tenant().tenantId
    staticWebAppHostname: staticWebApp.outputs.defaultHostname
  }
}

module bffAppService './modules/bffAppService.bicep' = {
  name: 'bffAppServiceDeployment'
  scope: rg
  params: {
    location: location
    bffWebAppName: names.bffWebApp
    appServicePlanId: appService.outputs.appServicePlanId
    tenantId: tenant().tenantId
    bffClientId: entraApps.outputs.bffAppId
    ordersApiBaseUrl: 'https://${appService.outputs.webAppHostname}'
    ordersApiScope: entraApps.outputs.ordersApiScope
    allowedOrigin: 'https://${staticWebApp.outputs.defaultHostname}'
    applicationInsightsConnectionString: OrderObservability.outputs.applicationInsightsConnectionString
  }
}

// Last, because it needs the BFF's managed identity to exist.
module entraAssignments './modules/entraAssignments.bicep' = {
  name: 'entraAssignmentsDeployment'
  params: {
    ordersApiServicePrincipalId: entraApps.outputs.ordersApiServicePrincipalId
    bffServicePrincipalId: entraApps.outputs.bffServicePrincipalId
    bffManagedIdentityPrincipalId: bffAppService.outputs.principalId
    adminUserObjectId: adminUserObjectId
    readerTestUserObjectId: readerTestUserObjectId
    adminTestUserObjectId: adminTestUserObjectId
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Name of the resource group that was created.')
output resourceGroupName string = rg.name

@description('FQDN of the SQL server.')
output sqlServerFqdn string = sql.outputs.sqlServerFqdn

@description('Default hostname of the Web App.')
output webAppHostname string = appService.outputs.webAppHostname

@description('Client ID of the SPA app registration. Baked into the frontend build by spa-cd.yml.')
output spaClientId string = entraApps.outputs.spaAppId

@description('Scope the SPA requests to call the BFF.')
output bffScope string = entraApps.outputs.bffScope

@description('Hostname of the BFF, which the SPA calls.')
output bffHostname string = bffAppService.outputs.defaultHostName

@description('Hostname of the Static Web App.')
output staticWebAppHostname string = staticWebApp.outputs.defaultHostname

@description('Name of the Static Web App, so spa-cd.yml can fetch its deployment token via OIDC instead of storing one as a repo secret.')
output staticWebAppName string = staticWebApp.outputs.name

@description('Client ID of the Orders API app registration.')
output ordersApiClientId string = entraApps.outputs.ordersApiAppId
