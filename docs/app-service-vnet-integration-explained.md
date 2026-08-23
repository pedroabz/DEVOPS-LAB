# App Service VNet integration, explained

Part 2 of 3.

- [VNets and subnets](vnet-and-subnets-explained.md) — the network itself
- **This doc** — getting your app into it
- [SQL network access](sql-network-access-explained.md) — controlling who reaches the DB

---

## The problem

You have a VNet with a subnet. Your Web App is still not in it, and can't be — a Web App isn't a VM
you can assign an IP to. It runs on shared infrastructure, on a chunk of machines you don't control,
alongside other customers' apps.

VNet integration is Azure's answer: it gives your app **a foot in your subnet for outgoing traffic**.

---

## What it actually does

It changes **which door your app's outgoing traffic leaves by**. That's it.

It does not block anything. It does not hide anything. Your app can reach exactly what it could
before — SQL, Key Vault, the Stripe API, any random website. Same destinations, different route:

```
Without integration:   app ──► straight out ──► SQL
With integration:      app ──► through your subnet ──► out ──► SQL
```

Why bother? Because of the **return address**. Traffic leaving through your subnet arrives carrying
that subnet's identity instead of the shared chunk's public IP. That's what lets SQL say "I trust
that subnet" — and a subnet, unlike an IP address, doesn't change when you scale or switch tiers.

So what you're buying is: *my app can prove where it's calling from.*

### It only touches traffic your app starts

This is the part people get wrong, so let's be precise about the two directions:

| Direction | What it is | Does integration change it? |
|---|---|---|
| **Outbound** — your app starts the conversation | Your app calling SQL, Key Vault, an external API | ✅ Yes — reroutes it through your subnet. Doesn't block it. |
| **Inbound** — someone else starts the conversation | A browser hitting your `.azurewebsites.net` URL | ❌ No — completely untouched |

Your app keeps its public address and anyone on the internet can still call it. Integration does
nothing about that. Locking down inbound is a separate feature: access restrictions, or a private
endpoint on the app itself.

### And if you actually want to block outbound?

That's a third thing, which integration doesn't give you. You'd add it on top:

- an **NSG** on the subnet with deny rules, or
- a **route table** forcing traffic through a firewall

Neither is in scope here. Worth knowing they exist so you don't expect integration to do their job.

---

## The requirements, all of which bite

**Basic tier or higher.** Free and Shared can't do it at all. This is why row 6 moved from F1 to B1.
The integration itself is free once you're on B1.

**A dedicated, empty subnet.** No VMs, no NICs, no private endpoints, nothing else. One App Service
plan per subnet.

**Delegated to `Microsoft.Web/serverFarms`.** Without the delegation, integration fails.

**At least a `/28`.** Microsoft recommends `/26`. App Service takes IPs from the subnet for each
instance, and needs spare addresses during scaling and platform upgrades — it uses more than you'd
expect from instance count alone.

**Same region as the app.** Regional integration only reaches VNets in the app's own region.

---

## The setting that decides whether any of this works

Here's the trap. By default, VNet integration only routes **private** traffic — the RFC1918 ranges
(`10.x`, `172.16-31.x`, `192.168.x`) — into your VNet. Everything else takes the normal public route
straight out, completely bypassing your subnet.

Azure SQL's endpoint is a **public** address. So with default settings:

1. You create the VNet ✅
2. You add the service endpoint ✅
3. You integrate the app ✅
4. You add a SQL rule allowing your subnet ✅
5. Your app connects to SQL... **from the shared chunk's public IP, not your subnet**
6. SQL rejects it, because that IP isn't allowed

Everything looks configured. Nothing works. And the error tells you an IP is blocked, not that your
routing is wrong.

The fix is to tell App Service to route application traffic through the VNet:

```bicep
outboundVnetRouting: {
  applicationTraffic: true
}
```

> **Naming note:** you'll find a lot of examples using `vnetRouteAllEnabled: true` or the app setting
> `WEBSITE_VNET_ROUTE_ALL`. Those are the **legacy** names. They still work, but
> `outboundVnetRouting` is the current property. Same idea.

---

## What you configure in Bicep

Two pieces: connect the app to the subnet, and set the routing.

### Connecting

Either a property on the site:

```bicep
properties: {
  virtualNetworkSubnetId: '<subnet resource id>'
}
```

or a child resource, `Microsoft.Web/sites/networkConfig` named `virtualNetwork`. The property is
simpler and keeps everything in one place. Don't do both — they fight.

### Routing

| Property | What it does | For us |
|---|---|---|
| `outboundVnetRouting.applicationTraffic` | Routes your app's own calls (SQL, HTTP, etc.) through the VNet | **`true`** — required, see above |
| `outboundVnetRouting.allTraffic` | Everything, including platform traffic: container pulls, content share, backups, managed-identity token requests | Probably not — see below |
| `outboundVnetRouting.imagePullTraffic` | Just container image pulls | No, we're not using containers |
| `outboundVnetRouting.contentShareTraffic` | Just the app's file storage | No |
| `outboundVnetRouting.managedIdentityTraffic` | Just Entra token acquisition | No |

**Why not `allTraffic: true`?** It sounds safer, and Microsoft's docs recommend it — but it also
sends platform traffic through your subnet, including managed identity token requests to Entra. If
you later put an NSG on that subnet and get a rule slightly wrong, your app can't get a token, and
therefore can't authenticate to SQL, and the error will point at SQL rather than at your NSG. Start
with `applicationTraffic` only, and turn on more when you have a reason.

---

## Trade-offs

**What you gain:** your app's outbound traffic carries your subnet's identity. That's what lets SQL
trust "this subnet" rather than "these IP addresses," and unlike IPs, a subnet doesn't change when
you scale or switch tiers.

**What it costs:**

- B1 minimum, ~€11.53/month
- A new silent failure mode — routing misconfigured means traffic quietly takes the public path
- Debugging gets harder. "Connection refused" now has two possible causes: permissions, or traffic
  not going where you think

**What it doesn't do:** nothing about inbound. Your app is still publicly reachable. If that bothers
you, that's access restrictions or a private endpoint on the app — a separate decision, and one
worth taking separately.

---

## How to tell whether it's working

Don't assume from a green deployment. From the app's Kudu console, or a debug endpoint:

- Check the app's outbound IP: if it's a `10.0.1.x`, routing is working. If it's a public IP, it
  isn't.
- Or just try the SQL connection with the `0.0.0.0` firewall rule removed. If it connects, the
  subnet rule is doing the work. If it doesn't, routing is wrong.

That second test is the honest one, because it fails in exactly the way a misconfiguration would.

---

## What I'd do here

- `virtualNetworkSubnetId` on the Web App, pointing at the app subnet
- `outboundVnetRouting.applicationTraffic: true` — non-negotiable, this is the setting that makes it
  real
- Leave the other four routing options off
- Leave inbound alone for now. Locking down public access to the app is a real question, but it's
  APIM's job in v3, and deciding it now would be premature

Next: [what SQL does with all this](sql-network-access-explained.md) — and the four different
mechanisms it offers, which are easy to confuse.
