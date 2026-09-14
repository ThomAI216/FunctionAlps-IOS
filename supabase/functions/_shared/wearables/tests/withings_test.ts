// Withings adapter — Phase 2 golden trace (strategy 2026-09-14): signed `requesttoken` (corpus vendors/withings.md §7), the D4 HRV
// gate (sdnn_1/rmssd raw-only), PWV type 91 → 3008 with the unit exponent, provenance on every row, the unsigned notification
// parser, notify subscribe/revoke, the signed revoke and the WITHINGS_REGION guard. `globalThis.fetch` is stubbed; nothing leaves the box.
import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1"
import { T, hmacSha256 } from "../core.ts"
import { _withingsTest, apiBase, localDayIn, scaleMeasure, sign, signingString, withings } from "../withings.ts"

const EU = "https://wbsapi.withings.net"
const fixture = async (name: string) => JSON.parse(await Deno.readTextFile(new URL(`./fixtures/withings/${name}`, import.meta.url)))
type Call = { url: string; params: Record<string, string>; headers: Record<string, string> }

/** Routes every POST by (pathname, action) to a `{status, body}` envelope and records what was sent. */
function stubFetch(route: (path: string, action: string, params: URLSearchParams) => unknown) {
  const calls: Call[] = []
  const orig = globalThis.fetch
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input), params = new URLSearchParams(String(init?.body ?? ""))
    calls.push({ url, params: Object.fromEntries(params), headers: (init?.headers as Record<string, string>) ?? {} })
    const body = route(new URL(url).pathname, params.get("action") ?? "", params) ?? { status: 0, body: {} }
    return new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } })
  }) as typeof fetch
  return { calls, restore: () => { globalThis.fetch = orig } }
}

const withEnv = async (vars: Record<string, string | null>, fn: () => Promise<void>) => {
  const prev = Object.fromEntries(Object.keys(vars).map((k) => [k, Deno.env.get(k)]))
  for (const [k, v] of Object.entries(vars)) v == null ? Deno.env.delete(k) : Deno.env.set(k, v)
  try { await fn() } finally { for (const [k, v] of Object.entries(prev)) v == null ? Deno.env.delete(k) : Deno.env.set(k, v) }
}
const CREDS = { WITHINGS_CLIENT_ID: "cid-test", WITHINGS_CLIENT_SECRET: "sec-test", WITHINGS_REGION: null }
const nonceRoute = (path: string, action: string) => path === "/v2/signature" && action === "getnonce" ? { status: 0, body: { nonce: "nonce-1" } } : null

Deno.test("adapter shape: pkce not_documented (W §28), comma scopes (W §6), reconcile 3/14", () => {
  assertEquals(withings.pkce, "not_documented")
  assertEquals(withings.reconcile, { nightlyDays: 3, weeklyDays: 14 })
  assertEquals(withings.scopes, ["user.info", "user.metrics", "user.activity", "user.sleepevents"])
  assertEquals(_withingsTest.APPLIS, [1, 2, 4, 16, 44, 46])
  const u = new URL(withings.authorizeURL({ clientId: "cid", redirectUri: "https://f/cb", state: "st" }))
  assertEquals(u.origin + u.pathname, "https://account.withings.com/oauth2_user/authorize2")
  assertEquals(Object.fromEntries(u.searchParams), { response_type: "code", client_id: "cid", state: "st", scope: _withingsTest.SCOPES, redirect_uri: "https://f/cb" })
})

Deno.test("signing helper: `action,client_id,<nonce|timestamp>` comma-joined, HMAC-SHA256 hex with the client secret (W §7/§26)", async () => {
  assertEquals(signingString("getnonce", "cid-test", 1789279200), "getnonce,cid-test,1789279200")
  assertEquals(signingString("revoke", "cid-test", "nonce-1"), "revoke,cid-test,nonce-1")
  assertEquals(signingString("requesttoken", "cid-test", "nonce-1"), "requesttoken,cid-test,nonce-1")
  assertEquals(await sign("sec-test", "getnonce", "cid-test", 1789279200), await hmacSha256("sec-test", "getnonce,cid-test,1789279200"))
  assertEquals(await sign("sec-test", "revoke", "cid-test", "nonce-1"), await hmacSha256("sec-test", "revoke,cid-test,nonce-1"))
  assertMatch(await sign("sec-test", "revoke", "cid-test", "nonce-1"), /^[0-9a-f]{64}$/)
})

Deno.test("exchangeCode: getnonce then a SIGNED requesttoken carrying client_id, code, grant_type, redirect_uri, nonce, signature — no client_secret (W §7)", async () => {
  await withEnv(CREDS, async () => {
    const f = stubFetch((path, action) => nonceRoute(path, action) ?? (path === "/v2/oauth2" && action === "requesttoken"
      ? { status: 0, body: { userid: 12345, access_token: "at-1", refresh_token: "rt-1", scope: "user.info,user.metrics", expires_in: 10800, token_type: "Bearer", csrf_token: "x" } } : null))
    try {
      const r = await withings.exchangeCode({ code: "code-1", redirectUri: "https://f/cb" })
      assertEquals(f.calls.length, 2)
      assertEquals(f.calls[0].url, `${EU}/v2/signature`)
      const ts = f.calls[0].params.timestamp
      assertMatch(ts, /^\d{10}$/)
      assertEquals(f.calls[0].params, { action: "getnonce", client_id: "cid-test", timestamp: ts, signature: await hmacSha256("sec-test", `getnonce,cid-test,${ts}`) })
      assertEquals(f.calls[1].url, `${EU}/v2/oauth2`)
      assertEquals(f.calls[1].params, {
        action: "requesttoken", grant_type: "authorization_code", client_id: "cid-test", nonce: "nonce-1",
        signature: await hmacSha256("sec-test", "requesttoken,cid-test,nonce-1"), code: "code-1", redirect_uri: "https://f/cb",
      })
      assert(!("client_secret" in f.calls[1].params))
      assert(!f.calls[1].headers.Authorization)
      assertEquals([r.accessToken, r.refreshToken, r.vendorUserId, r.scopes], ["at-1", "rt-1", "12345", ["user.info", "user.metrics"]])
      assert(r.expiresAt! > Date.now() / 1000 + 10_000)
    } finally { f.restore() }
  })
})

Deno.test("refresh: the same signed requesttoken with grant_type=refresh_token; rotated refresh token adopted, old one kept when absent (W §8)", async () => {
  await withEnv(CREDS, async () => {
    let withNew = true
    const f = stubFetch((path, action) => nonceRoute(path, action) ?? (path === "/v2/oauth2" && action === "requesttoken"
      ? { status: 0, body: { userid: 12345, access_token: "at-2", ...(withNew ? { refresh_token: "rt-2" } : {}), expires_in: 10800 } } : null))
    try {
      const a = await withings.refresh("rt-1")
      assertEquals(f.calls[1].params, { action: "requesttoken", grant_type: "refresh_token", client_id: "cid-test", nonce: "nonce-1", signature: await hmacSha256("sec-test", "requesttoken,cid-test,nonce-1"), refresh_token: "rt-1" })
      assertEquals([a.accessToken, a.refreshToken], ["at-2", "rt-2"])
      withNew = false
      const b = await withings.refresh("rt-1")
      assertEquals(b.refreshToken, "rt-1")
    } finally { f.restore() }
  })
})

Deno.test("revoke: signed `/v2/oauth2 action=revoke` with the stored userid (W §25 — VERIFY exact call); nothing without a userid", async () => {
  await withEnv(CREDS, async () => {
    const f = stubFetch((path, action) => nonceRoute(path, action))
    try {
      await withings.revoke!({ accessToken: "at" }, { patientId: "p", vendorUserId: null, meta: {} })
      assertEquals(f.calls.length, 0)
      await withings.revoke!({ accessToken: "at" }, { patientId: "p", vendorUserId: "12345", meta: {} })
      assertEquals(f.calls.length, 2)
      assertEquals(f.calls[1].url, `${EU}/v2/oauth2`)
      assertEquals(f.calls[1].params, { action: "revoke", client_id: "cid-test", nonce: "nonce-1", signature: await hmacSha256("sec-test", "revoke,cid-test,nonce-1"), userid: "12345" })
    } finally { f.restore() }
  })
})

Deno.test("afterConnect subscribes every appli (W §10); unsubscribe revokes exactly the applis recorded in meta with the same callback", async () => {
  await withEnv(CREDS, async () => {
    const f = stubFetch(() => ({ status: 0, body: {} }))
    try {
      const r = await withings.afterConnect!({ accessToken: "at" }, { patientId: "p", webhookUrl: "https://f/wearable-vendor-webhook/withings", vendorUserId: "12345" })
      assertEquals(f.calls.length, 6)
      assertEquals(f.calls.map((c) => c.params), _withingsTest.APPLIS.map((a) => ({ action: "subscribe", callbackurl: "https://f/wearable-vendor-webhook/withings", appli: String(a), comment: "FunctionAlps" })))
      assert(f.calls.every((c) => c.url === `${EU}/notify` && c.headers.Authorization === "Bearer at"))
      assertEquals(r.meta, { notify_applis: [1, 2, 4, 16, 44, 46], notify_url: "https://f/wearable-vendor-webhook/withings" })

      f.calls.length = 0
      await withings.unsubscribe!({ accessToken: "at" }, { patientId: "p", vendorUserId: "12345", meta: { notify_applis: [1, 44], notify_url: "https://f/wearable-vendor-webhook/withings" } })
      assertEquals(f.calls.map((c) => [c.url, c.headers.Authorization, c.params]), [
        [`${EU}/notify`, "Bearer at", { action: "revoke", callbackurl: "https://f/wearable-vendor-webhook/withings", appli: "1" }],
        [`${EU}/notify`, "Bearer at", { action: "revoke", callbackurl: "https://f/wearable-vendor-webhook/withings", appli: "44" }],
      ])
    } finally { f.restore() }
  })
})

Deno.test("parseWebhook: unsigned form trigger → window + derived eventId; unlink → revoked; empty (HEAD probe) → []", async () => {
  const fx = await fixture("notification.form.json")
  const req = new Request("https://f/wearable-vendor-webhook/withings", { method: "POST" })
  const url = new URL(req.url)
  assertEquals(await withings.parseWebhook(req, fx.sleep_update, url), [{
    vendorUserId: "12345", kind: "appli.44.update", eventId: "44:12345:1789250400:1789277400", windowStart: "2026-09-12", windowEnd: "2026-09-13", revoked: false,
  }])
  const unlink = (await withings.parseWebhook(req, fx.unlink, url)) as { revoked?: boolean; eventId?: string | null }[]
  assertEquals([unlink[0].revoked, unlink[0].eventId], [true, "46:12345::"])
  assertEquals(await withings.parseWebhook(req, fx.head_probe, url), [])
})

Deno.test("measure scaling: value × 10^unit, exact for negative exponents; local day from the body timezone", () => {
  assertEquals([scaleMeasure(72450, -3), scaleMeasure(2180, -2), scaleMeasure(7850, -3), scaleMeasure(121, 0), scaleMeasure(5, 2)], [72.45, 21.8, 7.85, 121, 500])
  assertEquals(localDayIn(1789338600, "Europe/Zurich"), "2026-09-14")   // 22:30Z → 00:30 CEST
  assertEquals(localDayIn(1789338600, null), "2026-09-13")
  assertEquals(localDayIn(1789338600, "Not/AZone"), "2026-09-13")
})

Deno.test("golden trace: fetchRange → exact rows; HRV raw-only under details (D4); PWV 91 → 3008 scaled; provenance on every row", async () => {
  const getmeas = await fixture("getmeas.json"), summary = await fixture("sleep_getsummary.json"), series = await fixture("sleep_get_series.json")
  await withEnv(CREDS, async () => {
    const f = stubFetch((path, action) => {
      if (path === "/v2/sleep" && action === "getsummary") return summary
      if (path === "/v2/sleep" && action === "get") return series
      if (path === "/measure" && action === "getmeas") return getmeas
      if (path === "/v2/measure" && action === "getactivity") return { status: 0, body: { activities: [] } }
      if (path === "/v2/measure" && action === "getworkouts") return { status: 0, body: { series: [] } }
      throw new Error(`unexpected call ${path} ${action}`)
    })
    try {
      const rows = await withings.fetchRange({ accessToken: "at" }, "2026-09-12", "2026-09-14", { patientId: "p", vendorUserId: "12345", meta: {} })
      // The calls themselves: bearer on every data call, sdnn_1/rmssd requested but only ever kept raw.
      assert(f.calls.every((c) => c.headers.Authorization === "Bearer at"))
      assertEquals(f.calls.map((c) => [new URL(c.url).pathname, c.params.action]), [["/v2/sleep", "getsummary"], ["/v2/sleep", "get"], ["/v2/measure", "getactivity"], ["/measure", "getmeas"], ["/v2/measure", "getworkouts"]])
      assertEquals(f.calls[3].params, { action: "getmeas", meastypes: Object.keys(_withingsTest.MEAS).join(","), category: "1", startdate: "1789171200", enddate: "1789430399" })

      const sleep = { sourceRecordId: "9001", sourceResourceType: "sleep_summary", sourceDeviceId: "hd-sleep-1", sourceModifiedAt: "2026-09-13T05:35:00.000Z" }
      const base = { model: 32, sleep_id: 9001, timezone: "Europe/Zurich" }
      const sd = (id: number, name: string, value: number) => ({ day: "2026-09-13", dataTypeId: id, dataTypeName: name, value, valueType: "LONG" as const, ...sleep, details: base })
      const grp = (grpid: number, meastype: number, unit: number, model: number, deviceId: string, modified: string | null) => ({
        sourceRecordId: String(grpid), sourceResourceType: "measuregrp", sourceDeviceId: deviceId, sourceModifiedAt: modified,
        details: { grpid, attrib: 0, model, meastype, unit_exponent: unit, timezone: "Europe/Zurich" },
      })
      const weight = grp(5001, 1, -3, 6, "dev-scale-1", "2026-09-13T06:00:05.000Z"), fat = grp(5001, 6, -2, 6, "dev-scale-1", "2026-09-13T06:00:05.000Z")
      const sys = grp(5002, 10, 0, 45, "dev-bpm-1", null), dia = grp(5002, 9, 0, 45, "dev-bpm-1", null), hr = grp(5002, 11, 0, 45, "dev-bpm-1", null)
      const pwv = grp(5003, 91, -3, 6, "dev-scale-1", "2026-09-13T06:01:05.000Z")

      assertEquals(rows.daily, [
        { day: "2026-09-13", dataTypeId: 2300, dataTypeName: "ThryveMainSleepDuration", value: 25200, valueType: "LONG", ...sleep, details: {
          ...base, sdnn_1_unverified: 62, rmssd_unverified: 48, hrv_source: "sleep_summary",
          hrv_note: "UNVERIFIED: Withings HRV statistic/window not pinned (strategy D4; W §20) — raw only, no canonical HRV row",
        } },
        sd(2200, "SleepEfficiency", 93), sd(2201, "SleepQuality", 81), sd(2301, "ThryveMainSleepInBedDuration", 27000), sd(2302, "ThryveMainSleepREMDuration", 6600),
        sd(2303, "ThryveMainSleepDeepDuration", 6000), sd(2305, "ThryveMainSleepLightDuration", 12600), sd(2306, "ThryveMainSleepAwakeDuration", 1800),
        sd(2307, "ThryveMainSleepLatency", 600), sd(2308, "ThryveMainSleepAwakeAfterWakeup", 900), sd(2402, "ThryveMainSleepInterruptions", 2),
        sd(3002, "HeartRateSleep", 54), sd(3020, "HeartRateSleepLowest", 47), sd(4002, "RespirationRateSleep", 14), sd(4100, "Breathing", 5), sd(4101, "SnoringBinary", 300), sd(1000105, "SleepScore", 81),
        { day: "2026-09-13", dataTypeId: 2400, dataTypeName: "ThryveMainSleepStartTime", value: 1789250400, valueText: "2026-09-12T22:00:00.000Z", valueType: "DATE", ...sleep, details: base },
        { day: "2026-09-13", dataTypeId: 2401, dataTypeName: "ThryveMainSleepEndTime", value: 1789277400, valueText: "2026-09-13T05:30:00.000Z", valueType: "DATE", ...sleep, details: base },
        { day: "2026-09-13", dataTypeId: 5020, dataTypeName: "Weight", value: 72.45, valueType: "DOUBLE", ...weight },
        { day: "2026-09-13", dataTypeId: 5025, dataTypeName: "FatRatio", value: 21.8, valueType: "DOUBLE", ...fat },
        { day: "2026-09-14", dataTypeId: 3301, dataTypeName: "BloodPressureSystolic", value: 121, valueType: "LONG", ...sys },
        { day: "2026-09-14", dataTypeId: 3300, dataTypeName: "BloodPressureDiastolic", value: 79, valueType: "LONG", ...dia },
        { day: "2026-09-13", dataTypeId: 3008, dataTypeName: "PulseWaveVelocity", value: 7.85, valueType: "DOUBLE", ...pwv },
      ])
      const serRow = (id: number, name: string, value: number) => ({ startTs: "2026-09-13T01:00:00.000Z", dataTypeId: id, dataTypeName: name, value, valueType: "LONG" as const, details: { source: "sleep_series" }, sourceRecordId: "9001", sourceResourceType: "sleep_series", sourceDeviceId: "hd-sleep-1", sourceModifiedAt: "2026-09-13T05:35:00.000Z" })
      assertEquals(rows.epoch, [
        serRow(3000, "HeartRate", 52), serRow(4000, "RespirationRate", 13),
        { startTs: "2026-09-13T06:00:00.000Z", dataTypeId: 5020, dataTypeName: "Weight", value: 72.45, valueType: "DOUBLE", ...weight },
        { startTs: "2026-09-13T06:00:00.000Z", dataTypeId: 5025, dataTypeName: "FatRatio", value: 21.8, valueType: "DOUBLE", ...fat },
        { startTs: "2026-09-13T22:30:00.000Z", dataTypeId: 3301, dataTypeName: "BloodPressureSystolic", value: 121, valueType: "LONG", ...sys },
        { startTs: "2026-09-13T22:30:00.000Z", dataTypeId: 3300, dataTypeName: "BloodPressureDiastolic", value: 79, valueType: "LONG", ...dia },
        { startTs: "2026-09-13T22:30:00.000Z", dataTypeId: 3000, dataTypeName: "HeartRate", value: 68, valueType: "LONG", ...hr },
        { startTs: "2026-09-13T06:01:00.000Z", dataTypeId: 3008, dataTypeName: "PulseWaveVelocity", value: 7.85, valueType: "DOUBLE", ...pwv },
      ])
      // D4: no canonical HRV id anywhere, the raw values only under the sleep-duration row.
      const all = [...rows.daily, ...rows.epoch]
      assertEquals(all.filter((r) => [T.Rmssd, T.RmssdSleep, T.SDNN, T.SDRR, T.RmssdSleepHighest].includes(r.dataTypeId as never)), [])
      const carriers = all.filter((r) => r.details && ("sdnn_1_unverified" in r.details || "rmssd_unverified" in r.details))
      assertEquals(carriers.map((r) => r.dataTypeId), [T.MainSleepDuration])
      // Every row is traceable to a vendor record (grpid / sleep id) with its resource type; BP pair shares one record + timestamp (P16).
      assert(all.every((r) => r.sourceRecordId && r.sourceResourceType))
      const bp = rows.epoch.filter((r) => r.dataTypeId === T.SystolicBP || r.dataTypeId === T.DiastolicBP)
      assertEquals(new Set(bp.map((r) => `${r.sourceRecordId}|${r.startTs}`)).size, 1)
      // Manual entry (attrib 2, grpid 5004) never appears.
      assertEquals(all.filter((r) => r.sourceRecordId === "5004"), [])
    } finally { f.restore() }
  })
})

Deno.test("HRV fallback: when the summary lacks sdnn_1/rmssd the series means land in the same raw details — still no canonical row", async () => {
  const summary = await fixture("sleep_getsummary.json"), series = await fixture("sleep_get_series.json")
  delete summary.body.series[0].data.sdnn_1; delete summary.body.series[0].data.rmssd
  await withEnv(CREDS, async () => {
    const f = stubFetch((path, action) => path === "/v2/sleep" ? (action === "getsummary" ? summary : series) : path === "/measure" ? { status: 0, body: { measuregrps: [] } } : { status: 0, body: {} })
    try {
      const rows = await withings.fetchRange({ accessToken: "at" }, "2026-09-13", "2026-09-13", { patientId: "p", vendorUserId: "12345", meta: {} })
      const main = rows.daily.find((r) => r.dataTypeId === T.MainSleepDuration)!
      assertEquals([main.details!.sdnn_1_unverified, main.details!.rmssd_unverified, main.details!.hrv_source, main.details!.hrv_samples], [60, 45, "sleep_series_mean", 1])
      assertEquals([...rows.daily, ...rows.epoch].filter((r) => [3100, 3106, 3112].includes(r.dataTypeId)), [])
    } finally { f.restore() }
  })
})

Deno.test("WITHINGS_REGION: EU by default (D10); an unpinned region falls back to the EU host (VERIFY) instead of inventing one", async () => {
  await withEnv({ WITHINGS_REGION: null }, async () => { assertEquals(apiBase(), EU) })
  await withEnv({ WITHINGS_REGION: "eu" }, async () => { assertEquals(apiBase(), EU) })
  await withEnv({ WITHINGS_REGION: "US" }, async () => { assertEquals(apiBase(), EU) })
})
