// The queue worker shared by wearable-vendor-sync (every 10 min + "Sync now") and wearable-reconcile
// (nightly). One job = one adapter.fetchRange over a day window → wearable_raw_events (vendor_api) →
// upserts. Claiming goes through `wearable_queue_claim` (for update skip locked + lease); outcomes follow
// the retry taxonomy in core.ts (`classifyError`): Retry-After for 429, exponential backoff for 5xx and
// network, dead-letter after MAX_ATTEMPTS, `reconnect_required` on a terminal 401.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"
import {
  MAX_ATTEMPTS, NoAccountError, RateLimitedError, ReconnectRequiredError, VendorPausedError, type AccountRow, type VendorKey,
  addDays, audit, classifyError, enqueue, isLive, loadAccount, localDay, markAccount, persistRows, storeRaw, withVendorCall,
} from "./core.ts"
import { adapter } from "./registry.ts"
import { errorSummary, log, timer } from "./log.ts"

export interface QueueJob {
  id: string
  patient_id: string | null
  vendor: VendorKey
  account_id: string | null
  window_start: string | null
  window_end: string | null
  attempts: number
  sync_kind: string
  priority: number
}

/** One pull for one account over [start, end] (inclusive days). */
export async function pull(db: SupabaseClient, account: AccountRow, start: string, end: string, fnName = "worker"): Promise<{ daily: number; epoch: number }> {
  const a = adapter(account.vendor)
  if (!a) throw new Error("unknown vendor")
  const t = timer()
  await markAccount(db, account.id, { status: "syncing" })
  try {
    const rows = await withVendorCall(db, account, a, (tokens, acc) => a.fetchRange(tokens, start, end, { patientId: acc.patient_id, vendorUserId: acc.vendor_user_id, meta: acc.meta ?? {}, accountId: acc.id }))
    const rawId = await storeRaw(db, account.patient_id, account.vendor, "vendor_api", { start, end, daily: rows.daily.length, epoch: rows.epoch.length, sample: rows.daily.slice(0, 20) }, { vendorUserId: account.vendor_user_id })
    const counts = await persistRows(db, account.patient_id, account.vendor, rows, rawId, account.id)
    const now = new Date().toISOString()
    await markAccount(db, account.id, { status: "connected", reconnect_required: false, last_sync_at: now, last_successful_sync_at: now, last_error: null, last_error_code: null })
    log("info", "pull.ok", { fn: fnName, vendor: account.vendor, account: account.id, start, end, daily: counts.daily, epoch: counts.epoch, ms: t() })
    return counts
  } catch (e) {
    // The account status is settled by the caller (classifyError) — but never leave it stuck on `syncing`.
    if (!(e instanceof ReconnectRequiredError)) {
      const fresh = await loadAccount(db, account.id)
      if (fresh?.status === "syncing") await markAccount(db, account.id, { status: "connected" })
    }
    log("warn", "pull.failed", { fn: fnName, vendor: account.vendor, account: account.id, start, end, ms: t(), ...errorSummary(e) })
    throw e
  }
}

async function accountForJob(db: SupabaseClient, job: QueueJob): Promise<AccountRow> {
  let account: AccountRow | null = job.account_id ? await loadAccount(db, job.account_id) : null
  if (!account && job.patient_id) {
    const { data } = await db.from("wearable_vendor_accounts").select("*").eq("patient_id", job.patient_id).eq("vendor", job.vendor).maybeSingle()
    account = (data as AccountRow | null) ?? null
  }
  if (!account || !isLive(account)) throw new NoAccountError()
  return account
}

/** Claims up to `limit` jobs (optionally one member's) and runs them. Stops early on a rate limit. */
export async function drainQueue(db: SupabaseClient, opts: { limit?: number; patientId?: string | null; worker?: string; fnName?: string } = {}) {
  const worker = opts.worker ?? `edge:${crypto.randomUUID().slice(0, 8)}`
  const fnName = opts.fnName ?? "worker"
  const { data: jobs, error } = await db.rpc("wearable_queue_claim", { p_worker: worker, p_limit: opts.limit ?? 25, p_lease_seconds: 300, p_patient: opts.patientId ?? null })
  if (error) { log("error", "queue.claim_failed", { fn: fnName, message: error.message }); return { done: 0, failed: 0, seen: 0 } }
  let done = 0, failed = 0
  for (const job of (jobs ?? []) as QueueJob[]) {
    try {
      const account = await accountForJob(db, job)
      const today = localDay(new Date())
      const start = job.window_start ? String(job.window_start).slice(0, 10) : addDays(today, -3)
      const end = job.window_end ? String(job.window_end).slice(0, 10) : today
      await pull(db, account, start, end, fnName)
      await db.from("wearable_sync_queue").update({ status: "done", processed_at: new Date().toISOString(), last_error: null, last_error_code: null, locked_by: null, lock_expires_at: null }).eq("id", job.id)
      done++
    } catch (e) {
      const c = classifyError(e, job.attempts ?? 1)
      const exhausted = (job.attempts ?? 1) >= MAX_ATTEMPTS
      const status = c.retry && !exhausted ? "pending" : (c.retry ? "dead" : "error")
      await db.from("wearable_sync_queue").update({
        status, last_error: String((e as Error)?.message ?? e).slice(0, 300), last_error_code: c.code, locked_by: null, lock_expires_at: null,
        next_attempt_at: status === "pending" ? new Date(Date.now() + c.delaySeconds * 1000).toISOString() : null,
        processed_at: status === "pending" ? null : new Date().toISOString(),
      }).eq("id", job.id)
      if (c.accountStatus && job.account_id && !(e instanceof VendorPausedError) && !(e instanceof ReconnectRequiredError)) {
        await markAccount(db, job.account_id, { status: c.accountStatus, last_error_code: c.code, last_error: String((e as Error)?.message ?? e).slice(0, 300) })
      }
      log(status === "dead" ? "error" : "warn", "job.failed", { fn: fnName, vendor: job.vendor, job: job.id, account: job.account_id, attempt: job.attempts, code: c.code, next: status, delaySeconds: c.delaySeconds })
      if (status === "dead" && job.patient_id) await audit(db, { patientId: job.patient_id, vendor: job.vendor, accountId: job.account_id, action: "job_dead_lettered", details: { code: c.code, attempts: job.attempts } })
      failed++
      if (e instanceof RateLimitedError) break
    }
  }
  return { done, failed, seen: jobs?.length ?? 0 }
}

/** "Sync now" / reconcile helper: one job per live account over [today−days, today], deduped per account+window. */
export async function enqueueAccountWindow(db: SupabaseClient, account: AccountRow, days: number, syncKind: "manual" | "reconcile" | "backfill", priority: number, rawEventId: string | null = null): Promise<string | null> {
  const today = localDay(new Date())
  const start = addDays(today, -days)
  return await enqueue(db, {
    patientId: account.patient_id, vendor: account.vendor, vendorUserId: account.vendor_user_id ?? account.patient_id, kind: syncKind, syncKind,
    windowStart: start, windowEnd: today, rawEventId, priority, accountId: account.id, dedupeKey: `${syncKind}:${account.id}:${start}:${today}`,
  })
}
