// Suunto adapter golden trace: fixtures/suunto/* (shapes per Suunto's APIZone reference, 2026-11-06) → the EXACT
// catalogue rows; the webhook signature matrix (lowercase hex only); HRV raw-only (no 3100/3106/3112/3113); sleep durations
// in seconds with asleep = Deep + Light + REM and in bed = Duration; recovery Balance numeric 0–1 (1000134) and StressState
// text (1000135, never 1000109); provenance on every row; 28-day chunks; workout paging; 4xx skipped, 401/429/5xx propagate.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1"
import { type DailyRow, type EpochRow, RateLimitedError, UnauthorizedError, VendorHttpError, hmacSha256 } from "../core.ts"
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
  "/247samples/daily-activity-statistics": "daily_activity_statistics.json", "/v3/workouts": "workouts.json",
}

type Call = { url: string; headers: Headers; body?: string }
/** Stubs fetch for one test: fixture per path, or an override `(path) => Response`. Records every request. */
async function withFetch<R>(fn: () => Promise<R>, override?: (path: string, req: Call) => Response | null): Promise<{ result: R; calls: Call[] }> {
  const real = globalThis.fetch, calls: Call[] = []
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
const sleepBase = { sleep_id: "1757738520", unit: "seconds", avg_hrv_unverified: 58, avg_hrv_sample_count: 121, sleep_quality_score_unverified: 78, wake_before_off_bed_s: 300, max_spo2_fraction: 0.98, feeling: null }
const sleepRow = (id: number, name: string, value: number): DailyRow => ({ day: "2026-09-13", dataTypeId: id, dataTypeName: name, value, valueType: "LONG", details: sleepBase, ...sleepProv })
const recDetails = (raw: number) => ({ balance_scale: "0-1", stress_state_scale_unverified: true, stress_state_raw: raw })
const recProv = (ts: string, raw: number) => ({ timezoneOffset: 120, sourceRecordId: ts, sourceResourceType: "247_recovery", details: recDetails(raw) })
const recDaily = { timezoneOffset: 120, sourceRecordId: "2026-09-13T20:00:00+02:00", sourceResourceType: "247_recovery", details: { balance_scale: "0-1", stress_state_scale_unverified: true, sample_ts: "2026-09-13T20:00:00+02:00", statistic: "latest_of_day" } }
const actRaw = (hrv: number | null, spo2: number | null, energy: number | null, min: number | null, max: number | null) => ({ hrv_unverified: hrv, spo2_fraction: spo2, energy_consumption_j: energy, hr_min: min, hr_max: max })
const wkRaw = { workout_key: "wk-abc123", activity_id: "3", total_time_s: 3600, energy_consumption_unverified: 612, step_count: 9800, total_ascent_m: 85 }
const wkProv = { sourceRecordId: "wk-abc123", sourceResourceType: "workout", timezoneOffset: 120, endTs: "2026-09-13T10:40:00.000Z" }
const midRaw = { workout_key: "wk-midnight", activity_id: "1", total_time_s: 1200, energy_consumption_unverified: null, step_count: null, total_ascent_m: null }

Deno.test("golden: fetchRange over the Suunto fixtures → the exact daily and epoch rows", async () => {
  const { result, calls } = await withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx))
  // Both secrets on every data call; every documented path is called once (one 28-day chunk, one workout page).
  assertEquals(calls.map((c) => new URL(c.url).pathname), Object.keys(FILES))
  for (const c of calls) { assertEquals(c.headers.get("Authorization"), "Bearer jwt-access"); assertEquals(c.headers.get("Ocp-Apim-Subscription-Key"), "sub-key") }
  // 24/7 samples: from/to in epoch ms over UTC days; daily statistics: startdate/enddate in ISO-8601 (APIZone)
  for (const i of [0, 1, 2]) assertEquals(new URL(calls[i].url).search, "?from=1789171200000&to=1789343999999")
  assertEquals(Object.fromEntries(new URL(calls[3].url).searchParams), { startdate: "2026-09-12T00:00:00", enddate: "2026-09-13T23:59:59" })
  // workouts by START time with a day of margin either side, paged
  assertEquals(Object.fromEntries(new URL(calls[4].url).searchParams), { since: "1789084800000", until: "1789430400000", limit: "50", offset: "0", "filter-by-modification-time": "false" })

  assertEquals(result.daily, [
    sleepRow(2300, "ThryveMainSleepDuration", 24600),          // asleep = Deep 5400 + Light 14400 + REM 4800
    sleepRow(2301, "ThryveMainSleepInBedDuration", 27840),     // Duration = time in bed (22:58 → 06:42)
    sleepRow(2303, "ThryveMainSleepDeepDuration", 5400), sleepRow(2305, "ThryveMainSleepLightDuration", 14400), sleepRow(2302, "ThryveMainSleepREMDuration", 4800),
    sleepRow(2307, "ThryveMainSleepLatency", 600),
    sleepRow(2308, "ThryveMainSleepAwakeAfterWakeup", 720),    // 2308 is "wake-after-sleep-onset" in the catalogue ← WakeAfterSleepOnsetDuration
    sleepRow(3002, "HeartRateSleep", 52), sleepRow(3020, "HeartRateSleepLowest", 45),
    { day: "2026-09-13", dataTypeId: 2400, dataTypeName: "ThryveMainSleepStartTime", value: 1789246680, valueText: "2026-09-12T20:58:00.000Z", valueType: "DATE", details: sleepBase, ...sleepProv },
    { day: "2026-09-13", dataTypeId: 2401, dataTypeName: "ThryveMainSleepEndTime", value: 1789274520, valueText: "2026-09-13T04:42:00.000Z", valueType: "DATE", details: sleepBase, ...sleepProv },
    // recovery: the latest sample of the day; Balance numeric (0–1), StressState as text
    { day: "2026-09-13", dataTypeId: 1000134, dataTypeName: "SuuntoRecoveryBalance", value: 0.65, valueType: "DOUBLE", ...recDaily },
    { day: "2026-09-13", dataTypeId: 1000135, dataTypeName: "SuuntoStressState", value: null, valueText: "3", valueType: "STRING", ...recDaily },
    // daily statistics: per day, the largest source (never a sum of overlapping watches); energy J → kcal in details
    { day: "2026-09-12", dataTypeId: 1000, dataTypeName: "Steps", value: 6100, valueType: "LONG", sourceRecordId: "daily_stats:2026-09-12", sourceResourceType: "247_daily_activity_statistics", details: { day_basis: "utc", energy_consumption_kcal: null } },
    { day: "2026-09-13", dataTypeId: 1000, dataTypeName: "Steps", value: 8421, valueType: "LONG", sourceRecordId: "daily_stats:2026-09-13", sourceResourceType: "247_daily_activity_statistics", details: { day_basis: "utc", energy_consumption_kcal: 2342 } },
  ])
  assertEquals(result.epoch, [
    { startTs: "2026-09-13T06:00:00.000Z", dataTypeId: 1000134, dataTypeName: "SuuntoRecoveryBalance", value: 0.82, valueType: "DOUBLE", ...recProv("2026-09-13T08:00:00+02:00", 2) },
    { startTs: "2026-09-13T06:00:00.000Z", dataTypeId: 1000135, dataTypeName: "SuuntoStressState", value: null, valueText: "2", valueType: "STRING", ...recProv("2026-09-13T08:00:00+02:00", 2) },
    { startTs: "2026-09-13T18:00:00.000Z", dataTypeId: 1000134, dataTypeName: "SuuntoRecoveryBalance", value: 0.65, valueType: "DOUBLE", ...recProv("2026-09-13T20:00:00+02:00", 3) },
    { startTs: "2026-09-13T18:00:00.000Z", dataTypeId: 1000135, dataTypeName: "SuuntoStressState", value: null, valueText: "3", valueType: "STRING", ...recProv("2026-09-13T20:00:00+02:00", 3) },
    { startTs: "2026-09-13T08:00:00.000Z", dataTypeId: 3000, dataTypeName: "HeartRate", value: 71, valueType: "LONG", timezoneOffset: 120, sourceRecordId: "2026-09-13T10:00:00+02:00", sourceResourceType: "247_activity", details: actRaw(44, 0.97, 125600, 60, 88) },
    { startTs: "2026-09-13T08:00:00.000Z", dataTypeId: 1000, dataTypeName: "Steps", value: 340, valueType: "LONG", timezoneOffset: 120, sourceRecordId: "2026-09-13T10:00:00+02:00", sourceResourceType: "247_activity", details: actRaw(44, 0.97, 125600, 60, 88) },
    { startTs: "2026-09-13T08:10:00.000Z", dataTypeId: 1000, dataTypeName: "Steps", value: 120, valueType: "LONG", timezoneOffset: 120, sourceRecordId: "2026-09-13T10:10:00+02:00", sourceResourceType: "247_activity", details: actRaw(null, null, null, null, null) },
    { startTs: "2026-09-13T09:40:00.000Z", dataTypeId: 1200, dataTypeName: "ActivityType", value: null, valueText: "suunto_activity_3", valueType: "STRING", ...wkProv, details: wkRaw },
    { startTs: "2026-09-13T09:40:00.000Z", dataTypeId: 1001, dataTypeName: "CoveredDistance", value: 10250, valueType: "LONG", ...wkProv, details: { ...wkRaw, unit: "m" } },
    { startTs: "2026-09-13T09:40:00.000Z", dataTypeId: 1003, dataTypeName: "ElevationGain", value: 85, valueType: "LONG", ...wkProv, details: { ...wkRaw, unit: "m" } },
    { startTs: "2026-09-13T09:40:00.000Z", dataTypeId: 3000, dataTypeName: "HeartRate", value: 148, valueType: "LONG", ...wkProv, details: { ...wkRaw, statistic: "workout_average", max_heart_rate: 176 } },
    // 22:30 UTC on the 11th is 00:30 local on the 12th → inside the window; its zero distance writes nothing
    { startTs: "2026-09-11T22:30:00.000Z", dataTypeId: 1200, dataTypeName: "ActivityType", value: null, valueText: "suunto_activity_1", valueType: "STRING", sourceRecordId: "wk-midnight", sourceResourceType: "workout", timezoneOffset: 120, endTs: "2026-09-11T22:50:00.000Z", details: midRaw },
  ])
})

Deno.test("invariants: HRV raw-only, recovery types, provenance everywhere, seconds on sleep rows, no zeros for absent fields", async () => {
  const { result } = await withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx))
  const all = [...result.daily, ...result.epoch]
  const ids = new Set(all.map((r) => r.dataTypeId))
  for (const forbidden of [3100, 3106, 3112, 3113, 1000109, 2201, 1000105, 3001, 1000110, 2306]) assert(!ids.has(forbidden), `${forbidden} must not be written`)
  // AvgHRV / HRV survive only inside details
  for (const r of result.daily.filter((r) => r.sourceResourceType === "247_sleep")) assertEquals(r.details?.avg_hrv_unverified, 58)
  assertEquals(result.epoch.find((r) => r.sourceResourceType === "247_activity")?.details?.hrv_unverified, 44)
  // 1000134 numeric in [0, 1]; 1000135 STRING, never a number
  for (const r of all.filter((r) => r.dataTypeId === 1000134)) { assertEquals(r.valueType, "DOUBLE"); assert(r.value != null && r.value >= 0 && r.value <= 1) }
  for (const r of all.filter((r) => r.dataTypeId === 1000135)) { assertEquals(r.valueType, "STRING"); assertEquals(r.value, null); assertEquals(typeof r.valueText, "string") }
  // provenance + the unit on every sleep duration
  for (const r of all) { assert(r.sourceRecordId, `sourceRecordId missing on ${r.dataTypeId}`); assert(r.sourceResourceType, `sourceResourceType missing on ${r.dataTypeId}`) }
  for (const r of result.daily.filter((r) => [2300, 2301, 2302, 2303, 2305, 2307, 2308].includes(r.dataTypeId))) assertEquals(r.details?.unit, "seconds")
  // asleep never exceeds time in bed
  const v = (id: number) => result.daily.find((r) => r.dataTypeId === id)?.value as number
  assert(v(2300) <= v(2301))
  // the nap is excluded; the sparse activity sample yields no HR row; the out-of-window workout is skipped; nothing is 0
  assertEquals(result.daily.filter((r) => r.sourceRecordId === "1757766900").length, 0)
  assertEquals(result.epoch.filter((r) => r.sourceRecordId === "2026-09-13T10:10:00+02:00").map((r) => r.dataTypeId), [1000])
  assertEquals(result.epoch.filter((r) => r.sourceRecordId === "wk-old"), [])
  assert(all.every((r) => r.value !== 0))
})

Deno.test("fetchRange: a 4xx on one path is skipped; 401, 429 and 5xx propagate for the core refresh / backoff / retry paths", async () => {
  const { result } = await withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx), (path) => path === "/v3/workouts" ? new Response("nope", { status: 404 }) : null)
  assertEquals(result.epoch.filter((r) => r.sourceResourceType === "workout"), [])
  assertEquals(result.daily.length, 15)
  await assertRejects(() => withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx), (path) => path === "/v3/workouts" ? new Response("Service capacity exceeded", { status: 503 }) : null), VendorHttpError)
  await assertRejects(() => withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx), () => new Response("expired", { status: 401 })), UnauthorizedError)
  await assertRejects(() => withFetch(() => suunto.fetchRange(tokens, "2026-09-12", "2026-09-13", ctx), () => new Response("slow down", { status: 429, headers: { "Retry-After": "30" } })), RateLimitedError)
})

Deno.test("fetchRange: windows longer than 28 days are chunked; workouts follow every page until a short one", async () => {
  const page = (n: number, from: number) => ({ payload: Array.from({ length: n }, (_, i) => ({ workoutKey: `wk-${from + i}`, activityId: 2, startTime: 1789292400000, timeOffsetInMinutes: 120, totalTime: 600, totalDistance: 1000 + from + i })) })
  const { result, calls } = await withFetch(() => suunto.fetchRange(tokens, "2026-08-01", "2026-09-13", ctx), (path, req) => {
    if (path !== "/v3/workouts") return path.startsWith("/247samples/") ? new Response("[]", { status: 200 }) : null
    const offset = Number(new URL(req.url).searchParams.get("offset"))
    return new Response(JSON.stringify(offset === 0 ? page(50, 0) : page(3, 50)), { status: 200 })
  })
  const sleepCalls = calls.filter((c) => new URL(c.url).pathname === "/247samples/sleep").map((c) => new URL(c.url).searchParams)
  assertEquals(sleepCalls.map((q) => [new Date(Number(q.get("from"))).toISOString().slice(0, 10), new Date(Number(q.get("to"))).toISOString().slice(0, 10)]), [["2026-08-01", "2026-08-28"], ["2026-08-29", "2026-09-13"]])
  assertEquals(calls.filter((c) => new URL(c.url).pathname === "/247samples/daily-activity-statistics").map((c) => new URL(c.url).searchParams.get("startdate")), ["2026-08-01T00:00:00", "2026-08-29T00:00:00"])
  assertEquals(calls.filter((c) => new URL(c.url).pathname === "/v3/workouts").map((c) => new URL(c.url).searchParams.get("offset")), ["0", "50"])
  assertEquals(new Set(result.epoch.filter((r) => r.dataTypeId === 1200).map((r) => r.sourceRecordId)).size, 53)
})

Deno.test("chunkDays: inclusive 28-day chunks, a single day, an empty window", () => {
  assertEquals(_suuntoTest.chunkDays("2026-01-01", "2026-03-01"), [{ start: "2026-01-01", end: "2026-01-28" }, { start: "2026-01-29", end: "2026-02-25" }, { start: "2026-02-26", end: "2026-03-01" }])
  assertEquals(_suuntoTest.chunkDays("2026-09-13", "2026-09-13"), [{ start: "2026-09-13", end: "2026-09-13" }])
  assertEquals(_suuntoTest.chunkDays("2026-09-14", "2026-09-13"), [])
})

Deno.test("mapDailyStats: unknown metric names and malformed samples are ignored; no steps → no row", () => {
  assertEquals(_suuntoTest.mapDailyStats({ not: "a list" }), [])
  assertEquals(_suuntoTest.mapDailyStats([{ Name: "energyconsumption", Sources: [{ Samples: [{ TimeISO8601: "2026-09-13T00:00:00Z", Value: 4184000 }] }] }]), [])
  const rows = _suuntoTest.mapDailyStats([{ Name: "StepCount", Sources: [{ Samples: [{ TimeISO8601: "2026-09-13T00:00:00Z", Value: "7000" }, { Value: 9 }, { TimeISO8601: "2026-09-14T00:00:00Z" }] }] }])
  assertEquals(rows.map((r) => [r.day, r.value]), [["2026-09-13", 7000]])
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
  assertEquals(daily.map((r) => r.dataTypeId), [2300, 2301, 2303, 2305, 2302, 3002, 3020, 2400, 2401])   // no latency/WASO fields in this body → no rows for them
  assertEquals(daily.slice(0, 2).map((r) => r.value), [24600, 27840])
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

Deno.test("parseWebhook: WORKOUT_CREATED maps the inline `workout` (local day window); a bare pointer has no rows; recovery maps inline", async () => {
  const url = new URL("https://x/wearable-vendor-webhook/suunto")
  type Events = Exclude<Awaited<ReturnType<typeof suunto.parseWebhook>>, "challenge">
  const signed = async (body: string) => new Request(url, { method: "POST", headers: { "X-HMAC-SHA256-Signature": await hmacSha256("notification-secret", body, "hex") }, body })
  const inline = JSON.stringify({ username: "suunto-user-1", type: "WORKOUT_CREATED", workout: { workoutKey: "wk-abc123", activityId: 3, startTime: 1789292400000, timeOffsetInMinutes: 120, totalTime: 3600, totalDistance: 10000, hrdata: { workoutAvgHR: 140, workoutMaxHR: 170 } } })
  const [wi] = (await suunto.parseWebhook(await signed(inline), inline, url)) as Events
  assertEquals([wi.kind, wi.eventId, wi.windowStart, wi.windowEnd], ["WORKOUT_CREATED", "WORKOUT_CREATED|suunto-user-1|wk-abc123", "2026-09-13", "2026-09-13"])
  assertEquals(wi.rows!.daily, [])
  assertEquals(wi.rows!.epoch.map((e) => [e.dataTypeId, e.value ?? e.valueText, e.sourceRecordId]), [[1200, "suunto_activity_3", "wk-abc123"], [1001, 10000, "wk-abc123"], [3000, 140, "wk-abc123"]])
  const wk = JSON.stringify({ username: "suunto-user-1", type: "WORKOUT_CREATED", workoutKey: "wk-abc123" })
  const [w] = (await suunto.parseWebhook(await signed(wk), wk, url)) as Events
  assertEquals([w.kind, w.eventId, w.rows, w.windowStart], ["WORKOUT_CREATED", "WORKOUT_CREATED|suunto-user-1|wk-abc123", undefined, undefined])
  const rec = JSON.stringify({ username: "suunto-user-1", type: "SUUNTO_247_RECOVERY_CREATED", samples: [{ timestamp: "2026-09-13T08:00:00+02:00", entryData: { Balance: 0.82, StressState: 2 } }] })
  const [r] = (await suunto.parseWebhook(await signed(rec), rec, url)) as Events
  assertEquals(r.eventId, "SUUNTO_247_RECOVERY_CREATED|suunto-user-1|2026-09-13T08:00:00+02:00..2026-09-13T08:00:00+02:00")
  assertEquals(r.rows!.daily.map((d) => [d.dataTypeId, d.valueType, d.value, d.valueText ?? null]), [[1000134, "DOUBLE", 0.82, null], [1000135, "STRING", null, "2"]])
  assertEquals(r.rows!.epoch.map((e) => [e.dataTypeId, e.startTs, e.value ?? e.valueText]), [[1000134, "2026-09-13T06:00:00.000Z", 0.82], [1000135, "2026-09-13T06:00:00.000Z", "2"]])
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

Deno.test("mapSleep: absent fields are skipped (no zeros), the nap is excluded, Duration alone is time in bed", () => {
  const rows = _suuntoTest.mapSleep([
    { timestamp: "2026-09-13T06:42:00+02:00", entryData: { SleepId: 7, IsNap: false, BedtimeEnd: "2026-09-13T06:42:00+02:00", Duration: 25000 } },
    { timestamp: "2026-09-13T14:35:00+02:00", entryData: { SleepId: 8, IsNap: true, BedtimeEnd: "2026-09-13T14:35:00+02:00", Duration: 2100 } },
    { entryData: { SleepId: 9 } },   // no instant at all → nothing
  ])
  // no stage durations → no asleep row (never Duration passed off as sleep)
  assertEquals(rows.map((r) => [r.dataTypeId, r.value, r.valueText ?? null, r.sourceRecordId]), [[2301, 25000, null, "7"], [2401, 1789274520, "2026-09-13T04:42:00.000Z", "7"]])
  assertEquals(rows[0].details, { sleep_id: "7", unit: "seconds", avg_hrv_unverified: null, avg_hrv_sample_count: null, sleep_quality_score_unverified: null, wake_before_off_bed_s: null, max_spo2_fraction: null, feeling: null })
})

Deno.test("mapWorkout: no start or no key → nothing; no offset → UTC day; nested `key` accepted", () => {
  assertEquals(_suuntoTest.mapWorkout({ workoutKey: "x" }), null)
  assertEquals(_suuntoTest.mapWorkout({ startTime: 1789292400000 }), null)
  const m = _suuntoTest.mapWorkout({ key: "k-1", startTime: 1789165800000, activityId: 5 })!
  assertEquals([m.day, m.rows.map((r) => [r.dataTypeId, r.sourceRecordId, r.endTs ?? null, r.timezoneOffset ?? null])], ["2026-09-11", [[1200, "k-1", null, null]]])
})
