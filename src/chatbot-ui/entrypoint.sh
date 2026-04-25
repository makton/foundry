#!/bin/sh
set -e

# Generate runtime auth config from environment variables injected by Container Apps.
# The SPA loads this file synchronously via <script src="/env-config.js"> before
# the main bundle, so window.__ENV__ is available at module evaluation time.
#
# Falls back to empty strings when variables are absent (local vite dev server
# uses its own proxy and doesn't need this file).
cat > /usr/share/nginx/html/env-config.js << EOF
window.__ENV__ = {
  AZURE_TENANT_ID:    "${AZURE_TENANT_ID:-}",
  AZURE_UI_CLIENT_ID: "${AZURE_UI_CLIENT_ID:-}",
  AZURE_API_SCOPE:    "${AZURE_API_SCOPE:-}"
};
EOF

exec nginx -g 'daemon off;'
