-- Gives the Web App's managed identity access to the Orders database.
-- Inventory row 11. See docs/prd/v0-foundations.md task 6.5 for the open question of
-- WHERE this should run — by hand, from the pipeline, or from a Bicep deploymentScript.
--
-- WHY THIS IS NOT BICEP
--   Managed identity handles authentication. It does not handle authorization inside SQL.
--   Azure SQL predates Azure RBAC and keeps its own permission model — database users and
--   roles — so "grant access" here is T-SQL, not an ARM role assignment. Bicep cannot
--   execute T-SQL.
--
--   Without this, the app authenticates fine and then gets:
--       Login failed for user '<token-identified principal>'
--
-- WHERE TO RUN IT
--   Against sqldb-orders-dev, NOT master.
--   Signed in as a member of sg-devopslab-sql-admins (that's you).
--   VS Code: MS SQL extension, "Microsoft Entra ID - MFA" auth.
--
-- NAMING
--   For a system-assigned managed identity, the principal's name in Entra is the name of
--   the resource that owns it. So the user is named after the Web App itself.

-- ---------------------------------------------------------------------------
-- 1. Create the database user
-- ---------------------------------------------------------------------------
-- FROM EXTERNAL PROVIDER means "Entra validates this identity", so no password is
-- stored here. The user is a permission record, not a credential.

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app-devopslab-dev-spc-pabz')
BEGIN
    CREATE USER [app-devopslab-dev-spc-pabz] FROM EXTERNAL PROVIDER;
END
GO

-- ---------------------------------------------------------------------------
-- 2. Grant it exactly what the API needs
-- ---------------------------------------------------------------------------
-- Read and write rows. Deliberately NOT db_owner or db_ddladmin: the pipeline runs
-- migrations as sp-devopslab-github-dev, so the app itself never needs to change schema.

IF IS_ROLEMEMBER('db_datareader', 'app-devopslab-dev-spc-pabz') = 0
    ALTER ROLE db_datareader ADD MEMBER [app-devopslab-dev-spc-pabz];
GO

IF IS_ROLEMEMBER('db_datawriter', 'app-devopslab-dev-spc-pabz') = 0
    ALTER ROLE db_datawriter ADD MEMBER [app-devopslab-dev-spc-pabz];
GO

-- ---------------------------------------------------------------------------
-- 3. Verify
-- ---------------------------------------------------------------------------

SELECT
    p.name,
    p.type_desc,
    USER_NAME(rm.role_principal_id) AS role_name
FROM sys.database_principals p
LEFT JOIN sys.database_role_members rm ON rm.member_principal_id = p.principal_id
WHERE p.name = 'app-devopslab-dev-spc-pabz';
GO

-- Expect two rows: EXTERNAL_USER in db_datareader, and in db_datawriter.


-- ===========================================================================
-- FALLBACK — only if step 1 fails
-- ===========================================================================
-- If you get:
--     Principal 'app-devopslab-dev-spc-pabz' could not be found or this principal type
--     is not supported.
--
-- ...then FROM EXTERNAL PROVIDER could not resolve the name through Microsoft Graph.
-- Azure SQL needs directory read permission to look up service principals, and a plain
-- personal-tenant setup often lacks it. Rather than granting that, create the user from
-- the identity's object ID directly — no Graph lookup involved.
--
-- The SID below is the Web App's managed identity principal ID
--   2d9eb90d-d77a-49ea-a1cb-d8e1af55354c
-- converted to the little-endian byte order SQL expects. If you ever recreate the Web
-- App the identity changes, and this value goes stale.
--
-- IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app-devopslab-dev-spc-pabz')
-- BEGIN
--     CREATE USER [app-devopslab-dev-spc-pabz]
--         WITH SID = 0x0DB99E2D7AD7EA49A1CBD8E1AF55354C, TYPE = E;
-- END
-- GO
