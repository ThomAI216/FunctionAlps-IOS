// wearable-oauth-start — MEMBER function (verify_jwt): POST { vendor, target? } → { url, vendor }.
// Creates a single-use OAuth state (10 min, bound to the member): only the SHA-256 of the state is stored,
// the PKCE verifier (when the vendor documents PKCE) is encrypted, the redirect URI is pinned to the row.
// Returns the vendor's authorisation URL for ASWebAuthenticationSession. Refuses vendors that are not
// `available` (kill switch / not yet opened) with 409 vendor_unavailable.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { CORS, encrypt, json, oauthRedirectUri, pkceChallenge, randomToken, resolvePatientId, sendsPKCE, serviceClient, sha256Hex, vendorClient, vendorStatus } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"
import { errorSummary, hashId, log } from "../_shared/wearables/log.ts"

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)
  const db = serviceClient()
  const patientId = await resolvePatientId(req, db)
  if (!patientId) return json({ error: "Unauthorized" }, 401)

  let body: { vendor?: string; target?: string }
  try { body = await req.json() } catch { return json({ error: "Invalid JSON" }, 400) }
  const a = adapter(body.vendor)
  if (!a) return json({ error: "Unknown vendor" }, 400)

  const status = await vendorStatus(db, a.key)
  if (status !== "available") return json({ error: "Vendor not available yet", code: status === "paused" ? "vendor_paused" : "vendor_unavailable" }, 409)

  try {
    const { clientId } = vendorClient(a.key)
    const state = randomToken(32)
    const stateHex = await sha256Hex(state)
    const verifier = sendsPKCE(a.pkce) ? randomToken(48) : null
    const redirectUri = oauthRedirectUri()
    const { error } = await db.from("wearable_oauth_states").insert({
      state: stateHex, state_hash: `\\x${stateHex}`, patient_id: patientId, vendor: a.key,
      code_verifier: null,
      code_verifier_enc: verifier ? await encrypt(verifier, { accountId: stateHex, vendor: a.key, tokenType: "verifier" }) : null,
      redirect_uri: redirectUri, pkce_mode: a.pkce,
      post_auth_target: typeof body.target === "string" ? body.target.slice(0, 120) : null,
      expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
    })
    if (error) throw new Error(`state insert: ${error.message}`)
    const url = a.authorizeURL({ clientId, redirectUri, state, codeChallenge: verifier ? await pkceChallenge(verifier) : undefined })
    log("info", "oauth.start", { fn: "wearable-oauth-start", vendor: a.key, patientHash: await hashId(patientId), pkce: a.pkce })
    return json({ url, vendor: a.key })
  } catch (e) {
    log("error", "oauth.start_failed", { fn: "wearable-oauth-start", vendor: a.key, ...errorSummary(e) })
    return json({ error: "Could not start the connection" }, 500)
  }
})
