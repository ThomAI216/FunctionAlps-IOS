// Polar Dynamic API v4 — strategy 2026-09-14 Phase 2 (D4, D10), rebuilt from the corpus
// `.context/research/2026-09-14_wearables-implementation/vendors/polar.md` (the authority; § numbers below refer to it).
//
// What the corpus pins (and this file relies on):
//   • §6/§7/§8  hosts: authorize + token at `auth.polar.com`, HTTP Basic client auth at the token endpoint, refresh via
//               `grant_type=refresh_token`; `expires_in` from the response (~43199 s), never a hardcoded 12 h.
//   • §6        granular, space-delimited `<family>:read` scopes; PKCE NOT DOCUMENTED → `pkce: "not_documented"`.
//   • §9        identity = the v4 profile call, never the v3 `x_user_id`; no `/v3/users` registration (§28: v4 only).
//   • §12/§13/§21  data base `www.polaraccesslink.com/v4/data`; `nightly-recharge-results`, `sleeps`, `ppi-samples`
//               take `from` (inclusive) / `to` (EXCLUSIVE) dates; range-based, not cursor-paginated.
//   • §15       28-day maximum range without `features=samples`, ONE day when samples are requested → `rangeChunks`.
//   • §18/§20/§30  `meanNightlyRecoveryRmssd` is semantically RMSSD but its v4 UNIT IS NOT PINNED → raw-only in
//               `details` (VERIFY), NOT written to 3106. `ansStatus` → 1000132 (numeric only; never coerced when
//               categorical). PPI `ppInterval` is pinned as ms → FunctionAlps-derived RMSSD (`functionalps_rmssd_v1`) → 3100.
//   • §19       sleep: `sleepDate` is the vendor day (wake/end day), canonical uses the CURRENT `sleepResult`, never
//               `originalSleepResult` (§16); efficiency % → 2200 DIRECT; `sleepScore` → 1000105 VENDOR-ONLY;
//               stage durations "verify v4 unit" → raw-only.
//   • §10/§11   webhooks are the v3 AccessLink mechanism (`Polar-Webhook-Signature` HMAC-SHA256 lowercase hex over the
//               raw body with the once-returned `signature_secret_key` = POLAR_WEBHOOK_SECRET (D10); `Polar-Webhook-Event`
//               is the category; PING must be acknowledged). v3-webhook/v4-data compatibility is UNCONFIRMED → the whole
//               parse path sits behind `POLAR_WEBHOOKS_ENABLED=1` (§28 "feature-flag v3 webhook").
//   • §25       revocation "REQUIRES PORTAL VERIFICATION" → `revoke` stays undefined; the webhook is app-level → no `unsubscribe`.
//   • §17       reconcile nightly 3 days / weekly 14 days (inside the 28-day range).
// Field names inside the v4 records are NOT captured by the corpus beyond those listed in §12/§18/§19 — every other key
// this file reads is marked VERIFY and mirrored in tests/fixtures/polar/*.json `_note`.
import { type DailyRow, type EpochRow, type RowBatch, type TokenSet, type VendorAdapter, type WebhookEvent, T, VendorHttpError, addDays, compact, daily, dailyDate, dailyText, daysBetween, env, epoch, getJSON, hmacSha256, num, offsetMinutes, timingSafeEqual, tokenPost, vendorClient } from "./core.ts"
import { log } from "./log.ts"

export const POLAR_AUTH = "https://auth.polar.com/oauth/authorize"          // §6
export const POLAR_TOKEN = "https://auth.polar.com/oauth/token"             // §7
export const POLAR_DATA = "https://www.polaraccesslink.com/v4/data"         // §12
/** VERIFY (§9/§12): the profile family exists under /v4/data; the exact path + identity field need the live v4 schema. */
export const POLAR_PROFILE = `${POLAR_DATA}/profile`

/** §15: 28 days without samples; 1 day with `features=samples`. Sleep maximum is not pinned (§15) → same 28 (VERIFY). */
export const NIGHTLY_MAX_DAYS = 28
export const SLEEPS_MAX_DAYS = 28
export const SAMPLES_MAX_DAYS = 1

/** §6: space-delimited `<family>:read`. `ppi:read` follows the documented family list ("PPI") + pattern — VERIFY the literal. */
const SCOPES = ["profile:read", "sleep:read", "nightly_recharge:read", "ppi:read", "activity:read", "continuous_samples:read", "training_sessions:read"]

// MARK: - Pure helpers (exported through _polarTest)

type Rec = Record<string, unknown>
const isRec = (v: unknown): v is Rec => typeof v === "object" && v != null && !Array.isArray(v)
const str = (v: unknown): string | null => (typeof v === "string" && v ? v : typeof v === "number" ? String(v) : null)

/** First present key of `keys` in `obj` (the v4 field names are only partly pinned → ordered candidates, VERIFY). */
function first(obj: Rec | null | undefined, keys: string[]): unknown {
  if (!obj) return undefined
  for (const k of keys) if (obj[k] !== undefined && obj[k] !== null) return obj[k]
  return undefined
}

/** A v4 collection body: a bare array, or a wrapper object whose first array-valued key is the collection (VERIFY §13). */
function unwrap(body: unknown, preferred: string[]): Rec[] {
  if (Array.isArray(body)) return body.filter(isRec)
  if (!isRec(body)) return []
  for (const k of preferred) if (Array.isArray(body[k])) return (body[k] as unknown[]).filter(isRec)
  for (const v of Object.values(body)) if (Array.isArray(v)) return v.filter(isRec)
  return []
}

/** §9: the stable v4 profile identifier. Fails closed — an empty id would silently break webhook routing. VERIFY the key. */
function profileIdentity(profile: Rec): string {
  const id = str(first(profile, ["userId", "polarUserId", "memberId", "id"]))
  if (!id) throw new Error("polar v4 profile carried no user identifier (VERIFY identity field, polar.md §9)")
  return id
}

/** Splits the inclusive day window [start, end] into `{from, to}` pairs with `to` EXCLUSIVE (§21), each ≤ maxDays. */
function rangeChunks(start: string, end: string, maxDays: number): { from: string; to: string }[] {
  const out: { from: string; to: string }[] = []
  const stop = addDays(end, 1)
  let from = start
  while (from < stop && out.length < 400) {
    const to = addDays(from, Math.max(1, maxDays))
    out.push({ from, to: to < stop ? to : stop })
    from = to
  }
  return out
}

/**
 * FunctionAlps-derived RMSSD (`functionalps_rmssd_v1`): sqrt(mean((PP[i+1] − PP[i])²)) over successive intervals in
 * milliseconds (corpus metrics/hrv-semantics.md "FunctionAlps-derived HRV"). Non-finite / non-positive intervals are
 * dropped before differencing; needs at least 2 accepted intervals.
 */
function rmssdFromPPI(ppiMs: number[]): number | null {
  const xs = ppiMs.filter((x) => typeof x === "number" && Number.isFinite(x) && x > 0)
  if (xs.length < 2) return null
  let sum = 0
  for (let i = 1; i < xs.length; i++) { const d = xs[i] - xs[i - 1]; sum += d * d }
  return Math.sqrt(sum / (xs.length - 1))
}

const RES_NIGHTLY = "nightly-recharge-results", RES_SLEEPS = "sleeps", RES_PPI = "ppi-samples"

/** One Nightly Recharge result → rows (§18/§20/§30). */
function nightlyRechargeRows(rec: Rec): DailyRow[] {
  const day = str(first(rec, ["date", "nightlyRechargeDate", "sleepDate"]))?.slice(0, 10)   // VERIFY: date key
  if (!day) return []
  const prov: Partial<DailyRow> = {
    sourceRecordId: str(rec.id) ?? `${RES_NIGHTLY}:${day}`, sourceResourceType: RES_NIGHTLY,
    sourceModifiedAt: str(rec.modified), sourceDeviceId: str(first(rec, ["deviceId", "device_id"])),
  }
  const status = first(rec, ["nightlyRechargeStatus", "status"])                                   // VERIFY: status key
  const ans = first(rec, ["ansStatus"])
  const details: Rec = {
    // §30: unit NOT pinned → raw only, never 3106. §18: `meanNightlyRecoveryRri`, respiration interval, baselines are raw.
    mean_nightly_recovery_rmssd: num(rec.meanNightlyRecoveryRmssd),
    mean_nightly_recovery_rri: num(rec.meanNightlyRecoveryRri),
    mean_nightly_recovery_respiration_interval: num(first(rec, ["meanNightlyRecoveryRespirationInterval", "respirationInterval"])),
    unverified: ["VERIFY: meanNightlyRecoveryRmssd unit not pinned in v4 schema (polar.md §30) — raw only, not 3106"],
    ...(typeof ans === "string" ? { ans_status_raw: ans } : {}),
  }
  return compact([
    dailyText(day, T.PolarNightlyRechargeStatus, status == null ? null : String(status), { ...prov, sourceField: "status", details }),
    // 1000132 is numeric in the catalogue; a categorical ansStatus is kept raw (§18 "do not coerce if categorical").
    daily(day, T.PolarAnsStatus, typeof ans === "number" ? ans : null, { ...prov, sourceField: "ansStatus", details }),
    daily(day, T.PolarSleepCharge, num(first(rec, ["sleepCharge"])), { ...prov, sourceField: "sleepCharge", details }),   // §18 "if exposed" (VERIFY)
  ])
}

/** One v4 sleep → rows from the CURRENT `sleepResult` (§16/§19). */
function sleepRows(rec: Rec): DailyRow[] {
  const day = str(rec.sleepDate)?.slice(0, 10)
  if (!day) return []
  const sr = isRec(rec.sleepResult) ? rec.sleepResult : rec                    // VERIFY: nesting of the result fields
  const startIso = str(first(sr, ["sleepStartTime", "startTime"])) ?? str(first(rec, ["sleepStartTime", "startTime"]))
  const endIso = str(first(sr, ["sleepEndTime", "endTime"])) ?? str(first(rec, ["sleepEndTime", "endTime"]))
  const tz = offsetMinutes(startIso?.slice(19))
  const prov: Partial<DailyRow> = {
    sourceRecordId: str(rec.id) ?? `${RES_SLEEPS}:${day}`, sourceResourceType: RES_SLEEPS, timezoneOffset: tz,
    sourceModifiedAt: str(rec.modified), sourceDeviceId: str(first(rec, ["deviceId", "device_id"])),
  }
  const details: Rec = {
    edited: rec.originalSleepResult != null,
    // "verify v4 unit" (canonical-metric-map) → stage durations stay raw until pinned.
    stages_raw: { light: num(first(sr, ["lightSleep", "light"])), deep: num(first(sr, ["deepSleep", "deep"])), rem: num(first(sr, ["remSleep", "rem"])), wake: num(first(sr, ["wake", "awake"])), unknown: num(first(sr, ["unknown"])) },
    continuity: num(first(sr, ["continuity"])),
    unverified: ["VERIFY: stage duration unit not pinned (canonical-metric-map) — raw only"],
  }
  return compact([
    daily(day, T.SleepEfficiency, num(first(sr, ["efficiency", "sleepEfficiency"])), { ...prov, sourceField: "efficiency", details }),
    daily(day, T.SleepScore, num(first(sr, ["sleepScore"]) ?? first(rec, ["sleepScore"])), { ...prov, sourceField: "sleepScore", details }),
    dailyDate(day, T.SleepStart, startIso, { ...prov, sourceField: "sleepStartTime" }),
    dailyDate(day, T.SleepEnd, endIso, { ...prov, sourceField: "sleepEndTime" }),
  ])
}

/** One PPI sample set → one 3100 epoch row (FunctionAlps-derived RMSSD, ms pinned for `ppInterval`). */
function ppiRows(rec: Rec, queryDay: string): EpochRow[] {
  const samples = (Array.isArray(rec.samples) ? rec.samples : []).filter(isRec)   // VERIFY: `samples` key (§21 anchor + offsetMillis)
  const raw = samples.map((s) => num(s.ppInterval))
  const accepted = raw.filter((x): x is number => x != null && Number.isFinite(x) && x > 0)
  const value = rmssdFromPPI(accepted)
  if (value == null) return []
  const anchor = str(first(rec, ["startTime", "start", "timestamp"]))
  const startTs = anchor ? new Date(Date.parse(anchor)).toISOString() : `${queryDay}T00:00:00Z`
  const lastOff = num(samples[samples.length - 1]?.offsetMillis)
  const endTs = lastOff != null ? new Date(Date.parse(startTs) + lastOff).toISOString() : null
  const row = epoch(startTs, T.Rmssd, value, {
    endTs, sourceRecordId: str(rec.id) ?? `${RES_PPI}:${queryDay}:${startTs}`, sourceResourceType: RES_PPI, sourceField: "ppInterval", sourceModifiedAt: str(rec.modified), sourceDeviceId: str(first(rec, ["deviceId", "device_id"])),
    details: { algorithm: "functionalps_rmssd_v1", n: accepted.length, rejected: raw.length - accepted.length, quality: "functionalps_derived", window_ms: lastOff, anchor: anchor ? "record_start" : "day_start" },
  })
  return row ? [row] : []
}

// MARK: - HTTP

async function v4get(resource: string, q: Record<string, string>, tokens: TokenSet): Promise<Rec[]> {
  try {
    const body: unknown = await getJSON(`${POLAR_DATA}/${resource}?${new URLSearchParams(q)}`, { Authorization: `Bearer ${tokens.accessToken}` })
    return unwrap(body, [resource, "items", "data", "results"])
  } catch (e) {
    if (e instanceof VendorHttpError && e.status === 404) return []   // §24: missing data is not a failure
    throw e
  }
}

const tokenSet = (t: Rec, fallbackRefresh?: string): TokenSet => {
  const exp = num(t.expires_in)
  return {
    accessToken: String(t.access_token), refreshToken: (t.refresh_token as string | undefined) ?? fallbackRefresh,
    expiresAt: exp ? Math.floor(Date.now() / 1000) + exp : undefined,   // §7: response expiry, no 12 h constant
    scopes: typeof t.scope === "string" ? t.scope.split(" ").filter(Boolean) : undefined,
  }
}

// MARK: - Adapter

export const polar: VendorAdapter = {
  key: "polar",
  name: "Polar",
  pkce: "not_documented",          // §6
  scopes: SCOPES,
  reconcile: { nightlyDays: 3, weeklyDays: 14 },   // §17

  authorizeURL({ clientId, redirectUri, state }) {
    return `${POLAR_AUTH}?${new URLSearchParams({ client_id: clientId, response_type: "code", scope: SCOPES.join(" "), redirect_uri: redirectUri, state })}`
  },

  async exchangeCode({ code, redirectUri }) {
    const { clientId, clientSecret } = vendorClient("polar")
    const t = await tokenPost(POLAR_TOKEN, { grant_type: "authorization_code", code, redirect_uri: redirectUri }, { basic: { id: clientId, secret: clientSecret } })
    const set = tokenSet(t)
    // §9: identity from the v4 profile, never `x_user_id`.
    const profile = await getJSON(POLAR_PROFILE, { Authorization: `Bearer ${set.accessToken}` })
    return { ...set, scopes: set.scopes ?? SCOPES, vendorUserId: profileIdentity(profile) }
  },

  async refresh(refreshToken) {
    // §8: rotation semantics not documented → keep the old refresh token when none is returned; the core serialises refreshes.
    const { clientId, clientSecret } = vendorClient("polar")
    const t = await tokenPost(POLAR_TOKEN, { grant_type: "refresh_token", refresh_token: refreshToken }, { basic: { id: clientId, secret: clientSecret } })
    return tokenSet(t, refreshToken)
  },

  // revoke: undefined on purpose — §25 "REQUIRES PORTAL VERIFICATION" for the v4 unlink request. The core erases tokens locally.
  // unsubscribe: undefined — the v3 webhook is one per client (§10), never per user.
  // afterConnect: none — v4 needs no `/v3/users` registration (§28).

  async parseWebhook(req, rawBody): Promise<WebhookEvent[]> {
    if (env("POLAR_WEBHOOKS_ENABLED", "") !== "1") {
      log("warn", "polar.webhook_disabled", { fn: "polar", vendor: "polar", reason: "v3-webhook/v4-data compatibility unconfirmed (polar.md §10)" })
      return []
    }
    let e: Rec = {}
    try { const j: unknown = JSON.parse(rawBody); if (isRec(j)) e = j } catch { throw new Error("polar webhook: malformed body") }
    if (e.event === "PING") return []            // §11: the creation ping arrives before any secret exists
    const secret = env("POLAR_WEBHOOK_SECRET")   // D10
    const sig = (req.headers.get("Polar-Webhook-Signature") ?? "").trim().toLowerCase()
    const mac = await hmacSha256(secret, rawBody, "hex")
    if (!sig || !timingSafeEqual(mac, sig)) throw new Error("polar signature mismatch")
    // VERIFY (§9): the v3 `user_id` is not guaranteed to equal the v4 profile identity — one more reason for the flag.
    const userId = str(e.user_id)
    if (!userId) return []
    const kind = req.headers.get("Polar-Webhook-Event") ?? str(e.event) ?? "event"
    const date = str(e.date)?.slice(0, 10)
    return [{
      vendorUserId: userId, kind,
      eventId: str(first(e, ["event_id", "id"])),   // no vendor event id is documented → body-hash dedupe in the core
      ...(date ? { windowStart: date, windowEnd: date } : {}),
      // `url` in the payload is never fetched (§11): the sync pulls the known v4 resources for the window instead.
    }]
  },

  async fetchRange(tokens, start, end): Promise<RowBatch> {
    const dailyRows: DailyRow[] = [], epochRows: EpochRow[] = []
    const inRange = (r: DailyRow) => r.day >= start && r.day <= end
    for (const { from, to } of rangeChunks(start, end, NIGHTLY_MAX_DAYS)) {
      for (const rec of await v4get(RES_NIGHTLY, { from, to }, tokens)) dailyRows.push(...nightlyRechargeRows(rec).filter(inRange))
    }
    for (const { from, to } of rangeChunks(start, end, SLEEPS_MAX_DAYS)) {
      for (const rec of await v4get(RES_SLEEPS, { from, to }, tokens)) dailyRows.push(...sleepRows(rec).filter(inRange))
    }
    // §15: sample endpoints are one day per call.
    for (const day of daysBetween(start, end)) {
      for (const rec of await v4get(RES_PPI, { from: day, to: addDays(day, SAMPLES_MAX_DAYS), features: "samples" }, tokens)) epochRows.push(...ppiRows(rec, day))
    }
    return { daily: dailyRows, epoch: epochRows }
  },
}

export const _polarTest = { rmssdFromPPI, rangeChunks, profileIdentity, unwrap, nightlyRechargeRows, sleepRows, ppiRows, first }
