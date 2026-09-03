#!/usr/bin/env sh
# Rebuilds bundle/index.ts — the single file uploaded through the Supabase MCP.
# 1. esbuild: one ESM file, Deno's npm:/jsr: specifiers left as-is, syntax minified
#    but line breaks kept so the file can be read in chunks.
# 2. strip-prose.mjs: drops the screen-only copy of the two data catalogs.
set -e
cd "$(dirname "$0")"
npx -y esbuild index.ts --bundle --format=esm --platform=neutral --target=esnext \
  '--external:npm:*' '--external:jsr:*' --minify-syntax --outfile=bundle/index.ts --log-level=warning
node strip-prose.mjs bundle/index.ts
node --check bundle/index.ts
wc -c bundle/index.ts
