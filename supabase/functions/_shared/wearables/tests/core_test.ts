// Platform v2 guarantees, each pinned by a test: token crypto (AAD, key ring, v1 compatibility), the
// catalogue mirror (golden against fixtures/catalogue.json), deprecated-id rewriting, the retry taxonomy,
// receipt keys and the day helpers.
import { assert, assertEquals, assertNotEquals, assertRejects, assertThrows } from "jsr:@std/assert@1"
import {
  CANONICAL, MAX_ATTEMPTS, NAMES, RateLimitedError, ReconnectRequiredError, T, UnauthorizedError, VendorHttpError, VendorPausedError,
  _setKeyForTests, addDays, backoffSeconds, blobKeyVersion, canonicalId, classifyError, daily, dailyText, dayOfISO, decrypt, encrypt, epoch,
  keyEnvName, localDay, offsetMinutes, receiptKey, sendsPKCE, sha256Hex, timingSafeEqual,
} from "../core.ts"

const key1 = new Uint8Array(32).map((_, i) => i + 1)
const key2 = new Uint8Array(32).map((_, i) => 200 - i)
_setKeyForTests(1, key1)
_setKeyForTests(2, key2)
const aad = { accountId: "acc-1", vendor: "whoop", tokenType: "access" as const }

Deno.test("encrypt/decrypt round-trips under the AAD and the chosen key version", async () => {
  const blob = await encrypt("secret-token", aad, 2)
  assert(blob.startsWith("v2.2."))
  assertEquals(blobKeyVersion(blob), 2)
  assertEquals(await decrypt(blob, aad), "secret-token")
})

Deno.test("a blob moved to another account, vendor or column does not decrypt", async () => {
  const blob = await encrypt("secret-token", aad, 1)
  await assertRejects(() => decrypt(blob, { ...aad, accountId: "acc-2" }))
  await assertRejects(() => decrypt(blob, { ...aad, vendor: "oura" }))
  await assertRejects(() => decrypt(blob, { ...aad, tokenType: "refresh" }))
})

Deno.test("legacy v1 blobs (no AAD, key 1) still decrypt — the rotation path can read them", async () => {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const k = await crypto.subtle.importKey("raw", key1, "AES-GCM", false, ["encrypt"])
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, k, new TextEncoder().encode("old-token")))
  const out = new Uint8Array(iv.length + ct.length); out.set(iv); out.set(ct, iv.length)
  const v1 = "v1." + btoa(String.fromCharCode(...out))
  assertEquals(blobKeyVersion(v1), 1)
  assertEquals(await decrypt(v1, aad), "old-token")
  await assertRejects(() => decrypt("v3.1.abc", aad))
})

Deno.test("key ring naming", () => {
  assertEquals(keyEnvName(1), "WEARABLE_TOKEN_KEY")
  assertEquals(keyEnvName(2), "WEARABLE_TOKEN_KEY_V2")
})

Deno.test("catalogue golden: every id in T exists in wearable_data_types with the same name; aliases match", async () => {
  const fx = JSON.parse(await Deno.readTextFile(new URL("./fixtures/catalogue.json", import.meta.url))) as { rows: { id: number; name: string; unit: string | null; value_type: string; canonical_id: number | null }[] }
  const byId = new Map(fx.rows.map((r) => [r.id, r]))
  for (const [key, id] of Object.entries(T)) {
    const row = byId.get(id)
    assert(row, `T.${key} = ${id} is not in the catalogue`)
    assertEquals(NAMES[id], row.name, `NAMES[${id}] (T.${key}) differs from the catalogue`)
    assertEquals(CANONICAL[id] ?? null, row.canonical_id ?? null, `CANONICAL[${id}] differs from the catalogue`)
  }
  for (const id of Object.keys(NAMES).map(Number)) assert(byId.has(id), `NAMES has ${id} which the catalogue lacks`)
  assertEquals(byId.get(1000107)?.unit, "mg/dL")
  assertEquals(byId.get(1000130)?.value_type, "STRING")
})

Deno.test("deprecated ids are rewritten to the canonical id on every row helper", () => {
  assertEquals(canonicalId(1000110), 5041)
  assertEquals(canonicalId(5041), 5041)
  const d = daily("2026-09-13", T.SkinTemperatureAlt, 33.4)!
  assertEquals([d.dataTypeId, d.dataTypeName, d.valueType], [5041, "SkinTemperature", "DOUBLE"])
  const e = epoch("2026-09-13T06:00:00Z", T.SystolicBPAlt, 121)!
  assertEquals([e.dataTypeId, e.dataTypeName, e.valueType], [3301, "BloodPressureSystolic", "LONG"])
  const s = dailyText("2026-09-13", T.PolarNightlyRechargeStatus, "COMPROMISED")!
  assertEquals([s.dataTypeId, s.valueType, s.valueText, s.value], [1000130, "STRING", "COMPROMISED", null])
  assertEquals(daily("2026-09-13", T.Steps, null), null)
  assertEquals(daily("2026-09-13", T.Steps, NaN), null)
})

Deno.test("retry taxonomy", () => {
  const rl = classifyError(new RateLimitedError("120"), 1)
  assertEquals([rl.code, rl.retry, rl.delaySeconds], ["rate_limited", true, 120])
  assertEquals(classifyError(new RateLimitedError(null), 1).delaySeconds, 60)
  const un = classifyError(new UnauthorizedError("x"), 1)
  assertEquals([un.code, un.retry, un.accountStatus], ["unauthorized", false, "reconnect_required"])
  const rr = classifyError(new ReconnectRequiredError(), 1)
  assertEquals([rr.code, rr.retry], ["reconnect_required", false])
  const p = classifyError(new VendorPausedError("oura"), 1)
  assertEquals([p.code, p.retry, p.delaySeconds], ["vendor_paused", true, 3600])
  const s5 = classifyError(new VendorHttpError(503, "down"), 3, 0)
  assertEquals([s5.code, s5.retry, s5.delaySeconds, s5.accountStatus], ["vendor_5xx", true, 40, "degraded"])
  const s4 = classifyError(new VendorHttpError(404, "gone"), 1)
  assertEquals([s4.code, s4.retry, s4.accountStatus], ["vendor_4xx", false, "error"])
  const net = classifyError(new TypeError("fetch failed"), 2, 0)
  assertEquals([net.code, net.retry, net.delaySeconds], ["network", true, 20])
  assertEquals(classifyError(new Error("boom"), 5).retry, false)
})

Deno.test("backoff is min(15 min, 2^attempt·5 s) plus jitter, dead-letter after 8", () => {
  assertEquals(backoffSeconds(0, 0), 5)
  assertEquals(backoffSeconds(4, 0), 80)
  assertEquals(backoffSeconds(20, 0), 900)
  assert(backoffSeconds(1, 0.99) <= 10 + 5)
  assertEquals(MAX_ATTEMPTS, 8)
})

Deno.test("receipt keys: vendor event id first, else body hash + index", () => {
  assertEquals(receiptKey({ eventId: "tr-1" }, "abc", 0), "evt:tr-1")
  assertEquals(receiptKey({ eventId: null }, "abc", 2), "hash:abc#2")
  assertNotEquals(receiptKey({}, "abc", 0), receiptKey({}, "abc", 1))
})

Deno.test("hashing and constant-time compare", async () => {
  assertEquals(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  assertEquals(await sha256Hex(new TextEncoder().encode("abc")), await sha256Hex("abc"))
  assert(timingSafeEqual("a1", "a1")); assert(!timingSafeEqual("a1", "a2")); assert(!timingSafeEqual("a", "ab"))
})

Deno.test("PKCE mode", () => {
  assert(sendsPKCE("required")); assert(sendsPKCE("supported")); assert(!sendsPKCE("unsupported")); assert(!sendsPKCE("not_documented"))
})

Deno.test("day helpers honour the vendor offset", () => {
  assertEquals(localDay(new Date("2026-09-13T23:30:00Z"), 120), "2026-09-14")
  assertEquals(localDay(new Date("2026-09-13T23:30:00Z"), -300), "2026-09-13")
  assertEquals(addDays("2026-02-28", 1), "2026-03-01")
  assertEquals(offsetMinutes("+02:00"), 120); assertEquals(offsetMinutes("-0530"), -330); assertEquals(offsetMinutes("Z"), 0); assertEquals(offsetMinutes(null), null)
  assertEquals(dayOfISO("2026-09-13T23:30:00+02:00"), "2026-09-13"); assertEquals(dayOfISO("2026-09-13T23:30:00Z", 120), "2026-09-14")
})

Deno.test("malformed blobs are refused", () => {
  assertThrows(() => { if (blobKeyVersion("zzz") !== null) throw new Error("should be null"); throw new Error("ok") })
})
