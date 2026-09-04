#!/usr/bin/env sh
# Bundles each direct-connector function into ONE file (bundle/<name>.ts) so the Supabase MCP deploy
# needs no relative imports. Deno's npm:/jsr: specifiers stay external. Re-run after any change to
# _shared/wearables/* or a function's index.ts, then deploy bundle/<name>.ts with `deploy_edge_function`
# (verify_jwt: start/disconnect = true; callback/webhook/sync = false — the vendor and pg_cron call them).
set -e
cd "$(dirname "$0")"
mkdir -p bundle
for fn in wearable-oauth-start wearable-oauth-callback wearable-vendor-webhook wearable-vendor-sync wearable-vendor-disconnect; do
  npx -y esbuild "$fn/index.ts" --bundle --format=esm --platform=neutral --target=esnext \
    '--external:npm:*' '--external:jsr:*' --outfile="bundle/$fn.ts" --log-level=warning
  node --check "bundle/$fn.ts"
  printf '%s: %s bytes\n' "$fn" "$(wc -c < "bundle/$fn.ts")"
done
