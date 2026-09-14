// wearable-reconcile — SCHEDULED (verify_jwt off; pg_cron nightly 03:25 UTC with `x-report-secret`).
// Webhooks miss, vendors correct data after the fact, and a phone can be offline for days: every live
// account gets a re-pull window queued with a dedupe key — nightly the adapter's short window (default
// 3 days), on Sundays the longer one (default 14 days) — then the queue is drained right away. Also
// re-encrypts tokens still under an old key version (rotation path) and releases stale leases.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { type AccountRow, LIVE_STATUSES, currentKeyVersion, json, rotateAccountTokens, serviceClient, vendorClient, vendorStatus } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"
import { drainQueue, enqueueAccountWindow } from "../_shared/wearables/worker.ts"
import { polarRegisterWebhook } from "../_shared/wearables/polar.ts"
import { errorSummary, log } from "../_shared/wearables/log.ts"

const FN = "wearable-reconcile"
const REPORT_SECRET = Deno.env.get("REPORT_SECRET")

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405)
  if (!REPORT_SECRET || req.headers.get("x-report-secret") !== REPORT_SECRET) return json({ error: "Unauthorized" }, 401)
  // Ops probe (`{"probe":"polar-credentials"}`): does Polar accept the client credentials held in the function
  // secrets? Answers the HTTP status of the app-level webhook list plus the registered webhooks' id/events/url —
  // never a secret, never a body. Lets the owner tell "wrong values in Supabase" from "wrong values typed locally".
  let probe: string | null = null
  try { probe = ((await req.clone().json()) as { probe?: string }).probe ?? null } catch { /* no body */ }
  if (probe === "polar-credentials") {
    const { clientId, clientSecret } = vendorClient("polar")
    const r = await fetch("https://www.polaraccesslink.com/v3/webhooks", { headers: { Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`, Accept: "application/json" } })
    let webhooks: unknown = null
    if (r.ok) {
      const j = (await r.json()) as { data?: { id?: string; events?: string[]; url?: string }[] }
      webhooks = (j.data ?? []).map((w) => ({ id: w.id, events: w.events, url: w.url }))
    }
    log("info", "probe.polar_credentials", { fn: FN, vendor: "polar", status: r.status, clientIdLength: clientId.length, secretLength: clientSecret.length })
    return json({ probe, status: r.status, clientIdLength: clientId.length, secretLength: clientSecret.length, webhooks })
  }
  const db = serviceClient()
  // Ops action (`{"probe":"polar-register-webhook"}`, optional `"force":true`): the backend registers Polar's
  // application webhook and keeps the once-shown signing key encrypted in the app-level subscription row.
  if (probe === "polar-register-webhook") {
    let force = false
    try { force = ((await req.clone().json()) as { force?: boolean }).force === true } catch { /* no body */ }
    try { return json({ probe, ...(await polarRegisterWebhook(db, { force })) }) }
    catch (e) { log("warn", "probe.polar_register_failed", { fn: FN, vendor: "polar", ...errorSummary(e) }); return json({ probe, error: errorSummary(e).message }, 502) }
  }
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
