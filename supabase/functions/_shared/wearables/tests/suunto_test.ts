// Suunto adapter golden trace (Phase 2): fixtures/suunto/* → the EXACT catalogue rows, the webhook signature
// matrix (lowercase hex only), the raw-only HRV rule (no 3100/3106/3112/3113), the categorical recovery rows
// (1000134/1000135 STRING, never 1000109), provenance on every row, and the error semantics of the VERIFY endpoints.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1"
import { type DailyRow, type EpochRow, RateLimitedError, UnauthorizedError, hmacSha256 } from "../core.ts"
import { _suuntoTest, suunto } from "../suunto.ts"

const FX = new URL("./fixtures/suunto/", import.meta.url)
const fixture = (name: string) => Deno.readTextFile(new URL(name, FX))
const ctx = { patientId: "patient-1", vendorUserId: "suunto-user-1", meta: {}, accountId: "acc-1" }
const tokens = { accessToken: "jwt-access" }

Deno.env.set("SUUNTO_SUBSCRIPTION_KEY", "sub-key")
Deno.env.set("SUUNTO_CLIENT_ID", "client-id")
Deno.env.set("SUUNTO_CLIENT_SECRET", "client-secret")
Deno.env.set("SUUNTO_WEBHOOK_SECRET", "notification-secret")

const FILES: Record<string, string> = {
  "/247samples/sleep": "sleep_247.json", "/247samples/recovery": "recovery_247.json", "/247samples/activity": "activity_247.json",
  "/247/daily-activity-statistics": "daily_activity_statistics.json", "/v3/workouts": "workouts.json",
}

/** Stubs fetch for one test: fixture per path, or an override `(path) => Response`. Records every request. */
async function withFetch<R>(fn: () => Promise<R>, override?: (path: string, req: { url: string; headers: Headers; body?: string }) => Response | null): Promise<{ result: R; calls: { url: string; headers: Headers; body?: string }[] }> {
  const real = globalThis.fetch, calls: { url: string; headers: Headers; body?: string }[] = []
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input), headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined))
    const body = init?.body ? String(init.body) : undefined
    calls.push({ url, headers, body })
    const path = new URL(url).pathname
    const o = override?.(path, { url, headers, body })
    if (o) return o
    const file = FILES[path]
    return file ? new Response(await fixture(file), { status: 200, headers: { "Content-Type": "application/json" } }) : new Response("not found", { status: 404 })
  }) as typeof fetch
  try { return { result: await fn(), calls } } finally { globalThis.fetch = real }
}

const sleepProv = { timezoneOffset: 120, sourceRecordId: "1757738520", sourceResourceType: "247_sleep" }
const sleepBase = { sleep_id: "1757738520", avg_hrv_unverified: 58, avg_hrv_sample_count: 121, sleep_quality_score_unverified: 78 }
const sleepDuration = (id: number, name: string, value: number): DailyRow => ({ day: "2026-09-13", dataTypeId: id, dataTypeName: name, value, valueType: "LONG", details: { ...sleepBase, unit_unverified: true }, ...sleepProv })
const recDaily = { balance_scale_unverified: true, stress_state_scale_unverified: true, sample_ts: "2026-09-13T20:00:00+02:00" }
const recEpoch = (ts: string, id: number, name: string, text: string, bal: number, state: number): EpochRow => ({
  startTs: new Date(Date.parse(ts)).toISOString(), dataTypeId: id, dataTypeName: name, value: null, valueText: text, valueType: "STRING",
  timezoneOffset: 120, sourceRecordId: ts, sourceResourceType: "247_recovery", details: { balance_scale_unverified: true, stress_state_scale_unverified: true, balance_raw: bal, stress_state_raw: state },
})
const actRaw = (hrv: number | null, spo2: number | null, energy: number | null) => ({ hrv_unverified: hrv, spo2_unverified: spo2, energy_consumption_unverified: energy })
const wkRaw = { workout_key: "wk-abc123", activity_id: "3", total_time_unverified: 3600, energy_consumption_unverified: 2500000 }
const wkProv = { sourceRecordId: "wk-abc123", sourceResourceType: "workout" }

Deno.test("golden: fetchRange over the Suunto fixtures → the exact daily and epoch rows", async () => {
  const { result, calls } = await withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx))
  // Both secrets on every data call (§12); the window is ms epoch (VERIFY §21); every VERIFY path is called once.
  assertEquals(calls.map((c) => new URL(c.url).pathname), Object.keys(FILES))
  for (const c of calls) { assertEquals(c.headers.get("Authorization"), "Bearer jwt-access"); assertEquals(c.headers.get("Ocp-Apim-Subscription-Key"), "sub-key") }
  assertEquals(new URL(calls[0].url).search, "?from=1789171200000&to=1789343999000")

  assertEquals(result.daily, [
    sleepDuration(2300, "ThryveMainSleepDuration", 25920), sleepDuration(2303, "ThryveMainSleepDeepDuration", 5400), sleepDuration(2305, "ThryveMainSleepLightDuration", 14400),
    sleepDuration(2302, "ThryveMainSleepREMDuration", 4800), sleepDuration(2307, "ThryveMainSleepLatency", 600),
    sleepDuration(2306, "ThryveMainSleepAwakeDuration", 720),          // WakeAfterSleepOnsetDuration = awake during the night
    sleepDuration(2308, "ThryveMainSleepAwakeAfterWakeup", 300),       // WakeBeforeOffBedDuration = awake before leaving the bed
    { day: "2026-09-13", dataTypeId: 3002, dataTypeName: "HeartRateSleep", value: 52, valueType: "LONG", details: sleepBase, ...sleepProv },
    { day: "2026-09-13", dataTypeId: 3020, dataTypeName: "HeartRateSleepLowest", value: 45, valueType: "LONG", details: sleepBase, ...sleepProv },
    { day: "2026-09-13", dataTypeId: 2400, dataTypeName: "ThryveMainSleepStartTime", value: 1789246680, valueText: "2026-09-12T20:58:00.000Z", valueType: "DATE", details: sleepBase, ...sleepProv },
    { day: "2026-09-13", dataTypeId: 2401, dataTypeName: "ThryveMainSleepEndTime", value: 1789274520, valueText: "2026-09-13T04:42:00.000Z", valueType: "DATE", details: sleepBase, ...sleepProv },
    // recovery: the latest sample of the day, as TEXT (Balance has no pinned scale; StressState is categorical)
    { day: "2026-09-13", dataTypeId: 1000134, dataTypeName: "SuuntoRecoveryBalance", value: null, valueText: "65", valueType: "STRING", timezoneOffset: 120, sourceRecordId: "2026-09-13T20:00:00+02:00", sourceResourceType: "247_recovery", details: recDaily },
    { day: "2026-09-13", dataTypeId: 1000135, dataTypeName: "SuuntoStressState", value: null, valueText: "4", valueType: "STRING", timezoneOffset: 120, sourceRecordId: "2026-09-13T20:00:00+02:00", sourceResourceType: "247_recovery", details: recDaily },
    { day: "2026-09-13", dataTypeId: 1000, dataTypeName: "Steps", value: 8421, valueType: "LONG", timezoneOffset: 120, sourceRecordId: "2026-09-13", sourceResourceType: "247_daily_activity_statistics", details: { energy_consumption_unverified: 9800000 } },
  ])
  assertEquals(result.epoch, [
    recEpoch("2026-09-13T08:00:00+02:00", 1000134, "SuuntoRecoveryBalance", "72", 72, 2), recEpoch("2026-09-13T08:00:00+02:00", 1000135, "SuuntoStressState", "2", 72, 2),
    recEpoch("2026-09-13T20:00:00+02:00", 1000134, "SuuntoRecoveryBalance", "65", 65, 4), recEpoch("2026-09-13T20:00:00+02:00", 1000135, "SuuntoStressState", "4", 65, 4),
    { startTs: "2026-09-13T08:00:00.000Z", dataTypeId: 3000, dataTypeName: "HeartRate", value: 71, valueType: "LONG", timezoneOffset: 120, sourceRecordId: "2026-09-13T10:00:00+02:00", sourceResourceType: "247_activity", details: actRaw(44, 0.97, 125600) },
    { startTs: "2026-09-13T08:00:00.000Z", dataTypeId: 1000, dataTypeName: "Steps", value: 340, valueType: "LONG", timezoneOffset: 120, sourceRecordId: "2026-09-13T10:00:00+02:00", sourceResourceType: "247_activity", details: actRaw(44, 0.97, 125600) },
    { startTs: "2026-09-13T08:10:00.000Z", dataTypeId: 1000, dataTypeName: "Steps", value: 120, valueType: "LONG", timezoneOffset: 120, sourceRecordId: "2026-09-13T10:10:00+02:00", sourceResourceType: "247_activity", details: actRaw(null, null, null) },
    { startTs: "2026-09-13T09:40:00.000Z", dataTypeId: 1200, dataTypeName: "ActivityType", value: null, valueText: "suunto_activity_3", valueType: "STRING", ...wkProv, details: wkRaw },
    { startTs: "2026-09-13T09:40:00.000Z", dataTypeId: 1001, dataTypeName: "CoveredDistance", value: 10250, valueType: "LONG", ...wkProv, details: { ...wkRaw, unit_unverified: true } },
    { startTs: "2026-09-13T09:40:00.000Z", dataTypeId: 3000, dataTypeName: "HeartRate", value: 148, valueType: "LONG", ...wkProv, details: { ...wkRaw, statistic: "workout_average" } },
  ])
})

Deno.test("invariants: HRV raw-only, categorical recovery rows, provenance everywhere, no zeros for absent fields", async () => {
  const { result } = await withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx))
  const all = [...result.daily, ...result.epoch]
  const ids = new Set(all.map((r) => r.dataTypeId))
  for (const forbidden of [3100, 3106, 3112, 3113, 1000109, 2201, 1000105, 3001, 1000110]) assert(!ids.has(forbidden), `${forbidden} must not be written`)
  // AvgHRV / HRV survive only inside details
  for (const r of result.daily.filter((r) => r.sourceResourceType === "247_sleep")) assertEquals(r.details?.avg_hrv_unverified, 58)
  assertEquals(result.epoch.find((r) => r.sourceResourceType === "247_activity")?.details?.hrv_unverified, 44)
  // 1000134 / 1000135: STRING, value null, never a number
  for (const r of all.filter((r) => r.dataTypeId === 1000134 || r.dataTypeId === 1000135)) { assertEquals(r.valueType, "STRING"); assertEquals(r.value, null); assertEquals(typeof r.valueText, "string") }
  assert(all.some((r) => r.dataTypeId === 1000134) && all.some((r) => r.dataTypeId === 1000135))
  // provenance + the duration flag
  for (const r of all) { assert(r.sourceRecordId, `sourceRecordId missing on ${r.dataTypeId}`); assert(r.sourceResourceType, `sourceResourceType missing on ${r.dataTypeId}`) }
  for (const r of result.daily.filter((r) => [2300, 2302, 2303, 2305, 2306, 2307, 2308].includes(r.dataTypeId))) assertEquals(r.details?.unit_unverified, true)
  // the nap is excluded; the sparse activity sample yields no HR row; nothing is 0
  assertEquals(result.daily.filter((r) => r.sourceRecordId === "1757766900").length, 0)
  assertEquals(result.epoch.filter((r) => r.sourceRecordId === "2026-09-13T10:10:00+02:00").map((r) => r.dataTypeId), [1000])
  assert(all.every((r) => r.value !== 0))
})

Deno.test("fetchRange: an unverified endpoint failing is skipped; 401 and 429 propagate for the core refresh/backoff paths", async () => {
  const { result } = await withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx), (path) => path === "/v3/workouts" ? new Response("boom", { status: 500 }) : null)
  assertEquals(result.epoch.filter((r) => r.sourceResourceType === "workout"), [])
  assertEquals(result.daily.length, 14)
  await assertRejects(() => withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx), () => new Response("expired", { status: 401 })), UnauthorizedError)
  await assertRejects(() => withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx), () => new Response("slow down", { status: 429, headers: { "Retry-After": "30" } })), RateLimitedError)
})

Deno.test("parseWebhook: lowercase-hex HMAC over the exact body is accepted → rows, VERIFY-triple eventId, window", async () => {
  const body = await fixture("webhook_sleep_created.json")
  const sig = await hmacSha256("notification-secret", body, "hex")
  assert(/^[0-9a-f]{64}$/.test(sig))
  const req = new Request("https://x/wearable-vendor-webhook/suunto", { method: "POST", headers: { "X-HMAC-SHA256-Signature": sig }, body })
  const events = await suunto.parseWebhook(req, body, new URL(req.url))
  assert(events !== "challenge")
  assertEquals(events.length, 1)
  const ev = events[0]
  assertEquals([ev.vendorUserId, ev.kind, ev.eventId, ev.windowStart, ev.windowEnd], ["suunto-user-1", "SUUNTO_247_SLEEP_CREATED", "SUUNTO_247_SLEEP_CREATED|suunto-user-1|1757738520", "2026-09-13", "2026-09-13"])
  const daily = ev.rows!.daily
  assertEquals(daily.map((r) => r.dataTypeId), [2300, 2303, 2305, 2302, 3002, 3020, 2400, 2401])   // no latency/WASO fields in this body → no rows for them
  for (const r of daily) { assertEquals(r.sourceRecordId, "1757738520"); assertEquals(r.details?.avg_hrv_unverified, 58) }
  assertEquals(ev.rows!.epoch, [])
})

Deno.test("parseWebhook: base64, wrong secret, uppercase hex and a missing header are all rejected before JSON parse", async () => {
  const body = await fixture("webhook_sleep_created.json")
  const mk = (sig: string | null) => new Request("https://x/wearable-vendor-webhook/suunto", { method: "POST", headers: sig == null ? {} : { "X-HMAC-SHA256-Signature": sig }, body })
  const url = new URL("https://x/wearable-vendor-webhook/suunto")
  const good = await hmacSha256("notification-secret", body, "hex")
  const b64 = await hmacSha256("notification-secret", body, "base64")
  const wrongSecret = await hmacSha256("wrong-secret", body, "hex")
  const parse = (sig: string | null, raw = body) => Promise.resolve(suunto.parseWebhook(mk(sig), raw, url))
  await assertRejects(() => parse(b64), Error, "not lowercase hex")
  await assertRejects(() => parse(wrongSecret), Error, "mismatch")
  await assertRejects(() => parse(good.toUpperCase()), Error, "not lowercase hex")
  await assertRejects(() => parse(null), Error, "missing")
  // a valid signature over a different body (tampered) is a mismatch too — and invalid JSON is never parsed
  await assertRejects(() => parse(good, body.replace("suunto-user-1", "someone-else")), Error, "mismatch")
  await assertRejects(() => parse("00", "{not json"), Error, "not lowercase hex")
})

Deno.test("parseWebhook: WORKOUT_CREATED is a pointer (no rows, workout key in the eventId); recovery payloads map inline", async () => {
  const url = new URL("https://x/wearable-vendor-webhook/suunto")
  const signed = async (body: string) => new Request(url, { method: "POST", headers: { "X-HMAC-SHA256-Signature": await hmacSha256("notification-secret", body, "hex") }, body })
  const wk = JSON.stringify({ username: "suunto-user-1", type: "WORKOUT_CREATED", workoutKey: "wk-abc123" })
  const [w] = (await suunto.parseWebhook(await signed(wk), wk, url)) as Exclude<Awaited<ReturnType<typeof suunto.parseWebhook>>, "challenge">
  assertEquals([w.kind, w.eventId, w.rows, w.windowStart], ["WORKOUT_CREATED", "WORKOUT_CREATED|suunto-user-1|wk-abc123", undefined, undefined])
  const rec = JSON.stringify({ username: "suunto-user-1", type: "SUUNTO_247_RECOVERY_CREATED", samples: [{ timestamp: "2026-09-13T08:00:00+02:00", entryData: { Balance: 72, StressState: 2 } }] })
  const [r] = (await suunto.parseWebhook(await signed(rec), rec, url)) as Exclude<Awaited<ReturnType<typeof suunto.parseWebhook>>, "challenge">
  assertEquals(r.eventId, "SUUNTO_247_RECOVERY_CREATED|suunto-user-1|2026-09-13T08:00:00+02:00..2026-09-13T08:00:00+02:00")
  assertEquals(r.rows!.daily.map((d) => [d.dataTypeId, d.valueType, d.value, d.valueText]), [[1000134, "STRING", null, "72"], [1000135, "STRING", null, "2"]])
  assertEquals(r.rows!.epoch.map((e) => [e.dataTypeId, e.startTs, e.valueText]), [[1000134, "2026-09-13T06:00:00.000Z", "72"], [1000135, "2026-09-13T06:00:00.000Z", "2"]])
  // no username → a valid ping carrying nothing
  const ping = JSON.stringify({ type: "PING" })
  assertEquals(await suunto.parseWebhook(await signed(ping), ping, url), [])
})

Deno.test("adapter contract: pkce not_documented, no scopes requested, reconcile 3/14, state always sent", () => {
  assertEquals([suunto.key, suunto.pkce, suunto.scopes, suunto.reconcile], ["suunto", "not_documented", [], { nightlyDays: 3, weeklyDays: 14 }])
  const u = new URL(suunto.authorizeURL({ clientId: "client-id", redirectUri: "https://x/cb", state: "st-1", codeChallenge: "ignored" }))
  assertEquals(u.origin + u.pathname, "https://cloudapi-oauth.suunto.com/oauth/authorize")
  assertEquals(Object.fromEntries(u.searchParams), { response_type: "code", client_id: "client-id", redirect_uri: "https://x/cb", state: "st-1" })
})

Deno.test("oauth: exchangeCode reads the `user` claim + expires_in + scope; refresh (VERIFY) keeps the old refresh token unless rotated", async () => {
  const jwt = "h." + btoa(JSON.stringify({ user: "suunto-user-1", sub: "abc" })).replace(/=+$/, "") + ".s"
  const tokenResp = (extra: Record<string, unknown>) => new Response(JSON.stringify({ access_token: jwt, token_type: "bearer", expires_in: 86400, scope: "workout", ...extra }), { status: 200 })
  const t0 = Math.floor(Date.now() / 1000)
  const ex = await withFetch(() => suunto.exchangeCode({ code: "c1", redirectUri: "https://x/cb" }), () => tokenResp({ refresh_token: "r1" }))
  assertEquals([ex.result.accessToken, ex.result.refreshToken, ex.result.vendorUserId, ex.result.scopes], [jwt, "r1", "suunto-user-1", ["workout"]])
  assert(ex.result.expiresAt! >= t0 + 86400 && ex.result.expiresAt! <= t0 + 86401)
  assertEquals(ex.calls[0].headers.get("Authorization"), "Basic " + btoa("client-id:client-secret"))
  assertEquals(new URLSearchParams(ex.calls[0].body).get("grant_type"), "authorization_code")
  const rf = await withFetch(() => suunto.refresh("r1"), () => tokenResp({}))
  assertEquals([rf.result.accessToken, rf.result.refreshToken], [jwt, "r1"])
  assertEquals(new URLSearchParams(rf.calls[0].body).get("grant_type"), "refresh_token")
  const rot = await withFetch(() => suunto.refresh("r1"), () => tokenResp({ refresh_token: "r2" }))
  assertEquals(rot.result.refreshToken, "r2")
})

Deno.test("revoke (VERIFY endpoint) is best effort: a vendor failure never throws", async () => {
  const { calls } = await withFetch(() => suunto.revoke!(tokens, ctx), () => new Response("nope", { status: 404 }))
  assertStringIncludes(calls[0].url, "https://cloudapi-oauth.suunto.com/oauth/deauthorize?client_id=client-id")
  await withFetch(() => suunto.revoke!(tokens, ctx), () => { throw new TypeError("fetch failed") })
})

Deno.test("mapSleep: absent fields are skipped (no zeros), the nap is excluded, the record id is SleepId", () => {
  const rows = _suuntoTest.mapSleep([
    { timestamp: "2026-09-13T06:42:00+02:00", entryData: { SleepId: 7, IsNap: false, BedtimeEnd: "2026-09-13T06:42:00+02:00", Duration: 25000 } },
    { timestamp: "2026-09-13T14:35:00+02:00", entryData: { SleepId: 8, IsNap: true, BedtimeEnd: "2026-09-13T14:35:00+02:00", Duration: 2100 } },
    { entryData: { SleepId: 9 } },   // no instant at all → nothing
  ])
  assertEquals(rows.map((r) => [r.dataTypeId, r.value, r.valueText ?? null, r.sourceRecordId]), [[2300, 25000, null, "7"], [2401, 1789274520, "2026-09-13T04:42:00.000Z", "7"]])
  assertEquals(rows[0].details, { sleep_id: "7", avg_hrv_unverified: null, avg_hrv_sample_count: null, sleep_quality_score_unverified: null, unit_unverified: true })
})
