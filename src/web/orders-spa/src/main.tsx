import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { PublicClientApplication } from '@azure/msal-browser'
import { MsalProvider } from '@azure/msal-react'
import { msalConfig } from './authConfig'
import App from './App'

// Created once, outside the component tree: a new instance per render would throw away the token
// cache and the in-flight interaction state on every re-render.
const msalInstance = new PublicClientApplication(msalConfig)

// MsalProvider calls instance.initialize() and handleRedirectPromise() itself, so there is nothing
// to await here — until it resolves it reports InteractionStatus.Startup, which SignInBar honours.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <MsalProvider instance={msalInstance}>
      <App />
    </MsalProvider>
  </StrictMode>,
)
