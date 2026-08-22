targetScope = 'resourceGroup'

@description('Globally unique name of the SQL logical server.')
param sqlServerName string

@description('Azure region for the server and database.')
param location string

@description('Display name of the Entra group that administers SQL.')
param sqlEntraAdminName string

@description('Object ID of the Entra group that administers SQL.')
param sqlEntraAdminObjectId string

@description('Name of the database.')
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

// Allow other Azure services (the Web App, and later the Function App) to reach this server.
// The 0.0.0.0-0.0.0.0 range is a special case: it does NOT mean "the whole internet", it means
// "requests originating from inside Azure". Replaced by private endpoints in v4.
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2025-01-01' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// General Purpose SERVERLESS (the _S_ in GP_S_Gen5). Compute autoscales between minCapacity and
// sku.capacity, is billed per vCore-second, and deallocates entirely after autoPauseDelay minutes
// of inactivity — at which point only storage is billed. See docs/adr/0001.
//
// ⚠️ RESUMING FROM PAUSE TAKES 30-60 SECONDS, AND THE FIRST CONNECTION USUALLY TIMES OUT
//    RATHER THAN WAITING.
//
//    This is inherent to auto-pause, not a defect, and it shapes everything downstream:
//      - The API (v1) MUST use EF Core `EnableRetryOnFailure` with a window > 60s, or the first
//        request after an idle period returns a 500 and the app looks broken.
//      - A SQL-touching health check belongs on READINESS, never liveness — a liveness probe that
//        fails during resume can trigger a restart loop.
//      - Pipeline smoke tests must warm the database first, or they will be intermittently red.
//      - Anything holding a connection open (monitoring, pool keepalive, a stray SSMS window)
//        prevents pausing entirely and silently keeps the meter running.
//
//    Set autoPauseDelay to -1 to disable pausing. That removes the latency and the savings both.
resource sqlDatabase 'Microsoft.Sql/servers/databases@2025-01-01' = {
  parent: sqlServer
  name: databaseName
  location: location

  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1 // maximum vCores it can scale UP to
  }

  properties: {
    // Minimum vCores while active. Bicep has no float type, so a decimal must be smuggled through
    // json() — a bare 0.5 is a parse error (BCP020).
    minCapacity: json('0.5')

    // Minutes of inactivity before compute is deallocated. 60 is the minimum Azure permits.
    autoPauseDelay: 60

    maxSizeBytes: 2147483648 // 2 GiB — ample for the lab, and storage is the only idle cost
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
  }
}

@description('Fully qualified domain name of the SQL server, e.g. sql-xxx.database.windows.net.')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('Name of the SQL server.')
output sqlServerName string = sqlServer.name

@description('Name of the database.')
output databaseName string = sqlDatabase.name

@description('ADO.NET connection string using Entra managed-identity auth. No password: the Web App authenticates as its managed identity. The identity still needs a database user created via T-SQL (see task 6.5).')
output connectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabase.name};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=90;'
