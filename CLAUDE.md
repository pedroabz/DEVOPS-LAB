# Working agreement

This repo exists so Pedro can **learn Azure and IaC**. He is experienced in software architecture
and new to cloud and Bicep. The deliverable is his understanding, not working code. Optimise for
that, never for your throughput.

## Hard rules

1. **Ask before deciding.** Any choice with more than one defensible answer is his. Give 2–4
   options, the trade-offs, and a recommendation clearly labelled as a recommendation. This includes
   choices that feel minor: SKUs, API versions, property values, file names, module boundaries,
   commit granularity, naming.
2. **Never commit or push.** Make file changes and say what changed. He commits. If you think work
   should be committed, ask.
3. **Never deploy.** `az bicep build` and `az deployment sub what-if` change nothing and are fine.
   `az deployment sub create`, and anything that creates or mutates an Azure resource, an Entra
   object, or a GitHub setting, requires an explicit request each time.
4. **No unrequested extras.** Do not add properties, parameters, outputs, tags, files, or resources
   that were not agreed. If something looks missing, ask — do not add it and mention it afterwards.
5. **Report what you actually did.** Not a summary of the outcome — the specific changes. If you ran
   `sed` across three files, show the wording that changed.
6. **Docs record decisions, they don't make them.** `README.md` and `docs/prd/` capture earlier
   choices. When something conflicts, surface it and ask whether to change the code or the doc.
7. **Verify before asserting.** Especially "tier X has feature Y" claims. A wrong one here
   propagated into three documents.

## Code style

Simple and boring. He should be able to read any line and know what it does.

- Literals over computed values. A hardcoded name beats a derived one.
- No lookup maps, `uniqueString()`, safe-dereference (`[?]`), or ternaries unless he asked for that
  specific behaviour.
- Never set a property to its own default value.
- No outputs or parameters that nothing consumes.
- A parameter must have more than one possible value. Otherwise it is a literal.
- Comments explain *why*. Never restate the line below them.

## The repo

```
iac/
  main.bicep                    subscription scope: creates the RG, calls modules
  subscription.dev.bicepparam   the dev environment's values
  bicepconfig.json              linter + Microsoft Graph extension (PREVIEW)
  modules/
    network.bicep               VNet + snet-app (delegated, Microsoft.Sql service endpoint)
    observability.bicep         Log Analytics + Application Insights (SHARED by API and BFF)
    sqlServer.bicep             SQL server + database + firewall rule + VNet rule
    appService.bicep            App Service plan + Orders API web app
    bffAppService.bicep         BFF web app, on the same plan
    staticWebApp.bicep          SPA hosting. Free tier, and NOT in spaincentral
    entraApps.bicep             3 app registrations + service principals (tenant-scoped)
    entraAssignments.bicep      app role assignments (tenant-scoped)
src/
  orders-api/                   ONE deployable, four layers
    DevOpsLab.Api / .Application / .Domain / .Infrastructure
  bff/DevOpsLab.Bff             BFF. References nothing — speaks HTTP to the API
  web/orders-spa                React + Vite + MSAL
  functions/                    v3
scripts/
  deploy-dev.sh                 sources .env, then what-if (default) or deploy
  create-test-users.sh          the one part of v2 that cannot be Bicep
  get-admin-token.sh            direct admin token for the Orders API
  teardown-entra.sh             Entra objects survive `az group delete`
docs/
  azure-setup.md                one-time account bootstrap
  prd/                          v0 and v2 specs
  adr/                          decision records
  *-explained.md                plain-language topic explainers
.env / .env.example             local values, gitignored
```

Nothing is deployed yet. Everything so far has been validated with `what-if` only.

## Local values

`subscription.dev.bicepparam` reads `CLIENT_IP` via `readEnvironmentVariable()`. `az` does not load
`.env` on its own, so deploy through `scripts/deploy-dev.sh`, which sources it first. There is
deliberately **no default** — an unset `CLIENT_IP` fails with `BCP427` rather than silently
producing an empty firewall rule.

## Commands

- `/add-resource <thing>` — guided interview for adding an Azure resource. Use it for infra work.
- `/estimate-cost` — live prices from the Azure Retail Prices API, per resource, idle vs active.
- `/deep-dive <topic>` — plain-language explainer: how it works, trade-offs, what each setting does.

## Context worth not re-deriving

- Region is under discussion: currently `spaincentral` in code; `spaincentral` is closer to Portugal
  and was verified to have Flex Consumption and APIM.
- GitHub OIDC is wired and working. Federated credentials exist for both the plain and the
  **immutable** subject format (`repo:pedroabz@34903747/DEVOPS-LAB@1339815353:...`).
- Deployment slots require **Standard (S1)**. Free and Basic have none.
- Azure SQL serverless takes **30–60s to resume** from auto-pause; see `docs/adr/0001`.
- Bicep has no float type — decimals need `json('0.5')`.
- App Service VNet integration is **outbound only** and reroutes rather than blocks. It needs
  `outboundVnetRouting.applicationTraffic: true`, or SQL traffic leaves by the public path and the
  virtual network rule never matches — deploys green, connection refused.
- `vnetRouteAllEnabled` / `WEBSITE_VNET_ROUTE_ALL` are the **legacy** names for that setting.
- `what-if` short-circuits `sqlDeployment` and `appServiceDeployment` because they consume
  `network.outputs.appSubnetId`. Their resources are real but invisible in the preview.
