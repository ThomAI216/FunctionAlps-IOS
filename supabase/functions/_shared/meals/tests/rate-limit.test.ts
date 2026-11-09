// A rate-limited upstream (HTTP 429) is not a bad roll of the dice — it is the same answer eight times
// in a row. From 2026-11-08 Infomaniak's vision model answered 429 to every photo for 36 hours; each
// meal spent its whole budget in ~111 minutes and parked at needs_input. Two defences, both tested here:
//   1. a second SOVEREIGN model takes the photo when the first is rate-limited (still Infomaniak);
//   2. when both are rate-limited the attempt is handed back and the retry waits ≥15 min (Retry-After
//      honoured), for up to six hours, before the member is asked.
import { assert, assertEquals } from "jsr:@std/assert@1"

type Call = { model: string; messages: unknown }

const OK_CONTENT = JSON.stringify({
  dish_name: "Toast",
  items: [{ name: "toasted bread", estimated_grams: 60, flags: [] }],
  confidence: 0.9,
  coverage: "full",
})

async function identifyWith(
  env: Record<string, string | undefined>,
  tag: string,
  answer: (model: string) => Response,
  input: Record<string, unknown> = { imageBase64: "AAAA" },
) {
  const keys = ["MEAL_AI_PROVIDER", "OPENAI_API_KEY", "INFOMANIAK_AI_API_KEY", "SOVEREIGN_VISION_FALLBACK_MODEL", "SOVEREIGN_TEXT_FALLBACK_MODEL"]
  for (const k of keys) {
    const v = env[k]
    if (v === undefined) Deno.env.delete(k)
    else Deno.env.set(k, v)
  }
  const mod = await import(`../meal-analysis.ts?rl=${tag}`)
  const calls: Call[] = []
  const realFetch = globalThis.fetch
  globalThis.fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as { model: string; messages: unknown }
    calls.push({ model: body.model, messages: body.messages })
    return answer(body.model)
  }) as typeof fetch
  try {
    const result = await mod.identifyMeal(input)
    return { mod, calls, result }
  } finally {
    globalThis.fetch = realFetch
  }
}

const ok = () => new Response(JSON.stringify({ choices: [{ message: { content: OK_CONTENT } }] }), { status: 200 })
const tooMany = (retryAfter?: string) =>
  new Response(JSON.stringify({ error: "rate limited" }), {
    status: 429,
    headers: retryAfter ? { "retry-after": retryAfter } : undefined,
  })

const IK = { INFOMANIAK_AI_API_KEY: "ik" }

Deno.test("a 429 from the vision model sends the photo to the second sovereign model", async () => {
  const { calls, result } = await identifyWith(IK, "fallback", (model) =>
    model === "google/gemma-4-31B-it" ? tooMany() : ok())
  assertEquals(calls.length, 2)
  assertEquals(calls[0].model, "google/gemma-4-31B-it")
  assertEquals(calls[1].model, "Qwen/Qwen3.8-27B-FP8")
  // Same prompt, same image — only the model name changes.
  assertEquals(calls[1].messages, calls[0].messages)
  assert(result.ok)
  assertEquals(result.model, "Qwen/Qwen3.8-27B-FP8")
  assertEquals(result.items.length, 1)
})

Deno.test("a text meal rate-limited on the chat model falls back to the vision model", async () => {
  const { calls, result } = await identifyWith(IK, "textfallback", (model) =>
    model === "Qwen/Qwen3.8-27B-FP8" ? tooMany() : ok(), { description: "two eggs and toast" })
  assertEquals(calls.map((c) => c.model), ["Qwen/Qwen3.8-27B-FP8", "google/gemma-4-31B-it"])
  assert(result.ok)
  assertEquals(result.model, "google/gemma-4-31B-it")
})

Deno.test("both sovereign models rate-limited: retryable, flagged, Retry-After carried, both named", async () => {
  const { calls, result } = await identifyWith(IK, "both", () => tooMany("120"))
  assertEquals(calls.length, 2)
  assertEquals(result.ok, false)
  assertEquals(result.permanent, false)
  assertEquals(result.rateLimited, true)
  assertEquals(result.retryAfterS, 120)
  assert(result.technical.includes("429"), result.technical)
  assert(result.technical.includes("Qwen/Qwen3.8-27B-FP8"), result.technical)
  assert(result.technical.length <= 200)
})

Deno.test("a 5xx also earns the fallback; a 4xx that is not 429 does not", async () => {
  const five = await identifyWith(IK, "fivexx", (model) =>
    model === "google/gemma-4-31B-it" ? new Response("boom", { status: 503 }) : ok())
  assertEquals(five.calls.length, 2)
  assert(five.result.ok)

  const four = await identifyWith(IK, "fourxx", () => new Response("bad request", { status: 400 }))
  assertEquals(four.calls.length, 1)
  assertEquals(four.result.ok, false)
  assertEquals(four.result.permanent, true)
  assertEquals(four.result.rateLimited, false)
})

Deno.test("SOVEREIGN_VISION_FALLBACK_MODEL='' switches the fallback off", async () => {
  const { calls, result } = await identifyWith({ ...IK, SOVEREIGN_VISION_FALLBACK_MODEL: "" }, "off", () => tooMany())
  assertEquals(calls.length, 1)
  assertEquals(result.ok, false)
  assertEquals(result.rateLimited, true)
  assertEquals(result.retryAfterS, null)
})

Deno.test("the fallback is never OpenAI: MEAL_AI_PROVIDER=openai gets one provider and no second model", async () => {
  const { calls, result } = await identifyWith(
    { MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk", INFOMANIAK_AI_API_KEY: "ik" },
    "openai",
    () => tooMany(),
  )
  assertEquals(calls.length, 1)
  assertEquals(result.ok, false)
  assertEquals(result.rateLimited, true)
})

// ── the retry schedule ──────────────────────────────────────────────────────

Deno.test("a rate-limited failure keeps the meal queued, hands the attempt back and waits at least 15 minutes", async () => {
  const mod = await import("../meal-analysis.ts?rl=patch")
  const now = new Date("2026-11-09T18:00:00Z")
  const loggedAt = "2026-11-09T17:00:00Z"
  const patch = mod.retryLaterPatch("vision model returned HTTP 429", 3, "IDENTIFY_FAILED", { rateLimited: true, now, loggedAt })
  assertEquals(patch.analysis_status, "queued")
  assertEquals(patch.analysis_attempts, 2)
  assertEquals(patch.analysis_next_retry_at, new Date(now.getTime() + mod.RATE_LIMIT_RETRY_S * 1000).toISOString())
  assertEquals(mod.RATE_LIMIT_RETRY_S, 900)
})

Deno.test("Retry-After longer than the floor wins", async () => {
  const mod = await import("../meal-analysis.ts?rl=patch")
  const now = new Date("2026-11-09T18:00:00Z")
  const patch = mod.retryLaterPatch("x", 1, "IDENTIFY_FAILED", { rateLimited: true, retryAfterS: 3600, now, loggedAt: now.toISOString() })
  assertEquals(patch.analysis_next_retry_at, new Date(now.getTime() + 3600_000).toISOString())
  assertEquals(patch.analysis_attempts, 0)
})

Deno.test("the attempt handed back never goes below zero", async () => {
  const mod = await import("../meal-analysis.ts?rl=patch")
  const now = new Date()
  const patch = mod.retryLaterPatch("x", 0, "IDENTIFY_FAILED", { rateLimited: true, now, loggedAt: now.toISOString() })
  assertEquals(patch.analysis_attempts, 0)
})

Deno.test("after six hours of rate limiting the member is asked", async () => {
  const mod = await import("../meal-analysis.ts?rl=patch")
  const now = new Date("2026-11-09T18:00:00Z")
  const patch = mod.retryLaterPatch("x", 2, "IDENTIFY_FAILED", { rateLimited: true, now, loggedAt: "2026-11-09T11:30:00Z" })
  assertEquals(patch.analysis_status, "needs_input")
  assertEquals(patch.analysis_next_retry_at, null)
  assertEquals("analysis_attempts" in patch, false)
  assertEquals(mod.RATE_LIMIT_MAX_WAIT_MS, 6 * 3600_000)
})

Deno.test("a row whose logged_at is unknown is not waited on forever: the attempt budget applies", async () => {
  const mod = await import("../meal-analysis.ts?rl=patch")
  const now = new Date()
  const patch = mod.retryLaterPatch("x", mod.MAX_ATTEMPTS, "IDENTIFY_FAILED", { rateLimited: true, now })
  assertEquals(patch.analysis_status, "needs_input")
})

Deno.test("an ordinary failure still spends its attempt on the usual backoff", async () => {
  const mod = await import("../meal-analysis.ts?rl=patch")
  const now = new Date("2026-11-09T18:00:00Z")
  const patch = mod.retryLaterPatch("UPSTREAM_TIMEOUT", 3, "IDENTIFY_FAILED", { now, loggedAt: now.toISOString() })
  assertEquals(patch.analysis_status, "queued")
  assertEquals("analysis_attempts" in patch, false)
  assertEquals(patch.analysis_next_retry_at, new Date(now.getTime() + mod.backoffSeconds(3) * 1000).toISOString())
})

Deno.test("failurePatch carries the identify failure's rate-limit facts through", async () => {
  const mod = await import("../meal-analysis.ts?rl=patch")
  const now = new Date("2026-11-09T18:00:00Z")
  const ident = {
    ok: false as const,
    response: { status: 502, body: {} },
    technical: "UPSTREAM_HTTP: vision model returned HTTP 429",
    permanent: false,
    rateLimited: true,
    retryAfterS: 2000,
    elapsed_ms: 300,
  }
  const patch = mod.failurePatch(ident, 5, now, "2026-11-09T17:50:00Z")
  assertEquals(patch.analysis_status, "queued")
  assertEquals(patch.analysis_attempts, 4)
  assertEquals(patch.analysis_next_retry_at, new Date(now.getTime() + 2000_000).toISOString())
})
