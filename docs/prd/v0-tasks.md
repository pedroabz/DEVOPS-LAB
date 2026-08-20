# v0 — Task list

Companion to [`v0-foundations.md`](v0-foundations.md). The PRD says *what and why*; this says
*what to do next*, one tickable item at a time.

**How to use this**

- Work top to bottom — tasks are dependency-ordered.
- Tick items as you go. Commit the tick along with the work, so the file records real progress.
- Each task has a **Look up** line: the concept to search before writing anything. Read first, then
  write. That ordering is the whole point of the lab.
- No task here tells you the answer. If you want one, ask — say whether you want a hint or the
  solution.
- **One PR per milestone.** You want to run the `what-if`-on-PR loop many times.

**Progress**

| Milestone | Tasks | Done |
|---|---|---|
| M1 · Skeleton and hygiene | 6 | ☐ |
| M2 · Subscription scope + RG | 7 | ☐ |
| M3 · Observability | 5 | ☐ |
| M4 · Data | 8 | ☐ |
| M5 · Compute | 6 | ☐ |
| M6 · Identity wiring | 6 | ☐ |
| M7 · CI (what-if on PR) | 7 | ☐ |
| M8 · CD (deploy on merge) | 5 | ☐ |
| M9 · Teardown and docs | 6 | ☐ |

---

## M1 · Bicep skeleton and repo hygiene

- [ ] **1.1** Add a `.gitignore` covering .NET build output (`bin/`, `obj/`), compiled ARM
      (`*.json` emitted by `bicep build`), `.DS_Store`, and local settings files.
      <br>*Look up:* GitHub's `VisualStudio.gitignore` template.
- [ ] **1.2** Add an `.editorconfig` setting 2-space indent for `.bicep` and 4-space for `.cs`.
      <br>*Look up:* EditorConfig properties supported by the Bicep VS Code extension.
- [ ] **1.3** Create `infra/bicepconfig.json` and enable the linter. Decide which rules are errors
      vs warnings.
      <br>*Look up:* Bicep linter rules; `no-unused-params`, `secure-secrets-in-params`, `prefer-interpolation`.
- [ ] **1.4** Create an empty `infra/main.bicep` with only `targetScope` set. Confirm it builds.
      <br>*Look up:* `targetScope` values and what each one can create.
- [ ] **1.5** Repoint or replace `infra/subscription.dev.bicepparam` — its `using` line references the
      deleted `subscription.bicep`. Decide now whether params live at `infra/` root or in `infra/params/`.
      <br>*Look up:* `.bicepparam` files and the `using` statement.
- [ ] **1.6** Verify the toolchain: `az bicep build --file infra/main.bicep` exits clean, and the VS
      Code Bicep extension reports no problems.

**Milestone done when:** the file builds with zero linter warnings and you understand every line in
`bicepconfig.json`.

---

## M2 · Subscription scope and the resource group

- [ ] **2.1** Decide the parameter surface for `main.bicep`. At minimum: environment name, location,
      workload name. Keep it small — parameters are API surface.
      <br>*Look up:* `@description`, `@allowed`, `@minLength` decorators.
- [ ] **2.2** Rename any `environment` parameter to `envName`.
      <br>*Look up:* Bicep's built-in `environment()` function and why shadowing it is a problem.
- [ ] **2.3** Write the naming convention as Bicep variables (see PRD §7). Every resource name should
      derive from the parameters, never be hardcoded.
      <br>*Look up:* string interpolation, `toLower()`, and `uniqueString()` — specifically **what seed**
      makes a name stable across deployments but unique across subscriptions.
- [ ] **2.4** Create the resource group in `main.bicep` with the tag set from PRD §7.
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

**Milestone done when:** `az group show -n rg-devopslab-dev-weu` returns your tagged resource group,
and a second deployment reports no changes.

---

## M3 · Observability

> Deliberately before compute, so telemetry is never a retrofit.

- [ ] **3.1** Create `infra/modules/observability.bicep` (or two modules — your call, note the
      decision).
- [ ] **3.2** Add a Log Analytics workspace: `PerGB2018`, 30-day retention, **daily cap 1 GB**.
      <br>*Look up:* `workspaceCapping.dailyQuotaGb`, and what happens when the cap is hit.
- [ ] **3.3** Add Application Insights in **workspace-based** mode, linked to the workspace.
      <br>*Look up:* `Application_Type`, `WorkspaceResourceId`; why classic App Insights is retired.
- [ ] **3.4** Output the App Insights **connection string** from the module.
      <br>*Look up:* why connection strings replaced instrumentation keys; `@secure()` on outputs and
      why module outputs can't be marked secure.
- [ ] **3.5** Deploy and confirm via `az monitor app-insights component show`.

**Milestone done when:** both resources exist, AI is workspace-linked, and you can retrieve the
connection string from the CLI.

---

## M4 · Data

> The most conceptually loaded milestone. Fresh head recommended.

- [ ] **4.1** Confirm the Entra group from setup §11.1 exists (`sg-devopslab-sql-admins`) and capture
      its **object ID**. Create it if you skipped that step.
      <br>*Look up:* `az ad group show`.
- [ ] **4.2** Replace the `xxxxxxxx-...` placeholder in your `.bicepparam` with the real object ID.
      Decide whether an object ID belongs in a committed file.
      <br>*Look up:* is an Entra object ID a secret? (Reason it through — it affects later choices.)
- [ ] **4.3** Create the SQL logical server with **Entra-only authentication** enabled.
      <br>*Look up:* `administrators` property, `azureADOnlyAuthentication: true`, `principalType: 'Group'`.
- [ ] **4.4** Confirm no SQL admin login/password exists anywhere in your template.
      <br>*Look up:* why `administratorLogin` and Entra-only auth are mutually exclusive.
- [ ] **4.5** Add the database: General Purpose **serverless**, 0.5–1 vCore, **auto-pause 60 min**.
      <br>*Look up:* `GP_S_Gen5_1`, `autoPauseDelay`, `minCapacity`.
- [ ] **4.6** Add a firewall rule allowing Azure services, and decide whether to add your own IP.
      <br>*Look up:* the `0.0.0.0` special-case rule and what it actually means.
- [ ] **4.7** Deploy, then connect from VS Code's mssql extension using your Entra account. Run `SELECT 1`.
      <br>*Look up:* "Microsoft Entra MFA" auth type in the mssql extension.
- [ ] **4.8** Leave it idle an hour, confirm it auto-paused, then query again and time the resume.
      <br>*Look up:* serverless resume latency — so it doesn't look like a bug in v1.

**Milestone done when:** you authenticate to SQL with your Entra identity, no password exists, and
you've observed a pause/resume cycle.

---

## M5 · Compute

- [ ] **5.1** Add a Linux App Service plan. Choose F1 or B1 and record why in the PR description.
      <br>*Look up:* `reserved: true` for Linux; what F1 gives up vs B1.
- [ ] **5.2** Add the Web App with the .NET 10 runtime stack.
      <br>*Look up:* `linuxFxVersion` and the current value for .NET 10.
- [ ] **5.3** Enable a **system-assigned managed identity**.
      <br>*Look up:* `identity: { type: 'SystemAssigned' }`; system-assigned vs user-assigned trade-offs.
- [ ] **5.4** Set `httpsOnly`, a minimum TLS version, and disable FTP deployment.
      <br>*Look up:* App Service security baseline.
- [ ] **5.5** Wire the App Insights connection string in as an app setting.
      <br>*Look up:* `APPLICATIONINSIGHTS_CONNECTION_STRING`; passing module outputs between modules.
- [ ] **5.6** Deploy and confirm the default hostname serves the placeholder page over HTTPS.

**Milestone done when:** the site responds, and `az webapp identity show` returns a principal ID.

---

## M6 · Identity wiring

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
- [ ] **6.6** Write the decision from 6.5 into an ADR before implementing it.

**Milestone done when:** role assignments exist against the MI, redeployment is clean, and 6.5 is a
recorded decision rather than an open question.

---

## M7 · CI — validate and preview on PRs

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

**Milestone done when:** a PR shows an accurate preview, and nothing reaches Azure.

---

## M8 · CD — deploy on merge

- [ ] **8.1** Create `.github/workflows/infra-cd.yml` on push to `main`, filtered to `infra/**`.
- [ ] **8.2** Target the `dev` GitHub Environment.
      <br>*Look up:* `environment:` in a job; the `github-env-dev` federated credential from setup.
- [ ] **8.3** Add a concurrency group so two deployments can never overlap.
      <br>*Look up:* `concurrency` with `cancel-in-progress` — and think about whether cancelling a
      deployment mid-flight is safe.
- [ ] **8.4** Deploy with `az deployment sub create`, using a deterministic deployment name.
      <br>*Look up:* deployment history limits (800 per subscription) and why naming matters.
- [ ] **8.5** Merge M7's test PR and confirm the deployment runs green.

**Milestone done when:** merging to `main` deploys automatically, and concurrent runs queue rather
than collide.

---

## M9 · Teardown and documentation

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
- [ ] **9.6** Check Cost Analysis and record actual spend against the PRD's €5 estimate.

**Milestone done when:** you have destroyed and rebuilt the entire environment from an empty
subscription using nothing but the pipeline.

---

## When you're stuck

Ask, and say which you want:

- **Hint** — the concept and where to look, nothing more (default).
- **Review** — you've written it, you want it critiqued before merging.
- **Answer** — you've spent enough time and want to move on.

All three are legitimate. Reaching for the third occasionally is not cheating; reaching for it first
is how the learning gets skipped.
