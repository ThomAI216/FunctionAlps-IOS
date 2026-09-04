// Polar AccessLink v3 — spec §4 (tier B). Basic client auth at the token endpoint, mandatory user
// registration (`POST /v3/users`), long-lived tokens (v3: no refresh → a 401 means re-consent), one
// application-level webhook whose secret is returned once (POLAR_WEBHOOK_SECRET).
import { type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent, T, UnauthorizedError, compact, dailyDate, dailyMap, daysBetween, env, epoch, hmacSha256, mean, num, randomToken, timingSafeEqual, tokenPost, unixOf, vendorClient } from "./core.ts"

const AUTH = "https://flow.polar.com/oauth2/authorization"
const TOKEN = "https://polarremote.com/v2/oauth2/token"
const API = "https://www.polaraccesslink.com"

async function pget(path: string, tokens: TokenSet): Promise<Record<string, unknown> | null> {
  const r = await fetch(API + path, { headers: { Authorization: `Bearer ${tokens.accessToken}`, Accept: "application/json" } })
  if (r.status === 401 || r.status === 403) throw new UnauthorizedError(`polar ${r.status}`)
  if (r.status === 204 || r.status === 404) return null
  const text = await r.text()
  if (!r.ok) throw new Error(`polar GET ${path} ${r.status}: ${text.slice(0, 200)}`)
  return text ? JSON.parse(text) : null
}

/** `{ "HH:MM": value }` clock series anchored at `startIso` (wraps past midnight). */
function clockSeries(id: number, samples: Record<string, unknown> | undefined, startIso: string | undefined, extra: Record<string, unknown> = {}): EpochRow[] {
  if (!samples || !startIso) return []
  const startT = Date.parse(startIso), startDay = startIso.slice(0, 10)
  const out: EpochRow[] = []
  for (const [hhmm, v] of Object.entries(samples)) {
    const [h, m] = hhmm.split(":").map(Number)
    let t = Date.parse(`${startDay}T${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:00${startIso.slice(19) || "Z"}`)
    if (t < startT - 3_600_000) t += 86_400_000
    const row = epoch(new Date(t).toISOString(), id, num(v), { details: extra })
    if (row) out.push(row)
  }
  return out
}

const isoMinutes = (d: unknown): number | null => {
  if (typeof d !== "string") return null
  const m = /P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?/.exec(d)
  if (!m) return null
  return (Number(m[1] ?? 0) * 1440) + (Number(m[2] ?? 0) * 60) + Number(m[3] ?? 0) + Number(m[4] ?? 0) / 60
}

export const polar: VendorAdapter = {
  key: "polar",
  name: "Polar",
  usesPKCE: false,
  scopes: ["accesslink.read_all"],

  authorizeURL({ clientId, redirectUri, state }) {
    return `${AUTH}?${new URLSearchParams({ response_type: "code", client_id: clientId, redirect_uri: redirectUri, scope: "accesslink.read_all", state })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("polar")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri }, { basic: { id: clientId, secret: clientSecret } })
    const exp = num(t.expires_in)
    return { accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined, expiresAt: exp ? Math.floor(Date.now() / 1000) + exp : undefined, scopes: polar.scopes, vendorUserId: String(t.x_user_id ?? "") }
  },

  async refresh(refreshToken) {
    if (!refreshToken) throw new UnauthorizedError("polar v3 tokens do not refresh — reconnect")
    const { clientId, clientSecret } = vendorClient("polar")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken }, { basic: { id: clientId, secret: clientSecret } })
    const exp = num(t.expires_in)
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string) ?? refreshToken, expiresAt: exp ? Math.floor(Date.now() / 1000) + exp : undefined }
  },

  async revoke(tokens) {
    if (!tokens.vendorUserId) return
    await fetch(`${API}/v3/users/${tokens.vendorUserId}`, { method: "DELETE", headers: { Authorization: `Bearer ${tokens.accessToken}` } })
  },

  async afterConnect(tokens) {
    // Registration is mandatory before any data flows; 409 = already registered. member-id = an unguessable alias.
    const memberId = randomToken(18)
    const r = await fetch(`${API}/v3/users`, { method: "POST", headers: { Authorization: `Bearer ${tokens.accessToken}`, "Content-Type": "application/json", Accept: "application/json" }, body: JSON.stringify({ "member-id": memberId }) })
    if (![200, 201, 409].includes(r.status)) throw new Error(`polar register ${r.status}: ${(await r.text()).slice(0, 200)}`)
    const meta: Record<string, unknown> = { member_id: memberId, registered_status: r.status }
    if (r.status !== 409) {
      try { const u = await r.json(); meta.polar_user_id = u["polar-user-id"] ?? null; meta.registration_date = u["registration-date"] ?? null } catch { /* fine */ }
    }
    return { vendorUserId: tokens.vendorUserId || (meta.polar_user_id ? String(meta.polar_user_id) : undefined), meta }
  },

  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    const e = JSON.parse(rawBody) as Record<string, unknown>
    if (e.event === "PING") return []                      // the creation ping — must be 200 before any secret exists
    const secret = env("POLAR_WEBHOOK_SECRET")
    const sig = (req.headers.get("Polar-Webhook-Signature") ?? "").toLowerCase()
    const mac = await hmacSha256(secret, rawBody, "hex")
    if (!sig || !timingSafeEqual(mac, sig)) throw new Error("polar signature mismatch")
    if (e.user_id == null) return []
    const date = typeof e.date === "string" ? e.date.slice(0, 10) : undefined
    return [{ vendorUserId: String(e.user_id), kind: String(e.event ?? "event"), windowStart: date ?? (typeof e.from === "string" ? e.from.slice(0, 10) : undefined), windowEnd: date ?? (typeof e.to === "string" ? e.to.slice(0, 10) : undefined) }]
  },

  async fetchRange(tokens, start, end) {
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    for (const day of daysBetween(start, end)) {
      const s = await pget(`/v3/users/sleep/${day}`, tokens)
      if (s) {
        const light = num(s.light_sleep) ?? 0, deep = num(s.deep_sleep) ?? 0, rem = num(s.rem_sleep) ?? 0
        const st = s.sleep_start_time as string | undefined, en = s.sleep_end_time as string | undefined
        dailyRows.push(...dailyMap(day, {
          [T.MainSleepDuration]: light + deep + rem || null, [T.InBed]: st && en ? unixOf(en) - unixOf(st) : null, [T.REM]: rem || null, [T.Deep]: deep || null, [T.Light]: light || null,
          [T.Awake]: num(s.total_interruption_duration), [T.AwakeAfterWakeup]: num(s.total_interruption_duration), [T.SleepQuality]: num(s.sleep_score), [T.SleepScore]: num(s.sleep_score), [T.SleepIntensity]: num(s.continuity),
        }, { details: { cycles: num(s.sleep_cycles), sleep_charge: num(s.sleep_charge), continuity_class: num(s.continuity_class), device_id: s.device_id ?? null } }))
        dailyRows.push(...compact([dailyDate(day, T.SleepStart, st), dailyDate(day, T.SleepEnd, en)]))
        const hr = clockSeries(T.HeartRate, s.heart_rate_samples as Record<string, unknown>, st, { source: "sleep" })
        epochRows.push(...hr)
        const lowest = hr.length ? Math.min(...hr.map((r) => r.value as number)) : null
        dailyRows.push(...dailyMap(day, { [T.HeartRateSleepLowest]: lowest, [T.HeartRateResting]: lowest }, { details: { proxy: "min_sleep_hr" } }))
        const hyp = s.hypnogram as Record<string, unknown> | undefined
        if (hyp && st) {
          const map: Record<number, number> = { 0: T.SleepAwakeBinary, 1: T.SleepREMBinary, 2: T.SleepLightBinary, 3: T.SleepLightBinary, 4: T.SleepDeepBinary }
          for (const row of clockSeries(T.SleepAwakeBinary, hyp, st)) { const id = map[row.value as number]; if (id) epochRows.push({ ...row, dataTypeId: id, dataTypeName: String(id), value: 5 }) }
        }
      }
      const n = await pget(`/v3/users/nightly-recharge/${day}`, tokens)
      if (n) {
        const hrv = num(n.heart_rate_variability_avg)
        dailyRows.push(...dailyMap(day, { [T.RmssdSleep]: hrv, [T.Rmssd]: hrv, [T.HeartRateSleep]: num(n.heart_rate_avg), [T.RespirationRateSleep]: num(n.breathing_rate_avg), [T.ANSCharge]: num(n.ans_charge), [T.RecoveryScore]: num(n.nightly_recharge_status) },
          { details: { statistic: "rmssd", window: "4h_after_onset", ans_charge_status: num(n.ans_charge_status), beat_to_beat_avg: num(n.beat_to_beat_avg), recovery_scale: "nightly_recharge_status_1_6" } }))
        const st = (s?.sleep_start_time as string | undefined) ?? `${day}T00:00:00Z`
        epochRows.push(...clockSeries(T.Rmssd, n.hrv_samples as Record<string, unknown>, st, { statistic: "rmssd" }), ...clockSeries(T.RespirationRate, n.breathing_samples as Record<string, unknown>, st))
      }
      const a = await pget(`/v3/users/activities/${day}?steps=true&activity_zones=true`, tokens)
      if (a) {
        dailyRows.push(...dailyMap(day, { [T.Steps]: num(a.steps), [T.CoveredDistance]: num(a.distance_from_steps), [T.BurnedCalories]: num(a.calories), [T.ActiveBurnedCalories]: num(a.active_calories), [T.ActivityDuration]: isoMinutes(a.active_duration) }, { details: { daily_activity_pct: num(a.daily_activity) } }))
        const steps = ((a.samples as Record<string, unknown>)?.steps as Record<string, unknown> | undefined)
        for (const sm of (steps?.samples as Record<string, unknown>[]) ?? []) { const row = epoch(String(sm.timestamp), T.Steps, num(sm.steps)); if (row) epochRows.push(row) }
      }
      const c = await pget(`/v3/users/continuous-heart-rate/${day}`, tokens)
      for (const h of (c?.heart_rate_samples as Record<string, unknown>[]) ?? []) { const row = epoch(`${day}T${h.sample_time}Z`, T.HeartRate, num(h.heart_rate), { details: { source: "continuous" } }); if (row) epochRows.push(row) }
    }
    // Exercises (last 30 days, post-registration) + physical info: once per range.
    try {
      const ex = await fetch(`${API}/v3/exercises`, { headers: { Authorization: `Bearer ${tokens.accessToken}`, Accept: "application/json" } })
      if (ex.ok) for (const e of ((await ex.json()) as Record<string, unknown>[]) ?? []) {
        const startTs = String(e.start_time), day = startTs.slice(0, 10)
        if (day < start || day > end) continue
        const hr = (e.heart_rate ?? {}) as Record<string, unknown>
        epochRows.push(...compact([
          epoch(startTs, T.ActivityType, 0, { valueText: String(e.sport ?? e.detailed_sport_info ?? ""), valueType: "STRING", details: { exercise_id: e.id, duration_min: isoMinutes(e.duration), training_load: num(e.training_load) } }),
          epoch(startTs, T.ActiveBurnedCalories, num(e.calories), { details: { workout: true } }), epoch(startTs, T.CoveredDistance, num(e.distance), { details: { workout: true } }),
          epoch(startTs, T.HeartRate, num(hr.average), { details: { workout: true, max: num(hr.maximum) } }),
        ]))
      }
      const pi = await pget("/v3/users/physical-info", tokens)
      if (pi) dailyRows.push(...dailyMap(end, { [T.Weight]: num(pi.weight), [T.Height]: num(pi.height), [T.VO2max]: num(pi.vo2_max) }, { details: { source: "polar_setting" } }))
    } catch (e) { console.warn("[polar] exercises/physical", String(e).slice(0, 120)) }
    return { daily: dailyRows, epoch: epochRows }
  },
}

export const _polarTest = { clockSeries, isoMinutes, mean }
