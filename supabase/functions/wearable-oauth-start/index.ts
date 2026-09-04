// wearable-oauth-start — MEMBER function (verify_jwt): POST { vendor } → { url }.
// Creates a single-use OAuth state (10 min, bound to the member, with a PKCE verifier when the
// vendor supports it) and returns the vendor's authorisation URL for ASWebAuthenticationSession.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { CORS, json, oauthRedirectUri, pkceChallenge, randomToken, resolvePatientId, serviceClient, vendorClient } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)
  const db = serviceClient()
  const patientId = await resolvePatientId(req, db)
  if (!patientId) return json({ error: "Unauthorized" }, 401)

  let body: { vendor?: string }
  try { body = await req.json() } catch { return json({ error: "Invalid JSON" }, 400) }
  const a = adapter(body.vendor)
  if (!a) return json({ error: "Unknown vendor" }, 400)

  const { data: v } = await db.from("wearable_vendors").select("status").eq("key", a.key).maybeSingle()
  if (v?.status !== "available") return json({ error: "Vendor not available yet", code: "vendor_unavailable" }, 409)

  try {
    const { clientId } = vendorClient(a.key)
    const state = randomToken(32)
    const verifier = a.usesPKCE ? randomToken(48) : null
    const { error } = await db.from("wearable_oauth_states").insert({
      state, patient_id: patientId, vendor: a.key, code_verifier: verifier,
      expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
    })
    if (error) throw new Error(`state insert: ${error.message}`)
    const url = a.authorizeURL({ clientId, redirectUri: oauthRedirectUri(), state, codeChallenge: verifier ? await pkceChallenge(verifier) : undefined })
    return json({ url, vendor: a.key })
  } catch (e) {
    console.error("[wearable-oauth-start]", String(e))
    return json({ error: "Could not start the connection" }, 500)
  }
})
