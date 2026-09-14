// wearable-vendor-sync — two callers:
//   • pg_cron (every 10 min while the queue has claimable vendor rows), authenticated by the shared
//     `x-report-secret` header (Vault `report_secret` → REPORT_SECRET): drains `wearable_sync_queue`
//     through the leased claim (`wearable_queue_claim`);
//   • the member (bearer JWT) — "Sync now": enqueues a 3-day window per live account of their own
//     (priority 10, deduped) and drains THEIR jobs inline, so the single code path serves both.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { CORS, type AccountRow, LIVE_STATUSES, json, resolvePatientId, serviceClient } from "../_shared/wearables/core.ts"
import { drainQueue, enqueueAccountWindow } from "../_shared/wearables/worker.ts"
import { ouraMaintain } from "../_shared/wearables/oura.ts"
import { errorSummary, log } from "../_shared/wearables/log.ts"

const FN = "wearable-vendor-sync"
const REPORT_SECRET = Deno.env.get("REPORT_SECRET")

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)
  const db = serviceClient()

  if (REPORT_SECRET && req.headers.get("x-report-secret") === REPORT_SECRET) {
    const drained = await drainQueue(db, { limit: 25, fnName: FN })
    // Oura's application-level webhook subscriptions expire: keep them alive once an hour (Phase 2 flags this).
    let oura: unknown = null
    if (new Date().getMinutes() < 10 && Deno.env.get("OURA_CLIENT_ID") && Deno.env.get("OURA_MAINTAIN_SUBSCRIPTIONS") === "1") {
      try { oura = await ouraMaintain() } catch (e) { oura = { error: errorSummary(e).message } }
    }
    log("info", "cron.drained", { fn: FN, ...drained })
    return json({ ...drained, oura })
  }

  const patientId = await resolvePatientId(req, db)
  if (!patientId) return json({ error: "Unauthorized" }, 401)
  const { data: accounts } = await db.from("wearable_vendor_accounts").select("*").eq("patient_id", patientId).in("status", LIVE_STATUSES)
  const queued: Record<string, string | null> = {}
  for (const account of (accounts ?? []) as AccountRow[]) {
    queued[account.vendor] = await enqueueAccountWindow(db, account, 3, "manual", 10)
  }
  const drained = await drainQueue(db, { limit: 5, patientId, fnName: FN })
  return json({ ok: true, queued, ...drained })
})
