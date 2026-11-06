// Strava API v3 — added 2026-11-06, behind `wearable_vendors.status = 'planned'` until the owner registers the app,
// sets the secrets and one real connection syncs. Strava is an ACTIVITY service: it holds the workouts a member
// recorded (on any device or app that uploads to Strava) and nothing else — no sleep, no HRV, no resting heart rate,
// no steps, no weight. So this adapter writes WORKOUT epoch rows only, never daily totals: a daily distance from
// Strava would mean "distance in recorded activities", not the all-day distance every other source writes under
// 1001, and the dashboard's per-day source collapse must never mix the two.
//
// Contract (developers.strava.com — the public API reference and the Strava API Agreement):
//   • OAuth 2.0 web flow: authorize at www.strava.com/oauth/authorize (comma-separated scopes, `approval_prompt`),
//     token + refresh at www.strava.com/oauth/token with the client secret in the body. No PKCE is documented.
//     Access tokens live 6 h (`expires_at`, unix seconds); the refresh reply may carry a NEW refresh token — the
//     core adopts it and keeps the old one when absent. Revocation: POST www.strava.com/oauth/deauthorize.
//     The redirect URI's HOST must equal the app's "Authorization Callback Domain" (ndojytvvlvlbgtodujkf.supabase.co).
//   • Identity: the token reply carries `athlete.id` → `vendor_user_id`.
//   • Data: GET /api/v3/athlete/activities?after&before&page&per_page (SummaryActivity). `start_date` is UTC;
//     `start_date_local` is the local wall time written with a misleading `Z` — its first 10 chars ARE the local day;
//     `utc_offset` is seconds.
//   • Webhooks: ONE push subscription per app (POST /api/v3/push_subscriptions), validated by a GET challenge
//     (`hub.mode=subscribe`, `hub.verify_token`, `hub.challenge` → 200 `{"hub.challenge": …}` within 2 s). Events are
//     `{object_type, object_id, aspect_type, owner_id, subscription_id, event_time, updates}` and are NOT SIGNED.
//     So an event is only ever a "pull now" hint (like Withings): its `subscription_id` must match the one we
//     registered, and a deauthorisation event (`updates.authorized = "false"`) is NOT trusted to revoke the account —
//     it queues a pull, Strava answers 401 for a really revoked grant, and the core then marks the account
//     `reconnect_required` (and the member sees it). A forged body can at most cause one extra pull.
//   • Rate limits: per app, per 15 minutes and per day (overall and "read" buckets), reported in the
//     X-RateLimit-Limit / X-RateLimit-Usage headers; 429 carries no Retry-After, so we wait for the next quarter hour.
//   • Capacity: a new Strava app is limited to its owner's own athlete until Strava reviews it — fine for 'planned'.
//   • Terms (Strava API Agreement): data shown only to the athlete it belongs to and the people they choose to share it
//     with (here: their practitioner, under the Privacy Notice); no AI/ML use → `ai-policy.ts` keeps Strava denied;
//     data of an athlete who disconnects is deleted on request (`wearable-vendor-disconnect` erase path).
// Every row carries provenance: `sourceRecordId` = the Strava activity id, `sourceResourceType` = "activity".
import { type SupabaseClient } from "npm:@supabase/supabase-js@2"
import {
  type AccountContext, type EpochRow, type RowBatch, type TokenSet, type VendorAdapter, type WebhookEvent,
  T, RateLimitedError, UnauthorizedError, VendorHttpError, addDays, compact, epoch, num, serviceClient, tokenPost, vendorClient, webhookUrl,
} from "./core.ts"
import { log } from "./log.ts"

const FN = "strava"
export const STRAVA_AUTH = "https://www.strava.com/oauth/authorize"
export const STRAVA_TOKEN = "https://www.strava.com/oauth/token"
export const STRAVA_DEAUTH = "https://www.strava.com/oauth/deauthorize"
export const STRAVA_API = "https://www.strava.com/api/v3"
export const STRAVA_SUBSCRIPTIONS = `${STRAVA_API}/push_subscriptions`
/** `read` = public profile (needed for the athlete id); `activity:read_all` = every activity, including "Only you". */
export const STRAVA_SCOPES = ["read", "activity:read_all"]
const PER_PAGE = 100
const MAX_PAGES = 20

type Rec = Record<string, unknown>
const str = (v: unknown): string | null => (v == null || v === "" ? null : String(v))

/** Seconds until the next quarter hour (Strava's short window resets on :00/:15/:30/:45 UTC). */
export function secondsToNextQuarter(now = new Date()): number {
  const s = now.getUTCMinutes() * 60 + now.getUTCSeconds()
  return 900 - (s % 900) || 900
}

async function stravaGet(path: string, tokens: TokenSet, query: Record<string, string | number>): Promise<unknown> {
  const url = `${STRAVA_API}${path}?${new URLSearchParams(Object.entries(query).map(([k, v]) => [k, String(v)]))}`
  const resp = await fetch(url, { headers: { Accept: "application/json", Authorization: `Bearer ${tokens.accessToken}` } })
  const text = await resp.text()
  if (resp.status === 401) throw new UnauthorizedError(text.slice(0, 200))
  if (resp.status === 429) {
    log("warn", "strava.rate_limited", { fn: FN, vendor: "strava", limit: resp.headers.get("X-RateLimit-Limit"), usage: resp.headers.get("X-RateLimit-Usage") })
    throw new RateLimitedError(String(secondsToNextQuarter()))
  }
  if (!resp.ok) throw new VendorHttpError(resp.status, `GET ${path}: ${text.slice(0, 300)}`)
  return text ? JSON.parse(text) : null
}

/** One SummaryActivity → its workout epoch rows. Null-safe: a missing field drops only its own row. */
export function activityRows(a: Rec): { day: string; rows: EpochRow[] } | null {
  const id = str(a.id), startTs = str(a.start_date), local = str(a.start_date_local)
  if (!id || !startTs || !local) return null
  const day = local.slice(0, 10)
  const offsetMin = num(a.utc_offset) == null ? null : Math.round(Number(a.utc_offset) / 60)
  const moving = num(a.moving_time), elapsed = num(a.elapsed_time)
  const endTs = elapsed != null ? new Date(Date.parse(startTs) + elapsed * 1000).toISOString() : null
  const sport = str(a.sport_type) ?? str(a.type) ?? "Workout"
  const prov: Partial<EpochRow> = { endTs, timezoneOffset: offsetMin, sourceRecordId: id, sourceResourceType: "activity", sourceDeviceId: str(a.device_name) }
  const hr = a.has_heartrate === false ? null : num(a.average_heartrate)
  const rows = compact([
    // Same shape as the other vendors' workouts: value 0, the sport in valueText, the duration in details (the Apple
    // Health relay also carries `duration_min`). `kilojoules` is mechanical WORK on a power meter, not energy burned —
    // it stays raw and is never converted to kcal.
    epoch(startTs, T.ActivityType, 0, {
      ...prov, valueText: sport, valueType: "STRING",
      details: {
        sport_type: sport, workout_type: num(a.workout_type), manual: a.manual === true, trainer: a.trainer === true,
        moving_time_s: moving, elapsed_time_s: elapsed, duration_min: moving != null ? Math.round(moving / 6) / 10 : null,
        kilojoules_work: num(a.kilojoules), average_watts: num(a.average_watts), suffer_score: num(a.suffer_score), timezone: str(a.timezone),
      },
    }),
    epoch(startTs, T.CoveredDistance, num(a.distance) || null, { ...prov, details: { workout: true } }),
    epoch(startTs, T.ElevationGain, num(a.total_elevation_gain) || null, { ...prov, details: { workout: true } }),
    epoch(startTs, T.HeartRate, hr == null ? null : Math.round(hr), { ...prov, details: { workout: true, statistic: "average", max_heart_rate: num(a.max_heartrate) } }),
  ])
  return { day, rows }
}

export const strava: VendorAdapter = {
  key: "strava",
  name: "Strava",
  pkce: "not_documented",
  scopes: STRAVA_SCOPES,
  // Athletes edit and re-upload activities after the fact: a week nightly, a month on Sundays.
  reconcile: { nightlyDays: 7, weeklyDays: 30 },

  authorizeURL({ clientId, redirectUri, state }) {
    return `${STRAVA_AUTH}?${new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, response_type: "code", approval_prompt: "auto", scope: STRAVA_SCOPES.join(","), state })}`
  },

  async exchangeCode({ code }) {
    const { clientId, clientSecret } = vendorClient("strava")
    const t = await tokenPost(STRAVA_TOKEN, { client_id: clientId, client_secret: clientSecret, code, grant_type: "authorization_code" })
    const athlete = (t.athlete ?? {}) as Rec
    return {
      accessToken: String(t.access_token), refreshToken: t.refresh_token as string | undefined,
      expiresAt: num(t.expires_at) ?? Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 21_600),
      // The granted scopes travel in the callback's query (`scope=`), not in the token reply: the requested set is
      // recorded, and a member who unticked activity:read_all gets a 401 on the first pull → "Needs reconnecting".
      scopes: STRAVA_SCOPES, vendorUserId: str(athlete.id) ?? undefined,
    }
  },

  async refresh(refreshToken) {
    const { clientId, clientSecret } = vendorClient("strava")
    const t = await tokenPost(STRAVA_TOKEN, { client_id: clientId, client_secret: clientSecret, grant_type: "refresh_token", refresh_token: refreshToken })
    return {
      accessToken: String(t.access_token), refreshToken: (t.refresh_token as string | undefined) ?? refreshToken,
      expiresAt: num(t.expires_at) ?? Math.floor(Date.now() / 1000) + (num(t.expires_in) ?? 21_600),
    }
  },

  async revoke(tokens) {
    // Deauthorising also stops this athlete's events to our subscription.
    await fetch(STRAVA_DEAUTH, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", Authorization: `Bearer ${tokens.accessToken}` }, body: new URLSearchParams({ access_token: tokens.accessToken }) })
  },

  challengeResponse(url) {
    if (url.searchParams.get("hub.mode") !== "subscribe") return null
    const expected = Deno.env.get("STRAVA_WEBHOOK_VERIFY_TOKEN")
    const given = url.searchParams.get("hub.verify_token") ?? ""
    // Fail closed, like Oura: without our own verify token no subscription can be validated.
    if (!expected || given !== expected) return new Response("forbidden", { status: 403 })
    return new Response(JSON.stringify({ "hub.challenge": url.searchParams.get("hub.challenge") ?? "" }), { status: 200, headers: { "Content-Type": "application/json" } })
  },

  async parseWebhook(_req, rawBody): Promise<WebhookEvent[]> {
    if (!rawBody) return []
    const e = JSON.parse(rawBody) as Rec
    // Unsigned deliveries: the subscription id must be the one we registered (not a secret — a filter).
    const expected = await stravaSubscriptionId()
    if (expected == null) throw new Error("strava subscription not registered")
    if (str(e.subscription_id) !== expected) throw new Error("strava subscription mismatch")
    const owner = str(e.owner_id)
    if (!owner) return []
    const objectType = String(e.object_type ?? ""), aspect = String(e.aspect_type ?? ""), objectId = str(e.object_id)
    const deauth = objectType === "athlete" && String((e.updates as Rec | undefined)?.authorized ?? "") === "false"
    // A hint, never an instruction: even a deauthorisation only queues a pull (see the header).
    return [{
      vendorUserId: owner, kind: deauth ? "athlete.deauthorized" : `${objectType}.${aspect}`,
      eventId: `${objectType}.${aspect}.${objectId ?? ""}.${str(e.event_time) ?? ""}`,
      resourceId: objectId, deleted: aspect === "delete",
    }]
  },

  async fetchRange(tokens, start, end, _ctx: AccountContext): Promise<RowBatch> {
    // `after`/`before` filter on the UTC start; one day of margin each side, then keep the activities whose LOCAL day
    // is inside [start, end].
    const after = Math.floor(Date.parse(`${addDays(start, -1)}T00:00:00Z`) / 1000)
    const before = Math.floor(Date.parse(`${addDays(end, 2)}T00:00:00Z`) / 1000)
    const epochRows: EpochRow[] = []
    let seen = 0
    for (let page = 1; page <= MAX_PAGES; page++) {
      const list = await stravaGet("/athlete/activities", tokens, { after, before, page, per_page: PER_PAGE })
      const items = Array.isArray(list) ? (list as Rec[]) : []
      seen += items.length
      for (const a of items) {
        const r = activityRows(a)
        if (r && r.day >= start && r.day <= end) epochRows.push(...r.rows)
      }
      if (items.length < PER_PAGE) break
    }
    log("info", "strava.fetch_range", { fn: FN, vendor: "strava", start, end, activities: seen, epoch: epochRows.length })
    return { daily: [], epoch: epochRows }
  },
}

// MARK: - App-level push subscription (one per Strava app), registered by the backend

let cachedSubscription: { id: string | null; at: number } | null = null
export const _stravaTest = { resetSubscriptionCache: (id?: string | null) => { cachedSubscription = id === undefined ? null : { id, at: Date.now() } } }

/** The registered subscription id (env `STRAVA_SUBSCRIPTION_ID` wins, else the app-level row). Cached 10 minutes. */
export async function stravaSubscriptionId(db?: SupabaseClient): Promise<string | null> {
  const fromEnv = Deno.env.get("STRAVA_SUBSCRIPTION_ID")
  if (fromEnv) return fromEnv
  if (cachedSubscription && Date.now() - cachedSubscription.at < 600_000) return cachedSubscription.id
  const client = db ?? serviceClient()
  const { data } = await client.from("wearable_webhook_subscriptions").select("vendor_subscription_id").eq("vendor", "strava").is("account_id", null).eq("status", "active").order("created_at", { ascending: false }).limit(1).maybeSingle()
  const id = (data as { vendor_subscription_id?: string | null } | null)?.vendor_subscription_id ?? null
  cachedSubscription = { id, at: Date.now() }
  return id
}

export interface StravaWebhookRegistration { action: "kept" | "created"; id: string; url: string }

/**
 * Creates Strava's single push subscription from the backend (client credentials in the body). Strava calls the GET
 * challenge on `wearable-vendor-webhook/strava` DURING this request, so `STRAVA_WEBHOOK_VERIFY_TOKEN` must be set
 * before it runs. An existing subscription pointing at our URL is kept; one pointing elsewhere is an error (Strava
 * allows one per app — delete it in the Strava settings or with the API first; we never delete someone else's).
 */
export async function stravaRegisterWebhook(db: SupabaseClient, opts: { fetchImpl?: typeof fetch } = {}): Promise<StravaWebhookRegistration> {
  const f = opts.fetchImpl ?? fetch
  const { clientId, clientSecret } = vendorClient("strava")
  const verifyToken = Deno.env.get("STRAVA_WEBHOOK_VERIFY_TOKEN")
  if (!verifyToken) throw new Error("STRAVA_WEBHOOK_VERIFY_TOKEN unset")
  const url = webhookUrl("strava")
  const list = await f(`${STRAVA_SUBSCRIPTIONS}?${new URLSearchParams({ client_id: clientId, client_secret: clientSecret })}`, { headers: { Accept: "application/json" } })
  if (!list.ok) throw new VendorHttpError(list.status, "strava subscriptions list")
  const existing = (await list.json()) as { id: number | string; callback_url: string }[]
  let id: string, action: "kept" | "created"
  const ours = existing.find((s) => s.callback_url === url)
  if (ours) { id = String(ours.id); action = "kept" }
  else if (existing.length) throw new Error("another Strava push subscription exists for this app (one per app)")
  else {
    const create = await f(STRAVA_SUBSCRIPTIONS, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" }, body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, callback_url: url, verify_token: verifyToken }) })
    if (!create.ok) throw new VendorHttpError(create.status, `strava subscription create: ${(await create.text()).slice(0, 200)}`)
    id = String(((await create.json()) as { id: number | string }).id)
    action = "created"
  }
  await db.from("wearable_webhook_subscriptions").update({ status: "revoked", updated_at: new Date().toISOString() }).eq("vendor", "strava").is("account_id", null).eq("status", "active").neq("vendor_subscription_id", id)
  const { data: held } = await db.from("wearable_webhook_subscriptions").select("id").eq("vendor", "strava").is("account_id", null).eq("status", "active").eq("vendor_subscription_id", id).maybeSingle()
  if (!held) {
    const { error } = await db.from("wearable_webhook_subscriptions").insert({ vendor: "strava", vendor_subscription_id: id, data_type: "activity,athlete", event_type: "push_subscription", callback_url: url, status: "active", meta: { registered_by: "backend" } })
    if (error) throw new Error(`strava subscription row: ${error.message}`)
  }
  cachedSubscription = null
  log("info", "strava.webhook_registered", { fn: FN, vendor: "strava", action, id })
  return { action, id, url }
}
