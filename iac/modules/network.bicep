targetScope = 'resourceGroup'

@description('Name of the virtual network.')
param vnetName string

@description('Azure region.')
param location string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location

  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }

    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.0.1.0/24'

          // App Service injects its own network interfaces here, which it can only
          // do if the subnet is handed over to it. Nothing else can use this subnet.
          delegations: [
            {
              name: 'appservice'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]

          // Makes traffic leaving this subnet for Azure SQL carry the subnet's
          // identity, which is what the SQL virtual network rule matches on.
          serviceEndpoints: [
            {
              service: 'Microsoft.Sql'
            }
          ]
        }
      }
    ]
  }
}

@description('Resource ID of the app subnet. Consumed by the App Service (to integrate into it) and by SQL (to trust it).')
output appSubnetId string = vnet.properties.subnets[0].id
