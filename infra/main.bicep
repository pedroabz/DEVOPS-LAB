targetScope = 'subscription'

@description('Name of the resource group to create.')
param resourceGroupName string

@description('Azure region for every resource. Note this is independent of the --location passed to `az deployment sub create`, which only says where the deployment RECORD is stored.')
param location string = 'northeurope'

@description('Name of the Log Analytics workspace.')
param logAnalyticsName string

@description('Name of the Application Insights component.')
param ordersAppInsightsName string

@description('Globally unique name of the SQL logical server.')
param sqlServerName string

@description('Name of the SQL database.')
param databaseName string

@description('Display name of the Entra group that administers SQL.')
param sqlEntraAdminName string

@description('Object ID of the Entra group that administers SQL.')
param sqlEntraAdminObjectId string

@description('Name of the App Service plan.')
param appServicePlanName string

@description('Globally unique name of the Web App.')
param webAppName string

@description('App Service plan SKU.')
param appServicePlanSku string = 'B1'

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
}

module OrderObservability './modules/observability.bicep' = {
  name: 'observabilityDeployment'
  scope: rg
  params: {
    location: location
    name: logAnalyticsName
    applicationInsightsName: ordersAppInsightsName
  }
}

module sql './modules/sqlServer.bicep' = {
  name: 'sqlDeployment'
  scope: rg
  params: {
    location: location
    sqlServerName: sqlServerName
    databaseName: databaseName
    sqlEntraAdminName: sqlEntraAdminName
    sqlEntraAdminObjectId: sqlEntraAdminObjectId
  }
}

module compute './modules/compute.bicep' = {
  name: 'computeDeployment'
  scope: rg
  params: {
    location: location
    appServicePlanName: appServicePlanName
    webAppName: webAppName
    appServicePlanSku: appServicePlanSku
    applicationInsightsConnectionString: OrderObservability.outputs.applicationInsightsConnectionString
    sqlConnectionString: sql.outputs.connectionString
  }
}

@description('Default hostname of the deployed Web App.')
output webAppHostname string = compute.outputs.webAppHostname

@description('Managed identity principal ID of the Web App — needed for the M6 role assignments.')
output webAppPrincipalId string = compute.outputs.webAppPrincipalId

@description('FQDN of the SQL server.')
output sqlServerFqdn string = sql.outputs.sqlServerFqdn
