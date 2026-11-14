// Meal micros from the full nutrient catalogue (`food_lines_nutrition_cat`), merged by catalogue-nutrients.ts.
// Every RPC result here is REAL output captured read-only from CM OS (fixtures/catalogue-rpc.json, see its _note).
import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1"
import fx from "./fixtures/catalogue-rpc.json" with { type: "json" }
import { catalogueLines, mergeCatalogueNutrients } from "../catalogue-nutrients.ts"
import { CATALOGUE_MICRO_KEYS } from "../micro-keys.ts"
import { priceItem, type ResolvedItem } from "../food-resolver.ts"
import { completionPatch, emptyPriced, type IdentifySuccess } from "../meal-analysis.ts"

const SALMON = "f01b874c-a0df-41c3-befc-7037a4d1e3a1"
const BANANA = "ff486f7f-55f2-4196-a2ea-2b8c269779e2"
const EMMENTAL = "e6c1773a-8e90-4a78-acb4-1349eab70655"
const UNKNOWN = "00000000-0000-4000-8000-000000000000"
const MACROS = ["kcal", "energy_kcal", "energy_kj", "protein_g", "fat_g", "carbs_g", "fiber_g"]

const row = (id: string) => fx.legacy_rows.find((r) => r.id === id) as Record<string, unknown>
/** What the edge function stored before this change: the resolver's priceItem over the 34 nb_food_items columns. */
const legacy = (id: string, grams: number, basis: ResolvedItem["basis"] = "matched"): ResolvedItem =>
  priceItem(row(id), grams, { basis, foodItemId: id })

/** The three-food meal of fixture f1: salmon 150 g, banana 120 g, Emmental 30 g, all matched to a catalogue row. */
const f1Meal = (): ResolvedItem[] => [legacy(SALMON, 150), legacy(BANANA, 120), legacy(EMMENTAL, 30)]

const aiItem = (): ResolvedItem => ({
  name: "lentil soup", local_name: null, category: null, estimated_grams: 200,
  kcal: 150, protein_g: 9, carbs_g: 20, fat_g: 3, fiber_g: 6,
  micros: Object.fromEntries(CATALOGUE_MICRO_KEYS.map((k) => [k, k === "iron_mg" ? 3 : null])),
  basis: "ai", food_item_id: null,
})
const unpriced = (): ResolvedItem => ({
  name: "mystery sauce", local_name: null, category: null, estimated_grams: 100,
  kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, micros: {}, basis: "estimated", food_item_id: null,
  needs_review: true, review_reason: "not_found", review_severity: "red",
})

Deno.test("catalogue: a matched food carries the catalogue's amino acids (salmon -> leucine_g)", () => {
  const items = f1Meal()
  assertEquals(catalogueLines(items), fx.f1_lines)
  assertEquals(items[0].micros.leucine_g, undefined) // the 34 columns never had it
  const r = mergeCatalogueNutrients(items, fx.f1_result)
  assertEquals(r.items[0].micros?.leucine_g, 2.4225)
  assertEquals(r.micronutrient_totals.leucine_g, 2.4225)
  assertEquals(r.micro_coverage.by_key.leucine_g, 0.5) // 150 of 300 g
  assertEquals(r.catalogue_version, "2026-11-p1.1")
  assertEquals(r.catalogue_items, 3)
  for (const m of MACROS) assert(!(m in r.micronutrient_totals), m)
  assertEquals(r.micro_coverage.catalogue_tracked, 130) // 135 coverage keys - 5 macros, all 34 legacy keys among them
  assertEquals(r.micro_coverage.catalogue_measured, 111)
})

Deno.test("catalogue: an AI-estimated food keeps its estimate, is not sent, and gets no amino acids", () => {
  const ai = aiItem()
  const items = [...f1Meal(), ai]
  assertEquals(catalogueLines(items), fx.f1_lines) // the AI item is not a catalogue line
  const r = mergeCatalogueNutrients(items, fx.f1_result)
  assertEquals(r.items[3].micros, ai.micros)
  assert(!("leucine_g" in (r.items[3].micros ?? {})))
  assertAlmostEquals(r.micronutrient_totals.iron_mg, 0.51 + 0.24 + 0.045 + 3, 1e-9)
})

Deno.test("catalogue: mixed meal — partial coverage per key, metrics rescaled to the priced weight and partial", () => {
  const items = [...f1Meal(), aiItem(), unpriced()] // priced weight 150+120+30+200+100 = 600 g
  const r = mergeCatalogueNutrients(items, fx.f1_result)
  assertEquals(r.micro_coverage.by_key.leucine_g, 0.25)
  assertEquals(r.micro_coverage.by_key.iron_mg, 0.833) // the unpriced 100 g carries nothing
  assert(r.micro_coverage.by_key.leucine_g < 1)
  assertEquals(r.micro_coverage.below_limit.selenium_mcg, 0.25) // 150 g of traces over 600 g
  // The function said complete over its own 300 g; over the whole meal it is half.
  assertEquals(r.nutrient_metrics?.omega6_omega3_ratio, { value: 0.417, status: "partial", coverage: 0.5 })
  assertEquals(r.nutrient_metrics?.epa_dha_dpa_mg, { value: 3538.5, status: "partial", coverage: 0.25 })
})

Deno.test("catalogue: an all-catalogue meal keeps the function's own complete / partial verdicts", () => {
  const r = mergeCatalogueNutrients(f1Meal(), fx.f1_result)
  assertEquals(r.nutrient_metrics?.omega6_omega3_ratio, { value: 0.417, status: "complete", coverage: 1 })
  assertEquals(r.nutrient_metrics?.epa_dha_mg, { value: 2949, status: "complete", coverage: 1 })
  assertEquals(r.nutrient_metrics?.epa_dha_dpa_mg, { value: 3538.5, status: "partial", coverage: 0.5 })
})

Deno.test("catalogue: traces (amount 0 + below_limit_share) are recorded apart from a measured zero", () => {
  // Fixture f2: banana 120 g, a line the function does not know (a branded product id) 100 g, banana 60 g.
  const product: ResolvedItem = {
    ...legacy(BANANA, 100), name: "branded smoothie", food_item_id: UNKNOWN,
    micros: Object.fromEntries(CATALOGUE_MICRO_KEYS.map((k) => [k, k === "iron_mg" ? 1.5 : null])),
  }
  const items = [legacy(BANANA, 120), product, legacy(BANANA, 60)]
  assertEquals(catalogueLines(items), fx.f2_lines)
  const r = mergeCatalogueNutrients(items, fx.f2_result)
  // Selenium in banana is "< 20 µg/100 g": amount 0, but every gram of it is below the limit -> the UI says "Traces".
  assertEquals(r.micronutrient_totals.selenium_mcg, 0)
  assertEquals(r.micro_coverage.by_key.selenium_mcg, 0.643)
  assertEquals(r.micro_coverage.below_limit.selenium_mcg, 0.643)
  assert(r.micro_coverage.below_limit.selenium_mcg >= r.micro_coverage.by_key.selenium_mcg)
  // B12 in banana is a MEASURED zero: same 0 total, no below-limit share -> the UI says 0, not "Traces".
  assertEquals(r.micronutrient_totals.b12_mcg, 0)
  assertEquals(r.micro_coverage.by_key.b12_mcg, 0.643)
  assertEquals(r.micro_coverage.below_limit.b12_mcg, undefined)
  // Macro keys never reach below_limit (fat_g is in the function's below_limit_share).
  assertEquals(r.micro_coverage.below_limit.fat_g, undefined)
})

Deno.test("catalogue: a duplicate food and an unknown id map back by order; the unknown one keeps today's micros", () => {
  const product: ResolvedItem = { ...legacy(BANANA, 100), name: "branded smoothie", food_item_id: UNKNOWN, micros: { iron_mg: 1.5, zinc_mg: null } }
  const items = [legacy(BANANA, 120), product, legacy(BANANA, 60)]
  const r = mergeCatalogueNutrients(items, fx.f2_result)
  assertEquals(r.items[0].micros?.potassium_mg, 384)
  assertEquals(r.items[1].micros, { iron_mg: 1.5, zinc_mg: null }) // the function returned no item for it
  assertEquals(r.items[2].micros?.potassium_mg, 192)
  assertEquals(r.catalogue_items, 2)
  assertAlmostEquals(r.micronutrient_totals.iron_mg, 0.24 + 1.5 + 0.12, 1e-9)
  assertEquals(r.micro_coverage.by_key.zinc_mg, 0.643) // the product's null zinc is not a value
  // Not every priced gram is a catalogue line, so even a "complete" function metric could not be complete here.
  assertEquals(r.nutrient_metrics?.vitamin_a_re_mcg?.status, "partial")
})

Deno.test("catalogue: the 34 legacy keys are unchanged for matched foods (old columns x grams/100 vs the function)", () => {
  const items = f1Meal()
  const r = mergeCatalogueNutrients(items, fx.f1_result)
  for (let i = 0; i < items.length; i++) {
    const old = items[i].micros // priceItem over nb_food_items, the path this change retires for micros
    const now = r.items[i].micros ?? {}
    for (const k of CATALOGUE_MICRO_KEYS) {
      if (old[k] === null || old[k] === undefined) {
        assert(!(k in now), `${items[i].name}: ${k} was null in the columns, must be absent now (got ${now[k]})`)
      } else {
        assert(typeof now[k] === "number", `${items[i].name}: ${k} lost`)
        assertAlmostEquals(now[k] as number, old[k] as number, 1e-3, `${items[i].name}: ${k}`)
      }
    }
  }
  // K2 is on hold (nb_nutrients.hold_reason): the FUNCTION serves it from the legacy nb_food_items column, unchanged.
  // Salmon and banana have none (absent); Emmental's 5.23 µg/100 g x 0.3 comes through as before.
  assert(!("vitamin_k2_mcg" in (r.items[0].micros ?? {})))
  assertEquals(r.items[2].micros?.vitamin_k2_mcg, 1.569)
  assertEquals(r.micronutrient_totals.vitamin_k2_mcg, 1.569)
  // Macros are not this module's business: the items keep exactly the numbers they had.
  for (let i = 0; i < items.length; i++) {
    for (const k of ["kcal", "protein_g", "carbs_g", "fat_g", "fiber_g"] as const) assertEquals(r.items[i][k], items[i][k])
  }
})

Deno.test("catalogue: no result (RPC failed) — today's micros stand, nulls are absent, no version, no metrics", () => {
  const items = f1Meal()
  const r = mergeCatalogueNutrients(items, null)
  for (let i = 0; i < items.length; i++) assertEquals(r.items[i].micros, items[i].micros)
  assertAlmostEquals(r.micronutrient_totals.iron_mg, 0.51 + 0.24 + 0.045, 1e-9)
  assert(!("biotin_mcg" in r.micronutrient_totals)) // null on every item: absent, never 0 or null
  assert(!("leucine_g" in r.micronutrient_totals))
  assertEquals(r.catalogue_version, undefined)
  assertEquals(r.nutrient_metrics, undefined)
  assertEquals(r.catalogue_items, 0)
  assertEquals(r.micro_coverage.by_key.iron_mg, 1)
  assertEquals(r.micro_coverage.catalogue_tracked, 34)
})

Deno.test("catalogue: a decomposed item is priced from its components' catalogue lines", () => {
  const bowl: ResolvedItem = {
    name: "salmon banana bowl", local_name: null, category: null, estimated_grams: 270,
    kcal: 420, protein_g: 32, carbs_g: 24, fat_g: 20, fiber_g: 3, micros: { iron_mg: 0.75 }, basis: "decomposed", food_item_id: null,
    components: [
      { name: "salmon", grams: 150, kcal: 312, fraction: 150 / 270, food_item_id: SALMON },
      { name: "banana", grams: 120, kcal: 108.6, fraction: 120 / 270, food_item_id: BANANA },
    ],
  }
  const items = [bowl, legacy(EMMENTAL, 30)]
  assertEquals(catalogueLines(items), fx.f1_lines)
  const r = mergeCatalogueNutrients(items, fx.f1_result)
  assertEquals(r.items[0].micros?.leucine_g, 2.4225)
  assertAlmostEquals(r.items[0].micros?.potassium_mg as number, 544.5 + 384, 1e-9)
  assertEquals(r.micro_coverage.by_key.leucine_g, 0.5)
  assertEquals(r.catalogue_items, 2)
  assertEquals(r.nutrient_metrics?.omega6_omega3_ratio?.status, "complete")
})

Deno.test("catalogueLines: only catalogue bases, a uuid id and grams > 0; a decomposed item only when every part has an id", () => {
  const ok = (basis: ResolvedItem["basis"], id: string | null, grams: number) => ({ basis, food_item_id: id, estimated_grams: grams })
  const lines = catalogueLines([
    ok("ai", null, 100), ok("estimated", null, 100), ok("unknown", null, 100),
    ok("matched", "not-a-uuid", 100), ok("matched", SALMON, 0),
    ok("learned", BANANA, 80), ok("exact", EMMENTAL, 20),
    { basis: "decomposed", estimated_grams: 100, food_item_id: null, components: [{ grams: 50, food_item_id: SALMON }, { grams: 50, food_item_id: null }] },
  ])
  assertEquals(lines, [{ food_item_id: BANANA, grams: 80 }, { food_item_id: EMMENTAL, grams: 20 }])
})

Deno.test("completionPatch writes the catalogue additions into resolution_meta and the totals as merged", () => {
  const ident = {
    dish_name: "x", items: [], model_items: [], model: "m", confidence: 1, duplicates_dropped: 0, elapsed_ms: 1,
    coverage: "full", coverage_note: null,
  } as unknown as IdentifySuccess
  const merged = mergeCatalogueNutrients(f1Meal(), fx.f1_result)
  const priced = { ...emptyPriced(), items: merged.items, resolved: merged.items, micros: merged.micronutrient_totals, catalogue: merged } as never
  // deno-lint-ignore no-explicit-any
  const patch = completionPatch(ident, priced, 1, null) as Record<string, any>
  const mc = patch.resolution_meta.micro_coverage
  assertEquals([mc.tracked, mc.items, mc.items_from_catalogue], [34, 3, 3]) // the legacy fields keep their meaning
  assertEquals(mc.by_key.leucine_g, 0.5)
  assertEquals(mc.below_limit.selenium_mcg, 0.5)
  assertEquals([mc.catalogue_tracked, mc.catalogue_measured], [130, 111])
  assertEquals(patch.resolution_meta.catalogue_version, "2026-11-p1.1")
  assertEquals(patch.resolution_meta.nutrient_metrics.omega6_omega3_ratio, { value: 0.417, status: "complete", coverage: 1 })
  assertEquals(patch.micronutrient_totals.leucine_g, 2.4225)

  const failed = { ...emptyPriced(), catalogue: { ...mergeCatalogueNutrients(f1Meal(), null), catalogue_error: "boom" } } as never
  // deno-lint-ignore no-explicit-any
  const p2 = completionPatch(ident, failed, 1, null) as Record<string, any>
  assertEquals(p2.resolution_meta.catalogue_error, "boom")
  assertEquals(p2.resolution_meta.catalogue_version, undefined)
})
