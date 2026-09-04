// Suunto Cloud API — spec §2 (tier C/D: NO official spec text obtained → every field name is VERIFY).
// Basic client auth, JWT access tokens (claim `user` = username used in webhook payloads), every data call
// needs `Ocp-Apim-Subscription-Key`; 24/7 webhooks carry the samples inline (mapped here, no re-fetch).
import { type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent, T, compact, dailyDate, dailyMap, dayOfISO, env, epoch, getJSON, hmacSha256, num, timingSafeEqual, tokenPost, unixOf, vendorClient } from "./core.ts"

const AUTH = "https://cloudapi-oauth.suunto.com/oauth/authorize"
const TOKEN = "https://cloudapi-oauth.suunto.com/oauth/token"
const API = "https://cloudapi.suunto.com"

const headers = (tokens: TokenSet) => ({ Authorization: `Bearer ${tokens.accessToken}`, "Ocp-Apim-Subscription-Key": env("SUUNTO_SUBSCRIPTION_KEY") })

function jwtClaims(token: string): Record<string, unknown> {
  try { return JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))) } catch { return {} }
}

type Sample = { timestamp?: string; entryData?: Record<string, unknown> }

function mapSleep(samples: Sample[]): DailyRow[] {
  const rows: DailyRow[] = []
  for (const s of samples) {
    const e = s.entryData ?? {}
    if (e.IsNap === true) continue
    const endIso = (e.BedtimeEnd as string) ?? s.timestamp
    if (!endIso) continue
    const day = dayOfISO(endIso)
    const deep = num(e.DeepSleepDuration) ?? 0, light = num(e.LightSleepDuration) ?? 0, rem = num(e.REMSleepDuration) ?? 0
    const waso = num(e.WakeAfterSleepOnsetDuration), before = num(e.WakeBeforeOffBedDuration), spo2 = num(e.MaxSpo2), hrv = num(e.AvgHRV)
    rows.push(...dailyMap(day, {
      [T.MainSleepDuration]: deep + light + rem || num(e.Duration), [T.InBed]: num(e.Duration), [T.Deep]: deep || null, [T.Light]: light || null, [T.REM]: rem || null,
      [T.AwakeAfterWakeup]: waso, [T.Awake]: (waso ?? 0) + (before ?? 0) || null, [T.SleepQuality]: num(e.SleepQualityScore), [T.SleepScore]: num(e.SleepQualityScore),
      [T.HeartRateSleep]: num(e.HRAvg), [T.HeartRateSleepLowest]: num(e.HRMin), [T.HeartRateResting]: num(e.HRMin), [T.SPO2]: spo2 != null ? (spo2 <= 1 ? spo2 * 100 : spo2) : null,
    }, { details: { sleep_id: e.SleepId ?? null, proxy_rhr: "HRMin" } }))
    if (hrv != null) rows.push(...dailyMap(day, { [T.RmssdSleep]: hrv, [T.Rmssd]: hrv }, { details: { statistic: "rmssd?", window: "night", verify: true } }))
    rows.push(...compact([dailyDate(day, T.SleepStart, (e.BedtimeStart as string) ?? s.timestamp), dailyDate(day, T.SleepEnd, e.BedtimeEnd as string)]))
  }
  return rows
}

function mapRecovery(samples: Sample[]): DailyRow[] {
  const rows: DailyRow[] = []
  for (const s of samples) {
    const e = s.entryData ?? {}
    if (!s.timestamp) continue
    const bal = num(e.Balance)
    rows.push(...dailyMap(dayOfISO(s.timestamp), { [T.RecoveryScore]: bal != null ? (bal <= 1 ? bal * 100 : bal) : null, [T.StressScore]: num(e.StressState) }, { details: { stress_state_scale: "1_relaxing_2_active_3_passive_4_stressful", verify: true } }))
  }
  return rows
}

function mapActivity(samples: Sample[]): EpochRow[] {
  const rows: EpochRow[] = []
  for (const s of samples) {
    const e = s.entryData ?? {}, ts = s.timestamp
    if (!ts) continue
    const spo2 = num(e.SpO2), energy = num(e.EnergyConsumption)
    rows.push(...compact([
      epoch(ts, T.HeartRate, num(e.HR)), epoch(ts, T.Steps, num(e.StepCount)), epoch(ts, T.SPO2, spo2 != null ? (spo2 <= 1 ? spo2 * 100 : spo2) : null),
      epoch(ts, T.ActiveBurnedCalories, energy != null ? energy / 4184 : null), epoch(ts, T.Rmssd, num(e.HRV), { details: { statistic: "unknown", verify: true } }),
    ]))
  }
  return rows
}

export const suunto: VendorAdapter = {
  key: "suunto",
  name: "Suunto",
  usesPKCE: false,
  scopes: [],   // products, not scopes, gate the data (unverified)

  authorizeURL({ clientId, redirectUri, state }) {
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, redirect_uri: redirectUri, state })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("suunto")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri }, { basic: { id: clientId, secret: clientSecret } })
    const claims = jwtClaims(String(t.access_token))
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 86_400), vendorUserId: String(claims.user ?? claims.sub ?? ""), raw: { sub: claims.sub ?? null } }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("suunto")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken }, { basic: { id: clientId, secret: clientSecret } })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string) ?? refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 86_400) }
  },

  async revoke(tokens) {
    const { clientId } = vendorClient("suunto")
    await fetch(`https://cloudapi-oauth.suunto.com/oauth/deauthorize?client_id=${encodeURIComponent(clientId)}`, { headers: { Authorization: `Bearer ${tokens.accessToken}` } })
  },

  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    const secret = env("SUUNTO_WEBHOOK_SECRET")
    const sig = req.headers.get("X-HMAC-SHA256-Signature") ?? ""
    const hex = await hmacSha256(secret, rawBody, "hex"), b64 = await hmacSha256(secret, rawBody, "base64")
    if (!sig || !(timingSafeEqual(hex, sig.toLowerCase()) || timingSafeEqual(b64, sig))) throw new Error("suunto signature mismatch")
    const evt = JSON.parse(rawBody) as Record<string, unknown>
    const user = String(evt.username ?? "")
    if (!user) return []
    const type = String(evt.type ?? ""), samples = (evt.samples as Sample[]) ?? []
    const ev: WebhookEvent = { vendorUserId: user, kind: type }
    if (type === "SUUNTO_247_SLEEP_CREATED") ev.rows = { daily: mapSleep(samples), epoch: [] }
    else if (type === "SUUNTO_247_RECOVERY_CREATED") ev.rows = { daily: mapRecovery(samples), epoch: [] }
    else if (type === "SUUNTO_247_ACTIVITY_CREATED") ev.rows = { daily: [], epoch: mapActivity(samples) }
    // WORKOUT_CREATED / ROUTE_CREATED: the queued pull picks the workout up.
    return [ev]
  },

  async fetchRange(tokens, start, end) {
    const from = unixOf(`${start}T00:00:00Z`) * 1000, to = unixOf(`${end}T23:59:59Z`) * 1000
    const h = headers(tokens)
    const get = async (path: string): Promise<unknown> => { try { return await getJSON(`${API}${path}`, h) } catch (e) { console.warn("[suunto]", path.split("?")[0], String(e).slice(0, 120)); return null } }
    const asList = (j: unknown): Sample[] => Array.isArray(j) ? j as Sample[] : Array.isArray((j as Record<string, unknown>)?.payload) ? (j as Record<string, unknown>).payload as Sample[] : []
    const sleep = asList(await get(`/247samples/sleep?from=${from}&to=${to}`))
    const rec = asList(await get(`/247samples/recovery?from=${from}&to=${to}`))
    const act = asList(await get(`/247samples/activity?from=${from}&to=${to}`))
    const dailyRows = [...mapSleep(sleep), ...mapRecovery(rec)], epochRows = mapActivity(act)
    const stats = await get(`/247/daily-activity-statistics?from=${from}&to=${to}`)
    for (const d of asList(stats) as Record<string, unknown>[]) {
      const ts = (d.timestamp as string) ?? (d.date as string)
      if (!ts) continue
      const energy = num(d.energyconsumption ?? d.EnergyConsumption)
      dailyRows.push(...dailyMap(dayOfISO(ts), { [T.Steps]: num(d.stepcount ?? d.StepCount), [T.ActiveBurnedCalories]: energy != null ? energy / 4184 : null }, { details: { verify: true } }))
    }
    const wk = await get(`/v3/workouts?since=${from}&limit=100`)
    for (const w of asList(wk) as Record<string, unknown>[]) {
      const startMs = num(w.startTime), key = w.workoutKey
      if (!startMs) continue
      const startTs = new Date(startMs).toISOString()
      if (startTs.slice(0, 10) < start || startTs.slice(0, 10) > end) continue
      epochRows.push(...compact([
        epoch(startTs, T.ActivityType, num(w.activityId) ?? 0, { valueText: String(w.activityId ?? ""), valueType: "STRING", details: { workout_key: key, duration_s: num(w.totalTime), verify: true } }),
        epoch(startTs, T.ActiveBurnedCalories, num(w.energyConsumption) != null ? (num(w.energyConsumption) as number) / 4184 : null, { details: { workout: true } }),
        epoch(startTs, T.CoveredDistance, num(w.totalDistance), { details: { workout: true } }), epoch(startTs, T.HeartRate, num(w.avgHR ?? w.hrAvg), { details: { workout: true } }),
      ]))
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}

export const _suuntoTest = { mapSleep, mapRecovery, mapActivity, jwtClaims }
