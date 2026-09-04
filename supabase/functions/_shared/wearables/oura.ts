// Oura API v2 — spec §3 (tier B for OAuth/endpoints; webhook signature tier C → VERIFY on first live event).
// Tokens 30 d, refresh single-use. Webhooks are app-level subscriptions (one per data_type × event_type),
// expiring: `ouraMaintain()` (called from wearable-vendor-sync's cron branch) creates/renews them.
import { type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent, T, compact, daily, dailyDate, dailyMap, dayEndISO, dayStartISO, env, epoch, getJSON, hmacSha256, mean, num, timingSafeEqual, tokenPost, vendorClient, webhookUrl } from "./core.ts"

const AUTH = "https://cloud.ouraring.com/oauth/authorize"
const TOKEN = "https://api.ouraring.com/oauth/token"
const API = "https://api.ouraring.com/v2"
const DATA_TYPES = ["sleep", "daily_sleep", "daily_readiness", "daily_activity", "daily_spo2", "daily_stress", "vo2_max", "workout"]

const verificationToken = () => env("OURA_VERIFICATION_TOKEN", vendorClient("oura").clientSecret)

async function pages(path: string, tokens: TokenSet, q: Record<string, string>): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = []
  let next = ""
  for (let i = 0; i < 20; i++) {
    const qs = new URLSearchParams({ ...q, ...(next ? { next_token: next } : {}) })
    const j = await getJSON(`${API}/usercollection/${path}?${qs}`, { Authorization: `Bearer ${tokens.accessToken}` })
    out.push(...((j.data as Record<string, unknown>[]) ?? []))
    next = (j.next_token as string) ?? ""
    if (!next) break
  }
  return out
}

function series(id: number, s: Record<string, unknown> | undefined, extra: Record<string, unknown> = {}): EpochRow[] {
  if (!s || !Array.isArray(s.items) || typeof s.timestamp !== "string") return []
  const start = Date.parse(s.timestamp), step = (num(s.interval) ?? 300) * 1000
  return compact((s.items as unknown[]).map((v, i) => epoch(new Date(start + i * step).toISOString(), id, num(v), { endTs: new Date(start + (i + 1) * step).toISOString(), details: extra })))
}

function phases(code: string | undefined, start: string | undefined): EpochRow[] {
  if (!code || !start) return []
  const t0 = Date.parse(start), map: Record<string, number> = { "1": T.SleepDeepBinary, "2": T.SleepLightBinary, "3": T.SleepREMBinary, "4": T.SleepAwakeBinary }
  return compact([...code].map((c, i) => map[c] ? epoch(new Date(t0 + i * 300_000).toISOString(), map[c], 5, { endTs: new Date(t0 + (i + 1) * 300_000).toISOString() }) : null))
}

export const oura: VendorAdapter = {
  key: "oura",
  name: "Oura",
  usesPKCE: false,
  scopes: ["email", "personal", "daily", "heartrate", "workout", "tag", "session", "spo2Daily"],

  authorizeURL({ clientId, redirectUri, state }) {
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, redirect_uri: redirectUri, scope: oura.scopes.join(" "), state })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("oura")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri, client_id: clientId, client_secret: clientSecret })
    const me = await getJSON(`${API}/usercollection/personal_info`, { Authorization: `Bearer ${t.access_token}` })
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 2_592_000), scopes: oura.scopes, vendorUserId: String(me.id ?? ""), raw: { email_domain: String(me.email ?? "").split("@")[1] ?? null } }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("oura")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string) ?? refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 2_592_000) }
  },

  async revoke(tokens) {
    await fetch(`https://api.ouraring.com/oauth/revoke?access_token=${encodeURIComponent(tokens.accessToken)}`, { method: "POST" })
  },

  async afterConnect(tokens) {
    // Webhook subscriptions are per application, not per user — make sure they exist (idempotent).
    try { await ouraMaintain() } catch (e) { console.warn("[oura] subscriptions", String(e).slice(0, 200)) }
    const me = await getJSON(`${API}/usercollection/personal_info`, { Authorization: `Bearer ${tokens.accessToken}` })
    return { meta: { age: num(me.age), biological_sex: me.biological_sex ?? null, weight_kg: num(me.weight), height_m: num(me.height) } }
  },

  challengeResponse(url) {
    if (url.searchParams.get("verification_token") !== verificationToken()) return new Response("bad verification token", { status: 401 })
    return new Response(JSON.stringify({ challenge: url.searchParams.get("challenge") ?? "" }), { status: 200, headers: { "Content-Type": "application/json" } })
  },

  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    const { clientSecret } = vendorClient("oura")
    const ts = req.headers.get("x-oura-timestamp") ?? "", sig = (req.headers.get("x-oura-signature") ?? "").toUpperCase()
    const mac = (await hmacSha256(clientSecret, ts + rawBody)).toUpperCase()
    if (!sig || !timingSafeEqual(mac, sig)) throw new Error("oura signature mismatch")
    if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) throw new Error("oura timestamp too old")
    const e = JSON.parse(rawBody) as Record<string, unknown>
    if (!e.user_id) return []
    return [{ vendorUserId: String(e.user_id), kind: `${e.data_type}.${e.event_type}` }]
  },

  async fetchRange(tokens, start, end) {
    const q = { start_date: start, end_date: end }
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    for (const s of await pages("sleep", tokens, q)) {
      if (!["long_sleep", "sleep"].includes(String(s.type))) continue
      const day = String(s.day)
      const hrv = num(s.average_hrv)
      dailyRows.push(...dailyMap(day, {
        [T.MainSleepDuration]: num(s.total_sleep_duration), [T.InBed]: num(s.time_in_bed), [T.REM]: num(s.rem_sleep_duration), [T.Deep]: num(s.deep_sleep_duration),
        [T.Light]: num(s.light_sleep_duration), [T.Awake]: num(s.awake_time), [T.Latency]: num(s.latency), [T.SleepEfficiency]: num(s.efficiency), [T.Interruptions]: num(s.restless_periods),
        [T.HeartRateSleep]: num(s.average_heart_rate), [T.HeartRateSleepLowest]: num(s.lowest_heart_rate), [T.HeartRateResting]: num(s.lowest_heart_rate), [T.RespirationRateSleep]: num(s.average_breath),
      }, { details: { sleep_id: s.id, type: s.type } }))
      if (hrv != null) dailyRows.push(...dailyMap(day, { [T.RmssdSleep]: hrv, [T.Rmssd]: hrv }, { details: { statistic: "rmssd", window: "night", sleep_id: s.id } }))
      dailyRows.push(...compact([dailyDate(day, T.SleepStart, s.bedtime_start as string), dailyDate(day, T.SleepEnd, s.bedtime_end as string)]))
      epochRows.push(...series(T.Rmssd, s.hrv as Record<string, unknown>), ...series(T.HeartRate, s.heart_rate as Record<string, unknown>, { source: "sleep" }), ...phases(s.sleep_phase_5_min as string, s.bedtime_start as string))
    }
    for (const d of await pages("daily_sleep", tokens, q)) dailyRows.push(...dailyMap(String(d.day), { [T.SleepQuality]: num(d.score), [T.SleepScore]: num(d.score) }, { details: { contributors: d.contributors ?? null } }))
    for (const r of await pages("daily_readiness", tokens, q)) dailyRows.push(...dailyMap(String(r.day), { [T.ReadinessScore]: num(r.score), [T.SkinTemperatureDeviation]: num(r.temperature_deviation) }, { details: { contributors: r.contributors ?? null, temperature_trend_deviation: num(r.temperature_trend_deviation) } }))
    for (const a of await pages("daily_activity", tokens, q)) {
      const day = String(a.day), high = num(a.high_activity_time) ?? 0, med = num(a.medium_activity_time) ?? 0, low = num(a.low_activity_time) ?? 0
      dailyRows.push(...dailyMap(day, {
        [T.Steps]: num(a.steps), [T.ActiveBurnedCalories]: num(a.active_calories), [T.BurnedCalories]: num(a.total_calories), [T.CoveredDistance]: num(a.equivalent_walking_distance),
        [T.ActivityDuration]: (high + med + low) / 60, [T.ActivityHigh]: high / 60, [T.ActivityMid]: med / 60, [T.ActivityLow]: low / 60, [T.ActivitySedentary]: (num(a.sedentary_time) ?? 0) / 60 || null,
      }, { details: { score: num(a.score), average_met_minutes: num(a.average_met_minutes) } }))
      epochRows.push(...series(T.MET, a.met as Record<string, unknown>))
    }
    for (const p of await pages("daily_spo2", tokens, q)) dailyRows.push(...dailyMap(String(p.day), { [T.SPO2]: num((p.spo2_percentage as Record<string, unknown>)?.average), [T.Breathing]: num(p.breathing_disturbance_index) }))
    for (const v of await pages("vO2_max", tokens, q)) dailyRows.push(...dailyMap(String(v.day), { [T.VO2max]: num(v.vo2_max) }))
    for (const st of await pages("daily_stress", tokens, q)) {
      const stress = num(st.stress_high), recovery = num(st.recovery_high)
      dailyRows.push(...dailyMap(String(st.day), { [T.HighStress]: stress != null ? stress / 60 : null, [T.LowStress]: recovery != null ? recovery / 60 : null }, { details: { day_summary: st.day_summary ?? null } }))
    }
    for (const w of await pages("workout", tokens, q)) {
      const startTs = String(w.start_datetime)
      epochRows.push(...compact([
        epoch(startTs, T.ActivityType, 0, { endTs: w.end_datetime as string, valueText: String(w.activity ?? ""), valueType: "STRING", details: { intensity: w.intensity, source: w.source, label: w.label } }),
        epoch(startTs, T.ActiveBurnedCalories, num(w.calories), { endTs: w.end_datetime as string, details: { workout: true } }),
        epoch(startTs, T.CoveredDistance, num(w.distance), { endTs: w.end_datetime as string, details: { workout: true } }),
      ]))
    }
    // Daytime heart rate (5-min-ish samples): ISO datetime range.
    try {
      const hr = await pages("heartrate", tokens, { start_datetime: dayStartISO(start), end_datetime: dayEndISO(end) })
      epochRows.push(...compact(hr.map((h) => epoch(String(h.timestamp), T.HeartRate, num(h.bpm), { details: { source: h.source } }))))
    } catch (e) { console.warn("[oura] heartrate", String(e).slice(0, 120)) }
    return { daily: dailyRows, epoch: epochRows }
  },
}

/** Ensures every (data_type × create|update) subscription exists and renews those expiring within 7 days. */
export async function ouraMaintain(): Promise<{ created: number; renewed: number }> {
  const { clientId, clientSecret } = vendorClient("oura")
  const h = { "x-client-id": clientId, "x-client-secret": clientSecret, "Content-Type": "application/json", Accept: "application/json" }
  const listResp = await fetch(`${API}/webhook/subscription`, { headers: h })
  if (!listResp.ok) throw new Error(`oura subscriptions list ${listResp.status}`)
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
    const r = await fetch(`${API}/webhook/subscription`, { method: "POST", headers: h, body: JSON.stringify({ callback_url: webhookUrl("oura"), verification_token: verificationToken(), event_type, data_type }) })
    if (r.ok) created++
    else console.warn("[oura] subscribe", data_type, event_type, r.status, (await r.text()).slice(0, 120))
  }
  return { created, renewed }
}

export const _ouraTest = { mean, daily }
