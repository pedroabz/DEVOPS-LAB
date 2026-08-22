targetScope = 'subscription'

param resourceGroupName string
param logAnalyticsName string
param location string = 'westeurope'
param ordersAppInsightsName string

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
