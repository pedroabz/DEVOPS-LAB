# Testing v2 — identity, BFF and the SPA

Everything is deployed. This is how to exercise it, and what each result proves.

**Short answer to "which account?"** — your own works for the happy path, but it proves nothing
about RBAC, because you hold `Orders.Admin`. To see the roles actually doing something you need
**`ana.reader`**, who can list orders and cannot create them.

---

## Where things are

| | |
|---|---|
| **SPA** | <https://zealous-plant-0a8f0e50f.7.azurestaticapps.net> |
| **BFF** | `https://app-bff-devopslab-dev-spc-pabz.azurewebsites.net` |
| **Orders API** | `https://app-devopslab-dev-spc-pabz.azurewebsites.net` |

## Accounts

| Account | BFF role | API role | Can list | Can create |
|---|---|---|---|---|
| **you** — `pedroo.bezerra@gmail.com` | `Orders.Admin` | `Orders.Admin.Direct` | ✅ | ✅ |
| **`ana.reader@pedroobezerragmail.onmicrosoft.com`** | `Orders.Reader` | none | ✅ | ❌ **403** |
| **`miguel.admin@pedroobezerragmail.onmicrosoft.com`** | `Orders.Admin` | none | ✅ | ✅ |

Passwords for the two test users are in `.env` (gitignored). You are the only account that can also
call the API **directly** — that is what `Orders.Admin.Direct` means, and neither test user has it.

---

## Step 1 — one manual thing first

The database was recreated, so the Orders API's managed identity has no database user and every
order request will fail with `Login failed for user '<token-identified principal>'`.

In VS Code:

1. **MS SQL: Connect** → server `sql-devopslab-dev-spc-pabz.database.windows.net`,
   database `sqldb-orders-dev`, auth **Microsoft Entra ID – MFA**, sign in as yourself
2. Run [`scripts/sql/grant-webapp-db-access.sql`](../scripts/sql/grant-webapp-db-access.sql)
3. The verification query at the bottom should return two rows, `EXTERNAL_USER` in `db_datareader`
   and `db_datawriter`

The first connection may take 30–60 seconds or time out — that is the serverless database resuming,
not a fault. Retry.

> This is the one step in v2 that isn't automated. Granting a managed identity access to a *database*
> is T-SQL, not an ARM role assignment, and Bicep cannot execute it.

## Step 2 — register MFA for the test users

**Do this before trying the demo, not during it.** Entra security defaults force MFA registration on
first interactive sign-in, and hitting that halfway through is confusing.

For each of `ana.reader@` and `miguel.admin@`:

1. Open a **private/incognito** window (so it doesn't collide with your own session)
2. Go to <https://login.microsoftonline.com>, sign in with the password from `.env`
3. Complete the authenticator prompt

## Step 3 — the actual test

Open the SPA in a **private window**, so you control which account signs in.

### As `ana.reader` — the interesting one

| Action | Expected | What it proves |
|---|---|---|
| Sign in | Succeeds, name appears | Entra issues her a token; she is a valid user |
| Order list loads | Shows orders (empty at first) | `Orders.Reader` satisfies the BFF's read policy |
| Submit the form | **403, visible on screen** | `Orders.Reader` fails the write policy. **The BFF never calls the API** — the request stops at authorisation |

That 403 is the whole point of the milestone. A Reader can read and cannot write, and the decision
is made in the BFF.

### As `miguel.admin` or yourself

Both list and create succeed. Create an order and it appears in the list.

---

## Step 4 — prove the tokens really are different

This is the central claim of the design, and it takes two minutes to verify.

1. Signed into the SPA, open devtools → **Network**
2. Find the `POST /api/orders` request to the BFF, copy the `Authorization` header value
3. Paste it at <https://jwt.ms>

Look at `aud`. It is **`162f5318-e292-4b7b-9f15-6f1e129ae0eb`** — the BFF's client ID. Not the API's.

Now prove the API rejects it:

```bash
curl -i -H "Authorization: Bearer <that token>" \
  https://app-devopslab-dev-spc-pabz.azurewebsites.net/orders
```

**401.** The user's token is for the BFF and the API will not accept it. Nothing is forwarded — when
the BFF calls the API it requests its *own* token, with `aud` = `c57bde74-3e9a-4dfa-986f-564e6add32e0`.

### And your own direct access still works

```bash
TOKEN=$(./scripts/get-admin-token.sh)
curl -s -H "Authorization: Bearer $TOKEN" \
  https://app-devopslab-dev-spc-pabz.azurewebsites.net/orders | python3 -m json.tool
```

**200.** That works only because of an explicit `Orders.Admin.Direct` assignment to your account.
Try the same as `ana.reader` and there is no way to get such a token at all.

---

## Step 5 — the distributed trace

Portal → `appi-devopslab-dev-spc` → **Transaction search**, pick a request.

One `operation_id` should span **BFF → API → SQL**, with `orders-bff` and `orders-api` as separate
nodes on the application map. Both services report to the same App Insights and are distinguished by
`cloud_role_name`, which is why the trace joins up rather than breaking at the hop.

---

## When it doesn't work

| Symptom | Cause | Fix |
|---|---|---|
| Everything 403s in the SPA, even listing | Signed in with the wrong account, or `/common` picked your personal Microsoft account | Private window; check the name shown after sign-in |
| `Login failed for user '<token-identified principal>'` | Step 1 not done, or done against the wrong database | Run the grant script against `sqldb-orders-dev`, not `master` |
| First request hangs ~60s then fails | Serverless database resuming | Retry. Not a fault |
| Sign-in redirect loop or `AADSTS50011` | SPA origin not in the app registration's redirect URIs | Should already include the SWA hostname and `localhost:5173` |
| CORS error in the browser console | BFF's allowed origin doesn't match | It is set from the SWA hostname by Bicep; check it matches the URL you are actually on |
| SPA loads but every call fails with 404 | Built against the wrong BFF URL | `spa-cd` bakes it in from Bicep outputs — re-run it |

---

## Cost while testing

The App Service plan (B1, ~€0.40/day) carries **both** the API and the BFF. SQL bills only while
awake and pauses after 60 minutes idle. Static Web Apps is free.

**The one thing to watch:** keeping the SPA open holds the database awake, and awake SQL is
~€0.23/hour. Close the tab when you're done, and check it paused:

```bash
az sql db show -g rg-devopslab-dev-spc -s sql-devopslab-dev-spc-pabz \
  -n sqldb-orders-dev --query status -o tsv
```
