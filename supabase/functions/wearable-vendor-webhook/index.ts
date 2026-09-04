// wearable-vendor-webhook — PUBLIC (verify_jwt off; the vendor authenticates by signature / token in
// the adapter). Path: /wearable-vendor-webhook/<vendor>. GET = verification handshake where a vendor
// uses one; POST = events. Every accepted body is stored verbatim, then either the rows it carries are
// persisted or a pull is queued. Always answers fast; the pull happens in wearable-vendor-sync.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { addDays, enqueue, localDay, markAccount, persistRows, serviceClient, storeRaw, upsertConnection, type AccountRow } from "../_shared/wearables/core.ts"
import { adapter } from "../_shared/wearables/registry.ts"

Deno.serve(async (req) => {
  const url = new URL(req.url)
  const vendorKey = url.pathname.split("/").filter(Boolean).pop()
  const a = adapter(vendorKey)
  if (!a) return new Response("unknown vendor", { status: 404 })
  const rawBody = req.method === "POST" ? await req.text() : ""

  if (req.method === "GET" || req.method === "HEAD") {
    const r = a.challengeResponse?.(url, rawBody)
    return r ?? new Response("ok", { status: 200 })
  }
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 })

  let events
  try {
    events = await a.parseWebhook(req, rawBody, url)
  } catch (e) {
    console.warn("[wearable-vendor-webhook]", a.key, "rejected:", String(e).slice(0, 200))
    return new Response("invalid signature", { status: 401 })
  }
  if (events === "challenge") return a.challengeResponse?.(url, rawBody) ?? new Response("ok")

  const db = serviceClient()
  let parsed: unknown = rawBody
  try { parsed = JSON.parse(rawBody) } catch { /* keep text */ }

  for (const ev of events) {
    const { data: account } = await db.from("wearable_vendor_accounts").select("*").eq("vendor", a.key).eq("vendor_user_id", ev.vendorUserId).maybeSingle()
    const acc = account as AccountRow | null
    const rawId = await storeRaw(db, acc?.patient_id ?? null, a.key, "vendor_webhook", parsed, ev.vendorUserId)
    if (!acc) { console.warn("[wearable-vendor-webhook]", a.key, "no account for", ev.vendorUserId); continue }
    if (ev.revoked) {
      await markAccount(db, acc.id, { status: "revoked", revoked_at: new Date().toISOString(), access_token_enc: null, refresh_token_enc: null })
      await upsertConnection(db, acc.patient_id, a.key, false)
      continue
    }
    if (ev.rows) {
      try { await persistRows(db, acc.patient_id, a.key, ev.rows, rawId) } catch (e) { console.error("[wearable-vendor-webhook] persist", String(e)) }
    }
    const today = localDay(new Date())
    await enqueue(db, acc.patient_id, a.key, ev.vendorUserId, ev.kind, ev.windowStart ?? addDays(today, -3), ev.windowEnd ?? today, rawId)
  }
  return new Response(JSON.stringify({ ok: true, events: events.length }), { status: 200, headers: { "Content-Type": "application/json" } })
})
