# orders-spa

The v2 front end. Signs a user in with Entra ID and calls the BFF (`src/bff/DevOpsLab.Bff`), which
is the only thing it talks to — it never sees the Orders API and never holds a token for it.

Vite + React + TypeScript, `@azure/msal-browser` + `@azure/msal-react`. Deliberately plain: one
page, no styling framework, no router.

## Environment variables

All four are **required** and all are read at build time. Vite substitutes them into the bundle
during `vite build`, so changing one means rebuilding — there is no runtime configuration. Missing
any of them throws on load with the variable's name, rather than sending `undefined` to Entra.

| Variable | Value |
|---|---|
| `VITE_ENTRA_TENANT_ID` | Directory (tenant) ID |
| `VITE_SPA_CLIENT_ID` | Application (client) ID of `sp-devopslab-spa-dev` |
| `VITE_BFF_SCOPE` | `api://<tenantId>/orders-bff/access_as_user` |
| `VITE_BFF_BASE_URL` | Origin of the BFF, no trailing slash |

`.env.example` is the template. Copy it to `.env.local` — `.env` and `.env.*` are gitignored
repo-wide (`.env.example` excepted), which is also why the deployment workflow passes these as CLI
environment variables rather than committing a file.

## Running locally

```sh
npm install
npm run dev      # http://localhost:5173
npm run build    # tsc type-check, then a production bundle in dist/
npm run preview  # serve dist/ to check the built output
```

Two things must line up before sign-in works:

1. `http://localhost:5173` is registered as a **SPA** redirect URI on `sp-devopslab-spa-dev`. The
   app sends `redirectUri: window.location.origin`, so the origin alone is enough — no path.
2. The BFF's `Cors:AllowedOrigin` allows `http://localhost:5173`, or the browser blocks every call
   before the BFF ever sees it.

The BFF can be the deployed one or a local `dotnet run`; point `VITE_BFF_BASE_URL` at whichever.

## What to look for

A 403 from the BFF is rendered as visible text, not hidden. That is the point of the milestone:

- a user with **no app role** gets `Your account is not permitted to read orders.` on the list
- a user with **`Orders.Reader`** sees the list, but the form answers
  `Your account is not permitted to create orders.`
- a user with **`Orders.Admin`** can do both

## Notes on the auth setup

- **The authority is tenant-specific**, `https://login.microsoftonline.com/<tenantId>`, never
  `/common`. Pedro's account is a guest backed by a personal Microsoft account; `/common` would sign
  him in as that MSA and hand back a token with no `roles` claim, which looks exactly like an RBAC
  bug.
- **`cacheLocation: 'sessionStorage'`** — per-tab, cleared when the tab closes. It is msal-browser's
  current default; it is set explicitly so a future change of that default cannot start persisting
  tokens in `localStorage`.
- Tokens come from `acquireTokenSilent`, falling back to `acquireTokenRedirect` only on
  `InteractionRequiredAuthError`.
- **Sign-in is the redirect flow, not the popup flow.** With `redirectUri` set to the app's own
  origin, a popup lands on the application and boots a second copy of it — MSAL there refuses to
  process the response, because it belongs to the opener, so the popup renders a signed-out app
  with a Sign in button. Clicking that is a `loginPopup` from inside a popup, which MSAL rejects
  with `block_nested_popups`. The redirect flow has no second window to get this wrong.
