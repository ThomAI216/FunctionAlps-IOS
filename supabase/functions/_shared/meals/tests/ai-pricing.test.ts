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
  // Dense foods are honest: USDA carbohydrate already contains the fibre, so chia seeds pass.
  const chia = parsePer100(JSON.stringify(per100({ energy_kcal: 486, protein_g: 16.5, carbs_g: 42.1, fat_g: 30.7, fiber_g: 34.4 })))
  assert(chia && chia !== "not_food")
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
  for (const k of ["MEAL_AI_PROVIDER", "MEAL_PRICING", "OPENAI_API_KEY", "OPENAI_PRICING_MODEL", "OPENAI_MEAL_MODEL", "INFOMANIAK_AI_API_KEY", "SOVEREIGN_PRICING_MODEL"]) {
    const v = env[k]
    if (v === undefined) Deno.env.delete(k)
    else Deno.env.set(k, v)
  }
  return await import(`../meal-analysis.ts?pricing=${tag}`)
}

Deno.test("MEAL_PRICING: sovereign by default, even with OpenAI identification; OpenAI only when asked by name", async () => {
  // Thomas, 2026-11-10: pricing is sovereign. It no longer follows MEAL_AI_PROVIDER.
  assertEquals((await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk", INFOMANIAK_AI_API_KEY: "ik" }, "follow")).PRICING_SOURCE, "sovereign")
  assertEquals((await loadMealAnalysis({ INFOMANIAK_AI_API_KEY: "ik" }, "plain")).PRICING_SOURCE, "sovereign")
  assertEquals((await loadMealAnalysis({ MEAL_PRICING: "database", INFOMANIAK_AI_API_KEY: "ik" }, "db")).PRICING_SOURCE, "database")
  assertEquals((await loadMealAnalysis({ OPENAI_API_KEY: "sk", MEAL_PRICING: "OpenAI", INFOMANIAK_AI_API_KEY: "ik" }, "explicit")).PRICING_SOURCE, "openai")
  assertEquals((await loadMealAnalysis({ MEAL_PRICING: "openai", INFOMANIAK_AI_API_KEY: "ik" }, "nokey")).PRICING_SOURCE, "sovereign")
  assertEquals((await loadMealAnalysis({ OPENAI_API_KEY: "sk" }, "noik")).PRICING_SOURCE, "database")
})

Deno.test("priceMeal, sovereign: the table and Infomaniak price the meal; the model's own list is kept in resolution_meta", async () => {
  const mod = await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk", INFOMANIAK_AI_API_KEY: "ik" }, "sovereign-meal")
  const realFetch = globalThis.fetch
  const urls: string[] = []
  globalThis.fetch = (async (url: string | URL | Request) => {
    urls.push(String(url))
    const content = JSON.stringify({ foods: [{ i: 1, ref: "Rice, brown, cooked", parts: null, kcal: 123 }] })
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 })
  }) as typeof fetch
  try {
    const rice = { id: "rice", name: "Rice, brown, long-grain, cooked", name_fr: "Riz complet, cuit", category: "Cereal Grains and Pasta", energy_kcal: 123, protein_g: 2.7, carbs_g: 25.6, fat_g: 1, fiber_g: 1.6, magnesium_mg: 39 }
    const db = {
      rpc: (_fn: string, args: { q_terms: string[] }) =>
        Promise.resolve({ data: args.q_terms.map((t) => ({ term: t, id: "rice", name: rice.name, energy_kcal: 123, sim: 0.8 })), error: null }),
      from: (_table: string) => ({ select: () => ({ in: () => Promise.resolve({ data: [rice], error: null }) }) }),
    }
    const priced = await mod.priceMeal(db, [{ name: "cooked brown rice", estimated_grams: 200, flags: ["whole_grain"] }])
    assert(urls.length > 0 && urls.every((u) => u.startsWith("https://api.infomaniak.com/")))
    assertEquals(priced.items[0].basis, "matched")
    assertEquals(priced.items[0].food_item_id, "rice")
    assertEquals(priced.items[0].name, "cooked brown rice")
    assertEquals(priced.totals.kcal, 246)
    assertEquals(Math.round(priced.micros.magnesium_mg), 78)
    assertEquals(priced.pricing.source, "sovereign")
    assertEquals(priced.pricing.model, "Qwen/Qwen3.8-27B-FP8")
    assertEquals(priced.pricing.counts, { matched: 1, decomposed: 0, ai: 0, unpriced: 0 })
    const meta = mod.completionPatch(
      { dish_name: "Rice", items: [{ name: "cooked brown rice", estimated_grams: 200, flags: [] }], model: "gpt-5.4-mini", confidence: 0.9, duplicates_dropped: 0, elapsed_ms: 2000 },
      priced, 1, null,
    ).resolution_meta
    assertEquals(meta.identified, [{ name: "cooked brown rice", grams: 200 }])
  } finally {
    globalThis.fetch = realFetch
  }
})

Deno.test("priceMeal on OpenAI: every food priced, totals and scores from those numbers, the source recorded", async () => {
  const mod = await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk", MEAL_PRICING: "openai" }, "price")
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

/** A Supabase-shaped fake: every builder call chains, awaiting it answers from `answer(table, filters, op)`. */
function fakeDb(answer: (table: string, filters: Record<string, unknown>, op: string) => unknown) {
  return {
    from(table: string) {
      const filters: Record<string, unknown> = {}
      let op = "select"
      const chain: Record<string, unknown> = {
        select: () => chain,
        update: () => {
          op = "update"
          return chain
        },
        eq: (k: string, v: unknown) => {
          filters[k] = v
          return chain
        },
        in: (k: string, v: unknown) => {
          filters[k] = v
          return chain
        },
        maybeSingle: () => {
          op = op === "select" ? "single" : op
          return chain
        },
        then: (ok: (v: unknown) => unknown, ko: (e: unknown) => unknown) =>
          Promise.resolve({ data: answer(table, filters, op), error: null }).then(ok, ko),
      }
      return chain
    },
  }
}

Deno.test("a food the member corrected, and a placeholder, are the resolver's — never sent to OpenAI", async () => {
  const mod = await loadMealAnalysis({ MEAL_AI_PROVIDER: "openai", OPENAI_API_KEY: "sk", MEAL_PRICING: "openai" }, "pinned")
  const asked: string[] = []
  const realFetch = globalThis.fetch
  const g = globalThis as unknown as { Supabase?: unknown }
  const realSupabase = g.Supabase
  g.Supabase = { ai: { Session: class { run() { throw new Error("no embedding expected") } } } }
  globalThis.fetch = (async (_url: string | URL | Request, init?: RequestInit) => {
    const food = JSON.parse(String(init?.body)).messages[1].content as string
    asked.push(food)
    const content = JSON.stringify(per100({ name_fr: food }))
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 })
  }) as typeof fetch
  const db = fakeDb((table, filters, op) => {
    if (table === "nb_patient_food_aliases" && op === "select") return [{ alias_norm: "quark" }]
    if (table === "nb_patient_food_aliases" && op === "single") {
      return filters.alias_norm === "quark" ? { id: "a-1", food_item_id: "f-skyr", off_code: null, grams_default: null, hit_count: 2 } : null
    }
    if (table === "nb_food_items" && op === "single" && filters.id === "f-skyr") {
      return { id: "f-skyr", name: "Skyr, plain", name_fr: "skyr nature", category: "Dairy and Egg Products",
        energy_kcal: 63, protein_g: 11, carbs_g: 4, fat_g: 0.2, fiber_g: 0 }
    }
    return null
  })
  try {
    const priced = await mod.priceMeal(db, [
      { name: "quark", estimated_grams: 150, flags: [] },
      { name: "dinner items", estimated_grams: 300, flags: [] },
      { name: "cooked brown rice", estimated_grams: 100, flags: [] },
    ], "patient-1")
    assertEquals(asked, ["cooked brown rice"]) // only the open food went to OpenAI
    assertEquals(priced.items.map((i: { basis: string }) => i.basis), ["learned", "unknown", "ai"])
    assertEquals(priced.items[0].food_item_id, "f-skyr")
    assertEquals(priced.totals.kcal, Math.round(63 * 1.5 + 123)) // the placeholder is not counted
    assertEquals(priced.pricing.pinned, 2)
    assertEquals(priced.pricing.fallback, 0)
  } finally {
    globalThis.fetch = realFetch
    g.Supabase = realSupabase
  }
})
