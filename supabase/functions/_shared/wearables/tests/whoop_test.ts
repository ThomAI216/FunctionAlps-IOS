// WHOOP adapter golden trace (strategy Phase 2): the fixture pages under fixtures/whoop/ → the EXACT
// catalogue rows, plus the webhook contract (signature verified, old timestamps accepted, trace_id → eventId).
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1"
import { type EpochRow, type DailyRow, T, hmacSha256, unixOf } from "../core.ts"
import { whoop } from "../whoop.ts"

Deno.env.set("WHOOP_CLIENT_ID", "test-client-id")
Deno.env.set("WHOOP_CLIENT_SECRET", "test-client-secret")

const fixture = async (name: string) => JSON.parse(await Deno.readTextFile(new URL(`./fixtures/whoop/${name}`, import.meta.url)))

const ROUTES: Record<string, string> = {
  "/developer/v2/activity/sleep": "sleep.json",
  "/developer/v2/recovery": "recovery.json",
  "/developer/v2/cycle": "cycle.json",
  "/developer/v2/activity/workout": "workout.json",
}

/** Serves the fixture pages for `fetchRange`; records every request so the query contract can be asserted. */
async function withFetchStub<R>(fn: (calls: URL[]) => Promise<R>): Promise<R> {
  const real = globalThis.fetch
  const calls: URL[] = []
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url)
    calls.push(url)
    assertEquals(url.host, "api.prod.whoop.com")
    assertEquals((init?.headers as Record<string, string>)?.Authorization, "Bearer at-1")
    const file = ROUTES[url.pathname]
    if (!file) return new Response("not found", { status: 404 })
    return new Response(JSON.stringify(await fixture(file)), { status: 200, headers: { "Content-Type": "application/json" } })
  }) as typeof fetch
  try { return await fn(calls) } finally { globalThis.fetch = real }
}

const ctx = { patientId: "patient-1", vendorUserId: "456", meta: {} }
const SLEEP_ID = "6b1b2a4e-3c5f-4d2a-9e1f-0a1b2c3d4e5f"
const WORKOUT_ID = "2d3e4f50-6172-4839-a0b1-c2d3e4f50617"

Deno.test("adapter contract: PKCE not documented, reconcile 7/30, offline scope", () => {
  assertEquals(whoop.pkce, "not_documented")
  assertEquals(whoop.reconcile, { nightlyDays: 7, weeklyDays: 30 })
  assert(whoop.scopes.includes("offline"))
  const u = new URL(whoop.authorizeURL({ clientId: "cid", redirectUri: "https://x/cb", state: "s".repeat(43) }))
  assertEquals(u.origin + u.pathname, "https://api.prod.whoop.com/oauth/oauth2/auth")
  assertEquals(u.searchParams.get("code_challenge"), null)
})

Deno.test("golden: sleep + recovery + cycle + workout pages → exact daily/epoch rows", async () => {
  const rows = await withFetchStub(async (calls) => {
    const out = await whoop.fetchRange({ accessToken: "at-1" }, "2026-09-13", "2026-09-13", ctx)
    // One page per collection, the ±1 day window, limit 25 (whoop.md §13).
    assertEquals(calls.map((u) => u.pathname).sort(), Object.keys(ROUTES).sort())
    for (const u of calls) {
      assertEquals(u.searchParams.get("limit"), "25")
      assertEquals(u.searchParams.get("start"), "2026-09-12T00:00:00Z")
      assertEquals(u.searchParams.get("end"), "2026-09-15T00:00:00Z")
    }
    return out
  })

  const d = (r: DailyRow) => [r.dataTypeId, r.dataTypeName, r.value, r.day, r.sourceRecordId]
  // `dailyMap` emits one record's rows in ascending catalogue-id order (Object.entries on integer keys).
  assertEquals(rows.daily.map(d), [
    // sleep (main sleep only — the nap and the PENDING_SCORE sleep are skipped); durations ms→s
    [T.SleepEfficiency, "SleepEfficiency", 93.75, "2026-09-13", SLEEP_ID],
    [T.MainSleepDuration, "ThryveMainSleepDuration", 27000, "2026-09-13", SLEEP_ID],
    [T.InBed, "ThryveMainSleepInBedDuration", 28800, "2026-09-13", SLEEP_ID],
    [T.REM, "ThryveMainSleepREMDuration", 6300, "2026-09-13", SLEEP_ID],
    [T.Deep, "ThryveMainSleepDeepDuration", 6300, "2026-09-13", SLEEP_ID],
    [T.Light, "ThryveMainSleepLightDuration", 14400, "2026-09-13", SLEEP_ID],
    [T.Awake, "ThryveMainSleepAwakeDuration", 1800, "2026-09-13", SLEEP_ID],
    [T.RespirationRateSleep, "RespirationRateSleep", 15.2, "2026-09-13", SLEEP_ID],
    [1000133, "WHOOPSleepPerformance", 88, "2026-09-13", SLEEP_ID],
    [T.SleepStart, "ThryveMainSleepStartTime", unixOf("2026-09-12T21:30:00Z"), "2026-09-13", SLEEP_ID],
    [T.SleepEnd, "ThryveMainSleepEndTime", unixOf("2026-09-13T05:30:00Z"), "2026-09-13", SLEEP_ID],
    // cycle — keyed to the wake day of its linked sleep, not to its evening start (2026-09-12 local)
    [T.BurnedCalories, "BurnedCalories", 2350, "2026-09-13", "93845"],
    [T.HeartRate, "HeartRate", 71, "2026-09-13", "93845"],
    [T.StrainScore, "StrainScore", 14.3, "2026-09-13", "93845"],
    // recovery — sourceRecordId = cycle id; RMSSD → 3106 only
    [T.HeartRateResting, "HeartRateResting", 52, "2026-09-13", "93845"],
    [T.SPO2, "SPO2", 96.4, "2026-09-13", "93845"],
    [T.RmssdSleep, "RmssdSleep", 61.5, "2026-09-13", "93845"],
    [T.SkinTemperature, "SkinTemperature", 33.4, "2026-09-13", "93845"],
    [T.RecoveryScore, "RecoveryScore", 67, "2026-09-13", "93845"],
  ])

  const e = (r: EpochRow) => [r.dataTypeId, r.dataTypeName, r.value, r.startTs, r.sourceRecordId]
  assertEquals(rows.epoch.map(e), [
    [T.ActivityType, "ActivityType", 0, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.StrainScore, "StrainScore", 8.7, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.ActiveBurnedCalories, "ActiveBurnedCalories", 500, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.HeartRate, "HeartRate", 152, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.CoveredDistance, "CoveredDistance", 8120.5, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.ElevationGain, "ElevationGain", 64, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.HRZoneLight, "HeartRateZoneLightDuration", 10, "2026-09-13T15:00:00.000Z", WORKOUT_ID],     // zones 1+2: 3 + 7 min
    [T.HRZoneModerate, "HeartRateZoneModerateDuration", 15, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.HRZoneIntense, "HeartRateZoneIntenseDuration", 16, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
    [T.HRZoneMaximal, "HeartRateZoneMaximalDuration", 3, "2026-09-13T15:00:00.000Z", WORKOUT_ID],
  ])

  // The ids that must NOT appear: SleepScore 1000105 / SleepQuality 2201 (performance is vendor-only),
  // Interruptions 2402 (disturbances are metadata), Rmssd 3100 (RMSSD is sleep-linked only), AwakeAfterWakeup 2308.
  const ids = new Set([...rows.daily, ...rows.epoch].map((r) => r.dataTypeId))
  for (const id of [1000105, T.SleepQuality, T.Interruptions, T.Rmssd, T.AwakeAfterWakeup]) assert(!ids.has(id), `id ${id} must not be written`)
  assert(ids.has(1000133))

  // Provenance + metadata on the sleep rows.
  const sleepRow = rows.daily.find((r) => r.dataTypeId === T.MainSleepDuration)!
  assertEquals(sleepRow.sourceResourceType, "sleep")
  assertEquals(sleepRow.sourceModifiedAt, "2026-09-13T06:40:00.000Z")
  assertEquals(sleepRow.timezoneOffset, 120)
  assertEquals(sleepRow.details?.disturbance_count, 7)
  assertEquals(sleepRow.details?.sleep_cycle_count, 5)
  assertEquals(sleepRow.details?.sleep_consistency_percentage, 74)
  assertEquals(sleepRow.details?.cycle_id, "93845")
  assertEquals(sleepRow.details?.day_basis, "sleep_end_local")
  assertEquals(rows.daily.find((r) => r.dataTypeId === T.SleepStart)!.valueType, "DATE")

  // Recovery: cycle id as record id, sleep id kept in details, RMSSD semantics flagged.
  const hrv = rows.daily.find((r) => r.dataTypeId === T.RmssdSleep)!
  assertEquals(hrv.sourceResourceType, "recovery")
  assertEquals(hrv.details?.sleep_id, SLEEP_ID)
  assertEquals(hrv.details?.statistic, "rmssd")
  assertEquals(hrv.details?.user_calibrating, false)
  assertEquals(hrv.valueType, "DOUBLE")

  // Cycle: day basis is the linked sleep.
  const strain = rows.daily.find((r) => r.dataTypeId === T.StrainScore)!
  assertEquals(strain.sourceResourceType, "cycle")
  assertEquals(strain.details?.day_basis, "linked_sleep_end_local")
  assertEquals(strain.details?.max_heart_rate, 168)

  // Workout: every epoch row carries the workout UUID + type + updated_at; zones carry the model + raw ms.
  for (const r of rows.epoch) {
    assertEquals(r.sourceResourceType, "workout")
    assertEquals(r.sourceRecordId, WORKOUT_ID)
    assertEquals(r.sourceModifiedAt, "2026-09-13T15:50:00.000Z")
    assertEquals(r.endTs, "2026-09-13T15:45:00.000Z")
    assertEquals(r.timezoneOffset, 120)
  }
  const wStrain = rows.epoch.find((r) => r.dataTypeId === T.StrainScore)!
  assertEquals(wStrain.details, { scope: "workout" })
  const act = rows.epoch.find((r) => r.dataTypeId === T.ActivityType)!
  assertEquals(act.valueText, "running")
  assertEquals(act.valueType, "STRING")
  const light = rows.epoch.find((r) => r.dataTypeId === T.HRZoneLight)!
  assertEquals(light.details?.zone_model, "whoop_percent_max_hr_6_buckets")
  assertEquals(light.details?.buckets, ["zone_one", "zone_two"])
  assertEquals((light.details?.zone_durations_milli as Record<string, number>).zone_zero_milli, 60000)
})

Deno.test("golden: a window that excludes the wake day yields nothing (day filter, not the API window)", async () => {
  const rows = await withFetchStub(() => whoop.fetchRange({ accessToken: "at-1" }, "2026-09-10", "2026-09-11", ctx))
  assertEquals(rows, { daily: [], epoch: [] })
})

// ── Webhook ────────────────────────────────────────────────────────────────────────────────────────────────

async function signedRequest(body: string, ts: string, secret = "test-client-secret", sigOverride?: string) {
  const sig = sigOverride ?? await hmacSha256(secret, ts + body, "base64")
  return new Request("https://fn.example/wearable-vendor-webhook/whoop", {
    method: "POST", body, headers: { "Content-Type": "application/json", "X-WHOOP-Signature": sig, "X-WHOOP-Signature-Timestamp": ts },
  })
}
const webhookBody = async () => { const { _note: _n, ...ev } = await fixture("webhook_sleep_updated.json"); return JSON.stringify(ev) }

Deno.test("webhook: a valid signature with an OLD timestamp is accepted and carries trace_id as eventId", async () => {
  const body = await webhookBody()
  const oldTs = String(Date.now() - 2 * 86_400_000)  // two days old — WHOOP retries for ~1 h and documents no replay window
  const req = await signedRequest(body, oldTs)
  const events = await whoop.parseWebhook(req, body, new URL(req.url))
  assertEquals(events, [{ vendorUserId: "456", kind: "sleep.updated", eventId: "7d8e9fa0-b1c2-4d3e-8f4a-5b6c7d8e9fa0" }])
})

Deno.test("webhook: a fresh timestamp is accepted too, and a body without user_id is an empty ping", async () => {
  const body = await webhookBody()
  const req = await signedRequest(body, String(Date.now()))
  assertEquals((await whoop.parseWebhook(req, body, new URL(req.url))).length, 1)
  const ping = JSON.stringify({ type: "ping" })
  const pingReq = await signedRequest(ping, String(Date.now()))
  assertEquals(await whoop.parseWebhook(pingReq, ping, new URL(pingReq.url)), [])
})

Deno.test("webhook: a bad signature throws (wrong secret, tampered body, missing headers)", async () => {
  const body = await webhookBody()
  const ts = String(Date.now())
  const wrongSecret = await signedRequest(body, ts, "another-secret")
  await assertRejects(() => Promise.resolve(whoop.parseWebhook(wrongSecret, body, new URL(wrongSecret.url))), Error, "signature mismatch")
  const tampered = await signedRequest(body, ts)
  const other = body.replace("456", "457")
  await assertRejects(() => Promise.resolve(whoop.parseWebhook(tampered, other, new URL(tampered.url))), Error, "signature mismatch")
  const noHeaders = new Request("https://fn.example/wearable-vendor-webhook/whoop", { method: "POST", body })
  await assertRejects(() => Promise.resolve(whoop.parseWebhook(noHeaders, body, new URL(noHeaders.url))), Error, "headers missing")
})
