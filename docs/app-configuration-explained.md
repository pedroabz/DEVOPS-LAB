# Why does Bicep pass SQL and App Insights settings to the Web App?

Your question was: *isn't that the app's job to configure? Especially since I need it to work
locally too.*

Short answer: **the app decides what it needs. The environment decides what the value is.**

Let's go slowly.

---

## The problem

Your app needs to talk to a database. To do that it needs a connection string — an address,
basically. Something like:

```
Server=tcp:sql-devopslab-dev-neu-pabz.database.windows.net,1433;Database=sqldb-orders-dev;...
```

Now: where should that text live?

You have two obvious choices, and both are bad.

**Bad option 1: write it in the code.**

```csharp
var connection = "Server=tcp:sql-devopslab-dev-neu-pabz...";
```

Now your app only works against that one database. To run it on your laptop you'd have to edit
the code. To deploy to prod you'd edit it again. You'd be changing source code to move between
environments, and every change needs a rebuild.

**Bad option 2: put it in `appsettings.json` and commit it.**

Better, but the value still lives in your app's repo. And that server doesn't exist until Bicep
creates it. Every time you tear down and rebuild, you'd go edit the app repo by hand to match.
Two repos that must be kept in sync manually is a bug waiting to happen.

---

## What actually happens instead

Your code asks for a value **by name**. It never says where the value comes from.

```csharp
var connection = builder.Configuration.GetConnectionString("DefaultConnection");
```

Read that as: *"give me the thing called DefaultConnection."* That's it. The app has no idea
whether it's running on your laptop or in Azure.

Something else answers that question. And what answers it depends on where the app is running.

---

## The list of places to look

When your app starts, .NET builds a little lookup table. It fills it from several places, **in
order**. If two places have the same key, the later one wins.

The order is:

1. `appsettings.json`
2. `appsettings.Development.json`
3. user secrets (only when you're developing)
4. **environment variables**
5. command line arguments

That's the whole trick. Notice environment variables are near the bottom, so they beat the files.

---

## So what happens in each place

**On your laptop:**

You put your local database address in `appsettings.Development.json` (or in user secrets, which
is the same idea but the file lives outside your repo so you can't accidentally commit it).

Steps 1–3 fill in `DefaultConnection`. There are no environment variables set, so step 4 adds
nothing. Your local value survives. The app talks to your local database.

**In Azure:**

App Service takes the settings we're putting in the Bicep and hands them to your app as
environment variables. So step 4 fires and **overwrites** whatever came from the files.

The app talks to the real Azure database.

| | Laptop | Azure |
|---|---|---|
| Where the value comes from | `appsettings.Development.json` or user secrets | environment variables from App Service |
| Which database it hits | yours | `sqldb-orders-dev` |
| Code changes needed | none | none |
| Rebuild needed | none | none |

Same binary. Same code. Different answer to the same question.

---

## Why Bicep is the right place for the Azure value

Because Bicep is what **creates** the database. It's the only thing that knows the server's real
address the moment that address exists.

If Bicep passes the value straight to the Web App, the two can never disagree. Delete everything,
redeploy, and the new address flows through automatically. Nobody has to remember to update
anything.

That's the actual point of v0, and it's what your PRD means by "get the plumbing right against an
empty app."

---

## App Insights works the same way, but easier

The App Insights SDK looks for one specific environment variable on its own:
`APPLICATIONINSIGHTS_CONNECTION_STRING`.

You write one line in your app (`AddApplicationInsightsTelemetry()`), and the SDK goes hunting for
that variable. If it's there, telemetry flows. If it isn't, nothing happens and the app runs fine.

So on your laptop you just don't set it, and you get no telemetry — which is usually what you want
while developing.

---

## The genuinely nice bit: no passwords anywhere

Look at the connection string our Bicep produces. There is no username and no password in it:

```
Server=tcp:...;Database=...;Authentication=Active Directory Default;Encrypt=True;
```

`Active Directory Default` means: *"look around for whatever Azure identity is available here and
use that."*

- **In App Service**, the available identity is the Web App's managed identity.
- **On your laptop**, the available identity is whoever you are in `az login`.

Same string. Two different identities. No secret in either place.

This means you can literally copy that connection string into your local user secrets and it will
work — once task 6.5 has created a database user for you and one for the managed identity.

---

## One ugly detail, so it doesn't surprise you later

App Service has two boxes for this stuff: **app settings** and **connection strings**. They both
end up as environment variables, but connection strings get a prefix stuck on the front.

`DefaultConnection` becomes the environment variable `SQLAZURECONNSTR_DefaultConnection`.

.NET knows about that prefix and strips it back off, so `GetConnectionString("DefaultConnection")`
still finds it. But if you ever go poking at raw environment variables in the Azure portal and
wonder where that prefix came from — that's why.

---

## What this means for the Bicep we're about to write

Two settings go into the Web App:

| Setting | Where it comes from | What reads it |
|---|---|---|
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | the observability module's output | the App Insights SDK, automatically |
| `DefaultConnection` (type `SQLAzure`) | the sqlServer module's output | your code, via `GetConnectionString` |

Neither is a secret. Neither needs to exist in your app's repo. And neither stops the app running
on your laptop, because on your laptop nothing sets them and your local files win.
