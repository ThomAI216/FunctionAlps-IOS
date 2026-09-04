// push-send — delivers ONE `patient_notifications` row to the member's iPhone through APNs.
// Caller: `notify_member_push()` (DB trigger → pg_net) with the shared x-report-secret; also the
// 15-minute sweep (`{ sweep: true }`) for rows never delivered. verify_jwt = false (pg_net sends no JWT),
// FAIL-CLOSED on the secret.
//
// APNs: HTTP/2 to api.push.apple.com (or the sandbox host per the stored `apns_environment`), provider
// token auth (ES256 JWT from the .p8, cached 50 min). Secrets: APNS_TEAM_ID, APNS_KEY_ID, APNS_KEY_P8
// (the .p8 file content, base64), APNS_TOPIC (the bundle id, default com.functionalps.patient).
// Content-free by rule: title/body carry no health data — the route is the payload.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

const REPORT_SECRET = Deno.env.get("REPORT_SECRET")
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } })

const admin = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } })

// MARK: APNs provider token (ES256)

let cachedJwt: { token: string; issuedAt: number } | null = null

function b64url(bytes: Uint8Array | string): string {
  const s = typeof bytes === "string" ? bytes : String.fromCharCode(...bytes)
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJwt && now - cachedJwt.issuedAt < 50 * 60) return cachedJwt.token
  const teamId = Deno.env.get("APNS_TEAM_ID"), keyId = Deno.env.get("APNS_KEY_ID"), p8b64 = Deno.env.get("APNS_KEY_P8")
  if (!teamId || !keyId || !p8b64) throw new Error("APNS_TEAM_ID / APNS_KEY_ID / APNS_KEY_P8 missing")
  const pem = atob(p8b64)
  const der = Uint8Array.from(atob(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"])
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId }))
  const claims = b64url(JSON.stringify({ iss: teamId, iat: now }))
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`)))
  const token = `${header}.${claims}.${b64url(sig)}`
  cachedJwt = { token, issuedAt: now }
  return token
}

// MARK: Quiet hours (the member's local time)

function localHM(tz: string, d = new Date()): number {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(d).map((x) => [x.type, x.value]))
  return Number(p.hour) * 60 + Number(p.minute)
}
function inQuietHours(prefs: Record<string, unknown>): boolean {
  if (!prefs.quiet_hours_enabled) return false
  const toMin = (t: unknown) => { const m = String(t ?? "").match(/^(\d{2}):(\d{2})/); return m ? Number(m[1]) * 60 + Number(m[2]) : null }
  const start = toMin(prefs.quiet_hours_start), end = toMin(prefs.quiet_hours_end)
  if (start == null || end == null) return false
  const now = localHM(String(prefs.timezone ?? "Europe/Zurich"))
  return start <= end ? (now >= start && now < end) : (now >= start || now < end)
}

function categoryEnabled(prefs: Record<string, unknown>, type: string): boolean {
  switch (type) {
    case "practitioner_message": return prefs.messages_enabled !== false
    case "report_ready": return prefs.reports_enabled !== false
    case "care_plan_update": return prefs.care_plan_enabled !== false
    default: return true
  }
}

// MARK: Deliver one row

async function deliver(db: ReturnType<typeof admin>, id: string): Promise<Record<string, unknown>> {
  const { data: n } = await db.from("patient_notifications").select("id,patient_id,type,title,body,data_json,delivered_at").eq("id", id).maybeSingle()
  if (!n) return { id, skipped: "not_found" }
  if (n.delivered_at) return { id, skipped: "already_delivered" }
  const { data: prefs } = await db.from("patient_notification_preferences").select("*").eq("patient_id", n.patient_id).maybeSingle()
  const token = prefs?.apns_token as string | undefined
  if (!prefs || !token || prefs.push_enabled === false) return { id, skipped: "no_token" }
  if (!categoryEnabled(prefs, n.type)) { await db.from("patient_notifications").update({ dismissed_at: new Date().toISOString() }).eq("id", id); return { id, skipped: "category_off" } }
  if (inQuietHours(prefs)) return { id, deferred: "quiet_hours" }  // the sweep retries after the window

  const host = prefs.apns_environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com"
  const topic = Deno.env.get("APNS_TOPIC") ?? "com.functionalps.patient"
  const data = (n.data_json ?? {}) as Record<string, unknown>
  const payload = {
    aps: { alert: { title: n.title, body: n.body }, sound: "default", "thread-id": String(data.collapse ?? n.type), category: n.type, "mutable-content": 0 },
    route: data.route ?? null, notification_id: n.id, type: n.type,
  }
  const headers: Record<string, string> = {
    authorization: `bearer ${await apnsJwt()}`, "apns-topic": topic, "apns-push-type": "alert", "apns-priority": "10",
    "apns-expiration": String(Math.floor(Date.now() / 1000) + 24 * 3600),
  }
  if (data.collapse) headers["apns-collapse-id"] = String(data.collapse).slice(0, 64)
  const resp = await fetch(`${host}/3/device/${token}`, { method: "POST", headers, body: JSON.stringify(payload) })
  if (resp.ok) {
    await db.from("patient_notifications").update({ delivered_at: new Date().toISOString() }).eq("id", id)
    return { id, delivered: true }
  }
  const text = await resp.text()
  let reason = ""
  try { reason = JSON.parse(text).reason ?? "" } catch { /* keep empty */ }
  if (resp.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic") {
    await db.from("patient_notification_preferences").update({ apns_token: null, apns_token_updated_at: new Date().toISOString() }).eq("patient_id", n.patient_id)
  }
  console.error("[push-send]", id, resp.status, reason || text.slice(0, 200))
  return { id, failed: resp.status, reason }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405)
  if (!REPORT_SECRET || req.headers.get("x-report-secret") !== REPORT_SECRET) return json({ error: "forbidden" }, 403)
  let body: { notification_id?: string; sweep?: boolean } = {}
  try { body = await req.json() } catch { /* empty */ }
  const db = admin()
  try {
    if (body.notification_id) return json(await deliver(db, body.notification_id))
    if (body.sweep) {
      const since = new Date(Date.now() - 24 * 3600_000).toISOString()
      const { data: rows } = await db.from("patient_notifications").select("id").is("delivered_at", null).is("dismissed_at", null).eq("trigger_type", "event_driven").gte("created_at", since).order("created_at").limit(50)
      const out = []
      for (const r of rows ?? []) out.push(await deliver(db, r.id))
      return json({ swept: out.length, results: out })
    }
    return json({ error: "notification_id or sweep required" }, 400)
  } catch (e) {
    console.error("[push-send]", String(e))
    return json({ error: String(e).slice(0, 200) }, 500)
  }
})
