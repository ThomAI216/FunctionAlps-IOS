// Thryve is retired (owner decision 2026-09-04; legal finding APP-03). The three functions
// thryve-connect / thryve-webhook / thryve-sync are redeployed with THIS body (verify_jwt on) so the
// URLs answer 410 Gone until the owner deletes them in the Supabase dashboard. The direct connectors
// live in wearable-oauth-* / wearable-vendor-*.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
Deno.serve(() => new Response(JSON.stringify({ error: "Thryve integration retired (2026-09-04)" }), { status: 410, headers: { "Content-Type": "application/json" } }))
