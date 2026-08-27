import type { Configuration, PopupRequest } from '@azure/msal-browser'

/**
 * Fails the app at load time when a build-time variable is missing, rather than letting the
 * `undefined` reach Entra as part of an authority URL — which surfaces as an opaque 400 on the
 * sign-in popup with nothing pointing back at the build.
 */
function requiredEnv(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`${name} is not set. See src/web/orders-spa/README.md.`)
  }

  return value
}

const tenantId = requiredEnv('VITE_ENTRA_TENANT_ID', import.meta.env.VITE_ENTRA_TENANT_ID)
const clientId = requiredEnv('VITE_SPA_CLIENT_ID', import.meta.env.VITE_SPA_CLIENT_ID)

export const bffScope = requiredEnv('VITE_BFF_SCOPE', import.meta.env.VITE_BFF_SCOPE)
export const bffBaseUrl = requiredEnv('VITE_BFF_BASE_URL', import.meta.env.VITE_BFF_BASE_URL)

export const msalConfig: Configuration = {
  auth: {
    clientId,

    // Tenant-specific, and deliberately not /common or /organizations. The primary user is a guest
    // in this tenant backed by a personal Microsoft account; /common lets Entra pick the home
    // realm, so it signs him in as the MSA and issues a token from the consumers tenant with no
    // `roles` claim at all. Every BFF call would then answer 403 and the cause would look like RBAC.
    authority: `https://login.microsoftonline.com/${tenantId}`,

    // The default is the full current URL, which would need every route registered as a reply URL
    // on the app registration. Pinning the origin keeps that list at one entry.
    redirectUri: window.location.origin,
  },
  cache: {
    // Per-tab, and discarded when the tab closes. This is msal-browser's current default; setting
    // it explicitly means a future change of that default cannot silently start persisting tokens
    // in localStorage, where they would outlive the browser session.
    cacheLocation: 'sessionStorage',
  },
}

export const loginRequest: PopupRequest = {
  scopes: [bffScope],
}
