---
description: Price every resource in iac/ using the live Azure Retail Prices API — per hour, per month, and idle
---

# Estimate cost

Work out what `iac/` actually costs, using **live prices from Azure**, not remembered figures.

Scope: **$ARGUMENTS** (empty = the whole `iac/` template.)

---

## Rules

1. **Never guess a price.** Every number comes from the Retail Prices API or from a
   `learn.microsoft.com` page you fetched in this run. If you cannot find a price, say
   "not found" — do not substitute a figure from memory.
2. **Do not invent an hourly rate for something not billed hourly.** Log Analytics bills per GB
   ingested; SQL serverless bills per vCore-second *while awake*; storage bills per GB-month. Report
   each in its real unit, then show the assumption behind any monthly figure.
3. **Separate idle cost from active cost.** The number that matters for a lab is what it costs
   overnight with nobody using it. Say which resources keep billing when idle and which stop.
4. **Read the template, don't assume the SKU.** Get the actual values from the Bicep.

---

## Step 1 — Find the resources and their SKUs

```bash
az deployment sub what-if --location northeurope --name devopslab-dev \
  --template-file iac/main.bicep --parameters iac/subscription.dev.bicepparam \
  --result-format ResourceIdOnly
```

`what-if` short-circuits modules whose parameters depend on `reference()`, so resources can be
missing from that list. Cross-check against `iac/main.bicep` and `iac/modules/*.bicep`, and read
the SKU/tier/capacity out of the templates. **Say explicitly if `what-if` hid something.**

Also read the region from `subscription.dev.bicepparam` — prices vary by region.

## Step 2 — Query the Retail Prices API

Public, no auth:

```bash
curl -s "https://prices.azure.com/api/retail/prices?currencyCode='EUR'&\$filter=<odata>"
```

Useful filter fields: `armRegionName`, `serviceName`, `skuName`, `productName`, `meterName`,
`type` (use `'Consumption'`; `'Reservation'` and `'DevTestConsumption'` will pollute results).
`contains(productName,'...')` works and is often necessary.

Region and service names as they appear in the API:

| Resource | `serviceName` |
|---|---|
| App Service plan | `Azure App Service` |
| Azure SQL | `SQL Database` |
| Log Analytics / App Insights | `Log Analytics` |
| Key Vault | `Key Vault` |
| Service Bus | `Service Bus` |
| Storage account | `Storage` |
| API Management | `API Management` |
| Private endpoint / NAT / VNet | `Virtual Network` |

Watch out:

- **Linux and Windows App Service are separate products.** `Azure App Service Basic Plan - Linux`
  is not `Azure App Service Basic Plan`. Pick the right one; the Windows price is 4× higher.
- Several meters can match one resource — compute, storage, backup, egress. Report the ones that
  will actually be incurred and say which you excluded.
- A `0.00` price usually means a free grant tier, not free forever. Check for a paired non-zero
  meter (Log Analytics has both).
- Application Insights bills **through** its Log Analytics workspace. Don't double-count.

## Step 3 — Report

One table, ordered by monthly cost descending:

| Resource | SKU | Unit price | Billed on | €/hour | €/month if always on | Bills when idle? |
|---|---|---|---|---|---|---|

Then, separately:

- **Realistic monthly total for this lab**, with the assumptions stated as bullets (e.g. "SQL awake
  2h/day", "1 GB/month ingested"). Show the arithmetic.
- **Worst case** — everything running continuously. This is the number that catches people out.
- **What to delete or scale down between sessions**, ranked by savings.
- **Anything you could not price**, named explicitly.

Compare the realistic total against the €20 budget in `docs/azure-setup.md` §4 and say plainly
whether it fits.

## Step 4 — Flag drift

If the figures contradict `docs/prd/v0-foundations.md` §6 or `docs/azure-setup.md` §12, say so and
ask whether to update the docs. Do not edit them unprompted.

---

## Known traps

- **SQL serverless is expensive while awake.** GP serverless is roughly €0.47/vCore-hour in North
  Europe, so even `minCapacity: 0.5` is ~€170/month if it never pauses. Auto-pause is the entire
  cost model — always report the awake and paused cases as separate numbers.
- **App Service plans bill while they exist**, not while they're used. Stopping the Web App changes
  nothing; only deleting the plan or scaling to F1 does.
- **Log Analytics has a free grant** and then ~€2.43/GB. The daily cap protects the downside.
- **Private endpoints bill hourly** and never idle down, ~€7/month each.
- **Egress** is usually negligible in a lab. Say you excluded it rather than silently ignoring it.
