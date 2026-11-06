// Polar Dynamic API v4 adapter, rebuilt 2026-11-06 against Polar's official v4 Swagger. Fixtures under fixtures/polar/v4_*
// carry the Swagger's field names (values illustrative). Pins: the documented scopes only, NO identity call (v4 has no user
// id), Nightly Recharge nested twice + sleepResultDate + RMSSD → 3106, sleeps listed by date then fetched one day at a time
// with repeated `features`, durations parsed from "N.s" strings, and the v3 webhook flag + signature (§11).
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1"
import { T, _setKeyForTests, decrypt, encrypt } from "../core.ts"
import { NIGHTLY_MAX_DAYS, POLAR_DATA, POLAR_TOKEN, POLAR_WEBHOOKS, SLEEP_FEATURES, _polarTest, nightlyList, polar, polarRegisterWebhook, polarSeconds, polarWebhookSecret, sleepList } from "../polar.ts"

const { rangeChunks, nightlyRechargeRows, sleepRows } = _polarTest

async function fixture<R = unknown>(name: string): Promise<R> {
  return JSON.parse(await Deno.readTextFile(new URL(`./fixtures/polar/${name}.json`, import.meta.url))) as R
}

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
    return new Response(JSON.stringify(out ?? {}), { status: 200, headers: { "Content-Type": "application/json" } })
  }) as typeof fetch
  return { calls, restore: () => { globalThis.fetch = original } }
}

Deno.env.set("POLAR_CLIENT_ID", "polar-client-id")
Deno.env.set("POLAR_CLIENT_SECRET", "polar-client-secret")

// MARK: - Contract

Deno.test("scopes: exactly the documented ones we read (no ppi:read, no unused families); auth.polar.com; no PKCE documented", () => {
  assertEquals(polar.scopes, ["profile:read", "sleep:read", "nightly_recharge:read"])
  const u = new URL(polar.authorizeURL({ clientId: "cid", redirectUri: "https://x/cb", state: "st" }))
  assertEquals(u.origin + u.pathname, "https://auth.polar.com/oauth/authorize")
  assertEquals(u.searchParams.get("scope"), "profile:read sleep:read nightly_recharge:read")
  assertEquals(polar.pkce, "not_documented")
  assertEquals(polar.revoke, undefined)
  assertEquals(polar.reconcile, { nightlyDays: 3, weeklyDays: 14 })
})

Deno.test("exchangeCode: Basic auth at auth.polar.com and NO identity call (v4 has no user id) — the old /v4/data/profile 404 is gone", async () => {
  const stub = stubFetch(({ url }) => url.toString() === POLAR_TOKEN
    ? { access_token: "acc", token_type: "bearer", refresh_token: "ref", expires_in: 43199, scope: "profile:read sleep:read nightly_recharge:read", jti: "j" }
    : new Response("not found", { status: 404 }))
  try {
    const before = Math.floor(Date.now() / 1000)
    const r = await polar.exchangeCode({ code: "the-code", redirectUri: "https://x/cb" })
    assertEquals(stub.calls.length, 1)
    const [tok] = stub.calls
    assertEquals([tok.url.toString(), tok.method], ["https://auth.polar.com/oauth/token", "POST"])
    assertEquals(tok.headers.get("Authorization"), "Basic " + btoa("polar-client-id:polar-client-secret"))
    assertEquals(new URLSearchParams(tok.body!).get("grant_type"), "authorization_code")
    assertEquals(r.vendorUserId, undefined)
    assertEquals([r.accessToken, r.refreshToken], ["acc", "ref"])
    assert(r.expiresAt! >= before + 43199 && r.expiresAt! <= before + 43200, "expiry comes from expires_in")
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

// MARK: - Pure mapping

Deno.test("polarSeconds parses the documented \"3.000000001s\" strings; anything else is null", () => {
  assertEquals([polarSeconds("3.000000001s"), polarSeconds("27000s"), polarSeconds("0s"), polarSeconds(12.6)], [3, 27000, 0, 13])
  assertEquals([polarSeconds("27000"), polarSeconds("PT2H"), polarSeconds(null)], [null, null, null])
})

Deno.test("rangeChunks: `to` is exclusive, chunks ≤ 28 days, a 40-day window splits 28 + 12", () => {
  const c = rangeChunks("2026-09-01", "2026-10-10", NIGHTLY_MAX_DAYS)
  assertEquals(c, [{ from: "2026-09-01", to: "2026-09-29" }, { from: "2026-09-29", to: "2026-10-11" }])
})

Deno.test("Nightly Recharge: the doubly nested list, sleepResultDate, RMSSD (ms, 0.5–4.5 h window) → 3106, indicator kept as Polar's code", async () => {
  const body = await fixture("v4_nightly_recharge")
  const list = nightlyList(body)
  assertEquals(list.length, 2)
  const rows = nightlyRechargeRows(list[0])
  const by = (id: number) => rows.find((r) => r.dataTypeId === id)
  assertEquals([by(T.RmssdSleep)?.day, by(T.RmssdSleep)?.value, by(T.RmssdSleep)?.details?.window], ["2026-11-05", 46, "0.5h-4.5h_after_sleep_start"])
  assertEquals([by(T.PolarNightlyRechargeStatus)?.valueText, by(T.PolarNightlyRechargeStatus)?.valueType, by(T.PolarNightlyRechargeStatus)?.details?.sub_level], ["5", "STRING", 62])
  assertEquals(by(T.PolarAnsStatus)?.value, 3.4)
  assertEquals(by(T.PolarAnsStatus)?.details?.mean_nightly_recovery_rri_ms, 1043)
  assertEquals(nightlyList({ nightlyRechargeResults: [] }), [])   // the old single-level guess finds nothing
})

Deno.test("one night with features → stages in seconds, efficiency, interruptions, score + Sleep Charge, start/end with offset", async () => {
  const [night] = sleepList(await fixture("v4_sleep_night"))
  const rows = sleepRows(night)
  const v = (id: number) => rows.find((r) => r.dataTypeId === id)?.value
  assertEquals([v(T.MainSleepDuration), v(T.InBed), v(T.REM), v(T.Deep), v(T.Light), v(T.Awake)], [25081, 27000, 5400, 6000, 13680, 1920])
  assertEquals([v(T.SleepEfficiency), v(T.Interruptions), v(T.SleepScore), v(T.PolarSleepCharge)], [92.9, 14, 81.4, 4])
  assertEquals(rows.find((r) => r.dataTypeId === T.SleepEnd)?.valueText, "2026-11-05T05:40:00.000Z")
  assertEquals(rows[0].timezoneOffset, 60)
  assertEquals(rows[0].sourceDeviceId, "A1B2C3D4")
  assert(rows.every((r) => r.day === "2026-11-05"))
})

Deno.test("fetchRange: Nightly Recharge in 28-day chunks; sleep dates first, then ONE day per call with repeated features; window filter", async () => {
  const recharge = await fixture("v4_nightly_recharge"), dates = await fixture("v4_sleep_dates"), night = await fixture<{ nightSleeps: Record<string, unknown>[] }>("v4_sleep_night")
  const stub = stubFetch(({ url }) => {
    if (url.pathname.endsWith("/nightly-recharge-results")) return recharge
    if (url.pathname.endsWith("/sleeps") && url.searchParams.getAll("features").length === 0) return dates
    if (url.pathname.endsWith("/sleeps")) return { nightSleeps: night.nightSleeps.map((n) => ({ ...n, sleepDate: url.searchParams.get("from") })) }
    return new Response("unexpected", { status: 500 })
  })
  try {
    const out = await polar.fetchRange({ accessToken: "acc" }, "2026-11-03", "2026-11-05", { patientId: "p", vendorUserId: null, meta: {} })
    for (const c of stub.calls) {
      assert(c.url.toString().startsWith(POLAR_DATA))
      assertEquals(c.headers.get("Authorization"), "Bearer acc")
    }
    const detailCalls = stub.calls.filter((c) => c.url.pathname.endsWith("/sleeps") && c.url.searchParams.getAll("features").length > 0)
    assertEquals(detailCalls.map((c) => [c.url.searchParams.get("from"), c.url.searchParams.get("to")]), [["2026-11-04", "2026-11-05"], ["2026-11-05", "2026-11-06"]])
    assertEquals(detailCalls[0].url.searchParams.getAll("features"), SLEEP_FEATURES)
    assert(out.daily.every((r) => r.day >= "2026-11-03" && r.day <= "2026-11-05"))   // 2026-10-20 is outside the window
    assertEquals(out.daily.filter((r) => r.dataTypeId === T.RmssdSleep).map((r) => r.day), ["2026-11-05"])
    assertEquals(out.daily.filter((r) => r.dataTypeId === T.SleepScore).map((r) => r.day), ["2026-11-04", "2026-11-05"])
    assertEquals(out.epoch, [])
  } finally { stub.restore() }
})

Deno.test("fetchRange: a 404 on a resource is 'no data', not a failure (§24)", async () => {
  const stub = stubFetch(() => new Response("not found", { status: 404 }))
  try {
    const out = await polar.fetchRange({ accessToken: "acc" }, "2026-11-05", "2026-11-05", { patientId: "p", vendorUserId: null, meta: {} })
    assertEquals(out, { daily: [], epoch: [] })
  } finally { stub.restore() }
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

