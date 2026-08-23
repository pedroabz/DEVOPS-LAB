# VNets and subnets, explained

Part 1 of 3 on the networking for rows 8–10.

- **This doc** — what a VNet is and why PaaS makes it weird
- [App Service VNet integration](app-service-vnet-integration-explained.md) — getting your app into it
- [SQL network access](sql-network-access-explained.md) — the four ways to control who reaches the DB

---

## The thing that trips everyone up

In a data centre, "network" is physical. Machines are plugged into switches. Two machines can talk
because there's literally a cable path between them.

In Azure, none of that exists. There are no cables you control. So Azure gives you a **virtual
network** — a made-up private network you define in software, and Azure pretends it's real.

Here's the part that confuses people coming from on-prem: **most Azure PaaS services aren't in your
network at all, and never were.** Your App Service and your SQL database don't live in a VNet by
default. They live on Microsoft's shared infrastructure with public addresses. When your app talks
to your database, that traffic goes out to the public internet-facing endpoint and back.

Both are "in Azure," in "the same region," in "the same resource group" — and they're still talking
over public addresses. Resource groups are a billing and lifecycle grouping. They have nothing to do
with networking.

So the VNet isn't something you're adding *on top of* an existing private network. You're creating
the private network for the first time.

---

## What a VNet actually is

A range of private IP addresses that you own, inside Azure.

```
VNet: 10.0.0.0/16     ← 65,536 addresses, all yours
```

The `/16` is CIDR notation — it says how many of the 32 bits are fixed. `/16` fixes the first 16
bits (`10.0`), leaving 16 bits free, so `10.0.0.0` through `10.0.255.255`.

Smaller number = bigger network:

| CIDR | Addresses | Rough use |
|---|---|---|
| `/16` | 65,536 | A whole VNet |
| `/24` | 256 | A comfortable subnet |
| `/26` | 64 | Recommended minimum for App Service |
| `/28` | 16 | Absolute minimum for App Service |

These are **private** ranges (`10.x`, `172.16–31.x`, `192.168.x`). They don't exist on the public
internet. Anyone can use `10.0.0.0/16` in their own VNet, and it doesn't collide with yours, because
the two networks never meet.

Nothing about this costs money. A VNet is free. Subnets are free. You're charged for things you put
in it, and for gateways, but the network itself is bookkeeping.

---

## Subnets

A subnet is a slice of the VNet's range, and it's the unit everything actually attaches to. You
never put a resource "in a VNet" — you put it in a subnet.

```
VNet          10.0.0.0/16
├── subnet-app     10.0.1.0/24     ← the Web App integrates here
└── subnet-data    10.0.2.0/24     ← private endpoints would go here (v4)
```

Subnets matter because they're the unit of *policy*. Security rules, route tables, service
endpoints, and "who is allowed to talk to my database" are all expressed per-subnet. One subnet with
everything in it means you can't tell those things apart.

### Azure steals five addresses from every subnet

A `/24` gives you 256 addresses but only **251 usable**. Azure reserves five in every subnet:

- the first — network address
- the second — Azure's default gateway
- the third and fourth — Azure DNS
- the last — broadcast

Which is why a `/29` (8 addresses) leaves you 3, and why the App Service minimum of `/28` (16) gives
you 11 usable. Easy to size a subnet, do the maths in your head, and be off by five.

### Delegation

Some services need to inject their own hardware into your subnet. They can't do that unless you
formally hand the subnet over. That's **delegation**:

```
delegations: [ { name: 'appservice', properties: { serviceName: 'Microsoft.Web/serverFarms' } } ]
```

Once delegated, that subnet belongs to App Service. Nothing else can go in it. This is why you need
a dedicated subnet per App Service plan rather than one shared subnet for everything.

---

## What you configure in Bicep

Resource type: `Microsoft.Network/virtualNetworks`.

### On the VNet

| Property | What it does | For us |
|---|---|---|
| `addressSpace.addressPrefixes` | The overall range. An array, so a VNet can own several. | `['10.0.0.0/16']` — huge, free, no reason to be stingy |
| `subnets` | Defined inline here, or as separate child resources | Inline is simpler while there are two |
| `dhcpOptions.dnsServers` | Custom DNS instead of Azure's | Leave unset. Only needed for private endpoints (v4) or on-prem DNS |

### On each subnet

| Property | What it does | For us |
|---|---|---|
| `addressPrefix` | This subnet's slice | `10.0.1.0/24` for the app |
| `delegations` | Hands the subnet to a service | `Microsoft.Web/serverFarms` on the app subnet |
| `serviceEndpoints` | Tags outbound traffic to a named Azure service with this subnet's identity | `Microsoft.Sql` — this is what makes row 9 possible |
| `networkSecurityGroup` | Firewall rules on the subnet | Not needed yet; App Service integration already restricts a lot |
| `routeTable` | Custom routing | No |
| `privateEndpointNetworkPolicies` | Whether NSG rules apply to private endpoints in this subnet | Only relevant in v4 |

### Inline vs separate subnet resources

You can declare subnets inside the VNet, or as `Microsoft.Network/virtualNetworks/subnets`
resources. Inline reads better, but there's a real trap: **if you later add a subnet as a separate
resource while others are inline, deployments can wipe the inline ones**, because ARM treats the
VNet's `subnets` array as the full desired state. Pick one style and stick to it. For two subnets
that never change, inline is fine.

---

## Trade-offs

**What you gain:** a place to stand. Once your app is in a subnet, you can say "only this subnet may
reach the database" instead of "this IP address may," and IP addresses change while subnets don't.
Everything else in v4 — private endpoints, NSGs — needs a VNet to exist first.

**What it costs:** nothing in money, some in complexity. Three new concepts (address space,
delegation, service endpoints), a new failure mode (traffic silently not going where you assumed),
and an App Service tier bump to B1, because Free can't integrate with a VNet.

**What it doesn't do:** a VNet does not make your app private. Your Web App still has a public
`.azurewebsites.net` address that anyone can hit. VNet integration is about **outbound** traffic —
where your app's calls go. Locking down inbound is a separate mechanism, covered in the next doc.

---

## What I'd do here

- **One VNet**, `10.0.0.0/16`. No reason to size it carefully; it's free and unused space costs
  nothing.
- **One subnet now**, `10.0.1.0/24`, delegated to `Microsoft.Web/serverFarms`, with the
  `Microsoft.Sql` service endpoint on it. That's rows 8 and 9.
- **Leave room for a second subnet** at `10.0.2.0/24` for v4's private endpoints. Don't create it
  yet — an empty subnet does nothing.
- `/24` rather than the `/26` minimum. Same cost, and you'll never think about it again.

Next: [how the App Service actually gets into that subnet](app-service-vnet-integration-explained.md)
— including the one setting that makes the difference between this working and silently doing
nothing.
