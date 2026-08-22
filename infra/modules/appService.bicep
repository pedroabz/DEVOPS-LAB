targetScope = 'resourceGroup'

@description('Name of the App Service plan.')
param appServicePlanName string

@description('Globally unique name of the Web App.')
param webAppName string

@description('Azure region.')
param location string

@description('''App Service plan SKU.
  F1 — free; no Always On, 60 CPU-min/day, no slots. The lab default.
  B1 — ~EUR 12/mo; Always On, but no deployment slots.
  S1 — ~EUR 65/mo; 5 slots. Deployment slots require Standard or higher — Free, Shared and Basic
       have none. Scale up temporarily to practise slot swaps, then scale back.''')
@allowed([
  'F1'
  'B1'
  'S1'
])
param appServicePlanSku string = 'F1'

@description('Application Insights connection string, from the observability module.')
param applicationInsightsConnectionString string

@description('SQL connection string using Entra managed-identity auth. Contains no password.')
param sqlConnectionString string

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true // 'reserved' is how ARM spells "this is a Linux plan". Non-obvious but required.
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'

  // System-assigned managed identity. This is the principal that will authenticate to SQL and
  // Key Vault — it exists only as long as this Web App does, which is what we want here.
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true

    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled' // no FTP deployment path at all
      http20Enabled: true
      alwaysOn: appServicePlanSku != 'F1' // unsupported on the free tier

      appSettings: [
        {
          // Wiring telemetry via configuration rather than code means the app has no idea which
          // App Insights instance it reports to — the environment decides.
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Development'
        }
      ]

      connectionStrings: [
        {
          // Type 'SQLAzure' surfaces this to .NET as a connection string rather than an env var.
          // It carries no password — auth is the managed identity above.
          name: 'DefaultConnection'
          connectionString: sqlConnectionString
          type: 'SQLAzure'
        }
      ]
    }
  }
}

@description('Principal ID of the Web App system-assigned managed identity. Consumed by role assignments (M6) and by the T-SQL that creates its database user (task 6.5).')
output webAppPrincipalId string = webApp.identity.principalId

@description('Default hostname of the Web App.')
output webAppHostname string = webApp.properties.defaultHostName

@description('Name of the Web App.')
output webAppName string = webApp.name

@description('Resource ID of the Web App.')
output webAppId string = webApp.id
