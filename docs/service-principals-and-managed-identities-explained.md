# Service principals and managed identities, explained

Part 1 of 2.

- **This doc** — the object model: what a service principal *is*, and where managed identities fit
- [System-assigned vs user-assigned](managed-identity-types-explained.md) — the choice, the traps,
  and the Bicep

---

## The problem

Your Web App needs to talk to SQL. SQL needs to know who's calling. The obvious answer is a username
and password in the connection string, and it's the wrong one for reasons you already know: the
password ends up in config, in a repo, in a screenshot, in someone's shell history. It expires at
3am. Rotating it means a coordinated change across every consumer.

Entra ID's answer is to give the *application* an identity, the same way it gives a person one. Once
your app has an identity, SQL can grant permissions to that identity, and nothing anywhere holds a
password.

The confusing part is that Entra has **four names** for pieces of this, and they overlap:

| Name | What it actually is |
|---|---|
| **App registration** | The thing you create in the portal. Creates *two* objects, below. |
| **Application object** | The global blueprint. One per app, lives in the tenant that made it. |
| **Service principal** | The local instance. This is the thing that gets permissions. |
| **Enterprise application** | The portal's name for a service principal. Same object, different blade. |
| **Managed identity** | A service principal that Azure creates, owns, and holds the credential for. |

That's five rows for four names, which tells you something about how clear this is.

---

## The object model

If you write software, the analogy is exact:

```
Application object  ──►  is a CLASS
Service principal   ──►  is an INSTANCE of that class, one per tenant
```

Microsoft says this in as many words: *"An application object is used as a template or blueprint to
create one or more service principal objects... Similar to a class in object-oriented programming."*

The application object holds what's true everywhere: the app's display name, its redirect URIs, the
app roles it declares, the scopes it exposes. The service principal holds what's true *in one
tenant*: who's assigned to which role, what the app consented to, whether it's enabled.

For a single-tenant app — which everything in this repo is — there's exactly one service principal,
in your tenant, and the distinction feels like bureaucracy. It stops feeling like bureaucracy the
moment you need to grant something a permission, because **permissions attach to the service
principal, never to the application object.**

### Three kinds of service principal

Entra has exactly three, and it's worth knowing which one you're looking at:

- **Application** — the local instance of an app registration. `entraApps.bicep` creates three of
  these.
- **Managed identity** — a service principal that has *no application object at all*. Azure creates
  it, Azure holds its credential, and you can't edit it directly. The `identity: { type:
  'SystemAssigned' }` block on the Web App creates one of these.
- **Legacy** — predates app registrations. You will not meet one.

That middle row is the whole idea of managed identity: **a service principal with the credential
problem solved by someone else.** Microsoft is explicit that there's no app object behind it:

> *"Managed identities don't have an application object in the directory... Instead, Microsoft Graph
> permissions for managed identities need to be granted directly to the service principal."*

Which is why, when you want to give a managed identity a Graph permission, the portal's familiar
"API permissions" blade isn't there — you have to POST to Graph directly. Same for app roles.

---

## How a workload proves it's itself

Every one of these ends up doing the same thing: presenting proof to Entra, getting back a JWT,
sending that JWT to SQL or the Orders API. What differs is only the proof.

| Proof | Who holds it | Expires | Used here |
|---|---|---|---|
| Client secret | You. In config somewhere. | Yes, and it will surprise you | Nowhere. Deliberately. |
| Certificate | You. Better, still yours to rotate. | Yes | Nowhere. |
| Federated credential | Nobody — a trusted external IdP vouches | No | GitHub Actions → Azure |
| Managed identity | Azure, invisibly | No, from your side | Web App → SQL; BFF → Orders API |

**Federated credential** is worth understanding because it's already wired up here. You tell Entra:
"trust tokens from GitHub's OIDC issuer, but only when the subject claim is exactly
`repo:pedroabz/DEVOPS-LAB:ref:refs/heads/main`." GitHub mints a short-lived token describing the
workflow run, Entra swaps it for an access token. No secret exists on either side. Microsoft's
warning here is worth quoting because it's the failure everyone hits:

> *"The Federated Identity Credential `issuer`, `subject`, and `audience` values must
> case-sensitively match the corresponding `issuer`, `subject` and `audience` values contained in
> the token being sent."*

Federated credentials can go on **either** an app registration **or** a user-assigned managed
identity. Not on a system-assigned one.

**Managed identity** is the same secret-free outcome, but only inside Azure. The credential is real
— Microsoft says it's certificate-based, 90-day expiry, rolled at 45 days — you just never see it,
and they reserve the right to change how it works. The App Service platform injects two environment
variables into your app:

- `IDENTITY_ENDPOINT` — a local URL that mints tokens
- `IDENTITY_HEADER` — a rotating value you must send back as `X-IDENTITY-HEADER`, to stop a
  server-side request forgery bug in your app from turning into a token leak

`DefaultAzureCredential` in the Azure SDK finds those variables and uses them. Locally they don't
exist, so it falls back to your `az login`. That's why the same connection string works in both
places — and it's also why *managed identity has no local-development story of its own*. On your
laptop you are authenticating as Pedro, not as the app.

---

## The trap: three GUIDs, and picking the wrong one

An app registration produces **three different identifiers**, and they are all GUIDs, and Azure will
happily accept the wrong one in several places.

```
App registration "sp-devopslab-api-dev"
├── Application object
│     ├── object ID   f1e2...   ← identifies the BLUEPRINT. Rarely what you want.
│     └── appId       a3b4...   ← the "client ID". Public. Goes in tokens as the audience.
└── Service principal
      └── object ID   c5d6...   ← identifies the INSTANCE. This is what gets permissions.
```

The client ID (`appId`) is shared between the application object and its service principal, so it's
the one that appears in config. `appService.bicep` passes `ordersApiClientId` to the API so it can
validate that incoming tokens have the right audience. Correct use.

The object IDs are *different from each other*, and this is where it bites. An app role assignment —
`Microsoft.Graph/appRoleAssignedTo`, which `entraAssignments.bicep` uses five times — needs
`resourceId` to be the **service principal's** object ID of the API. Give it the application
object's ID and the deployment fails on an invalid principal. Give it the client ID and it also
fails. The module already gets this right, and the comment in it exists because it's easy to not.

A managed identity has only one ID you'll ever use: `principalId`, which is its service principal's
object ID. `bffAppService.bicep` outputs exactly that, and `entraAssignments.bicep` consumes it as
`principalId` on the role assignment. So one role assignment holds two object IDs from two different
kinds of principal, which is precisely as confusing as it sounds.

### How to tell you got it right

```bash
# The service principal object ID for an app, given its client ID:
az ad sp list --filter "appId eq '<client-id>'" --query '[0].id' -o tsv

# The managed identity's principal ID:
az webapp identity show -g rg-devopslab-dev-spc -n app-bff-devopslab-dev-spc-pabz --query principalId -o tsv

# What actually got assigned, after deploying:
az rest -m GET -u "https://graph.microsoft.com/v1.0/servicePrincipals/<api-sp-object-id>/appRoleAssignedTo"
```

That last one is the honest test. It lists what Entra thinks is true, rather than what your template
says.

### The related trap: display names are not identities

App display names aren't unique in a tenant. Microsoft's own docs warn about it twice — once telling
you to verify you got the right SP when searching by name, and once, more sharply, about App
Service:

> *"Ensure that your app service name doesn't duplicate any existing app registrations, which leads
> to Principal ID conflicts."*

A system-assigned managed identity is always named after its resource. So `app-devopslab-dev-spc-pabz`
is both a Web App and an Entra service principal. If you ever create an app registration with that
same name, anything that resolves principals by display name — Azure SQL's `CREATE USER ... FROM
EXTERNAL PROVIDER` does exactly this — becomes ambiguous. More on that in Part 2.

---

## What's in this repo right now

| Thing | Kind | Where | Credential |
|---|---|---|---|
| `sp-devopslab-github-dev` | App registration + SP | created in setup, not Bicep | Federated to GitHub OIDC |
| Orders API | App registration + SP | `entraApps.bicep` | None — it's a resource server, it only validates |
| BFF | App registration + SP | `entraApps.bicep` | None |
| SPA | App registration + SP | `entraApps.bicep` | None — public client, can't keep one |
| Orders API Web App | Managed identity | `appService.bicep` | Azure's |
| BFF Web App | Managed identity | `bffAppService.bicep` | Azure's |

Note the shape: the app registrations exist to *describe* things — audiences, roles, scopes,
redirect URIs. The managed identities exist to *be* things — the actual callers that show up at SQL
and at the Orders API. An app registration is a noun; a managed identity is a subject.

The BFF has both, and they're separate objects doing separate jobs. Its **app registration** is what
the SPA gets a token *for*, and where the user-facing app roles are declared. Its **managed
identity** is what it authenticates *as* when it calls the Orders API. They share a Web App and
nothing else.

---

## Trade-offs

**What the managed-identity approach gains you:** no secret exists, so no secret can leak, expire,
or need rotating. The audit trail names a resource rather than "whoever had the password".

**What it costs:**

- Nothing in money. Microsoft: *"Managed identities can be used at no extra cost."*
- Real complexity in the object model. You now have to know which of three GUIDs a given field wants.
- No local development story. Your laptop can't be a managed identity, so dev and prod authenticate
  by different paths, and a bug can live in the gap.
- New failure modes that don't look like auth failures. Part 2 is mostly about those.

**What it explicitly doesn't buy you:** anything cross-tenant — *"managed identities don't currently
support cross-directory scenarios"* — and anything running outside Azure *on the injected
credential*. Your laptop, a GitHub runner and another cloud have no `IDENTITY_ENDPOINT`, so none of
them can authenticate that way.

Note what that does **not** say. It doesn't say those workloads need an app registration. A
federated credential fixes the outside-Azure problem, and it goes on either kind of principal — an
app registration or a user-assigned managed identity, with GitHub Actions supported on both.
`sp-devopslab-github-dev` is an app registration because that's the conventional path and what
`azure-setup.md` §8.1 does, not because it had to be. The one structural argument for the choice is
mundane: a user-assigned identity is an Azure resource needing a resource group to live in, and this
identity's job is to *create* the resource group.

---

Next: [system-assigned vs user-assigned](managed-identity-types-explained.md) — the choice you
actually have to make, and the two silent failures that come with it.
