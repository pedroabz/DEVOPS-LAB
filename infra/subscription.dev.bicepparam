using './main.bicep'

param resourceGroupName = 'rg-devopslab-dev-neu'
param location = 'northeurope'

// --- Observability ---
param logAnalyticsName = 'log-analytics-devopslab-dev-neu'
param ordersAppInsightsName = 'order-appi'

// --- Data ---
// SQL server names are globally unique across all of Azure.
param sqlServerName = 'sql-devopslab-dev-neu-pabz'
param databaseName = 'sqldb-orders-dev'
param sqlEntraAdminName = 'sg-devopslab-sql-admins'
param sqlEntraAdminObjectId = 'cffa7571-2a23-417e-b71f-8cff180f7af8'

// --- Compute ---
param appServicePlanName = 'asp-devopslab-dev-neu'
// Web App names are globally unique — they become <name>.azurewebsites.net.
param webAppName = 'app-devopslab-api-dev-pabz'
param appServicePlanSku = 'B1'
