// Garmin Connect Developer Program — Health API (+ Activity / Women's Health summaries), rebuilt 2026-11-06 now that the
// owner holds an approved developer account. Replaces the 2026-09-14 portal stub (D6). Status stays `planned` until one
// real connection has synced rows under 1000002.
//
// What is pinned, and where it comes from
//   • OAuth 2.0 with PKCE (S256, REQUIRED) — Garmin's own "OAuth2 PKCE" specification (developerportal.garmin.com, June
//     2025): authorize `GET https://connect.garmin.com/oauth2Confirm` (response_type, client_id, code_challenge,
//     code_challenge_method=S256, redirect_uri, state); token `POST https://connectapi.garmin.com/di-oauth2-service/oauth/token`
//     (form body with client_id + client_secret + code + code_verifier + redirect_uri); refresh on the same URL — "we return a
//     new refresh token every time" (the core adopts it). The spec's sample says `expires_in: 86400` and
//     `refresh_token_expires_in` ≈ 90 days while its prose says three months: we honour `expires_in` and refresh 600 s early
//     as Garmin recommends. Scope is fixed by Garmin; what a member shares is chosen on the consent page (permissions).
//   • Identity `GET /wellness-api/rest/user/id`; permissions `GET /user/permissions` (HEALTH_EXPORT, ACTIVITY_EXPORT,
//     MCT_EXPORT…); disconnect `DELETE /user/registration` — which Garmin says MUST be called when the app offers its own
//     disconnect (ours does: `wearable-vendor-disconnect` → `revoke`).
//   • Delivery tiers (developer.garmin.com/gc-developer-program, 2026): **Starter = PUSH only, no historical backfill**;
//     Enterprise = Push or Ping/Pull + backfill. So PUSH is the default here: the summaries arrive inline in the webhook and
//     are persisted from it. `GARMIN_PULL_ENABLED=1` (Enterprise only) turns on the upload-time pulls in `fetchRange`; without
//     it `fetchRange` returns nothing and the nightly reconcile only keeps the tokens fresh. Backfill is requested after
//     connect on every tier and simply refused on Starter.
//   • Webhook authentication: Garmin documents NO signature, and a `garmin-client-id` header is not a secret (it is never
//     used here — 20_WEBHOOK_SYNC_SECURITY.md). The URL registered in the portal carries our own secret,
//     `…/wearable-vendor-webhook/garmin?token=<GARMIN_WEBHOOK_TOKEN>`, compared in constant time; unset → every POST is
//     refused (fail closed). On top: a push only lands on a `vendor_user_id` we already hold (the webhook function drops
//     unknown users), every write is an idempotent upsert on natural keys, and a PING callback URL is never fetched — only
//     its upload window is read, and only from `https://apis.garmin.com/wellness-api/rest/…`.
//
// What is NOT pinned (portal-gated Health API / Push spec PDFs — the owner can download them now): the summary FIELD NAMES
// and units below are carried over from the retired v1 mapper (`_retired/wearables-garmin-v1-2026-09-04.ts`) and marked
// VERIFY. Every push body is stored verbatim in `wearable_raw_events` (`vendor_webhook`) before mapping, so a wrong field
// name is corrected from the stored payload and re-mapped — never guessed twice. HRV follows decision D4: until the spec's
// definition of `lastNightAvg` is read (RMSSD over the sleep window?), it is NOT written to an HRV id
// (`HRV_RMSSD_CONFIRMED`); the values stay in the raw push.
//
// Terms the product must honour before `available` (Garmin API Brand Guidelines v6.30.2025): the connect card uses the
// official "Garmin Connect™" tile, and every view showing Garmin data carries "Garmin [device model]" (or "Garmin").
// `sourceDeviceId` carries the device name when the summary has one. AI: `ai-policy.ts` keeps Garmin denied.
import {
  type AccountContext, type DailyRow, type EpochRow, type RowBatch, type TokenSet, type VendorAdapter, type WebhookEvent,
  T, RateLimitedError, UnauthorizedError, VendorHttpError, compact, daily, dailyDate, dailyMap, epoch, getJSON, localDay, mean, num, timingSafeEqual, tokenPost, unixOf, vendorClient, addDays,
} from "./core.ts"
import { log } from "./log.ts"

const FN = "garmin"
export const GARMIN_AUTH = "https://connect.garmin.com/oauth2Confirm"
export const GARMIN_TOKEN = "https://connectapi.garmin.com/di-oauth2-service/oauth/token"
export const GARMIN_API = "https://apis.garmin.com/wellness-api/rest"
/** Garmin: "refresh at least 600 seconds before expiry". */
const REFRESH_MARGIN_S = 600
/** Summary types pulled in Ping/Pull mode (Enterprise) and requested as backfill after connect. VERIFY names in the spec. */
export const PULL_TYPES = ["dailies", "sleeps", "hrv", "stressDetails", "bodyComps", "userMetrics", "skinTemp", "bloodPressures", "activities", "mct"]
/** One backfill request per type covers this many days (the documented per-request maximum is portal-gated; 30 is safe). */
const BACKFILL_DAYS = 30
/** D4: flip to true only after the Health API spec confirms `lastNightAvg` / `hrvValues` are RMSSD (ms) over the sleep window. */
export const HRV_RMSSD_CONFIRMED = false

type Rec = Record<string, unknown>
const str = (v: unknown): string | null => (v == null || v === "" ? null : String(v))
const isoOf = (s: unknown): string | null => { const v = num(s); return v == null ? null : new Date(v * 1000).toISOString() }
const minutes = (s: unknown): number | null => { const v = num(s); return v == null || v <= 0 ? null : Math.round(v / 60) }
const kg = (g: unknown): number | null => { const v = num(g); return v == null ? null : Math.round(v) / 1000 }
const round = (v: number | null, digits = 0) => (v == null ? null : Math.round(v * 10 ** digits) / 10 ** digits)
const nonNegative = (v: number | null) => (v == null || v < 0 ? null : v)   // Garmin uses negative sentinels (-1, -2) for "no data"

/** The member-local day of a summary: Garmin's `calendarDate` when present, else start + offset. */
export function summaryDay(it: Rec): string {
  const cd = str(it.calendarDate)
  if (cd && /^\d{4}-\d{2}-\d{2}$/.test(cd)) return cd
  const start = num(it.startTimeInSeconds) ?? num(it.measurementTimeInSeconds) ?? 0
  const off = num(it.startTimeOffsetInSeconds) ?? num(it.measurementTimeOffsetInSeconds) ?? 0
  return localDay(new Date(start * 1000), off / 60)
}

/** One summary (pushed or pulled) → catalogue rows. `type` is the summary-type key of the push body. Pure. */
export function mapSummary(type: string, it: Rec, opts: { hrvConfirmed?: boolean } = {}): RowBatch {
  const d: DailyRow[] = [], e: EpochRow[] = []
  const day = summaryDay(it)
  const offS = num(it.startTimeOffsetInSeconds) ?? num(it.measurementTimeOffsetInSeconds)
  const prov = { timezoneOffset: offS == null ? null : Math.round(offS / 60), sourceRecordId: str(it.summaryId), sourceResourceType: type, sourceDeviceId: str(it.deviceName) }
  const at = isoOf(it.measurementTimeInSeconds) ?? isoOf(it.startTimeInSeconds)
  switch (type) {
    case "dailies": {
      const active = num(it.activeKilocalories), bmr = num(it.bmrKilocalories)
      d.push(...dailyMap(day, {
        [T.Steps]: num(it.steps), [T.CoveredDistance]: num(it.distanceInMeters), [T.FloorsClimbed]: num(it.floorsClimbed),
        [T.ActiveBurnedCalories]: round(active), [T.BurnedCalories]: active != null && bmr != null ? Math.round(active + bmr) : null,
        [T.ActivityDuration]: minutes(it.activeTimeInSeconds),
        [T.ActivityMid]: minutes(it.moderateIntensityDurationInSeconds), [T.ActivityHigh]: minutes(it.vigorousIntensityDurationInSeconds),
        [T.HeartRateResting]: num(it.restingHeartRateInBeatsPerMinute), [T.HeartRate]: num(it.averageHeartRateInBeatsPerMinute),
        [T.AverageStress]: nonNegative(num(it.averageStressLevel)),
        [T.HighStress]: minutes(it.highStressDurationInSeconds), [T.MediumStress]: minutes(it.mediumStressDurationInSeconds), [T.LowStress]: minutes(it.lowStressDurationInSeconds),
      }, { ...prov, details: { body_battery_charged: num(it.bodyBatteryChargedValue), body_battery_drained: num(it.bodyBatteryDrainedValue), max_stress: nonNegative(num(it.maxStressLevel)) } }))
      break
    }
    case "sleeps": {
      // VERIFY: `durationInSeconds` read as time asleep (stages sum to it), awake reported separately.
      const dur = num(it.durationInSeconds), awake = num(it.awakeDurationInSeconds) ?? 0, start = num(it.startTimeInSeconds)
      const levels = (it.sleepLevelsMap ?? {}) as Record<string, { startTimeInSeconds: number; endTimeInSeconds: number }[]>
      const score = num((it.overallSleepScore as Rec | undefined)?.value)
      const P = { ...prov, details: { validation: str(it.validation), naps_s: num(it.totalNapDurationInSeconds), unmeasurable_s: num(it.unmeasurableSleepInSeconds) } }
      d.push(...dailyMap(day, {
        [T.MainSleepDuration]: dur || null, [T.InBed]: dur != null ? dur + awake : null,
        [T.Deep]: num(it.deepSleepDurationInSeconds), [T.Light]: num(it.lightSleepDurationInSeconds), [T.REM]: num(it.remSleepInSeconds), [T.Awake]: num(it.awakeDurationInSeconds),
        [T.Interruptions]: Array.isArray(levels.awake) ? levels.awake.length : null, [T.SleepScore]: score,
        [T.RespirationRateSleep]: round(mean(Object.values((it.timeOffsetSleepRespiration ?? {}) as Rec).map(num)), 1),
        [T.SPO2]: round(mean(Object.values((it.timeOffsetSleepSpo2 ?? {}) as Rec).map(num)), 1),
      }, P))
      if (start != null && dur != null) {
        d.push(...compact([dailyDate(day, T.SleepStart, new Date(start * 1000).toISOString(), prov), dailyDate(day, T.SleepEnd, new Date((start + dur + awake) * 1000).toISOString(), prov)]))
      }
      // Hypnogram as stage epochs (value = minutes in the segment), the same shape the Oura adapter writes.
      const stage: Record<string, number> = { deep: T.SleepDeepBinary, light: T.SleepLightBinary, rem: T.SleepREMBinary, awake: T.SleepAwakeBinary }
      for (const [k, id] of Object.entries(stage)) {
        for (const r of Array.isArray(levels[k]) ? levels[k] : []) {
          const s = num(r.startTimeInSeconds), en = num(r.endTimeInSeconds)
          if (s == null || en == null || en <= s) continue
          const row = epoch(new Date(s * 1000).toISOString(), id, Math.round((en - s) / 60), { ...prov, endTs: new Date(en * 1000).toISOString() })
          if (row) e.push(row)
        }
      }
      break
    }
    case "hrv": {
      // D4: written only once the definition is confirmed (see the header); otherwise the raw push is the record.
      if (!opts.hrvConfirmed) break
      d.push(...dailyMap(day, { [T.RmssdSleep]: num(it.lastNightAvg), [T.RmssdSleepHighest]: num(it.lastNight5MinHigh) }, { ...prov, details: { statistic: "rmssd", window: "night", source_field: "lastNightAvg" } }))
      const base = num(it.startTimeInSeconds) ?? 0
      for (const [offS, v] of Object.entries((it.hrvValues ?? {}) as Rec)) {
        const row = epoch(new Date((base + Number(offS)) * 1000).toISOString(), T.Rmssd, num(v), { ...prov, details: { statistic: "rmssd", window: "5min" } })
        if (row) e.push(row)
      }
      break
    }
    case "stressDetails": {
      const bb = Object.values((it.timeOffsetBodyBatteryValues ?? {}) as Rec).map(num).filter((x): x is number => x != null && x >= 0)
      if (bb.length) d.push(...compact([daily(day, T.BodyBattery, Math.max(...bb), { ...prov, details: { statistic: "day_high", day_low: Math.min(...bb), samples: bb.length } })]))
      break
    }
    case "bodyComps": {
      d.push(...dailyMap(day, {
        [T.Weight]: kg(it.weightInGrams), [T.FatRatio]: num(it.bodyFatInPercent), [T.BMI]: num(it.bodyMassIndex),
        [T.MuscleMass]: kg(it.muscleMassInGrams), [T.BoneMass]: kg(it.boneMassInGrams),
      }, { ...prov, details: { body_water_pct: num(it.bodyWaterInPercent), measured_at: at } }))
      break
    }
    case "skinTemp":
      d.push(...dailyMap(day, { [T.SkinTemperatureDeviation]: num(it.avgDeviationCelsius) }, { ...prov, details: { statistic: "deviation_from_baseline_c" } }))
      break
    case "bloodPressures": {
      if (!at) break
      const X = { ...prov, details: { source: str(it.sourceType) } }
      e.push(...compact([epoch(at, T.SystolicBP, num(it.systolic), X), epoch(at, T.DiastolicBP, num(it.diastolic), X)]))
      d.push(...dailyMap(day, { [T.SystolicBP]: num(it.systolic), [T.DiastolicBP]: num(it.diastolic) }, X))
      break
    }
    case "userMetrics":
      d.push(...dailyMap(day, { [T.VO2max]: num(it.vo2Max) }, { ...prov, details: { fitness_age: num(it.fitnessAge), vo2max_cycling: num(it.vo2MaxCycling) } }))
      break
    case "activities": {
      const s = num(it.startTimeInSeconds), durS = num(it.durationInSeconds)
      if (s == null) break
      const startTs = new Date(s * 1000).toISOString(), endTs = durS != null ? new Date((s + durS) * 1000).toISOString() : null
      const A = { ...prov, sourceRecordId: str(it.summaryId) ?? str(it.activityId), endTs }
      // The activity's title stays in the raw push: it can be personal and nothing reads it.
      e.push(...compact([
        epoch(startTs, T.ActivityType, 0, { ...A, valueText: str(it.activityType) ?? "", valueType: "STRING", details: { activity_type: str(it.activityType), duration_min: durS != null ? Math.round(durS / 6) / 10 : null, manual: it.manual === true } }),
        epoch(startTs, T.ActiveBurnedCalories, round(num(it.activeKilocalories)), { ...A, details: { workout: true } }),
        epoch(startTs, T.CoveredDistance, num(it.distanceInMeters) || null, { ...A, details: { workout: true } }),
        epoch(startTs, T.HeartRate, num(it.averageHeartRateInBeatsPerMinute), { ...A, details: { workout: true, statistic: "average", max_heart_rate: num(it.maxHeartRateInBeatsPerMinute) } }),
        epoch(startTs, T.ElevationGain, num(it.totalElevationGainInMeters) || null, { ...A, details: { workout: true } }),
      ]))
      break
    }
    case "mct":
      d.push(...dailyMap(day, { [T.MenstrualCycleDay]: num(it.dayInCycle) }, { ...prov, details: { phase: str(it.currentPhaseType), cycle_length: num(it.cycleLength) } }))
      break
    default:
      // epochs, pulseox, allDayRespiration, … : not mapped (kept verbatim in the raw push). Don't subscribe to them.
      break
  }
  return { daily: d, epoch: e }
}

/** The upload window of a PING callback URL — only when it is Garmin's own API host and path (never fetched). */
export function pingWindow(callbackURL: unknown): { start: string; end: string } | null {
  let u: URL
  try { u = new URL(String(callbackURL ?? "")) } catch { return null }
  if (u.protocol !== "https:" || u.host !== "apis.garmin.com" || !u.pathname.startsWith("/wellness-api/rest/")) return null
  const s = num(u.searchParams.get("uploadStartTimeInSeconds")), en = num(u.searchParams.get("uploadEndTimeInSeconds"))
  if (s == null || en == null || en < s) return null
  return { start: new Date(s * 1000).toISOString().slice(0, 10), end: new Date(en * 1000).toISOString().slice(0, 10) }
}

/** Constant-time check of the `?token=` our portal URL carries. Throws (→ 401) when unset or wrong. */
function assertWebhookToken(url: URL): void {
  const expected = Deno.env.get("GARMIN_WEBHOOK_TOKEN")
  if (!expected) throw new Error("garmin webhook token unset")
  const given = url.searchParams.get("token") ?? ""
  if (!timingSafeEqual(given, expected)) throw new Error("garmin webhook token mismatch")
}

export const garmin: VendorAdapter = {
  key: "garmin",
  name: "Garmin",
  pkce: "required",
  scopes: [],               // fixed by Garmin; the member grants permissions (HEALTH_EXPORT, ACTIVITY_EXPORT, MCT_EXPORT) on the consent page
  reconcile: { nightlyDays: 3, weeklyDays: 14 },

  authorizeURL({ clientId, redirectUri, state, codeChallenge }) {
    if (!codeChallenge) throw new Error("garmin requires PKCE (S256)")
    return `${GARMIN_AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, code_challenge: codeChallenge, code_challenge_method: "S256", redirect_uri: redirectUri, state })}`
  },

  async exchangeCode({ code, redirectUri, codeVerifier }) {
    if (!codeVerifier) throw new Error("garmin requires the PKCE verifier")
    const { clientId, clientSecret } = vendorClient("garmin")
    const t = await tokenPost(GARMIN_TOKEN, { grant_type: "authorization_code", client_id: clientId, client_secret: clientSecret, code, code_verifier: codeVerifier, redirect_uri: redirectUri })
    const me = await getJSON(`${GARMIN_API}/user/id`, { Authorization: `Bearer ${t.access_token}` })
    return {
      accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined,
      expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 86_400) - REFRESH_MARGIN_S,
      scopes: String(t.scope ?? "").split(" ").filter(Boolean), vendorUserId: str(me.userId) ?? undefined,
    }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("garmin")
    const t = await tokenPost(GARMIN_TOKEN, { grant_type: "refresh_token", client_id: clientId, client_secret: clientSecret, refresh_token: refreshToken })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string | undefined) ?? refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 86_400) - REFRESH_MARGIN_S }
  },

  async revoke(tokens) {
    // Garmin: MUST be called when the partner app offers its own disconnect. 204 expected; a 401 means it is already gone.
    const r = await fetch(`${GARMIN_API}/user/registration`, { method: "DELETE", headers: { Authorization: `Bearer ${tokens.accessToken}` } })
    if (!r.ok && r.status !== 401 && r.status !== 404) throw new VendorHttpError(r.status, "garmin delete registration")
  },

  async afterConnect(tokens) {
    const h = { Authorization: `Bearer ${tokens.accessToken}` }
    let permissions: string[] | null = null
    try { const p = await getJSON(`${GARMIN_API}/user/permissions`, h) as unknown; permissions = Array.isArray(p) ? p.map(String) : null } catch { /* optional */ }
    // History: Enterprise accepts backfill (asynchronous — the data then arrives by push); Starter refuses it. Best effort.
    const endS = Math.floor(Date.now() / 1000), startS = endS - BACKFILL_DAYS * 86_400
    const backfill: Record<string, number> = {}
    for (const type of PULL_TYPES) {
      try {
        const r = await fetch(`${GARMIN_API}/backfill/${type}?summaryStartTimeInSeconds=${startS}&summaryEndTimeInSeconds=${endS}`, { headers: h })
        backfill[type] = r.status
        await r.body?.cancel()
      } catch { backfill[type] = 0 }
    }
    log("info", "garmin.after_connect", { fn: FN, vendor: "garmin", permissions, backfill })
    return { meta: { permissions, backfill_status: backfill, backfill_days: BACKFILL_DAYS } }
  },

  parseWebhook(_req, rawBody, url): WebhookEvent[] {
    assertWebhookToken(url)
    if (!rawBody) return []
    const body = JSON.parse(rawBody) as Record<string, unknown>
    const byUser = new Map<string, WebhookEvent & { rows: RowBatch }>()
    const ev = (uid: string) => {
      let x = byUser.get(uid)
      if (!x) { x = { vendorUserId: uid, kind: "push", rows: { daily: [], epoch: [] } }; byUser.set(uid, x) }
      return x
    }
    for (const [type, items] of Object.entries(body)) {
      if (!Array.isArray(items)) continue
      for (const raw of items as Rec[]) {
        const uid = str(raw?.userId)
        if (!uid) continue
        if (type === "deregistrations") { const x = ev(uid); x.revoked = true; x.kind = "deregistration"; continue }
        if (type === "userPermissionsChange") { const x = ev(uid); if (x.kind === "push") x.kind = "permissions"; continue }
        if (raw.callbackURL != null) {
          // PING (Enterprise): the URL is never fetched; its upload window becomes a queued pull of our own.
          const w = pingWindow(raw.callbackURL)
          if (!w) { log("warn", "garmin.ping_rejected", { fn: FN, vendor: "garmin", type }); continue }
          const x = ev(uid); x.kind = x.kind === "push" ? `ping:${type}` : x.kind
          x.windowStart = x.windowStart && x.windowStart < w.start ? x.windowStart : w.start
          x.windowEnd = x.windowEnd && x.windowEnd > w.end ? x.windowEnd : w.end
          continue
        }
        const m = mapSummary(type, raw, { hrvConfirmed: HRV_RMSSD_CONFIRMED })
        const x = ev(uid)
        x.rows.daily.push(...m.daily); x.rows.epoch.push(...m.epoch)
        for (const r of m.daily) { if (!x.windowStart || r.day < x.windowStart) x.windowStart = r.day; if (!x.windowEnd || r.day > x.windowEnd) x.windowEnd = r.day }
      }
    }
    return [...byUser.values()].map((x) => (x.rows.daily.length || x.rows.epoch.length ? x : { ...x, rows: undefined }) as WebhookEvent)
  },

  async fetchRange(tokens, start, end, _ctx: AccountContext): Promise<RowBatch> {
    // Starter tier = push only: the data came in the webhook; nothing to pull (the call still kept the tokens fresh).
    if (Deno.env.get("GARMIN_PULL_ENABLED") !== "1") return { daily: [], epoch: [] }
    const h = { Authorization: `Bearer ${tokens.accessToken}` }
    const out: RowBatch = { daily: [], epoch: [] }
    // Pull endpoints are keyed by UPLOAD time, at most 24 h per call (VERIFY the limit in the spec).
    let from = unixOf(`${start}T00:00:00Z`)
    const to = unixOf(`${addDays(end, 1)}T00:00:00Z`)
    while (from < to) {
      const chunkEnd = Math.min(from + 86_400, to)
      for (const type of PULL_TYPES) {
        try {
          const j = await getJSON(`${GARMIN_API}/${type}?uploadStartTimeInSeconds=${from}&uploadEndTimeInSeconds=${chunkEnd}`, h) as unknown
          for (const it of (Array.isArray(j) ? j : []) as Rec[]) { const m = mapSummary(type, it, { hrvConfirmed: HRV_RMSSD_CONFIRMED }); out.daily.push(...m.daily); out.epoch.push(...m.epoch) }
        } catch (e) {
          if (e instanceof UnauthorizedError || e instanceof RateLimitedError) throw e
          // A summary type the member did not share (or the tier does not serve) must not sink the others.
          log("warn", "garmin.pull_type_failed", { fn: FN, vendor: "garmin", type, status: (e as { status?: number }).status ?? null })
        }
      }
      from = chunkEnd
    }
    return out
  },
}
