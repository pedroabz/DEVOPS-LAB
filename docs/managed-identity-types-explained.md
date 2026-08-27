# System-assigned vs user-assigned managed identity, explained

Part 2 of 2.

- [Service principals and managed identities](service-principals-and-managed-identities-explained.md)
  — the object model
- **This doc** — which type to use, what silently breaks, and what goes in Bicep

---

## The problem

You've decided the Web App authenticates as itself rather than with a password. Azure now asks a
question you didn't want: should the identity **belong to the app**, or should it be **its own
resource that the app borrows**?

It sounds like a naming preference. It isn't — it's a lifecycle decision, and it determines whether
your deployments work on the first run or the second.

---

## How it actually works

Both types produce the same thing at runtime: a service principal in Entra, a token endpoint inside
your app, no secret anywhere. The difference is entirely about **who owns the object**.

```
SYSTEM-ASSIGNED
  Web App ──owns──► its identity
  delete the Web App  ──►  identity is deleted too
  name = the Web App's name, always
  one per resource, maximum

USER-ASSIGNED
  identity (a resource in your RG) ◄──borrowed by── Web App
                                   ◄──borrowed by── Function App
                                   ◄──borrowed by── VM
  delete the Web App  ──►  identity survives, untouched
  name = whatever you called it
  many per resource, and one identity across many resources
```

Microsoft's table, verbatim:

| | System-assigned | User-assigned |
|---|---|---|
| Creation | Created as part of an Azure resource | Created as a stand-alone Azure resource |
| Life cycle | Deleted with the parent resource | Independent. Must be explicitly deleted |
| Sharing | *"Can't be shared."* One resource only | *"Can be shared"* across resources |

### The one that decides it: chicken and egg

Here's the argument that actually matters, and it's not about tidiness.

A system-assigned identity **doesn't exist until the resource exists**. So you cannot grant it
permissions in advance. Your deployment has to: create the Web App → read back its `principalId` →
create the role assignment. That's a dependency chain, and Bicep handles it (`bffAppService.bicep`
outputs `principalId`, `entraAssignments.bicep` consumes it, `main.bicep` orders them). But it means
the deploying identity needs permission to *create role assignments*, not just resources.

A user-assigned identity can be created and permissioned **first**, months before the app exists.
Microsoft's phrasing:

> *"User-assigned identities and their role assignments can be configured in advance of the
> resources that require them... As system-assigned identities are created and deleted along with
> the resource, role assignments can't be created in advance. This sequence can cause failures while
> deploying infrastructure if the user creating the resource doesn't also have access to create role
> assignments."*

Microsoft's overall recommendation is blunter than you'd expect: *"User-assigned managed identities
... are the recommended managed identity type for Microsoft services."* They recommend
system-assigned in exactly two cases: when you need audit logs to name the specific resource, and
when you want permissions to die with the resource.

---

## The trap: the 24-hour token cache

This is the one that will waste your afternoon, and it's not in any error message.

You deploy. You assign `Orders.FullAccess` to the BFF's managed identity. The BFF calls the Orders
API. It gets a **403**. You check the assignment — it's there, in the portal, correct. You redeploy.
Still 403. You restart the app. Still 403.

Nothing is wrong. Azure caches managed identity tokens **server-side**, and role and group
memberships live *inside* the token as claims:

> *"The back-end services for managed identities maintain a cache per resource URI for around 24
> hours... It's currently not possible to force a managed identity's token to be refreshed before
> its expiration. If you change a managed identity's group or role membership to add or remove
> permissions, you might need to wait up to around 24 hours."*

Restarting your app does not help — the cache isn't in your app. Clearing your own token cache does
not help. There is no supported way to flush it.

This lands squarely on v2, where the BFF's managed identity is granted an app role on the Orders
API. The docs for that exact operation carry their own warning: *"any changes to the managed
identity's roles can take significant time to process."*

### How to tell it's the cache and not your config

Get the token the platform is handing your app and read it. From the app's Kudu console:

```bash
curl -s -H "X-IDENTITY-HEADER: $IDENTITY_HEADER" \
  "$IDENTITY_ENDPOINT?resource=api://<orders-api-client-id>&api-version=2019-08-01"
```

Paste the `access_token` into jwt.ms and look at the `roles` claim.

- **`roles` is missing or wrong, but the portal shows the assignment** → it's the cache. Wait.
- **`roles` is correct but the API still 403s** → it's your API's authorization policy, not Entra.
- **No token at all** → the assignment or the audience is wrong; see below.

That distinction is the whole value of the test, because both cases present identically as a 403.

**How to avoid it:** make role assignments *before* the workload first asks for a token. With
system-assigned that's impossible by construction — the identity doesn't exist yet. With
user-assigned it's a matter of ordering. If this becomes painful in v2, it's the strongest argument
for switching the BFF to a user-assigned identity.

---

## The second trap: which identity, when there's more than one

A resource can have a system-assigned identity *and* several user-assigned ones at the same time.
The token endpoint then has to guess, and it refuses to:

> *"If system assigned managed identity isn't enabled, and only one user assigned managed identity
> exists, IMDS defaults to that single user assigned managed identity. If another user assigned
> managed identity is assigned to the resource for any reason, your requests will start failing with
> the error `Multiple user assigned identities exist, please specify the clientId / resourceId of
> the identity in the token request`."*

Read that carefully: **adding a second identity breaks code that worked with one.** Nothing about
the first identity changed. Microsoft's advice — *"We highly recommend you explicitly specify an
identity in your request, even if only one user assigned managed identity currently exists"* — is
the tell that this catches people.

In .NET this means passing the client ID to `DefaultAzureCredential`. In a SQL connection string it
means adding `User Id=<client-id-of-the-uami>;` — because `Authentication=Active Directory Default`
alone reaches for the *system-assigned* identity:

> *"If the app is deployed, the driver gets a token from the app's system-assigned managed identity.
> The driver can also authenticate with a user-assigned managed identity if you include `User
> Id=<client-id-of-user-assigned-managed-identity>;` in your connection string."*

The connection string in `sqlServer.bicep` has no `User Id`. That is correct today and would become
a silent bug the moment the Web App gained a user-assigned identity.

---

## The third trap: SQL doesn't take role assignments

Managed identity access to most Azure services is an ARM role assignment, which Bicep can express.
Azure SQL is not one of those services. Database access is a **contained database user**, created in
T-SQL:

```sql
CREATE USER [app-devopslab-dev-spc-pabz] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-devopslab-dev-spc-pabz];
ALTER ROLE db_datawriter ADD MEMBER [app-devopslab-dev-spc-pabz];
```

Bicep cannot do this. It's already inventory row 11 and task 6.5, so this isn't news — but two
details matter and aren't recorded anywhere yet.

**One: the name in the brackets is a display name, resolved through Microsoft Graph.** For a
system-assigned identity it's the Web App's name. For a user-assigned identity it's the identity
resource's name.

**Two — and this is the real trap — *who runs the statement* changes whether it works at all.**

When *you* run it signed in as an Entra user, Azure SQL impersonates you and queries Graph with your
permissions. It works. When a **service principal** runs it — say, a GitHub Actions job
authenticating as `sp-devopslab-github-dev` — impersonation is impossible:

> *"This flow isn't possible with service principals, because an application can't impersonate
> another application. Instead, the SQL engine tries to use its server identity... The server
> identity must exist and have the Microsoft Graph query permissions or the operations fail."*

The failure looks like this:

```
Msg 33134, Level 16, State 1, Line 1
Principal 'test-user' could not be resolved.
Error message: 'Server identity is not configured...'
```

`sqlServer.bicep` gives the logical server **no identity at all**. That's fine right now — `api-cd`
only runs `dotnet ef database update`, which touches schema, not principals. It stops being fine the
day you try to automate the `CREATE USER`. Fixing it then means: give the server an identity, and
have someone with **Privileged Role Administrator** grant it `User.Read.All`,
`GroupMember.Read.All`, and `Application.Read.All` on Graph — a tenant-level privilege, grantable
only by PowerShell, *"You can't grant these permissions by using the Azure portal."*

There's an escape hatch worth knowing: `CREATE USER [name] WITH SID = <object-id>, TYPE = E` creates
the user **without validation**, so no Graph lookup happens. You supply the object ID and take
responsibility for it being right.

---

## What you configure in Bicep

### On the resource that uses the identity

| Property | What it does | For us |
|---|---|---|
| `identity.type: 'SystemAssigned'` | Azure creates an identity owned by this resource | **What both Web Apps use today** |
| `identity.type: 'UserAssigned'` | Borrow identities listed in `userAssignedIdentities` | Not today |
| `identity.type: 'SystemAssigned, UserAssigned'` | Both at once. Note the space — that's the literal allowed value | No. Triggers the ambiguity trap for no benefit |
| `identity.type: 'None'` | Removes it. A system-assigned identity is *deleted from Entra* | Never set explicitly — just omit the block |
| `identity.userAssignedIdentities` | Map of `<resource id>: {}`. The empty object is required | n/a |
| `keyVaultReferenceIdentity` | Which identity resolves `@Microsoft.KeyVault(...)` app settings | n/a — no Key Vault, by decision |

Reading back: `webApp.identity.principalId` for system-assigned. For user-assigned it's nested under
the resource ID key, which is why `bffAppService.bicep`'s one-line output would get uglier if you
switched.

### The user-assigned identity resource itself, if you ever add one

`Microsoft.ManagedIdentity/userAssignedIdentities`, latest stable API `2024-11-30`.

| Property | What it does | For us |
|---|---|---|
| `name` | Also its Entra display name, and the name SQL's `CREATE USER` resolves | Would need the CAF `id-` prefix |
| `location` | It's a regional resource | Same as everything else. Note the *service principal* is global — a region outage only affects managing the identity, not using it |
| `.properties.principalId` | Object ID. What role assignments target | The output you'd consume |
| `.properties.clientId` | What code and connection strings name | Would become an app setting |

Deliberately not listed: there is almost nothing else. A user-assigned identity is a name and a
region. Its whole substance is what you assign *to* it.

One constraint that reads like a footnote and isn't: *"Moving a user-assigned managed identity to a
different resource group isn't supported."* You'd have to create a new one and re-grant everything.

---

## Trade-offs

**System-assigned gains you:** nothing to name, nothing to clean up, and permissions that die with
the resource. Audit logs point at the specific app. One less resource in `iac/`.

**System-assigned costs you:** the chicken-and-egg ordering; a `principalId` that changes every time
the resource is recreated — which orphans the SQL user and every role assignment, and the orphans
don't clean themselves up (*"Role assignments aren't automatically deleted when either
system-assigned or user-assigned managed identities are deleted"*, showing as "Identity not found").
The identity is also soft-deleted for 30 days and counts against tenant quota the whole time.

**User-assigned gains you:** permissions configurable in advance; a stable `principalId` across
teardown and rebuild, which for a lab that gets destroyed and recreated is a genuine convenience;
one identity shared by API, BFF and (later) Functions, so one SQL user instead of three.

**User-assigned costs you:** a resource with its own lifecycle that `az group delete` will happily
leave behind, joining Entra objects on the list of things `teardown-entra.sh` has to know about. Two
more IDs to keep straight. And a shared identity means shared permissions — Microsoft: *"all the
permissions granted to the managed identity are now available to the Azure resource."* The BFF would
inherit the API's database access whether it needs it or not, which is exactly the boundary v2 went
to some trouble to draw.

**Neither buys you:** local development, cross-tenant access, or any escape from the 24-hour cache.

---

## What I'd do here

A recommendation, not a decision.

1. **Keep system-assigned for both Web Apps** (inventory rows 7 and v2 row 6). The chicken-and-egg
   problem is already solved in `main.bicep`, the permission boundary between API and BFF is
   deliberate, and there are two resources — not the ten where sharing starts paying. Changing it
   now buys complexity and no capability.

2. **Write down the cache.** The 24-hour delay is the single most likely way v2's M3 milestone
   ("BFF acquires a token") looks broken when it isn't. It belongs in the v2 PRD next to the app
   role assignments, not discovered live at 403 o'clock.

3. **Leave `sqlServer.bicep` without a server identity, and record why.** The `CREATE USER` in task
   6.5 is a human running sqlcmd, so it works. The moment that moves into `api-cd` it stops working,
   and Msg 33134 will not suggest that the *server* is what's misconfigured. A one-line comment
   there is cheap insurance.

4. **Revisit user-assigned when v3 adds Functions.** Three services wanting the same database means
   three `CREATE USER` statements you can't automate. That's the point where one shared identity
   starts earning its keep — and if you're teardown-and-rebuilding often by then, the stable
   `principalId` matters too.

5. **Don't add a second identity to a resource that has one.** If you ever do go user-assigned, go
   *fully* — replace, never add alongside. That's the ambiguity trap, and it fails at runtime, not
   at deploy time.
