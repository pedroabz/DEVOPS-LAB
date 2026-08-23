targetScope = 'subscription'

@description('Environment discriminator. Appears in every resource name and tag.')
@allowed([
  'dev'
  'prod'
])
param envName string

@description('Azure region for every resource. Independent of the --location passed to `az deployment sub create`, which only says where the deployment RECORD is stored.')
param location string = 'northeurope'

@description('Display name of the Entra group that administers SQL.')
param sqlEntraAdminName string

@description('Object ID of the Entra group that administers SQL.')
param sqlEntraAdminObjectId string

@description('Your public IP, so SQL lets you connect from VS Code. Supplied via the CLIENT_IP environment variable — see .env.example.')
param clientIpAddress string

// Names follow docs/prd/v0-foundations.md §7. 'neu' = northeurope.
// Single-region lab; change this alongside `location`.
var suffix = 'devopslab-${envName}-neu'

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
