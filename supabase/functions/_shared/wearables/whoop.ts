// WHOOP API v2 — spec §5 (tier B for OAuth/endpoints; webhook signature tier C/D → VERIFY on first live event).
// Tokens 1 h, refresh single-use (needs `scope=offline`); pages ≤ 25 records; webhook URL is set in the WHOOP dashboard.
import { type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent, T, compact, dailyDate, dailyMap, dayEndISO, dayOfISO, dayStartISO, epoch, getJSON, hmacSha256, num, offsetMinutes, timingSafeEqual, tokenPost, vendorClient, addDays } from "./core.ts"

const AUTH = "https://api.prod.whoop.com/oauth/oauth2/auth"
const TOKEN = "https://api.prod.whoop.com/oauth/oauth2/token"
const API = "https://api.prod.whoop.com/developer"

async function records(path: string, tokens: TokenSet, q: Record<string, string>): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = []
  let next = ""
  for (let i = 0; i < 40; i++) {
    const qs = new URLSearchParams({ ...q, limit: "25", ...(next ? { nextToken: next } : {}) })
    const j = await getJSON(`${API}${path}?${qs}`, { Authorization: `Bearer ${tokens.accessToken}` })
    out.push(...((j.records as Record<string, unknown>[]) ?? []))
    next = (j.next_token as string) ?? ""
    if (!next) break
  }
  return out
}

const kcal = (kj: unknown) => { const v = num(kj); return v == null ? null : v / 4.184 }

export const whoop: VendorAdapter = {
  key: "whoop",
  name: "WHOOP",
  usesPKCE: false,
  scopes: ["offline", "read:profile", "read:body_measurement", "read:cycles", "read:recovery", "read:sleep", "read:workout"],

  authorizeURL({ clientId, redirectUri, state }) {
    return `${AUTH}?${new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, response_type: "code", scope: whoop.scopes.join(" "), state })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("whoop")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri, client_id: clientId, client_secret: clientSecret })
    const me = await getJSON(`${API}/v2/user/profile/basic`, { Authorization: `Bearer ${t.access_token}` })
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 3600), scopes: String(t.scope ?? "").split(" ").filter(Boolean), vendorUserId: String(me.user_id ?? "") }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("whoop")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret, scope: "offline" })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string) ?? refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 3600) }
  },

  async revoke(tokens) {
    await fetch(`${API}/v2/user/access`, { method: "DELETE", headers: { Authorization: `Bearer ${tokens.accessToken}` } })
  },

  async afterConnect(tokens) {
    try {
      const b = await getJSON(`${API}/v2/user/measurement/body`, { Authorization: `Bearer ${tokens.accessToken}` })
      return { meta: { height_m: num(b.height_meter), weight_kg: num(b.weight_kilogram), max_heart_rate: num(b.max_heart_rate) } }
    } catch { return {} }
  },

  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    const { clientSecret } = vendorClient("whoop")
    const ts = req.headers.get("X-WHOOP-Signature-Timestamp") ?? "", sig = req.headers.get("X-WHOOP-Signature") ?? ""
    if (Math.abs(Date.now() - Number(ts)) > 300_000) throw new Error("whoop timestamp too old")
    const mac = await hmacSha256(clientSecret, ts + rawBody, "base64")
    if (!sig || !timingSafeEqual(mac, sig)) throw new Error("whoop signature mismatch")
    const e = JSON.parse(rawBody) as Record<string, unknown>
    if (e.user_id == null) return []
    return [{ vendorUserId: String(e.user_id), kind: String(e.type ?? "event") }]
  },

  async fetchRange(tokens, start, end) {
    // Sleeps end on `day`; cycles start on `day`. One extra day on each side, then filter by local date.
    const q = { start: dayStartISO(addDays(start, -1)), end: dayEndISO(addDays(end, 1)) }
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    const inRange = (d: string) => d >= start && d <= end
    const sleepDays = new Map<string, string>()   // sleep id → day
    for (const s of await records("/v2/activity/sleep", tokens, q)) {
      if (s.nap === true || s.score_state !== "SCORED" || !s.end) continue
      const day = dayOfISO(String(s.end), offsetMinutes(s.timezone_offset as string))
      sleepDays.set(String(s.id), day)
      if (!inRange(day)) continue
      const sc = (s.score ?? {}) as Record<string, unknown>, g = (sc.stage_summary ?? {}) as Record<string, unknown>, k = 1000
      const light = (num(g.total_light_sleep_time_milli) ?? 0) / k, sws = (num(g.total_slow_wave_sleep_time_milli) ?? 0) / k, rem = (num(g.total_rem_sleep_time_milli) ?? 0) / k, awake = (num(g.total_awake_time_milli) ?? 0) / k
      dailyRows.push(...dailyMap(day, {
        [T.MainSleepDuration]: light + sws + rem, [T.InBed]: (num(g.total_in_bed_time_milli) ?? 0) / k || null, [T.REM]: rem, [T.Deep]: sws, [T.Light]: light, [T.Awake]: awake, [T.AwakeAfterWakeup]: awake,
        [T.Interruptions]: num(g.disturbance_count), [T.SleepEfficiency]: num(sc.sleep_efficiency_percentage), [T.SleepQuality]: num(sc.sleep_performance_percentage), [T.SleepScore]: num(sc.sleep_performance_percentage), [T.RespirationRateSleep]: num(sc.respiratory_rate),
      }, { details: { sleep_id: s.id, cycle_id: s.cycle_id, cycles: num(g.sleep_cycle_count), consistency: num(sc.sleep_consistency_percentage), sleep_needed: sc.sleep_needed ?? null } }))
      dailyRows.push(...compact([dailyDate(day, T.SleepStart, String(s.start)), dailyDate(day, T.SleepEnd, String(s.end))]))
    }
    for (const r of await records("/v2/recovery", tokens, q)) {
      if (r.score_state !== "SCORED") continue
      const day = sleepDays.get(String(r.sleep_id))
      if (!day || !inRange(day)) continue
      const sc = (r.score ?? {}) as Record<string, unknown>, hrv = num(sc.hrv_rmssd_milli)
      dailyRows.push(...dailyMap(day, { [T.RmssdSleep]: hrv, [T.Rmssd]: hrv, [T.HeartRateResting]: num(sc.resting_heart_rate), [T.SPO2]: num(sc.spo2_percentage), [T.SkinTemperature]: num(sc.skin_temp_celsius), [T.RecoveryScore]: num(sc.recovery_score) },
        { details: { statistic: "rmssd", window: "night", calibrating: sc.user_calibrating ?? null, cycle_id: r.cycle_id } }))
    }
    for (const c of await records("/v2/cycle", tokens, q)) {
      if (!c.end || c.score_state !== "SCORED") continue
      const day = dayOfISO(String(c.start), offsetMinutes(c.timezone_offset as string))
      if (!inRange(day)) continue
      const sc = (c.score ?? {}) as Record<string, unknown>
      dailyRows.push(...dailyMap(day, { [T.BurnedCalories]: kcal(sc.kilojoule), [T.HeartRate]: num(sc.average_heart_rate), [T.StrainScore]: num(sc.strain) }, { details: { cycle_id: c.id, max_heart_rate: num(sc.max_heart_rate) } }))
    }
    for (const w of await records("/v2/activity/workout", tokens, q)) {
      if (w.score_state !== "SCORED") continue
      const sc = (w.score ?? {}) as Record<string, unknown>, startTs = String(w.start), endTs = String(w.end), z = (sc.zone_durations ?? {}) as Record<string, unknown>
      epochRows.push(...compact([
        epoch(startTs, T.ActivityType, 0, { endTs, valueText: String(w.sport_name ?? ""), valueType: "STRING", details: { workout_id: w.id, strain: num(sc.strain), percent_recorded: num(sc.percent_recorded) } }),
        epoch(startTs, T.ActiveBurnedCalories, kcal(sc.kilojoule), { endTs, details: { workout: true } }),
        epoch(startTs, T.HeartRate, num(sc.average_heart_rate), { endTs, details: { workout: true, max: num(sc.max_heart_rate) } }),
        epoch(startTs, T.CoveredDistance, num(sc.distance_meter), { endTs, details: { workout: true } }),
        epoch(startTs, T.ElevationGain, num(sc.altitude_gain_meter), { endTs, details: { workout: true } }),
        epoch(startTs, T.HRZoneLight, ((num(z.zone_one_milli) ?? 0) + (num(z.zone_two_milli) ?? 0)) / 60_000 || null, { endTs }),
        epoch(startTs, T.HRZoneModerate, (num(z.zone_three_milli) ?? 0) / 60_000 || null, { endTs }),
        epoch(startTs, T.HRZoneIntense, (num(z.zone_four_milli) ?? 0) / 60_000 || null, { endTs }),
        epoch(startTs, T.HRZoneMaximal, (num(z.zone_five_milli) ?? 0) / 60_000 || null, { endTs }),
      ]))
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}
