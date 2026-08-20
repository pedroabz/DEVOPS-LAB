param sqlServerName string
param location string
param sqlEntraAdminName string
param sqlEntraAdminObjectId string
param databaseName string


resource sqlServer 'Microsoft.Sql/servers@2025-01-01' = {
  name: sqlServerName
  location: location

  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'

    administrators: {
      administratorType: 'ActiveDirectory'
      login: sqlEntraAdminName
      sid: sqlEntraAdminObjectId
      tenantId: tenant().tenantId
      principalType: 'Group'
      azureADOnlyAuthentication: true
    }
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2025-01-01' = {
  parent: sqlServer
  name: databaseName
  location: location

  sku: {
    name: 'S0'
    tier: 'Standard'
  }
}
