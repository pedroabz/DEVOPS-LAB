targetScope = 'resourceGroup'

@description('Globally unique name of the BFF web app.')
param bffWebAppName string

@description('Azure region.')
param location string

@description('Resource ID of the App Service plan created by appService.bicep. The BFF shares it rather than paying for a second plan.')
param appServicePlanId string

@description('Entra tenant ID, for validating inbound user tokens.')
param tenantId string

@description('Client ID of the BFF app registration. This is the audience of the tokens the SPA sends.')
param bffClientId string

@description('Base URL of the Orders API.')
param ordersApiBaseUrl string

@description('Scope the BFF requests when calling the Orders API with its managed identity.')
param ordersApiScope string

@description('Origin allowed to call this BFF from a browser — the Static Web App.')
param allowedOrigin string

@description('Application Insights connection string. Shared with the API so one operation_id spans SPA to BFF to API to SQL.')
param applicationInsightsConnectionString string

resource bffWebApp 'Microsoft.Web/sites@2024-11-01' = {
  name: bffWebAppName
  location: location
  kind: 'app,linux'

  // The identity that authenticates to the Orders API. Nothing else about the BFF is a
  // credential — there is no client secret and no certificate anywhere.
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true

    // Deliberately no virtualNetworkSubnetId and no outboundVnetRouting. The BFF never touches
    // SQL, so it has no reason to be on the subnet, and putting it there would suggest it does.
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      alwaysOn: true
      healthCheckPath: '/health/live'

      appSettings: [
        {
          // App Service on Linux maps __ to : , so this arrives as AzureAd:TenantId.
          name: 'AzureAd__TenantId'
          value: tenantId
        }
        {
          name: 'AzureAd__ClientId'
          value: bffClientId
        }
        {
          name: 'OrdersApi__BaseUrl'
          value: ordersApiBaseUrl
        }
        {
          name: 'OrdersApi__Scope'
          value: ordersApiScope
        }
        {
          name: 'Cors__AllowedOrigin'
          value: allowedOrigin
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          // Distinguishes this service from the API inside the shared App Insights component,
          // so both appear as separate nodes on the application map while their traces still join.
          name: 'OTEL_SERVICE_NAME'
          value: 'orders-bff'
        }
      ]
    }
  }
}

@description('Principal ID of the BFF managed identity. Consumed by entraAssignments.bicep to grant it Orders.FullAccess on the API.')
output principalId string = bffWebApp.identity.principalId

@description('Default hostname of the BFF, baked into the SPA build.')
output defaultHostName string = bffWebApp.properties.defaultHostName
