// OpenAI pricing (ai-pricing.ts) and the MEAL_PRICING switch in meal-analysis.ts.
import { assert, assertEquals, assertAlmostEquals } from "jsr:@std/assert@1"
import { AI_MICRO_KEYS, parsePer100, priceFromPer100, priceItemsWithOpenAI } from "../ai-pricing.ts"

const per100 = (over: Record<string, unknown> = {}) => ({
  name_fr: "riz complet cuit",
  category: "cereal grains and pasta",
  energy_kcal: 123, protein_g: 2.7, carbs_g: 25.6, fat_g: 1, fiber_g: 1.6,
  sugar_g: 0.2, saturated_fat_g: 0.2, omega3_g: null, magnesium_mg: "43", iodine_mcg: -1,
  ...over,
})

Deno.test("an answer is read per 100 g, its category and French name kept, unknowns left null", () => {
  const p = parsePer100(JSON.stringify(per100()))
  assert(p && p !== "not_food")
  assertEquals(p.category, "Cereal Grains and Pasta")
  assertEquals(p.nameFr, "riz complet cuit")
  assertEquals(p.macros.energy_kcal, 123)
  assertEquals(p.micros.magnesium_mg, 43) // a numeric string is a number
  assertEquals(p.micros.omega3_g, null) // null stays "not measured"
  assertEquals(p.micros.iodine_mcg, null) // negative is not a measurement
  assertEquals(p.micros.zinc_mg, null) // missing is unknown, never 0
  assertEquals(Object.keys(p.micros).sort(), [...AI_MICRO_KEYS].sort())
})

Deno.test("an unusable answer is refused, so the food is priced another way", () => {
  assertEquals(parsePer100("not json"), null)
  assertEquals(parsePer100("[1,2]"), null)
  assertEquals(parsePer100(JSON.stringify(per100({ energy_kcal: null }))), null)
  assertEquals(parsePer100(JSON.stringify(per100({ energy_kcal: 1500 }))), null) // denser than fat
  assertEquals(parsePer100(JSON.stringify(per100({ protein_g: 60, carbs_g: 60 }))), null) // more than the food
  assertEquals(parsePer100(JSON.stringify(per100({ fat_g: -2 }))), null)
  assertEquals(parsePer100(JSON.stringify({ not_food: true })), "not_food")
  // A missing fibre is no fibre (water, oil); an unknown category is no category.
  const p = parsePer100(JSON.stringify(per100({ fiber_g: null, category: "Rice" })))
  assert(p && p !== "not_food")
  assertEquals(p.macros.fiber_g, 0)
  assertEquals(p.category, null)
})

Deno.test("a portion is scaled from 100 g at the resolver's rounding, as basis ai with no reference row", () => {
  const p = parsePer100(JSON.stringify(per100()))
  assert(p && p !== "not_food")
  const item = priceFromPer100("cooked brown rice", 147, p)
  assertEquals(item.estimated_grams, 150)
  assertAlmostEquals(item.kcal, 184.5)
  assertAlmostEquals(item.carbs_g, 38.4)
  assertEquals(item.micros.omega3_g, null)
  assertAlmostEquals(item.micros.magnesium_mg ?? 0, 64.5)
  assertEquals(item.basis, "ai")
  assertEquals(item.food_item_id, null)
  assertEquals(item.local_name, "riz complet cuit")
  assertEquals(priceFromPer100("salt", 3.04, p).estimated_grams, 3)
})

Deno.test("one call per distinct food, in order; a food that fails comes back null for the fallback", async () => {
  const bodies: Array<Record<string, unknown>> = []
  const fake = (async (_url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body))
    bodies.push(body)
    const food = body.messages[1].content as string
    if (food === "mystery") return new Response("upstream down", { status: 500 })
    const content = JSON.stringify(per100({ name_fr: food }))
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 })
  }) as typeof fetch
  const out = await priceItemsWithOpenAI(
    [{ name: "Olive oil", grams: 10 }, { name: "mystery", grams: 50 }, { name: "olive oil ", grams: 20 }],
    { apiKey: "sk", model: "gpt-5.4-mini", fetchImpl: fake },
  )
  assertEquals(bodies.length, 2) // "Olive oil" and "olive oil " are one food
  assertEquals(out.length, 3)
  assertEquals(out[0]?.name, "Olive oil")
  assertEquals(out[0]?.estimated_grams, 10)
  assertEquals(out[1], null)
  assertEquals(out[2]?.estimated_grams, 20)
  assertEquals(bodies[0].model, "gpt-5.4-mini")
  assertEquals(bodies[0].response_format, { type: "json_object" })
  assertEquals(bodies[0].reasoning_effort, "none")
  assertEquals("temperature" in bodies[0], false)
})

async function loadMealAnalysis(env: Record<string, string | undefined>, tag: string) {
  for (const k of ["MEAL_AI_PROVIDER", "MEAL_PRICING", "OPENAI_API_KEY", "OPENAI_PRICING_MODEL", "OPENAI_MEAL_MODEL"]) {
    const v = env[k]
    if (v === undefined) Deno.env.delete(k)
    else Deno.env.set(k, v)
  }
  return await import(`../meal-analysis.ts?pricing=${tag}`)
}

Deno.test("MEAL_PRICING: unset follows the identification provider; explicit wins; no key means the database", async () => {
  assertEquals((await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk" }, "follow")).PRICING_SOURCE, "openai")
  assertEquals((await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk", MEAL_PRICING: "database" }, "db")).PRICING_SOURCE, "database")
  assertEquals((await loadMealAnalysis({ OPENAI_API_KEY: "sk" }, "infomaniak")).PRICING_SOURCE, "database")
  assertEquals((await loadMealAnalysis({ OPENAI_API_KEY: "sk", MEAL_PRICING: "OpenAI" }, "explicit")).PRICING_SOURCE, "openai")
  assertEquals((await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", MEAL_PRICING: "openai" }, "nokey")).PRICING_SOURCE, "database")
})

Deno.test("priceMeal on OpenAI: every food priced, totals and scores from those numbers, the source recorded", async () => {
  const mod = await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk" }, "price")
  const realFetch = globalThis.fetch
  globalThis.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
    const food = JSON.parse(String(init?.body)).messages[1].content as string
    const content = JSON.stringify(per100({ name_fr: food }))
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 })
  }) as typeof fetch
  try {
    const db = {} // never touched: nothing falls back
    const priced = await mod.priceMeal(db, [
      { name: "cooked brown rice", estimated_grams: 200, flags: ["whole_grain"] },
      { name: "cooked brown rice", estimated_grams: 100, flags: [] },
    ])
    assertEquals(priced.items.map((i: { basis: string }) => i.basis), ["ai", "ai"])
    assertEquals(priced.items[0].flags, ["whole_grain"])
    assertEquals(priced.totals.kcal, 369) // 1.23 × 300 g
    assertEquals(priced.pricing.source, "openai")
    assertEquals(priced.pricing.fallback, 0)
    assertEquals(priced.pricing.model, "gpt-5.4-mini")
    assert(typeof priced.scores.glycemic === "number")
    const meta = mod.completionPatch(
      { dish_name: "Rice", items: [], model: "gpt-5.4-mini", confidence: 0.9, duplicates_dropped: 0, elapsed_ms: 2000 },
      priced, 1, null,
    ).resolution_meta
    assertEquals(meta.basis, { ai: 2 })
    assertEquals(meta.pricing.source, "openai")
  } finally {
    globalThis.fetch = realFetch
  }
})
