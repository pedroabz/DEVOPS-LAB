# First deploy — step by step

The first time anything in this repo touches Azure for real. Everything so far has been `what-if`
only.

Work down the list. Each step says what to run, what "good" looks like, and what to do when it
isn't. Tick as you go.

**This is the step that starts costing money.** See [§0](#0-what-this-creates-and-what-it-costs).

---

## 0. What this creates, and what it costs

Eleven resources, of which exactly one has a meaningful running cost.

| Resource | Cost |
|---|---|
| App Service plan (B1 Linux) | **€0.0158/hour ≈ €11.53/month** — bills while it exists, used or not |
| Azure SQL (GP serverless, auto-pause 60 min) | ~€0.47/vCore-hour **while awake**; storage only when paused |
| Log Analytics | free up to the monthly grant, then ~€2.43/GB. Capped at 1 GB/day |
| App Insights | billed through Log Analytics |
| VNet, subnet, firewall rules, VNet rule, resource group | free |

Free under your $200 credit. The number to watch is SQL: if something holds a connection open it
never pauses, and 0.5 vCore awake around the clock is ~€170/month. That's the one real footgun.

---

## 1. Pre-flight

- [ ] **Right subscription**
      ```bash
      az account show --query "{name:name, id:id}" -o table
      ```
      Expect `Azure subscription 1` / `25681d80-476e-40a6-9d21-da4138a1cd27`.

- [ ] **`.env` exists and your IP is current**
      ```bash
      cat .env
      curl -s https://api.ipify.org; echo
      ```
      Those two must match. If your ISP has rotated it, update `.env` first — otherwise SQL will
      refuse you later and the cause won't be obvious.

- [ ] **Nothing is deployed yet**
      ```bash
      az group list -o table
      ```
      Expect empty. If `rg-devopslab-dev-spc` already exists, you're re-running, not first-deploying.

- [ ] **Templates build**
      ```bash
      az bicep build --file iac/main.bicep && rm -f iac/main.json
      ```

---

## 2. Dry run

- [ ] ```bash
      ./scripts/deploy-dev.sh
      ```

Expect **4 resources to create** — resource group, Log Analytics, App Insights, VNet — plus two
`NestedDeploymentShortCircuited` diagnostics for `sqlDeployment` and `appServiceDeployment`.

> **Those two are not errors, and they matter.** Both modules consume `network.outputs.appSubnetId`,
> which `what-if` can't evaluate before the VNet exists. So SQL, the database, both firewall rules,
> the VNet rule, the App Service plan and the Web App are all invisible in this preview. The real
> deploy is the first time they're validated at all. Expect surprises here rather than in step 2.

---

## 3. Deploy

- [ ] ```bash
      ./scripts/deploy-dev.sh deploy
      ```

Takes roughly 5–10 minutes; the SQL logical server is the slow part. Leave it alone rather than
Ctrl-C — a half-finished deployment is more annoying than a failed one.

- [ ] **It reported `"provisioningState": "Succeeded"`**

If it failed, jump to [§8](#8-when-it-goes-wrong) — the likely causes are known.

---

## 4. Verify what actually exists

Don't trust "Succeeded". Check the things that can succeed while being wrong.

- [ ] **Everything is there**
      ```bash
      az resource list -g rg-devopslab-dev-spc -o table
      ```

- [ ] **SQL is serverless with auto-pause on**
      ```bash
      az sql db show -g rg-devopslab-dev-spc -s sql-devopslab-dev-spc-pabz -n sqldb-orders-dev \
        --query "{sku:sku.name, tier:sku.tier, minCap:minCapacity, autoPause:autoPauseDelay, status:status}" -o table
      ```
      Expect `GP_S_Gen5` / `GeneralPurpose` / `0.5` / `60`. **If `autoPause` is `-1`, stop and fix
      it** — that's the €170/month case.

- [ ] **No SQL password exists**
      ```bash
      az sql server ad-only-auth get -g rg-devopslab-dev-spc -n sql-devopslab-dev-spc-pabz
      ```
      Expect `azureAdOnlyAuthentication: true`.

- [ ] **The subnet is delegated and has both service endpoints**
      ```bash
      az network vnet subnet show -g rg-devopslab-dev-spc --vnet-name vnet-devopslab-dev-spc -n snet-app \
        --query "{prefix:addressPrefix, delegation:delegations[0].serviceName, endpoints:serviceEndpoints[].service}"
      ```
      Expect `10.0.1.0/24`, `Microsoft.Web/serverFarms`, and `Microsoft.Sql`.

- [ ] **The SQL rules are both present**
      ```bash
      az sql server firewall-rule list -g rg-devopslab-dev-spc -s sql-devopslab-dev-spc-pabz -o table
      az sql server vnet-rule list -g rg-devopslab-dev-spc -s sql-devopslab-dev-spc-pabz -o table
      ```
      Expect `my-laptop` with your IP, and `allow-app-subnet`. **No `AllowAllWindowsAzureIps`.**

- [ ] **The Web App has an identity and is in the subnet**
      ```bash
      az webapp show -g rg-devopslab-dev-spc -n app-devopslab-dev-spc-pabz \
        --query "{state:state, host:defaultHostName, mi:identity.principalId, subnet:virtualNetworkSubnetId}"
      ```
      All four must be non-null. Record the `mi` value — step 7 needs it.

- [ ] **Routing is actually on** — the setting everything depends on
      ```bash
      az resource show -g rg-devopslab-dev-spc -n app-devopslab-dev-spc-pabz \
        --resource-type Microsoft.Web/sites --query properties.outboundVnetRouting
      ```
      Expect `applicationTraffic: true`. If it's false or missing, the app's SQL traffic bypasses the
      subnet and the VNet rule will never match — and the error you'd get later says "IP not
      allowed", which sends you debugging the wrong thing.

- [ ] **The site responds**
      ```bash
      curl -sI https://app-devopslab-dev-spc-pabz.azurewebsites.net | head -1
      ```
      Any HTTP response is fine — it's an empty app. A TLS error is not.

---

## 5. Connect from VS Code — task 4.7

- [ ] Command Palette → **MS SQL: Connect**
- [ ] Server `sql-devopslab-dev-spc-pabz.database.windows.net`, database `sqldb-orders-dev`
- [ ] Auth type **Microsoft Entra ID – MFA**, sign in as `pedroo.bezerra@gmail.com`
- [ ] Run `SELECT 1`

You get in without any `CREATE USER` because you're in `sg-devopslab-sql-admins`, which is the
server's Entra admin — admins are mapped implicitly.

**The first connection may take 30–60 seconds or time out entirely.** That's the serverless resume,
not a fault. Try again.

---

## 6. Create the schema

- [ ] `dotnet tool install --global dotnet-ef` (once, if you don't have it)

- [ ] Point local config at Azure. In `src/orders-api/DevOpsLab.Api/appsettings.Development.json`, replace
      the `localhost` connection string with:
      ```
      Server=tcp:sql-devopslab-dev-spc-pabz.database.windows.net,1433;Database=sqldb-orders-dev;Authentication=Active Directory Default;Encrypt=True;Connection Timeout=90;
      ```
      No password — `Active Directory Default` uses your `az login` identity.

- [ ] ```bash
      dotnet ef database update \
        --project src/orders-api/DevOpsLab.Infrastructure \
        --startup-project src/orders-api/DevOpsLab.Api
      ```

- [ ] Confirm the tables exist — re-run a query in VS Code.

---

## 7. Run the app locally against Azure

- [ ] ```bash
      dotnet run --project src/orders-api/DevOpsLab.Api
      ```
- [ ] `curl http://localhost:5xxx/health/live` → healthy immediately
- [ ] `curl http://localhost:5xxx/health/ready` → healthy, but **slow on the first call** if the
      database has paused
- [ ] Exercise the Orders endpoints

Telemetry won't flow unless you set `APPLICATIONINSIGHTS_CONNECTION_STRING` in user secrets.
`Program.cs` guards for its absence, so leaving it unset is fine.

> **The deployed app cannot do this yet.** Your identity is a server admin; the Web App's managed
> identity has no database user at all. That's inventory row 11 / task 6.5, and it's the next
> decision. Until then the deployed app will authenticate and then fail with "login failed for user".

---

## 8. When it goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `BCP427: Environment variable "CLIENT_IP" does not exist` | `.env` not sourced | Use `./scripts/deploy-dev.sh`, not raw `az` |
| `RequestDisallowedByAzure ... not accepting new customers` | Region closed to new subscriptions | Not `spaincentral` — but if it appears, try `spaincentral`, `francecentral`, `uksouth` |
| VNet rule fails: service endpoint missing | Subnet lacks `Microsoft.Sql` | Intentional — `ignoreMissingVnetServiceEndpoint: false` makes it fail loudly. Check `network.bicep` |
| `Client with IP address 'x.x.x.x' is not allowed` | Your IP changed | Update `.env`, redeploy. The error names the new IP |
| Connection times out on first try | Serverless resume | Wait 60s and retry. Not a fault |
| Subnet delegation error | Subnet not empty, or wrong delegation | It must be empty and delegated to `Microsoft.Web/serverFarms` |
| Web App 503 | Empty app, still starting | Wait, then re-check. It has no code yet |

---

## 9. Cost check — same day

- [ ] Portal → **Cost Management** → **Cost analysis**, scope = your subscription, group by
      **Resource**.
- [ ] Confirm the App Service plan is the largest line.
- [ ] **Confirm SQL is not accruing compute.** After an hour idle:
      ```bash
      az sql db show -g rg-devopslab-dev-spc -s sql-devopslab-dev-spc-pabz -n sqldb-orders-dev \
        --query status -o tsv
      ```
      Expect `Paused`. If it says `Online` after a long idle period, something is holding a
      connection — a VS Code session, or the app still running.

---

## 10. Stopping the meter

Nothing here auto-stops except SQL.

```bash
az group delete --name rg-devopslab-dev-spc --yes --no-wait
```

Deletes everything, including the database and its data. Redeploying gives you an empty database
again, so you'd re-run step 6.

Nothing in v0 leaves a tombstone or holds a name after deletion — that would have been Key Vault,
which is no longer in scope.

Under the credit, leaving it running costs about €0.40/day. Not worth tearing down nightly unless
you want the practice — and proving destroy-and-rebuild works is task 9.5, so it's worth doing at
least once deliberately.

---

## After this

- Inventory rows 1–10 move from ☑ Bicep to ☑ Live
- Tasks 2.7, 3.5, 4.7, 4.8, 5.6 become genuinely completable
- Row 11 (database user for the managed identity) is the only thing left in v0
