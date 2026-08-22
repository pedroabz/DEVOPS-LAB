# ADR 0001 — Azure SQL serverless with auto-pause

**Status:** Accepted · **Date:** 2026-08-22 · **Deciders:** @pedroabz

## Context

The lab needs a relational database for the `Orders` API. It runs on a personal subscription with a
€20/month budget, and it is used for a few hours a week at most — idle well over 95% of the time.

Azure SQL bills compute in one of two ways:

- **Provisioned** — a fixed vCore allocation billed per hour, regardless of use. A database nobody
  touches costs exactly as much as one under load.
- **Serverless** — compute autoscales between a floor and a ceiling, billed **per vCore-second**, and
  deallocates entirely after a configurable idle period. While deallocated, compute billing is zero.

For a workload whose defining characteristic is that it is almost always idle, provisioned compute
means paying continuously for capacity that is doing nothing.

## Decision

Use **General Purpose, serverless, Gen5**, with:

| Setting | Value |
|---|---|
| `sku.name` / `tier` / `family` | `GP_S_Gen5` / `GeneralPurpose` / `Gen5` |
| `sku.capacity` (max vCores) | `1` |
| `properties.minCapacity` (min vCores) | `0.5` |
| `properties.autoPauseDelay` | `60` minutes (the minimum permitted) |

## Consequences

### Positive

- An idle database costs **storage only** — roughly €0.10–0.12/GB/month. A near-empty lab database
  is cents per month rather than tens of euros.
- Compute scales with demand up to 1 vCore without manual resizing.
- The environment can be left running between sessions without guilt, which means fewer teardowns
  and less friction.

### Negative — and this is the important half

**Resuming from a paused state takes 30–60 seconds, and the first connection usually fails rather
than waits.**

This is the single most consequential property of this decision. It is not a defect and it cannot be
configured away — deallocated compute has to be re-provisioned, storage reattached, and the database
brought online. Everything that touches this database must be built to expect it:

1. **The API needs connection resiliency.** EF Core: `EnableRetryOnFailure` with a retry window
   comfortably longer than 60 seconds. Without it, the first request after an idle period returns a
   500 and the app looks broken.
2. **Health checks must not fail the app on a paused database.** A liveness probe that opens a SQL
   connection will fail during resume and can trigger a restart loop, or mark a healthy instance
   unhealthy. Keep the SQL check on *readiness*, not liveness, and give it its own timeout.
3. **Smoke tests in the pipeline will be flaky** unless the first step deliberately warms the
   database and tolerates a slow first response.
4. **The first user-visible request after idle is slow.** Beyond the resume itself, the buffer pool
   is cold, so the following few queries are slower than steady state.
5. **Anything holding a connection open prevents pausing.** A monitoring probe, a keepalive in a
   connection pool, or a forgotten client session will keep the database awake and billing
   indefinitely. If the bill is higher than expected, this is the first thing to check.
6. **An awake-but-idle database still bills** at the `minCapacity` floor. Only a *paused* database
   is free of compute charges.

### Neutral

- Serverless requires the **vCore** purchasing model. The DTU tiers (`Basic`, `S0`, `P1`…) have no
  serverless option, so this also decides the purchasing model.
- `minCapacity` is a decimal, and Bicep has no floating-point type — it must be written as
  `json('0.5')`. A bare `0.5` is a parse error (`BCP020`).

## Alternatives considered

| Option | Why not |
|---|---|
| **Provisioned GP, 1 vCore** | Predictable performance and no resume latency, but bills 24/7 for a database used a few hours a week. Roughly an order of magnitude more expensive for this usage pattern. |
| **DTU Basic / S0** | Cheap and simple, but no auto-pause — still bills continuously — and it locks the lab out of learning the vCore model, which is what real workloads use. |
| **Disable auto-pause** (`autoPauseDelay: -1`) | Removes the resume latency entirely. Costs the entire benefit of the decision. |
| **SQL in a container / SQLite** | Cheapest of all, but the point of the lab is to learn managed Azure SQL, including Entra-only auth and managed identity access. |

## Revisit when

- The API is used often enough that it rarely pauses — at which point provisioned may be both
  cheaper and simpler.
- A `prod` environment appears (v4). Production should almost certainly **not** auto-pause; expect
  this ADR to be superseded for that environment rather than amended.

## References

- [Azure SQL Database serverless tier](https://learn.microsoft.com/azure/azure-sql/database/serverless-tier-overview)
- [Connection resiliency in EF Core](https://learn.microsoft.com/ef/core/miscellaneous/connection-resiliency)
- [`docs/prd/v0-foundations.md`](../prd/v0-foundations.md) §6, §10 — task 4.8 asks you to observe a
  pause/resume cycle first-hand.
