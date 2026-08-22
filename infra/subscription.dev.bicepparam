using './main.bicep'

// Resource names are NOT set here — main.bicep derives them from these inputs
// using the convention in docs/prd/v0-foundations.md §7.

param envName = 'dev'
param workload = 'devopslab'
param location = 'northeurope'

param appServicePlanSku = 'B1'

param sqlEntraAdminName = 'sg-devopslab-sql-admins'
param sqlEntraAdminObjectId = 'cffa7571-2a23-417e-b71f-8cff180f7af8'
