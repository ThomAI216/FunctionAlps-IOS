// Polar Dynamic API v4 adapter — golden trace against tests/fixtures/polar/*.json (synthetic shapes, see each `_note`).
// Pins: the v4 hosts, the 28-day / 1-day range chunking (polar.md §15), the exact rows (1000130 STRING, 1000132, 2200,
// 1000105, provenance), NO 3106 row while the RMSSD unit is unpinned (§30), the FunctionAlps RMSSD, the webhook flag
// + signature (§11), and identity from the profile call (§9).
import { assert, assertAlmostEquals, assertEquals, assertRejects } from "jsr:@std/assert@1"
import { T, _setKeyForTests, decrypt, encrypt } from "../core.ts"
import { NIGHTLY_MAX_DAYS, POLAR_DATA, POLAR_PROFILE, POLAR_TOKEN, POLAR_WEBHOOKS, _polarTest, polar, polarRegisterWebhook, polarWebhookSecret } from "../polar.ts"

const { rmssdFromPPI, rangeChunks, profileIdentity, unwrap, nightlyRechargeRows } = _polarTest

async function fixture<R = unknown>(name: string): Promise<R> {
  return JSON.parse(await Deno.readTextFile(new URL(`./fixtures/polar/${name}.json`, import.meta.url))) as R
}
type Collection = { response: Record<string, unknown>[] }

interface Call { url: URL; method: string; headers: Headers; body: string | null }
/** Replaces globalThis.fetch for one test; `handler` returns the JSON body (or a Response) for each call. */
function stubFetch(handler: (c: Call) => unknown): { calls: Call[]; restore: () => void } {
  const calls: Call[] = []
  const original = globalThis.fetch
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url)
    const body = init?.body == null ? null : init.body instanceof URLSearchParams ? init.body.toString() : String(init.body)
    const call: Call = { url, method: init?.method ?? "GET", headers: new Headers(init?.headers ?? {}), body }
    calls.push(call)
    const out = handler(call)
    if (out instanceof Response) return out
    return new Response(JSON.stringify(out ?? []), { status: 200, headers: { "Content-Type": "application/json" } })
  }) as typeof fetch
  return { calls, restore: () => { globalThis.fetch = original } }
}

Deno.env.set("POLAR_CLIENT_ID", "polar-client-id")
Deno.env.set("POLAR_CLIENT_SECRET", "polar-client-secret")

// MARK: - Pure helpers

Deno.test("rmssdFromPPI: the standard RMSSD over successive differences (hand-computed)", () => {
  // diffs 10, −20, 15 → squares 100, 400, 225 → mean 725/3 → sqrt = 15.5456…
  const v = rmssdFromPPI([800, 810, 790, 805])!
  assertAlmostEquals(v, Math.sqrt(725 / 3), 1e-12)
  assertAlmostEquals(v, 15.5456, 1e-4)
  assertEquals(rmssdFromPPI([800]), null)
  assertEquals(rmssdFromPPI([]), null)
  assertEquals(rmssdFromPPI([800, NaN, 0, -5]), null)               // only one accepted interval
  assertAlmostEquals(rmssdFromPPI([800, NaN, 810])!, 10, 1e-12)      // artefacts dropped before differencing
})

Deno.test("rangeChunks: `to` is exclusive (§21), chunks ≤ 28 days, a 40-day window splits 28 + 12", () => {
  assertEquals(rangeChunks("2026-08-05", "2026-09-13", NIGHTLY_MAX_DAYS), [{ from: "2026-08-05", to: "2026-09-02" }, { from: "2026-09-02", to: "2026-09-14" }])
  assertEquals(rangeChunks("2026-09-13", "2026-09-13", NIGHTLY_MAX_DAYS), [{ from: "2026-09-13", to: "2026-09-14" }])
  assertEquals(rangeChunks("2026-09-11", "2026-09-13", 1), [{ from: "2026-09-11", to: "2026-09-12" }, { from: "2026-09-12", to: "2026-09-13" }, { from: "2026-09-13", to: "2026-09-14" }])
})

Deno.test("profileIdentity fails closed; unwrap accepts a bare array or a wrapper", () => {
  assertEquals(profileIdentity({ userId: 42 }), "42")
  assertEquals(profileIdentity({ id: "abc" }), "abc")
  let threw = false
  try { profileIdentity({ email: "x@y" }) } catch { threw = true }
  assert(threw, "no identity field must throw, never yield an empty vendorUserId")
  assertEquals(unwrap([{ a: 1 }, 3], []), [{ a: 1 }])
  assertEquals(unwrap({ sleeps: [{ b: 2 }] }, ["sleeps"]), [{ b: 2 }])
  assertEquals(unwrap({}, ["x"]), [])
})

Deno.test("a categorical ansStatus is never coerced onto the numeric 1000132 (§18)", () => {
  const rows = nightlyRechargeRows({ id: "nr-9", date: "2026-09-10", status: "OK", ansStatus: "BALANCED" })
  assertEquals(rows.map((r) => r.dataTypeId), [T.PolarNightlyRechargeStatus])
  assertEquals(rows[0].details?.ans_status_raw, "BALANCED")
})

// MARK: - fetchRange golden trace

Deno.test("fetchRange: v4 hosts, 28-day chunking + one-day PPI calls for a 40-day window, exact rows", async () => {
  const nightly = await fixture<Collection>("nightly-recharge-results"), sleeps = await fixture<Collection>("sleeps"), ppi = await fixture<Collection>("ppi-samples")
  const within = (recs: Record<string, unknown>[], key: string, from: string, to: string) => recs.filter((r) => String(r[key]) >= from && String(r[key]) < to)
  const stub = stubFetch(({ url }) => {
    const from = url.searchParams.get("from")!, to = url.searchParams.get("to")!
    if (url.pathname.endsWith("/nightly-recharge-results")) return within(nightly.response, "date", from, to)
    if (url.pathname.endsWith("/sleeps")) return within(sleeps.response, "sleepDate", from, to)
    if (url.pathname.endsWith("/ppi-samples")) return within(ppi.response, "date", from, to)
    return new Response("nope", { status: 500 })
  })
  try {
    const rows = await polar.fetchRange({ accessToken: "at" }, "2026-08-05", "2026-09-13", { patientId: "p", vendorUserId: "u", meta: {} })

    // Every request hits the v4 data host with the bearer token.
    for (const c of stub.calls) {
      assertEquals(c.url.origin + c.url.pathname.replace(/\/[^/]+$/, ""), POLAR_DATA)
      assertEquals(c.headers.get("Authorization"), "Bearer at")
    }
    const byRes = (r: string) => stub.calls.filter((c) => c.url.pathname.endsWith("/" + r)).map((c) => ({ from: c.url.searchParams.get("from"), to: c.url.searchParams.get("to"), features: c.url.searchParams.get("features") }))
    assertEquals(byRes("nightly-recharge-results"), [{ from: "2026-08-05", to: "2026-09-02", features: null }, { from: "2026-09-02", to: "2026-09-14", features: null }])
    assertEquals(byRes("sleeps"), [{ from: "2026-08-05", to: "2026-09-02", features: null }, { from: "2026-09-02", to: "2026-09-14", features: null }])
    const ppiCalls = byRes("ppi-samples")
    assertEquals(ppiCalls.length, 40)
    assertEquals(ppiCalls[0], { from: "2026-08-05", to: "2026-08-06", features: "samples" })
    assertEquals(ppiCalls[39], { from: "2026-09-13", to: "2026-09-14", features: "samples" })
    assertEquals(stub.calls.length, 44)

    // Exact daily rows.
    const nightlyDetails = (rmssd: number, rri: number, resp: number) => ({
      mean_nightly_recovery_rmssd: rmssd, mean_nightly_recovery_rri: rri, mean_nightly_recovery_respiration_interval: resp,
      unverified: ["VERIFY: meanNightlyRecoveryRmssd unit not pinned in v4 schema (polar.md §30) — raw only, not 3106"],
    })
    const nProv = (id: string, mod: string) => ({ sourceRecordId: id, sourceResourceType: "nightly-recharge-results", sourceModifiedAt: mod, sourceDeviceId: null })
    const sleepDetails = { edited: true, stages_raw: { light: 14760, deep: 5820, rem: 6120, wake: 1740, unknown: 0 }, continuity: 3.2, unverified: ["VERIFY: stage duration unit not pinned (canonical-metric-map) — raw only"] }
    const sProv = { sourceRecordId: "sl-201", sourceResourceType: "sleeps", timezoneOffset: 120, sourceModifiedAt: "2026-09-12T09:05:00Z", sourceDeviceId: null }
    assertEquals(rows.daily, [
      { day: "2026-09-11", dataTypeId: 1000130, dataTypeName: "PolarNightlyRechargeStatus", value: null, valueText: "GOOD", valueType: "STRING", ...nProv("nr-101", "2026-09-11T05:10:00Z"), sourceField: "status", details: nightlyDetails(52.8, 1058, 4215) },
      { day: "2026-09-11", dataTypeId: 1000132, dataTypeName: "PolarAnsStatus", value: 2.1, valueType: "DOUBLE", ...nProv("nr-101", "2026-09-11T05:10:00Z"), sourceField: "ansStatus", details: nightlyDetails(52.8, 1058, 4215) },
      { day: "2026-09-12", dataTypeId: 1000130, dataTypeName: "PolarNightlyRechargeStatus", value: null, valueText: "COMPROMISED", valueType: "STRING", ...nProv("nr-102", "2026-09-12T05:12:00Z"), sourceField: "status", details: nightlyDetails(47.3, 1041, 4180) },
      { day: "2026-09-12", dataTypeId: 1000132, dataTypeName: "PolarAnsStatus", value: -1.4, valueType: "DOUBLE", ...nProv("nr-102", "2026-09-12T05:12:00Z"), sourceField: "ansStatus", details: nightlyDetails(47.3, 1041, 4180) },
      { day: "2026-09-12", dataTypeId: 2200, dataTypeName: "SleepEfficiency", value: 91, valueType: "LONG", ...sProv, sourceField: "efficiency", details: sleepDetails },
      { day: "2026-09-12", dataTypeId: 1000105, dataTypeName: "SleepScore", value: 78, valueType: "LONG", ...sProv, sourceField: "sleepScore", details: sleepDetails },
      { day: "2026-09-12", dataTypeId: 2400, dataTypeName: "ThryveMainSleepStartTime", value: 1789159260, valueText: "2026-09-11T20:41:00.000Z", valueType: "DATE", ...sProv, sourceField: "sleepStartTime" },
      { day: "2026-09-12", dataTypeId: 2401, dataTypeName: "ThryveMainSleepEndTime", value: 1789187700, valueText: "2026-09-12T04:35:00.000Z", valueType: "DATE", ...sProv, sourceField: "sleepEndTime" },
    ])
    // D4 / §30: no vendor RMSSD row until the unit is pinned; no sleep charge row (not exposed in the fixture).
    assertEquals(rows.daily.filter((r) => r.dataTypeId === T.RmssdSleep || r.dataTypeId === T.PolarSleepCharge), [])

    // Exact epoch rows: one FunctionAlps-derived RMSSD per PPI sample set.
    const expected = rmssdFromPPI([800, 810, 790, 805, 815, 798])!
    assertEquals(rows.epoch, [{
      startTs: "2026-09-12T01:00:00.000Z", endTs: "2026-09-12T01:00:04.020Z", dataTypeId: 3100, dataTypeName: "Rmssd", value: expected, valueType: "DOUBLE",
      sourceRecordId: "ppi-301", sourceResourceType: "ppi-samples", sourceField: "ppInterval", sourceModifiedAt: "2026-09-12T06:40:00Z", sourceDeviceId: null,
      details: { algorithm: "functionalps_rmssd_v1", n: 6, rejected: 0, quality: "functionalps_derived", window_ms: 4020, anchor: "record_start" },
    }])
    assertAlmostEquals(expected, Math.sqrt((100 + 400 + 225 + 100 + 289) / 5), 1e-12)
  } finally { stub.restore() }
})

Deno.test("fetchRange: a 404 on a resource is 'no data', not a failure (§24)", async () => {
  const stub = stubFetch(() => new Response("not found", { status: 404 }))
  try {
    const rows = await polar.fetchRange({ accessToken: "at" }, "2026-09-13", "2026-09-13", { patientId: "p", vendorUserId: "u", meta: {} })
    assertEquals(rows, { daily: [], epoch: [] })
    assertEquals(stub.calls.length, 3)
  } finally { stub.restore() }
})

// MARK: - OAuth

Deno.test("exchangeCode: Basic auth at auth.polar.com, vendorUserId from the v4 profile call (never x_user_id)", async () => {
  const profile = await fixture<{ response: Record<string, unknown> }>("profile")
  const stub = stubFetch(({ url }) => {
    if (url.toString() === POLAR_TOKEN) return { access_token: "acc", token_type: "bearer", refresh_token: "ref", expires_in: 43199, scope: "profile:read sleep:read", jti: "j", x_user_id: 999 }
    if (url.toString() === POLAR_PROFILE) return profile.response
    return new Response("nope", { status: 500 })
  })
  try {
    const before = Math.floor(Date.now() / 1000)
    const r = await polar.exchangeCode({ code: "the-code", redirectUri: "https://x/cb" })
    const [tok, prof] = stub.calls
    assertEquals(tok.url.toString(), "https://auth.polar.com/oauth/token")
    assertEquals(tok.method, "POST")
    assertEquals(tok.headers.get("Authorization"), "Basic " + btoa("polar-client-id:polar-client-secret"))
    assertEquals(new URLSearchParams(tok.body!).get("grant_type"), "authorization_code")
    assertEquals(new URLSearchParams(tok.body!).get("code"), "the-code")
    assertEquals(prof.url.toString(), "https://www.polaraccesslink.com/v4/data/profile")
    assertEquals(prof.headers.get("Authorization"), "Bearer acc")
    assertEquals(r.vendorUserId, "polar-v4-8123456")
    assertEquals([r.accessToken, r.refreshToken, r.scopes], ["acc", "ref", ["profile:read", "sleep:read"]])
    assert(r.expiresAt! >= before + 43199 && r.expiresAt! <= before + 43200, "expiry comes from expires_in, not a constant")
  } finally { stub.restore() }
})

Deno.test("refresh: same token host, grant_type=refresh_token, keeps the old refresh token when none is returned (§8)", async () => {
  const stub = stubFetch(() => ({ access_token: "acc2", expires_in: 43199 }))
  try {
    const t = await polar.refresh("old-ref")
    assertEquals(stub.calls[0].url.toString(), POLAR_TOKEN)
    assertEquals(new URLSearchParams(stub.calls[0].body!).get("grant_type"), "refresh_token")
    assertEquals([t.accessToken, t.refreshToken], ["acc2", "old-ref"])
  } finally { stub.restore() }
})

Deno.test("authorizeURL: auth.polar.com with the granular scopes; pkce not documented; no revoke/afterConnect", () => {
  const u = new URL(polar.authorizeURL({ clientId: "cid", redirectUri: "https://x/cb", state: "st" }))
  assertEquals(u.origin + u.pathname, "https://auth.polar.com/oauth/authorize")
  assertEquals(u.searchParams.get("scope"), polar.scopes.join(" "))
  assert(polar.scopes.includes("nightly_recharge:read") && polar.scopes.includes("profile:read"))
  assertEquals(polar.pkce, "not_documented")
  assertEquals(polar.revoke, undefined)
  assertEquals(polar.afterConnect, undefined)
  assertEquals(polar.reconcile, { nightlyDays: 3, weeklyDays: 14 })
})

// MARK: - Webhook

async function signed(body: string, secret: string, event = "SLEEP"): Promise<Request> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
  const mac = Array.from(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)))).map((b) => b.toString(16).padStart(2, "0")).join("")
  return new Request("https://fn/wearable-vendor-webhook/polar", { method: "POST", headers: { "Polar-Webhook-Signature": mac, "Polar-Webhook-Event": event, "Content-Type": "application/json" }, body })
}

Deno.test("parseWebhook: [] while POLAR_WEBHOOKS_ENABLED is unset, even for a validly signed event", async () => {
  const fx = await fixture<{ body: Record<string, unknown> }>("webhook")
  const body = JSON.stringify(fx.body)
  Deno.env.delete("POLAR_WEBHOOKS_ENABLED")
  Deno.env.set("POLAR_WEBHOOK_SECRET", "whsec")
  assertEquals(await polar.parseWebhook(await signed(body, "whsec"), body, new URL("https://fn/x")), [])
  Deno.env.set("POLAR_WEBHOOKS_ENABLED", "0")
  assertEquals(await polar.parseWebhook(await signed(body, "whsec"), body, new URL("https://fn/x")), [])
})

Deno.test("parseWebhook (flag set): lowercase-hex HMAC over the raw body, kind from Polar-Webhook-Event, window from date", async () => {
  const fx = await fixture<{ body: Record<string, unknown> }>("webhook")
  const body = JSON.stringify(fx.body)
  Deno.env.set("POLAR_WEBHOOKS_ENABLED", "1")
  Deno.env.set("POLAR_WEBHOOK_SECRET", "whsec")
  try {
    const ok = await polar.parseWebhook(await signed(body, "whsec"), body, new URL("https://fn/x"))
    assertEquals(ok, [{ vendorUserId: "475", kind: "SLEEP", eventId: null, windowStart: "2026-09-12", windowEnd: "2026-09-12" }])
    // Uppercase hex from the vendor is accepted; a wrong key or a tampered body is not.
    const req = await signed(body, "whsec")
    const upper = new Request(req, { headers: { "Polar-Webhook-Signature": req.headers.get("Polar-Webhook-Signature")!.toUpperCase(), "Polar-Webhook-Event": "SLEEP" } })
    assertEquals((await polar.parseWebhook(upper, body, new URL("https://fn/x")) as unknown[]).length, 1)
    await assertRejects(async () => { await polar.parseWebhook(await signed(body, "other"), body, new URL("https://fn/x")) }, Error, "signature mismatch")
    await assertRejects(async () => { await polar.parseWebhook(await signed(body, "whsec"), body.replace("475", "476"), new URL("https://fn/x")) }, Error, "signature mismatch")
    // The creation PING is acknowledged before any secret exists (§11).
    const ping = JSON.stringify({ event: "PING", timestamp: "2026-09-12T06:00:00Z" })
    assertEquals(await polar.parseWebhook(new Request("https://fn/x", { method: "POST", body: ping }), ping, new URL("https://fn/x")), [])
  } finally { Deno.env.delete("POLAR_WEBHOOKS_ENABLED") }
})

// MARK: - App-level webhook: the signing key lives encrypted in the subscription row, registered by the backend

const WEBHOOK_AAD = { accountId: "app", vendor: "polar", tokenType: "webhook" } as const
Deno.env.set("SUPABASE_URL", "https://proj.supabase.co")   // webhookUrl() derives the callback from it

/** A tiny awaitable query builder: `from(table)…maybeSingle()` returns `state.row`, writes are recorded. */
function stubDb(state: { row: Record<string, unknown> | null; inserted: Record<string, unknown>[]; updated: Record<string, unknown>[] }) {
  const builder = (table: string) => {
    let op: "select" | "insert" | "update" = "select"
    const b: Record<string, unknown> = {}
    const self = () => b
    for (const m of ["select", "eq", "is", "order", "limit"]) b[m] = self
    b.insert = (v: Record<string, unknown>) => { op = "insert"; state.inserted.push({ table, ...v }); return b }
    b.update = (v: Record<string, unknown>) => { op = "update"; state.updated.push({ table, ...v }); return b }
    b.maybeSingle = () => Promise.resolve({ data: state.row, error: null })
    b.then = (res: (v: unknown) => void) => res({ data: op === "select" ? state.row : null, error: null })
    return b
  }
  return { from: builder } as unknown as Parameters<typeof polarRegisterWebhook>[0]
}

Deno.test("polarWebhookSecret: env wins; otherwise the active app row's meta.secret_enc decrypts with the key ring; neither → throws", async () => {
  _setKeyForTests(1, new Uint8Array(32))
  Deno.env.set("POLAR_WEBHOOK_SECRET", "from-env")
  assertEquals(await polarWebhookSecret(stubDb({ row: null, inserted: [], updated: [] })), "from-env")
  Deno.env.delete("POLAR_WEBHOOK_SECRET")
  _polarTest.resetWebhookSecretCache()
  const secret_enc = await encrypt("abe1f3ae-once-shown", WEBHOOK_AAD, 1)
  assertEquals(await polarWebhookSecret(stubDb({ row: { meta: { secret_enc } }, inserted: [], updated: [] })), "abe1f3ae-once-shown")
  _polarTest.resetWebhookSecretCache()
  await assertRejects(() => polarWebhookSecret(stubDb({ row: null, inserted: [], updated: [] })), Error, "polar webhook secret unset")
  Deno.env.set("POLAR_WEBHOOK_SECRET", "whsec")
})

Deno.test("polarRegisterWebhook: a foreign webhook is deleted, ours is created with the documented events, the key is stored encrypted and never returned", async () => {
  _setKeyForTests(1, new Uint8Array(32))
  Deno.env.set("POLAR_CLIENT_ID", "polar-client-id"); Deno.env.set("POLAR_CLIENT_SECRET", "polar-client-secret")
  const calls: { method: string; url: string; body?: string }[] = []
  const fetchImpl = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input), method = init?.method ?? "GET"
    calls.push({ method, url, body: typeof init?.body === "string" ? init.body : undefined })
    if (method === "GET") return Promise.resolve(new Response(JSON.stringify({ data: [{ id: "old1", events: ["EXERCISE"], url: "https://elsewhere/hook" }] }), { status: 200 }))
    if (method === "DELETE") return Promise.resolve(new Response(null, { status: 204 }))
    return Promise.resolve(new Response(JSON.stringify({ data: { id: "new7", events: JSON.parse(init!.body as string).events, url: JSON.parse(init!.body as string).url, signature_secret_key: "once-shown-key" } }), { status: 201 }))
  }) as typeof fetch
  const state = { row: null, inserted: [] as Record<string, unknown>[], updated: [] as Record<string, unknown>[] }
  const r = await polarRegisterWebhook(stubDb(state), { fetchImpl })
  assertEquals(r.action, "recreated"); assertEquals(r.id, "new7")
  assertEquals(r.events, ["EXERCISE", "SLEEP", "CONTINUOUS_HEART_RATE", "ACTIVITY_SUMMARY", "PHYSICAL_INFORMATION"])
  assert(!JSON.stringify(r).includes("once-shown-key"))
  assertEquals(calls.map((c) => c.method), ["GET", "DELETE", "POST"])
  assertEquals(calls[1].url, `${POLAR_WEBHOOKS}/old1`)
  assertEquals(calls[2].url, POLAR_WEBHOOKS)
  assertEquals(state.updated.length, 1)                    // the previous app row (if any) is retired
  const row = state.inserted[0] as { vendor: string; vendor_subscription_id: string; status: string; meta: { secret_enc: string } }
  assertEquals([row.vendor, row.vendor_subscription_id, row.status], ["polar", "new7", "active"])
  assert(!row.meta.secret_enc.includes("once-shown-key"))
  assertEquals(await decrypt(row.meta.secret_enc, WEBHOOK_AAD), "once-shown-key")
})

Deno.test("polarRegisterWebhook: kept when Polar's webhook is the one we hold a key for at our URL", async () => {
  _setKeyForTests(1, new Uint8Array(32))
  Deno.env.set("POLAR_CLIENT_ID", "polar-client-id"); Deno.env.set("POLAR_CLIENT_SECRET", "polar-client-secret")
  const ours = (await import("../core.ts")).webhookUrl("polar")
  const fetchImpl = ((_i: string | URL | Request, init?: RequestInit) => {
    if ((init?.method ?? "GET") !== "GET") throw new Error("must not write")
    return Promise.resolve(new Response(JSON.stringify({ data: [{ id: "keep1", events: ["SLEEP"], url: ours }] }), { status: 200 }))
  }) as typeof fetch
  const state = { row: { vendor_subscription_id: "keep1", callback_url: ours, meta: { secret_enc: "v2.1.xx" } }, inserted: [], updated: [] }
  const r = await polarRegisterWebhook(stubDb(state), { fetchImpl })
  assertEquals(r.action, "kept"); assertEquals(state.inserted.length, 0)
})

