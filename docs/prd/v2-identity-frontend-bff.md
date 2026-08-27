# PRD — v2: Identity, frontend, and a BFF

**Status:** decisions settled — ready to build
**Depends on:** v0 (deployed), v1 (API running)

> This is the **next** version. Event-driven work (Service Bus + Functions) moves to v3, APIM to v4,
> production hardening to v5.

---

## 1. Summary

Put a real identity story in front of the Orders API. A React form signs a user in with Entra ID,
talks to a **backend-for-frontend** that enforces RBAC, and the BFF calls the Orders API with a
**token it obtains itself** — never the user's token forwarded on.

The point is the token boundary. Today anything holding a valid token can call the API directly.
After this, the API trusts one caller — the BFF — and the BFF is the only thing that knows about
users. You keep direct admin access, so you can still `curl` the API; that stays a deliberate
exception rather than an accident.

Everything, including the Entra app registrations, is Bicep.

## 2. Goals

1. A user signs in with Entra ID and uses the app without ever holding a credential.
2. The BFF authorises **per user** — an ordinary user and an admin get different answers.
3. The BFF gets a **fresh token scoped to the API**. The user's token is never forwarded.
4. Entra app registrations, roles and assignments are declared in Bicep, not clicked.
5. **No credentials anywhere at all** — not a secret, not a certificate, not even a federated
   credential. The BFF authenticates as its system-assigned managed identity, which needs none.
6. You retain direct API access as an admin, by a route ordinary users do not have.

## 3. Non-goals

| Deferred | To |
|---|---|
| Blob storage and product images | v3.5 — explicitly next, per your note |
| APIM in front of anything | see §4 decision 6 |
| Multi-tenant / external identities (B2C) | not planned |
| Refresh-token rotation, sign-out everywhere, session revocation | v4 |
| A designed UI. This is one form | — |

---

## 4. Decisions that block the build

**Nothing gets written until these are settled.** Each changes the architecture, not just the code.

### 4.1 Where does the token live in the browser?

You said "get a bearer token with OAuth as a user." That's one of two designs, and they're
meaningfully different.

| | **Token in the SPA** | **Token-less SPA (true BFF)** |
|---|---|---|
| How | MSAL.js does auth-code+PKCE, SPA holds an access token, sends it to the BFF as a bearer header | SPA has no token. BFF does the OAuth dance, keeps tokens server-side, gives the browser an HttpOnly session cookie |
| XSS exposure | Any script on the page can read the token | Nothing to steal; cookie is HttpOnly |
| Complexity | Lower. Standard MSAL React sample | Higher. Session store, CSRF protection, cookie config |
| Matches "BFF" | Partially | This is *why* the pattern exists |

Worth knowing: the modern reason to build a BFF at all is to keep tokens out of the browser. Doing
a BFF *and* holding tokens in the SPA gets you the extra hop without the main benefit.

**DECIDED: token in the SPA.** It only ever talks to the BFF, and this is not what the exercise is
about. MSAL's default is `sessionStorage`, which is per-tab and clears on close — prefer it over
`localStorage` unless you want the session to survive a browser restart.

### 4.2 How does the BFF authenticate to the API?

You said "a new token with managed identities". That works, and it has a consequence worth choosing
deliberately.

| | **Client credentials (managed identity)** | **On-Behalf-Of** |
|---|---|---|
| Token says | "I am the BFF" | "I am the BFF, acting for Ana" |
| API can authorise per user | ❌ no — every call looks identical | ✅ yes |
| Audit trail at the API | BFF only | user identity preserved |
| Secrets | none — MI, or MI as a federated credential | none, if the app registration federates to the MI |
| Complexity | low | higher; token cache per user, consent |

Client credentials means **all authorisation lives in the BFF**, and the API's only question is "are
you the BFF?". That is a legitimate and common design. It is also a real limitation: the API cannot
distinguish Ana from Miguel, so any per-user rule must be enforced upstream and cannot be
defended in depth.

**DECIDED: client credentials via managed identity.** The API never learns who the user is. All
per-user authorisation happens in the BFF; a request that reaches the API has already been approved.
The BFF therefore has full access to the API.

This is why there are **two separate sets of app roles** — see §4.3.

### 4.3 What is RBAC actually made of?

| Option | Mechanics | Notes |
|---|---|---|
| **App roles** on the app registration | Roles land in the `roles` claim | Purpose-built for this. Assigned per app |
| **Entra groups** | `groups` claim | Reuses org structure; claim can overflow past ~200 groups |
| **Both** | groups → app roles | Enterprise-typical, more moving parts |

**DECIDED: app roles.** And because of §4.2 there are two sets of them, on two different
registrations. Getting this wrong is the most likely way to build the wrong thing in M1:

| Registration | Roles | Assigned to | Answers the question |
|---|---|---|---|
| **BFF** | `Orders.Reader`, `Orders.Admin` | users | *what may this person do?* |
| **Orders API** | `Orders.FullAccess`, `Orders.Admin.Direct` | the BFF's service principal / you | *are you an allowed caller?* |

The Reader/Admin distinction lives entirely on the BFF. The API's roles are not about users at all —
one says "you are the BFF", the other says "you are Pedro with a direct token".

### 4.4 How do *you* keep direct API access?

The API needs to accept two very different callers:

- The **BFF**, presenting an app-only token (an `roles` claim from an app role assigned to its
  service principal)
- **You**, presenting a user token with an admin app role

Both are app roles on the API's registration; one is assigned to a service principal, the other to a
human. The API accepts either, and the *only* reason you get in is an explicit assignment that
ordinary users do not have.


### 4.5 Graph Bicep extension is in **preview**

**DECIDED: accept the preview.** It is what makes goal 4 possible. Breaking changes are permitted
and it is not covered by support; the fallback if a property turns out to be unsettable is an
`az ad` command in a pipeline step for that property only.

Note this does **not** cover Entra *users* — see §4.8.

### 4.6 Does APIM still make sense?

The old roadmap put APIM in v3 as the front door. A BFF is also a front door. Options: APIM in front
of the BFF, APIM between BFF and API, drop APIM, or defer it. Worth deciding now rather than
building something APIM later has to be retrofitted around.

**DECIDED: defer APIM to v4.** The BFF is not a universal front door — v3's Functions will react to
Service Bus and call the API without passing through it. APIM therefore sits in front of *the API*,
above both callers, and that only makes sense once both exist.

### 4.7 Where does the frontend run?

| Option | Cost | Notes |
|---|---|---|
| **Static Web Apps** | Free tier | Purpose-built for SPAs; has its own auth features you would deliberately not use |
| **Served by the BFF** | €0 extra | Simplest deployment, same origin, no CORS. Couples the two |
| **Second App Service** | €0 extra | An App Service plan hosts many apps — B1 can carry both |

**DECIDED: Static Web Apps**, free tier, in **`westeurope`** (falling back to `eastus2`).

> ⚠️ Static Web Apps is available in only five regions — Central US, East US 2, West US 2, West
> Europe, East Asia. **`spaincentral`, which every other resource uses, is not one of them.** This
> is the single resource in the project with its own location parameter.

Chosen over a second App Service because App Service will not serve a SPA correctly without help:
client-side routing means every unknown path has to fall back to `index.html`, or refreshing on
`/orders` returns 404. That needs a Node static server or explicit rewrite rules. Static Web Apps
does it natively, and costs nothing.

The SPA and BFF are still on different origins, so the BFF needs the SPA's hostname in its allowed
origins. That is a config value, not a design problem.

### 4.8 Test users

Proving `Orders.Reader` behaves differently from `Orders.Admin` needs two identities, and the tenant
currently has one.

The Graph Bicep extension *does* have a `Microsoft.Graph/users` type, but it is **read-only** —
`existing` is the only legal form. So creating users is still the one part of v2 that cannot be
Bicep, just not for the reason originally written here. Two cloud-only accounts created with `az ad user create` in a bootstrap
script, each assigned a different BFF app role — the assignment itself *is* Bicep, via
`appRoleAssignedTo`.

Their passwords are the only secrets introduced by this phase. They exist because interactive
sign-in needs a human credential; nothing in the running system uses them.

## 5. Target architecture

```
  browser
    │  1. sign in (auth code + PKCE)
    ▼
  Microsoft Entra ID ──────────────────────────────┐
    │  2. token for the BFF                        │
    ▼                                              │
  React SPA                                        │ 4. BFF asks for its OWN token
    │  3. call /api/orders  (bearer OR cookie)     │    for the Orders API,
    ▼                                              │    authenticating with its
  BFF  (App Service, managed identity)  ───────────┘    managed identity
    │        ├─ validates the user's token
    │        └─ RBAC: Orders.Reader / Orders.Admin
    │
    │  5. call with a DIFFERENT token, audience = Orders API
    ▼
  Orders API  ── accepts: BFF app role, or your admin app role
    │
    ▼
  Azure SQL  (managed identity, unchanged from v0)


  you ──── direct token for the Orders API (admin app role) ────────────┘
```

The one rule that defines this design: **the token in step 3 and the token in step 5 are different
tokens, with different audiences.** Nothing is forwarded.

## 6. Resource inventory

| Bicep | Live | # | Resource | Notes |
|:---:|:---:|---|---|---|
| ☑ | ☐ | 1 | Entra app registration — **SPA** | Public client, redirect URIs, no secret |
| ☑ | ☐ | 2 | Entra app registration — **BFF** | Exposes a scope for the SPA and declares the user-facing app roles. **No credentials of any kind** — a federated credential would only be needed for On-Behalf-Of, which §4.2 rules out |
| ☑ | ☐ | 3 | Entra app registration — **Orders API** | Resource server. Declares app roles |
| ☑ | ☐ | 4 | Service principals ×3 | `Microsoft.Graph/servicePrincipals` |
| ☑ | ☐ | 5 | App role assignments | BFF SP → `Orders.FullAccess`; you → `Orders.Admin.Direct`; test users → BFF roles |
| ☑ | ☐ | 6 | BFF Web App | On the existing B1 plan — no extra cost. System-assigned MI |
| ☑ | ☐ | 7 | **Static Web App** | Free tier |
| ☑ | ☐ | 8 | API auth configuration | Audience, issuer, required roles |
| ☑ | ☐ | 9 | BFF CORS allowed origins | The Static Web App's hostname |
| n/a | ☐ | 10 | **Two test users** | `az ad user create` — the Graph extension's `users` type is read-only |

Row 10 is the only thing here that cannot be Bicep.

## 7. Definition of done

- [ ] Signing in as `Orders.Reader` shows the order list, and creating an order is refused with 403
- [ ] Signing in as `Orders.Admin` permits both
- [ ] Signing in as a user *without* a role is refused by the BFF, with a 403 and no API call made
- [ ] Network traces show the SPA's token and the BFF→API token are **different**, with different `aud`
- [ ] The Orders API rejects the SPA's token outright
- [ ] You can still call the API directly with an admin token
- [ ] A user token, presented directly to the API, is rejected
- [ ] Every app registration, role and assignment exists in `iac/` — nothing clicked
- [ ] No client secret exists anywhere; `az ad app credential list` is empty for all three
- [ ] Teardown and rebuild reproduces the whole thing, Entra objects included

That third-from-last item is the real test of goal 4, and the one most likely to fail.

## 8. Milestones

Order chosen so each step is verifiable before the next depends on it.

**M1 · Entra objects in Bicep** — the three registrations, service principals, app roles, and the
federated credential from the BFF registration to its managed identity. Verified by `az ad app list`
matching the template with nothing created by hand.

**M2 · API validates tokens** — JWT validation, audience and issuer checks, and an authorization
policy requiring an app role. Verified by the API rejecting an unauthenticated call and accepting
your admin token.

**M3 · BFF acquires a token** — a service with a managed identity that obtains a token for the API
and proxies one endpoint. No user involved yet. Verified end to end with no user in the picture.

**M4 · BFF validates the user and enforces RBAC** — `Orders.Reader` vs `Orders.Admin`, 403 for
neither. Requires the two test users from §4.8, so create them before starting this milestone.

**M5 · React SPA and sign-in** — one form: customer, product, quantity, unit price. Sign in, POST an
order, see it listed.

**M6 · Lock the API down** — the API stops accepting anything but the BFF's app role and your admin
role. Verified by the old direct-user-token path failing.

**M7 · Pipelines** — the frontend and BFF get build/test/deploy workflows alongside `api-cd`.

**M8 · Rebuild test** — teardown and rebuild including Entra objects. This is where preview-extension
sharp edges will show up.

## 9. Risks

- **`what-if` cannot see Entra objects at all.** Verified: extensible resources report
  `ExtensibleResourceNotSupported` and show as "no change". The preview still exits 0, so
  `infra-ci` survives — but every app registration, service principal and role assignment is
  invisible in it.
- **Graph extension is preview.** Expect gaps. Some properties may be unsettable and need an
  imperative fallback, which would break goal 4 for that property.
- **Entra objects are not resource-group scoped.** `az group delete` does not remove them. Teardown
  needs a separate step, and orphaned app registrations accumulate silently.
- **App registration deletion is soft.** Deleted registrations sit recoverable for 30 days and keep
  their identifier URI, so rebuilds can collide — the Key Vault tombstone problem again.
- **Consent.** Some permissions need admin consent; grantable in Bicep via `oauth2PermissionGrants`,
  but it is a step people forget and the failure looks like a permissions bug.
- **Token caching in the BFF.** Requesting a token per call will hit throttling. Needs a cache, which
  is a correctness concern, not an optimisation.
- **Cost.** Static Web Apps free tier is genuinely free and the BFF shares the existing B1 plan, so
  this phase should add nothing. Verify with `/estimate-cost` before deploying.
- **Test-user passwords** are the only secrets v2 introduces. Keep them out of git; `.env` is
  already gitignored.

## 10. Roadmap position — settled

This is **v2**, the next thing built. Everything after it shifts:

| | Was | Now |
|---|---|---|
| v2 | Event-driven | **Identity, frontend, BFF** (this) |
| v3 | Security + APIM | Event-driven — Service Bus, Functions |
| v4 | Production hardening | APIM in front of the API, above both the BFF and the Functions |
| v5 | — | Production hardening |

APIM moved to v4 for the reason in §4.6: it is the front door for *the API*, and both of the API's
callers need to exist before that is worth building.
---

# Implementation report — M1 to M7

**Status:** all code written, builds green, 40 tests pass. **Nothing deployed.**

## What exists now

| Milestone | Built | Where |
|---|---|---|
| **M1** Entra objects in Bicep | 3 app registrations, 3 service principals, 5 app role assignments, Static Web App, BFF web app | `iac/modules/entraApps.bicep`, `entraAssignments.bicep`, `staticWebApp.bicep`, `bffAppService.bicep` |
| **M2** API validates tokens | JWT bearer, fail-closed fallback policy, health left anonymous | `src/orders-api/DevOpsLab.Api/Configuration/ApiAuthentication.cs` |
| **M3** BFF gets its own token | Cached token provider on the managed identity, typed HTTP client | `src/bff/DevOpsLab.Bff/Orders/` |
| **M4** BFF enforces RBAC | `Orders.Reader` reads, `Orders.Admin` also writes | `src/bff/DevOpsLab.Bff/Configuration/BffAuthentication.cs` |
| **M5** React SPA | Vite + React 19 + MSAL, one form and a list | `src/web/orders-spa/` |
| **M6** API locked down | Enforced by M2; Bruno moved to bearer auth | `bruno/collection.bru` |
| **M7** Pipelines | `bff-cd.yml`, `spa-cd.yml`; `api-cd.yml` path filters narrowed | `.github/workflows/` |

Supporting: `scripts/create-test-users.sh`, `get-admin-token.sh`, `teardown-entra.sh`.

## Two things proved by experiment rather than assumed

**Graph resources work inside a Bicep module.** The nested template carries its own `imports` block
and outputs pass through, so the four modules did not have to be inlined into `main.bicep`.

**`what-if` warns rather than errors on them.** Extensible resources report
`ExtensibleResourceNotSupported` and show as "no change", but the command still exits 0 — so
`infra-ci` survives despite `set -o pipefail`. Every Entra object is invisible in a PR preview, and
the PR comment now says so.

## Design points worth remembering

- **The BFF has no credentials of any kind.** No secret, no certificate, not even a federated
  credential — a FIC would only be needed for On-Behalf-Of, which §4.2 rules out. It authenticates
  as its system-assigned managed identity.
- **The API exposes a `user_impersonation` scope and pre-authorises the Azure CLI.** Without both,
  `az account get-access-token` has nothing to request and direct admin access dies at M6.
- **Token caching is correctness, not optimisation.** Entra throttles per-application token
  requests; one per inbound call returns 429 under load.
- **`requestedAccessTokenVersion: 2` and `MapInboundClaims = false`** are each a silent-401 or
  silent-403 waiting to happen if omitted.

---

# Pending before deploy

## Blocking — only you can do these

1. **Grant the deployment identity its Graph permissions.** `sp-devopslab-github-dev` holds no
   Microsoft Graph permissions and cannot grant them to itself. Commands in
   [`docs/azure-setup.md`](../azure-setup.md) §11.2. Without this, every Graph resource fails with
   `Authorization_RequestDenied`.

2. **Create the two test users and paste their object IDs.**
   `./scripts/create-test-users.sh` (needs `TEST_USER_*_PASSWORD` in `.env` first). It prints two
   object IDs which replace the placeholder GUIDs in `iac/subscription.dev.bicepparam`. Deployment
   fails on an invalid principal until they are real.

3. **Register MFA for each test user.** Entra security defaults force it on first interactive
   sign-in and will otherwise stop the RBAC demo at the worst moment.

## Expected to surface during the first deploy

- **A third Graph permission.** `Application.Read.All` may also be required for
  `appRoleAssignedTo`. Planned for, not a failure.
- **Static Web App region.** Set to `westeurope`; this subscription was blocked there for SQL. If it
  is blocked here too, change `staticWebAppLocation` to `eastus2`.
- **`identifierUris` format.** `api://<tenantId>/<name>` is documented as valid but Entra validates
  more strictly on create than update. Fallback is the `https://<tenant>.onmicrosoft.com/<name>` form.

## Sequence

```
1. azure-setup.md §11.2          grant Graph permissions      (you, once)
2. scripts/create-test-users.sh  then paste the object IDs    (you, once)
3. infra-cd                      Azure + Entra objects
4. api-cd                        API with auth enabled
5. bff-cd                        the BFF
6. spa-cd                        the SPA (MUST run after infra-cd — reads its outputs)
```

## Not done, and deliberately so

- **Verification of the running system.** Every claim in §8 of the plan is unproven until deployed.
- **`AzureCliCredential` locally.** Whether a local BFF can get an app-audience token is untested.
- **Teardown.** `teardown-entra.sh` is written but has never been run; the tombstone-purge path is
  the part most likely to need adjusting.
