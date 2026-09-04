// Garmin Health API — spec §6 (tier B-mirror). ⚠ The Connect Developer Program is closed to new applicants
// (2026): `wearable_vendors.status` stays `planned` until the practice holds a key. PKCE S256, body client
// auth, 24 h / 90 d tokens, PUSH webhooks with the data inline (verified only by `garmin-client-id`).
import { type DailyRow, type EpochRow, type VendorAdapter, type WebhookEvent, T, compact, dailyDate, dailyMap, epoch, getJSON, mean, num, timingSafeEqual, tokenPost, unixOf, vendorClient } from "./core.ts"

const AUTH = "https://connect.garmin.com/oauth2Confirm"
const TOKEN = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
const API = "https://apis.garmin.com/wellness-api/rest"
const PULL_TYPES = ["dailies", "sleeps", "hrv", "stressDetails", "pulseOx", "respiration", "bodyComps", "userMetrics", "skinTemp", "bloodPressures", "activities"]
const BACKFILL_TYPES = ["dailies", "sleeps", "hrv", "epochs", "pulseOx", "respiration", "stressDetails", "bodyComps", "userMetrics", "skinTemp", "bloodPressures", "activities"]

const iso = (s: unknown) => { const v = num(s); return v == null ? undefined : new Date(v * 1000).toISOString() }
const vals = (m: unknown) => Object.values((m ?? {}) as Record<string, unknown>).map(num)

function series(it: Record<string, unknown>, key: string, id: number, extra: Record<string, unknown> = {}): EpochRow[] {
  const base = num(it.startTimeInSeconds) ?? 0
  return compact(Object.entries((it[key] ?? {}) as Record<string, unknown>).map(([off, v]) => epoch(new Date((base + Number(off)) * 1000).toISOString(), id, num(v), { details: extra })))
}

/** One pushed/pulled summary → catalogue rows. `type` = the summary type key. */
export function mapItem(type: string, it: Record<string, unknown>): { daily: DailyRow[]; epoch: EpochRow[] } {
  const d: DailyRow[] = [], e: EpochRow[] = []
  const off = (num(it.startTimeOffsetInSeconds) ?? num(it.measurementTimeOffsetInSeconds) ?? 0) / 60
  const day = (it.calendarDate as string) ?? (iso(it.startTimeInSeconds ?? it.measurementTimeInSeconds)?.slice(0, 10) ?? "")
  const X = { timezoneOffset: off, details: { summary_id: it.summaryId ?? null } }
  const tm = iso(it.measurementTimeInSeconds) ?? iso(it.startTimeInSeconds) ?? ""
  switch (type) {
    case "dailies":
      d.push(...dailyMap(day, {
        [T.Steps]: num(it.steps), [T.CoveredDistance]: num(it.distanceInMeters), [T.FloorsClimbed]: num(it.floorsClimbed), [T.ActiveBurnedCalories]: num(it.activeKilocalories), [T.BurnedCalories]: (num(it.activeKilocalories) ?? 0) + (num(it.bmrKilocalories) ?? 0) || null,
        [T.ActivityDuration]: (num(it.activeTimeInSeconds) ?? 0) / 60 || null, [T.ActivityMid]: (num(it.moderateIntensityDurationInSeconds) ?? 0) / 60 || null, [T.ActivityHigh]: (num(it.vigorousIntensityDurationInSeconds) ?? 0) / 60 || null,
        [T.HeartRateResting]: num(it.restingHeartRateInBeatsPerMinute), [T.HeartRate]: num(it.averageHeartRateInBeatsPerMinute), [T.AverageStress]: num(it.averageStressLevel),
        [T.HighStress]: (num(it.highStressDurationInSeconds) ?? 0) / 60 || null, [T.MediumStress]: (num(it.mediumStressDurationInSeconds) ?? 0) / 60 || null, [T.LowStress]: (num(it.lowStressDurationInSeconds) ?? 0) / 60 || null,
      }, { ...X, details: { ...X.details, body_battery_charged: num(it.bodyBatteryChargedValue), body_battery_drained: num(it.bodyBatteryDrainedValue), max_stress: num(it.maxStressLevel) } }))
      e.push(...series(it, "timeOffsetHeartRateSamples", T.HeartRate))
      break
    case "sleeps": {
      if (it.validation === "MANUAL") break
      const awake = num(it.awakeDurationInSeconds) ?? 0, unm = num(it.unmeasurableSleepInSeconds) ?? 0, dur = num(it.durationInSeconds) ?? 0
      const levels = (it.sleepLevelsMap ?? {}) as Record<string, { startTimeInSeconds: number; endTimeInSeconds: number }[]>
      d.push(...dailyMap(day, {
        [T.MainSleepDuration]: dur || null, [T.InBed]: dur + awake + unm || null, [T.REM]: num(it.remSleepInSeconds), [T.Deep]: num(it.deepSleepDurationInSeconds), [T.Light]: num(it.lightSleepDurationInSeconds), [T.Awake]: awake || null, [T.AwakeAfterWakeup]: awake || null,
        [T.Interruptions]: (levels.awake ?? []).length || null, [T.SleepQuality]: num((it.overallSleepScore as Record<string, unknown>)?.value), [T.SleepScore]: num((it.overallSleepScore as Record<string, unknown>)?.value),
        [T.RespirationRateSleep]: mean(vals(it.timeOffsetSleepRespiration)), [T.SPO2]: mean(vals(it.timeOffsetSleepSpo2)),
      }, { ...X, details: { ...X.details, validation: it.validation ?? null, naps: num(it.totalNapDurationInSeconds) } }))
      const st = num(it.startTimeInSeconds)
      if (st) d.push(...compact([dailyDate(day, T.SleepStart, new Date(st * 1000).toISOString()), dailyDate(day, T.SleepEnd, new Date((st + dur + awake + unm) * 1000).toISOString())]))
      e.push(...series(it, "timeOffsetSleepRespiration", T.RespirationRate), ...series(it, "timeOffsetSleepSpo2", T.SPO2))
      const stage: Record<string, number> = { deep: T.SleepDeepBinary, light: T.SleepLightBinary, rem: T.SleepREMBinary, awake: T.SleepAwakeBinary }
      for (const [k, id] of Object.entries(stage)) for (const r of levels[k] ?? []) { const row = epoch(new Date(r.startTimeInSeconds * 1000).toISOString(), id, (r.endTimeInSeconds - r.startTimeInSeconds) / 60, { endTs: new Date(r.endTimeInSeconds * 1000).toISOString() }); if (row) e.push(row) }
      break
    }
    case "hrv":
      d.push(...dailyMap(day, { [T.RmssdSleep]: num(it.lastNightAvg), [T.Rmssd]: num(it.lastNightAvg), [T.RmssdSleepHighest]: num(it.lastNight5MinHigh) }, { ...X, details: { ...X.details, statistic: "rmssd", window: "night" } }))
      e.push(...series(it, "hrvValues", T.Rmssd, { statistic: "rmssd" }))
      break
    case "pulseOx": case "pulseox": e.push(...series(it, "timeOffsetSpo2Values", T.SPO2, { on_demand: it.onDemand ?? null })); break
    case "allDayRespiration": case "respiration": e.push(...series(it, "timeOffsetEpochToBreaths", T.RespirationRate)); break
    case "stressDetails":
      e.push(...series(it, "timeOffsetStressLevelValues", T.AverageStress).filter((r) => (r.value ?? -1) >= 0), ...series(it, "timeOffsetBodyBatteryValues", T.BodyBattery))
      { const bb = vals(it.timeOffsetBodyBatteryValues).filter((x): x is number => x != null); if (bb.length) d.push(...dailyMap(day, { [T.BodyBattery]: Math.max(...bb) }, { ...X, details: { ...X.details, statistic: "max", min: Math.min(...bb) } })) }
      break
    case "epochs":
      e.push(...compact([epoch(tm, T.Steps, num(it.steps), { endTs: iso((num(it.startTimeInSeconds) ?? 0) + (num(it.durationInSeconds) ?? 900)) }), epoch(tm, T.CoveredDistance, num(it.distanceInMeters)), epoch(tm, T.ActiveBurnedCalories, num(it.activeKilocalories)), epoch(tm, T.MET, num(it.met), { details: { intensity: it.intensity ?? null } })]))
      break
    case "userMetrics": d.push(...dailyMap(day, { [T.VO2max]: num(it.vo2Max) }, { ...X, details: { ...X.details, fitness_age: num(it.fitnessAge), vo2max_cycling: num(it.vo2MaxCycling) } })); break
    case "bodyComps": {
      const w = num(it.weightInGrams), fat = num(it.bodyFatInPercent), water = num(it.bodyWaterInPercent)
      const m: Record<number, number | null> = { [T.Weight]: w != null ? w / 1000 : null, [T.FatRatio]: fat, [T.BMI]: num(it.bodyMassIndex), [T.MuscleMass]: num(it.muscleMassInGrams) != null ? (num(it.muscleMassInGrams) as number) / 1000 : null, [T.BoneMass]: num(it.boneMassInGrams) != null ? (num(it.boneMassInGrams) as number) / 1000 : null, [T.WaterMass]: w != null && water != null ? (w / 1000) * water / 100 : null, [T.RestingMetabolicRate]: num(it.basalMetabolicRateInKilocalories) }
      d.push(...dailyMap(day, m, { ...X, details: { ...X.details, body_water_pct: water } }))
      for (const [id, v] of Object.entries(m)) { const row = epoch(tm, Number(id), v); if (row) e.push(row) }
      break
    }
    case "skinTemp": d.push(...dailyMap(day, { [T.SkinTemperatureDeviation]: num(it.avgDeviationCelsius) }, X)); break
    case "bloodPressures":
      e.push(...compact([epoch(tm, T.SystolicBP, num(it.systolic), { details: { source: it.sourceType ?? null } }), epoch(tm, T.DiastolicBP, num(it.diastolic), { details: { source: it.sourceType ?? null } }), epoch(tm, T.HeartRate, num(it.pulse), { details: { source: "bp_cuff" } })]))
      d.push(...dailyMap(day, { [T.SystolicBP]: num(it.systolic), [T.DiastolicBP]: num(it.diastolic) }, X))
      break
    case "activities": {
      const startTs = iso(it.startTimeInSeconds) ?? tm, endTs = iso((num(it.startTimeInSeconds) ?? 0) + (num(it.durationInSeconds) ?? 0))
      e.push(...compact([
        epoch(startTs, T.ActivityType, 0, { endTs, valueText: String(it.activityType ?? ""), valueType: "STRING", details: { activity_id: it.activityId, name: it.activityName, manual: it.manual ?? null } }),
        epoch(startTs, T.ActiveBurnedCalories, num(it.activeKilocalories), { endTs, details: { workout: true } }), epoch(startTs, T.CoveredDistance, num(it.distanceInMeters), { endTs, details: { workout: true } }),
        epoch(startTs, T.HeartRate, num(it.averageHeartRateInBeatsPerMinute), { endTs, details: { workout: true, max: num(it.maxHeartRateInBeatsPerMinute) } }), epoch(startTs, T.ElevationGain, num(it.totalElevationGainInMeters), { endTs }),
      ]))
      break
    }
    case "mct": d.push(...dailyMap(day, { [T.MenstrualCycleDay]: num(it.dayInCycle) }, { ...X, details: { ...X.details, phase: it.currentPhaseType ?? null, period_start: it.periodStartDate ?? null, cycle_length: num(it.cycleLength) } })); break
  }
  return { daily: d, epoch: e }
}

export const garmin: VendorAdapter = {
  key: "garmin",
  name: "Garmin",
  usesPKCE: true,
  scopes: [],   // fixed by Garmin; data access is governed by user permissions (HEALTH_EXPORT, ACTIVITY_EXPORT, MCT_EXPORT)

  authorizeURL({ clientId, redirectUri, state, codeChallenge }) {
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, code_challenge: codeChallenge ?? "", code_challenge_method: "S256", redirect_uri: redirectUri, state })}`
  },

  async exchangeCode({ code, redirectUri, codeVerifier }) {
    const { clientId, clientSecret } = vendorClient("garmin")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", client_id: clientId, client_secret: clientSecret, code, code_verifier: codeVerifier ?? "", redirect_uri: redirectUri })
    const h = { Authorization: `Bearer ${t.access_token}` }
    const id = await getJSON(`${API}/user/id`, h)
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 86_400) - 600, scopes: String(t.scope ?? "").split(" ").filter(Boolean), vendorUserId: String(id.userId ?? ""), raw: { refresh_token_expires_in: num(t.refresh_token_expires_in) } }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("garmin")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", client_id: clientId, client_secret: clientSecret, refresh_token: refreshToken })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string) ?? refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 86_400) - 600 }
  },

  async revoke(tokens) {
    await fetch(`${API}/user/registration`, { method: "DELETE", headers: { Authorization: `Bearer ${tokens.accessToken}` } })
  },

  async afterConnect(tokens) {
    const h = { Authorization: `Bearer ${tokens.accessToken}` }
    let permissions: unknown = null
    try { const p = await getJSON(`${API}/user/permissions`, h); permissions = Array.isArray(p) ? p : (p.permissions ?? null) } catch { /* optional */ }
    // Historical backfill (≤ 90 days per request; 202 accepted, data arrives through the PUSH endpoint).
    const endS = Math.floor(Date.now() / 1000), startS = endS - 30 * 86_400
    const requested: string[] = []
    for (const type of BACKFILL_TYPES) {
      try { const r = await fetch(`${API}/backfill/${type}?summaryStartTimeInSeconds=${startS}&summaryEndTimeInSeconds=${endS}`, { headers: h }); if (r.ok || r.status === 409) requested.push(type) } catch { /* best effort */ }
    }
    return { meta: { permissions, backfill_requested: requested } }
  },

  parseWebhook(req, rawBody): WebhookEvent[] {
    const { clientId } = vendorClient("garmin")
    const got = req.headers.get("garmin-client-id") ?? ""
    if (!got || !timingSafeEqual(got, clientId)) throw new Error("garmin client id mismatch")
    const push = JSON.parse(rawBody) as Record<string, Record<string, unknown>[]>
    const byUser = new Map<string, WebhookEvent>()
    for (const [type, items] of Object.entries(push)) {
      if (!Array.isArray(items)) continue
      for (const it of items) {
        const uid = String(it.userId ?? "")
        if (!uid) continue
        const ev = byUser.get(uid) ?? { vendorUserId: uid, kind: "push", rows: { daily: [], epoch: [] }, windowStart: "1970-01-01", windowEnd: "1970-01-01" }
        if (type === "deregistrations") ev.revoked = true
        else if (type === "userPermissionsChange") ev.kind = "permissions"
        else { const m = mapItem(type, it); ev.rows!.daily.push(...m.daily); ev.rows!.epoch.push(...m.epoch) }
        byUser.set(uid, ev)
      }
    }
    // Push carries the data: the queued pull is pointless → a zero-width window makes the sync a no-op (kept for the audit trail).
    return [...byUser.values()]
  },

  async fetchRange(tokens, start, end) {
    if (start === "1970-01-01") return { daily: [], epoch: [] }
    const h = { Authorization: `Bearer ${tokens.accessToken}` }
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    // Pull endpoints are keyed by UPLOAD time, ≤ 24 h per call.
    let from = unixOf(`${start}T00:00:00Z`)
    const to = unixOf(`${end}T23:59:59Z`)
    while (from < to) {
      const chunkEnd = Math.min(from + 86_400, to)
      for (const type of PULL_TYPES) {
        try {
          const j = await getJSON(`${API}/${type}?uploadStartTimeInSeconds=${from}&uploadEndTimeInSeconds=${chunkEnd}`, h)
          const items = Array.isArray(j) ? j as Record<string, unknown>[] : []
          for (const it of items) { const m = mapItem(type, it); dailyRows.push(...m.daily); epochRows.push(...m.epoch) }
        } catch (e) { console.warn("[garmin]", type, String(e).slice(0, 120)) }
      }
      from = chunkEnd
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}
