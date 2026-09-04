// wearable-vendor-disconnect — MEMBER function (verify_jwt): POST { vendor }. Revokes at the vendor
// when it has an endpoint (best effort), wipes the tokens, marks the account revoked and the
// connection disconnected. Stored readings stay in the member's record (retention rules apply).
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { CORS, decrypt, json, markAccount, resolvePatientId, serviceClient, upsertConnection, type AccountRow } from "../_shared/wearables/core.ts"
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

  const { data } = await db.from("wearable_vendor_accounts").select("*").eq("patient_id", patientId).eq("vendor", a.key).maybeSingle()
  const account = data as AccountRow | null
  if (account?.access_token_enc && a.revoke) {
    try {
      await a.revoke({ accessToken: await decrypt(account.access_token_enc), refreshToken: account.refresh_token_enc ? await decrypt(account.refresh_token_enc) : undefined, vendorUserId: account.vendor_user_id ?? undefined })
    } catch (e) { console.warn("[wearable-vendor-disconnect] revoke", a.key, String(e).slice(0, 200)) }
  }
  if (account) await markAccount(db, account.id, { status: "revoked", revoked_at: new Date().toISOString(), access_token_enc: null, refresh_token_enc: null, token_expires_at: null })
  await upsertConnection(db, patientId, a.key, false)
  await db.from("wearable_sync_queue").update({ status: "error", last_error: "disconnected" }).eq("patient_id", patientId).eq("vendor", a.key).eq("status", "pending")
  return json({ ok: true, vendor: a.key })
})
