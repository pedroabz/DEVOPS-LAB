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

// Static Web Apps is unavailable in spaincentral. westeurope was the closest supported region,
// but this subscription is blocked there — RequestDisallowedByAzure, exactly as it was for SQL.
// eastus2 is the fallback. The SPA is static files behind a global CDN, so origin region barely
// affects latency.
param staticWebAppLocation = 'eastus2'

// Object IDs are identifiers, not secrets — the SQL admin group's is already committed above.
param adminUserObjectId = 'afddd92f-091f-497b-9fdc-50b35a214aba'

// Created by scripts/create-test-users.sh. ana.reader@ and miguel.admin@ respectively.
param readerTestUserObjectId = '76e50907-3754-4918-9e43-ef9aa8978f76'
param adminTestUserObjectId = '84e1615b-fc30-43f4-b21b-e3ce8fd2d666'
