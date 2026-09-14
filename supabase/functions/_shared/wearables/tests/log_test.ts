import { assert, assertEquals } from "jsr:@std/assert@1"
import { _logTest, errorSummary, hashId } from "../log.ts"

Deno.test("secrets, tokens, codes, bodies and health values never reach a log line", () => {
  const out = _logTest.scrub({
    fn: "x", vendor: "oura", access_token: "AAA", refreshToken: "BBB", client_secret: "CCC", code: "DDD", authorization: "Bearer x",
    body: "{}", payload: {}, value: 61.5, code_verifier: "EEE", signature: "FFF", email: "a@b.c", nested: { token: "GGG", ms: 12 }, ms: 3,
    long: "x".repeat(400),
  })
  assertEquals(Object.keys(out).sort(), ["fn", "long", "ms", "nested", "vendor"])
  assertEquals(out.nested, { ms: 12 })
  assert((out.long as string).length < 320)
})

Deno.test("patient ids are hashed short and stable", async () => {
  const a = await hashId("patient-1"), b = await hashId("patient-1"), c = await hashId("patient-2")
  assertEquals(a, b); assert(a !== c); assertEquals(a!.length, 12); assertEquals(await hashId(null), null)
})

Deno.test("error summaries carry the class and a bounded message", () => {
  const s = errorSummary(new TypeError("fetch failed: " + "y".repeat(500)))
  assertEquals(s.errorClass, "TypeError"); assert(s.message.length <= 200)
})
