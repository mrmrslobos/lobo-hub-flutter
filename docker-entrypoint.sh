#!/bin/sh
# Generate runtime env-config.js so the browser picks up env vars
# injected at container start — no image rebuild needed when creds change.
cat > /usr/share/nginx/html/env-config.js <<EOF
window.process = window.process || {};
window.process.env = Object.assign(window.process.env || {}, {
  "NODE_ENV": "production",
  "VITE_SUPABASE_URL": "${VITE_SUPABASE_URL:-}",
  "VITE_SUPABASE_ANON_KEY": "${VITE_SUPABASE_ANON_KEY:-}",
  "VITE_GEMINI_API_KEY": "${VITE_GEMINI_API_KEY:-}",
  "VITE_GEMINI_MODEL": "${VITE_GEMINI_MODEL:-gemini-2.0-flash}"
});
EOF

exec nginx -g "daemon off;"
