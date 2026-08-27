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

// --- v2: identity, frontend, BFF ---

// Static Web Apps is unavailable in spaincentral. westeurope is the closest supported region;
// eastus2 is the fallback if this subscription is blocked there as it was for SQL.
param staticWebAppLocation = 'westeurope'

// Object IDs are identifiers, not secrets — the SQL admin group's is already committed above.
param adminUserObjectId = 'afddd92f-091f-497b-9fdc-50b35a214aba'

// TODO: replace after running scripts/create-test-users.sh, which prints both object IDs.
// Deployment will fail with an invalid-principal error until these are real.
param readerTestUserObjectId = '00000000-0000-0000-0000-000000000000'
param adminTestUserObjectId = '00000000-0000-0000-0000-000000000000'
