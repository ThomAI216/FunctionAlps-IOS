// Suunto Cloud API — Phase 2 correction (strategy 2026-09-14; decisions D4 secrets, D10 secret table).
// Authority: .context/research/2026-09-14_wearables-implementation/vendors/suunto.md (+ metrics/*, security/*),
// implementation pack 07_HRV / 08_SLEEP / 13_STRESS / 14_RECOVERY / 20_WEBHOOK. Status per the corpus:
//   VERIFIED (public quick-start / webhook page): authorize + token endpoints with Basic client auth, JWT
//     access token whose `user` claim is the Suunto username (also `username` in webhooks), `expires_in`,
//     `Ocp-Apim-Subscription-Key` on every data call, webhook header `X-HMAC-SHA256-Signature` = HMAC-SHA256
//     over the exact body, LOWERCASE HEX, event types WORKOUT_CREATED / ROUTE_CREATED / SUUNTO_247_*_CREATED,
//     the 24/7 sleep field names (08_SLEEP.md "Suunto").
//   VERIFY (partner portal / partner schema): PKCE + `state` support (§6), the refresh contract (§8), the
//     deauthorize endpoint (§25), every pull endpoint, pagination and the ms-epoch window (§12/§13/§21),
//     duration units (§19), `AvgHRV` semantics (§20), Balance/StressState scales (§18).
// Rules applied here: unverified endpoints stay callable but tolerant (absent fields are skipped, never
// written as zeros); durations are stored RAW with `details.unit_unverified`; `AvgHRV` / `HRV` are NEVER
// written to 3100/3106/3112/3113 — they live in `details.avg_hrv_unverified` / `details.hrv_unverified`;
// recovery Balance → 1000134 as text (no numeric scale in the corpus), StressState → 1000135 as a STRING
// row (never coerced to a number, never 1000109); every row carries sourceRecordId/sourceResourceType.
import { type DailyRow, type EpochRow, NAMES, RateLimitedError, type RowBatch, type TokenSet, UnauthorizedError, type VendorAdapter, type WebhookEvent, T, compact, dailyDate, dailyText, dayOfISO, env, epoch, getJSON, hmacSha256, num, offsetMinutes, timingSafeEqual, tokenPost, unixOf, vendorClient } from "./core.ts"
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

// MARK: - 24/7 sleep (field names VERIFIED on the public webhook page; units VERIFY — suunto.md §19)

function mapSleep(samples: Sample[]): DailyRow[] {
  const rows: DailyRow[] = []
  for (const s of samples) {
    const e = s.entryData ?? {}
    if (e.IsNap === true) continue                                   // 08_SLEEP: IsNap decides main-sleep eligibility
    const endIso = str(e.BedtimeEnd) ?? str(e.DateTime) ?? s.timestamp
    if (!endIso) continue
    const day = dayOfISO(endIso), timezoneOffset = offsetMinutes(endIso.slice(19))
    const sleepId = str(e.SleepId)
    const prov: Partial<DailyRow> = { timezoneOffset, sourceRecordId: sleepId ?? endIso, sourceResourceType: RES.sleep }
    // Raw-only vendor fields ride along in `details` on every row of the night (07_HRV: no 3100/3106/3112/3113 for AvgHRV;
    // canonical-metric-map: SleepQualityScore UNVERIFIED scale → no 2201/1000105 until pinned).
    const base: Record<string, unknown> = {
      sleep_id: sleepId,
      avg_hrv_unverified: num(e.AvgHRV),                             // VERIFY: statistic (RMSSD? SDNN?), window, unit — suunto.md §20
      avg_hrv_sample_count: num(e.AvgHRVSampleCount),
      sleep_quality_score_unverified: num(e.SleepQualityScore),      // VERIFY: 0–100? — suunto.md §22
    }
    // VERIFY: duration unit (seconds? minutes?) — stored raw, never converted (suunto.md §19 "do not infer seconds from magnitudes").
    const durations: [number, unknown][] = [
      [T.MainSleepDuration, e.Duration], [T.Deep, e.DeepSleepDuration], [T.Light, e.LightSleepDuration], [T.REM, e.REMSleepDuration],
      [T.Latency, e.SleepOnsetLatencyDuration], [T.Awake, e.WakeAfterSleepOnsetDuration], [T.AwakeAfterWakeup, e.WakeBeforeOffBedDuration],
    ]
    for (const [id, raw] of durations) {
      const v = num(raw)
      if (v == null) continue                                        // absent → skipped, never a zero
      rows.push({ day, dataTypeId: id, dataTypeName: NAMES[id], value: v, valueType: Number.isInteger(v) ? "LONG" : "DOUBLE", details: { ...base, unit_unverified: true }, ...prov })
    }
    // bpm is unambiguous for HRAvg / HRMin (VERIFY that HRMin is the sleep minimum, not resting HR — no 3001 proxy is written).
    for (const [id, raw] of [[T.HeartRateSleep, e.HRAvg], [T.HeartRateSleepLowest, e.HRMin]] as [number, unknown][]) {
      const v = num(raw)
      if (v == null) continue
      rows.push({ day, dataTypeId: id, dataTypeName: NAMES[id], value: v, valueType: Number.isInteger(v) ? "LONG" : "DOUBLE", details: base, ...prov })
    }
    // Bedtime instants are ISO with offsets (suunto.md §21) — the only fully verified unit in the payload.
    rows.push(...compact([dailyDate(day, T.SleepStart, str(e.BedtimeStart), { details: base, ...prov }), dailyDate(day, T.SleepEnd, str(e.BedtimeEnd), { details: base, ...prov })]))
  }
  return rows
}

// MARK: - 24/7 recovery (Balance / StressState VERIFIED as field names; scales VERIFY — suunto.md §18, 13_STRESS, 14_RECOVERY)

function mapRecovery(samples: Sample[]): RowBatch {
  const epochRows: EpochRow[] = [], latest = new Map<string, { ts: string; bal: string | null; state: string | null; tz: number | null }>()
  for (const s of samples) {
    const e = s.entryData ?? {}, ts = s.timestamp, startTs = ts ? utcISO(ts) : null
    if (!ts || !startTs) continue
    const bal = str(e.Balance), state = str(e.StressState), tz = offsetMinutes(ts.slice(19))
    if (bal == null && state == null) continue
    const details = { balance_scale_unverified: true, stress_state_scale_unverified: true, balance_raw: e.Balance ?? null, stress_state_raw: e.StressState ?? null }
    const prov: Partial<EpochRow> = { timezoneOffset: tz, sourceRecordId: ts, sourceResourceType: RES.recovery, details }
    // VERIFY: Balance has no documented numeric scale → text until pinned (catalogue declares 1000134 DOUBLE for the day it is).
    epochRows.push(...compact([epochText(startTs, T.SuuntoRecoveryBalance, bal, prov), epochText(startTs, T.SuuntoStressState, state, prov)]))
    const day = dayOfISO(ts), cur = latest.get(day)
    if (!cur || Date.parse(ts) >= Date.parse(cur.ts)) latest.set(day, { ts, bal, state, tz })
  }
  const daily: DailyRow[] = []
  for (const [day, l] of latest) {
    const prov: Partial<DailyRow> = { timezoneOffset: l.tz, sourceRecordId: l.ts, sourceResourceType: RES.recovery, details: { balance_scale_unverified: true, stress_state_scale_unverified: true, sample_ts: l.ts } }
    daily.push(...compact([dailyText(day, T.SuuntoRecoveryBalance, l.bal, prov), dailyText(day, T.SuuntoStressState, l.state, prov)]))
  }
  return { daily, epoch: epochRows }
}

// MARK: - 24/7 activity samples (VERIFY: field names are not in the public corpus — partner schema)

function mapActivity(samples: Sample[]): EpochRow[] {
  const rows: EpochRow[] = []
  for (const s of samples) {
    const e = s.entryData ?? {}, ts = s.timestamp, startTs = ts ? utcISO(ts) : null
    if (!ts || !startTs) continue
    const prov: Partial<EpochRow> = { timezoneOffset: offsetMinutes(ts.slice(19)), sourceRecordId: ts, sourceResourceType: RES.activity }
    // Raw-only: HRV (07_HRV — never 3100), SpO2 (fraction vs percent VERIFY), EnergyConsumption (unit VERIFY).
    const raw = { hrv_unverified: num(e.HRV), spo2_unverified: num(e.SpO2), energy_consumption_unverified: num(e.EnergyConsumption) }
    rows.push(...compact([
      epoch(startTs, T.HeartRate, num(e.HR), { ...prov, details: raw }),         // bpm — VERIFY field name `HR`
      epoch(startTs, T.Steps, num(e.StepCount), { ...prov, details: raw }),      // count — VERIFY field name `StepCount`
    ]))
  }
  return rows
}

// MARK: - Webhook event id (the public payload names no event id → VERIFY triple type|username|record)

function recordKey(evt: Record<string, unknown>, samples: Sample[]): string | null {
  const wk = str(evt.workoutKey) ?? str(evt.workoutid) ?? str(evt.workoutId) ?? str(evt.routeKey) ?? str(evt.routeid)
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
    // 24/7 payloads carry the samples inline (§10, §16) — mapped here; the queued pull re-reads the window when the portal exposes it.
    if (type === "SUUNTO_247_SLEEP_CREATED") ev.rows = { daily: mapSleep(samples), epoch: [] }
    else if (type === "SUUNTO_247_RECOVERY_CREATED") ev.rows = mapRecovery(samples)
    else if (type === "SUUNTO_247_ACTIVITY_CREATED") ev.rows = { daily: [], epoch: mapActivity(samples) }
    // WORKOUT_CREATED / ROUTE_CREATED: pointer only — the queued pull fetches the workout.
    return [ev]
  },

  // VERIFY — suunto.md §12/§13: the exact pull endpoints, pagination and history limits come from the approved API Zone
  // reference. Every path below is the pre-approval assumption: kept callable, each one optional (a 4xx/5xx on one path
  // is logged and skipped), 401/429 propagate so the core refresh / backoff paths run. Window = ms epoch (§21, VERIFY).
  async fetchRange(tokens, start, end, ctx) {
    const from = unixOf(`${start}T00:00:00Z`) * 1000, to = unixOf(`${end}T23:59:59Z`) * 1000
    const h = headers(tokens)
    const get = async (path: string): Promise<unknown> => {
      try { return await getJSON(`${API}${path}`, h) }
      catch (e) {
        if (e instanceof UnauthorizedError || e instanceof RateLimitedError) throw e
        log("warn", "suunto.pull_failed", { fn: FN, vendor: "suunto", account: ctx.accountId ?? null, path: path.split("?")[0], ...errorSummary(e) })
        return null
      }
    }
    const asList = (j: unknown): Sample[] => Array.isArray(j) ? j as Sample[] : Array.isArray((j as Record<string, unknown>)?.payload) ? (j as Record<string, unknown>).payload as Sample[] : []

    const sleep = asList(await get(`/247samples/sleep?from=${from}&to=${to}`))          // VERIFY: path + response envelope
    const recovery = mapRecovery(asList(await get(`/247samples/recovery?from=${from}&to=${to}`)))  // VERIFY: path + response envelope
    const act = asList(await get(`/247samples/activity?from=${from}&to=${to}`))         // VERIFY: path + response envelope
    const dailyRows: DailyRow[] = [...mapSleep(sleep), ...recovery.daily], epochRows: EpochRow[] = [...recovery.epoch, ...mapActivity(act)]

    // VERIFY: daily activity statistics — path, field names (`stepcount` / `energyconsumption`) and energy unit.
    for (const d of asList(await get(`/247/daily-activity-statistics?from=${from}&to=${to}`)) as Record<string, unknown>[]) {
      const ts = str(d.timestamp) ?? str(d.date)
      if (!ts) continue
      const day = dayOfISO(ts), steps = num(d.stepcount ?? d.StepCount)
      if (steps == null) continue
      dailyRows.push({ day, dataTypeId: T.Steps, dataTypeName: NAMES[T.Steps], value: steps, valueType: "LONG", timezoneOffset: offsetMinutes(ts.slice(19)), sourceRecordId: day, sourceResourceType: RES.dailyStats, details: { energy_consumption_unverified: num(d.energyconsumption ?? d.EnergyConsumption) } })
    }

    // VERIFY: workouts — path `/v3/workouts?since=<ms>&limit=`, pagination, `startTime` (ms epoch in known examples, §21),
    // `totalTime` / `totalDistance` / `energyConsumption` units, HR field name. Durations/distance stored raw + unit_unverified.
    for (const w of asList(await get(`/v3/workouts?since=${from}&limit=100`)) as Record<string, unknown>[]) {
      const startMs = num(w.startTime), key = str(w.workoutKey)
      if (!startMs || !key) continue
      const startTs = new Date(startMs).toISOString()
      if (startTs.slice(0, 10) < start || startTs.slice(0, 10) > end) continue
      const prov: Partial<EpochRow> = { sourceRecordId: key, sourceResourceType: RES.workout }
      const activityId = str(w.activityId), raw = { workout_key: key, activity_id: activityId, total_time_unverified: num(w.totalTime), energy_consumption_unverified: num(w.energyConsumption) }
      const distance = num(w.totalDistance), avgHr = num(w.avgHR ?? w.hrAvg)
      epochRows.push(...compact([
        epochText(startTs, T.ActivityType, activityId ? `suunto_activity_${activityId}` : null, { ...prov, details: raw }),
        distance != null ? { startTs, dataTypeId: T.CoveredDistance, dataTypeName: NAMES[T.CoveredDistance], value: distance, valueType: Number.isInteger(distance) ? "LONG" : "DOUBLE", ...prov, details: { ...raw, unit_unverified: true } } as EpochRow : null,
        epoch(startTs, T.HeartRate, avgHr, { ...prov, details: { ...raw, statistic: "workout_average" } }),
      ]))
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}

export const _suuntoTest = { mapSleep, mapRecovery, mapActivity, jwtClaims, recordKey }
