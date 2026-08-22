# PRD — v0: Foundations

**Status:** in progress · **Owner:** @pedroabz · **Depends on:** [`docs/azure-setup.md`](../azure-setup.md) (complete)

Sections 1–7 are the spec: what v0 is and why. [Section 8](#8-implementation) is the working
checklist — tick items as you go and commit the ticks alongside the work.

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
  ┌──────────────────────── rg-devopslab-dev-neu ────────────────────────┐
  │                                                                      │
  │   ┌────────────────┐        ┌──────────────────┐                     │
  │   │ App Service    │        │  Key Vault       │                     │
  │   │ plan (F1 free) │        │  (RBAC mode)     │                     │
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
| 1 | Resource group | `northeurope` | Lifecycle boundary; one per environment |
| 2 | Log Analytics workspace | PerGB2018, 30-day retention, **daily cap 1 GB** | The cap is the cost guardrail; ingestion is the only thing here that can run away |
| 3 | Application Insights | **Workspace-based**, linked to #2 | Classic AI is retired; workspace-based is required for modern features |
| 4 | Azure SQL logical server | **Entra-only authentication**, admin = the Entra group from setup §11.1 | No password to leak or rotate; the whole point of the exercise |
| 5 | Azure SQL database | **General Purpose serverless**, 0.5–1 vCore, **auto-pause 60 min** | Scales to zero; an idle DB costs storage only |
| 6 | App Service plan | Linux, **F1** (free) | Zero compute cost. Slots need **S1** — B1 has none either. Scale up temporarily when v1 practises swaps |
| 7 | Web App | Linux, .NET 10 runtime, **system-assigned MI**, HTTPS-only | The MI is what authenticates to SQL and Key Vault |
| 8 | Key Vault | Standard, **RBAC authorization**, soft-delete on | RBAC mode over access policies — access policies are legacy |
| 9 | Role assignments | Web App MI → Key Vault Secrets User; MI → SQL | Your deployment identity already holds RBAC Administrator |

> **On Key Vault in v0:** it holds nothing yet. Deploy it anyway so the pattern and permissions
> exist before v1 needs them. Deferring it means retrofitting identity plumbing later, which is the
> harder job.

## 7. Naming and tagging convention

Adopt [Microsoft CAF abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) — `<type>-<workload>-<env>-<region>`:

| Resource | Pattern | Note |
|---|---|---|
| Resource group | `rg-devopslab-dev-neu` | |
| Log Analytics | `log-devopslab-dev-neu` | |
| App Insights | `appi-devopslab-dev-neu` | |
| SQL server | `sql-devopslab-dev-neu-pabz` | **globally unique** — hence the `owner` token |
| SQL database | `sqldb-orders-dev` | |
| App Service plan | `asp-devopslab-dev-neu` | |
| Web App | `app-devopslab-dev-neu-pabz` | **globally unique** — hence the `owner` token |
| Key Vault | `kv-dvlab-dev-<unique>` | **globally unique, ≤24 chars** |

Two of these are globally unique across all of Azure. A short `owner` token disambiguates them.
`uniqueString()` is the alternative, but it produces unreadable names you cannot predict before
deploying — not worth it for a single-owner lab.

Tag every resource, applied once at the resource group and inherited by convention:

```
env=dev · workload=devopslab · managedBy=bicep · costCenter=lab · repo=pedroabz/DEVOPS-LAB
```

`managedBy=bicep` is the one that matters — it tells future-you that hand-editing in the portal
will be silently reverted by the next deployment.

---

## 8. Implementation

Milestones are dependency-ordered, and ordered by what teaches most per unit of frustration.
**Each milestone should be its own PR** — that way you exercise the `what-if`-on-PR loop many times,
which is itself the point.

Each task carries a **Look up** line: the concept to search *before* writing anything. Read first,
then write. No task here gives you the answer — if you want one, ask, and say whether you want a
hint, a review, or the solution.

| Milestone | Tasks | Status |
|---|---|---|
| [M1 · Skeleton and hygiene](#m1--bicep-skeleton-and-repo-hygiene) | 6 | ◐ 3/6 |
| [M2 · Subscription scope + RG](#m2--subscription-scope-and-the-resource-group) | 7 | ☐ |
| [M3 · Observability](#m3--observability) | 5 | ☐ |
| [M4 · Data](#m4--data) | 8 | ☐ |
| [M5 · Compute](#m5--compute) | 6 | ☐ |
| [M6 · Identity wiring](#m6--identity-wiring) | 6 | ☐ |
| [M7 · CI — what-if on PRs](#m7--ci--validate-and-preview-on-prs) | 7 | ☐ |
| [M8 · CD — deploy on merge](#m8--cd--deploy-on-merge) | 5 | ☐ |
| [M9 · Teardown and docs](#m9--teardown-and-documentation) | 6 | ☐ |

---

### M1 · Bicep skeleton and repo hygiene

**Learn:** the Bicep linter, `bicepconfig.json`, why `targetScope` matters.

- [x] **1.1** `.gitignore` — .NET output, compiled ARM, local settings, OS cruft. *(done for you —
      boilerplate, not the object of study)*
      <br>Note the negation pattern: `infra/**/*.json` ignores `bicep build` output, and
      `!infra/**/bicepconfig.json` keeps the config tracked.
- [x] **1.2** `.editorconfig` — 2-space for `.bicep`/`.bicepparam`/YAML/JSON, 4-space for `.cs`,
      plus a few C# conventions. *(done for you)*
- [x] **1.3** `infra/bicepconfig.json` — linter enabled. *(done for you)* Rules are split three ways:
      security and dead-code rules are **errors**, style rules are **warnings**, and
      `use-recent-api-versions` is **off** because it flags every API version as stale within months.
      <br>*Worth knowing:* verified by building a throwaway file with an unused param and confirming
      it failed as `Error` rather than the default `Warning`. A misspelled rule name is silently
      ignored, so a config that "looks right" can do nothing.
- [ ] **1.4** Create an empty `infra/main.bicep` with only `targetScope` set. Confirm it builds.
      <br>*Look up:* `targetScope` values and what each one can create.
- [ ] **1.5** Repoint or replace `infra/subscription.dev.bicepparam` — its `using` line still
      references the deleted `subscription.bicep`. Decide now whether params live at `infra/` root or
      in `infra/params/`.
      <br>*Look up:* `.bicepparam` files and the `using` statement.
- [ ] **1.6** Verify the toolchain: `az bicep build --file infra/main.bicep` exits clean, and the VS
      Code Bicep extension reports no problems.

**Done when:** the file builds with zero linter warnings and you understand every line in
`bicepconfig.json`.

---

### M2 · Subscription scope and the resource group

**Learn:** deployment scopes, `scope:` on modules, `.bicepparam` vs JSON parameter files.

- [ ] **2.1** Decide the parameter surface for `main.bicep`. At minimum: environment name, location,
      workload name. Keep it small — parameters are API surface.
      <br>*Look up:* `@description`, `@allowed`, `@minLength` decorators.
- [ ] **2.2** Rename any `environment` parameter to `envName`.
      <br>*Look up:* Bicep's built-in `environment()` function and why shadowing it is a problem.
- [ ] **2.3** Express the naming convention from §7 as Bicep variables. Every resource name should
      derive from parameters, never be hardcoded.
      <br>*Look up:* string interpolation, `toLower()`, and `uniqueString()` — specifically **what seed**
      makes a name stable across deployments but unique across subscriptions.
- [ ] **2.4** Create the resource group in `main.bicep` with the tag set from §7.
      <br>*Look up:* `Microsoft.Resources/resourceGroups` — note it can *only* be created at subscription scope.
- [ ] **2.5** Understand why `resourceGroup().location` fails at subscription scope, and what to use
      instead.
      <br>*Look up:* which template functions are available per scope; `deployment().location`.
- [ ] **2.6** Add a module call scoped into the new resource group — even a trivial one — to prove
      the pattern works.
      <br>*Look up:* the `scope:` property on modules; `resourceGroup(name)` as a scope function.
- [ ] **2.7** Run `az deployment sub what-if`, read the output, then deploy. Run the deploy a second
      time and confirm nothing changes.
      <br>*Look up:* `what-if` result codes — Create / Modify / NoChange / Ignore.

> ⚠️ **Your first draft failed here for a reason worth understanding.** At
> `targetScope = 'subscription'` there is no resource group in context, so `resourceGroup().location`
> and `uniqueString(resourceGroup().id)` are both invalid. You need a `location` parameter supplied
> by the caller, and a different seed for `uniqueString` — `subscription().subscriptionId` is the
> usual choice. Modules creating RG-scoped resources also need an explicit `scope:`. Work it out
> from the error messages; they're clear once you know scope is the issue.

**Done when:** `az group show -n rg-devopslab-dev-neu` returns your tagged resource group, and a
second deployment reports no changes.

---

### M3 · Observability

> Deliberately **before** compute. When the Web App lands you can wire telemetry immediately rather
> than going back to retrofit it.

**Learn:** why App Insights needs a workspace, retention vs daily cap, passing values between modules.

- [ ] **3.1** Create `infra/modules/observability.bicep` (or two modules — your call; note the
      decision).
- [ ] **3.2** Add a Log Analytics workspace: `PerGB2018`, 30-day retention, **daily cap 1 GB**.
      <br>*Look up:* `workspaceCapping.dailyQuotaGb`, and what happens when the cap is hit.
- [ ] **3.3** Add Application Insights in **workspace-based** mode, linked to the workspace.
      <br>*Look up:* `Application_Type`, `WorkspaceResourceId`; why classic App Insights is retired.
- [ ] **3.4** Output the App Insights **connection string** from the module.
      <br>*Look up:* why connection strings replaced instrumentation keys; `@secure()` on outputs and
      why module outputs can't be marked secure.
- [ ] **3.5** Deploy and confirm via `az monitor app-insights component show`.

**Done when:** both resources exist, AI is workspace-linked, and you can retrieve the connection
string from the CLI.

---

### M4 · Data

> The most conceptually loaded milestone. Budget time; start it with a fresh head.

**Learn:** Entra-only authentication, serverless vs provisioned, auto-pause economics, why the
admin is a group rather than a person.

- [ ] **4.1** Confirm the Entra group from setup §11.1 exists (`sg-devopslab-sql-admins`) and capture
      its **object ID**. Create it if you skipped that step.
      <br>*Look up:* `az ad group show`.
- [ ] **4.2** Replace the `xxxxxxxx-...` placeholder in your `.bicepparam` with the real object ID.
      Decide whether an object ID belongs in a committed file.
      <br>*Look up:* is an Entra object ID a secret? Reason it through — it affects later choices.
- [ ] **4.3** Create the SQL logical server with **Entra-only authentication** enabled.
      <br>*Look up:* `administrators` property, `azureADOnlyAuthentication: true`, `principalType: 'Group'`.
- [ ] **4.4** Confirm no SQL admin login or password exists anywhere in your template.
      <br>*Look up:* why `administratorLogin` and Entra-only auth are mutually exclusive.
- [ ] **4.5** Add the database: General Purpose **serverless**, 0.5–1 vCore, **auto-pause 60 min**.
      <br>*Look up:* `GP_S_Gen5_1`, `autoPauseDelay`, `minCapacity`.
- [ ] **4.6** Add a firewall rule allowing Azure services, and decide whether to add your own IP.
      <br>*Look up:* the `0.0.0.0` special-case rule and what it actually means.
- [ ] **4.7** Deploy, then connect from VS Code's mssql extension using your Entra account. Run `SELECT 1`.
      <br>*Look up:* the "Microsoft Entra MFA" auth type in the mssql extension.
- [ ] **4.8** Leave it idle an hour, confirm it auto-paused, then query again and time the resume.
      <br>*Look up:* serverless resume latency — so it doesn't look like a bug in v1.

**Done when:** you authenticate to SQL with your Entra identity, no password exists anywhere, and
you've observed a pause/resume cycle.

---

### M5 · Compute

**Learn:** managed identity vs service principal, App Service configuration, why the connection
string is an app setting rather than baked into code.

- [ ] **5.1** Add a Linux App Service plan. Default F1; record the reasoning in the PR description.
      <br>*Look up:* `reserved: true` for Linux; the F1 CPU-minute quota; **which tier deployment slots actually start at** (it is not Basic).
- [ ] **5.2** Add the Web App with the .NET 10 runtime stack.
      <br>*Look up:* `linuxFxVersion` and the current value for .NET 10.
- [ ] **5.3** Enable a **system-assigned managed identity**.
      <br>*Look up:* `identity: { type: 'SystemAssigned' }`; system-assigned vs user-assigned trade-offs.
- [ ] **5.4** Set `httpsOnly`, a minimum TLS version, and disable FTP deployment.
      <br>*Look up:* the App Service security baseline.
- [ ] **5.5** Wire the App Insights connection string in as an app setting.
      <br>*Look up:* `APPLICATIONINSIGHTS_CONNECTION_STRING`; passing outputs between modules.
- [ ] **5.6** Deploy and confirm the default hostname serves the placeholder page over HTTPS.

**Done when:** the site responds, and `az webapp identity show` returns a principal ID.

---

### M6 · Identity wiring

**Learn:** role assignments in Bicep, consuming `principalId` from a module output, deterministic
GUIDs for assignment names.

- [ ] **6.1** Add Key Vault in **RBAC authorization** mode with soft-delete enabled.
      <br>*Look up:* `enableRbacAuthorization`; why access policies are legacy.
- [ ] **6.2** Grant the Web App's managed identity the **Key Vault Secrets User** role.
      <br>*Look up:* `Microsoft.Authorization/roleAssignments`, built-in role definition IDs.
- [ ] **6.3** Work out how role assignment **names** must be generated so redeployment is idempotent.
      <br>*Look up:* `guid()` with a deterministic seed — scope + principal + role.
- [ ] **6.4** Deploy twice. Confirm the second run doesn't fail on a duplicate assignment.
- [ ] **6.5** Decide how the managed identity gets **database** access. This is not an ARM role
      assignment — it's T-SQL (`CREATE USER ... FROM EXTERNAL PROVIDER` plus role membership) that
      Bicep cannot execute. Options: deployment script, pipeline step, or manual now / automated in v1.
      <br>*Look up:* `Microsoft.Resources/deploymentScripts`; contained database users.
- [ ] **6.6** Write the decision from 6.5 into an ADR **before** implementing it.

**Done when:** role assignments exist against the MI, redeployment is clean, and 6.5 is a recorded
decision rather than an open question.

---

### M7 · CI — validate and preview on PRs

**Learn:** `paths:` filters, OIDC in practice, `what-if` output modes, writing PR comments from Actions.

- [ ] **7.1** Create `.github/workflows/infra-ci.yml` triggered on `pull_request` with a `paths:`
      filter for `infra/**`.
      <br>*Look up:* `paths` filters; why they matter in a monorepo.
- [ ] **7.2** Add the OIDC login block. Remember `permissions: id-token: write`.
      <br>*Look up:* re-read setup §9 — the `github-pr` federated credential already exists for this.
- [ ] **7.3** Add a build/lint step that fails the job on linter errors.
- [ ] **7.4** Add `az deployment sub what-if` against the dev parameters.
      <br>*Look up:* `--result-format`; `ResourceIdOnly` vs `FullResourcePayloads`.
- [ ] **7.5** Post the `what-if` output as a PR comment.
      <br>*Look up:* `actions/github-script`, or `gh pr comment` with `GITHUB_TOKEN`; the
      `pull-requests: write` permission.
- [ ] **7.6** Confirm the workflow **never deploys** — only previews.
- [ ] **7.7** Test it: open a PR that changes one SKU and check the comment shows exactly that.

**Done when:** a PR shows an accurate preview, and nothing reaches Azure.

---

### M8 · CD — deploy on merge

**Learn:** GitHub Environments, concurrency groups, idempotency.

- [ ] **8.1** Create `.github/workflows/infra-cd.yml` on push to `main`, filtered to `infra/**`.
- [ ] **8.2** Target the `dev` GitHub Environment.
      <br>*Look up:* `environment:` in a job; the `github-env-dev` federated credential from setup.
- [ ] **8.3** Add a concurrency group so two deployments can never overlap.
      <br>*Look up:* `concurrency` with `cancel-in-progress` — and think about whether cancelling a
      deployment mid-flight is safe.
- [ ] **8.4** Deploy with `az deployment sub create`, using a deterministic deployment name.
      <br>*Look up:* deployment history limits (800 per subscription) and why naming matters.
- [ ] **8.5** Merge M7's test PR and confirm the deployment runs green.

**Done when:** merging to `main` deploys automatically, and concurrent runs queue rather than collide.

---

### M9 · Teardown and documentation

**Learn:** ADRs as a habit; proving rebuild-from-scratch actually works.

- [ ] **9.1** Write `scripts/teardown.sh` to delete the resource group.
- [ ] **9.2** Handle the **Key Vault soft-delete tombstone** in that script — a rebuild with the same
      name fails for 90 days otherwise.
      <br>*Look up:* `az keyvault purge`; purge protection vs soft delete.
- [ ] **9.3** Write ADRs for: Entra-only SQL auth, serverless tier, Key Vault RBAC mode, and the 6.5
      decision.
      <br>*Look up:* the Michael Nygard ADR format — keep them to one page.
- [ ] **9.4** Write `infra/README.md`: how to deploy manually, how to run `what-if` locally, what
      each module does.
- [ ] **9.5** Run the full rebuild test — tear down, re-run the pipeline, everything returns green.
- [ ] **9.6** Check Cost Analysis and record actual spend against the €5 estimate in §4.

**Done when:** you have destroyed and rebuilt the entire environment from an empty subscription
using nothing but the pipeline.

---

## 9. Decisions you need to make

| Decision | Options | Note |
|---|---|---|
| App Service tier | F1 free (default) vs B1 ~€12 vs S1 ~€65 | **Slots require S1** — Free, Shared *and Basic* have none. B1 buys Always On but no slots, so it is rarely the right stop. Run F1, and flip `appServicePlanSku` to `'S1'` for an afternoon when v1 practises slot swaps (~€0.10), then flip back. Plans resize in place. |
| SQL MI grant mechanism | deployment script / pipeline step / manual | See task 6.5. No wrong answer, but pick consciously. |
| `what-if` on PRs | comment-only vs blocking check | Comment-only is friendlier while you're iterating alone. |
| Module granularity | one per resource vs grouped | Grouped (`observability.bicep`, `data.bicep`) tends to age better than one-file-per-resource. |
| Secrets in Key Vault | populate in v0 vs leave empty | Empty is fine — the point is that the plumbing exists. |
| Parameter file location | `infra/` root vs `infra/params/` | Root reads better for one environment; `params/` scales when prod arrives in v4. |

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

## 11. Suggested first session

M1 → M2 is one sitting and gets you the satisfying `what-if` → deploy → resource-group-appears loop.
M3 is quick. Stop there; **M4 deserves a fresh head.**

## 12. When you're stuck

Ask, and say which you want:

- **Hint** — the concept and where to look, nothing more (default).
- **Review** — you've written it and want it critiqued before merging.
- **Answer** — you've spent enough time and want to move on.

All three are legitimate. Reaching for the third occasionally is not cheating; reaching for it first
is how the learning gets skipped.

---

## 13. References

- [Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Deployment scopes](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-subscription)
- [CAF resource naming abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
- [Azure SQL Entra-only authentication](https://learn.microsoft.com/azure/azure-sql/database/authentication-azure-ad-only-authentication)
- [Serverless compute tier](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-overview)
- [Managed identity with App Service](https://learn.microsoft.com/azure/app-service/overview-managed-identity)
- [Key Vault RBAC guide](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
