// wearable-vendor-sync — two callers:
//   • pg_cron (every 10 min while the queue has pending vendor rows), authenticated by the shared
//     `x-report-secret` header (Vault `report_secret` → REPORT_SECRET), drains `wearable_sync_queue`;
//   • the member (bearer JWT) — "Sync now": pulls the last 3 days of their own connected vendors.
// A pull = adapter.fetchRange(tokens, start, end) → wearable_raw_events (vendor_api) → upserts.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { CORS, RateLimitedError, UnauthorizedError, addDays, json, liveTokens, localDay, markAccount, persistRows, resolvePatientId, serviceClient, storeRaw, type AccountRow } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"
import { ouraMaintain } from "../_shared/wearables/oura.ts"
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"

const REPORT_SECRET = Deno.env.get("REPORT_SECRET")

async function pull(db: SupabaseClient, account: AccountRow, start: string, end: string): Promise<{ daily: number; epoch: number }> {
  const a = adapter(account.vendor)
  if (!a) throw new Error("unknown vendor")
  const tokens = await liveTokens(db, account, a)
  const rows = await a.fetchRange(tokens, start, end, { patientId: account.patient_id, vendorUserId: account.vendor_user_id, meta: account.meta ?? {} })
  const rawId = await storeRaw(db, account.patient_id, account.vendor, "vendor_api", { start, end, daily: rows.daily.length, epoch: rows.epoch.length, sample: rows.daily.slice(0, 20) }, account.vendor_user_id)
  const counts = await persistRows(db, account.patient_id, account.vendor, rows, rawId)
  await markAccount(db, account.id, { last_sync_at: new Date().toISOString(), last_error: null, status: "connected" })
  return counts
}

async function drainQueue(db: SupabaseClient, limit = 25) {
  const { data: jobs } = await db.from("wearable_sync_queue").select("id,patient_id,vendor,window_start,window_end,attempts").eq("status", "pending").not("vendor", "is", null).order("created_at").limit(limit)
  let done = 0, failed = 0
  for (const job of jobs ?? []) {
    await db.from("wearable_sync_queue").update({ status: "processing", attempts: (job.attempts ?? 0) + 1 }).eq("id", job.id)
    try {
      const { data: account } = await db.from("wearable_vendor_accounts").select("*").eq("patient_id", job.patient_id).eq("vendor", job.vendor).maybeSingle()
      if (!account || account.status === "revoked") throw new Error("no connected account")
      const today = localDay(new Date())
      const start = job.window_start ? String(job.window_start).slice(0, 10) : addDays(today, -3)
      const end = job.window_end ? String(job.window_end).slice(0, 10) : today
      await pull(db, account as AccountRow, start, end)
      await db.from("wearable_sync_queue").update({ status: "done", processed_at: new Date().toISOString(), last_error: null }).eq("id", job.id)
      done++
    } catch (e) {
      const msg = String(e).slice(0, 300)
      const attempts = (job.attempts ?? 0) + 1
      const giveUp = attempts >= 3 || e instanceof UnauthorizedError
      await db.from("wearable_sync_queue").update({ status: giveUp ? "error" : "pending", last_error: msg, processed_at: giveUp ? new Date().toISOString() : null }).eq("id", job.id)
      if (e instanceof UnauthorizedError) {
        const { data: account } = await db.from("wearable_vendor_accounts").select("id").eq("patient_id", job.patient_id).eq("vendor", job.vendor).maybeSingle()
        if (account) await markAccount(db, account.id, { status: "error", last_error: msg })
      }
      if (e instanceof RateLimitedError) break
      failed++
    }
  }
  return { done, failed, seen: jobs?.length ?? 0 }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)
  const db = serviceClient()

  if (REPORT_SECRET && req.headers.get("x-report-secret") === REPORT_SECRET) {
    const drained = await drainQueue(db)
    // Oura's application-level webhook subscriptions expire: keep them alive once an hour (cheap: one list call).
    let oura: unknown = null
    if (new Date().getMinutes() < 10 && Deno.env.get("OURA_CLIENT_ID")) {
      try { oura = await ouraMaintain() } catch (e) { oura = { error: String(e).slice(0, 200) } }
    }
    return json({ ...drained, oura })
  }
  const patientId = await resolvePatientId(req, db)
  if (!patientId) return json({ error: "Unauthorized" }, 401)
  const { data: accounts } = await db.from("wearable_vendor_accounts").select("*").eq("patient_id", patientId).eq("status", "connected")
  const today = localDay(new Date())
  const results: Record<string, unknown> = {}
  for (const account of (accounts ?? []) as AccountRow[]) {
    try { results[account.vendor] = await pull(db, account, addDays(today, -3), today) }
    catch (e) { results[account.vendor] = { error: String(e).slice(0, 200) }; await markAccount(db, account.id, { last_error: String(e).slice(0, 300) }) }
  }
  return json({ ok: true, results })
})
