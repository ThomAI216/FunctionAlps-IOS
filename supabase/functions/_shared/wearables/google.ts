// Google Health API v4 (the Fitbit successor) — spec §7 (tier A for scopes/endpoints). ⚠ Deferred: restricted-scope
// verification + CASA assessment are required before real users can consent (`wearable_vendors.status` = `planned`).
// Standard Google OAuth with PKCE, 1 h access tokens, long-lived refresh; webhooks = a project-level subscriber
// authenticated by the shared `Authorization` secret (ECDSA signature key not yet published).
import { type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent, T, UnauthorizedError, compact, dailyDate, dailyMap, daysBetween, dayOfISO, env, epoch, num, offsetMinutes, tokenPost, vendorClient, addDays } from "./core.ts"

const AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
const TOKEN = "https://oauth2.googleapis.com/token"
const API = "https://health.googleapis.com/v4"
const SCOPES = ["sleep", "health_metrics_and_measurements", "activity_and_fitness", "profile", "settings"].map((s) => `https://www.googleapis.com/auth/googlehealth.${s}.readonly`)

async function gget(tokens: TokenSet, dt: string, filter: string, pageSize = 1000): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = []
  let pageToken = ""
  for (let i = 0; i < 20; i++) {
    const q = new URLSearchParams({ pageSize: String(pageSize), filter, ...(pageToken ? { pageToken } : {}) })
    const r = await fetch(`${API}/users/me/dataTypes/${dt}/dataPoints?${q}`, { headers: { Authorization: `Bearer ${tokens.accessToken}`, Accept: "application/json" } })
    if (r.status === 401) throw new UnauthorizedError("google 401")
    if (r.status === 403 || r.status === 404) return out          // scope not granted / type unavailable
    const text = await r.text()
    if (!r.ok) throw new Error(`google ${dt} ${r.status}: ${text.slice(0, 200)}`)
    const j = JSON.parse(text)
    out.push(...((j.dataPoints as Record<string, unknown>[]) ?? []))
    pageToken = j.nextPageToken ?? ""
    if (!pageToken) break
  }
  return out
}

async function rollup(tokens: TokenSet, dt: string, day: string): Promise<Record<string, unknown> | null> {
  const r = await fetch(`${API}/users/me/dataTypes/${dt}/dataPoints:dailyRollUp`, { method: "POST", headers: { Authorization: `Bearer ${tokens.accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ range: { start: { year: +day.slice(0, 4), month: +day.slice(5, 7), day: +day.slice(8, 10) }, end: { year: +addDays(day, 1).slice(0, 4), month: +addDays(day, 1).slice(5, 7), day: +addDays(day, 1).slice(8, 10) } }, windowSizeDays: 1 }) })
  if (r.status === 401) throw new UnauthorizedError("google 401")
  if (!r.ok) return null
  const j = await r.json()
  return (j.rollupDataPoints as Record<string, unknown>[])?.[0] ?? null
}

export const google: VendorAdapter = {
  key: "google",
  name: "Google Health",
  usesPKCE: true,
  scopes: SCOPES,

  authorizeURL({ clientId, redirectUri, state, codeChallenge }) {
    return `${AUTH}?${new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, response_type: "code", scope: SCOPES.join(" "), access_type: "offline", prompt: "consent", include_granted_scopes: "true", state, code_challenge: codeChallenge ?? "", code_challenge_method: "S256" })}`
  },

  async exchangeCode({ code, redirectUri, codeVerifier }) {
    const { clientId, clientSecret } = vendorClient("google")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri, code_verifier: codeVerifier ?? "" })
    const idr = await fetch(`${API}/users/me/identity`, { headers: { Authorization: `Bearer ${t.access_token}` } })
    const id = idr.ok ? await idr.json() : {}
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 3600), scopes: String(t.scope ?? "").split(" ").filter(Boolean), vendorUserId: String(id.healthUserId ?? ""), raw: { legacy_user_id: id.legacyUserId ?? null } }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("google")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret })
    return { accessToken: String(t.access_token), refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 3600) }
  },

  async revoke(tokens) {
    await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(tokens.refreshToken ?? tokens.accessToken)}`, { method: "POST" })
  },

  challengeResponse() {
    return new Response(null, { status: 201 })
  },

  parseWebhook(req, rawBody): WebhookEvent[] | "challenge" {
    const expected = `Bearer ${env("GOOGLE_WEBHOOK_SECRET")}`
    if ((req.headers.get("Authorization") ?? "") !== expected) throw new Error("google subscriber secret mismatch")
    const body = JSON.parse(rawBody)
    if (!Array.isArray(body)) return body?.type === "verification" ? "challenge" : []
    const out: WebhookEvent[] = []
    for (const n of body as { data?: Record<string, unknown> }[]) {
      const d = n.data
      if (!d?.healthUserId) continue
      const intervals = (d.intervals as { physicalTimeInterval?: { startTime?: string; endTime?: string } }[]) ?? []
      const starts = intervals.map((i) => i.physicalTimeInterval?.startTime).filter(Boolean) as string[], ends = intervals.map((i) => i.physicalTimeInterval?.endTime).filter(Boolean) as string[]
      out.push({ vendorUserId: String(d.healthUserId), kind: `${d.dataType}.${d.operation ?? "UPSERT"}`, windowStart: starts.length ? starts.sort()[0].slice(0, 10) : undefined, windowEnd: ends.length ? ends.sort().at(-1)!.slice(0, 10) : undefined })
    }
    return out
  },

  async fetchRange(tokens, start, end) {
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    const dayF = (t: string, day: string) => `${t}.date = "${day}"`
    for (const p of await gget(tokens, "sleep", `sleep.interval.end_time >= "${start}T00:00:00Z" AND sleep.interval.end_time < "${addDays(end, 2)}T00:00:00Z"`, 25)) {
      const s = p.sleep as Record<string, unknown> | undefined
      const meta = (s?.metadata ?? {}) as Record<string, unknown>, iv = (s?.interval ?? {}) as Record<string, unknown>, sm = (s?.summary ?? {}) as Record<string, unknown>
      if (!s || meta.mainSleep !== true || !iv.endTime) continue
      const day = dayOfISO(String(iv.endTime), offsetMinutes(iv.endUtcOffset as string))
      if (day < start || day > end) continue
      const st = Object.fromEntries(((sm.stagesSummary as Record<string, unknown>[]) ?? []).map((x) => [String(x.type), x]))
      const m = (k: string) => st[k] ? (num((st[k] as Record<string, unknown>).minutes) ?? 0) * 60 : null
      const asleep = num(sm.minutesAsleep), period = num(sm.minutesInSleepPeriod)
      dailyRows.push(...dailyMap(day, {
        [T.MainSleepDuration]: asleep != null ? asleep * 60 : null, [T.InBed]: period != null ? period * 60 : null, [T.REM]: m("REM"), [T.Deep]: m("DEEP"), [T.Light]: m("LIGHT"), [T.Awake]: num(sm.minutesAwake) != null ? (num(sm.minutesAwake) as number) * 60 : null,
        [T.Latency]: num(sm.minutesToFallAsleep) != null ? (num(sm.minutesToFallAsleep) as number) * 60 : null, [T.Interruptions]: st.AWAKE ? num((st.AWAKE as Record<string, unknown>).count) : null, [T.SleepEfficiency]: asleep != null && period ? 100 * asleep / period : null,
      }, { details: { type: s.type ?? null, stages_status: meta.stagesStatus ?? null } }))
      dailyRows.push(...compact([dailyDate(day, T.SleepStart, String(iv.startTime)), dailyDate(day, T.SleepEnd, String(iv.endTime))]))
      const stage: Record<string, number> = { DEEP: T.SleepDeepBinary, LIGHT: T.SleepLightBinary, REM: T.SleepREMBinary, AWAKE: T.SleepAwakeBinary, RESTLESS: T.SleepAwakeBinary, ASLEEP: T.SleepLightBinary }
      for (const g of (s.stages as Record<string, unknown>[]) ?? []) { const id = stage[String(g.type)]; if (!id || !g.startTime || !g.endTime) continue; const row = epoch(String(g.startTime), id, (Date.parse(String(g.endTime)) - Date.parse(String(g.startTime))) / 60_000, { endTs: String(g.endTime) }); if (row) epochRows.push(row) }
    }
    for (const day of daysBetween(start, end)) {
      for (const p of await gget(tokens, "daily-resting-heart-rate", dayF("daily_resting_heart_rate", day))) dailyRows.push(...dailyMap(day, { [T.HeartRateResting]: num((p.dailyRestingHeartRate as Record<string, unknown>)?.beatsPerMinute) }))
      for (const p of await gget(tokens, "daily-heart-rate-variability", dayF("daily_heart_rate_variability", day))) {
        const h = (p.dailyHeartRateVariability ?? {}) as Record<string, unknown>, hrv = num(h.averageHeartRateVariabilityMilliseconds)
        dailyRows.push(...dailyMap(day, { [T.RmssdSleep]: hrv, [T.Rmssd]: hrv, [T.HeartRateSleep]: num(h.nonRemHeartRateBeatsPerMinute) }, { details: { statistic: "rmssd", window: "night", deep_rmssd: num(h.deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds) } }))
      }
      for (const p of await gget(tokens, "daily-oxygen-saturation", dayF("daily_oxygen_saturation", day))) dailyRows.push(...dailyMap(day, { [T.SPO2]: num((p.dailyOxygenSaturation as Record<string, unknown>)?.averagePercentage) }))
      for (const p of await gget(tokens, "daily-respiratory-rate", dayF("daily_respiratory_rate", day))) dailyRows.push(...dailyMap(day, { [T.RespirationRateSleep]: num((p.dailyRespiratoryRate as Record<string, unknown>)?.breathsPerMinute) }))
      for (const p of await gget(tokens, "daily-sleep-temperature-derivations", dayF("daily_sleep_temperature_derivations", day))) {
        const t = (p.dailySleepTemperatureDerivations ?? {}) as Record<string, unknown>, n = num(t.nightlyTemperatureCelsius), b = num(t.baselineTemperatureCelsius)
        dailyRows.push(...dailyMap(day, { [T.SkinTemperature]: n, [T.SkinTemperatureDeviation]: n != null && b != null ? n - b : null }, { details: { baseline: b } }))
      }
      for (const p of await gget(tokens, "daily-vo2-max", dayF("daily_vo2_max", day))) dailyRows.push(...dailyMap(day, { [T.VO2max]: num((p.dailyVo2Max as Record<string, unknown>)?.vo2Max) }))
      const [st, di, ae, tc] = await Promise.all([rollup(tokens, "steps", day), rollup(tokens, "distance", day), rollup(tokens, "active-energy-burned", day), rollup(tokens, "total-calories", day)])
      const dist = num((di?.distance as Record<string, unknown>)?.millimetersSum)
      dailyRows.push(...dailyMap(day, { [T.Steps]: num((st?.steps as Record<string, unknown>)?.countSum), [T.CoveredDistance]: dist != null ? dist / 1000 : null, [T.ActiveBurnedCalories]: num((ae?.activeEnergyBurned as Record<string, unknown>)?.kcalSum), [T.BurnedCalories]: num((tc?.totalCalories as Record<string, unknown>)?.kcalSum) }))
    }
    for (const p of await gget(tokens, "weight", `weight.sample_time.physical_time >= "${start}T00:00:00Z" AND weight.sample_time.physical_time < "${addDays(end, 1)}T00:00:00Z"`)) {
      const w = (p.weight ?? {}) as Record<string, unknown>, ts = String((w.sampleTime as Record<string, unknown>)?.physicalTime ?? ""), g = num(w.weightGrams)
      if (ts && g != null) { const row = epoch(ts, T.Weight, g / 1000); if (row) { epochRows.push(row); dailyRows.push(...dailyMap(ts.slice(0, 10), { [T.Weight]: g / 1000 })) } }
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}
