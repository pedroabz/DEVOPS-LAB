targetScope = 'resourceGroup'

@description('Name of the App Service plan.')
param appServicePlanName string

@description('Globally unique name of the Web App.')
param webAppName string

@description('Azure region for the plan and the Web App.')
param location string

@description('Application Insights connection string, from the observability module.')
param applicationInsightsConnectionString string

@description('Resource ID of the subnet to route outbound traffic through.')
param appSubnetId string

@description('Client ID of the Orders API app registration. With v2 tokens this GUID is the audience the API validates, and it is what makes the API reject the SPA token — whose audience is the BFF.')
param ordersApiClientId string

@description('Entra tenant ID, used to build the token authority.')
param tenantId string

@description('SQL connection string using Entra managed-identity auth. Contains no password.')
param sqlConnectionString string

// Basic is the cheapest tier that supports VNet integration
resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1'
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

  // The principal that authenticates to SQL and Key Vault. System-assigned, so it is created and
  // destroyed with this Web App instead of needing a lifecycle of its own.
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: appSubnetId

    // Without this, only private (RFC1918) traffic takes the subnet route. SQL's endpoint is a
    // public address, so its traffic would leave by the old path and arrive at SQL from the App
    // Service scale unit's IP — which the virtual network rule does not match. Everything would
    // deploy green and the connection would still be refused.
    outboundVnetRouting: {
      applicationTraffic: true
    }

    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      ftpsState: 'Disabled' // deployment is GitHub Actions only, so close the unwatched FTP door

      // Without this the app unloads after 20 idle minutes, and the next request pays a cold start
      // on top of SQL's 30-60s resume. Costs nothing: the plan bills the same either way.
      alwaysOn: true

      // App Service restarts instances that fail this probe, so it points at LIVENESS, which runs no
      // checks. /health/ready exists too and reaches SQL — pointing this at it would turn every
      // auto-pause into a restart loop.
      healthCheckPath: '/health/live'

      appSettings: [
        {
          // Supplying telemetry wiring as configuration means the app has no idea which App
          // Insights instance it reports to — the environment decides.
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          // Distinguishes this service from the BFF inside the shared App Insights component,
          // so both appear as separate nodes on the application map while their traces still join
          // into one operation_id.
          name: 'OTEL_SERVICE_NAME'
          value: 'orders-api'
        }
        {
          // App Service on Linux maps __ to : , so this arrives as AzureAd:TenantId.
          name: 'AzureAd__TenantId'
          value: tenantId
        }
        {
          name: 'AzureAd__ClientId'
          value: ordersApiClientId
        }
      ]

      connectionStrings: [
        {
          // Type 'SQLAzure' reaches .NET as ConnectionStrings:DefaultConnection rather than as a
          // bare environment variable. It carries no password — auth is the identity above.
          name: 'DefaultConnection'
          connectionString: sqlConnectionString
          type: 'SQLAzure'
        }
      ]
    }
  }
}

@description('Default hostname of the Web App. Used to confirm the site responds, per docs/prd/v0-foundations.md §4.')
output webAppHostname string = webApp.properties.defaultHostName

@description('Resource ID of the App Service plan, so the BFF can be hosted on it without paying for a second plan.')
output appServicePlanId string = appServicePlan.id
