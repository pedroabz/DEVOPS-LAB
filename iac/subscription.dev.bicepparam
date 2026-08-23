using './main.bicep'

// Resource names are NOT set here — main.bicep derives them from these inputs
// using the convention in docs/prd/v0-foundations.md §7.

param envName = 'dev'
param location = 'spaincentral'

param sqlEntraAdminName = 'sg-devopslab-sql-admins'
param sqlEntraAdminObjectId = 'cffa7571-2a23-417e-b71f-8cff180f7af8'

// Your public IP, for the SQL firewall rule. Kept out of git: set CLIENT_IP in .env
// (gitignored) and source it before deploying — scripts/deploy-dev.sh does that for you.
param clientIpAddress = readEnvironmentVariable('CLIENT_IP')
