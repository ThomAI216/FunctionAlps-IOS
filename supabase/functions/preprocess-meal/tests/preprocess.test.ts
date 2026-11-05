// preprocess-meal on Qwen 3.8: what is sent to Infomaniak, and what is read back.
// The module reads its env at load, so each case imports a fresh instance (distinct query string).
import { assert, assertEquals } from "jsr:@std/assert@1"

type Captured = { url: string; body: Record<string, unknown> }

const ANSWER = { language: "fr", cleaned_transcript: "saumon et riz", items: [{ name: "saumon", quantity: "", estimated_g: 120, volume_measure: "", confidence: "high" }], clarifications: [] }

async function run(env: Record<string, string | undefined>, tag: string, message: Record<string, unknown>) {
  for (const k of ["INFOMANIAK_AI_API_KEY", "INFOMANIAK_TEXT_MODEL", "SOVEREIGN_CHAT_MODEL", "INFOMANIAK_PRODUCT_ID", "INFOMANIAK_AI_PRODUCT_ID"]) {
    const v = env[k]
    if (v === undefined) Deno.env.delete(k)
    else Deno.env.set(k, v)
  }
  const mod = await import(`../preprocess.ts?case=${tag}`)
  const calls: Captured[] = []
  const realFetch = globalThis.fetch
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), body: JSON.parse(String(init?.body)) })
    return new Response(JSON.stringify({ choices: [{ message }] }), { status: 200 })
  }) as typeof fetch
  try {
    const result = await mod.preprocessTranscript({ transcript: "euh du saumon et du riz", mealType: "dinner", locale: "fr" })
    return { calls, result }
  } finally {
    globalThis.fetch = realFetch
  }
}

Deno.test("defaults to Qwen 3.8 by its full id, thinking off, one JSON object", async () => {
  const { calls, result } = await run({ INFOMANIAK_AI_API_KEY: "ik" }, "default", { content: JSON.stringify(ANSWER) })
  assertEquals(calls.length, 1)
  assert(calls[0].url.startsWith("https://api.infomaniak.com/2/ai/108797/openai/v1/"))
  assertEquals(calls[0].body.model, "Qwen/Qwen3.8-27B-FP8")
  assertEquals(calls[0].body.reasoning_effort, "none")
  assertEquals(calls[0].body.stream, false)
  assertEquals(calls[0].body.response_format, { type: "json_object" })
  assertEquals(result.status, 200)
  assertEquals((result.body.items as unknown[]).length, 1)
})

Deno.test("SOVEREIGN_CHAT_MODEL picks the model; the old INFOMANIAK_TEXT_MODEL secret no longer does", async () => {
  const left = await run({ INFOMANIAK_AI_API_KEY: "ik", INFOMANIAK_TEXT_MODEL: "mistralai/Mistral-Small-4-119B-2603" }, "legacy", { content: JSON.stringify(ANSWER) })
  assertEquals(left.calls[0].body.model, "Qwen/Qwen3.8-27B-FP8")
  const set = await run({ INFOMANIAK_AI_API_KEY: "ik", SOVEREIGN_CHAT_MODEL: "some/other-model" }, "override", { content: JSON.stringify(ANSWER) })
  assertEquals(set.calls[0].body.model, "some/other-model")
})

Deno.test("an answer Qwen put in `reasoning` instead of `content` is still read", async () => {
  const { result } = await run({ INFOMANIAK_AI_API_KEY: "ik" }, "reasoning", { content: "", reasoning: `Here it is: ${JSON.stringify(ANSWER)}` })
  assertEquals(result.status, 200)
  assertEquals(result.body.language, "fr")
  assertEquals((result.body.items as { name: string }[])[0].name, "saumon")
})

Deno.test("both product-id secret names are accepted", async () => {
  const { calls } = await run({ INFOMANIAK_AI_API_KEY: "ik", INFOMANIAK_AI_PRODUCT_ID: "4242" }, "pid", { content: JSON.stringify(ANSWER) })
  assert(calls[0].url.startsWith("https://api.infomaniak.com/2/ai/4242/"))
})

Deno.test("a fenced answer is unwrapped", async () => {
  const { result } = await run({ INFOMANIAK_AI_API_KEY: "ik" }, "fenced", { content: "```json\n" + JSON.stringify(ANSWER) + "\n```" })
  assertEquals(result.status, 200)
  assertEquals(result.body.cleanedTranscript, "saumon et riz")
})
