import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { MsalProvider } from '@azure/msal-react';
import { PublicClientApplication } from '@azure/msal-browser';
import './App.css';
import App from './App.jsx';

// Runtime config written by entrypoint.sh at container startup.
// Falls back to empty strings when absent (local vite dev server — auth is skipped).
const {
  AZURE_TENANT_ID:    tenantId    = '',
  AZURE_UI_CLIENT_ID: clientId    = '',
  AZURE_API_SCOPE:    apiScope    = '',
} = window.__ENV__ ?? {};

const authEnabled = Boolean(tenantId && clientId && apiScope);

// Always construct a PublicClientApplication so MsalProvider is never skipped.
// When auth is disabled (empty config), MSAL is present but never invoked.
const msalInstance = new PublicClientApplication({
  auth: {
    clientId:               clientId || 'placeholder-disabled',
    authority:              `https://login.microsoftonline.com/${tenantId || 'common'}`,
    redirectUri:            window.location.origin,
    postLogoutRedirectUri:  window.location.origin,
  },
  cache: {
    cacheLocation:       'sessionStorage',
    storeAuthStateInCookie: false,
  },
  system: {
    // Suppress MSAL console noise when auth is disabled
    loggerOptions: { loggerCallback: () => {} },
  },
});

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <MsalProvider instance={msalInstance}>
      <App apiScope={authEnabled ? apiScope : null} />
    </MsalProvider>
  </StrictMode>,
);
