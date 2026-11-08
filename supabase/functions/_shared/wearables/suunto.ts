// Suunto Cloud API — Phase 2 correction (strategy 2026-09-14; decisions D4 secrets, D10 secret table).
// Authority: .context/research/2026-09-14_wearables-implementation/vendors/suunto.md (+ metrics/*, security/*),
// implementation pack 07_HRV / 08_SLEEP / 13_STRESS / 14_RECOVERY / 20_WEBHOOK. Status per the corpus:
//   VERIFIED (public quick-start / webhook page): authorize + token endpoints with Basic client auth, JWT
//     access token whose `user` claim is the Suunto username (also `username` in webhooks), `expires_in`,
//     `Ocp-Apim-Subscription-Key` on every data call, webhook header `X-HMAC-SHA256-Signature` = HMAC-SHA256
//     over the exact body, LOWERCASE HEX, event types WORKOUT_CREATED / ROUTE_CREATED / SUUNTO_247_*_CREATED,
//     the 24/7 sleep field names (08_SLEEP.md "Suunto").
//   VERIFY (partner portal / partner schema): PKCE + `state` support (§6), the refresh contract (§8), the
//     deauthorize endpoint (§25), `AvgHRV` semantics (§20), the StressState meaning (§18).
// Rules applied here (updated 2026-11-06 against the APIZone reference — see the block above `chunkDays`): absent fields are
// skipped, never written as zeros; sleep durations are seconds (`details.unit`); `AvgHRV` / `HRV` are NEVER written to
// 3100/3106/3112/3113 — they live in `details.avg_hrv_unverified` / `details.hrv_unverified`; recovery Balance → 1000134 as a
// 0–1 number, StressState → 1000135 as a STRING row (meaning undocumented, never 1000109); every row carries
// sourceRecordId/sourceResourceType. Still to confirm in the partner portal: PKCE/`state`, the refresh contract, deauthorize.
import { type DailyRow, type EpochRow, NAMES, RateLimitedError, type RowBatch, type TokenSet, UnauthorizedError, type VendorAdapter, VendorHttpError, type WebhookEvent, T, compact, dailyDate, dailyText, dayOfISO, env, epoch, getJSON, hmacSha256, num, offsetMinutes, timingSafeEqual, tokenPost, vendorClient } from "./core.ts"
import { errorSummary, log } from "./log.ts"

const AUTH = "https://cloudapi-oauth.suunto.com/oauth/authorize"
const TOKEN = "https://cloudapi-oauth.suunto.com/oauth/token"
const DEAUTHORIZE = "https://cloudapi-oauth.suunto.com/oauth/deauthorize"
const API = "https://cloudapi.suunto.com"
const FN = "suunto"

/** Both secrets on every data call (suunto.md §12, §26): the OAuth JWT and the APIM subscription key. */
const headers = (tokens: TokenSet) => ({ Authorization: `Bearer ${tokens.accessToken}`, "Ocp-Apim-Subscription-Key": env("SUUNTO_SUBSCRIPTION_KEY") })

function jwtClaims(token: string): Record<string, unknown> {
  try { return JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))) } catch { return {} }
}

const str = (v: unknown): string | null => (v == null || v === "" ? null : String(v))
/** Epoch rows start at the UTC instant (like every other adapter); the vendor's offset stays in `timezoneOffset` and the raw stamp in `sourceRecordId`. */
const utcISO = (iso: string): string | null => { const t = Date.parse(iso); return Number.isFinite(t) ? new Date(t).toISOString() : null }
const expiresAt = (t: Record<string, unknown>) => Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 86_400)  // suunto.md §7: "use actual expires_in"; 86400 is the documented example
const scopesOf = (t: Record<string, unknown>): string[] | undefined => (typeof t.scope === "string" && t.scope ? t.scope.split(/[ ,]+/) : undefined)

/** A STRING epoch row (categorical sample) — core has `dailyText` but no epoch twin; same shape, built here. */
function epochText(startTs: string, id: number, text: string | null, extra: Partial<EpochRow> = {}): EpochRow | null {
  if (!text) return null
  return { startTs, dataTypeId: id, dataTypeName: NAMES[id] ?? String(id), value: null, valueText: text, valueType: "STRING", ...extra }
}

type Sample = { timestamp?: string; entryData?: Record<string, unknown> }
const RES = { sleep: "247_sleep", recovery: "247_recovery", activity: "247_activity", dailyStats: "247_daily_activity_statistics", workout: "workout" } as const

// ── 2026-11-06: rebuilt against Suunto's APIZone reference (SUUNTO 247 DATA API, SUUNTO WORKOUT API, the webhook page) ──
// What the official pages pin, and this file follows:
//   • `/247samples/{sleep,recovery,activity}?from&to` (epoch ms) and `/247samples/daily-activity-statistics?startdate&enddate`
//     (ISO-8601): "Maximum fetch interval duration is 28 days" → 28-day chunks. Data "fetched from the API using UTC time".
//   • daily statistics return `[{ Name: "stepcount" | "energyconsumption", Aggregation: "sum", Sources: [{ Samples:
//     [{ TimeISO8601, Value }] }] }]`, energy "in joules" (the old call used from/to in ms and read fields that do not exist).
//   • sleep durations are SECONDS and `Duration` is TIME IN BED: the webhook example spans 23:29 → 08:30 = 32 460 s = Duration,
//     while Deep + Light + REM = 30 600 s. So asleep (2300) = Deep + Light + REM, in bed (2301) = Duration, latency 2307,
//     wake after sleep onset 2308 (catalogue: "wake-after-sleep-onset"); WakeBeforeOffBed stays in details.
//   • recovery `Balance` is a 0–1 number (examples 0.82, 0.85) → 1000134 numeric; `StressState` 1–3 (meaning undocumented) text.
//   • workouts: `/v3/workouts?since&until&limit&offset&filter-by-modification-time` → `{ payload: [ … ] }`, heart rate in
//     `hrdata.workoutAvgHR` / `workoutMaxHR`, `timeOffsetInMinutes` for the local day; `totalDistance` in metres and `totalTime` in
//     seconds (the webhook example: 10 000 m in 3 600 s at avgSpeed 2.78 m/s). A WORKOUT_CREATED webhook carries the same object
//     inline under `workout` — mapped there too.
//   • AvgHRV / HRV stay raw (statistic undocumented — D4); MaxSpo2 is a maximum, not the average 3009 → raw.

const DAY_MS = 86_400_000
/** Inclusive day window → chunks of at most `max` days (Suunto: "Maximum fetch interval duration is 28 days"). */
export function chunkDays(start: string, end: string, max = 28): { start: string; end: string }[] {
  const out: { start: string; end: string }[] = []
  let s = Date.parse(`${start}T00:00:00Z`)
  const stop = Date.parse(`${end}T00:00:00Z`)
  while (s <= stop && out.length < 60) {
    const e = Math.min(s + (max - 1) * DAY_MS, stop)
    out.push({ start: new Date(s).toISOString().slice(0, 10), end: new Date(e).toISOString().slice(0, 10) })
    s = e + DAY_MS
  }
  return out
}

// MARK: - 24/7 sleep

function mapSleep(samples: Sample[]): DailyRow[] {
  const rows: DailyRow[] = []
  for (const s of samples) {
    const e = s.entryData ?? {}
    if (e.IsNap === true) continue                                   // IsNap decides main-sleep eligibility
    const endIso = str(e.BedtimeEnd) ?? str(e.DateTime) ?? s.timestamp
    if (!endIso) continue
    const day = dayOfISO(endIso), timezoneOffset = offsetMinutes(endIso.slice(19))
    const sleepId = str(e.SleepId)
    const prov: Partial<DailyRow> = { timezoneOffset, sourceRecordId: sleepId ?? endIso, sourceResourceType: RES.sleep }
    const base: Record<string, unknown> = {
      sleep_id: sleepId, unit: "seconds",
      avg_hrv_unverified: num(e.AvgHRV), avg_hrv_sample_count: num(e.AvgHRVSampleCount),   // statistic undocumented → raw (D4)
      sleep_quality_score_unverified: num(e.SleepQualityScore),
      wake_before_off_bed_s: num(e.WakeBeforeOffBedDuration), max_spo2_fraction: num(e.MaxSpo2), feeling: num(e.Feeling),
    }
    const deep = num(e.DeepSleepDuration), light = num(e.LightSleepDuration), rem = num(e.REMSleepDuration)
    const asleep = deep == null && light == null && rem == null ? null : (deep ?? 0) + (light ?? 0) + (rem ?? 0)
    const values: [number, number | null][] = [
      [T.MainSleepDuration, asleep], [T.InBed, num(e.Duration)], [T.Deep, deep], [T.Light, light], [T.REM, rem],
      [T.Latency, num(e.SleepOnsetLatencyDuration)], [T.AwakeAfterWakeup, num(e.WakeAfterSleepOnsetDuration)],
      [T.HeartRateSleep, num(e.HRAvg)], [T.HeartRateSleepLowest, num(e.HRMin)],
    ]
    for (const [id, v] of values) {
      if (v == null) continue                                        // absent → skipped, never a zero
      rows.push({ day, dataTypeId: id, dataTypeName: NAMES[id], value: v, valueType: Number.isInteger(v) ? "LONG" : "DOUBLE", details: base, ...prov })
    }
    rows.push(...compact([dailyDate(day, T.SleepStart, str(e.BedtimeStart), { details: base, ...prov }), dailyDate(day, T.SleepEnd, str(e.BedtimeEnd), { details: base, ...prov })]))
  }
  return rows
}

// MARK: - 24/7 recovery

function mapRecovery(samples: Sample[]): RowBatch {
  const epochRows: EpochRow[] = [], latest = new Map<string, { ts: string; bal: number | null; state: string | null; tz: number | null }>()
  for (const s of samples) {
    const e = s.entryData ?? {}, ts = s.timestamp, startTs = ts ? utcISO(ts) : null
    if (!ts || !startTs) continue
    const bal = num(e.Balance), state = str(e.StressState), tz = offsetMinutes(ts.slice(19))
    if (bal == null && state == null) continue
    const details = { balance_scale: "0-1", stress_state_scale_unverified: true, stress_state_raw: e.StressState ?? null }
    const prov: Partial<EpochRow> = { timezoneOffset: tz, sourceRecordId: ts, sourceResourceType: RES.recovery, details }
    epochRows.push(...compact([epoch(startTs, T.SuuntoRecoveryBalance, bal, { ...prov, valueType: "DOUBLE" }), epochText(startTs, T.SuuntoStressState, state, prov)]))
    const day = dayOfISO(ts), cur = latest.get(day)
    if (!cur || Date.parse(ts) >= Date.parse(cur.ts)) latest.set(day, { ts, bal, state, tz })
  }
  const daily: DailyRow[] = []
  for (const [day, l] of latest) {
    const prov: Partial<DailyRow> = { timezoneOffset: l.tz, sourceRecordId: l.ts, sourceResourceType: RES.recovery, details: { balance_scale: "0-1", stress_state_scale_unverified: true, sample_ts: l.ts, statistic: "latest_of_day" } }
    daily.push(...compact([l.bal == null ? null : { day, dataTypeId: T.SuuntoRecoveryBalance, dataTypeName: NAMES[T.SuuntoRecoveryBalance], value: l.bal, valueType: "DOUBLE" as const, ...prov }, dailyText(day, T.SuuntoStressState, l.state, prov)]))
  }
  return { daily, epoch: epochRows }
}

// MARK: - 24/7 activity samples (~10 min: HR bpm, StepCount, EnergyConsumption joules, SpO2 0–1, HRExt, HRV)

function mapActivity(samples: Sample[]): EpochRow[] {
  const rows: EpochRow[] = []
  for (const s of samples) {
    const e = s.entryData ?? {}, ts = s.timestamp, startTs = ts ? utcISO(ts) : null
    if (!ts || !startTs) continue
    const prov: Partial<EpochRow> = { timezoneOffset: offsetMinutes(ts.slice(19)), sourceRecordId: ts, sourceResourceType: RES.activity }
    const ext = (e.HRExt ?? {}) as Record<string, unknown>
    const raw = { hrv_unverified: num(e.HRV), spo2_fraction: num(e.SpO2), energy_consumption_j: num(e.EnergyConsumption), hr_min: num(ext.Min), hr_max: num(ext.Max) }
    rows.push(...compact([
      epoch(startTs, T.HeartRate, num(e.HR), { ...prov, details: raw }),
      epoch(startTs, T.Steps, num(e.StepCount), { ...prov, details: raw }),
    ]))
  }
  return rows
}

// MARK: - Daily statistics (the official `[{ Name, Aggregation, Sources: [{ Samples: [{ TimeISO8601, Value }] }] }]`)

function mapDailyStats(list: unknown): DailyRow[] {
  const perDay = new Map<string, { steps: number | null; energyJ: number | null }>()
  for (const metric of (Array.isArray(list) ? list : []) as Record<string, unknown>[]) {
    const name = String(metric.Name ?? "").toLowerCase()
    if (name !== "stepcount" && name !== "energyconsumption") continue
    for (const src of (Array.isArray(metric.Sources) ? metric.Sources : []) as Record<string, unknown>[]) {
      for (const sm of (Array.isArray(src.Samples) ? src.Samples : []) as Record<string, unknown>[]) {
        const t = str(sm.TimeISO8601), v = num(sm.Value)
        if (!t || v == null) continue
        const day = t.slice(0, 10), cur = perDay.get(day) ?? { steps: null, energyJ: null }
        // Several sources (watches) for one day: keep the largest, never their sum (they overlap in time).
        if (name === "stepcount") cur.steps = Math.max(cur.steps ?? 0, v)
        else cur.energyJ = Math.max(cur.energyJ ?? 0, v)
        perDay.set(day, cur)
      }
    }
  }
  const rows: DailyRow[] = []
  for (const [day, d] of [...perDay].sort(([a], [b]) => a.localeCompare(b))) {
    if (d.steps == null) continue
    rows.push({ day, dataTypeId: T.Steps, dataTypeName: NAMES[T.Steps], value: d.steps, valueType: "LONG", sourceRecordId: `daily_stats:${day}`, sourceResourceType: RES.dailyStats,
      details: { day_basis: "utc", energy_consumption_kcal: d.energyJ == null ? null : Math.round(d.energyJ / 4184) } })
  }
  return rows
}

// MARK: - Workouts (list item, single GET payload and WORKOUT_CREATED webhook share one shape)

function mapWorkout(w: Record<string, unknown>): { day: string; rows: EpochRow[] } | null {
  const startMs = num(w.startTime), key = str(w.workoutKey) ?? str(w.key)
  if (!startMs || !key) return null
  const off = num(w.timeOffsetInMinutes)
  const startTs = new Date(startMs).toISOString(), day = new Date(startMs + (off ?? 0) * 60_000).toISOString().slice(0, 10)
  const totalTime = num(w.totalTime), endTs = totalTime != null ? new Date(startMs + totalTime * 1000).toISOString() : null
  const hr = (w.hrdata ?? {}) as Record<string, unknown>
  const activityId = str(w.activityId)
  const prov: Partial<EpochRow> = { sourceRecordId: key, sourceResourceType: RES.workout, timezoneOffset: off, endTs }
  const raw = { workout_key: key, activity_id: activityId, total_time_s: totalTime, energy_consumption_unverified: num(w.energyConsumption), step_count: num(w.stepCount), total_ascent_m: num(w.totalAscent) }
  return {
    day,
    rows: compact([
      epochText(startTs, T.ActivityType, activityId ? `suunto_activity_${activityId}` : null, { ...prov, details: raw }),
      epoch(startTs, T.CoveredDistance, num(w.totalDistance) || null, { ...prov, details: { ...raw, unit: "m" } }),
      epoch(startTs, T.ElevationGain, num(w.totalAscent) || null, { ...prov, details: { ...raw, unit: "m" } }),
      epoch(startTs, T.HeartRate, num(hr.workoutAvgHR), { ...prov, details: { ...raw, statistic: "workout_average", max_heart_rate: num(hr.workoutMaxHR) } }),
    ]),
  }
}

// MARK: - Webhook event id (no event id is documented → type|username|record)

function recordKey(evt: Record<string, unknown>, samples: Sample[]): string | null {
  const workout = (evt.workout ?? {}) as Record<string, unknown>, route = (evt.route ?? {}) as Record<string, unknown>
  const wk = str(workout.workoutKey) ?? str(route.id) ?? str(evt.workoutKey) ?? str(evt.workoutid)
  if (wk) return wk
  const sleepId = str(samples[0]?.entryData?.SleepId)
  if (sleepId) return sleepId
  const ts = samples.map((s) => s.timestamp).filter((t): t is string => !!t).sort()
  return ts.length ? `${ts[0]}..${ts[ts.length - 1]}` : null
}

export const suunto: VendorAdapter = {
  key: "suunto",
  name: "Suunto",
  pkce: "not_documented",   // suunto.md §6: the public quick-start shows neither PKCE nor `state` — VERIFY in the portal
  scopes: [],               // products/partner agreement gate the data; the token response reports e.g. `scope: "workout"` (§7)
  reconcile: { nightlyDays: 3, weeklyDays: 14 },   // suunto.md §17

  authorizeURL({ clientId, redirectUri, state }) {
    // VERIFY: `state` support (§6 SECURITY BLOCKER) — we always send it; the callback refuses a response without it.
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, redirect_uri: redirectUri, state })}`
  },

  // VERIFIED — suunto.md §7: Basic client auth, form body, JWT access token + refresh_token + expires_in.
  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("suunto")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri }, { basic: { id: clientId, secret: clientSecret } })
    const claims = jwtClaims(String(t.access_token))
    // §9: the `user` claim is the Suunto username (matches webhook `username`); `sub` only as a fallback. Never the email.
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: expiresAt(t), scopes: scopesOf(t), vendorUserId: String(claims.user ?? claims.sub ?? ""), raw: { sub: claims.sub ?? null } }
  },

  // VERIFY — suunto.md §8: the refresh request/body/rotation is NOT DOCUMENTED publicly. Standard RFC 6749
  // refresh_token grant with the same Basic auth is assumed; a rejected refresh surfaces as reconnect_required.
  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("suunto")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken }, { basic: { id: clientId, secret: clientSecret } })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string | undefined) ?? refreshToken, expiresAt: expiresAt(t), scopes: scopesOf(t) }
  },

  // VERIFY — suunto.md §25: the revoke endpoint REQUIRES PORTAL VERIFICATION. Best effort: failures are logged, never thrown
  // (the caller erases tokens locally regardless). The app-level webhook is not removed per user.
  async revoke(tokens, ctx) {
    const { clientId } = vendorClient("suunto")
    try {
      const r = await fetch(`${DEAUTHORIZE}?client_id=${encodeURIComponent(clientId)}`, { headers: { Authorization: `Bearer ${tokens.accessToken}` } })
      if (!r.ok) log("warn", "suunto.deauthorize_failed", { fn: FN, vendor: "suunto", account: ctx.accountId ?? null, status: r.status })
    } catch (e) { log("warn", "suunto.deauthorize_failed", { fn: FN, vendor: "suunto", account: ctx.accountId ?? null, ...errorSummary(e) }) }
  },

  // VERIFIED — security/webhook-verification.md "Suunto" + 20_WEBHOOK: HMAC-SHA256 over the exact body with the
  // notification secret, LOWERCASE HEX in `X-HMAC-SHA256-Signature`, rejected before any JSON parse. No base64, no
  // case folding. Secret: `SUUNTO_WEBHOOK_SECRET` (D10 secret table; the corpus calls it the "notification secret").
  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    const secret = env("SUUNTO_WEBHOOK_SECRET")
    const sig = req.headers.get("X-HMAC-SHA256-Signature") ?? ""
    if (!/^[0-9a-f]{64}$/.test(sig)) throw new Error("suunto signature missing or not lowercase hex")
    if (!timingSafeEqual(await hmacSha256(secret, rawBody, "hex"), sig)) throw new Error("suunto signature mismatch")
    const evt = JSON.parse(rawBody) as Record<string, unknown>
    const user = str(evt.username)
    if (!user) return []
    const type = String(evt.type ?? ""), samples = Array.isArray(evt.samples) ? evt.samples as Sample[] : []
    // VERIFY: the public payload names no event id → triple type|username|record (workoutKey / SleepId / sample span); null → body hash.
    const key = recordKey(evt, samples)
    const ev: WebhookEvent = { vendorUserId: user, kind: type, eventId: key ? `${type}|${user}|${key}` : null }
    const days = samples.map((s) => s.timestamp).filter((t): t is string => !!t).map((t) => dayOfISO(t)).sort()
    if (days.length) { ev.windowStart = days[0]; ev.windowEnd = days[days.length - 1] }
    // Signed payloads carry the data inline (24/7 samples; the workout summary under `workout`) — mapped here.
    if (type === "SUUNTO_247_SLEEP_CREATED") ev.rows = { daily: mapSleep(samples), epoch: [] }
    else if (type === "SUUNTO_247_RECOVERY_CREATED") ev.rows = mapRecovery(samples)
    else if (type === "SUUNTO_247_ACTIVITY_CREATED") ev.rows = { daily: [], epoch: mapActivity(samples) }
    else if (type === "WORKOUT_CREATED" && evt.workout && typeof evt.workout === "object") {
      const w = mapWorkout(evt.workout as Record<string, unknown>)
      if (w) { ev.rows = { daily: [], epoch: w.rows }; ev.windowStart = w.day; ev.windowEnd = w.day }
    }
    return [ev]
  },

  // Pull endpoints and limits from the APIZone reference (2026-11-06 — see the block above `mapSleep`). Each path is optional
  // for one sync: a 4xx is logged and skipped; 401 / 429 / 5xx (incl. 503 "Service capacity exceeded") propagate so the core
  // refresh, backoff and retry paths run.
  async fetchRange(tokens, start, end, ctx) {
    const h = headers(tokens)
    const get = async (path: string): Promise<unknown> => {
      try { return await getJSON(`${API}${path}`, h) }
      catch (e) {
        if (e instanceof UnauthorizedError || e instanceof RateLimitedError || (e instanceof VendorHttpError && e.status >= 500)) throw e
        log("warn", "suunto.pull_failed", { fn: FN, vendor: "suunto", account: ctx.accountId ?? null, path: path.split("?")[0], ...errorSummary(e) })
        return null
      }
    }
    const asList = (j: unknown): Sample[] => Array.isArray(j) ? j as Sample[] : Array.isArray((j as Record<string, unknown>)?.payload) ? (j as Record<string, unknown>).payload as Sample[] : []

    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    for (const c of chunkDays(start, end, 28)) {
      const from = Date.parse(`${c.start}T00:00:00Z`), to = Date.parse(`${c.end}T23:59:59.999Z`)
      dailyRows.push(...mapSleep(asList(await get(`/247samples/sleep?from=${from}&to=${to}`))))
      const rec = mapRecovery(asList(await get(`/247samples/recovery?from=${from}&to=${to}`)))
      dailyRows.push(...rec.daily); epochRows.push(...rec.epoch)
      epochRows.push(...mapActivity(asList(await get(`/247samples/activity?from=${from}&to=${to}`))))
      dailyRows.push(...mapDailyStats(await get(`/247samples/daily-activity-statistics?startdate=${c.start}T00:00:00&enddate=${c.end}T23:59:59`)))
    }

    // Workouts by START time (filter-by-modification-time=false), every page.
    const since = Date.parse(`${start}T00:00:00Z`) - DAY_MS, until = Date.parse(`${end}T00:00:00Z`) + 2 * DAY_MS, limit = 50
    for (let offset = 0, page = 0; page < 20; page++, offset += limit) {
      const list = asList(await get(`/v3/workouts?since=${since}&until=${until}&limit=${limit}&offset=${offset}&filter-by-modification-time=false`)) as unknown as Record<string, unknown>[]
      for (const w of list) { const m = mapWorkout(w); if (m && m.day >= start && m.day <= end) epochRows.push(...m.rows) }
      if (list.length < limit) break
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}

export const _suuntoTest = { mapSleep, mapRecovery, mapActivity, mapDailyStats, mapWorkout, jwtClaims, recordKey, chunkDays }
