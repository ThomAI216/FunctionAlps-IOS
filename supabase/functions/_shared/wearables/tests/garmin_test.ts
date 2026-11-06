// Garmin adapter (rebuilt 2026-11-06). The OAuth/user-management contract is pinned to Garmin's public OAuth2 PKCE
// specification; the summary MAPPING tests below use small hand-written objects that exercise OUR rules (units,
// sentinels, D4, day basis, what is never stored). They are NOT contract fixtures: the field names are VERIFY until
// a sanitised real push replaces them (corpus rule: no fabricated payloads as contract tests). Nothing here reaches
// the network — `globalThis.fetch` is stubbed per test.
import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1"
import { T, UnauthorizedError, type AccountContext, type TokenSet } from "../core.ts"
import { GARMIN_API, HRV_RMSSD_CONFIRMED, garmin, mapSummary, pingWindow, summaryDay } from "../garmin.ts"

Deno.env.set("GARMIN_CLIENT_ID", "garmin-client")
Deno.env.set("GARMIN_CLIENT_SECRET", "garmin-secret")

const tokens: TokenSet = { accessToken: "at-1" }
const ctx: AccountContext = { patientId: "p", vendorUserId: "u-1", meta: {} }
const REDIRECT = "https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-oauth-callback"
const HOOK = "https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-vendor-webhook/garmin"

type Call = { url: URL; init?: RequestInit }
async function withFetch<R>(handler: (url: URL, init?: RequestInit) => Response, fn: (calls: Call[]) => Promise<R> | R): Promise<R> {
  const real = globalThis.fetch
  const calls: Call[] = []
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url)
    calls.push({ url, init })
    return handler(url, init)
  }) as typeof fetch
  try { return await fn(calls) } finally { globalThis.fetch = real }
}
const noNetwork = () => { throw new Error("network call attempted") }
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } })
const post = (body: unknown, query = "") => ({ req: new Request(`${HOOK}${query}`, { method: "POST", headers: { "garmin-client-id": "garmin-client" } }), raw: JSON.stringify(body), url: new URL(`${HOOK}${query}`) })

Deno.test("contract: PKCE required, scope fixed by Garmin, reconcile 3/14, HRV gate closed (D4)", () => {
  assertEquals([garmin.key, garmin.name, garmin.pkce], ["garmin", "Garmin", "required"])
  assertEquals(garmin.scopes, [])
  assertEquals(garmin.reconcile, { nightlyDays: 3, weeklyDays: 14 })
  assertEquals(HRV_RMSSD_CONFIRMED, false)
})

Deno.test("authorizeURL: connect.garmin.com/oauth2Confirm with S256 challenge; refuses to build without PKCE", () => {
  const u = new URL(garmin.authorizeURL({ clientId: "garmin-client", redirectUri: REDIRECT, state: "s-1", codeChallenge: "ch-1" }))
  assertEquals(`${u.origin}${u.pathname}`, "https://connect.garmin.com/oauth2Confirm")
  assertEquals(Object.fromEntries(u.searchParams), { response_type: "code", client_id: "garmin-client", code_challenge: "ch-1", code_challenge_method: "S256", redirect_uri: REDIRECT, state: "s-1" })
  assertThrows(() => garmin.authorizeURL({ clientId: "c", redirectUri: REDIRECT, state: "s" }), Error, "PKCE")
})

Deno.test("exchangeCode: token on connectapi with the verifier, then /user/id with the new bearer; refresh 600 s early", () =>
  withFetch((url) => url.host === "connectapi.garmin.com"
    ? json({ access_token: "at-1", token_type: "bearer", refresh_token: "rt-1", expires_in: 86400, scope: "PARTNER_WRITE PARTNER_READ CONNECT_READ CONNECT_WRITE", refresh_token_expires_in: 7775998 })
    : json({ userId: "4aacafe82427c251df9c9592d0c06768" }), async (calls) => {
    const before = Math.floor(Date.now() / 1000)
    const r = await garmin.exchangeCode({ code: "c-1", redirectUri: REDIRECT, codeVerifier: "v-1" })
    assertEquals(calls[0].url.toString(), "https://connectapi.garmin.com/di-oauth2-service/oauth/token")
    const b = new URLSearchParams(String(calls[0].init?.body))
    assertEquals(Object.fromEntries(b), { grant_type: "authorization_code", client_id: "garmin-client", client_secret: "garmin-secret", code: "c-1", code_verifier: "v-1", redirect_uri: REDIRECT })
    assertEquals(calls[1].url.toString(), `${GARMIN_API}/user/id`)
    assertEquals((calls[1].init?.headers as Record<string, string>).Authorization, "Bearer at-1")
    assertEquals(r.vendorUserId, "4aacafe82427c251df9c9592d0c06768")
    assertEquals(r.refreshToken, "rt-1")
    assert(r.expiresAt! >= before + 86400 - 600 && r.expiresAt! <= before + 86400 - 600 + 5)
    await assertRejects(() => garmin.exchangeCode({ code: "c", redirectUri: REDIRECT }), Error, "verifier")
  }))

Deno.test("refresh: same token URL, grant refresh_token; the new refresh token Garmin returns every time is adopted", () =>
  withFetch(() => json({ access_token: "at-2", refresh_token: "rt-2", expires_in: 86400 }), async (calls) => {
    const r = await garmin.refresh("rt-1")
    assertEquals([r.accessToken, r.refreshToken], ["at-2", "rt-2"])
    assertEquals(new URLSearchParams(String(calls[0].init?.body)).get("grant_type"), "refresh_token")
    assertEquals(calls[0].url.host, "connectapi.garmin.com")
  }))

Deno.test("revoke: DELETE /user/registration (required on our own disconnect); 401/404 = already gone; 5xx throws", async () => {
  await withFetch(() => new Response(null, { status: 204 }), async (calls) => {
    await garmin.revoke!(tokens, ctx)
    assertEquals([calls[0].init?.method, calls[0].url.toString()], ["DELETE", `${GARMIN_API}/user/registration`])
  })
  await withFetch(() => new Response(null, { status: 401 }), async () => { await garmin.revoke!(tokens, ctx) })
  await withFetch(() => new Response("boom", { status: 503 }), async () => { await assertRejects(() => garmin.revoke!(tokens, ctx)) })
})

Deno.test("afterConnect: permissions + one 30-day backfill per type, recorded by status; a Starter refusal never throws", () =>
  withFetch((url) => url.pathname.endsWith("/user/permissions") ? json(["HEALTH_EXPORT", "ACTIVITY_EXPORT"]) : new Response("not allowed", { status: 403 }), async (calls) => {
    const r = await garmin.afterConnect!(tokens, { patientId: "p", webhookUrl: HOOK, vendorUserId: "u-1" })
    assertEquals(r.meta?.permissions, ["HEALTH_EXPORT", "ACTIVITY_EXPORT"])
    const bf = r.meta?.backfill_status as Record<string, number>
    assertEquals(bf.dailies, 403)
    const one = calls.find((c) => c.url.pathname.endsWith("/backfill/dailies"))!
    const s = Number(one.url.searchParams.get("summaryStartTimeInSeconds")), e = Number(one.url.searchParams.get("summaryEndTimeInSeconds"))
    assertEquals(e - s, 30 * 86_400)
  }))

Deno.test("webhook auth: our ?token= secret, constant time; unset fails closed; the garmin-client-id header alone is never enough", () => {
  const body = { dailies: [{ userId: "u-1", summaryId: "d1", calendarDate: "2026-11-05", steps: 8000 }] }
  Deno.env.delete("GARMIN_WEBHOOK_TOKEN")
  const a = post(body, "?token=anything")
  assertThrows(() => garmin.parseWebhook(a.req, a.raw, a.url), Error, "unset")
  Deno.env.set("GARMIN_WEBHOOK_TOKEN", "hook-secret-1")
  const b = post(body)
  assertThrows(() => garmin.parseWebhook(b.req, b.raw, b.url), Error, "mismatch")
  const c = post(body, "?token=hook-secret-2")
  assertThrows(() => garmin.parseWebhook(c.req, c.raw, c.url), Error, "mismatch")
  const ok = post(body, "?token=hook-secret-1")
  assertEquals((garmin.parseWebhook(ok.req, ok.raw, ok.url) as unknown[]).length, 1)
})

Deno.test("webhook push: rows grouped per user with the day window; deregistration revokes; PING only yields a window", () => {
  Deno.env.set("GARMIN_WEBHOOK_TOKEN", "hook-secret-1")
  const p = post({
    dailies: [{ userId: "u-1", summaryId: "d1", calendarDate: "2026-11-04", steps: 9000 }, { userId: "u-2", summaryId: "d2", calendarDate: "2026-11-05", steps: 100 }],
    bodyComps: [{ userId: "u-1", summaryId: "b1", measurementTimeInSeconds: 1793865600, measurementTimeOffsetInSeconds: 3600, weightInGrams: 72450 }],
    deregistrations: [{ userId: "u-3" }],
    sleeps: [{ userId: "u-4", callbackURL: "https://apis.garmin.com/wellness-api/rest/sleeps?uploadStartTimeInSeconds=1793836800&uploadEndTimeInSeconds=1793923200" }],
    hrv: [{ userId: "u-5", callbackURL: "https://evil.example/wellness-api/rest/hrv?uploadStartTimeInSeconds=1&uploadEndTimeInSeconds=2" }],
  }, "?token=hook-secret-1")
  const evs = garmin.parseWebhook(p.req, p.raw, p.url) as { vendorUserId: string; kind: string; revoked?: boolean; rows?: { daily: { day: string; dataTypeId: number; value: number | null }[] }; windowStart?: string; windowEnd?: string }[]
  const by = Object.fromEntries(evs.map((e) => [e.vendorUserId, e]))
  assertEquals(Object.keys(by).sort(), ["u-1", "u-2", "u-3", "u-4"])   // u-5's foreign callback host is dropped
  assertEquals(by["u-1"].rows!.daily.map((r) => [r.day, r.dataTypeId, r.value]), [["2026-11-04", T.Steps, 9000], ["2026-11-05", T.Weight, 72.45]])
  assertEquals([by["u-1"].windowStart, by["u-1"].windowEnd], ["2026-11-04", "2026-11-05"])
  assertEquals([by["u-3"].revoked, by["u-3"].rows], [true, undefined])
  assertEquals([by["u-4"].kind, by["u-4"].windowStart, by["u-4"].windowEnd, by["u-4"].rows], ["ping:sleeps", "2026-11-05", "2026-11-06", undefined])
})

Deno.test("pingWindow: only https://apis.garmin.com/wellness-api/rest/… with a sane upload window", () => {
  assertEquals(pingWindow("https://apis.garmin.com/wellness-api/rest/dailies?uploadStartTimeInSeconds=1793836800&uploadEndTimeInSeconds=1793840400"), { start: "2026-11-05", end: "2026-11-05" })
  assertEquals(pingWindow("http://apis.garmin.com/wellness-api/rest/dailies?uploadStartTimeInSeconds=1&uploadEndTimeInSeconds=2"), null)
  assertEquals(pingWindow("https://apis.garmin.com.evil.example/wellness-api/rest/dailies?uploadStartTimeInSeconds=1&uploadEndTimeInSeconds=2"), null)
  assertEquals(pingWindow("https://apis.garmin.com/other?uploadStartTimeInSeconds=1&uploadEndTimeInSeconds=2"), null)
  assertEquals(pingWindow("https://apis.garmin.com/wellness-api/rest/dailies?uploadStartTimeInSeconds=5&uploadEndTimeInSeconds=2"), null)
  assertEquals(pingWindow("not a url"), null)
})

Deno.test("mapping rules — dailies: negative stress sentinel dropped, total kcal only from both parts, seconds → whole minutes", () => {
  const { daily } = mapSummary("dailies", { summaryId: "d1", calendarDate: "2026-11-05", startTimeOffsetInSeconds: 3600, steps: 10432, distanceInMeters: 7800.5, activeKilocalories: 512.4, bmrKilocalories: 1650, moderateIntensityDurationInSeconds: 1290, vigorousIntensityDurationInSeconds: 30, restingHeartRateInBeatsPerMinute: 52, averageStressLevel: -1, highStressDurationInSeconds: 0 })
  const v = (id: number) => daily.find((r) => r.dataTypeId === id)?.value
  assertEquals([v(T.Steps), v(T.CoveredDistance), v(T.ActiveBurnedCalories), v(T.BurnedCalories)], [10432, 7800.5, 512, 2162])
  assertEquals([v(T.ActivityMid), v(T.ActivityHigh), v(T.HeartRateResting)], [22, 1, 52])
  assertEquals([v(T.AverageStress), v(T.HighStress)], [undefined, undefined])
  assertEquals(daily[0].timezoneOffset, 60)
  assertEquals(daily[0].sourceRecordId, "d1")
  assertEquals(mapSummary("dailies", { calendarDate: "2026-11-05", activeKilocalories: 300 }).daily.find((r) => r.dataTypeId === T.BurnedCalories), undefined)
})

Deno.test("mapping rules — sleeps: stages in seconds, in-bed = asleep + awake, hypnogram epochs in minutes, score", () => {
  const start = 1793833200 // 2026-11-04T23:00:00Z
  const m = mapSummary("sleeps", { summaryId: "s1", calendarDate: "2026-11-05", startTimeInSeconds: start, startTimeOffsetInSeconds: 3600, durationInSeconds: 25200, deepSleepDurationInSeconds: 5400, lightSleepDurationInSeconds: 14400, remSleepInSeconds: 5400, awakeDurationInSeconds: 1200, overallSleepScore: { value: 81, qualifierKey: "GOOD" }, sleepLevelsMap: { deep: [{ startTimeInSeconds: start, endTimeInSeconds: start + 1800 }], awake: [{ startTimeInSeconds: start + 9000, endTimeInSeconds: start + 9600 }, { startTimeInSeconds: start + 20000, endTimeInSeconds: start + 20600 }] } })
  const v = (id: number) => m.daily.find((r) => r.dataTypeId === id)?.value
  assertEquals([v(T.MainSleepDuration), v(T.InBed), v(T.Deep), v(T.REM), v(T.Awake), v(T.Interruptions), v(T.SleepScore)], [25200, 26400, 5400, 5400, 1200, 2, 81])
  assertEquals(m.daily.find((r) => r.dataTypeId === T.SleepEnd)?.valueText, "2026-11-05T06:20:00.000Z")
  assertEquals(m.epoch.map((r) => [r.dataTypeId, r.value]), [[T.SleepDeepBinary, 30], [T.SleepAwakeBinary, 10], [T.SleepAwakeBinary, 10]])
})

Deno.test("mapping rules — HRV is written only once D4 is confirmed; then RMSSD night + 5-min epochs", () => {
  const it = { summaryId: "h1", calendarDate: "2026-11-05", startTimeInSeconds: 1793833200, lastNightAvg: 48, lastNight5MinHigh: 71, hrvValues: { "300": 45, "600": 52 } }
  assertEquals(mapSummary("hrv", it), { daily: [], epoch: [] })
  const on = mapSummary("hrv", it, { hrvConfirmed: true })
  assertEquals(on.daily.map((r) => [r.dataTypeId, r.value]), [[T.RmssdSleep, 48], [T.RmssdSleepHighest, 71]])
  assertEquals(on.epoch.map((r) => [r.startTs, r.value]), [["2026-11-04T23:05:00.000Z", 45], ["2026-11-04T23:10:00.000Z", 52]])
})

Deno.test("mapping rules — body comp grams → kg, Body Battery day high with the low in details, activity title never stored", () => {
  const bc = mapSummary("bodyComps", { summaryId: "b1", measurementTimeInSeconds: 1793865600, measurementTimeOffsetInSeconds: 3600, weightInGrams: 72450, muscleMassInGrams: 33100, bodyFatInPercent: 18.2 })
  assertEquals(bc.daily.map((r) => [r.day, r.dataTypeId, r.value]), [["2026-11-05", T.Weight, 72.45], ["2026-11-05", T.MuscleMass, 33.1], ["2026-11-05", T.FatRatio, 18.2]])
  const bb = mapSummary("stressDetails", { summaryId: "x", calendarDate: "2026-11-05", timeOffsetBodyBatteryValues: { "0": 35, "180": 88, "360": -1, "540": 61 } })
  assertEquals([bb.daily[0].dataTypeId, bb.daily[0].value, bb.daily[0].details?.day_low], [T.BodyBattery, 88, 35])
  const act = mapSummary("activities", { summaryId: "a1", activityId: 9, activityName: "Run with Anna", activityType: "RUNNING", startTimeInSeconds: 1793865600, startTimeOffsetInSeconds: 3600, durationInSeconds: 2700, activeKilocalories: 410.6, distanceInMeters: 7000, averageHeartRateInBeatsPerMinute: 148, deviceName: "Forerunner 965" })
  assert(!JSON.stringify(act).includes("Anna"))
  assertEquals(act.epoch.find((r) => r.dataTypeId === T.ActivityType)?.valueText, "RUNNING")
  assertEquals(act.epoch[0].sourceDeviceId, "Forerunner 965")
  assertEquals(mapSummary("epochs", { summaryId: "e", steps: 12 }), { daily: [], epoch: [] })   // not mapped on purpose
})

Deno.test("summaryDay: Garmin's calendarDate wins; otherwise the local day from start + offset", () => {
  assertEquals(summaryDay({ calendarDate: "2026-11-05", startTimeInSeconds: 0 }), "2026-11-05")
  assertEquals(summaryDay({ startTimeInSeconds: 1793833200, startTimeOffsetInSeconds: 3600 }), "2026-11-05")   // 23:00Z + 1 h
  assertEquals(summaryDay({ startTimeInSeconds: 1793833200, startTimeOffsetInSeconds: 0 }), "2026-11-04")
})

Deno.test("fetchRange: push-only tier pulls nothing; with GARMIN_PULL_ENABLED it pulls each type per 24 h upload window", async () => {
  Deno.env.delete("GARMIN_PULL_ENABLED")
  await withFetch(noNetwork, async () => assertEquals(await garmin.fetchRange(tokens, "2026-11-04", "2026-11-05", ctx), { daily: [], epoch: [] }))
  Deno.env.set("GARMIN_PULL_ENABLED", "1")
  try {
    await withFetch((url) => url.pathname.endsWith("/dailies") ? json([{ userId: "u-1", summaryId: "d1", calendarDate: "2026-11-04", steps: 5 }]) : url.pathname.endsWith("/mct") ? new Response("no permission", { status: 412 }) : json([]), async (calls) => {
      const out = await garmin.fetchRange(tokens, "2026-11-04", "2026-11-05", ctx)
      assertEquals(calls.filter((c) => c.url.pathname.endsWith("/dailies")).length, 2)   // two 24 h upload windows
      assertEquals(out.daily.filter((r) => r.dataTypeId === T.Steps).length, 2)
      assertEquals((calls[0].init?.headers as Record<string, string>).Authorization, "Bearer at-1")
    })
    await withFetch(() => new Response("expired", { status: 401 }), async () => {
      await assertRejects(() => garmin.fetchRange(tokens, "2026-11-04", "2026-11-04", ctx), UnauthorizedError)
    })
  } finally { Deno.env.delete("GARMIN_PULL_ENABLED") }
})
