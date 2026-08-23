targetScope = 'resourceGroup'

param location string
param name string
param applicationInsightsName string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: name
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'

  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

@description('Resource ID of the Log Analytics workspace. Needed to point diagnostic settings at it.')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('Customer ID (workspace ID) of the Log Analytics workspace.')
output logAnalyticsCustomerId string = logAnalytics.properties.customerId

@description('Resource ID of the Application Insights component.')
output applicationInsightsId string = applicationInsights.id

@description('Connection string for Application Insights. Consumed as the APPLICATIONINSIGHTS_CONNECTION_STRING app setting by the API (v1) and the Functions app (v2).')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
