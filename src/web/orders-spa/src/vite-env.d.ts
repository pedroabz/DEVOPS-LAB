/// <reference types="vite/client" />

// Declared as `string | undefined` rather than `string`, because Vite substitutes these at build
// time and simply leaves `undefined` where a variable was not set. Typing them as present would
// hide that from the compiler and push the failure into the browser.
interface ImportMetaEnv {
  readonly VITE_ENTRA_TENANT_ID: string | undefined
  readonly VITE_SPA_CLIENT_ID: string | undefined
  readonly VITE_BFF_SCOPE: string | undefined
  readonly VITE_BFF_BASE_URL: string | undefined
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
