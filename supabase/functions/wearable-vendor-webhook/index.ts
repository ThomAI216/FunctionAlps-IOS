// wearable-vendor-webhook — PUBLIC (verify_jwt off; the vendor authenticates by signature / token in the
// adapter). Path: /wearable-vendor-webhook/<vendor>. GET = verification handshake where a vendor uses one;
// POST = events. The body is read ONCE as bytes; every accepted body is stored verbatim once; each event
// gets a receipt (vendor event id, else body hash) so a redelivery is ACKed and skipped; rows a vendor
// pushes are persisted, everything else becomes a queued pull. Answers fast, never calls the vendor here.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { type AccountRow, addDays, audit, cancelJobs, enqueue, localDay, markAccount, persistRows, receiptKey, recordReceipt, serviceClient, sha256Hex, storeRaw, upsertConnection } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"
import { errorSummary, log, timer } from "../_shared/wearables/log.ts"

const FN = "wearable-vendor-webhook"

Deno.serve(async (req) => {
  const t = timer()
  const url = new URL(req.url)
  const vendorKey = url.pathname.split("/").filter(Boolean).pop()
  const a = adapter(vendorKey)
  if (!a) return new Response("unknown vendor", { status: 404 })
  const bytes = req.method === "POST" ? new Uint8Array(await req.arrayBuffer()) : new Uint8Array()
  const rawBody = bytes.length ? new TextDecoder().decode(bytes) : ""

  if (req.method === "GET" || req.method === "HEAD") {
    const r = a.challengeResponse?.(url, rawBody)
    return r ?? new Response("ok", { status: 200 })
  }
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 })

  let events
  try {
    events = await a.parseWebhook(req, rawBody, url)
  } catch (e) {
    log("warn", "webhook.rejected", { fn: FN, vendor: a.key, ...errorSummary(e) })
    return new Response("invalid signature", { status: 401 })
  }
  if (events === "challenge") return a.challengeResponse?.(url, rawBody) ?? new Response("ok")

  const db = serviceClient()
  let parsed: unknown = rawBody
  try { parsed = JSON.parse(rawBody) } catch { /* keep text */ }
  const bodyHash = await sha256Hex(bytes)
  let rawId: string | null = null
  let accepted = 0, duplicates = 0, unknown = 0

  for (const [i, ev] of events.entries()) {
    const key = receiptKey(ev, bodyHash, i)
    const { data: account } = await db.from("wearable_vendor_accounts").select("*").eq("vendor", a.key).eq("vendor_user_id", ev.vendorUserId).maybeSingle()
    const acc = account as AccountRow | null
    if (rawId === null) rawId = await storeRaw(db, acc?.patient_id ?? null, a.key, "vendor_webhook", parsed, { vendorUserId: ev.vendorUserId, payloadHash: bodyHash, vendorEventId: ev.eventId ?? null })
    if (!(await recordReceipt(db, a.key, key, bodyHash, ev.eventId ?? null, rawId))) { duplicates++; continue }
    if (!acc) { unknown++; log("info", "webhook.no_account", { fn: FN, vendor: a.key, kind: ev.kind }); continue }
    accepted++
    await markAccount(db, acc.id, { last_webhook_at: new Date().toISOString() })
    if (ev.revoked) {
      await markAccount(db, acc.id, { status: "revoked", revoked_at: new Date().toISOString(), access_token_enc: null, refresh_token_enc: null, token_expires_at: null, reconnect_required: true, last_error_code: "revoked_by_vendor" })
      await upsertConnection(db, acc.patient_id, a.key, false)
      await cancelJobs(db, acc.patient_id, a.key, "revoked_by_vendor")
      await audit(db, { patientId: acc.patient_id, vendor: a.key, accountId: acc.id, action: "revoke_by_vendor", actor: "vendor" })
      continue
    }
    if (ev.rows) {
      try { await persistRows(db, acc.patient_id, a.key, ev.rows, rawId, acc.id) } catch (e) { log("error", "webhook.persist_failed", { fn: FN, vendor: a.key, account: acc.id, ...errorSummary(e) }) }
    }
    const today = localDay(new Date())
    const start = ev.windowStart ?? addDays(today, -3), end = ev.windowEnd ?? today
    await enqueue(db, { patientId: acc.patient_id, vendor: a.key, vendorUserId: ev.vendorUserId, kind: ev.kind, syncKind: ev.rows ? "push" : "notification", windowStart: start, windowEnd: end, rawEventId: rawId, priority: 3, accountId: acc.id, dedupeKey: `notification:${acc.id}:${start}:${end}` })
  }
  log("info", "webhook.ok", { fn: FN, vendor: a.key, events: events.length, accepted, duplicates, unknown, ms: t() })
  return new Response(JSON.stringify({ ok: true, events: events.length, accepted, duplicates }), { status: 200, headers: { "Content-Type": "application/json" } })
})
