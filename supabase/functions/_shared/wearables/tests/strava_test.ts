// Strava adapter (2026-11-06): OAuth contract, the activities → workout-epoch golden trace (local day from
// `start_date_local`, no daily rows, kilojoules never turned into kcal), rate-limit/401 taxonomy, and the unsigned
// webhook treated as a hint only (subscription filter, a deauthorisation never revokes by itself).
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1"
import { RateLimitedError, T, UnauthorizedError, VENDOR_SOURCE_IDS } from "../core.ts"
import { activityRows, secondsToNextQuarter, strava, _stravaTest } from "../strava.ts"
import { adapter } from "../registry.ts"
import { aiPolicy } from "../ai-policy.ts"
import { authorizeCheck, secretPresence } from "../readiness.ts"

Deno.env.set("STRAVA_CLIENT_ID", "54321")
Deno.env.set("STRAVA_CLIENT_SECRET", "test-strava-secret")

const fixture = async (name: string) => JSON.parse(await Deno.readTextFile(new URL(`./fixtures/strava/${name}`, import.meta.url)))
const REDIRECT = "https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-oauth-callback"
const tokens = { accessToken: "at-1" }
const ctx = { patientId: "patient-1", vendorUserId: "134815", meta: {} }

type Handler = (url: URL, init?: RequestInit) => Response | Promise<Response>
async function withFetch<R>(handler: Handler, fn: (calls: { url: URL; init?: RequestInit }[]) => Promise<R>): Promise<R> {
  const real = globalThis.fetch
  const calls: { url: URL; init?: RequestInit }[] = []
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url)
    calls.push({ url, init })
    return await handler(url, init)
  }) as typeof fetch
  try { return await fn(calls) } finally { globalThis.fetch = real }
}
const jsonResp = (body: unknown, status = 200, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...headers } })

Deno.test("adapter contract: registered, source id 1000070, no PKCE, read + activity:read_all, reconcile 7/30", () => {
  assertEquals(adapter("strava"), strava)
  assertEquals(VENDOR_SOURCE_IDS.strava, 1000070)
  assertEquals(strava.pkce, "not_documented")
  assertEquals(strava.scopes, ["read", "activity:read_all"])
  assertEquals(strava.reconcile, { nightlyDays: 7, weeklyDays: 30 })
})

Deno.test("authorizeURL: Strava web flow, comma-joined scopes, approval_prompt=auto, exact redirect, no code_challenge", () => {
  const u = new URL(strava.authorizeURL({ clientId: "54321", redirectUri: REDIRECT, state: "s-1", codeChallenge: "ignored" }))
  assertEquals(`${u.origin}${u.pathname}`, "https://www.strava.com/oauth/authorize")
  assertEquals(u.searchParams.get("scope"), "read,activity:read_all")
  assertEquals(u.searchParams.get("approval_prompt"), "auto")
  assertEquals(u.searchParams.get("response_type"), "code")
  assertEquals(u.searchParams.get("redirect_uri"), REDIRECT)
  assertEquals(u.searchParams.get("state"), "s-1")
  assertEquals(u.searchParams.has("code_challenge"), false)
})

Deno.test("exchangeCode: client credentials in the body, athlete.id → vendorUserId, expires_at kept as unix seconds", async () => {
  await withFetch(() => jsonResp({ token_type: "Bearer", expires_at: 1793621600, expires_in: 21600, refresh_token: "rt-1", access_token: "at-1", athlete: { id: 134815 } }), async (calls) => {
    const r = await strava.exchangeCode({ code: "c-1", redirectUri: REDIRECT })
    assertEquals(r.vendorUserId, "134815")
    assertEquals(r.expiresAt, 1793621600)
    assertEquals(r.refreshToken, "rt-1")
    assertEquals(calls[0].url.toString(), "https://www.strava.com/oauth/token")
    const body = new URLSearchParams(String(calls[0].init?.body))
    assertEquals(body.get("grant_type"), "authorization_code")
    assertEquals(body.get("client_id"), "54321")
    assertEquals(body.get("client_secret"), "test-strava-secret")
    assertEquals(body.get("code"), "c-1")
  })
})

Deno.test("refresh: a rotated refresh token is adopted, the old one kept when the reply omits it", async () => {
  await withFetch(() => jsonResp({ access_token: "at-2", refresh_token: "rt-2", expires_at: 1793700000 }), async () => {
    const r = await strava.refresh("rt-1")
    assertEquals([r.accessToken, r.refreshToken, r.expiresAt], ["at-2", "rt-2", 1793700000])
  })
  await withFetch(() => jsonResp({ access_token: "at-3", expires_at: 1793710000 }), async () => {
    assertEquals((await strava.refresh("rt-2")).refreshToken, "rt-2")
  })
})

Deno.test("golden trace: activities → workout epochs only, local day from start_date_local, window filter, no kcal from kJ", async () => {
  const page = await fixture("activities_page1.json")
  await withFetch((url) => {
    assertEquals(url.pathname, "/api/v3/athlete/activities")
    return jsonResp(page)
  }, async (calls) => {
    const out = await strava.fetchRange(tokens, "2026-11-01", "2026-11-03", ctx)
    assertEquals(out.daily, [])   // activities only: never daily totals
    // Query contract: one day of margin each side on the UTC filter, Bearer auth, one page (5 < per_page).
    assertEquals(calls.length, 1)
    assertEquals(calls[0].url.searchParams.get("after"), String(Date.parse("2026-10-31T00:00:00Z") / 1000))
    assertEquals(calls[0].url.searchParams.get("before"), String(Date.parse("2026-11-05T00:00:00Z") / 1000))
    assertEquals((calls[0].init?.headers as Record<string, string>).Authorization, "Bearer at-1")
    assertEquals(activityRows({ id: 9, start_date: "2026-11-03T23:15:00Z", start_date_local: "2026-11-04T00:15:00Z", utc_offset: 3600 })?.day, "2026-11-04")

    const ids = [...new Set(out.epoch.map((r) => r.sourceRecordId))]
    // 2026-10-31 22:00 local is outside the window even though the UTC filter fetched it; 00:15 local on 4 Nov is
    // outside too although its UTC start (3 Nov 23:15) is inside — the LOCAL day decides.
    assertEquals(ids, ["154504250376823", "154504250376824", "154504250376825"])

    const run = out.epoch.filter((r) => r.sourceRecordId === "154504250376823")
    // 23:30 local on 1 Nov = 22:30 UTC: the row keeps the UTC start, the local offset, and the end from elapsed_time.
    const type = run.find((r) => r.dataTypeId === T.ActivityType)!
    assertEquals(type.startTs, "2026-11-01T22:30:00Z")
    assertEquals(type.endTs, "2026-11-01T23:25:00.000Z")
    assertEquals(type.timezoneOffset, 60)
    assertEquals([type.value, type.valueText, type.valueType], [0, "TrailRun", "STRING"])
    assertEquals(type.details?.duration_min, 52)
    assertEquals(type.sourceResourceType, "activity")
    assertEquals(type.sourceDeviceId, "Garmin Forerunner 965")
    assertEquals(run.find((r) => r.dataTypeId === T.CoveredDistance)?.value, 10234.5)
    assertEquals(run.find((r) => r.dataTypeId === T.ElevationGain)?.value, 85.2)
    assertEquals(run.find((r) => r.dataTypeId === T.HeartRate)?.value, 151)

    const ride = out.epoch.filter((r) => r.sourceRecordId === "154504250376824")
    assertEquals(ride.find((r) => r.dataTypeId === T.HeartRate), undefined)                  // has_heartrate: false
    assertEquals(ride.find((r) => r.dataTypeId === T.ActiveBurnedCalories), undefined)       // kJ of work ≠ kcal burned
    assertEquals(ride.find((r) => r.dataTypeId === T.ActivityType)?.details?.kilojoules_work, 980.4)

    const yoga = out.epoch.filter((r) => r.sourceRecordId === "154504250376825")
    assertEquals(yoga.map((r) => r.dataTypeId), [T.ActivityType])                            // 0 m, 0 m+: no distance rows
    assertEquals(yoga[0].details?.manual, true)
    // The activity title never leaves Strava's payload.
    assert(!JSON.stringify(out.epoch).includes("Evening Run"))
  })
})

Deno.test("pagination: a full page asks for the next one; stops on a short page", async () => {
  const full = Array.from({ length: 100 }, (_, i) => ({ id: 1000 + i, start_date: "2026-11-02T08:00:00Z", start_date_local: "2026-11-02T09:00:00Z", utc_offset: 3600, moving_time: 600, elapsed_time: 600, sport_type: "Walk", distance: 900 }))
  await withFetch((url) => jsonResp(url.searchParams.get("page") === "1" ? full : []), async (calls) => {
    const out = await strava.fetchRange(tokens, "2026-11-02", "2026-11-02", ctx)
    assertEquals(calls.map((c) => c.url.searchParams.get("page")), ["1", "2"])
    assertEquals(out.epoch.filter((r) => r.dataTypeId === T.ActivityType).length, 100)
  })
})

Deno.test("errors: 429 → RateLimitedError until the next quarter hour; 401 → UnauthorizedError (refresh, then reconnect)", async () => {
  await withFetch(() => new Response("Rate Limit Exceeded", { status: 429, headers: { "X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "201,540" } }), async () => {
    const e = await assertRejects(() => strava.fetchRange(tokens, "2026-11-01", "2026-11-01", ctx), RateLimitedError)
    assert(e.retryAfter > 0 && e.retryAfter <= 900)
  })
  await withFetch(() => new Response('{"message":"Authorization Error"}', { status: 401 }), async () => {
    await assertRejects(() => strava.fetchRange(tokens, "2026-11-01", "2026-11-01", ctx), UnauthorizedError)
  })
  assertEquals(secondsToNextQuarter(new Date("2026-11-06T10:14:30Z")), 30)
  assertEquals(secondsToNextQuarter(new Date("2026-11-06T10:15:00Z")), 900)
})

Deno.test("challenge: answers hub.challenge only with our verify token; fails closed when the token is unset", () => {
  const url = (token: string) => new URL(`https://x/functions/v1/wearable-vendor-webhook/strava?hub.mode=subscribe&hub.verify_token=${token}&hub.challenge=15f7d1a91c1f40f8a748fd134752feb3`)
  Deno.env.delete("STRAVA_WEBHOOK_VERIFY_TOKEN")
  assertEquals(strava.challengeResponse!(url("anything"), "")?.status, 403)
  Deno.env.set("STRAVA_WEBHOOK_VERIFY_TOKEN", "our-verify-token")
  assertEquals(strava.challengeResponse!(url("wrong"), "")?.status, 403)
  const ok = strava.challengeResponse!(url("our-verify-token"), "")!
  assertEquals(ok.status, 200)
  assertEquals(strava.challengeResponse!(new URL("https://x/functions/v1/wearable-vendor-webhook/strava"), ""), null)
  return ok.json().then((b) => assertEquals(b, { "hub.challenge": "15f7d1a91c1f40f8a748fd134752feb3" }))
})

Deno.test("webhook: unsigned events are hints — subscription filter, deauthorisation never revokes, empty body → []", async () => {
  const req = new Request("https://x", { method: "POST" })
  const create = JSON.stringify(await fixture("webhook_activity_create.json"))
  const deauth = JSON.stringify(await fixture("webhook_deauthorize.json"))

  _stravaTest.resetSubscriptionCache(null)
  await assertRejects(async () => { await strava.parseWebhook(req, create, new URL("https://x")) }, Error, "not registered")
  _stravaTest.resetSubscriptionCache("999")
  await assertRejects(async () => { await strava.parseWebhook(req, create, new URL("https://x")) }, Error, "mismatch")

  _stravaTest.resetSubscriptionCache("120475")
  const [ev] = await strava.parseWebhook(req, create, new URL("https://x")) as { vendorUserId: string; kind: string; eventId: string; revoked?: boolean }[]
  assertEquals([ev.vendorUserId, ev.kind, ev.eventId], ["134815", "activity.create", "activity.create.154504250376823.1793600000"])

  const [d] = await strava.parseWebhook(req, deauth, new URL("https://x")) as { kind: string; revoked?: boolean }[]
  assertEquals(d.kind, "athlete.deauthorized")
  assertEquals(d.revoked, undefined)   // a forged body must not be able to unlink a member
  assertEquals(await strava.parseWebhook(req, "", new URL("https://x")), [])
})

Deno.test("activityRows: an activity without id or start is skipped, not guessed", () => {
  assertEquals(activityRows({ start_date: "2026-11-01T10:00:00Z" }), null)
  assertEquals(activityRows({ id: 1, start_date_local: "2026-11-01T10:00:00Z" }), null)
})

Deno.test("AI policy: Strava data never reaches a model and never leaves without review", () => {
  assertEquals(aiPolicy({ vendor: "strava", transport: "vendor_direct", purpose: "llm_prompt" }), "deny")
  assertEquals(aiPolicy({ vendor: "strava", transport: "vendor_direct", purpose: "export" }), "deny")
  assertEquals(aiPolicy({ vendor: "strava", transport: "vendor_direct", purpose: "member_display" }), "allow")
})

Deno.test("readiness probe: describes the authorize URL without its values; names → booleans only", () => {
  const ok = authorizeCheck(strava, "54321", REDIRECT)
  assertEquals(ok.ok, true)
  assertEquals([ok.origin, ok.path, ok.redirectExact, ok.pkce], ["https://www.strava.com", "/oauth/authorize", true, false])
  assertEquals(ok.params, ["approval_prompt", "client_id", "redirect_uri", "response_type", "scope", "state"])
  assert(!JSON.stringify(ok).includes("54321"))
  assertEquals(authorizeCheck(strava, undefined, REDIRECT), { ok: false, error: "STRAVA_CLIENT_ID unset" })
  const p = secretPresence(["STRAVA_CLIENT_SECRET", "STRAVA_NOT_A_SECRET?"])
  assertEquals(p, { STRAVA_CLIENT_SECRET: true, "STRAVA_NOT_A_SECRET?": false })
})
