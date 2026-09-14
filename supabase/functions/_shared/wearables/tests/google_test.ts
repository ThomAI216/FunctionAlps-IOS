// Google Health adapter — golden trace against fixtures/google/* (strategy Phase 2, D4/D10). `globalThis.fetch` is
// stubbed to serve the fixtures, the token endpoint, the identity call, the subscriber endpoint and a keyset that
// this file generates (a P-256 key pair from WebCrypto, exported into Tink's JSON keyset shape). Nothing here
// touches the network.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1"
import { T, type TokenSet } from "../core.ts"
import { API, KEYSET_URL, SIGNATURE_HEADER, _googleTest, derToP1363, google, googleAuthorizeURL, parseKeyset, verifySignature } from "../google.ts"

Deno.env.set("GOOGLE_CLIENT_ID", "cid-test")
Deno.env.set("GOOGLE_CLIENT_SECRET", "csecret-test")
Deno.env.set("GOOGLE_WEBHOOK_SECRET", "hook-secret-test")
Deno.env.set("GOOGLE_CLOUD_PROJECT_NUMBER", "123456789012")

const fixturesDir = new URL("./fixtures/google/", import.meta.url)
const fixture = async (name: string) => JSON.parse(await Deno.readTextFile(new URL(name, fixturesDir)))
const tokens: TokenSet = { accessToken: "at-1", refreshToken: "rt-1" }
const enc = (s: string): Uint8Array<ArrayBuffer> => new TextEncoder().encode(s)

// MARK: - Tink keyset + signature helpers (test side)

const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b))
const unb64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - s.length % 4) % 4)), (c) => c.charCodeAt(0))
const varint = (n: number) => { const out: number[] = []; do { let b = n & 0x7f; n = Math.floor(n / 128); if (n) b |= 0x80; out.push(b) } while (n); return out }
const field = (no: number, wire: 0 | 2, v: number | Uint8Array): number[] => wire === 0 ? [...varint((no << 3) | 0), ...varint(v as number)] : [...varint((no << 3) | 2), ...varint((v as Uint8Array).length), ...(v as Uint8Array)]

/** Serialises Tink's `EcdsaPublicKey` proto: version, params { hash SHA256=3, curve P256=2, encoding }, x, y. */
function tinkEcdsaPublicKey(x: Uint8Array, y: Uint8Array, encoding: 1 | 2): Uint8Array {
  const params = new Uint8Array([...field(1, 0, 3), ...field(2, 0, 2), ...field(3, 0, encoding)])
  return new Uint8Array([...field(1, 0, 0), ...field(2, 2, params), ...field(3, 2, x), ...field(4, 2, y)])
}

interface TestKey { pair: CryptoKeyPair; keyId: number; x: Uint8Array; y: Uint8Array }
async function makeKey(keyId: number): Promise<TestKey> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey)
  return { pair, keyId, x: unb64url(jwk.x!), y: unb64url(jwk.y!) }
}

/** A Tink JSON keyset. The x coordinate gets a leading sign byte (33 bytes) like Tink's BigInteger encoding does. */
function tinkKeyset(keys: { k: TestKey; prefix: "TINK" | "RAW" | "LEGACY"; encoding: 1 | 2 }[]) {
  return {
    primaryKeyId: keys[0].k.keyId,
    key: keys.map(({ k, prefix, encoding }) => ({
      keyData: { typeUrl: "type.googleapis.com/google.crypto.tink.EcdsaPublicKey", value: b64(tinkEcdsaPublicKey(new Uint8Array([0, ...k.x]), k.y, encoding)), keyMaterialType: "ASYMMETRIC_PUBLIC" },
      status: "ENABLED", keyId: k.keyId, outputPrefixType: prefix,
    })),
  }
}

function p1363ToDer(sig: Uint8Array): Uint8Array {
  const int = (b: Uint8Array) => { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; let v = b.slice(i); if (v[0] & 0x80) v = new Uint8Array([0, ...v]); return [0x02, v.length, ...v] }
  const body = [...int(sig.slice(0, 32)), ...int(sig.slice(32))]
  return new Uint8Array([0x30, body.length, ...body])
}

/** Signs `bytes` the way a Tink PublicKeySign would for the given prefix/encoding and returns the header value. */
async function sign(k: TestKey, bytes: Uint8Array<ArrayBuffer>, prefix: "TINK" | "RAW" | "LEGACY", encoding: 1 | 2): Promise<string> {
  const msg: Uint8Array<ArrayBuffer> = prefix === "LEGACY" ? new Uint8Array([...bytes, 0]) : bytes
  const p1363 = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, k.pair.privateKey, msg))
  const raw = encoding === 2 ? p1363ToDer(p1363) : p1363
  const id = k.keyId, pre = prefix === "RAW" ? [] : [prefix === "TINK" ? 0x01 : 0x00, (id >>> 24) & 0xff, (id >>> 16) & 0xff, (id >>> 8) & 0xff, id & 0xff]
  return b64(new Uint8Array([...pre, ...raw]))
}

// MARK: - fetch stub

type Route = (url: URL, init: RequestInit | undefined) => Promise<Response> | Response
interface Call { method: string; url: string; body: string | null }
const jsonResp = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })

async function withFetch<R>(route: Route, fn: (calls: Call[]) => Promise<R>): Promise<R> {
  const real = globalThis.fetch
  const calls: Call[] = []
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input))
    const body = init?.body == null ? null : typeof init.body === "string" ? init.body : init.body instanceof URLSearchParams ? init.body.toString() : String(init.body)
    calls.push({ method: init?.method ?? "GET", url: url.toString(), body })
    return await route(url, init)
  }) as typeof fetch
  try { return await fn(calls) } finally { globalThis.fetch = real }
}

/** Serves the fixtures for the day 2026-09-13; every other data type is empty, every rollup is 404 (= nothing that day). */
async function apiRoute(keysetJson: unknown): Promise<Route> {
  const hrv = await fixture("heart_rate_variability.json"), dhrv = await fixture("daily_heart_rate_variability.json"), sleep = await fixture("sleep.json"), temp = await fixture("daily_sleep_temperature_derivations.json")
  const byType: Record<string, unknown> = { "heart-rate-variability": hrv, "daily-heart-rate-variability": dhrv, sleep, "daily-sleep-temperature-derivations": temp }
  return (url, init) => {
    if (url.toString() === KEYSET_URL) return jsonResp(keysetJson)
    if (url.pathname.endsWith(":dailyRollUp")) return new Response("not found", { status: 404 })
    const m = /\/v4\/users\/me\/dataTypes\/([^/]+)\/dataPoints$/.exec(url.pathname)
    if (m) {
      assertEquals((init?.headers as Record<string, string>).Authorization, "Bearer at-1")
      return jsonResp(byType[m[1]] ?? { dataPoints: [] })
    }
    return new Response("unexpected " + url, { status: 500 })
  }
}

// MARK: - OAuth

Deno.test("authorizeURL: the four corpus scopes, no settings scope, PKCE S256, offline, no prompt unless consent is forced", () => {
  const u = new URL(google.authorizeURL({ clientId: "cid", redirectUri: "https://x/cb", state: "st", codeChallenge: "chal" }))
  assertEquals(u.origin + u.pathname, "https://accounts.google.com/o/oauth2/v2/auth")
  const scope = u.searchParams.get("scope")!.split(" ")
  assertEquals(scope, ["activity_and_fitness", "health_metrics_and_measurements", "sleep", "profile"].map((s) => `https://www.googleapis.com/auth/googlehealth.${s}.readonly`))
  assert(!scope.some((s) => s.includes("settings")))
  assertEquals([u.searchParams.get("access_type"), u.searchParams.get("include_granted_scopes"), u.searchParams.get("code_challenge"), u.searchParams.get("code_challenge_method"), u.searchParams.get("state")], ["offline", "true", "chal", "S256", "st"])
  assertEquals(u.searchParams.get("prompt"), null)
  const forced = new URL(googleAuthorizeURL({ clientId: "cid", redirectUri: "https://x/cb", state: "st" }, { forceConsent: true }))
  assertEquals(forced.searchParams.get("prompt"), "consent")
  assertEquals(forced.searchParams.get("code_challenge"), null)
  assertEquals(google.pkce, "supported")
  assertEquals(google.reconcile, { nightlyDays: 3, weeklyDays: 14 })
  assertEquals(google.unsubscribe, undefined)
})

Deno.test("exchangeCode: token + getIdentity → healthUserId as vendorUserId, legacyUserId kept as raw metadata", async () => {
  await withFetch((url) => {
    if (url.toString() === "https://oauth2.googleapis.com/token") return jsonResp({ access_token: "at-new", refresh_token: "rt-new", expires_in: 3599, token_type: "Bearer", scope: "https://www.googleapis.com/auth/googlehealth.sleep.readonly https://www.googleapis.com/auth/googlehealth.profile.readonly" })
    if (url.pathname === "/v4/users/me:getIdentity") return jsonResp({ healthUserId: "hu-123", legacyUserId: "FITBIT1" })
    return new Response("unexpected", { status: 500 })
  }, async (calls) => {
    const r = await google.exchangeCode({ code: "c", redirectUri: "https://x/cb", codeVerifier: "ver" })
    assertEquals([r.accessToken, r.refreshToken, r.vendorUserId, r.raw?.legacy_user_id], ["at-new", "rt-new", "hu-123", "FITBIT1"])
    assertEquals(r.scopes?.length, 2)
    const p = new URLSearchParams(calls[0].body!)
    assertEquals([p.get("grant_type"), p.get("client_id"), p.get("client_secret"), p.get("code_verifier"), p.get("redirect_uri")], ["authorization_code", "cid-test", "csecret-test", "ver", "https://x/cb"])
  })
})

Deno.test("refresh adopts a rotated refresh_token and keeps the current one when Google omits it", async () => {
  await withFetch(() => jsonResp({ access_token: "at-2", expires_in: 3600, refresh_token: "rt-2" }), async (calls) => {
    const t = await google.refresh("rt-1")
    assertEquals([t.accessToken, t.refreshToken], ["at-2", "rt-2"])
    assert(t.expiresAt! > Date.now() / 1000 + 3500)
    assertEquals(new URLSearchParams(calls[0].body!).get("grant_type"), "refresh_token")
  })
  await withFetch(() => jsonResp({ access_token: "at-3", expires_in: 3600 }), async () => {
    const t = await google.refresh("rt-1")
    assertEquals([t.accessToken, t.refreshToken], ["at-3", "rt-1"])
  })
})

Deno.test("afterConnect registers the project-level subscriber once (endpointAuthorization secret, data types) and records its id", async () => {
  const subscribers: Record<string, unknown>[] = []
  const route: Route = (url, init) => {
    if (url.pathname === "/v4/projects/123456789012/subscribers" && (init?.method ?? "GET") === "GET") return jsonResp({ subscribers })
    if (url.pathname === "/v4/projects/123456789012/subscribers" && init?.method === "POST") { const b = JSON.parse(String(init.body)); subscribers.push({ ...b, name: "projects/123456789012/subscribers/sub-1" }); return jsonResp({ name: "projects/123456789012/subscribers/sub-1" }) }
    return new Response("unexpected", { status: 500 })
  }
  await withFetch(route, async (calls) => {
    const r = await google.afterConnect!({ ...tokens, raw: { legacy_user_id: "FITBIT1" } }, { patientId: "p", webhookUrl: "https://fn/wearable-vendor-webhook/google", vendorUserId: "hu-123" })
    assertEquals(r.meta?.subscriber_id, "projects/123456789012/subscribers/sub-1")
    assertEquals(r.meta?.subscriber_status, "created")
    assertEquals(r.meta?.legacy_user_id, "FITBIT1")
    const create = JSON.parse(calls.find((c) => c.method === "POST")!.body!)
    assertEquals(create.endpointUri, "https://fn/wearable-vendor-webhook/google")
    assertEquals(create.endpointAuthorization, { secret: "hook-secret-test" })
    assert(create.subscriberConfigs.some((c: { dataType: string }) => c.dataType === "heart-rate-variability"))
  })
  await withFetch(route, async (calls) => {
    const r = await google.afterConnect!(tokens, { patientId: "p", webhookUrl: "https://fn/wearable-vendor-webhook/google", vendorUserId: "hu-123" })
    assertEquals([r.meta?.subscriber_status, r.meta?.subscriber_id], ["existing", "projects/123456789012/subscribers/sub-1"])
    assertEquals(calls.filter((c) => c.method === "POST").length, 0)
  })
  await withFetch(() => new Response("boom", { status: 500 }), async () => {
    const r = await google.afterConnect!(tokens, { patientId: "p", webhookUrl: "https://fn/x", vendorUserId: "hu-123" })
    assertEquals(r.meta?.subscriber_status, "error")   // best effort: the connect still succeeds
  })
})

// MARK: - Golden trace

Deno.test("golden: fixtures → exact rows; RMSSD on 3100 (epoch + daily aggregate), SDNN on 3112, 3106 absent, temperature rows, provenance on every row", async () => {
  _googleTest.resetKeyset()
  const k = await makeKey(0x0a1b2c3d)
  const rows = await withFetch(await apiRoute(tinkKeyset([{ k, prefix: "TINK", encoding: 2 }])), () => google.fetchRange(tokens, "2026-09-13", "2026-09-13", { patientId: "p", vendorUserId: "hu-123", meta: {} }))

  const sleepId = "users/me/dataTypes/sleep/dataPoints/slp-20260913-1"
  assertEquals(rows.daily.map((r) => [r.dataTypeId, r.value, r.sourceRecordId]), [
    [2200, 100 * 420 / 450, sleepId], [2300, 25200, sleepId], [2301, 27000, sleepId], [2302, 5400, sleepId], [2303, 5400, sleepId], [2305, 14400, sleepId], [2306, 1800, sleepId], [2307, 600, sleepId], [2402, 5, sleepId],
    [2400, Date.parse("2026-09-12T21:30:00Z") / 1000, sleepId], [2401, Date.parse("2026-09-13T05:00:00Z") / 1000, sleepId],
    [3002, 54, "users/me/dataTypes/daily-heart-rate-variability/dataPoints/dhrv-20260913"],
    [3100, 46.5, "users/me/dataTypes/daily-heart-rate-variability/dataPoints/dhrv-20260913"],
    [5041, 33.9, "users/me/dataTypes/daily-sleep-temperature-derivations/dataPoints/tmp-20260913"],
    [1000106, 0.3, "users/me/dataTypes/daily-sleep-temperature-derivations/dataPoints/tmp-20260913"],
  ])
  const hrv1 = "users/me/dataTypes/heart-rate-variability/dataPoints/hrv-20260913-0405", hrv2 = "users/me/dataTypes/heart-rate-variability/dataPoints/hrv-20260913-0410"
  assertEquals(rows.epoch.map((r) => [r.dataTypeId, r.startTs, r.endTs ?? null, r.value, r.sourceRecordId]), [
    [2003, "2026-09-12T21:30:00Z", "2026-09-12T22:30:00Z", 60, sleepId], [2005, "2026-09-12T22:30:00Z", "2026-09-13T00:00:00Z", 90, sleepId], [2002, "2026-09-13T00:00:00Z", "2026-09-13T00:30:00Z", 30, sleepId],
    [3100, "2026-09-13T02:05:00Z", null, 48.2, hrv1], [3112, "2026-09-13T02:05:00Z", null, 55.1, hrv1],
    [3100, "2026-09-13T02:10:00Z", null, 51.7, hrv2],
  ])
  // The HRV sample row in full: RMSSD ms on 3100, provenance + version + offset, never 3106.
  assertEquals(rows.epoch[3], {
    startTs: "2026-09-13T02:05:00Z", dataTypeId: T.Rmssd, dataTypeName: "Rmssd", value: 48.2, valueType: "DOUBLE", timezoneOffset: 120,
    sourceRecordId: hrv1, sourceResourceType: "heart-rate-variability", sourceModifiedAt: "2026-09-13T04:06:10Z", sourceDeviceId: "dev-fitbit-01",
    details: { statistic: "rmssd", window: "sample", version: "1" },
  })
  const dailyHrv = rows.daily.find((r) => r.dataTypeId === T.Rmssd)!
  assertEquals(dailyHrv, {
    day: "2026-09-13", dataTypeId: 3100, dataTypeName: "Rmssd", value: 46.5, valueType: "DOUBLE",
    sourceRecordId: "users/me/dataTypes/daily-heart-rate-variability/dataPoints/dhrv-20260913", sourceResourceType: "daily-heart-rate-variability", sourceModifiedAt: "2026-09-13T07:12:00Z", sourceDeviceId: "dev-fitbit-01",
    details: { statistic: "rmssd", window: "daily_aggregate", deep_sleep_rmssd_ms: 52, version: "2" },
  })
  const temp = rows.daily.filter((r) => r.sourceResourceType === "daily-sleep-temperature-derivations")
  assertEquals(temp.map((r) => [r.dataTypeName, r.value]), [["SkinTemperature", 33.9], ["SkinTemperatureDeviation", 0.3]])
  assertEquals(temp[1].details, { baseline_celsius: 33.6, relative_nightly_stddev_30d_celsius: 0.4, deviation_derived: "nightly_minus_baseline_celsius", version: "1" })
  const all = [...rows.daily, ...rows.epoch]
  assertEquals(all.filter((r) => r.dataTypeId === T.RmssdSleep || r.dataTypeId === T.RmssdSleepHighest).length, 0)
  for (const r of all) { assert(r.sourceRecordId, `row ${r.dataTypeId} lacks sourceRecordId`); assert(r.sourceResourceType, `row ${r.dataTypeId} lacks sourceResourceType`) }
  assertEquals(rows.daily.filter((r) => r.sourceResourceType === "sleep").every((r) => r.timezoneOffset === 120), true)
  assertEquals(rows.daily.filter((r) => r.sourceRecordId?.includes("nap")).length, 0)   // the non-main sleep is skipped
})

// MARK: - Webhook: Authorization secret + Tink/ECDSA signature

const hookUrl = new URL("https://fn/wearable-vendor-webhook/google")
const request = (body: string, headers: Record<string, string>) => new Request(hookUrl, { method: "POST", body, headers })
const auth = { Authorization: "Bearer hook-secret-test" }

Deno.test("parseWebhook: a TINK-prefixed DER signature over the exact bytes is accepted and yields eventIds + windows", async () => {
  _googleTest.resetKeyset()
  const k = await makeKey(0x0a1b2c3d)
  const body = JSON.stringify((await fixture("webhook_notification.json")).body)
  const sig = await sign(k, enc(body), "TINK", 2)
  await withFetch(await apiRoute(tinkKeyset([{ k, prefix: "TINK", encoding: 2 }])), async (calls) => {
    const events = await google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: sig }), body, hookUrl)
    assertEquals(events, [
      { vendorUserId: "hu-123", kind: "heart-rate-variability.UPSERT", eventId: "msg-7f3a1c", windowStart: "2026-09-13", windowEnd: "2026-09-13" },
      { vendorUserId: "hu-123", kind: "sleep.DELETE", eventId: "hu-123|sleep|users/me/dataTypes/sleep/dataPoints/slp-20260913-nap@2", windowStart: "2026-09-13", windowEnd: "2026-09-13" },
    ])
    assertEquals(calls.filter((c) => c.url === KEYSET_URL).length, 1)
    // Second delivery: the keyset is served from the module cache.
    await google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: sig }), body, hookUrl)
    assertEquals(calls.filter((c) => c.url === KEYSET_URL).length, 1)
  })
})

Deno.test("parseWebhook fails closed: tampered body, wrong key, missing signature, missing/wrong Authorization", async () => {
  _googleTest.resetKeyset()
  const k = await makeKey(7), other = await makeKey(7)
  const body = JSON.stringify((await fixture("webhook_notification.json")).body)
  const sig = await sign(k, enc(body), "TINK", 2)
  await withFetch(await apiRoute(tinkKeyset([{ k, prefix: "TINK", encoding: 2 }])), async () => {
    const tampered = body.replace("hu-123", "hu-999")
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(tampered, { ...auth, [SIGNATURE_HEADER]: sig }), tampered, hookUrl)), Error, "signature invalid")
    const forged = await sign(other, enc(body), "TINK", 2)
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: forged }), body, hookUrl)), Error, "signature invalid")
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(body, auth), body, hookUrl)), Error, "signature missing")
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(body, { [SIGNATURE_HEADER]: sig }), body, hookUrl)), Error, "secret mismatch")
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(body, { Authorization: "Bearer nope", [SIGNATURE_HEADER]: sig }), body, hookUrl)), Error, "secret mismatch")
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: "not base64!!" }), body, hookUrl)), Error, "signature invalid")
  })
  // An unreachable keyset is also a rejection (→ 401 at the function layer), never an accept.
  _googleTest.resetKeyset()
  await withFetch(() => new Response("down", { status: 503 }), async () => {
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: sig }), body, hookUrl)), Error, "keyset 503")
  })
})

Deno.test("key rotation: an unknown key id forces one keyset refetch; RAW/P1363 and LEGACY envelopes verify too", async () => {
  _googleTest.resetKeyset()
  const old = await makeKey(1), fresh = await makeKey(2)
  const body = JSON.stringify((await fixture("webhook_notification.json")).body)
  let served = tinkKeyset([{ k: old, prefix: "TINK", encoding: 2 }])
  await withFetch((url) => url.toString() === KEYSET_URL ? jsonResp(served) : new Response("x", { status: 500 }), async (calls) => {
    await google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: await sign(old, enc(body), "TINK", 2) }), body, hookUrl)
    served = tinkKeyset([{ k: fresh, prefix: "TINK", encoding: 2 }, { k: old, prefix: "TINK", encoding: 2 }])
    // A forced refetch is rate-limited to once a minute (a bad signature must not become a keyset-fetch storm) — age the cache past it.
    const freshSig = await sign(fresh, enc(body), "TINK", 2)
    await assertRejects(() => Promise.resolve(google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: freshSig }), body, hookUrl)), Error, "signature invalid")
    assertEquals(calls.filter((c) => c.url === KEYSET_URL).length, 1)
    _googleTest.ageKeyset(2 * 60 * 1000)
    const ev = await google.parseWebhook(request(body, { ...auth, [SIGNATURE_HEADER]: freshSig }), body, hookUrl)
    assertEquals(ev.length, 2)
    assertEquals(calls.filter((c) => c.url === KEYSET_URL).length, 2)
  })
  const raw = await makeKey(9), legacy = await makeKey(11)
  const keys = await parseKeyset(tinkKeyset([{ k: raw, prefix: "RAW", encoding: 1 }, { k: legacy, prefix: "LEGACY", encoding: 2 }]))
  assertEquals(keys.map((k) => [k.keyId, k.prefix, k.encoding]), [[9, "RAW", "IEEE_P1363"], [11, "LEGACY", "DER"]])
  assertEquals(await verifySignature(enc(body), await sign(raw, enc(body), "RAW", 1), keys), true)
  assertEquals(await verifySignature(enc(body), await sign(legacy, enc(body), "LEGACY", 2), keys), true)
  assertEquals(await verifySignature(enc(body + " "), await sign(legacy, enc(body), "LEGACY", 2), keys), false)
  // Disabled / non-P-256 keys are ignored; DER round-trips.
  const ks = tinkKeyset([{ k: raw, prefix: "RAW", encoding: 1 }]); (ks.key[0] as Record<string, unknown>).status = "DISABLED"
  assertEquals((await parseKeyset(ks)).length, 0)
  const p1363 = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, raw.pair.privateKey, enc("x")))
  assertEquals(derToP1363(p1363ToDer(p1363)), p1363)
})

Deno.test("verification probes: authenticated + empty → 'challenge' (204); unauthenticated → throws (401)", async () => {
  const c = await google.parseWebhook(request("", auth), "", hookUrl)
  assertEquals(c, "challenge")
  assertEquals(google.challengeResponse!(hookUrl, "")?.status, 204)
  await assertRejects(() => Promise.resolve(google.parseWebhook(request("", {}), "", hookUrl)), Error, "secret mismatch")
  assertEquals(_googleTest.notificationsOf(JSON.stringify({ messages: [{ id: "m1", data: { healthUserId: "u", dataType: "steps" } }] })), [{ vendorUserId: "u", dataType: "steps", operation: "UPSERT", eventId: "m1", windowStart: undefined, windowEnd: undefined }])
})

Deno.test("revoke posts the refresh token to Google's revocation endpoint", async () => {
  await withFetch(() => new Response(null, { status: 200 }), async (calls) => {
    await google.revoke!(tokens, { patientId: "p", vendorUserId: "hu-123", meta: {} })
    assertEquals(calls[0].url, "https://oauth2.googleapis.com/revoke")
    assertStringIncludes(calls[0].body!, "token=rt-1")
  })
})
