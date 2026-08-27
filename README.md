# devops-lab

A hands-on monorepo for practising **Azure** and **DevOps** skills end to end: infrastructure as code,
an application, event-driven compute, and the pipelines that ship all of it.

The point is not the application. The application is deliberately boring — a small CRUD API over
`Orders` — so that all the interesting complexity lives where the learning is: Bicep, identity,
telemetry, gateways, and CI/CD.

---

## The idea

One repository holds three kinds of thing, versioned and deployed together:

1. **`iac/`** — every Azure resource, declared in Bicep. Nothing is created by hand in the portal
   after the initial account bootstrap. If it exists in Azure, it exists in this folder.
2. **`src/orders-api/`** — an ASP.NET Core Minimal API (.NET 10) doing CRUD against Azure SQL, instrumented
   with Application Insights.
3. **`src/functions/`** — Azure Functions that react to events. The first one drains a Service Bus
   queue and calls the API.

Everything is glued by **GitHub Actions** using **OIDC federated credentials** — no long-lived
secrets in the repo — and every service talks to every other service using **managed identity**
rather than connection strings wherever Azure supports it.

### Target architecture

```
                            ┌──────────────────────────────┐
                            │        Azure API            │
   client ──────────────▶   │      Management (v2)         │  ◀── OAuth 2.0 / Entra ID
                            │  rate limit · validate JWT   │
                            └───────────────┬──────────────┘
                                            │
                                            ▼
   ┌──────────────┐  message   ┌────────────────────┐  HTTP   ┌──────────────────┐
   │ Service Bus  │ ─────────▶ │  Function App      │ ──────▶ │  Orders API      │
   │ order-events │            │  OrderIngestor     │         │  App Service     │
   └──────────────┘            │  (Flex Consumption)│         │  (.NET 10)       │
                               └─────────┬──────────┘         └────────┬─────────┘
                                         │                             │
                                         │                             │ managed identity
                                         │                             ▼
                                         │                    ┌──────────────────┐
                                         │                    │   Azure SQL      │
                                         │                    │   (serverless)   │
                                         │                    └──────────────────┘
                                         │                             │
                                         └──────────┬──────────────────┘
                                                    ▼
                                       ┌────────────────────────────┐
                                       │ Application Insights       │
                                       │ + Log Analytics workspace  │
                                       │ distributed traces E2E     │
                                       └────────────────────────────┘
```

The distributed trace is a first-class goal: one `operation_id` should span
**Service Bus message → Function → HTTP call → API → SQL query**, visible in a single
App Insights transaction view.

---

## Roadmap

Built in slices. Each version is deployable and demoable on its own.

### v0 — Foundations _(current)_ — [PRD + task list](docs/prd/v0-foundations.md)
- [x] Monorepo layout, docs, conventions
- [ ] Azure account + subscription + budget alerts ([`docs/azure-setup.md`](docs/azure-setup.md))
- [ ] GitHub OIDC federated identity, no stored secrets
- [ ] Bicep: resource group, Log Analytics, **Application Insights**, **Azure SQL** (serverless),
      App Service plan + Web App
- [ ] **VNet + subnet with a `Microsoft.Sql` service endpoint**, App Service VNet integration, and a
      SQL virtual network rule — so the database is reachable only from that subnet, never from
      "all of Azure"
- [ ] `infra-ci` workflow: lint + `what-if` on PR, deploy on merge

### v1 — The API
- [ ] Minimal API CRUD over `Orders`, EF Core, migrations applied by pipeline
- [ ] App Insights: auto-instrumentation, custom metrics, structured logs, health checks
- [ ] **Managed identity** auth to Azure SQL (zero connection-string passwords)
- [ ] `api-ci` workflow: build → test → publish → deploy to staging slot → swap
- [ ] Smoke tests against the deployed environment

### v1.5 — Dashboards & alerting

Exceptions have to exist before you can chart or alert on them, so this follows v1. Everything here
is Bicep like the rest — no dashboards clicked together in the portal.

**The dashboard** — an [Azure Workbook](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-overview)
(`Microsoft.Insights/workbooks`), deployed as code, showing:
- [ ] Exception rate over time, and top exception types by count
- [ ] Failed requests by endpoint and status code
- [ ] Dependency failures — SQL timeouts, HTTP call failures
- [ ] Slowest endpoints (P50/P95/P99)
- [ ] Log volume, and how close ingestion is to the daily cap
- [ ] A KQL query library kept in the repo, so the queries are reviewable and reusable

> Workbooks, not Azure Dashboards. Workbooks support parameters, KQL, and sensible source control;
> Azure Dashboards are a portal-layout artifact that round-trips badly through IaC.

**The email alerts** — Azure Monitor, in two parts:
- [ ] An **Action Group** (`Microsoft.Insights/actionGroups`) holding the email receiver. This is the
      "who gets told" half, reusable across every rule.
- [ ] **Log search alert rules** (`Microsoft.Insights/scheduledQueryRules`) — KQL against App Insights
      for *specific* exception signatures, so you alert on what matters instead of on everything.
- [ ] **Metric alerts** for the coarse signals: failed-request rate, server response time, availability.
- [ ] Route App Insights **Smart Detection** (anomaly detection) to the same Action Group.
- [ ] An alert for the Log Analytics **daily cap being hit** — otherwise telemetry silently stops and
      every other alert goes quiet with it.
- [ ] Tune severities and add suppression/action rules so a single incident doesn't send 200 emails.

> Email is the v1.5 target because it needs no extra service. The Action Group abstraction means
> adding Slack, Teams, SMS, or a webhook later is a change to one resource, not to every rule.

### v2 — Identity, frontend & a BFF — [PRD](docs/prd/v2-identity-frontend-bff.md)
- [ ] Entra app registrations declared in **Bicep** via the Microsoft Graph extension
- [ ] React SPA on **Static Web Apps** (free tier) — one form, user signs in with Entra ID
- [ ] **BFF** on the existing App Service plan, enforcing per-user RBAC (`Orders.Reader` / `Orders.Admin`)
- [ ] BFF calls the API with **its own token** via managed identity — the user's token is never forwarded
- [ ] API locked to the BFF, plus a direct admin route for you
- [ ] Two test users, to prove Reader and Admin get different answers

### v3 — Event-driven
- [ ] Service Bus namespace + `order-events` queue + dead-letter handling
- [ ] `OrderIngestor` Function (Flex Consumption) → calls the API
- [ ] Trace correlation across the queue boundary
- [ ] `functions-ci` workflow

### v4 — API Management
- [ ] **APIM in front of the API** — above both callers, the BFF and the Functions
- [ ] JWT validation, rate limiting, products, versioning
- [ ] API surface locked to APIM only
- [ ] **Key Vault**, *if* anything by then actually holds a secret

### v5 — Production hardening _(stretch)_
- [ ] `prod` environment + promotion pipeline with manual approval
- [ ] Private endpoints (SQL public access off entirely) + the VPN/jump-box access it forces
- [ ] Availability tests (synthetic monitoring) feeding the v1.5 alerts
- [ ] On-call escalation: severity-based routing, action rules, maintenance windows
- [ ] Load test in the pipeline, cost reporting

---

## Repository layout

```
devops-lab/
├── .github/workflows/       CI/CD pipelines (GitHub Actions)
├── docs/                    Project documentation
│   ├── azure-setup.md       ← START HERE: one-time Azure account bootstrap
│   ├── conventions.md       Naming, tagging, branching, environments
│   └── adr/                 Architecture decision records
├── iac/                   All Bicep IaC
│   ├── main.bicep           Subscription-scope entry point
│   ├── modules/             One module per resource family
│   └── params/              Per-environment .bicepparam files
├── src/
│   ├── api/                 DevOpsLab.Api — the CRUD API
│   ├── functions/           DevOpsLab.Functions.* — event-driven compute
│   └── shared/              DevOpsLab.Contracts — DTOs shared by API + Functions
├── tests/                   Unit + integration tests
└── scripts/                 Bootstrap and helper scripts
```

---

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| IaC | Bicep | Native to Azure, no state file to manage, first-class `what-if` |
| Language | C# / .NET 10 | LTS, strongest Azure story: managed identity, App Insights, SB bindings |
| CI/CD | GitHub Actions + OIDC | No secrets at rest; workflows live beside the code |
| API hosting | App Service (Linux) | Easy managed identity; free on F1. Slots need S1 — scale up only to practise |
| Function hosting | **Flex Consumption** | .NET 10 is *not* supported on Linux Consumption — Flex is required |
| SQL | Azure SQL serverless, auto-pause | Scales to zero when idle; keeps the lab cheap |
| Auth to data | Managed identity everywhere | The habit worth building; no passwords to rotate |
| Environments | `dev` now, `prod` at v4 | Keeps spend near zero while the shape is still moving |

Longer-form reasoning goes in [`docs/adr/`](docs/adr/) as decisions get made.

---

## Getting started

1. Read and follow [**`docs/azure-setup.md`**](docs/azure-setup.md) — account, subscription,
   budget guardrails, CLI tooling, and the GitHub ↔ Azure OIDC trust.
2. Skim [`docs/conventions.md`](docs/conventions.md) so resource names and tags stay consistent.
3. Then start on v0: the Bicep foundation.

> **Cost warning.** This lab is designed to run for a few euros a month, but a mis-sized SKU can
> cost real money fast. The budget alert in the setup guide is not optional — set it before you
> deploy anything.
