targetScope = 'subscription'

@description('Environment discriminator. Appears in every resource name and tag.')
@allowed([
  'dev'
  'prod'
])
param envName string

@description('Azure region for every resource. Independent of the --location passed to `az deployment sub create`, which only says where the deployment RECORD is stored.')
param location string = 'northeurope'

@description('''App Service plan SKU. Defaults to F1 (free) to keep the lab at zero compute cost.
  F1 — free. No Always On (app unloads after ~20 min idle), 60 CPU-minutes/day, no deployment slots.
  B1 — ~EUR 12/mo. Always On, but STILL NO SLOTS. Slots start at Standard.
  S1 — ~EUR 65/mo. 5 deployment slots. Same hardware as B1; you pay purely for features.
  Plans bill hourly and resize in place, so switch to S1 for an afternoon to practise slot swaps
  (v1), then switch back. See docs/prd/v0-foundations.md section 9.''')
@allowed([
  'F1'
  'B1'
  'S1'
])
param appServicePlanSku string = 'F1'

@description('Display name of the Entra group that administers SQL.')
param sqlEntraAdminName string

@description('Object ID of the Entra group that administers SQL.')
param sqlEntraAdminObjectId string

// Names follow docs/prd/v0-foundations.md §7. 'neu' = northeurope.
// Single-region lab; change this alongside `location`.
var suffix = 'devopslab-${envName}-neu'

// SQL server and Web App names are globally unique across ALL of Azure, so they
// carry an extra token. If one is ever taken, change this.
var owner = 'pabz'

var names = {
  resourceGroup: 'rg-${suffix}'
  logAnalytics: 'log-${suffix}'
  applicationInsights: 'appi-${suffix}'
  appServicePlan: 'asp-${suffix}'
  sqlServer: 'sql-${suffix}-${owner}'
  sqlDatabase: 'sqldb-orders-${envName}'
  webApp: 'app-${suffix}-${owner}'
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

module sql './modules/sqlServer.bicep' = {
  name: 'sqlDeployment'
  scope: rg
  params: {
    location: location
    sqlServerName: names.sqlServer
    databaseName: names.sqlDatabase
    sqlEntraAdminName: sqlEntraAdminName
    sqlEntraAdminObjectId: sqlEntraAdminObjectId
  }
}

module appService './modules/appService.bicep' = {
  name: 'appServiceDeployment'
  scope: rg
  params: {
    location: location
    appServicePlanName: names.appServicePlan
    webAppName: names.webApp
    appServicePlanSku: appServicePlanSku
    applicationInsightsConnectionString: OrderObservability.outputs.applicationInsightsConnectionString
    sqlConnectionString: sql.outputs.connectionString
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Name of the resource group that was created.')
output resourceGroupName string = rg.name

@description('Default hostname of the deployed Web App.')
output webAppHostname string = appService.outputs.webAppHostname

@description('Managed identity principal ID of the Web App — needed for the M6 role assignments.')
output webAppPrincipalId string = appService.outputs.webAppPrincipalId

@description('FQDN of the SQL server.')
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
