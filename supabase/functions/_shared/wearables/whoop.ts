// WHOOP API v2 — strategy 2026-09-14, Phase 2 (this adapter corrected against the research corpus,
// `.context/research/2026-09-14_wearables-implementation/vendors/whoop.md`, cited below as "whoop.md §n").
//
// What the corpus establishes (official docs retrieved 2026-09-14, whoop.md §31):
//   • OAuth: code flow, form-encoded token POST, `offline` scope for a refresh token, rotating refresh
//     (old access + refresh invalidated, concurrent refreshes fail) — §6–§8. PKCE is NOT DOCUMENTED (§6):
//     we do not send unverified PKCE parameters, hence `pkce: "not_documented"`.
//   • Identity: integer `user_id` from `GET /v2/user/profile/basic`, stored stringified (§9).
//   • Webhooks: app-level, v2 body `{user_id, id, type, trace_id}`; types `workout|sleep|recovery.updated|deleted`;
//     triggers only — no cycle / body-measurement webhook, so `/v2/cycle` is polled (§10, §16).
//   • Signature: `X-WHOOP-Signature` = Base64(HMAC-SHA256(client_secret, timestampHeader ‖ rawBody)),
//     `X-WHOOP-Signature-Timestamp` in ms; constant-time compare (§11, security/webhook-verification.md "WHOOP").
//     No replay-age window is documented and WHOOP retries failed deliveries for ~1 h, so an old timestamp is
//     LOGGED (skew), never rejected; `trace_id` is the idempotency key → `WebhookEvent.eventId`.
//   • Pagination: `limit` ≤ 25, `start` inclusive / `end` exclusive, `nextToken` → `next_token`, newest first (§13).
//   • Rate limit 100/min, 10 000/day (§14). Reconcile: 7 days nightly, 30 days weekly (§17).
//   • Metric map (§18, metrics/canonical-metric-map.md rows "WHOOP"): recovery `hrv_rmssd_milli` → RmssdSleep 3106
//     ONLY (no SDNN/SDRR/epoch RMSSD may be synthesised, §20 + 07_HRV.md "WHOOP — strong mapping");
//     `resting_heart_rate` → 3001; `spo2_percentage` → 3009; `skin_temp_celsius` → 5041; `recovery_score` → 1000101;
//     cycle/workout `strain` → 1000102; stage `*_milli` → sleep duration ids after `ms_to_s`;
//     `sleep_performance_percentage` → WHOOPSleepPerformance (catalogue v2 id 1000133 — the corpus proposed 1000116
//     before the block moved to 1000130+), NOT SleepScore 1000105 and not generic SleepQuality;
//     `sleep_efficiency_percentage` → 2200; `respiratory_rate` → 4002; workout `distance_meter` → 1001,
//     `altitude_gain_meter` → 1003. `disturbance_count`, sleep cycle count and sleep-needed stay in metadata (§19).
//   • `score_state != "SCORED"` (PENDING_SCORE / UNSCORABLE) is not zero: the record is skipped and re-pulled by
//     reconciliation (§24, 14_RECOVERY_READINESS_STRAIN.md "WHOOP").
//   • Day key: WHOOP exposes no `sleepDate`; the sleep's local wake date (end + timezone_offset) is the derived day
//     (§21). Recovery and cycle rows are keyed to the day of their linked sleep so recovery / strain / sleep land on
//     the same member-day; `details.day_basis` says which rule produced the key.
//
// VERIFY on the first live capture (the corpus names the resources, not every field): workout `sport_name` and
// `zone_durations.zone_{zero..five}_milli`, sleep `stage_summary.total_no_data_time_milli`, recovery `user_calibrating`.
import {
  type AccountContext, type DailyRow, type EpochRow, type TokenSet, type VendorAdapter, type WebhookEvent,
  T, addDays, compact, dailyDate, dailyMap, dayEndISO, dayOfISO, dayStartISO, epoch, getJSON, hmacSha256, num, offsetMinutes, timingSafeEqual, tokenPost, vendorClient,
} from "./core.ts"
import { log } from "./log.ts"

const FN = "whoop"
const AUTH = "https://api.prod.whoop.com/oauth/oauth2/auth"
const TOKEN = "https://api.prod.whoop.com/oauth/oauth2/token"
const API = "https://api.prod.whoop.com/developer"

/** Above this the skew between WHOOP's signature timestamp and our clock is logged at `warn` (still accepted). */
const SKEW_WARN_MS = 300_000

type Rec = Record<string, unknown>
const obj = (v: unknown): Rec => (v && typeof v === "object" ? (v as Rec) : {})
const str = (v: unknown): string | null => (v == null ? null : String(v))

/** Collection pages: `limit` ≤ 25, `nextToken` in, `next_token` out, the range constant (whoop.md §13). */
async function records(path: string, tokens: TokenSet, q: Record<string, string>): Promise<Rec[]> {
  const out: Rec[] = []
  let next = ""
  for (let i = 0; i < 40; i++) {
    const qs = new URLSearchParams({ ...q, limit: "25", ...(next ? { nextToken: next } : {}) })
    const j = await getJSON(`${API}${path}?${qs}`, { Authorization: `Bearer ${tokens.accessToken}` })
    out.push(...((j.records as Rec[]) ?? []))
    next = (j.next_token as string) ?? ""
    if (!next) break
  }
  return out
}

/** WHOOP energy is kilojoules; the catalogue's 1010/1011 are integer kcal. */
const kcal = (kj: unknown) => { const v = num(kj); return v == null ? null : Math.round(v / 4.184) }
/** `ms_to_s` (whoop.md §22): stage durations are milliseconds, the sleep duration ids are integer seconds. */
const msToS = (ms: unknown) => { const v = num(ms); return v == null ? null : Math.round(v / 1000) }
/** Zone durations are milliseconds; 3090–3093 are integer minutes. Sub-minute buckets round to 0 and are dropped. */
const msToMin = (ms: number) => Math.round(ms / 60_000) || null

/**
 * HR-zone bucket mapping (05_WORKOUTS_AND_HR_ZONES.md "HR zones": prefer vendor duration-in-zone, keep the
 * threshold definition in metadata; "Catalogue": 3090–3093 retain the project definitions, semantics documented here).
 * WHOOP reports six buckets of the member's max HR — zone 0 (< 50 %), 1 (50–60 %), 2 (60–70 %), 3 (70–80 %),
 * 4 (80–90 %), 5 (90–100 %) — as `score.zone_durations.zone_{zero..five}_milli` (VERIFY: field names and the
 * percentage bands are not pinned in the corpus; they are WHOOP's published zone model as of 2026-09).
 * Project buckets: Light 3090 = zones 1+2 · Moderate 3091 = zone 3 · Intense 3092 = zone 4 · Maximal 3093 = zone 5.
 * Zone 0 is below any training zone and stays in metadata only. Zones from other vendors' threshold models must
 * never be summed with these (same doc, "Do not combine vendor zones").
 */
const ZONE_MODEL = "whoop_percent_max_hr_6_buckets"
function hrZones(z: Rec): { light: number | null; moderate: number | null; intense: number | null; maximal: number | null; raw: Record<string, number | null> } {
  const ms = (k: string) => num(z[k])
  const raw = { zone_zero_milli: ms("zone_zero_milli"), zone_one_milli: ms("zone_one_milli"), zone_two_milli: ms("zone_two_milli"), zone_three_milli: ms("zone_three_milli"), zone_four_milli: ms("zone_four_milli"), zone_five_milli: ms("zone_five_milli") }
  return {
    light: msToMin((raw.zone_one_milli ?? 0) + (raw.zone_two_milli ?? 0)),
    moderate: msToMin(raw.zone_three_milli ?? 0),
    intense: msToMin(raw.zone_four_milli ?? 0),
    maximal: msToMin(raw.zone_five_milli ?? 0),
    raw,
  }
}

export const whoop: VendorAdapter = {
  key: "whoop",
  name: "WHOOP",
  pkce: "not_documented",  // whoop.md §6 — do not send unverified PKCE parameters
  scopes: ["offline", "read:profile", "read:body_measurement", "read:cycles", "read:recovery", "read:sleep", "read:workout"],
  reconcile: { nightlyDays: 7, weeklyDays: 30 },  // whoop.md §17

  authorizeURL({ clientId, redirectUri, state }) {
    return `${AUTH}?${new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, response_type: "code", scope: whoop.scopes.join(" "), state })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("whoop")
    const t = await tokenPost(TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri, client_id: clientId, client_secret: clientSecret })
    const me = await getJSON(`${API}/v2/user/profile/basic`, { Authorization: `Bearer ${t.access_token}` })
    return {
      accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined,
      expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 3600),
      scopes: String(t.scope ?? "").split(" ").filter(Boolean), vendorUserId: String(me.user_id ?? ""),
    }
  },

  async refresh(refreshToken) {
    // Rotating: the reply carries a NEW refresh token and the old pair is dead (whoop.md §8). `scope=offline` keeps it rotating.
    const { clientId, clientSecret } = vendorClient("whoop")
    const t = await tokenPost(TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret, scope: "offline" })
    return { accessToken: String(t.access_token), refreshToken: (t.refresh_token as string) ?? refreshToken, expiresAt: Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 3600) }
  },

  async revoke(tokens) {
    // whoop.md §25 — WHOOP states revocation also stops that user's webhooks.
    await fetch(`${API}/v2/user/access`, { method: "DELETE", headers: { Authorization: `Bearer ${tokens.accessToken}` } })
  },

  async afterConnect(tokens) {
    // Webhooks are app-level (dashboard), nothing to register per user (whoop.md §10, §23). Body measurements → meta.
    try {
      const b = await getJSON(`${API}/v2/user/measurement/body`, { Authorization: `Bearer ${tokens.accessToken}` })
      return { meta: { height_m: num(b.height_meter), weight_kg: num(b.weight_kilogram), max_heart_rate: num(b.max_heart_rate) } }
    } catch { return {} }
  },

  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    const { clientSecret } = vendorClient("whoop")
    const ts = req.headers.get("X-WHOOP-Signature-Timestamp") ?? "", sig = req.headers.get("X-WHOOP-Signature") ?? ""
    if (!ts || !sig) throw new Error("whoop signature headers missing")
    // Signed bytes = timestamp header ‖ raw body, HMAC-SHA256 with the client secret, Base64 (whoop.md §11).
    const mac = await hmacSha256(clientSecret, ts + rawBody, "base64")
    if (!timingSafeEqual(mac, sig)) throw new Error("whoop signature mismatch")
    const e = JSON.parse(rawBody) as Rec
    const kind = String(e.type ?? "event"), eventId = str(e.trace_id)
    // No documented replay window; WHOOP retries for ~1 h and duplicates are deduped on trace_id (§11). Log the skew only.
    const skewMs = Number.isFinite(Number(ts)) ? Date.now() - Number(ts) : null
    log(skewMs != null && Math.abs(skewMs) > SKEW_WARN_MS ? "warn" : "info", "whoop.webhook_skew", { fn: FN, vendor: "whoop", kind, skewMs, hasTraceId: eventId != null })
    if (e.user_id == null) return []
    // `id` is the sleep/workout UUID (for recovery.* the UUID of the associated sleep, §10). The contract carries a day
    // window, not a resource id, so the sync re-pulls the default window; the exact-resource GET is a later refinement.
    return [{ vendorUserId: String(e.user_id), kind, eventId }]
  },

  async fetchRange(tokens, start, end, _ctx: AccountContext) {
    // Sleeps are keyed by wake day, cycles start the evening before: one extra day each side, then filter by local day.
    const q = { start: dayStartISO(addDays(start, -1)), end: dayEndISO(addDays(end, 1)) }
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    const inRange = (d: string) => d >= start && d <= end
    const sleepDay = new Map<string, string>()      // sleep id → wake day
    const cycleSleepDay = new Map<string, string>() // cycle id → wake day of its sleep
    const cycleStartDay = new Map<string, string>() // cycle id → start day (fallback)

    // ── Sleep (whoop.md §19, §21; 08_SLEEP.md "WHOOP": `nap` is explicit) ─────────────────────────────────────
    for (const s of await records("/v2/activity/sleep", tokens, q)) {
      if (s.nap === true || s.score_state !== "SCORED" || !s.end) continue
      const off = offsetMinutes(s.timezone_offset as string), day = dayOfISO(String(s.end), off), id = String(s.id)
      sleepDay.set(id, day)
      if (s.cycle_id != null) cycleSleepDay.set(String(s.cycle_id), day)
      if (!inRange(day)) continue
      const sc = obj(s.score), g = obj(sc.stage_summary), need = obj(sc.sleep_needed)
      const light = msToS(g.total_light_sleep_time_milli) ?? 0, sws = msToS(g.total_slow_wave_sleep_time_milli) ?? 0, rem = msToS(g.total_rem_sleep_time_milli) ?? 0
      const prov: Partial<DailyRow> = {
        timezoneOffset: off, sourceRecordId: id, sourceResourceType: "sleep", sourceModifiedAt: str(s.updated_at),
        details: {
          day_basis: "sleep_end_local", cycle_id: str(s.cycle_id), score_state: "SCORED",
          // Metadata, never canonical ids (§19): disturbances, sleep cycles, sleep need, no-data time.
          disturbance_count: num(g.disturbance_count), sleep_cycle_count: num(g.sleep_cycle_count), total_no_data_time_milli: num(g.total_no_data_time_milli),
          sleep_consistency_percentage: num(sc.sleep_consistency_percentage),
          sleep_needed: Object.keys(need).length ? need : null,
        },
      }
      dailyRows.push(...dailyMap(day, {
        [T.MainSleepDuration]: light + sws + rem || null, [T.InBed]: msToS(g.total_in_bed_time_milli) || null,
        [T.REM]: rem, [T.Deep]: sws, [T.Light]: light, [T.Awake]: msToS(g.total_awake_time_milli),
        [T.SleepEfficiency]: num(sc.sleep_efficiency_percentage),
        [T.WHOOPSleepPerformance]: num(sc.sleep_performance_percentage),  // vendor-only, NOT SleepScore / SleepQuality
        [T.RespirationRateSleep]: num(sc.respiratory_rate),
      }, prov))
      dailyRows.push(...compact([dailyDate(day, T.SleepStart, String(s.start), prov), dailyDate(day, T.SleepEnd, String(s.end), prov)]))
    }

    // ── Cycle (whoop.md §12, §16: no webhook, always polled) ──────────────────────────────────────────────────
    const cycles = await records("/v2/cycle", tokens, q)
    for (const c of cycles) cycleStartDay.set(String(c.id), dayOfISO(String(c.start), offsetMinutes(c.timezone_offset as string)))
    for (const c of cycles) {
      if (!c.end || c.score_state !== "SCORED") continue
      const id = String(c.id), off = offsetMinutes(c.timezone_offset as string)
      const linked = cycleSleepDay.get(id), day = linked ?? cycleStartDay.get(id)!
      if (!inRange(day)) continue
      const sc = obj(c.score)
      dailyRows.push(...dailyMap(day, { [T.StrainScore]: num(sc.strain), [T.BurnedCalories]: kcal(sc.kilojoule), [T.HeartRate]: num(sc.average_heart_rate) }, {
        timezoneOffset: off, sourceRecordId: id, sourceResourceType: "cycle", sourceModifiedAt: str(c.updated_at),
        details: { day_basis: linked ? "linked_sleep_end_local" : "cycle_start_local", max_heart_rate: num(sc.max_heart_rate), cycle_start: str(c.start), cycle_end: str(c.end), score_state: "SCORED" },
      }))
    }

    // ── Recovery (whoop.md §18, §20, §22; 07_HRV.md "WHOOP — strong mapping") ─────────────────────────────────
    for (const r of await records("/v2/recovery", tokens, q)) {
      if (r.score_state !== "SCORED") continue
      const cycleId = String(r.cycle_id), sleepId = str(r.sleep_id)
      const day = (sleepId ? sleepDay.get(sleepId) : undefined) ?? cycleSleepDay.get(cycleId) ?? cycleStartDay.get(cycleId)
      if (!day || !inRange(day)) continue
      const sc = obj(r.score)
      dailyRows.push(...dailyMap(day, {
        [T.RmssdSleep]: num(sc.hrv_rmssd_milli),  // RMSSD ms, sleep-linked → 3106 only; nothing else is derived from it (§20)
        [T.HeartRateResting]: num(sc.resting_heart_rate), [T.SPO2]: num(sc.spo2_percentage), [T.SkinTemperature]: num(sc.skin_temp_celsius), [T.RecoveryScore]: num(sc.recovery_score),
      }, {
        sourceRecordId: cycleId, sourceResourceType: "recovery", sourceModifiedAt: str(r.updated_at),
        details: { day_basis: "linked_sleep_end_local", sleep_id: sleepId, statistic: "rmssd", window: "night", user_calibrating: r.score == null ? null : (sc.user_calibrating ?? null), score_state: "SCORED" },
      }))
    }

    // ── Workout (whoop.md §12, §18; 05_WORKOUTS_AND_HR_ZONES.md) — EPOCH rows keyed by the workout UUID ──────────
    for (const w of await records("/v2/activity/workout", tokens, q)) {
      if (w.score_state !== "SCORED" || !w.start) continue
      const id = String(w.id), off = offsetMinutes(w.timezone_offset as string), startTs = String(w.start), endTs = str(w.end)
      if (!inRange(dayOfISO(startTs, off))) continue
      const sc = obj(w.score), zones = hrZones(obj(sc.zone_durations))
      const prov: Partial<EpochRow> = { endTs, timezoneOffset: off, sourceRecordId: id, sourceResourceType: "workout", sourceModifiedAt: str(w.updated_at) }
      const zoneMeta = { zone_model: ZONE_MODEL, zone_durations_milli: zones.raw }
      epochRows.push(...compact([
        epoch(startTs, T.ActivityType, 0, { ...prov, valueText: str(w.sport_name) ?? "", valueType: "STRING", details: { sport_name: str(w.sport_name), sport_id: num(w.sport_id), percent_recorded: num(sc.percent_recorded), score_state: "SCORED" } }),
        epoch(startTs, T.StrainScore, num(sc.strain), { ...prov, details: { scope: "workout" } }),
        epoch(startTs, T.ActiveBurnedCalories, kcal(sc.kilojoule), { ...prov, details: { workout: true } }),
        epoch(startTs, T.HeartRate, num(sc.average_heart_rate), { ...prov, details: { workout: true, max_heart_rate: num(sc.max_heart_rate) } }),
        epoch(startTs, T.CoveredDistance, num(sc.distance_meter), { ...prov, details: { workout: true } }),
        epoch(startTs, T.ElevationGain, num(sc.altitude_gain_meter), { ...prov, details: { workout: true, altitude_change_meter: num(sc.altitude_change_meter) } }),
        epoch(startTs, T.HRZoneLight, zones.light, { ...prov, details: { ...zoneMeta, buckets: ["zone_one", "zone_two"] } }),
        epoch(startTs, T.HRZoneModerate, zones.moderate, { ...prov, details: { ...zoneMeta, buckets: ["zone_three"] } }),
        epoch(startTs, T.HRZoneIntense, zones.intense, { ...prov, details: { ...zoneMeta, buckets: ["zone_four"] } }),
        epoch(startTs, T.HRZoneMaximal, zones.maximal, { ...prov, details: { ...zoneMeta, buckets: ["zone_five"] } }),
      ]))
    }
    log("info", "whoop.fetch_range", { fn: FN, vendor: "whoop", start, end, daily: dailyRows.length, epoch: epochRows.length })
    return { daily: dailyRows, epoch: epochRows }
  },
}
