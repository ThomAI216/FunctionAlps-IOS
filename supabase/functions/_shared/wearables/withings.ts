// Withings Public Cloud — spec §1 (tier B). Form-encoded POSTs, `{status, body}` envelopes (HTTP 200 always —
// `status !== 0` is the error), comma-separated scopes, 30-second authorization codes, 3-hour access tokens.
// Notify API: per user per `appli` category, unsigned notifications → we only trust them as a "pull now" hint.
import { type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent, T, UnauthorizedError, compact, dailyDate, dailyMap, daysBetween, epoch, hmacSha256, mean, num, unixOf, vendorClient } from "./core.ts"

const AUTH = "https://account.withings.com/oauth2_user/authorize2"
const API = "https://wbsapi.withings.net"
const SCOPES = "user.info,user.metrics,user.activity,user.sleepevents"
const APPLIS = [1, 2, 4, 16, 44, 46]

async function wapi(path: string, params: Record<string, string | number>, accessToken?: string): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded" }
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`
  const r = await fetch(API + path, { method: "POST", headers, body: new URLSearchParams(Object.fromEntries(Object.entries(params).map(([k, v]) => [k, String(v)]))) })
  const j = (await r.json()) as { status: number; body?: Record<string, unknown>; error?: string }
  if (j.status === 401 || j.status === 2555) throw new UnauthorizedError(`withings status ${j.status}`)
  if (j.status !== 0) throw new Error(`withings ${path} status ${j.status}: ${String(j.error ?? "").slice(0, 200)}`)
  return j.body ?? {}
}

const tokenSet = (b: Record<string, unknown>): TokenSet => ({
  accessToken: String(b.access_token), refreshToken: b.refresh_token as string | undefined,
  expiresAt: Math.floor(Date.now() / 1000) + (num(b.expires_in) ?? 10_800), scopes: String(b.scope ?? SCOPES).split(","), vendorUserId: b.userid != null ? String(b.userid) : undefined,
})

const MEAS: Record<number, number> = { 1: T.Weight, 4: T.Height, 5: T.FatFreeMass, 6: T.FatRatio, 8: T.FatMass, 9: T.DiastolicBP, 10: T.SystolicBP, 11: T.HeartRate, 12: T.UndefinedTemperature, 54: T.SPO2, 71: T.BodyTemperature, 73: T.SkinTemperature, 76: T.MuscleMass, 77: T.WaterMass, 88: T.BoneMass, 91: T.PulseWaveVelocity, 123: T.VO2max, 130: T.AFib }

export const withings: VendorAdapter = {
  key: "withings",
  name: "Withings",
  usesPKCE: false,
  scopes: SCOPES.split(","),

  authorizeURL({ clientId, redirectUri, state }) {
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, state, scope: SCOPES, redirect_uri: redirectUri })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("withings")
    return tokenSet(await wapi("/v2/oauth2", { action: "requesttoken", grant_type: "authorization_code", client_id: clientId, client_secret: clientSecret, code, redirect_uri: redirectUri }))
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("withings")
    const t = tokenSet(await wapi("/v2/oauth2", { action: "requesttoken", grant_type: "refresh_token", client_id: clientId, client_secret: clientSecret, refresh_token: refreshToken }))
    return { ...t, refreshToken: t.refreshToken ?? refreshToken }
  },

  async revoke(tokens) {
    // Signature mode: nonce → HMAC-SHA256(client_secret, values of the params sorted by name, comma-joined).
    const { clientId, clientSecret } = vendorClient("withings")
    if (!tokens.vendorUserId) return
    const ts = Math.floor(Date.now() / 1000)
    const nonceBody = await wapi("/v2/signature", { action: "getnonce", client_id: clientId, timestamp: ts, signature: await hmacSha256(clientSecret, `getnonce,${clientId},${ts}`) })
    const nonce = String(nonceBody.nonce ?? "")
    await wapi("/v2/oauth2", { action: "revoke", client_id: clientId, nonce, userid: tokens.vendorUserId, signature: await hmacSha256(clientSecret, `revoke,${clientId},${nonce}`) })
  },

  async afterConnect(tokens, { webhookUrl }) {
    const subscribed: number[] = []
    for (const appli of APPLIS) {
      try { await wapi("/notify", { action: "subscribe", callbackurl: webhookUrl, appli, comment: "FunctionAlps" }, tokens.accessToken); subscribed.push(appli) }
      catch (e) { console.warn("[withings] subscribe", appli, String(e).slice(0, 120)) }
    }
    return { meta: { notify_applis: subscribed, notify_url: webhookUrl } }
  },

  parseWebhook(_req, rawBody): WebhookEvent[] {
    // application/x-www-form-urlencoded: userid, appli, startdate, enddate, [date, action] — unsigned.
    const p = Object.fromEntries(new URLSearchParams(rawBody))
    if (!p.userid) return []
    const day = (unix: string | undefined) => unix && /^\d+$/.test(unix) ? new Date(Number(unix) * 1000).toISOString().slice(0, 10) : undefined
    const revoked = p.action === "unlink" || (p.appli === "46" && p.action === "delete")
    return [{ vendorUserId: String(p.userid), kind: `appli.${p.appli ?? "?"}.${p.action ?? "update"}`, windowStart: p.date?.slice(0, 10) ?? day(p.startdate), windowEnd: p.date?.slice(0, 10) ?? day(p.enddate), revoked }]
  },

  async fetchRange(tokens, start, end) {
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    const tok = tokens.accessToken
    // Sleep summaries + per-night series (HR / RR / HRV per minute; nightly means computed here).
    const sum = await wapi("/v2/sleep", { action: "getsummary", startdateymd: start, enddateymd: end, data_fields: "total_timeinbed,total_sleep_time,sleep_efficiency,sleep_latency,waso,deepsleepduration,lightsleepduration,remsleepduration,wakeupduration,wakeupcount,hr_average,hr_min,rr_average,snoring,breathing_disturbances_intensity,sleep_score" }, tok)
    for (const n of (sum.series as Record<string, unknown>[]) ?? []) {
      const d = (n.data ?? {}) as Record<string, unknown>, day = String(n.date), st = num(n.startdate), en = num(n.enddate)
      const eff = num(d.sleep_efficiency)
      dailyRows.push(...dailyMap(day, {
        [T.MainSleepDuration]: num(d.total_sleep_time), [T.InBed]: num(d.total_timeinbed), [T.REM]: num(d.remsleepduration), [T.Deep]: num(d.deepsleepduration), [T.Light]: num(d.lightsleepduration),
        [T.Awake]: num(d.wakeupduration), [T.Latency]: num(d.sleep_latency), [T.AwakeAfterWakeup]: num(d.waso), [T.Interruptions]: num(d.wakeupcount), [T.SleepEfficiency]: eff != null && eff <= 1 ? eff * 100 : eff,
        [T.SleepQuality]: num(d.sleep_score), [T.SleepScore]: num(d.sleep_score), [T.HeartRateSleep]: num(d.hr_average), [T.HeartRateSleepLowest]: num(d.hr_min), [T.HeartRateResting]: num(d.hr_min), [T.RespirationRateSleep]: num(d.rr_average),
        [T.Snoring]: num(d.snoring), [T.Breathing]: num(d.breathing_disturbances_intensity),
      }, { details: { model: n.model, sleep_id: n.id, timezone: n.timezone } }))
      if (st && en) {
        dailyRows.push(...compact([dailyDate(day, T.SleepStart, new Date(st * 1000).toISOString()), dailyDate(day, T.SleepEnd, new Date(en * 1000).toISOString())]))
        try {
          const ser = await wapi("/v2/sleep", { action: "get", startdate: st, enddate: en, data_fields: "hr,rr,sdnn_1,rmssd" }, tok)
          const rm: number[] = [], sd: number[] = []
          for (const seg of (ser.series as Record<string, unknown>[]) ?? []) {
            const push = (id: number, m: unknown, acc?: number[]) => { for (const [u, v] of Object.entries((m ?? {}) as Record<string, unknown>)) { const x = num(v); if (x == null) continue; acc?.push(x); const row = epoch(new Date(Number(u) * 1000).toISOString(), id, x, { details: { source: "sleep" } }); if (row) epochRows.push(row) } }
            push(T.HeartRate, seg.hr); push(T.RespirationRate, seg.rr); push(T.SDNN, seg.sdnn_1, sd); push(T.Rmssd, seg.rmssd, rm)
          }
          if (rm.length) dailyRows.push(...dailyMap(day, { [T.RmssdSleep]: mean(rm), [T.Rmssd]: mean(rm) }, { details: { statistic: "rmssd", window: "night", samples: rm.length } }))
          if (sd.length) dailyRows.push(...dailyMap(day, { [T.SDNN]: mean(sd) }, { details: { statistic: "sdnn_1", window: "night", samples: sd.length } }))
        } catch (e) { console.warn("[withings] sleep series", String(e).slice(0, 120)) }
      }
    }
    // Daily activity (Withings devices only; brand 18 = external, skipped to avoid double counting with the relay).
    const act = await wapi("/v2/measure", { action: "getactivity", startdateymd: start, enddateymd: end, data_fields: "steps,distance,elevation,active,calories,totalcalories,hr_average,hr_zone_0,hr_zone_1,hr_zone_2,hr_zone_3" }, tok)
    for (const x of (act.activities as Record<string, unknown>[]) ?? []) {
      if (num(x.brand) === 18) continue
      dailyRows.push(...dailyMap(String(x.date), {
        [T.Steps]: num(x.steps), [T.CoveredDistance]: num(x.distance), [T.FloorsClimbed]: num(x.elevation), [T.ActivityDuration]: (num(x.active) ?? 0) / 60 || null, [T.ActiveBurnedCalories]: num(x.calories), [T.BurnedCalories]: num(x.totalcalories), [T.HeartRate]: num(x.hr_average),
        [T.HRZoneLight]: (num(x.hr_zone_0) ?? 0) / 60 || null, [T.HRZoneModerate]: (num(x.hr_zone_1) ?? 0) / 60 || null, [T.HRZoneIntense]: (num(x.hr_zone_2) ?? 0) / 60 || null, [T.HRZoneMaximal]: (num(x.hr_zone_3) ?? 0) / 60 || null,
      }, { details: { brand: num(x.brand), is_tracker: x.is_tracker ?? null } }))
    }
    // Body / BP / SpO2 / temperature measures: value × 10^unit; device-known readings only.
    const meas = await wapi("/measure", { action: "getmeas", meastypes: Object.keys(MEAS).join(","), category: 1, startdate: unixOf(`${start}T00:00:00Z`), enddate: unixOf(`${end}T23:59:59Z`) }, tok)
    for (const g of (meas.measuregrps as Record<string, unknown>[]) ?? []) {
      const attrib = num(g.attrib) ?? 0
      if (attrib > 1) continue
      const ts = new Date((num(g.date) ?? 0) * 1000).toISOString(), day = ts.slice(0, 10)
      for (const q of (g.measures as Record<string, unknown>[]) ?? []) {
        const id = MEAS[num(q.type) ?? -1]
        if (!id) continue
        let v = (num(q.value) ?? 0) * Math.pow(10, num(q.unit) ?? 0)
        if (id === T.Height) v *= 100
        const row = epoch(ts, id, v, { details: { grpid: g.grpid, attrib, model: g.model, meastype: q.type } })
        if (row) epochRows.push(row)
        if ([T.Weight, T.FatRatio, T.FatMass, T.FatFreeMass, T.MuscleMass, T.BoneMass, T.WaterMass, T.Height, T.VO2max, T.SPO2, T.DiastolicBP, T.SystolicBP, T.BodyTemperature, T.SkinTemperature].includes(id)) {
          dailyRows.push(...dailyMap(day, { [id]: v }, { details: { grpid: g.grpid, model: g.model } }))
        }
      }
    }
    // Workouts.
    try {
      const wk = await wapi("/v2/measure", { action: "getworkouts", startdateymd: start, enddateymd: end, data_fields: "calories,hr_average,hr_min,hr_max,steps,distance,effduration" }, tok)
      for (const w of (wk.series as Record<string, unknown>[]) ?? []) {
        const st = num(w.startdate), en = num(w.enddate), d = (w.data ?? {}) as Record<string, unknown>
        if (!st) continue
        const startTs = new Date(st * 1000).toISOString(), endTs = en ? new Date(en * 1000).toISOString() : undefined
        epochRows.push(...compact([
          epoch(startTs, T.ActivityType, num(w.category) ?? 0, { endTs, valueText: `withings_category_${w.category}`, valueType: "STRING", details: { workout_id: w.id, effduration: num(d.effduration) } }),
          epoch(startTs, T.ActiveBurnedCalories, num(d.calories), { endTs, details: { workout: true } }), epoch(startTs, T.CoveredDistance, num(d.distance), { endTs, details: { workout: true } }),
          epoch(startTs, T.HeartRate, num(d.hr_average), { endTs, details: { workout: true, max: num(d.hr_max) } }),
        ]))
      }
    } catch (e) { console.warn("[withings] workouts", String(e).slice(0, 120)) }
    return { daily: dailyRows, epoch: epochRows }
  },
}

export const _withingsTest = { daysBetween }
