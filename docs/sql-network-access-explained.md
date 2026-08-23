# Azure SQL network access, explained

Part 3 of 3.

- [VNets and subnets](vnet-and-subnets-explained.md) — the network itself
- [App Service VNet integration](app-service-vnet-integration-explained.md) — getting your app into it
- **This doc** — controlling who reaches the database

---

## Start here: two gates, not one

Every connection to your database passes two independent checks:

```
connection → [ 1. NETWORK: are you allowed to even knock? ] → [ 2. IDENTITY: who are you? ] → in
```

**Gate 1 is the network layer.** Firewall rules, VNet rules, private endpoints. It only asks *where
are you coming from*. Fail this and you're refused before anything else happens.

**Gate 2 is Entra.** Your server is Entra-only — no SQL usernames, no passwords — so this asks *are
you a recognised identity with a database user*.

People conflate these. Gate 2 is genuinely strong here: there's no password to steal or brute-force,
and an attacker needs a compromised Entra identity that's already been granted database access. But
gate 1 is what stops the internet from reaching port 1433 in the first place, and "the second gate
is strong" isn't a reason to leave the first one wide open.

---

## The four mechanisms

Azure SQL gives you four ways to control gate 1. They stack — a connection gets in if *any* rule
allows it.

### 1. IP firewall rules

The simplest. A list of allowed source IP ranges.

```bicep
resource rule 'Microsoft.Sql/servers/firewallRules@2025-01-01' = {
  parent: sqlServer
  name: 'my-laptop'
  properties: {
    startIpAddress: '203.0.113.45'
    endIpAddress: '203.0.113.45'
  }
}
```

Good for: your laptop. That's about it.

**The `0.0.0.0` special case.** A rule with start *and* end of `0.0.0.0` doesn't mean "the whole
internet." It's a magic value meaning "anything inside Azure." In the portal it's the checkbox
*"Allow Azure services and resources to access this server."*

The problem is that "inside Azure" includes **other Microsoft customers' subscriptions**. Not just
yours. Any VM anyone owns anywhere in Azure passes this filter. This is the rule currently sitting in
our `sqlServer.bicep`, and it's row 10's ⚠.

### 2. Virtual network rules

Instead of an IP, you name a **subnet**:

```bicep
resource vnetRule 'Microsoft.Sql/servers/virtualNetworkRules@2025-01-01' = {
  parent: sqlServer
  name: 'allow-app-subnet'
  properties: {
    virtualNetworkSubnetId: '<subnet resource id>'
    ignoreMissingVnetServiceEndpoint: false
  }
}
```

This is the row 9 approach. The subnet needs the `Microsoft.Sql` service endpoint on it, and the app
needs `outboundVnetRouting.applicationTraffic: true`, or the traffic never arrives looking like it
came from that subnet.

Why it's better than IP rules: subnets don't change. Scale your app, change tier, redeploy — the
subnet ID is the same, so the rule keeps working. IP-based rules break on all of those.

**What it is not:** private. Traffic still goes to SQL's public endpoint. It travels over Microsoft's
backbone rather than the open internet, and SQL can see which subnet it came from — but the endpoint
is still publicly addressable. You've changed *who's allowed in*, not *whether there's a public door*.

### 3. Private endpoint

The real thing. SQL gets an actual private IP inside your VNet:

```
sql-devopslab-dev-neu-pabz.database.windows.net → 10.0.2.4
```

A private DNS zone rewrites the hostname to resolve to that private address for anything in your
VNet. Combined with `publicNetworkAccess: 'Disabled'`, the public endpoint stops existing.

Costs ~€7/month per endpoint, and needs a private DNS zone plus a link to your VNet.

**Why it's v4 and not now:** with public access off, *nothing outside the VNet can connect*. Your
laptop can't — task 4.7 becomes impossible. GitHub-hosted runners can't, so v1's EF Core migrations
break. Fixing that needs a VPN gateway (~€25/month) or a jump box or a self-hosted runner. That's a
pile of infrastructure whose only purpose is to restore access you deliberately removed. Worth doing
once you've felt the problem.

### 4. `publicNetworkAccess`

The master switch on the server:

```bicep
properties: {
  publicNetworkAccess: 'Enabled'   // or 'Disabled'
}
```

`Disabled` turns off the public endpoint entirely, and every firewall and VNet rule becomes
irrelevant — only private endpoints work. It's the second half of option 3, not a thing you'd use on
its own.

---

## Comparison

| | Who gets in | Survives scaling? | Public endpoint? | Cost/mo |
|---|---|---|---|---|
| `0.0.0.0` rule | Every Azure resource, any tenant | ✅ | yes | €0 |
| Your IP | One address, until your ISP changes it | n/a | yes | €0 |
| App Service outbound IPs | Any app on the same App Service chunk | ❌ breaks on tier change | yes | €0 |
| **VNet rule** | **Your subnet only** | ✅ | yes | €0 (needs B1) |
| Private endpoint | Your VNet only | ✅ | **no** | ~€7 |

---

## Everything you can configure

### On the server (`Microsoft.Sql/servers`)

| Property | What it does | Ours |
|---|---|---|
| `publicNetworkAccess` | Master on/off for the public endpoint | `Enabled` — required while your laptop connects |
| `minimalTlsVersion` | Rejects older TLS | `1.2` ✅ already set |
| `administrators` | Entra admin, and `azureADOnlyAuthentication` | ✅ already set, group-based |
| `restrictOutboundNetworkAccess` | Stops *SQL* making outbound calls | Leave off; only matters for external data sources |

### Firewall rule (`Microsoft.Sql/servers/firewallRules`)

| Property | What it does |
|---|---|
| `startIpAddress` / `endIpAddress` | The allowed range. Same value twice = a single IP |

Name it something meaningful — `my-laptop` beats `AllowAllWindowsAzureIps` for knowing what to delete
later.

### VNet rule (`Microsoft.Sql/servers/virtualNetworkRules`)

| Property | What it does | Ours |
|---|---|---|
| `virtualNetworkSubnetId` | The subnet to trust | The app subnet |
| `ignoreMissingVnetServiceEndpoint` | Create the rule even if the service endpoint isn't there yet | `false` — you *want* it to fail loudly if the endpoint is missing, otherwise you get a rule that silently never matches |

That last flag is worth understanding. Setting it `true` is tempting to dodge a dependency ordering
problem, and it produces exactly the failure mode that's hardest to debug: a rule that exists, looks
right, and does nothing.

---

## Trade-offs for this project

**Doing rows 8–10 (VNet + service endpoint + VNet rule + your IP):**

Gains — the database is reachable only from your subnet and your laptop. "All of Azure" goes away.
The rule survives scaling and tier changes. And you learn the mechanism that private endpoints build
on.

Costs — B1 instead of F1 (~€11.53/month), three new resources, and a new silent failure mode if the
routing setting is wrong.

**Staying with `0.0.0.0`:** free, works immediately, and gate 2 is genuinely strong. But the network
boundary is meaningless, and it's the thing you'd be embarrassed to explain in an interview.

---

## What I'd do here

1. **Delete** the `AllowAllWindowsAzureIps` rule.
2. **Add** a firewall rule for your home IP, named `my-laptop`, so task 4.7 works.
3. **Add** a VNet rule for the app subnet, with `ignoreMissingVnetServiceEndpoint: false`.
4. **Keep** `publicNetworkAccess: 'Enabled'` — you need it for the laptop rule to mean anything.
5. **Defer** private endpoints to v4, when you're ready to also build the way back in.

One ordering detail for when we write it: the VNet rule depends on the subnet existing *with* the
service endpoint, and the app's routing setting depends on the subnet too. So the deployment order is
VNet → SQL VNet rule → App Service integration. Bicep works most of this out from symbolic
references, but it's worth knowing what depends on what when something fails.
