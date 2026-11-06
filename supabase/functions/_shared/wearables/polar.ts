// Polar Dynamic API v4. Data path REBUILT 2026-11-06 from Polar's official v4 Swagger (see the block under the constants:
// it supersedes the corpus wherever they differ). The webhook part below still follows the 2026-09-14 corpus
// `.context/research/2026-09-14_wearables-implementation/vendors/polar.md` (§ numbers refer to it).
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
import { type SupabaseClient } from "npm:@supabase/supabase-js@2"
import { type DailyRow, type RowBatch, type TokenAAD, type TokenSet, type VendorAdapter, type WebhookEvent, T, VendorHttpError, addDays, compact, currentKeyVersion, daily, dailyDate, dailyText, decrypt, encrypt, env, getJSON, hmacSha256, num, offsetMinutes, serviceClient, timingSafeEqual, tokenPost, vendorClient, webhookUrl } from "./core.ts"
import { log } from "./log.ts"

export const POLAR_AUTH = "https://auth.polar.com/oauth/authorize"          // §6
export const POLAR_TOKEN = "https://auth.polar.com/oauth/token"             // §7
export const POLAR_DATA = "https://www.polaraccesslink.com/v4/data"         // §12

// ── 2026-11-06 rebuild against Polar's OFFICIAL v4 Swagger (https://www.polar.com/polar-api-v4/swagger.yaml) ──────────
// The corpus-era version of this file called `GET /v4/data/profile` (not a v4 path → 404 → every connect failed), asked for
// the undocumented scope `ppi:read` (the documented one is `ppi_data:read`), read sleep and Nightly Recharge fields that do
// not exist, and derived its own RMSSD from whole-day PPI. What the Swagger pins, and this file now follows:
//   • scopes per path: `/sleeps` sleep:read · `/nightly-recharge-results` nightly_recharge:read · `/user/account-data`
//     profile:read. We request ONLY what we read (Polar API Agreement §3.1.2, data minimisation).
//   • identity: neither the token reply (access_token, token_type, refresh_token, expires_in, scope, jti) nor
//     `/user/account-data` (name, email, settings — no id) carries a user id → Polar accounts have NO vendor_user_id;
//     v3 webhooks (keyed by the v3 user id) therefore cannot be matched and stay off (POLAR_WEBHOOKS_ENABLED unset).
//   • `/nightly-recharge-results?from&to` (to EXCLUSIVE) → `{ nightlyRechargeResults: { nightlyRechargeResults: [ … ] } }`,
//     keyed by `sleepResultDate` (member-local date). `meanNightlyRecoveryRmssd` is documented as "Mean of the PPI (after 0.5h
//     from sleep start to 4,5h after sleep start PPI) calculated RMSSD values. (ms)" → RmssdSleep 3106 (decision D4 is met:
//     statistic and unit are official). `recoveryIndicator` 1–6 → 1000130 (categorical, kept as Polar's code).
//   • `/sleeps?from&to` without `features` lists only DATES; details need `features=sleep-result&features=sleep-evaluation&
//     features=sleep-score` (collectionFormat multi) and ONE day per call. Durations are strings of seconds ("3.000000001s").
//     Start/end are `sleepResult.hypnogram.sleepStart/sleepEnd` (local, with offset); `sleepEvaluation.asleepDuration`,
//     `.sleepSpan`, `.phaseDurations.{rem,light,deep,wake}`, `.analysis.efficiencyPercent`, `.interruptions.totalCount`;
//     `sleepScore.sleepScore` (1–100) and `sleepScore.scoreRate` (1–5 "compared to own usual level" = Polar's Sleep Charge).
export const NIGHTLY_MAX_DAYS = 28
export const SLEEP_DATES_MAX_DAYS = 28
export const SLEEP_FEATURES = ["sleep-result", "sleep-evaluation", "sleep-score"]

const SCOPES = ["profile:read", "sleep:read", "nightly_recharge:read"]

// MARK: - Pure helpers (exported through _polarTest)

type Rec = Record<string, unknown>
const isRec = (v: unknown): v is Rec => typeof v === "object" && v != null && !Array.isArray(v)
const str = (v: unknown): string | null => (typeof v === "string" && v ? v : typeof v === "number" ? String(v) : null)
const obj = (v: unknown): Rec => (isRec(v) ? v : {})

/** First present key of `keys` in `obj` (webhook body only). */
function first(o: Rec | null | undefined, keys: string[]): unknown {
  if (!o) return undefined
  for (const k of keys) if (o[k] !== undefined && o[k] !== null) return o[k]
  return undefined
}

/** Polar v4 durations: "Format is seconds with optional fraction of seconds … like \"3.000000001s\"" → whole seconds. */
export function polarSeconds(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? Math.round(v) : null
  if (typeof v !== "string") return null
  const m = /^(-?\d+(?:\.\d+)?)s$/.exec(v.trim())
  return m ? Math.round(Number(m[1])) : null
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

const RES_NIGHTLY = "nightly-recharge-results", RES_SLEEPS = "sleeps"

/** `{ nightlyRechargeResults: { nightlyRechargeResults: [ … ] } }` → the array (Swagger `domainsnightlyrechargeListResponse`). */
export function nightlyList(body: unknown): Rec[] {
  const inner = obj(obj(body).nightlyRechargeResults).nightlyRechargeResults
  return Array.isArray(inner) ? inner.filter(isRec) : []
}

/** `{ nightSleeps: [ … ] }` → the array (Swagger `sleepListSleepsResponse`). */
export function sleepList(body: unknown): Rec[] {
  const a = obj(body).nightSleeps
  return Array.isArray(a) ? a.filter(isRec) : []
}

/** One Nightly Recharge result (Swagger `nightlyrechargeNightlyRechargeResult`) → daily rows. */
function nightlyRechargeRows(rec: Rec): DailyRow[] {
  const day = str(rec.sleepResultDate)?.slice(0, 10)
  if (!day) return []
  const prov: Partial<DailyRow> = { sourceRecordId: `${RES_NIGHTLY}:${day}`, sourceResourceType: RES_NIGHTLY, sourceModifiedAt: str(rec.modified) }
  const indicator = num(rec.recoveryIndicator)
  return compact([
    daily(day, T.RmssdSleep, num(rec.meanNightlyRecoveryRmssd), {
      ...prov, sourceField: "meanNightlyRecoveryRmssd",
      details: { statistic: "rmssd", window: "0.5h-4.5h_after_sleep_start", unit: "ms", baseline_mean: num(rec.meanBaselineRmssd), baseline_sd: num(rec.sdBaselineRmssd) },
    }),
    // Categorical (catalogue 1000130 is STRING): Polar's own 1–6 code, never relabelled; the sub-level stays beside it.
    dailyText(day, T.PolarNightlyRechargeStatus, indicator == null ? null : String(indicator), {
      ...prov, sourceField: "recoveryIndicator",
      details: { scale: "polar_recovery_indicator_1_6", sub_level: num(rec.recoveryIndicatorSubLevel), ans_rate: num(rec.ansRate) },
    }),
    daily(day, T.PolarAnsStatus, num(rec.ansStatus), {
      ...prov, sourceField: "ansStatus",
      // Kept raw: mean RR interval and respiration interval (ms) — turning them into bpm / breaths per minute is a derivation
      // the practice has not decided on.
      details: { mean_nightly_recovery_rri_ms: num(rec.meanNightlyRecoveryRri), mean_nightly_recovery_respiration_interval_ms: num(rec.meanNightlyRecoveryRespirationInterval), baseline_rri_ms: num(rec.meanBaselineRri) },
    }),
  ])
}

/** One night (Swagger `sleepNightSleep`, fetched WITH features) → daily rows from the CURRENT `sleepResult` (§16/§19). */
function sleepRows(night: Rec): DailyRow[] {
  const day = str(night.sleepDate)?.slice(0, 10)
  if (!day) return []
  const hyp = obj(obj(night.sleepResult).hypnogram)
  const ev = obj(night.sleepEvaluation), phases = obj(ev.phaseDurations), analysis = obj(ev.analysis), interruptions = obj(ev.interruptions)
  const score = obj(night.sleepScore)
  const startIso = str(hyp.sleepStart), endIso = str(hyp.sleepEnd)
  const prov: Partial<DailyRow> = {
    sourceRecordId: `${RES_SLEEPS}:${day}`, sourceResourceType: RES_SLEEPS, timezoneOffset: offsetMinutes(startIso?.slice(19)),
    sourceModifiedAt: str(score.lastModified), sourceDeviceId: str(obj(hyp.deviceReference).deviceId),
  }
  const details = { sleep_type: str(ev.sleepType), edited: night.originalSleepResult != null, continuity_index: num(analysis.continuityIndex), unknown_s: polarSeconds(phases.unknown) }
  return compact([
    daily(day, T.MainSleepDuration, polarSeconds(ev.asleepDuration), { ...prov, sourceField: "sleepEvaluation.asleepDuration", details }),
    daily(day, T.InBed, polarSeconds(ev.sleepSpan), { ...prov, sourceField: "sleepEvaluation.sleepSpan" }),
    daily(day, T.REM, polarSeconds(phases.rem), { ...prov, sourceField: "phaseDurations.rem" }),
    daily(day, T.Deep, polarSeconds(phases.deep), { ...prov, sourceField: "phaseDurations.deep" }),
    daily(day, T.Light, polarSeconds(phases.light), { ...prov, sourceField: "phaseDurations.light" }),
    daily(day, T.Awake, polarSeconds(phases.wake), { ...prov, sourceField: "phaseDurations.wake" }),
    daily(day, T.SleepEfficiency, num(analysis.efficiencyPercent), { ...prov, sourceField: "analysis.efficiencyPercent" }),
    daily(day, T.Interruptions, num(interruptions.totalCount), { ...prov, sourceField: "interruptions.totalCount", details: { long_count: num(interruptions.longCount), short_count: num(interruptions.shortCount) } }),
    daily(day, T.SleepScore, num(score.sleepScore), { ...prov, sourceField: "sleepScore.sleepScore" }),
    daily(day, T.PolarSleepCharge, num(score.scoreRate), { ...prov, sourceField: "sleepScore.scoreRate", details: { scale: "1-5_vs_own_usual_level" } }),
    dailyDate(day, T.SleepStart, startIso, { ...prov, sourceField: "hypnogram.sleepStart" }),
    dailyDate(day, T.SleepEnd, endIso, { ...prov, sourceField: "hypnogram.sleepEnd" }),
  ])
}

// MARK: - HTTP

async function v4get(resource: string, q: Record<string, string | string[]>, tokens: TokenSet): Promise<unknown> {
  const qs = new URLSearchParams()
  for (const [k, v] of Object.entries(q)) for (const x of Array.isArray(v) ? v : [v]) qs.append(k, x)
  try {
    return await getJSON(`${POLAR_DATA}/${resource}?${qs}`, { Authorization: `Bearer ${tokens.accessToken}` })
  } catch (e) {
    if (e instanceof VendorHttpError && e.status === 404) return {}   // §24: missing data is not a failure
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
    // v4 exposes no user id anywhere (token reply or /user/account-data) → no vendor_user_id; never derived from name/email.
    return { ...set, scopes: set.scopes ?? SCOPES }
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
    const secret = await polarWebhookSecret()    // D10: env, else the app-level row written by polarRegisterWebhook
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
    const dailyRows: DailyRow[] = []
    const inRange = (r: DailyRow) => r.day >= start && r.day <= end
    for (const { from, to } of rangeChunks(start, end, NIGHTLY_MAX_DAYS)) {
      for (const rec of nightlyList(await v4get(RES_NIGHTLY, { from, to }, tokens))) dailyRows.push(...nightlyRechargeRows(rec).filter(inRange))
    }
    // Sleep: the dates first (no features), then each night with its features — one day per call (Swagger).
    const dates = new Set<string>()
    for (const { from, to } of rangeChunks(start, end, SLEEP_DATES_MAX_DAYS)) {
      for (const n of sleepList(await v4get(RES_SLEEPS, { from, to }, tokens))) { const d = str(n.sleepDate)?.slice(0, 10); if (d && d >= start && d <= end) dates.add(d) }
    }
    for (const d of [...dates].sort()) {
      for (const n of sleepList(await v4get(RES_SLEEPS, { from: d, to: addDays(d, 1), features: SLEEP_FEATURES }, tokens))) dailyRows.push(...sleepRows(n).filter(inRange))
    }
    log("info", "polar.fetch_range", { fn: "polar", vendor: "polar", start, end, nights: dates.size, daily: dailyRows.length })
    return { daily: dailyRows, epoch: [] }
  },
}

export const _polarTest = { rangeChunks, nightlyRechargeRows, sleepRows, first, resetWebhookSecretCache: () => { cachedWebhookSecret = null } }

// MARK: - App-level webhook (v3 AccessLink): registered by the backend, its once-shown signing key kept encrypted

export const POLAR_WEBHOOKS = "https://www.polaraccesslink.com/v3/webhooks"
/** §10: the documented webhook event types the adapter understands. */
export const POLAR_WEBHOOK_EVENTS = ["EXERCISE", "SLEEP", "CONTINUOUS_HEART_RATE", "ACTIVITY_SUMMARY", "PHYSICAL_INFORMATION"]
/** The signing key is bound to the app row, not to a member account. */
const WEBHOOK_AAD: TokenAAD = { accountId: "app", vendor: "polar", tokenType: "webhook" }
let cachedWebhookSecret: { value: string; at: number } | null = null

/**
 * `POLAR_WEBHOOK_SECRET` (D10, hand-registered) wins; otherwise the active app-level row of
 * `wearable_webhook_subscriptions` carries `meta.secret_enc`, written by `polarRegisterWebhook` and decrypted with
 * the token key ring. Cached 10 minutes per isolate. Throws when neither exists (fail closed, like Oura).
 */
export async function polarWebhookSecret(db?: SupabaseClient): Promise<string> {
  const fromEnv = Deno.env.get("POLAR_WEBHOOK_SECRET")
  if (fromEnv) return fromEnv
  if (cachedWebhookSecret && Date.now() - cachedWebhookSecret.at < 600_000) return cachedWebhookSecret.value
  const client = db ?? serviceClient()
  const { data } = await client.from("wearable_webhook_subscriptions").select("meta").eq("vendor", "polar").is("account_id", null).eq("status", "active").order("created_at", { ascending: false }).limit(1).maybeSingle()
  const enc = (data?.meta as { secret_enc?: string } | null | undefined)?.secret_enc
  if (!enc) throw new Error("polar webhook secret unset (no POLAR_WEBHOOK_SECRET and no registered webhook)")
  const value = await decrypt(enc, WEBHOOK_AAD)
  cachedWebhookSecret = { value, at: Date.now() }
  return value
}

export interface PolarWebhookRegistration { action: "kept" | "created" | "recreated"; id: string; events: string[]; url: string }

/**
 * Registers the application webhook with Polar from the backend (client credentials, §10/§11) so the once-shown
 * `signature_secret_key` never passes through a screen: it is encrypted (AAD `app|polar|webhook|<key version>`)
 * into the app-level subscription row. Polar allows one webhook per client and returns the key only at creation,
 * so an existing webhook we hold no key for is deleted and recreated; `force` recreates unconditionally.
 * Never returns or logs the key.
 */
export async function polarRegisterWebhook(db: SupabaseClient, opts: { force?: boolean; fetchImpl?: typeof fetch } = {}): Promise<PolarWebhookRegistration> {
  const f = opts.fetchImpl ?? fetch
  const { clientId, clientSecret } = vendorClient("polar")
  const h = { Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`, Accept: "application/json", "Content-Type": "application/json" }
  const url = webhookUrl("polar")
  const list = await f(POLAR_WEBHOOKS, { headers: h })
  if (!list.ok) throw new VendorHttpError(list.status, "polar webhooks list")
  const existing = ((await list.json()) as { data?: { id: string; events: string[]; url: string }[] }).data ?? []
  const { data: row } = await db.from("wearable_webhook_subscriptions").select("vendor_subscription_id, callback_url, meta").eq("vendor", "polar").is("account_id", null).eq("status", "active").order("created_at", { ascending: false }).limit(1).maybeSingle()
  const held = row as { vendor_subscription_id: string | null; callback_url: string | null; meta: { secret_enc?: string } | null } | null
  const known = existing.find((w) => w.id === held?.vendor_subscription_id)
  if (known && held?.meta?.secret_enc && known.url === url && !opts.force) return { action: "kept", id: known.id, events: known.events, url: known.url }
  for (const w of existing) {
    const del = await f(`${POLAR_WEBHOOKS}/${w.id}`, { method: "DELETE", headers: h })
    if (!del.ok && del.status !== 404) throw new VendorHttpError(del.status, "polar webhook delete")
  }
  const create = await f(POLAR_WEBHOOKS, { method: "POST", headers: h, body: JSON.stringify({ events: POLAR_WEBHOOK_EVENTS, url }) })
  if (!create.ok) throw new VendorHttpError(create.status, "polar webhook create")
  const made = ((await create.json()) as { data: { id: string; events: string[]; url: string; signature_secret_key: string } }).data
  const secret_enc = await encrypt(made.signature_secret_key, WEBHOOK_AAD)
  await db.from("wearable_webhook_subscriptions").update({ status: "revoked", updated_at: new Date().toISOString() }).eq("vendor", "polar").is("account_id", null).eq("status", "active")
  const { error } = await db.from("wearable_webhook_subscriptions").insert({ vendor: "polar", vendor_subscription_id: made.id, data_type: made.events.join(","), event_type: "webhook", callback_url: made.url, status: "active", meta: { secret_enc, key_version: currentKeyVersion(), registered_by: "backend" } })
  if (error) throw new Error(`polar webhook row: ${error.message}`)
  cachedWebhookSecret = null
  log("info", "polar.webhook_registered", { fn: "polar", vendor: "polar", action: existing.length ? "recreated" : "created", id: made.id, events: made.events })
  return { action: existing.length ? "recreated" : "created", id: made.id, events: made.events, url: made.url }
}
