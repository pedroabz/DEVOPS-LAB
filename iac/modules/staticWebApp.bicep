targetScope = 'resourceGroup'

@description('Name of the Static Web App.')
param staticWebAppName string

@description('''Azure region. Static Web Apps is NOT available everywhere — only Central US,
East US 2, West US 2, West Europe and East Asia. spaincentral, which every other resource here
uses, is not among them, so this is the one resource with its own location.''')
param location string

resource staticWebApp 'Microsoft.Web/staticSites@2024-11-01' = {
  name: staticWebAppName
  location: location

  sku: {
    name: 'Free'
    tier: 'Free'
  }

  properties: {
    // repositoryUrl / branch / provider are deliberately unset. Setting them makes Static Web
    // Apps generate a GitHub Actions workflow file and commit it into the repository, which
    // would appear as an unexplained file nobody wrote. spa-cd.yml deploys this instead.
    stagingEnvironmentPolicy: 'Disabled'
    allowConfigFileUpdates: true
  }
}

@description('Generated hostname, e.g. something-something.azurestaticapps.net. Becomes the SPA redirect URI and the BFF CORS origin.')
output defaultHostname string = staticWebApp.properties.defaultHostname

@description('Name of the Static Web App, so spa-cd.yml can fetch its deployment token at deploy time rather than storing one as a repo secret.')
output name string = staticWebApp.name
