// wearable-reconcile — SCHEDULED (verify_jwt off; pg_cron nightly 03:25 UTC with `x-report-secret`).
// Webhooks miss, vendors correct data after the fact, and a phone can be offline for days: every live
// account gets a re-pull window queued with a dedupe key — nightly the adapter's short window (default
// 3 days), on Sundays the longer one (default 14 days) — then the queue is drained right away. Also
// re-encrypts tokens still under an old key version (rotation path) and releases stale leases.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { type AccountRow, LIVE_STATUSES, currentKeyVersion, json, rotateAccountTokens, serviceClient, vendorStatus } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"
import { drainQueue, enqueueAccountWindow } from "../_shared/wearables/worker.ts"
import { errorSummary, log } from "../_shared/wearables/log.ts"

const FN = "wearable-reconcile"
const REPORT_SECRET = Deno.env.get("REPORT_SECRET")

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)
  if (!REPORT_SECRET || req.headers.get("x-report-secret") !== REPORT_SECRET) return json({ error: "Unauthorized" }, 401)
  const db = serviceClient()
  const weekly = new Date().getUTCDay() === 0
  const { data: accounts } = await db.from("wearable_vendor_accounts").select("*").in("status", LIVE_STATUSES)
  let queued = 0, skipped = 0, rotated = 0
  const paused = new Map<string, boolean>()
  for (const account of (accounts ?? []) as AccountRow[]) {
    const a = adapter(account.vendor)
    if (!a) { skipped++; continue }
    if (!paused.has(account.vendor)) paused.set(account.vendor, (await vendorStatus(db, account.vendor)) === "paused")
    if (paused.get(account.vendor)) { skipped++; continue }
    try { if (await rotateAccountTokens(db, account)) rotated++ } catch (e) { log("warn", "rotate.failed", { fn: FN, vendor: account.vendor, account: account.id, ...errorSummary(e) }) }
    const days = weekly ? (a.reconcile?.weeklyDays ?? 14) : (a.reconcile?.nightlyDays ?? 3)
    const id = await enqueueAccountWindow(db, account, days, "reconcile", 0)
    if (id) queued++
    await db.from("wearable_sync_state").upsert({ account_id: account.id, patient_id: account.patient_id, vendor: account.vendor, last_reconcile_at: new Date().toISOString(), updated_at: new Date().toISOString() }, { onConflict: "account_id" })
  }
  const drained = await drainQueue(db, { limit: 50, fnName: FN })
  log("info", "reconcile.done", { fn: FN, accounts: accounts?.length ?? 0, queued, skipped, rotated, keyVersion: currentKeyVersion(), weekly, ...drained })
  return json({ ok: true, accounts: accounts?.length ?? 0, queued, skipped, rotated, weekly, ...drained })
})
