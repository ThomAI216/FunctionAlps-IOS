// wearable-vendor-disconnect — MEMBER function (verify_jwt): POST { vendor, erase?: boolean }.
// Disconnect = revoke at the vendor (best effort) + drop notification subscriptions where the adapter has
// them + cancel queued jobs + erase the tokens + status `disconnected` + audit + retention (the vendor's
// raw events get a delete_after 30 days out). With `erase: true` (the separate delete-my-data flow) the
// stored readings of that vendor are deleted now (`wearable_erase_vendor_data`) and the raw events purged
// on the next nightly run. Nothing here touches another source's data.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { CORS, type AccountRow, audit, cancelJobs, decodeTokens, findAccount, json, markAccount, resolvePatientId, serviceClient, upsertConnection } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"
import { errorSummary, hashId, log } from "../_shared/wearables/log.ts"

const FN = "wearable-vendor-disconnect"
const DISCONNECT_RAW_RETENTION_DAYS = Number(Deno.env.get("WEARABLE_DISCONNECT_RAW_RETENTION_DAYS") ?? "30") || 30

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)
  const db = serviceClient()
  const patientId = await resolvePatientId(req, db)
  if (!patientId) return json({ error: "Unauthorized" }, 401)
  let body: { vendor?: string; erase?: boolean }
  try { body = await req.json() } catch { return json({ error: "Invalid JSON" }, 400) }
  const a = adapter(body.vendor)
  if (!a) return json({ error: "Unknown vendor" }, 400)
  const erase = body.erase === true

  const account: AccountRow | null = await findAccount(db, patientId, a.key)
  const ctx = account ? { patientId, vendorUserId: account.vendor_user_id, meta: account.meta ?? {}, accountId: account.id } : null
  const steps: Record<string, string> = {}
  if (account?.access_token_enc && ctx) {
    let tokens = null
    try { tokens = await decodeTokens(account) } catch (e) { steps.decode = errorSummary(e).errorClass }
    if (tokens) {
      if (a.unsubscribe) { try { await a.unsubscribe(tokens, ctx); steps.unsubscribe = "ok" } catch (e) { steps.unsubscribe = errorSummary(e).errorClass } }
      if (a.revoke) { try { await a.revoke(tokens, ctx); steps.revoke = "ok" } catch (e) { steps.revoke = errorSummary(e).errorClass } }
    }
  }
  await cancelJobs(db, patientId, a.key, "disconnected")
  if (account) {
    await markAccount(db, account.id, { status: "disconnected", disconnected_at: new Date().toISOString(), access_token_enc: null, refresh_token_enc: null, token_expires_at: null, reconnect_required: false, refresh_lock_owner: null, refresh_lock_until: null, last_error_code: null })
    await db.from("wearable_webhook_subscriptions").update({ status: "revoked", updated_at: new Date().toISOString() }).eq("account_id", account.id).eq("status", "active")
    await db.from("wearable_sync_state").delete().eq("account_id", account.id)
  }
  await upsertConnection(db, patientId, a.key, false)
  // Retention: the vendor's raw events leave after the disconnect window (erase = now, below).
  await db.from("wearable_raw_events").update({ retention_class: "disconnected", delete_after: new Date(Date.now() + DISCONNECT_RAW_RETENTION_DAYS * 86_400_000).toISOString() })
    .eq("patient_id", patientId).eq("provider", a.key).is("delete_after", null)
  let erased: unknown = null
  if (erase) {
    const { data, error } = await db.rpc("wearable_erase_vendor_data", { p_patient: patientId, p_vendor: a.key })
    erased = error ? { error: error.message } : data
  }
  await audit(db, { patientId, vendor: a.key, accountId: account?.id ?? null, action: erase ? "erase" : "disconnect", actor: "member", details: { steps, erased } })
  log("info", erase ? "account.erased" : "account.disconnected", { fn: FN, vendor: a.key, account: account?.id ?? null, patientHash: await hashId(patientId), steps })
  return json({ ok: true, vendor: a.key, erased })
})
