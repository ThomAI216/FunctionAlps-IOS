// Golden trace for the Oura adapter (strategy Phase 2): fixtures under fixtures/oura/ → the EXACT rows, plus the
// webhook gates (signature, verification token fail-closed, derived event id), the rate-limit taxonomy and the
// `ouraMaintain()` flag. `globalThis.fetch` is stubbed; nothing here talks to the network.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1"
import { type RowBatch, RateLimitedError, T, hmacSha256 } from "../core.ts"
import { OURA_DELETE_WITHIN_HOURS, oura, ouraMaintain } from "../oura.ts"

const HRV_IDS = [T.Rmssd, T.RmssdSleep, T.RmssdSleepHighest, T.SDNN, T.SDRR]  // 3100 3106 3107 3112 3113
const fixture = (name: string) => Deno.readTextFile(new URL(`./fixtures/oura/${name}.json`, import.meta.url))
const tokens = { accessToken: "at-test" }
const ctx = { patientId: "patient-1", vendorUserId: "oura-user-1", meta: {} }

/** Serves fixtures/oura/<collection>.json for the four fixtured collections and an empty page for the rest. */
function stubFetch(handler: (url: string, init?: RequestInit) => Response | Promise<Response>) {
  const real = globalThis.fetch
  const calls: { url: string; init?: RequestInit }[] = []
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url
    calls.push({ url, init })
    return Promise.resolve(handler(url, init))
  }) as typeof fetch
  return { calls, restore: () => { globalThis.fetch = real } }
}
const jsonResp = (body: unknown, status = 200, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...headers } })
const FIXTURED = ["sleep", "daily_sleep", "daily_readiness", "daily_activity"]
async function collectionsHandler(url: string): Promise<Response> {
  const m = /\/v2\/usercollection\/([^?/]+)/.exec(url)
  const collection = m?.[1] ?? ""
  if (FIXTURED.includes(collection)) return jsonResp(JSON.parse(await fixture(collection)))
  return jsonResp({ data: [], next_token: null })
}

const row = (r: { dataTypeId: number; dataTypeName: string; value: number | null; day?: string; startTs?: string; sourceRecordId?: string | null }) => [r.dataTypeId, r.dataTypeName, r.value, r.day ?? r.startTs, r.sourceRecordId ?? null]

Deno.test("golden: fixtures → exact daily rows; no HRV id; the nap does not feed 2300; average_hrv stays raw in details", async () => {
  const f = stubFetch(collectionsHandler)
  let out: RowBatch
  try { out = await oura.fetchRange(tokens, "2026-09-13", "2026-09-13", ctx) } finally { f.restore() }

  assertEquals(out.daily.map(row), [
    // sleep (long_sleep only) — dailyMap emits numeric keys in ascending order
    [2200, "SleepEfficiency", 93, "2026-09-13", "sl-long-1"],
    [2300, "ThryveMainSleepDuration", 25200, "2026-09-13", "sl-long-1"],
    [2301, "ThryveMainSleepInBedDuration", 27000, "2026-09-13", "sl-long-1"],
    [2302, "ThryveMainSleepREMDuration", 5400, "2026-09-13", "sl-long-1"],
    [2303, "ThryveMainSleepDeepDuration", 6300, "2026-09-13", "sl-long-1"],
    [2305, "ThryveMainSleepLightDuration", 13500, "2026-09-13", "sl-long-1"],
    [2306, "ThryveMainSleepAwakeDuration", 1800, "2026-09-13", "sl-long-1"],
    [2307, "ThryveMainSleepLatency", 420, "2026-09-13", "sl-long-1"],
    [2402, "ThryveMainSleepInterruptions", 3, "2026-09-13", "sl-long-1"],
    [3001, "HeartRateResting", 48, "2026-09-13", "sl-long-1"],
    [3002, "HeartRateSleep", 54.5, "2026-09-13", "sl-long-1"],
    [3020, "HeartRateSleepLowest", 48, "2026-09-13", "sl-long-1"],
    [4002, "RespirationRateSleep", 14.2, "2026-09-13", "sl-long-1"],
    [2400, "ThryveMainSleepStartTime", 1789247400, "2026-09-13", "sl-long-1"],
    [2401, "ThryveMainSleepEndTime", 1789274400, "2026-09-13", "sl-long-1"],
    // daily_sleep
    [2201, "SleepQuality", 82, "2026-09-13", "ds-1"],
    [1000105, "SleepScore", 82, "2026-09-13", "ds-1"],
    // daily_readiness
    [1000100, "ReadinessScore", 77, "2026-09-13", "dr-1"],
    [1000106, "SkinTemperatureDeviation", -0.2, "2026-09-13", "dr-1"],
    // daily_activity (seconds → minutes for the activity buckets)
    [1000, "Steps", 8421, "2026-09-13", "da-1"],
    [1001, "CoveredDistance", 6900, "2026-09-13", "da-1"],
    [1010, "BurnedCalories", 2310, "2026-09-13", "da-1"],
    [1011, "ActiveBurnedCalories", 412, "2026-09-13", "da-1"],
    [1100, "ActivityDuration", 160, "2026-09-13", "da-1"],
    [1101, "ActivityLowBinary", 120, "2026-09-13", "da-1"],
    [1102, "ActivityMidBinary", 30, "2026-09-13", "da-1"],
    [1103, "ActivityHighBinary", 10, "2026-09-13", "da-1"],
    [1104, "ActivitySedentaryBinary", 500, "2026-09-13", "da-1"],
  ])

  // D4 HRV gate: no canonical HRV id anywhere; the vendor field is carried raw on the sleep-duration row only.
  for (const r of [...out.daily, ...out.epoch]) assert(!HRV_IDS.includes(r.dataTypeId as typeof HRV_IDS[number]), `row carries HRV id ${r.dataTypeId}`)
  const main = out.daily.find((r) => r.dataTypeId === T.MainSleepDuration)!
  assertEquals(main.details, { type: "long_sleep", average_hrv_unverified: 41 })
  assertEquals(main.sourceResourceType, "sleep")
  assertEquals(main.timezoneOffset, 120)
  assertEquals(main.valueType, "LONG")
  assertEquals(out.daily.filter((r) => r.dataTypeId === T.MainSleepDuration).length, 1)
  // The nap (sl-nap-1) feeds no daily row at all — 2300 and the other main-sleep ids see only the long_sleep.
  assertEquals(out.daily.filter((r) => r.sourceRecordId === "sl-nap-1"), [])
  // Every daily row has provenance: the Oura document id + the collection name.
  for (const r of out.daily) { assert(r.sourceRecordId, `no sourceRecordId on ${r.dataTypeId}`); assert(r.sourceResourceType, `no sourceResourceType on ${r.dataTypeId}`) }
  assertEquals(new Set(out.daily.map((r) => r.sourceResourceType)), new Set(["sleep", "daily_sleep", "daily_readiness", "daily_activity"]))
  assertEquals(out.daily.find((r) => r.dataTypeId === T.SleepScore)!.details, { contributors: { deep_sleep: 90, efficiency: 95, latency: 80, rem_sleep: 70, restfulness: 60, timing: 85, total_sleep: 88 } })
  assertEquals(out.daily.find((r) => r.dataTypeId === T.ReadinessScore)!.details, { contributors: { activity_balance: 80, body_temperature: 90, hrv_balance: 70, previous_day_activity: 75, previous_night: 85, recovery_index: 88, resting_heart_rate: 92, sleep_balance: 79 }, temperature_trend_deviation: -0.1 })
})

Deno.test("golden: fixtures → exact epoch rows; the nap lands as epochs tagged with its type", async () => {
  const f = stubFetch(collectionsHandler)
  let out: RowBatch
  try { out = await oura.fetchRange(tokens, "2026-09-13", "2026-09-13", ctx) } finally { f.restore() }

  assertEquals(out.epoch.map(row), [
    // long_sleep heart_rate series (null sample dropped), then its 5-min phases 4-2-2-1
    [3000, "HeartRate", 52, "2026-09-12T21:10:00.000Z", "sl-long-1"],
    [3000, "HeartRate", 50, "2026-09-12T21:15:00.000Z", "sl-long-1"],
    [2006, "SleepAwakeBinary", 5, "2026-09-12T21:10:00.000Z", "sl-long-1"],
    [2005, "SleepLightBinary", 5, "2026-09-12T21:15:00.000Z", "sl-long-1"],
    [2005, "SleepLightBinary", 5, "2026-09-12T21:20:00.000Z", "sl-long-1"],
    [2003, "SleepDeepBinary", 5, "2026-09-12T21:25:00.000Z", "sl-long-1"],
    // nap phases 4-2-2 (no heart_rate series in the fixture)
    [2006, "SleepAwakeBinary", 5, "2026-09-13T12:00:00.000Z", "sl-nap-1"],
    [2005, "SleepLightBinary", 5, "2026-09-13T12:05:00.000Z", "sl-nap-1"],
    [2005, "SleepLightBinary", 5, "2026-09-13T12:10:00.000Z", "sl-nap-1"],
    // daily_activity MET series (60 s interval)
    [1012, "MetabolicEquivalent", 1.2, "2026-09-13T02:00:00.000Z", "da-1"],
    [1012, "MetabolicEquivalent", 1.5, "2026-09-13T02:01:00.000Z", "da-1"],
  ])
  const nap = out.epoch.filter((r) => r.sourceRecordId === "sl-nap-1")
  assertEquals(nap.length, 3)
  for (const r of nap) {
    assertEquals(r.sourceResourceType, "sleep")
    assertEquals(r.timezoneOffset, 120)
    assertEquals(r.details, { type: "sleep", day: "2026-09-13", total_sleep_duration: 1500, time_in_bed: 1800, bedtime_start: "2026-09-13T14:00:00+02:00", bedtime_end: "2026-09-13T14:30:00+02:00" })
  }
  assertEquals(out.epoch[0].endTs, "2026-09-12T21:15:00.000Z")
  assertEquals(out.epoch[0].details, { type: "long_sleep" })
  assertEquals(out.epoch[9].sourceResourceType, "daily_activity")
  // The 5-min `hrv` series of the sleep document is not emitted under any id (D4).
  assertEquals(out.epoch.filter((r) => r.value === 40 || r.value === 42), [])
})

Deno.test("fetchRange pulls every collection once with the day window; heartrate uses the datetime window", async () => {
  const f = stubFetch(collectionsHandler)
  try { await oura.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx) } finally { f.restore() }
  const paths = f.calls.map((c) => new URL(c.url).pathname.replace("/v2/usercollection/", ""))
  assertEquals(paths, ["sleep", "daily_sleep", "daily_readiness", "daily_activity", "daily_spo2", "vO2_max", "daily_stress", "workout", "heartrate"])
  assertEquals(new URL(f.calls[0].url).searchParams.get("start_date"), "2026-09-12")
  assertEquals(new URL(f.calls[0].url).searchParams.get("end_date"), "2026-09-13")
  const hr = new URL(f.calls[8].url).searchParams
  assertEquals([hr.get("start_datetime"), hr.get("end_datetime")], ["2026-09-12T00:00:00Z", "2026-09-14T00:00:00Z"])
  for (const c of f.calls) assertEquals((c.init?.headers as Record<string, string>).Authorization, "Bearer at-test")
})

Deno.test("pagination follows next_token until absent", async () => {
  let page = 0
  const f = stubFetch((url) => {
    if (!/\/daily_activity/.test(url)) return jsonResp({ data: [], next_token: null })
    page++
    const next = new URL(url).searchParams.get("next_token")
    if (!next) return jsonResp({ data: [{ id: "da-p1", day: "2026-09-12", steps: 100 }], next_token: "cursor-2" })
    assertEquals(next, "cursor-2")
    return jsonResp({ data: [{ id: "da-p2", day: "2026-09-13", steps: 200 }], next_token: null })
  })
  let out: RowBatch
  try { out = await oura.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx) } finally { f.restore() }
  assertEquals(page, 2)
  assertEquals(out.daily.filter((r) => r.dataTypeId === T.Steps).map(row), [[1000, "Steps", 100, "2026-09-12", "da-p1"], [1000, "Steps", 200, "2026-09-13", "da-p2"]])
})

Deno.test("429 → RateLimitedError carrying Retry-After; an exhausted X-RateLimit-Remaining with more pages → RateLimitedError from X-RateLimit-Reset", async () => {
  const f1 = stubFetch(() => jsonResp({ detail: "rate limited" }, 429, { "Retry-After": "37" }))
  try {
    const e = await assertRejects(() => oura.fetchRange(tokens, "2026-09-13", "2026-09-13", ctx), RateLimitedError)
    assertEquals(e.retryAfter, 37)
  } finally { f1.restore() }
  const f2 = stubFetch(() => jsonResp({ data: [], next_token: "more" }, 200, { "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "45" }))
  try {
    const e = await assertRejects(() => oura.fetchRange(tokens, "2026-09-13", "2026-09-13", ctx), RateLimitedError)
    assertEquals(e.retryAfter, 45)
    assertEquals(f2.calls.length, 1)  // stopped before the second page
  } finally { f2.restore() }
})

Deno.test("adapter contract: pkce per corpus, reconcile 3/14, no email scope, the 72 h deletion bound", () => {
  assertEquals(oura.pkce, "not_documented")
  assertEquals(oura.reconcile, { nightlyDays: 3, weeklyDays: 14 })
  assert(!oura.scopes.includes("email"))
  assert(oura.scopes.includes("personal"))  // personal_info → vendor user id
  assertEquals(OURA_DELETE_WITHIN_HOURS, 72)
  const u = new URL(oura.authorizeURL({ clientId: "cid", redirectUri: "https://x/cb", state: "st", codeChallenge: "ignored" }))
  assertEquals(u.origin + u.pathname, "https://cloud.ouraring.com/oauth/authorize")
  assertEquals(u.searchParams.get("scope"), oura.scopes.join(" "))
  assertEquals(u.searchParams.get("code_challenge"), null)
})

// MARK: - Webhooks

const webhookBody = await fixture("webhook_event")
async function signedRequest(secret: string, body: string, ts = String(Math.floor(Date.now() / 1000))): Promise<Request> {
  const sig = (await hmacSha256(secret, ts + body)).toUpperCase()
  return new Request("https://fn.test/wearable-vendor-webhook/oura", { method: "POST", headers: { "x-oura-timestamp": ts, "x-oura-signature": sig, "Content-Type": "application/json" }, body })
}
const withEnv = async (vars: Record<string, string | null>, fn: () => Promise<void>) => {
  const prev: Record<string, string | undefined> = {}
  for (const [k, v] of Object.entries(vars)) { prev[k] = Deno.env.get(k); if (v == null) Deno.env.delete(k); else Deno.env.set(k, v) }
  try { await fn() } finally { for (const [k, v] of Object.entries(prev)) { if (v == null) Deno.env.delete(k); else Deno.env.set(k, v) } }
}

Deno.test("parseWebhook: a correct uppercase-hex HMAC over timestamp+raw body → one event with the derived eventId", async () => {
  await withEnv({ OURA_CLIENT_SECRET: "cs-test", OURA_WEBHOOK_VERIFICATION_TOKEN: "vt-test" }, async () => {
    const req = await signedRequest("cs-test", webhookBody)
    const events = await oura.parseWebhook(req, webhookBody, new URL(req.url))
    assertEquals(events, [{ vendorUserId: "oura-user-1", kind: "sleep.update", eventId: "sleep.update.sl-long-1" }])
  })
})

Deno.test("parseWebhook: a wrong secret, a lowercase-tampered body or a stale timestamp is rejected", async () => {
  await withEnv({ OURA_CLIENT_SECRET: "cs-test", OURA_WEBHOOK_VERIFICATION_TOKEN: "vt-test" }, async () => {
    const bad = await signedRequest("cs-other", webhookBody)
    await assertRejects(() => Promise.resolve(oura.parseWebhook(bad, webhookBody, new URL(bad.url))), Error, "signature mismatch")
    const ok = await signedRequest("cs-test", webhookBody)
    const tampered = webhookBody.replace("oura-user-1", "oura-user-2")
    await assertRejects(() => Promise.resolve(oura.parseWebhook(ok, tampered, new URL(ok.url))), Error, "signature mismatch")
    const stale = await signedRequest("cs-test", webhookBody, String(Math.floor(Date.now() / 1000) - 3600))
    await assertRejects(() => Promise.resolve(oura.parseWebhook(stale, webhookBody, new URL(stale.url))), Error, "too old")
  })
})

Deno.test("challenge: served only with the exact OURA_WEBHOOK_VERIFICATION_TOKEN", async () => {
  await withEnv({ OURA_CLIENT_SECRET: "cs-test", OURA_WEBHOOK_VERIFICATION_TOKEN: "vt-test" }, async () => {
    const good = oura.challengeResponse!(new URL("https://fn.test/wearable-vendor-webhook/oura?verification_token=vt-test&challenge=abc123"), "")!
    assertEquals(good.status, 200)
    assertEquals(await good.json(), { challenge: "abc123" })
    const wrong = oura.challengeResponse!(new URL("https://fn.test/wearable-vendor-webhook/oura?verification_token=vt-other&challenge=abc123"), "")!
    assertEquals(wrong.status, 401)
  })
})

Deno.test("fail closed: with OURA_WEBHOOK_VERIFICATION_TOKEN unset the challenge is refused and a correctly signed POST is rejected (no client-secret fallback)", async () => {
  await withEnv({ OURA_CLIENT_SECRET: "cs-test", OURA_WEBHOOK_VERIFICATION_TOKEN: null }, async () => {
    const warned: string[] = []
    const realWarn = console.warn
    console.warn = (line: string) => { warned.push(String(line)) }
    try {
      const r = oura.challengeResponse!(new URL("https://fn.test/wearable-vendor-webhook/oura?verification_token=cs-test&challenge=abc123"), "")!
      assertEquals(r.status, 401)
      const req = await signedRequest("cs-test", webhookBody)
      await assertRejects(() => Promise.resolve(oura.parseWebhook(req, webhookBody, new URL(req.url))), Error, "verification token unset")
    } finally { console.warn = realWarn }
    assertEquals(warned.filter((l) => l.includes('"event":"oura.webhook_token_unset"')).length, 2)
    for (const l of warned) { assert(!l.includes("cs-test")); assert(!l.includes("oura-user-1")) }
  })
})

// MARK: - Subscriptions

Deno.test("ouraMaintain: flag unset → skipped without any fetch", async () => {
  await withEnv({ OURA_MAINTAIN_SUBSCRIPTIONS: null, OURA_CLIENT_ID: "cid", OURA_CLIENT_SECRET: "cs-test", OURA_WEBHOOK_VERIFICATION_TOKEN: "vt-test" }, async () => {
    const f = stubFetch(() => { throw new Error("fetch must not be called") })
    try { assertEquals(await ouraMaintain(), { created: 0, renewed: 0, skipped: true }) } finally { f.restore() }
    assertEquals(f.calls.length, 0)
  })
  await withEnv({ OURA_MAINTAIN_SUBSCRIPTIONS: "0" }, async () => {
    const f = stubFetch(() => { throw new Error("fetch must not be called") })
    try { assertEquals(await ouraMaintain(), { created: 0, renewed: 0, skipped: true }) } finally { f.restore() }
    assertEquals(f.calls.length, 0)
  })
})

Deno.test("ouraMaintain: flag on → lists, renews the expiring one, creates the missing pairs with our verification token", async () => {
  await withEnv({ OURA_MAINTAIN_SUBSCRIPTIONS: "1", OURA_CLIENT_ID: "cid", OURA_CLIENT_SECRET: "cs-test", OURA_WEBHOOK_VERIFICATION_TOKEN: "vt-test", SUPABASE_URL: "https://proj.supabase.co" }, async () => {
    const soon = new Date(Date.now() + 2 * 86_400_000).toISOString(), later = new Date(Date.now() + 30 * 86_400_000).toISOString()
    const f = stubFetch((url, init) => {
      if (url.endsWith("/webhook/subscription") && (init?.method ?? "GET") === "GET") {
        return jsonResp([{ id: "sub-1", data_type: "sleep", event_type: "create", expiration_time: soon }, { id: "sub-2", data_type: "sleep", event_type: "update", expiration_time: later }])
      }
      return jsonResp({ id: "new" }, 201)
    })
    let res
    try { res = await ouraMaintain() } finally { f.restore() }
    assertEquals(res, { created: 14, renewed: 1 })  // 8 data types × 2 − the 2 that exist
    const renew = f.calls.filter((c) => c.url.includes("/webhook/subscription/renew/"))
    assertEquals(renew.map((c) => [c.url.split("/").pop(), c.init?.method]), [["sub-1", "PUT"]])
    const creates = f.calls.filter((c) => c.init?.method === "POST")
    assertEquals(creates.length, 14)
    const body = JSON.parse(String(creates[0].init?.body))
    assertEquals(body, { callback_url: "https://proj.supabase.co/functions/v1/wearable-vendor-webhook/oura", verification_token: "vt-test", event_type: "create", data_type: "daily_sleep" })
    for (const c of f.calls) assertEquals((c.init?.headers as Record<string, string>)["x-client-secret"], "cs-test")
  })
})
