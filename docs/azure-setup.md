# Azure setup guide

Everything you need to do **once**, by hand, before any code or Bicep in this repo can deploy.
After this guide, all further Azure resources are created by pipelines from `iac/`.

Written for **macOS + zsh**. Estimated time: 45–60 minutes, most of it waiting on account verification.

---

## Contents

1. [What you'll end up with](#1-what-youll-end-up-with)
2. [Create the Azure account](#2-create-the-azure-account)
3. [Understand the hierarchy](#3-understand-the-hierarchy)
4. [Set cost guardrails — do this before deploying anything](#4-set-cost-guardrails)
5. [Install local tooling](#5-install-local-tooling)
6. [Sign in and prepare the subscription](#6-sign-in-and-prepare-the-subscription)
7. [Create the GitHub repository](#7-create-the-github-repository)
8. [Wire GitHub to Azure with OIDC](#8-wire-github-to-azure-with-oidc)
9. [Configure GitHub secrets and variables](#9-configure-github-secrets-and-variables)
10. [Verify the connection](#10-verify-the-connection)
11. [Prepare for later phases](#11-prepare-for-later-phases)
12. [Cost expectations and hygiene](#12-cost-expectations-and-hygiene)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. What you'll end up with

A checklist to tick off. By the end of this guide you should have:

- [x] An Azure account with an active subscription
- [x] The **spending limit** confirmed ON, with the $200 / 30-day free credit applied
- [x] A **budget with email alerts** on that subscription — *different from the spending limit, see §4*
- [x] `az`, `bicep`, `gh`, `jq`, and the .NET 10 SDK installed locally
- [ ] Azure Functions Core Tools v4 — *deferred to v2; blocked on Xcode Command Line Tools, see §13*
- [x] Required resource providers registered
- [x] A GitHub repository holding this monorepo — [`pedroabz/DEVOPS-LAB`](https://github.com/pedroabz/DEVOPS-LAB)
- [x] An Entra ID **app registration** with **federated credentials** — GitHub Actions can deploy to Azure with no stored secret
- [x] Repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`
- [x] A green `az account show` running inside a GitHub Actions job — [run 32280219877](https://github.com/pedroabz/DEVOPS-LAB/actions/runs/32280219877)

**Setup complete.** Recorded values for this lab:

| Name | Value |
|---|---|
| Subscription | `25681d80-476e-40a6-9d21-da4138a1cd27` (*Azure subscription 1*) |
| Tenant | `61bd2f87-a074-421c-9c1e-a2137bc0c1ca` |
| Deployment identity | `sp-devopslab-github-dev` → client ID `2e50e486-a03e-402f-9e2e-47f530aac6b6` |
| Repository | `pedroabz/DEVOPS-LAB` |
| Region | `northeurope` |

None of these are secrets — they are identifiers. The only thing that can authenticate as that
identity is a GitHub Actions token from this specific repository.

Nothing else. No resource groups, no SQL, no App Service — those come from Bicep in v0.

---

## 2. Create the Azure account

### 2.1 Sign up

Go to **<https://azure.microsoft.com/free>** and start the free account flow.

You'll need:

| Thing | Notes |
|---|---|
| A Microsoft account | A personal one (Outlook/Hotmail/Gmail-backed) is fine. Consider making a *fresh* one dedicated to this lab so your personal mail and cloud identity stay separate. |
| A phone number | For SMS verification. |
| A credit or debit card | Required for identity verification even though you won't be charged. A temporary ~$1 authorisation is placed and then reversed. Prepaid/virtual cards are frequently rejected — use a real one. |

The free account gives you **$200 (or local equivalent) in credit valid for 30 days**, plus a set of
services free for 12 months and 65+ services that are always free within monthly limits. There is a
limit of one free account per person.

### 2.2 Understand the spending limit

New free subscriptions have a **spending limit turned ON**. This is your single best protection:

- When the $200 credit is exhausted, Azure **disables** your resources rather than charging your card.
- You are never charged unless you explicitly convert to pay-as-you-go.
- The downside: "disabled" means your lab stops working until you upgrade.

**Leave the spending limit on.** You want the lab to break, not your bank account.

### 2.3 After the 30 days

When the credit expires, the subscription is disabled until you convert it to **pay-as-you-go**.
At that point the always-free tiers still apply, and this lab — sized as recommended in
[§12](#12-cost-expectations-and-hygiene) — should cost single-digit euros per month. Section 12
also covers how to stop paying between working sessions.

> If you have access to a **Visual Studio subscription** (Dev Essentials, Professional, Enterprise)
> through work or school, use that instead — it grants recurring monthly Azure credit
> ($50–$150/month) rather than a one-off 30-day grant, which suits a long-running lab far better.

---

## 3. Understand the hierarchy

Worth five minutes now because every `az` command and every Bicep scope depends on it:

```
Entra ID Tenant                  ← your identity boundary (users, groups, app registrations)
└── Subscription                 ← your billing + quota boundary
    └── Resource Group           ← lifecycle + RBAC boundary  (rg-devopslab-dev-neu)
        └── Resource             ← the actual thing  (sql-devopslab-dev-neu)
```

- **Tenant**: where identities live. App registrations, managed identities, and groups are tenant-level.
- **Subscription**: what gets billed. `main.bicep` in this repo deploys at *subscription scope* so it
  can create the resource group itself.
- **Resource group**: delete it and everything inside it goes. One per environment in this lab.

Take note of your **tenant ID** and **subscription ID** — you'll need both shortly.

---

## 4. Set cost guardrails

**Do this before you deploy a single resource.** The spending limit protects your card; a budget
alert protects you from burning the $200 credit in a weekend on a mis-sized SKU.

### 4.1 Create a budget (portal)

1. Portal → search **Cost Management + Billing** → **Cost Management** → **Budgets**
2. Ensure the scope at the top is your subscription → **+ Add**
3. Configure:
   - **Name**: `budget-devopslab-monthly`
   - **Reset period**: Monthly
   - **Creation date / expiration**: today / +1 year
   - **Amount**: `20` (in your currency — deliberately low so alerts are loud)
4. **Next** → set alert conditions:

   | Type | % of budget | Action |
   |---|---|---|
   | Actual | 50% | email you |
   | Actual | 80% | email you |
   | Forecasted | 100% | email you |

5. Enter your email address under **Alert recipients** → **Create**

### 4.2 Turn on the cost anomaly alert

Cost Management → **Cost alerts** → **+ Add** → **Anomaly alert**. Catches "something started
running that you didn't expect" faster than a monthly budget does.

### 4.3 Sanity-check daily

Cost Management → **Cost analysis**, group by **Resource**. Get in the habit of glancing at it after
each deployment. In v0 we will also codify the budget in Bicep so it's reproducible.

---

## 5. Install local tooling

You already have Homebrew and .NET 8. You need .NET **10** and the Azure tooling.

### 5.1 .NET 10 SDK

This repo targets `net10.0`. Your machine currently has only the 8.0.129 SDK.

Download the **.NET 10 SDK (Arm64) installer** from
<https://dotnet.microsoft.com/download/dotnet/10.0> and run the `.pkg`, or:

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
/tmp/dotnet-install.sh --channel 10.0 --install-dir "$HOME/.dotnet"

# add to ~/.zshrc
echo 'export PATH="$HOME/.dotnet:$PATH"' >> ~/.zshrc
echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> ~/.zshrc
source ~/.zshrc
```

Verify — you should see a `10.0.x` SDK listed:

```bash
dotnet --list-sdks
```

> Keep .NET 8 installed. The Azure Functions Core Tools host has historically needed an
> older runtime present alongside .NET 10 to start reliably.

### 5.2 Azure CLI and Bicep

```bash
brew update && brew install azure-cli
az bicep install          # bicep ships as an az extension, not a separate brew formula
az bicep version
```

### 5.3 Azure Functions Core Tools v4

```bash
brew tap azure/functions
brew install azure-functions-core-tools@4
func --version
```

### 5.4 GitHub CLI

```bash
brew install gh
gh auth login             # choose GitHub.com → HTTPS → login with a browser
```

### 5.5 Optional but useful

```bash
brew install sqlcmd       # query Azure SQL from the terminal
brew install jq           # parsing az CLI JSON output; used by scripts in this repo
```

### 5.6 VS Code extensions

These are declared in [`.vscode/extensions.json`](../.vscode/extensions.json), so VS Code will
prompt you to install them when you open the workspace. To install them up front:

```bash
for ext in \
  ms-azuretools.vscode-bicep \
  ms-vscode.azure-account \
  ms-azuretools.vscode-azureresourcegroups \
  ms-mssql.mssql \
  ms-dotnettools.csdevkit
do
  code --install-extension "$ext" --force
done
```

| Extension | ID | What you'll use it for |
|---|---|---|
| Bicep | `ms-azuretools.vscode-bicep` | IntelliSense, linting, and the resource visualiser for `iac/` |
| Azure Account | `ms-vscode.azure-account` | Sign-in + subscription picker shared by the Azure extensions |
| Azure Resources | `ms-azuretools.vscode-azureresourcegroups` | Browse deployed resources from the sidebar |
| SQL Server (mssql) | `ms-mssql.mssql` | Query Azure SQL, inspect schema, run migrations by hand |
| C# Dev Kit | `ms-dotnettools.csdevkit` | Solution explorer, test runner, debugger |

Keep the Bicep extension version aligned with `az bicep version` — a mismatch produces linter
warnings the compiler doesn't agree with.

> **Note on Azure Account:** Microsoft has been folding its sign-in flow into the Azure Resources
> extension, and `ms-vscode.azure-account` is on a deprecation path. It still installs and works
> today; if it stops being available, Azure Resources handles authentication on its own and you can
> drop it from the recommendations list.

### 5.7 Verify everything

```bash
az version && az bicep version && func --version && gh --version && dotnet --list-sdks
```

---

## 6. Sign in and prepare the subscription

### 6.1 Log in

```bash
az login
```

A browser opens. After signing in, the CLI prints your subscriptions.

```bash
# See what you have
az account list --output table

# Pin the one you want (use the name or the id)
az account set --subscription "Azure subscription 1"

# Confirm
az account show --output table
```

### 6.2 Capture the IDs you'll need

```bash
export AZ_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZ_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Subscription: $AZ_SUBSCRIPTION_ID"
echo "Tenant:       $AZ_TENANT_ID"
```

Keep this shell open for the rest of the guide, or note the values down.

### 6.3 Choose your region

Pick one region and use it everywhere — cross-region traffic costs money and adds latency.
Good European options: `westeurope` (Netherlands), `northeurope` (Ireland), `swedencentral`,
`francecentral`. In the Americas: `eastus`, `brazilsouth`.

```bash
export AZ_LOCATION=northeurope    # change to suit; this becomes the `location` param in Bicep
```

> ⚠️ **`westeurope` is closed to new customers.** A `what-if` against it fails every resource with
> `RequestDisallowedByAzure — The selected region is currently not accepting new customers`. This is a
> subscription-age restriction, not a quota you can request an increase for, and it is not visible
> until you try to deploy. This lab uses **`northeurope`**; `swedencentral`, `francecentral` and
> `uksouth` were also verified open. Test a candidate region with a `what-if` **before** you commit
> to it — the region is threaded through every resource name and moving later means recreating
> everything.

> Some regions periodically refuse new App Service plans or SQL servers due to capacity.
> `westeurope` and `eastus` are the safest bets. Check with:
> `az vm list-skus --location $AZ_LOCATION --output table | head` (slow, but tells you if the region responds).

### 6.4 Register resource providers

A fresh subscription has most providers unregistered. Registering is idempotent, takes a few
minutes, and prevents confusing `MissingSubscriptionRegistration` failures during your first deploy.

```bash
for provider in \
  Microsoft.Web \
  Microsoft.Sql \
  Microsoft.Insights \
  Microsoft.OperationalInsights \
  Microsoft.ServiceBus \
  Microsoft.KeyVault \
  Microsoft.Storage \
  Microsoft.ManagedIdentity \
  Microsoft.ApiManagement \
  Microsoft.Network \
  Microsoft.Authorization \
  Microsoft.Resources \
  Microsoft.AlertsManagement
do
  echo "Registering $provider..."
  az provider register --namespace "$provider"
done
```

Check progress (all should read `Registered`; give it 5–10 minutes):

```bash
az provider list \
  --query "[?registrationState!='NotRegistered'].{Provider:namespace, Status:registrationState}" \
  --output table | sort
```

> Match provider names case-**insensitively** if you filter by name. Azure returns some namespaces
> lower-cased — notably `microsoft.insights` — so a `namespace=='Microsoft.Insights'` filter silently
> returns nothing even though the provider is registering fine.

---

## 7. Create the GitHub repository

From the repo root (`/Users/pedroazeredo/Documents/Repos/devops-lab`):

```bash
git add -A
git commit -m "chore: scaffold monorepo structure and docs"

gh repo create devops-lab --private --source=. --remote=origin --push
```

Capture the repo slug — the OIDC subject claims must match it **exactly, including case**:

```bash
export GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "$GH_REPO"
```

> ⚠️ **Do not assume the slug is what goes in the OIDC subject.** This lab's repo is
> `pedroabz/DEVOPS-LAB` (upper-case — GitHub preserves case in tokens), but more importantly GitHub
> may mint **immutable subject claims** that embed numeric IDs instead of the plain slug. See
> §8.2 — get this wrong and every workflow fails to authenticate.

`gh` must be authenticated before §8.4 and §9, which create the environment and set repo variables:

```bash
gh auth status || gh auth login    # GitHub.com → HTTPS → login with a browser
```

> Private repos are fine. GitHub Actions minutes are free for public repos and generous
> (2,000 min/month) on the free plan for private ones — plenty for this lab.

---

## 8. Wire GitHub to Azure with OIDC

This is the important part, and the piece most tutorials get wrong by telling you to paste a
client **secret** into GitHub. We won't. Instead GitHub Actions presents a short-lived signed token,
Azure verifies it against a **federated credential**, and issues an access token. Nothing secret is
ever stored in the repository.

### 8.1 Create the app registration

```bash
export APP_NAME="sp-devopslab-github-dev"

# Create the application object
export AZ_CLIENT_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --query appId -o tsv)

# Create the service principal (the identity that actually gets role assignments)
az ad sp create --id "$AZ_CLIENT_ID"

echo "Client ID: $AZ_CLIENT_ID"
```

> **If `az ad app create` fails with an authorization error**, your account isn't allowed to register
> applications in the tenant. On a personal free account you are the Global Administrator, so this
> should work. On a work/school tenant, ask an admin — or use a personal tenant for this lab.

### 8.2 Add federated credentials

One credential per trust scenario. The `subject` must match GitHub's token claim **character for
character** — and the claim is very probably not the plain `owner/repo` slug you expect.

#### The immutable-subject gotcha

Most tutorials tell you the subject is `repo:<owner>/<repo>:ref:refs/heads/main`. GitHub now also
mints **immutable subject claims**, which splice the numeric owner ID and repository ID into the
slug so that renaming a user or repo cannot silently hand your Azure trust to whoever claims the old
name. On this repo the real claim is:

```
repo:pedroabz@34903747/DEVOPS-LAB@1339815353:ref:refs/heads/main
        ^^^^^^^^ owner id        ^^^^^^^^^^ repo id
```

A credential registered against the plain slug will **not** match, and you get `AADSTS700213`.

Build the subject prefix from the API instead of typing it, and register **both** forms so the setup
survives GitHub toggling the behaviour either way:

```bash
# Plain slug, e.g. pedroabz/DEVOPS-LAB
export GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# Immutable form, e.g. pedroabz@34903747/DEVOPS-LAB@1339815353
export GH_REPO_IMMUTABLE=$(gh api "repos/${GH_REPO}" \
  --jq '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"')

echo "plain:     $GH_REPO"
echo "immutable: $GH_REPO_IMMUTABLE"
```

```bash
add_fic () {   # $1 = credential name, $2 = subject
  az ad app federated-credential create --id "$AZ_CLIENT_ID" --parameters "{
    \"name\": \"$1\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$2\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
}

for form in "$GH_REPO" "$GH_REPO_IMMUTABLE"; do
  suffix=""; [ "$form" = "$GH_REPO_IMMUTABLE" ] && suffix="-immutable"
  add_fic "github-main${suffix}"    "repo:${form}:ref:refs/heads/main"   # deployments from main
  add_fic "github-pr${suffix}"      "repo:${form}:pull_request"          # `what-if` previews on PRs
  add_fic "github-env-dev${suffix}" "repo:${form}:environment:dev"       # gated/approved deploys
done
```

Registering both is harmless — a federated credential is a matching rule, not a grant. Only a token
that actually presents the subject can use it, and both subjects identify the same repository.

#### If it still fails

Don't guess. The failing `azure/login` step **prints the exact subject it presented**:

```
Federated token details:
 subject claim - repo:pedroabz@34903747/DEVOPS-LAB@1339815353:ref:refs/heads/main
```

Copy that string verbatim into a new credential's `subject` and it will match.

Verify:

```bash
az ad app federated-credential list --id "$AZ_CLIENT_ID" --query "[].{name:name, subject:subject}" -o table
```

### 8.3 Grant Azure permissions

Two roles at **subscription scope**:

```bash
export AZ_SP_OBJECT_ID=$(az ad sp show --id "$AZ_CLIENT_ID" --query id -o tsv)

# Create and manage resources
az role assignment create \
  --assignee-object-id "$AZ_SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/$AZ_SUBSCRIPTION_ID"

# Assign roles to managed identities from Bicep (e.g. API → SQL, Function → Service Bus)
az role assignment create \
  --assignee-object-id "$AZ_SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" \
  --scope "/subscriptions/$AZ_SUBSCRIPTION_ID"
```

Why the second one: `Contributor` deliberately **cannot** create role assignments. Since our Bicep
grants managed identities access to SQL, Service Bus, and Key Vault, the deployment identity needs
that ability. `Role Based Access Control Administrator` is the least-privileged role that allows it
— prefer it over `Owner` or `User Access Administrator`.

Confirm:

```bash
az role assignment list --assignee "$AZ_CLIENT_ID" --all \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

### 8.4 Create the GitHub `dev` environment

```bash
gh api --method PUT "repos/$GH_REPO/environments/dev" --silent && echo "dev environment created"
```

Later you can add required reviewers to a `prod` environment the same way, giving you manual
approval gates.

---

## 9. Configure GitHub secrets and variables

None of these are secrets in the cryptographic sense — a client ID and tenant ID are not
credentials on their own, and there is no password to store. Using **variables** rather than
secrets keeps them readable in logs, which makes debugging far easier.

```bash
gh variable set AZURE_CLIENT_ID       --body "$AZ_CLIENT_ID"       --repo "$GH_REPO"
gh variable set AZURE_TENANT_ID       --body "$AZ_TENANT_ID"       --repo "$GH_REPO"
gh variable set AZURE_SUBSCRIPTION_ID --body "$AZ_SUBSCRIPTION_ID" --repo "$GH_REPO"
gh variable set AZURE_LOCATION        --body "$AZ_LOCATION"        --repo "$GH_REPO"

gh variable list --repo "$GH_REPO"
```

Every workflow that touches Azure then needs these permissions and this login step:

```yaml
permissions:
  id-token: write      # REQUIRED — mints the OIDC token. Without it you get AADSTS700016.
  contents: read

steps:
  - uses: azure/login@v2
    with:
      client-id:       ${{ vars.AZURE_CLIENT_ID }}
      tenant-id:       ${{ vars.AZURE_TENANT_ID }}
      subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

---

## 10. Verify the connection

Create a throwaway workflow to prove the trust works before writing any Bicep.

```bash
cat > .github/workflows/verify-azure-login.yml <<'YAML'
name: verify-azure-login

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: azure/login@v2
        with:
          client-id:       ${{ vars.AZURE_CLIENT_ID }}
          tenant-id:       ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - name: Show account
        run: |
          az account show --output table
          az group list --output table
YAML

git add .github/workflows/verify-azure-login.yml
git commit -m "ci: add temporary Azure OIDC verification workflow"
git push

gh workflow run verify-azure-login
sleep 10 && gh run watch
```

A green run showing your subscription means **the hard part is done**. Delete the workflow
afterwards — the real pipelines land in v0.

```bash
git rm .github/workflows/verify-azure-login.yml
git commit -m "ci: remove temporary verification workflow"
git push
```

---

## 11. Prepare for later phases

Not needed today. Listed here so nothing surprises you mid-roadmap.

### 11.1 Azure SQL admin group (needed in v0/v1)

Azure SQL should have an **Entra ID group** as its administrator rather than a person — that way
both you and the deployment identity can administer it, and nothing breaks if an account changes.

```bash
az ad group create \
  --display-name "sg-devopslab-sql-admins" \
  --mail-nickname "sg-devopslab-sql-admins"

export SQL_ADMIN_GROUP_ID=$(az ad group show --group "sg-devopslab-sql-admins" --query id -o tsv)

# add yourself
az ad group member add --group "$SQL_ADMIN_GROUP_ID" \
  --member-id "$(az ad signed-in-user show --query id -o tsv)"

echo "SQL admin group object id: $SQL_ADMIN_GROUP_ID"   # becomes a Bicep parameter
```

### 11.2 Entra ID app registrations for OAuth (v3)

v3 needs two more app registrations — one exposing the API's scopes and app roles, one for the
client. Both are created with `az ad app create` in the same way as §8.1. They will be documented in
`docs/adr/` when we get there.

### 11.3 API Management SKU choice (v3)

Read [§12](#12-cost-expectations-and-hygiene) **before** creating APIM. It is by far the easiest way
to accidentally spend real money in this lab.

---

## 12. Cost expectations and hygiene

Rough monthly figures for a lab that is idle most of the time. Treat as order-of-magnitude, not a quote.

| Resource | Recommended lab SKU | Approx. €/month | Notes |
|---|---|---|---|
| Log Analytics workspace | Pay-as-you-go | €0–3 | First 5 GB/month ingestion is free. Set a daily cap. |
| Application Insights | Workspace-based | included above | Billed through Log Analytics. |
| Azure SQL | **Serverless**, Gen5, 0.5–1 vCore, auto-pause 60 min | €2–15 | Auto-pause is what keeps this cheap — an idle DB bills only ~€0.10/GB storage. |
| App Service plan | **F1 Linux (free)** | €0 | F1 has no Always On and a 60 CPU-min/day cap. **Deployment slots require Standard (S1, ~€65/mo) — Basic B1 has none either.** Scale to S1 for an afternoon to practise swaps (~€0.10), then back. |
| Function App | **Flex Consumption** | €0–2 | Pay per execution. Keep always-ready instances at 0. Required for .NET 10. |
| Service Bus | **Basic** | <€1 | €0.05 per million operations. Basic is queues-only; upgrade to Standard (~€9) only if you need topics or sessions. |
| Storage account (Functions) | Standard LRS | <€1 | |
| Key Vault | Standard | <€1 | Billed per 10k operations. |
| **API Management** | **Consumption** | €0–2 | ⚠️ Includes 1M free calls/month. |
| ~~API Management~~ | ~~Developer~~ | ~~€45~~ | ⚠️ **Avoid.** Billed hourly whether used or not, cannot be stopped, and takes ~45 min to deploy or delete. |

**Total for the lab as designed: roughly €15–20/month**, and less if you follow the hygiene below.

### Hygiene rules

1. **Tear down between sessions.** Because everything is in Bicep, deleting is safe and re-creating
   takes one pipeline run:
   ```bash
   az group delete --name rg-devopslab-dev-neu --yes --no-wait
   ```
2. **Let SQL auto-pause.** Don't set a keep-alive ping. An idle serverless database costs almost nothing.
3. **Cap Log Analytics.** Set a daily ingestion cap (e.g. 1 GB/day) on the workspace — a chatty
   debug logger left on overnight is the classic surprise bill.
4. **Never leave APIM Developer tier running.** If you do try it, delete it the same day.
5. **Check `Cost analysis` weekly.** Group by resource; anything unexpected gets deleted.
6. **Add `az group list -o table` to your routine** before you close the laptop.

---

## 13. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `AADSTS700213: No matching federated identity record found for presented assertion subject` | The `subject` claim doesn't match any federated credential — **usually because GitHub minted an immutable subject** (`owner@ownerId/repo@repoId`) and you registered the plain slug | Read the presented subject straight out of the failed run's `azure/login` log ("Federated token details → subject claim") and register a credential with exactly that string. See §8.2. |
| `AADSTS70021: No matching federated identity record found` | Same cause, older error code | As above. Also check case — repo owner/name is case-sensitive — and that a branch push uses `ref:refs/heads/main` while a PR uses `pull_request`. |
| `AADSTS700016: Application not found in the directory` | Wrong `client-id`, wrong `tenant-id`, or `permissions: id-token: write` missing from the workflow | Add the permission block; re-check the variables. |
| `Unable to get ACTIONS_ID_TOKEN_REQUEST_URL` | `id-token: write` permission missing | Add it at the workflow or job level. |
| `AuthorizationFailed` when Bicep creates a role assignment | Deployment identity lacks RBAC-writing rights | Re-run §8.3's second `az role assignment create`. |
| `MissingSubscriptionRegistration` | Resource provider not registered | Re-run §6.4 and wait for `Registered`. |
| `SubscriptionNotFound` / resources unreachable | Free credit exhausted, subscription disabled by spending limit | Portal → Subscriptions → your subscription → **Remove spending limit** / upgrade to pay-as-you-go. |
| `LocationNotAvailableForResourceType` or capacity errors | Region out of capacity for that SKU | Try `northeurope` / `eastus`, or a different SKU. |
| Card declined at signup | Prepaid or virtual card | Use a standard credit/debit card. |
| `az bicep` command not found | Bicep not installed into the CLI | `az bicep install` (it is not a separate brew formula). |
| `brew install azure-functions-core-tools@4` fails: *"Your Command Line Tools are too outdated"* | The formula builds from source and needs current Xcode CLT | `sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install`, then retry the brew install. Only needed for local Functions development (v2). |
| Functions host hangs or times out locally | Only .NET 10 installed; Core Tools needs an older runtime present | Keep the .NET 8 SDK/runtime installed alongside .NET 10. |
| `dotnet build` fails: "SDK not found" | `global.json` pins .NET 10, which isn't installed | Complete §5.1. |

---

## Reference links

- [Azure free account](https://azure.microsoft.com/free) · [FAQ](https://azure.microsoft.com/free/free-account-faq/)
- [Avoid charges with your Azure free account](https://learn.microsoft.com/azure/cost-management-billing/manage/avoid-charges-free-account)
- [Configure GitHub Actions OIDC with Azure](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect)
- [Azure built-in roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles)
- [Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure Functions C# isolated worker guide](https://learn.microsoft.com/azure/azure-functions/dotnet-isolated-process-guide)
- [Azure Functions Flex Consumption plan](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)

---

**Next step:** [`docs/conventions.md`](conventions.md), then start on v0 — the Bicep foundation in
[`iac/`](../iac/).
