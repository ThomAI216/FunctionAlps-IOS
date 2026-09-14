// Withings Public Health Data API — strategy 2026-09-14 Phase 2 (Withings correction PR), D4 HRV gate, D10 secret names.
// Corpus (all under FunctionAlps-STUDIO/.context/research/):
//   W  = 2026-09-14_wearables-implementation/vendors/withings.md (sections cited as W §n)
//   P19 = 2026-09-14_functionalps-wearables-implementation-pack/19_OAUTH_ACCOUNT_LIFECYCLE.md "Withings"
//   P20 = …/20_WEBHOOK_SYNC_SECURITY.md "Withings — deliberately treat as unsigned pointer"
//   P16 = …/16_BLOOD_PRESSURE_PWV_AFIB.md, P15 = …/15_BODY_COMPOSITION.md "Withings implementation", P07 = …/07_HRV.md "Withings — do not guess algorithm"
//   HRV = 2026-09-14_wearables-implementation/metrics/hrv-semantics.md "Vendor decisions"; MAP = …/metrics/canonical-metric-map.md
// Facts relied on:
//   • Form-encoded POSTs, `{status, body}` envelopes (HTTP 200 always — `status !== 0` is the error); comma-separated scopes (W §6);
//     30-second authorization codes, 3-hour access tokens, 1-year rotating refresh tokens with a documented grace window (W §8, P19).
//   • `action=requesttoken` IS SIGNED: "Withings signing requires first obtaining a nonce and calculating the documented HMAC-SHA256
//     signature using client secret and the ordered/comma-concatenated signing fields. Request includes client ID, code, grant type,
//     redirect URI, nonce and signature" (W §7); "Nonce/HMAC request signing is part of token exchange" (W §26); flow "get nonce →
//     HMAC-signed requesttoken" (W §5); P19 "official signed-request flow". Refresh is the same `requesttoken` action → signed too.
//   • Notifications are UNSIGNED triggers: "No public cryptographic notification signature is documented" (W §11, P20); only the
//     authenticated pull writes health values. Body is form-encoded `userid, appli, startdate, enddate, [date, deviceid, action]` (W §10, P20).
//   • HRV: "Withings overnight HRV mathematical definition is not verified … do not map it to RMSSD/SDNN" (W §18, §20; HRV; MAP; P07)
//     → D4: `sdnn_1` / `rmssd` are RAW-ONLY (details of the sleep-duration row), never 3100 / 3106 / 3112.
//   • PWV → catalogue 3008 (P16 "Best source": the API "explicitly covers BP, body metrics, heart recordings and PWV"; pack index
//     "PWV/AFib/BP 3008, 3120, 3300–3301"). BP systolic+diastolic share one `source_record_id` and timestamp (P16 "Measurement pairing").
//   • Region: the app is an EU app, API base `https://wbsapi.withings.net`, `WITHINGS_REGION=EU` (W §3, §4, §7, §26; strategy D10).
import { type AccountContext, type DailyRow, type EpochRow, type ExchangeResult, type TokenSet, type VendorAdapter, type WebhookEvent, T, UnauthorizedError, compact, daily, dailyDate, dailyMap, daysBetween, env, epoch, hmacSha256, mean, num, unixOf, vendorClient, webhookUrl } from "./core.ts"
import { errorSummary, log } from "./log.ts"

const AUTH = "https://account.withings.com/oauth2_user/authorize2"
/** The corpus pins ONE host (EU, W §7 "EU API base", §26 "EU cloud endpoint should be pinned for Swiss users") and gives no host table per
 *  region. `WITHINGS_REGION` (D10, default `EU`) is therefore read only to flag a mismatch — VERIFY: add a host here if Withings ever
 *  documents a non-EU base for the FunctionAlps app. */
const HOSTS: Record<string, string> = { EU: "https://wbsapi.withings.net" }
const SCOPES = "user.info,user.metrics,user.activity,user.sleepevents"
/** Notification categories subscribed per user (W §10 `appli`). VERIFY: the corpus does not list the appli codes ("Open: the exact
 *  `appli` category list", 2026-09-13 research prompt); 1 weight, 2 temperature, 4 heart/BP, 16 activity, 44 sleep, 46 user-info/unlink
 *  come from the Withings notification reference and must be confirmed against the current page before go-live. */
const APPLIS = [1, 2, 4, 16, 44, 46]

let regionChecked = false
export function apiBase(): string {
  const region = env("WITHINGS_REGION", "EU").toUpperCase()
  if (!HOSTS[region] && !regionChecked) {
    regionChecked = true
    log("warn", "withings.region_unpinned", { fn: "withings", vendor: "withings", region, note: "VERIFY: corpus pins only the EU host (W §7/§26); using EU" })
  }
  return HOSTS[region] ?? HOSTS.EU
}

async function wapi(path: string, params: Record<string, string | number>, accessToken?: string): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded" }
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`
  const r = await fetch(apiBase() + path, { method: "POST", headers, body: new URLSearchParams(Object.fromEntries(Object.entries(params).map(([k, v]) => [k, String(v)]))) })
  const j = (await r.json()) as { status: number; body?: Record<string, unknown>; error?: string }
  if (j.status === 401 || j.status === 2555) throw new UnauthorizedError(`withings status ${j.status}`)
  if (j.status !== 0) throw new Error(`withings ${path} status ${j.status}: ${String(j.error ?? "").slice(0, 200)}`)
  return j.body ?? {}
}

// MARK: - Request signing (W §7, §26; source `withings_sign` in pack 25_SOURCES.md)

/** The string Withings signs: the comma-joined ordered fields `action,client_id,<nonce | timestamp>` (W §7 "ordered/comma-concatenated
 *  signing fields", §26 "preserve exact parameter order"). `getnonce` signs the timestamp; every other action signs the nonce.
 *  VERIFY: the corpus does not print the field list per action — confirm against the official Signing Requests page on the first live exchange. */
export const signingString = (action: string, clientId: string, nonceOrTimestamp: string | number) => `${action},${clientId},${nonceOrTimestamp}`
export const sign = (secret: string, action: string, clientId: string, nonceOrTimestamp: string | number) => hmacSha256(secret, signingString(action, clientId, nonceOrTimestamp))

/** `getnonce` → the one-time nonce a signed request carries (W §5 "get nonce", §7). */
async function getNonce(clientId: string, clientSecret: string): Promise<string> {
  const timestamp = Math.floor(Date.now() / 1000)
  const body = await wapi("/v2/signature", { action: "getnonce", client_id: clientId, timestamp, signature: await sign(clientSecret, "getnonce", clientId, timestamp) })
  const nonce = String(body.nonce ?? "")
  if (!nonce) throw new Error("withings getnonce: empty nonce")
  return nonce
}

/** `client_id, nonce, signature` for a signed action. The corpus lists the signed `requesttoken` fields WITHOUT `client_secret`
 *  (W §7: "client ID, code, grant type, redirect URI, nonce and signature") — the signature replaces it. VERIFY on first live exchange. */
async function signedParams(action: string): Promise<{ client_id: string; nonce: string; signature: string }> {
  const { clientId, clientSecret } = vendorClient("withings")
  const nonce = await getNonce(clientId, clientSecret)
  return { client_id: clientId, nonce, signature: await sign(clientSecret, action, clientId, nonce) }
}

const tokenSet = (b: Record<string, unknown>): ExchangeResult => ({
  accessToken: String(b.access_token), refreshToken: b.refresh_token as string | undefined,
  expiresAt: Math.floor(Date.now() / 1000) + (num(b.expires_in) ?? 10_800), scopes: String(b.scope ?? SCOPES).split(","), vendorUserId: b.userid != null ? String(b.userid) : undefined,
})

// MARK: - Measure types (W §12/§18: "map by official `type` IDs only after pinning"; P15: "use the current Measure API reference for exact type constants")
// VERIFY: the numeric codes below are from the Withings Measure reference, not printed in the corpus; the TARGET ids are corpus-pinned
// (Weight 5020, FatRatio 5025 — MAP "Withings" rows; BP 3300/3301 + PWV 3008 — P16; SpO2 3009 — P09; temperature 5040/5041 — W §18).
const MEAS: Record<number, number> = { 1: T.Weight, 4: T.Height, 5: T.FatFreeMass, 6: T.FatRatio, 8: T.FatMass, 9: T.DiastolicBP, 10: T.SystolicBP, 11: T.HeartRate, 12: T.UndefinedTemperature, 54: T.SPO2, 71: T.BodyTemperature, 73: T.SkinTemperature, 76: T.MuscleMass, 77: T.WaterMass, 88: T.BoneMass, 91: T.PulseWaveVelocity, 123: T.VO2max, 130: T.AFib }
/** Measure types that also get a day-level row (latest device reading of the day). */
const DAILY_MEAS = new Set<number>([T.Weight, T.FatRatio, T.FatMass, T.FatFreeMass, T.MuscleMass, T.BoneMass, T.WaterMass, T.Height, T.VO2max, T.SPO2, T.DiastolicBP, T.SystolicBP, T.BodyTemperature, T.SkinTemperature, T.PulseWaveVelocity])

/** Withings measures are `value × 10^unit` (P15 "unit conventions"; e.g. weight 72450 / unit −3 → 72.45 kg, PWV 7850 / unit −3 → 7.85 m/s).
 *  Negative exponents divide so 72450 → 72.45 exactly rather than 72450 × 0.001. */
export function scaleMeasure(value: number, unit: number): number {
  return unit < 0 ? value / Math.pow(10, -unit) : value * Math.pow(10, unit)
}

const iso = (unix: unknown): string | null => { const n = num(unix); return n ? new Date(n * 1000).toISOString() : null }
/** The vendor-local day of an instant in an IANA zone (W §21: "preserve timezone from official response"); UTC day when the zone is unusable. */
export function localDayIn(unix: number, timeZone: string | null | undefined): string {
  const d = new Date(unix * 1000)
  if (timeZone) {
    try { return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(d) } catch { /* unknown zone → UTC */ }
  }
  return d.toISOString().slice(0, 10)
}

const warn = (event: string, e: unknown, extra: Record<string, unknown> = {}) => log("warn", event, { fn: "withings", vendor: "withings", ...errorSummary(e), ...extra })

export const withings: VendorAdapter = {
  key: "withings",
  name: "Withings",
  pkce: "not_documented",  // W §28 skeleton: `pkce:"not_documented"`
  scopes: SCOPES.split(","),
  reconcile: { nightlyDays: 3, weeklyDays: 14 },

  authorizeURL({ clientId, redirectUri, state }) {
    // W §6: response_type, client_id, scope (comma-separated), redirect_uri, state.
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, state, scope: SCOPES, redirect_uri: redirectUri })}`
  },

  async exchangeCode({ code, redirectUri }) {
    // W §7: signed `requesttoken` — client ID, code, grant type, redirect URI, nonce, signature. The code lives ~30 s (W §6), so no retries here.
    const signed = await signedParams("requesttoken")
    return tokenSet(await wapi("/v2/oauth2", { action: "requesttoken", grant_type: "authorization_code", ...signed, code, redirect_uri: redirectUri }))
  },

  async refresh(refreshToken) {
    // Same signed `requesttoken` action with `grant_type=refresh_token` (W §7/§8). Withings returns a NEW refresh token (W §8, P19) — stored by the caller.
    const signed = await signedParams("requesttoken")
    const t = tokenSet(await wapi("/v2/oauth2", { action: "requesttoken", grant_type: "refresh_token", ...signed, refresh_token: refreshToken }))
    return { ...t, refreshToken: t.refreshToken ?? refreshToken }
  },

  async revoke(_tokens, ctx) {
    // W §25: "revoke/unlink via current official OAuth endpoint if documented … Pin exact revoke call before production"; W §30 flags the
    // exact request as an open blocker. The corpus documents no parameters, so this keeps the signed `/v2/oauth2 action=revoke`
    // (client_id, nonce, userid, signature) — VERIFY against the current OAuth reference before go-live. Needs the stored userid (W §9).
    if (!ctx.vendorUserId) return
    const signed = await signedParams("revoke")
    await wapi("/v2/oauth2", { action: "revoke", ...signed, userid: ctx.vendorUserId })
  },

  async afterConnect(tokens, { webhookUrl: url }) {
    // W §10: `POST /notify`, Bearer user token, `action=subscribe`, `callbackurl`, `appli`, `comment`; Withings HEAD-checks the callback (P20).
    const subscribed: number[] = []
    for (const appli of APPLIS) {
      try { await wapi("/notify", { action: "subscribe", callbackurl: url, appli, comment: "FunctionAlps" }, tokens.accessToken); subscribed.push(appli) }
      catch (e) { warn("withings.subscribe_failed", e, { appli }) }
    }
    return { meta: { notify_applis: subscribed, notify_url: url } }
  },

  async unsubscribe(tokens, ctx) {
    // W §25: "Unsubscribe notification categories using current Withings notify operation for the user" → `notify` `action=revoke` per
    // appli subscribed in afterConnect (meta.notify_applis; the full list when meta is missing). VERIFY: the revoke parameters
    // (`callbackurl`, `appli`) mirror subscribe (W §10); the corpus does not print them.
    const fromMeta = Array.isArray(ctx.meta?.notify_applis) ? (ctx.meta.notify_applis as unknown[]).map(Number).filter(Number.isFinite) : []
    const applis = fromMeta.length ? fromMeta : APPLIS
    let callbackurl = typeof ctx.meta?.notify_url === "string" ? ctx.meta.notify_url : ""
    if (!callbackurl) { try { callbackurl = webhookUrl("withings") } catch (e) { warn("withings.unsubscribe_no_callback", e); return } }
    for (const appli of applis) {
      try { await wapi("/notify", { action: "revoke", callbackurl, appli }, tokens.accessToken) }
      catch (e) { warn("withings.unsubscribe_failed", e, { appli }) }
    }
  },

  parseWebhook(_req, rawBody): WebhookEvent[] {
    // Unsigned form-encoded trigger (W §10/§11, P20): userid, appli, startdate, enddate, [date, deviceid, action]. Nothing here is a
    // health value; the worker pulls the window with the user's token. Non-POST (Withings' HEAD reachability check) reaches us as an empty body → [].
    const p = Object.fromEntries(new URLSearchParams(rawBody))
    if (!p.userid) return []
    const day = (unix: string | undefined) => unix && /^\d+$/.test(unix) ? new Date(Number(unix) * 1000).toISOString().slice(0, 10) : undefined
    // VERIFY: the notification carries no stable event id (W §10 field list; provenance doc: "notification hash only schedules pull"),
    // so the dedupe key is the tuple appli:userid:startdate:enddate — a re-delivery of the same window collapses, a new window does not.
    const eventId = `${p.appli ?? "?"}:${p.userid}:${p.startdate ?? p.date ?? ""}:${p.enddate ?? p.date ?? ""}`
    // VERIFY: appli 46 (user info) with `action=unlink`/`delete` as the revocation signal is from the notification reference, not the corpus.
    const revoked = p.action === "unlink" || (p.appli === "46" && p.action === "delete")
    return [{ vendorUserId: String(p.userid), kind: `appli.${p.appli ?? "?"}.${p.action ?? "update"}`, eventId, windowStart: p.date?.slice(0, 10) ?? day(p.startdate), windowEnd: p.date?.slice(0, 10) ?? day(p.enddate), revoked }]
  },

  async fetchRange(tokens, start, end, _ctx: AccountContext) {
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    const tok = tokens.accessToken
    // ── Sleep summaries (W §12/§19; P08 "Withings": score, efficiency, latency, time in bed, stages, overnight HRV, RR, HR, snoring).
    // VERIFY: exact Sleep v2 field names/units are an open blocker (W §30) — `sdnn_1`/`rmssd` are requested from the summary and, when
    // absent there, read from the per-night series; either way they stay RAW (D4).
    const sum = await wapi("/v2/sleep", { action: "getsummary", startdateymd: start, enddateymd: end, data_fields: "total_timeinbed,total_sleep_time,sleep_efficiency,sleep_latency,waso,deepsleepduration,lightsleepduration,remsleepduration,wakeupduration,wakeupcount,hr_average,hr_min,rr_average,snoring,breathing_disturbances_intensity,sleep_score,sdnn_1,rmssd" }, tok)
    for (const n of (sum.series as Record<string, unknown>[]) ?? []) {
      const d = (n.data ?? {}) as Record<string, unknown>, day = String(n.date), st = num(n.startdate), en = num(n.enddate)
      const sleepId = n.id != null ? String(n.id) : `${day}:${st ?? ""}`
      const prov = { sourceRecordId: sleepId, sourceResourceType: "sleep_summary", sourceDeviceId: n.hash_deviceid != null ? String(n.hash_deviceid) : null, sourceModifiedAt: iso(n.modified) }
      const base = { model: n.model ?? null, sleep_id: n.id ?? null, timezone: n.timezone ?? null }
      // Per-night series (HR / RR per minute → epoch rows). HRV series values are only ever folded into the raw `_unverified` details.
      let sdnn = num(d.sdnn_1), rmssd = num(d.rmssd), hrvSource: string | null = sdnn != null || rmssd != null ? "sleep_summary" : null, hrvSamples = 0
      if (st && en) {
        try {
          const ser = await wapi("/v2/sleep", { action: "get", startdate: st, enddate: en, data_fields: "hr,rr,sdnn_1,rmssd" }, tok)
          const sd: number[] = [], rm: number[] = []
          for (const seg of (ser.series as Record<string, unknown>[]) ?? []) {
            const each = (m: unknown, f: (ts: string, x: number) => void) => { for (const [u, v] of Object.entries((m ?? {}) as Record<string, unknown>)) { const x = num(v); if (x != null) f(new Date(Number(u) * 1000).toISOString(), x) } }
            const ep = (id: number) => (ts: string, x: number) => { const row = epoch(ts, id, x, { details: { source: "sleep_series" }, sourceRecordId: sleepId, sourceResourceType: "sleep_series", sourceDeviceId: prov.sourceDeviceId, sourceModifiedAt: prov.sourceModifiedAt }); if (row) epochRows.push(row) }
            each(seg.hr, ep(T.HeartRate)); each(seg.rr, ep(T.RespirationRate))
            each(seg.sdnn_1, (_, x) => sd.push(x)); each(seg.rmssd, (_, x) => rm.push(x))
          }
          if (hrvSource == null && (sd.length || rm.length)) { sdnn = mean(sd); rmssd = mean(rm); hrvSource = "sleep_series_mean"; hrvSamples = Math.max(sd.length, rm.length) }
        } catch (e) { warn("withings.sleep_series_failed", e) }
      }
      // D4 gate: the HRV fields ride on the sleep-duration row as raw details and are never written to 3100 / 3106 / 3112.
      const hrv = hrvSource ? { sdnn_1_unverified: sdnn, rmssd_unverified: rmssd, hrv_source: hrvSource, ...(hrvSamples ? { hrv_samples: hrvSamples } : {}), hrv_note: "UNVERIFIED: Withings HRV statistic/window not pinned (strategy D4; W §20) — raw only, no canonical HRV row" } : {}
      const eff = num(d.sleep_efficiency)
      dailyRows.push(...compact([daily(day, T.MainSleepDuration, num(d.total_sleep_time), { ...prov, details: { ...base, ...hrv } })]))
      dailyRows.push(...dailyMap(day, {
        [T.InBed]: num(d.total_timeinbed), [T.REM]: num(d.remsleepduration), [T.Deep]: num(d.deepsleepduration), [T.Light]: num(d.lightsleepduration),
        [T.Awake]: num(d.wakeupduration), [T.Latency]: num(d.sleep_latency), [T.AwakeAfterWakeup]: num(d.waso), [T.Interruptions]: num(d.wakeupcount), [T.SleepEfficiency]: eff != null && eff <= 1 ? eff * 100 : eff,
        [T.SleepQuality]: num(d.sleep_score), [T.SleepScore]: num(d.sleep_score), [T.HeartRateSleep]: num(d.hr_average), [T.HeartRateSleepLowest]: num(d.hr_min), [T.RespirationRateSleep]: num(d.rr_average),
        [T.Snoring]: num(d.snoring), [T.Breathing]: num(d.breathing_disturbances_intensity),
      }, { ...prov, details: base }))
      if (st && en) dailyRows.push(...compact([dailyDate(day, T.SleepStart, new Date(st * 1000).toISOString(), { ...prov, details: base }), dailyDate(day, T.SleepEnd, new Date(en * 1000).toISOString(), { ...prov, details: base })]))
    }
    // ── Daily activity (Withings devices only; brand 18 = external source, skipped to avoid double counting with the Apple Health relay).
    // VERIFY: activity has no vendor record id — `activity:<date>` is a FunctionAlps key.
    const act = await wapi("/v2/measure", { action: "getactivity", startdateymd: start, enddateymd: end, data_fields: "steps,distance,elevation,active,calories,totalcalories,hr_average,hr_zone_0,hr_zone_1,hr_zone_2,hr_zone_3" }, tok)
    for (const x of (act.activities as Record<string, unknown>[]) ?? []) {
      if (num(x.brand) === 18) continue
      const day = String(x.date)
      dailyRows.push(...dailyMap(day, {
        [T.Steps]: num(x.steps), [T.CoveredDistance]: num(x.distance), [T.FloorsClimbed]: num(x.elevation), [T.ActivityDuration]: (num(x.active) ?? 0) / 60 || null, [T.ActiveBurnedCalories]: num(x.calories), [T.BurnedCalories]: num(x.totalcalories), [T.HeartRate]: num(x.hr_average),
        [T.HRZoneLight]: (num(x.hr_zone_0) ?? 0) / 60 || null, [T.HRZoneModerate]: (num(x.hr_zone_1) ?? 0) / 60 || null, [T.HRZoneIntense]: (num(x.hr_zone_2) ?? 0) / 60 || null, [T.HRZoneMaximal]: (num(x.hr_zone_3) ?? 0) / 60 || null,
      }, { details: { brand: num(x.brand), is_tracker: x.is_tracker ?? null, timezone: x.timezone ?? null }, sourceRecordId: `activity:${day}`, sourceResourceType: "activity", sourceDeviceId: x.deviceid != null ? String(x.deviceid) : null, sourceModifiedAt: iso(x.modified) }))
    }
    // ── Measures (body composition / BP / PWV / SpO2 / temperature): `value × 10^unit`, category 1 = real measures; device readings only
    // (attrib 0/1; manual entries 2+ skipped — P15 "whether user-entered/manual if exposed" is kept in details). Row identity = measure
    // group id (P15 "Keep: measurement group/id"; P16: systolic and diastolic share one `source_record_id` and timestamp).
    const meas = await wapi("/measure", { action: "getmeas", meastypes: Object.keys(MEAS).join(","), category: 1, startdate: unixOf(`${start}T00:00:00Z`), enddate: unixOf(`${end}T23:59:59Z`) }, tok)
    const tz = typeof meas.timezone === "string" ? meas.timezone : null
    for (const g of (meas.measuregrps as Record<string, unknown>[]) ?? []) {
      const attrib = num(g.attrib) ?? 0
      if (attrib > 1) continue
      const unix = num(g.date) ?? 0, ts = new Date(unix * 1000).toISOString(), day = localDayIn(unix, tz)
      const prov = { sourceRecordId: g.grpid != null ? String(g.grpid) : null, sourceResourceType: "measuregrp", sourceDeviceId: g.deviceid != null ? String(g.deviceid) : null, sourceModifiedAt: iso(g.modified) }
      for (const q of (g.measures as Record<string, unknown>[]) ?? []) {
        const type = num(q.type) ?? -1, id = MEAS[type]
        if (!id) continue
        const unit = num(q.unit) ?? 0
        let v = scaleMeasure(num(q.value) ?? 0, unit)
        if (id === T.Height) v *= 100  // metres → cm (catalogue 5030)
        const details = { grpid: g.grpid ?? null, attrib, model: g.model ?? null, meastype: type, unit_exponent: unit, timezone: tz }
        const row = epoch(ts, id, v, { ...prov, details })
        if (row) epochRows.push(row)
        if (DAILY_MEAS.has(id)) dailyRows.push(...dailyMap(day, { [id]: v }, { ...prov, details }))
      }
    }
    // ── Workouts.
    try {
      const wk = await wapi("/v2/measure", { action: "getworkouts", startdateymd: start, enddateymd: end, data_fields: "calories,hr_average,hr_min,hr_max,steps,distance,effduration" }, tok)
      for (const w of (wk.series as Record<string, unknown>[]) ?? []) {
        const st = num(w.startdate), en = num(w.enddate), d = (w.data ?? {}) as Record<string, unknown>
        if (!st) continue
        const startTs = new Date(st * 1000).toISOString(), endTs = en ? new Date(en * 1000).toISOString() : undefined
        const prov = { sourceRecordId: w.id != null ? String(w.id) : `workout:${st}`, sourceResourceType: "workout", sourceDeviceId: w.deviceid != null ? String(w.deviceid) : null, sourceModifiedAt: iso(w.modified) }
        epochRows.push(...compact([
          epoch(startTs, T.ActivityType, num(w.category) ?? 0, { ...prov, endTs, valueText: `withings_category_${w.category}`, valueType: "STRING", details: { workout_id: w.id ?? null, effduration: num(d.effduration) } }),
          epoch(startTs, T.ActiveBurnedCalories, num(d.calories), { ...prov, endTs, details: { workout: true } }), epoch(startTs, T.CoveredDistance, num(d.distance), { ...prov, endTs, details: { workout: true } }),
          epoch(startTs, T.HeartRate, num(d.hr_average), { ...prov, endTs, details: { workout: true, max: num(d.hr_max) } }),
        ]))
      }
    } catch (e) { warn("withings.workouts_failed", e) }
    return { daily: dailyRows, epoch: epochRows }
  },
}

export const _withingsTest = { daysBetween, APPLIS, MEAS, SCOPES }
