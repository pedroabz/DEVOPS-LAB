# PRD — v0: Foundations

**Status:** in progress · **Owner:** @pedroabz · **Depends on:** [`docs/azure-setup.md`](../azure-setup.md) (complete)

> **Working checklist:** [`v0-tasks.md`](v0-tasks.md) — this document is the *what and why*;
> the task list is the tickable *what next*.

---

## 1. Summary

Stand up the complete Azure footprint for the lab **as code**, deployed **by pipeline**, with
nothing created by hand. No application code ships in v0 — the Web App is deployed empty. The
deliverable is a resource group full of correctly-configured, correctly-wired, correctly-named
resources that v1 can drop an API onto.

The reason to do infrastructure before application is that every hard problem in this lab is an
infrastructure problem: identity, telemetry plumbing, secret-free authentication, and repeatable
deployment. Get those right against an empty app and v1 becomes almost trivial.

## 2. Goals

1. One Bicep entry point deploys the entire `dev` environment from nothing to ready.
2. Deployments run **only** from GitHub Actions, using the OIDC identity from setup.
3. Pull requests show a **`what-if` preview** of infrastructure changes before merge.
4. Every resource is named by convention, tagged, and reproducible.
5. The whole environment can be destroyed and rebuilt on demand for a few euros.

## 3. Non-goals

Explicitly **not** in v0 — resist scope creep into these:

| Deferred | To |
|---|---|
| API code, EF Core, migrations | v1 |
| Service Bus, Function App | v2 |
| Entra app registrations for OAuth, RBAC, APIM | v3 |
| `prod` environment, approvals, private endpoints | v4 |
| Alert rules, dashboards, availability tests | v4 |

## 4. Definition of done

v0 is finished when **all** of these are true:

- [ ] A PR touching `infra/` posts a `what-if` result and does not deploy.
- [ ] Merging that PR to `main` deploys automatically and succeeds.
- [ ] `az group show` reveals the resource group with every resource from §6 present.
- [ ] The Web App responds on its default hostname (the empty-app placeholder page is fine).
- [ ] The Web App has a **system-assigned managed identity** with a role assignment on SQL.
- [ ] Azure SQL has **Entra-only authentication** — no SQL admin username/password exists.
- [ ] Application Insights is **workspace-based** and the Web App's app settings point at it.
- [ ] `az deployment sub create` run twice in a row is idempotent — second run changes nothing.
- [ ] `az group delete` followed by a re-run of the pipeline rebuilds everything.
- [ ] Total spend visible in Cost Analysis is under €5 for the build week.

---

## 5. Architecture — the v0 slice

```
  ┌──────────────────────── rg-devopslab-dev-weu ────────────────────────┐
  │                                                                      │
  │   ┌────────────────┐        ┌──────────────────┐                     │
  │   │ App Service    │        │  Key Vault       │                     │
  │   │ plan (B1/F1)   │        │  (RBAC mode)     │                     │
  │   └───────┬────────┘        └────────▲─────────┘                     │
  │           │                          │ get secrets                   │
  │   ┌───────▼────────┐                 │                               │
  │   │  Web App       ├─────────────────┘                               │
  │   │  (empty in v0) │                                                 │
  │   │  system MI ────┼──────────┐                                      │
  │   └───────┬────────┘          │ db_datareader / writer               │
  │           │                   ▼                                      │
  │           │          ┌──────────────────┐                            │
  │           │          │  Azure SQL       │  Entra-only auth           │
  │           │          │  serverless DB   │  auto-pause 60 min         │
  │           │          └──────────────────┘                            │
  │           │ telemetry                                                │
  │           ▼                                                          │
  │   ┌────────────────────┐      ┌────────────────────────┐             │
  │   │ Application        │─────▶│ Log Analytics          │             │
  │   │ Insights           │      │ workspace (daily cap)  │             │
  │   └────────────────────┘      └────────────────────────┘             │
  └──────────────────────────────────────────────────────────────────────┘
```

## 6. Resource inventory

| # | Resource | SKU / config | Why this choice |
|---|---|---|---|
| 1 | Resource group | `westeurope` | Lifecycle boundary; one per environment |
| 2 | Log Analytics workspace | PerGB2018, 30-day retention, **daily cap 1 GB** | The cap is the cost guardrail; ingestion is the only thing here that can run away |
| 3 | Application Insights | **Workspace-based**, linked to #2 | Classic AI is retired; workspace-based is required for modern features |
| 4 | Azure SQL logical server | **Entra-only authentication**, admin = the Entra group from setup §11.1 | No password to leak or rotate; the whole point of the exercise |
| 5 | Azure SQL database | **General Purpose serverless**, 0.5–1 vCore, **auto-pause 60 min** | Scales to zero; an idle DB costs storage only |
| 6 | App Service plan | Linux, **B1** (or F1 to start) | B1 is the cheapest tier with deployment slots — needed in v1 |
| 7 | Web App | Linux, .NET 10 runtime, **system-assigned MI**, HTTPS-only | The MI is what authenticates to SQL and Key Vault |
| 8 | Key Vault | Standard, **RBAC authorization**, soft-delete on | RBAC mode over access policies — access policies are legacy |
| 9 | Role assignments | Web App MI → Key Vault Secrets User; MI → SQL | Your deployment identity already holds RBAC Administrator |

> **On Key Vault in v0:** it holds nothing yet. Deploy it anyway so the pattern and permissions
> exist before v1 needs them. Deferring it means retrofitting identity plumbing later, which is the
> harder job.

## 7. Naming and tagging convention

Adopt [Microsoft CAF abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) — `<type>-<workload>-<env>-<region>`:

| Resource | Pattern | Example |
|---|---|---|
| Resource group | `rg-devopslab-dev-weu` | |
| Log Analytics | `log-devopslab-dev-weu` | |
| App Insights | `appi-devopslab-dev-weu` | |
| SQL server | `sql-devopslab-dev-<unique>` | **globally unique** |
| SQL database | `sqldb-orders-dev` | |
| App Service plan | `asp-devopslab-dev-weu` | |
| Web App | `app-devopslab-api-dev-<unique>` | **globally unique** |
| Key Vault | `kv-dvlab-dev-<unique>` | **globally unique, ≤24 chars** |

Three of these are globally unique across all of Azure — use `uniqueString()` on a deterministic
seed so the name is stable across redeployments but doesn't collide with strangers.

Tag every resource, applied once at the resource group and inherited by convention:

```
env=dev · workload=devopslab · managedBy=bicep · costCenter=lab · repo=pedroabz/DEVOPS-LAB
```

`managedBy=bicep` is the one that matters — it tells future-you that hand-editing in the portal
will be silently reverted by the next deployment.

---

## 8. Implementation order

Ordered by dependency, and by what teaches most per unit of frustration. **Each milestone should be
its own PR** — that way you exercise the `what-if`-on-PR loop many times, which is itself the point.

### M1 · Bicep skeleton and repo hygiene
**Build:** `.gitignore`, `.editorconfig`, `bicepconfig.json` (linter rules), decide the entry-point
file name and parameter shape. You already have `infra/subscription.bicep` — keep it if you like
that name, just be consistent.

**Learn:** Bicep linter, `bicepconfig.json`, why `targetScope` matters.

**Done when:** `az bicep build --file infra/subscription.bicep` succeeds with no linter warnings.

---

### M2 · Subscription scope and the resource group
**Build:** subscription-scoped deployment that creates the resource group and applies tags. One
`.bicepparam` for `dev`.

**Learn:** deployment scopes, `scope: resourceGroup(...)` on modules, `.bicepparam` vs JSON params.

> ⚠️ **This is where your current file will fail.** At `targetScope = 'subscription'` there is no
> resource group in context, so `resourceGroup().location` and `uniqueString(resourceGroup().id)`
> are both invalid. You need a `location` parameter supplied by the caller, and a different seed for
> `uniqueString` — `subscription().subscriptionId` is the usual choice. Modules that create
> RG-scoped resources also need an explicit `scope:`. Work it out from the error messages; they're
> clear once you know scope is the issue.

> ⚠️ Also: `environment` shadows Bicep's built-in `environment()` function. Rename it `envName`
> before it bites you.

**Done when:** `az deployment sub what-if` shows the RG being created; deploying twice is a no-op.

---

### M3 · Observability first
**Build:** Log Analytics workspace (with daily cap) + workspace-based Application Insights.

**Learn:** why AI needs a workspace, retention vs cap, `outputs` for passing the connection string.

**Done when:** both exist and `az monitor app-insights component show` returns a connection string.

> Do this **before** compute. When the Web App lands you can wire telemetry immediately rather than
> going back to retrofit it.

---

### M4 · Data
**Build:** SQL logical server with Entra-only auth (admin = your `sg-devopslab-sql-admins` group)
and a serverless database with auto-pause. Firewall rule for Azure services.

**Learn:** Entra-only authentication, serverless vs provisioned, auto-pause economics, why the
admin is a group rather than a person.

**Done when:** you can connect from VS Code's mssql extension using your Entra login, and
`SELECT 1` works. Confirm the DB auto-pauses after an hour of inactivity.

> This is the most conceptually loaded milestone. Budget time for it.

---

### M5 · Compute
**Build:** Linux App Service plan + Web App on .NET 10, HTTPS-only, system-assigned managed
identity, app settings pointing at the App Insights connection string from M3.

**Learn:** managed identity vs service principal, App Service configuration, why the connection
string is an app setting rather than baked into code.

**Done when:** default hostname serves the placeholder page over HTTPS and the MI has a principal ID.

---

### M6 · Identity wiring
**Build:** role assignments — Web App MI → Key Vault Secrets User; Web App MI → SQL. Key Vault in
RBAC mode.

**Learn:** RBAC role assignment in Bicep, `principalId` from a module output, deterministic GUIDs
for assignment names.

**Done when:** role assignments show against the MI, and re-deploying doesn't error on duplicates.

> The SQL half is the interesting one: granting a managed identity database access is **not** an
> ARM role assignment — it's a `CREATE USER ... FROM EXTERNAL PROVIDER` T-SQL statement. Bicep alone
> can't do it. Decide how you'll handle it: a deployment script, a pipeline step, or manual for now
> and automated in v1. Any of the three is a defensible answer; picking one deliberately is the
> learning.

---

### M7 · CI — validate and preview
**Build:** `.github/workflows/infra-ci.yml` — on PRs touching `infra/`: OIDC login, `az bicep build`,
lint, then `az deployment sub what-if`, posting the result as a PR comment.

**Learn:** `paths:` filters, OIDC in practice, `what-if` output modes, writing PR comments from Actions.

**Done when:** opening a PR that changes a SKU shows exactly that change in the comment, and nothing deploys.

---

### M8 · CD — deploy on merge
**Build:** `.github/workflows/infra-cd.yml` — on push to `main` touching `infra/`, deploy to the
`dev` GitHub Environment.

**Learn:** environments, concurrency groups (never two deployments at once), idempotency.

**Done when:** merging deploys automatically and the run is green.

---

### M9 · Teardown and documentation
**Build:** `scripts/teardown.sh`, an ADR in `docs/adr/` for each significant choice (Entra-only SQL,
serverless, Flex Consumption, RBAC vs access policies), and a short `infra/README.md`.

**Learn:** ADRs as a habit; proving rebuild-from-scratch actually works.

**Done when:** you destroy the RG, re-run the pipeline, and everything comes back green.

---

## 9. Decisions you need to make

| Decision | Options | Note |
|---|---|---|
| App Service tier | F1 free vs B1 (~€12/mo) | F1 has no slots and no Always On. v1 wants slots — but you can start F1 and change one line. |
| SQL MI grant mechanism | deployment script / pipeline step / manual | See M6. No wrong answer, but pick consciously. |
| `what-if` on PRs | comment-only vs blocking check | Comment-only is friendlier while you're iterating alone. |
| Module granularity | one per resource vs grouped | Grouped (`observability.bicep`, `data.bicep`) tends to age better than one-file-per-resource. |
| Secrets in Key Vault | populate in v0 vs leave empty | Empty is fine — the point is that the plumbing exists. |

## 10. Risks and known gotchas

- **Key Vault soft-delete.** Deleting a vault leaves a tombstone holding the name for 90 days. A
  rebuild with the same name fails unless you purge it first. Bake this into the teardown script.
- **SQL server names are global.** So are Web App and Key Vault names. Collisions surface as
  confusing deployment errors.
- **Serverless auto-pause resume latency.** The first query after a pause takes ~30–60 seconds.
  This will look like a bug in v1. It isn't.
- **App Insights sampling** is on by default and will quietly drop telemetry. Know it's there before
  you conclude your instrumentation is broken.
- **Role assignment propagation** takes 30 s–5 min. A deployment that creates an assignment and
  immediately uses it can fail intermittently.
- **`what-if` noise.** Some resource types always report changes even when nothing changed. Learn
  which ones lie so you don't chase them.
- **Daily cap on Log Analytics** stops ingestion when hit — telemetry silently disappears until
  midnight UTC. That's the intended trade, but know the symptom.

## 11. Suggested sequence for a first session

M1 → M2 is one sitting and gets you the satisfying `what-if` → deploy → resource-group-appears loop.
M3 is quick. Stop there; **M4 deserves a fresh head.**

---

## 12. References

- [Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Deployment scopes](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-subscription)
- [CAF resource naming abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
- [Azure SQL Entra-only authentication](https://learn.microsoft.com/azure/azure-sql/database/authentication-azure-ad-only-authentication)
- [Serverless compute tier](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-overview)
- [Managed identity with App Service](https://learn.microsoft.com/azure/app-service/overview-managed-identity)
- [Key Vault RBAC guide](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
