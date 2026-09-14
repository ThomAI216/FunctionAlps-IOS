// Oura API v2 — strategy 2026-09-14, Phase 2 (corpus: .context/research/2026-09-14_wearables-implementation/vendors/oura.md).
// Tokens: `expires_in`-derived expiry, refresh SINGLE-USE (§8) — the core serialises refresh under the DB lease.
// Webhooks are app-level subscriptions (one per data_type × event_type) that expire; `ouraMaintain()` creates/renews
// them ONLY when `OURA_MAINTAIN_SUBSCRIPTIONS=1` (the subscription contract is an open blocker, §10/§30).
//
// Decisions pinned here (each has a test in tests/oura_test.ts):
//   • D4 HRV gate: `average_hrv` is NOT written to 3100/3106/3107/3112/3113 (§18/§20, metrics/hrv-semantics.md
//     "Oura: UNVERIFIED, raw only"). It travels as `details.average_hrv_unverified` on the sleep-duration row.
//   • Nap vs main sleep: only `type === "long_sleep"` feeds the main-sleep ids (2300…2402); other sessions become
//     epoch rows with `details.type` (08_SLEEP.md "Nap + main sleep same day: only main sleep populates 2300").
//   • Verification token: ONLY `OURA_WEBHOOK_VERIFICATION_TOKEN` (§4/§26: a FunctionAlps secret separate from the
//     client secret). Unset → challenge refused + every POST rejected, with a logged warning (fail closed).
//   • Provenance: every row carries `sourceRecordId` = the Oura document `id`, `sourceResourceType` = collection.
//   • Rate limit (§14): 5000 req / 5 min per token and per app; 429 → RateLimitedError(Retry-After).
//   • AI boundary (§27, security/ai-data-boundaries.md): nothing here reaches a model — ai-policy.ts denies oura.
import { type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent, T, RateLimitedError, UnauthorizedError, VendorHttpError, compact, dailyDate, dailyMap, dayEndISO, dayStartISO, env, epoch, getJSON, hmacSha256, num, offsetMinutes, timingSafeEqual, tokenPost, vendorClient, webhookUrl } from "./core.ts"
import { errorSummary, log } from "./log.ts"

const FN = "oura"
const AUTH = "https://cloud.ouraring.com/oauth/authorize"
const TOKEN = "https://api.ouraring.com/oauth/token"
const API = "https://api.ouraring.com/v2"
// VERIFY: the data_type × event_type matrix must come from the pinned OpenAPI after app approval (§10, §30).
const DATA_TYPES = ["sleep", "daily_sleep", "daily_readiness", "daily_activity", "daily_spo2", "daily_stress", "vo2_max", "workout"]

/**
 * Oura API and MCP Agreement (effective 2026-06-08, §27): deletion within 72 hours in the described user-deletion
 * circumstances. Retention is executed by `wearable-vendor-disconnect` (raw events get `delete_after`; `erase: true`
 * deletes the readings now) — that function owns the clock; this constant is the contractual bound it must respect.
 */
export const OURA_DELETE_WITHIN_HOURS = 72

/** The FunctionAlps-generated challenge token (§4). No fallback: unset means the webhook path is closed. */
function verificationToken(): string | null {
  const v = Deno.env.get("OURA_WEBHOOK_VERIFICATION_TOKEN")
  if (!v) { log("warn", "oura.webhook_token_unset", { fn: FN, vendor: "oura" }); return null }
  return v
}

// MARK: - HTTP with the rate-limit headers (§14)

// VERIFY: §14 says 429s carry `Retry-After` plus "Oura-specific limit/window/reset/tier headers" without naming them;
// `X-RateLimit-Remaining` / `X-RateLimit-Reset` are the conventional names — pin them on a live 429.
const H_REMAINING = "X-RateLimit-Remaining"
const H_RESET = "X-RateLimit-Reset"

/** Seconds to wait from `Retry-After`, else from a reset header (unix seconds or seconds-from-now), else null. */
function retryAfterSeconds(headers: Headers): string | null {
  const ra = headers.get("Retry-After")
  if (ra) return ra
  const reset = num(headers.get(H_RESET))
  if (reset == null) return null
  return String(Math.max(1, Math.ceil(reset > 1e9 ? reset - Date.now() / 1000 : reset)))
}

async function ouraGet(url: string, tokens: TokenSet): Promise<{ json: Record<string, unknown>; remaining: number | null; retryAfter: string | null }> {
  const resp = await fetch(url, { headers: { Accept: "application/json", Authorization: `Bearer ${tokens.accessToken}` } })
  const text = await resp.text()
  if (resp.status === 401) throw new UnauthorizedError(text.slice(0, 200))
  if (resp.status === 429) throw new RateLimitedError(retryAfterSeconds(resp.headers))
  if (!resp.ok) throw new VendorHttpError(resp.status, `GET ${url.split("?")[0]}: ${text.slice(0, 300)}`)
  return { json: text ? JSON.parse(text) : {}, remaining: num(resp.headers.get(H_REMAINING)), retryAfter: retryAfterSeconds(resp.headers) }
}

/** All pages of a usercollection (§13: `data` + `next_token` until absent). A page that exhausts the quota with more to come stops here. */
async function pages(path: string, tokens: TokenSet, q: Record<string, string>): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = []
  let next = ""
  for (let i = 0; i < 20; i++) {
    const qs = new URLSearchParams({ ...q, ...(next ? { next_token: next } : {}) })
    const { json, remaining, retryAfter } = await ouraGet(`${API}/usercollection/${path}?${qs}`, tokens)
    out.push(...((json.data as Record<string, unknown>[]) ?? []))
    next = (json.next_token as string) ?? ""
    if (!next) break
    if (remaining != null && remaining <= 0) { log("warn", "oura.rate_limit_exhausted", { fn: FN, vendor: "oura", path }); throw new RateLimitedError(retryAfter) }
  }
  return out
}

// MARK: - Row helpers

const prov = (collection: string, id: unknown, extra: Record<string, unknown> = {}) => ({ sourceRecordId: id == null ? null : String(id), sourceResourceType: collection, ...extra })

function series(id: number, s: Record<string, unknown> | undefined, extra: Partial<EpochRow> = {}): EpochRow[] {
  if (!s || !Array.isArray(s.items) || typeof s.timestamp !== "string") return []
  const start = Date.parse(s.timestamp), step = (num(s.interval) ?? 300) * 1000
  return compact((s.items as unknown[]).map((v, i) => epoch(new Date(start + i * step).toISOString(), id, num(v), { endTs: new Date(start + (i + 1) * step).toISOString(), ...extra })))
}

/** `sleep_phase_5_min`: one char per 5 minutes — 1 deep, 2 light, 3 REM, 4 awake (Oura v2 docs). */
function phases(code: string | undefined, start: string | undefined, extra: Partial<EpochRow> = {}): EpochRow[] {
  if (!code || !start) return []
  const t0 = Date.parse(start), map: Record<string, number> = { "1": T.SleepDeepBinary, "2": T.SleepLightBinary, "3": T.SleepREMBinary, "4": T.SleepAwakeBinary }
  return compact([...code].map((c, i) => map[c] ? epoch(new Date(t0 + i * 300_000).toISOString(), map[c], 5, { endTs: new Date(t0 + (i + 1) * 300_000).toISOString(), ...extra }) : null))
}

// MARK: - Adapter

export const oura: VendorAdapter = {
  key: "oura",
  name: "Oura",
  pkce: "not_documented",  // §6: "PKCE: NOT DOCUMENTED" — no code_challenge is sent (core.sendsPKCE is false).
  // §6 + 19_OAUTH_ACCOUNT_LIFECYCLE.md: minimal scopes, no `email`. `personal` is needed for personal_info → user id (§9).
  scopes: ["personal", "daily", "heartrate", "workout", "spo2Daily"],
  reconcile: { nightlyDays: 3, weeklyDays: 14 },  // §17

  authorizeURL({ clientId, redirectUri, state }) {
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, redirect_uri: redirectUri, scope: oura.scopes.join(" "), state })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("oura")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri, client_id: clientId, client_secret: clientSecret })
    const me = await getJSON(`${API}/usercollection/personal_info`, { Authorization: `Bearer ${t.access_token}` })
    // VERIFY: §9 — pin the exact personal_info identity property (name/type) on a live fixture; `id` is the documented guess.
    const vendorUserId = me.id == null ? "" : String(me.id)
    // §7: absolute expiry from `expires_in`; the 30 d fallback is only for a response without it.
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 2_592_000), scopes: oura.scopes, vendorUserId }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("oura")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string) ?? refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 2_592_000) }
  },

  async revoke(tokens) {
    // VERIFY: §25 — the revoke URL is documented, the HTTP method is not; POST is the guess. Best effort, never throws.
    try {
      const r = await fetch(`https://api.ouraring.com/oauth/revoke?access_token=${encodeURIComponent(tokens.accessToken)}`, { method: "POST" })
      if (!r.ok) log("warn", "oura.revoke_failed", { fn: FN, vendor: "oura", status: r.status })
    } catch (e) { log("warn", "oura.revoke_failed", { fn: FN, vendor: "oura", ...errorSummary(e) }) }
  },

  async afterConnect(tokens) {
    // Subscriptions are per application, not per user; ouraMaintain is a no-op unless the flag is on.
    try { await ouraMaintain() } catch (e) { log("warn", "oura.subscriptions_failed", { fn: FN, vendor: "oura", ...errorSummary(e) }) }
    const me = await getJSON(`${API}/usercollection/personal_info`, { Authorization: `Bearer ${tokens.accessToken}` })
    // §26: personal-scope responses are never logged; only these non-identifying fields land in account meta (no email, §9).
    return { meta: { age: num(me.age), biological_sex: me.biological_sex ?? null, weight_kg: num(me.weight), height_m: num(me.height) } }
  },

  /** GET handshake (§11): `{ "challenge": … }` only when `verification_token` matches ours; unset token → 401. */
  challengeResponse(url) {
    const expected = verificationToken()
    const got = url.searchParams.get("verification_token") ?? ""
    if (!expected || !timingSafeEqual(got, expected)) return new Response("bad verification token", { status: 401 })
    return new Response(JSON.stringify({ challenge: url.searchParams.get("challenge") ?? "" }), { status: 200, headers: { "Content-Type": "application/json" } })
  },

  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    // Fail closed: without the verification token the subscription was never ours to accept (§4/§26).
    if (!verificationToken()) throw new Error("oura webhook verification token unset")
    // §11 / 20_WEBHOOK_SYNC_SECURITY.md: HMAC-SHA256 with the client secret over `timestamp + body`, uppercase hex.
    // VERIFY: the official example signs `JSON.stringify(body)`; we sign the raw bytes — pin on a captured live delivery.
    const secret = env("OURA_CLIENT_SECRET")
    const ts = req.headers.get("x-oura-timestamp") ?? "", sig = (req.headers.get("x-oura-signature") ?? "").toUpperCase()
    const mac = (await hmacSha256(secret, ts + rawBody)).toUpperCase()
    if (!sig || !timingSafeEqual(mac, sig)) throw new Error("oura signature mismatch")
    if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) throw new Error("oura timestamp too old")
    const e = JSON.parse(rawBody) as Record<string, unknown>
    if (!e.user_id) return []
    // §10: body = event_type, data_type, object_id, user_id — a trigger, never the record (§16). No vendor event id is
    // documented (architecture/07-provenance-deduplication.md), so the dedupe key is the stable triple.
    // VERIFY: two `update` deliveries for the same object collapse into one receipt; fine while the pull window is 3 d.
    const dataType = String(e.data_type ?? ""), eventType = String(e.event_type ?? ""), objectId = e.object_id == null ? "" : String(e.object_id)
    return [{ vendorUserId: String(e.user_id), kind: `${dataType}.${eventType}`, eventId: objectId ? `${dataType}.${eventType}.${objectId}` : null }]
  },

  async fetchRange(tokens, start, end) {
    const q = { start_date: start, end_date: end }
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []

    for (const s of await pages("sleep", tokens, q)) {
      const type = String(s.type ?? ""), day = String(s.day), id = s.id
      const tz = offsetMinutes(String(s.bedtime_start ?? ""))
      const P = prov("sleep", id, { timezoneOffset: tz })
      if (type === "long_sleep") {
        // Main sleep → the daily main-sleep ids (§19: seconds; Oura `day` preserved, never derived).
        dailyRows.push(...dailyMap(day, {
          [T.MainSleepDuration]: num(s.total_sleep_duration), [T.InBed]: num(s.time_in_bed), [T.REM]: num(s.rem_sleep_duration), [T.Deep]: num(s.deep_sleep_duration),
          [T.Light]: num(s.light_sleep_duration), [T.Awake]: num(s.awake_time), [T.Latency]: num(s.latency), [T.SleepEfficiency]: num(s.efficiency), [T.Interruptions]: num(s.restless_periods),
          [T.HeartRateSleep]: num(s.average_heart_rate), [T.HeartRateSleepLowest]: num(s.lowest_heart_rate), [T.HeartRateResting]: num(s.lowest_heart_rate), [T.RespirationRateSleep]: num(s.average_breath),
        }, { ...P, details: { type } }))
        // D4: `average_hrv` stays raw — on the duration row's details, under no HRV id (§20).
        const main = dailyRows.find((r) => r.day === day && r.dataTypeId === T.MainSleepDuration && r.sourceRecordId === P.sourceRecordId)
        if (main) main.details = { ...main.details, average_hrv_unverified: num(s.average_hrv) }
        dailyRows.push(...compact([dailyDate(day, T.SleepStart, s.bedtime_start as string, P), dailyDate(day, T.SleepEnd, s.bedtime_end as string, P)]))
        epochRows.push(...series(T.HeartRate, s.heart_rate as Record<string, unknown>, { ...P, details: { type } }), ...phases(s.sleep_phase_5_min as string, s.bedtime_start as string, { ...P, details: { type } }))
      } else {
        // Naps / rest / other sessions: epoch rows only, tagged with the Oura type; the day's main-sleep ids stay untouched.
        const details = { type, day, total_sleep_duration: num(s.total_sleep_duration), time_in_bed: num(s.time_in_bed), bedtime_start: s.bedtime_start ?? null, bedtime_end: s.bedtime_end ?? null }
        epochRows.push(...series(T.HeartRate, s.heart_rate as Record<string, unknown>, { ...P, details }), ...phases(s.sleep_phase_5_min as string, s.bedtime_start as string, { ...P, details }))
      }
    }
    // §18 / 14_RECOVERY_READINESS_STRAIN.md: sleep score → 1000105 (2201 kept as the generic quality mirror); contributors stay in details.
    for (const d of await pages("daily_sleep", tokens, q)) dailyRows.push(...dailyMap(String(d.day), { [T.SleepQuality]: num(d.score), [T.SleepScore]: num(d.score) }, prov("daily_sleep", d.id, { details: { contributors: d.contributors ?? null } })))
    // §18: readiness → 1000100; `temperature_deviation` is explicitly a deviation → 1000106.
    for (const r of await pages("daily_readiness", tokens, q)) dailyRows.push(...dailyMap(String(r.day), { [T.ReadinessScore]: num(r.score), [T.SkinTemperatureDeviation]: num(r.temperature_deviation) }, prov("daily_readiness", r.id, { details: { contributors: r.contributors ?? null, temperature_trend_deviation: num(r.temperature_trend_deviation) } })))
    for (const a of await pages("daily_activity", tokens, q)) {
      const day = String(a.day), high = num(a.high_activity_time) ?? 0, med = num(a.medium_activity_time) ?? 0, low = num(a.low_activity_time) ?? 0
      dailyRows.push(...dailyMap(day, {
        [T.Steps]: num(a.steps),  // §22: identity, daily count.
        [T.ActiveBurnedCalories]: num(a.active_calories),
        [T.BurnedCalories]: num(a.total_calories),  // VERIFY: §22 — 1010 only after the documented unit (kcal) is pinned from the schema.
        [T.CoveredDistance]: num(a.equivalent_walking_distance),
        [T.ActivityDuration]: (high + med + low) / 60, [T.ActivityHigh]: high / 60, [T.ActivityMid]: med / 60, [T.ActivityLow]: low / 60, [T.ActivitySedentary]: (num(a.sedentary_time) ?? 0) / 60 || null,
      }, prov("daily_activity", a.id, { details: { score: num(a.score), average_met_minutes: num(a.average_met_minutes) } })))
      epochRows.push(...series(T.MET, a.met as Record<string, unknown>, prov("daily_activity", a.id)))
    }
    for (const p of await pages("daily_spo2", tokens, q)) dailyRows.push(...dailyMap(String(p.day), { [T.SPO2]: num((p.spo2_percentage as Record<string, unknown>)?.average), [T.Breathing]: num(p.breathing_disturbance_index) }, prov("daily_spo2", p.id)))
    // VERIFY: the path casing `vO2_max` is what the v2 docs show; confirm against the pinned OpenAPI (§12).
    for (const v of await pages("vO2_max", tokens, q)) dailyRows.push(...dailyMap(String(v.day), { [T.VO2max]: num(v.vo2_max) }, prov("vO2_max", v.id)))
    for (const st of await pages("daily_stress", tokens, q)) {
      const stress = num(st.stress_high), recovery = num(st.recovery_high)
      dailyRows.push(...dailyMap(String(st.day), { [T.HighStress]: stress != null ? stress / 60 : null, [T.LowStress]: recovery != null ? recovery / 60 : null }, prov("daily_stress", st.id, { details: { day_summary: st.day_summary ?? null } })))
    }
    for (const w of await pages("workout", tokens, q)) {
      const startTs = String(w.start_datetime), P = prov("workout", w.id, { endTs: w.end_datetime as string })
      epochRows.push(...compact([
        epoch(startTs, T.ActivityType, 0, { ...P, valueText: String(w.activity ?? ""), valueType: "STRING", details: { intensity: w.intensity, source: w.source, label: w.label } }),
        epoch(startTs, T.ActiveBurnedCalories, num(w.calories), { ...P, details: { workout: true } }),
        epoch(startTs, T.CoveredDistance, num(w.distance), { ...P, details: { workout: true } }),
      ]))
    }
    // Daytime heart rate (5-min-ish samples): ISO datetime range. Samples carry no document id → sourceRecordId null.
    try {
      const hr = await pages("heartrate", tokens, { start_datetime: dayStartISO(start), end_datetime: dayEndISO(end) })
      epochRows.push(...compact(hr.map((h) => epoch(String(h.timestamp), T.HeartRate, num(h.bpm), { sourceResourceType: "heartrate", details: { source: h.source } }))))
    } catch (e) {
      if (e instanceof RateLimitedError || e instanceof UnauthorizedError) throw e
      log("warn", "oura.heartrate_failed", { fn: FN, vendor: "oura", ...errorSummary(e) })
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}

// MARK: - App-level webhook subscriptions (flagged)

export interface OuraMaintainResult { created: number; renewed: number; skipped?: boolean }

/**
 * Ensures every (data_type × create|update) subscription exists and renews those expiring within 7 days.
 * Pure function of the flag: without `OURA_MAINTAIN_SUBSCRIPTIONS=1` nothing is fetched and `skipped: true` is returned.
 * VERIFY: the subscription endpoint paths/body below are the public rendering, not the pinned OpenAPI (§10 blocker).
 */
export async function ouraMaintain(): Promise<OuraMaintainResult> {
  if (Deno.env.get("OURA_MAINTAIN_SUBSCRIPTIONS") !== "1") return { created: 0, renewed: 0, skipped: true }
  const token = verificationToken()
  if (!token) return { created: 0, renewed: 0, skipped: true }
  const { clientId, clientSecret } = vendorClient("oura")
  const h = { "x-client-id": clientId, "x-client-secret": clientSecret, "Content-Type": "application/json", Accept: "application/json" }
  const listResp = await fetch(`${API}/webhook/subscription`, { headers: h })
  if (listResp.status === 429) throw new RateLimitedError(retryAfterSeconds(listResp.headers))
  if (!listResp.ok) throw new VendorHttpError(listResp.status, "oura subscriptions list")
  const existing = (await listResp.json()) as { id: string; data_type: string; event_type: string; expiration_time?: string }[]
  let created = 0, renewed = 0
  const soon = Date.now() + 7 * 86_400_000
  for (const s of existing) {
    if (s.expiration_time && Date.parse(s.expiration_time) < soon) {
      const r = await fetch(`${API}/webhook/subscription/renew/${s.id}`, { method: "PUT", headers: h })
      if (r.ok) renewed++
    }
  }
  for (const data_type of DATA_TYPES) for (const event_type of ["create", "update"]) {
    if (existing.some((s) => s.data_type === data_type && s.event_type === event_type)) continue
    const r = await fetch(`${API}/webhook/subscription`, { method: "POST", headers: h, body: JSON.stringify({ callback_url: webhookUrl("oura"), verification_token: token, event_type, data_type }) })
    if (r.ok) created++
    else log("warn", "oura.subscribe_failed", { fn: FN, vendor: "oura", data_type, event_type, status: r.status })
  }
  log("info", "oura.subscriptions_maintained", { fn: FN, vendor: "oura", created, renewed })
  return { created, renewed }
}
