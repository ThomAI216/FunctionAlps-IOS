// The provider switch in meal-analysis.ts: which upstream a photo goes to, with which body.
// The module reads its env at load, so each case imports a fresh instance (distinct query string).
import { assert, assertEquals } from "jsr:@std/assert@1"

type Captured = { url: string; auth: string; body: Record<string, unknown> }

async function identifyWith(env: Record<string, string | undefined>, tag: string) {
  const keys = ["MEAL_AI_PROVIDER", "OPENAI_API_KEY", "INFOMANIAK_AI_API_KEY", "OPENAI_MEAL_MODEL"]
  for (const k of keys) {
    const v = env[k]
    if (v === undefined) Deno.env.delete(k)
    else Deno.env.set(k, v)
  }
  const mod = await import(`../meal-analysis.ts?case=${tag}`)
  const calls: Captured[] = []
  const realFetch = globalThis.fetch
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(input),
      auth: new Headers(init?.headers).get("Authorization") ?? "",
      body: JSON.parse(String(init?.body)),
    })
    const content = JSON.stringify({ dish_name: "Toast", items: [{ name: "toasted bread", estimated_grams: 60, flags: [] }], confidence: 0.9, coverage: "full" })
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 })
  }) as typeof fetch
  try {
    const result = await mod.identifyMeal({ imageBase64: "AAAA" })
    return { mod, calls, result }
  } finally {
    globalThis.fetch = realFetch
  }
}

Deno.test("default is Infomaniak, the shipped body unchanged", async () => {
  const { mod, calls, result } = await identifyWith({ INFOMANIAK_AI_API_KEY: "ik", OPENAI_API_KEY: "sk" }, "default")
  assertEquals(mod.IDENTIFY_PROVIDER, "infomaniak")
  assertEquals(calls.length, 1)
  assert(calls[0].url.startsWith("https://api.infomaniak.com/2/ai/"))
  assertEquals(calls[0].auth, "Bearer ik")
  assertEquals(calls[0].body.model, "google/gemma-4-31B-it")
  assertEquals(calls[0].body.temperature, 0.2)
  assertEquals(result.ok, true)
})

Deno.test("an OpenAI key alone does not move meals to OpenAI", async () => {
  const { mod, calls } = await identifyWith({ INFOMANIAK_AI_API_KEY: "ik", OPENAI_API_KEY: "sk", MEAL_AI_PROVIDER: "" }, "keyonly")
  assertEquals(mod.IDENTIFY_PROVIDER, "infomaniak")
  assert(calls[0].url.includes("infomaniak"))
})

Deno.test("MEAL_AI_PROVIDER=openai sends the photo to OpenAI with a JSON-object body", async () => {
  const { mod, calls, result } = await identifyWith({ MEAL_AI_PROVIDER: "OpenAI", OPENAI_API_KEY: "sk", INFOMANIAK_AI_API_KEY: "ik" }, "openai")
  assertEquals(mod.IDENTIFY_PROVIDER, "openai")
  assertEquals(mod.IDENTIFY_CONFIGURED, true)
  assertEquals(calls.length, 1)
  assertEquals(calls[0].url, "https://api.openai.com/v1/chat/completions")
  assertEquals(calls[0].auth, "Bearer sk")
  assertEquals(calls[0].body.model, "gpt-5.4-mini")
  assertEquals(calls[0].body.response_format, { type: "json_object" })
  assertEquals("temperature" in calls[0].body, false)
  const user = (calls[0].body.messages as { role: string; content: unknown }[])[1]
  assert(JSON.stringify(user.content).includes("data:image/jpeg;base64,AAAA"))
  assertEquals(result.ok, true)
  if (result.ok) assertEquals(result.model, "gpt-5.4-mini")
})

Deno.test("OpenAI selected without its key refuses instead of falling back", async () => {
  const { mod } = await identifyWith({ MEAL_AI_PROVIDER: "openai", INFOMANIAK_AI_API_KEY: "ik" }, "nokey")
  assertEquals(mod.IDENTIFY_CONFIGURED, false)
  assert(String(mod.IDENTIFY_NOT_CONFIGURED).startsWith("OPENAI_API_KEY"))
})
