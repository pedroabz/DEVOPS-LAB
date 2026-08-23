# The Web App's front door

Your Web App will get a public URL — `app-devopslab-dev-neu-pabz.azurewebsites.net` — the moment
it exists. Anyone on the internet can type that in. Three settings control *how* they're allowed
to reach it. Here's what each one actually does.

---

## 1. `httpsOnly` — "no plain HTTP"

**The background.** `http://` sends everything in readable text. Anyone between you and the server
— your ISP, the coffee shop wifi, a compromised router — can read it. `https://` wraps the same
traffic in encryption.

**The default.** A Web App answers on *both*. `http://yourapp...` and `https://yourapp...` both work.

**What the setting does.** `httpsOnly: true` makes the plain-HTTP version stop serving content.
Instead it sends back a redirect: *"go ask for the https version instead."* The browser follows it
automatically, so users see no difference.

**Does it matter for an empty app?** Not today — there's nothing to steal. It matters the moment v1
puts a real API behind it, and by then you won't remember to go back and set it. It costs nothing
and breaks nothing.

**One honest caveat:** a redirect means the first request *did* go out in the clear before being
bounced. Closing that gap needs a thing called HSTS, which is a browser-side promise to never try
HTTP again. Out of scope here, but that's why "httpsOnly" isn't quite the whole story.

---

## 2. `minTlsVersion` — "how old a handshake will you accept"

**The background.** TLS is the encryption *underneath* https. It has versions: 1.0 and 1.1 are old
and considered broken, 1.2 is today's baseline, 1.3 is newer and better. When a browser connects,
the two sides negotiate which version to use.

**What the setting does.** It sets a floor. `minTlsVersion: '1.2'` means "refuse anything older
than 1.2."

**Here's the catch.** I checked the Microsoft docs — Azure App Service **already defaults to 1.2**.
So writing that line changes precisely nothing.

**The argument for writing it anyway:** someone reading your Bicep can see the security posture
without going to look up Azure's defaults. It's documentation that lives next to the thing it
documents.

**The argument against** — and this is the one I find convincing:

> If Azure ever raises the default to 1.3, your explicit `'1.2'` doesn't document the default any
> more. It *overrides* it, and holds you at the weaker version. The line that was supposed to be a
> comment silently became a downgrade.

That's the real reason your repo has a "never set a property to its own default" rule. It isn't
tidiness. A redundant line isn't neutral — it's a line that can start meaning something later,
when nobody's looking.

---

## 3. `ftpsState` — "the other door"

**The surprise.** A Web App has a *second* way to get files into it: FTP. It's a leftover from when
you deployed websites by dragging files onto a server. It's still switched on.

**The three values:**

| Value | What it allows |
|---|---|
| `AllAllowed` | Plain FTP (unencrypted!) and FTPS |
| `FtpsOnly` | Encrypted FTPS only — **this is the default** |
| `Disabled` | No FTP door at all |

**Why turn it off.** You're going to deploy from GitHub Actions using the OIDC identity you already
set up. You will never once use FTP. But the door stays open, with its own set of credentials, that
you aren't monitoring and won't think about again. Closing a door you never use is free.

**The cost.** If you ever want to shove a file in by hand in a hurry, you can't until you flip it
back and redeploy.

---

## 4. IP restrictions — the one I'm *not* recommending

**What it is.** `ipSecurityRestrictions` is an allow-list of source IP addresses. Set it to your
home IP and the app becomes invisible to everyone else.

**Why it sounds appealing.** It mirrors what PRD row 10 wants to do for SQL — only your machine
gets in.

**Why not now:**

- **Your home IP changes.** Most ISPs rotate it when the router reconnects. One day your own app
  returns 403 and you spend the evening convinced your Bicep is broken.
- **GitHub Actions runners have unpredictable IPs.** Anything in the pipeline that pokes the app —
  a smoke test, a health check — would need the whole GitHub IP range allow-listed, which is a
  large and *changing* list.
- **It's not the grown-up answer anyway.** The real version of "only my network can reach this" is
  a private endpoint, which your PRD already parks in v4.

---

## So, the actual choice

| Option | `httpsOnly` | `minTlsVersion` | `ftpsState` | Result |
|---|---|---|---|---|
| **A** | `true` | *(omitted)* | `Disabled` | Secure, and no dead lines. Needs PRD task 5.4 reworded. |
| **B** | `true` | `'1.2'` | `Disabled` | Follows the PRD literally. Carries one line that does nothing — and could bite later. |
| **C** | `true` | *(omitted)* | `Disabled` + IP allow-list | Locks out the internet. Adds a parameter that goes stale and can break your own pipeline. |

**What I'd pick: A.** You get every actual security benefit. The only thing you give up is a line of
code that currently does nothing, and the only cost is editing one sentence in your PRD — which is
exactly what your rule 6 says to do when the code and the doc disagree.

**Pick B instead if** you'd rather your Bicep read as a complete statement of the security posture
and you're willing to revisit it if Azure's default moves.
