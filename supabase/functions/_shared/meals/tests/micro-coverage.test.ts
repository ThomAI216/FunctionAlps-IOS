// Micronutrient key list (micro-keys.ts) and the per-meal coverage record (`resolution_meta.micro_coverage`).
import { assert, assertEquals } from "jsr:@std/assert@1"
import { CATALOGUE_MICRO_KEYS, computeMicroCoverage } from "../micro-keys.ts"
import { AI_MICRO_KEYS } from "../ai-pricing.ts"
import { completionPatch, emptyPriced, type IdentifySuccess } from "../meal-analysis.ts"

type It = { basis: string; micros?: Record<string, number | null> }
const it = (basis: string, micros: Record<string, number | null>): It => ({ basis, micros })

Deno.test("the catalogue key list has 34 distinct keys, all in the _g/_mg/_mcg naming, none a macro", () => {
  assertEquals(CATALOGUE_MICRO_KEYS.length, 34)
  assertEquals(new Set(CATALOGUE_MICRO_KEYS).size, 34)
  for (const k of CATALOGUE_MICRO_KEYS) assert(/_(g|mg|mcg)$/.test(k), k)
  for (const macro of ["energy_kcal", "protein_g", "carbs_g", "fat_g", "fiber_g"]) assert(!CATALOGUE_MICRO_KEYS.includes(macro as never), macro)
})

Deno.test("the AI estimate asks for exactly the catalogue's keys (one shared list, no drift)", () => {
  assertEquals([...AI_MICRO_KEYS].sort(), [...CATALOGUE_MICRO_KEYS].sort())
  for (const k of ["thiamin_mg", "riboflavin_mg", "niacin_mg", "b6_mg", "vitamin_k_mcg", "copper_mg", "manganese_mg", "omega6_g", "chromium_mcg", "alcohol_g"]) {
    assert((AI_MICRO_KEYS as readonly string[]).includes(k), k)
  }
})

Deno.test("coverage: measured = keys with a value on at least one item; partial = value on some items, not all", () => {
  const c = computeMicroCoverage([
    it("matched", { iron_mg: 2, zinc_mg: 1, iodine_mcg: null }),
    it("ai", { iron_mg: 1, iodine_mcg: null }),
    it("matched", { iron_mg: 3, zinc_mg: null }),
  ])
  assertEquals(c.tracked, 34)
  assertEquals(c.items, 3)
  assertEquals(c.items_from_catalogue, 2)
  assertEquals(c.measured, 2) // iron, zinc. iodine is null everywhere.
  assertEquals(c.partial, ["zinc_mg"])
})

Deno.test("coverage: an unknown (not-a-food) item is not an item; an unmatched estimate with no micros makes keys partial", () => {
  const c = computeMicroCoverage([
    it("matched", { iron_mg: 2 }),
    it("unknown", {}),
    it("estimated", {}),
  ])
  assertEquals(c.items, 2)
  assertEquals(c.items_from_catalogue, 1)
  assertEquals(c.partial, ["iron_mg"])
})

Deno.test("coverage: keys outside the catalogue list are not counted; empty meal is all zeros", () => {
  const c = computeMicroCoverage([it("matched", { made_up_mg: 4, iron_mg: 1 })])
  assertEquals(c.measured, 1)
  assertEquals(c.partial, [])
  assertEquals(computeMicroCoverage([]), { tracked: 34, measured: 0, items: 0, items_from_catalogue: 0, partial: [] })
})

Deno.test("completionPatch records micro_coverage in resolution_meta and leaves totals and other fields as they were", () => {
  const ident = {
    dish_name: "x", items: [], model_items: [], model: "m", confidence: 1, duplicates_dropped: 0, elapsed_ms: 1,
    coverage: "full", coverage_note: null,
  } as unknown as IdentifySuccess
  const priced = emptyPriced()
  const mk = (basis: string, micros: Record<string, number | null>) => ({ name: "a", basis, micros, estimated_grams: 100, kcal: 1, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 })
  priced.items = [mk("matched", { iron_mg: 2, zinc_mg: 1 }), mk("ai", { iron_mg: 1 })] as never
  priced.resolved = priced.items as never
  priced.micros = { iron_mg: 3, zinc_mg: 1 }
  const patch = completionPatch(ident, priced, 1, null) as Record<string, any>
  assertEquals(patch.resolution_meta.micro_coverage, {
    tracked: 34, measured: 2, items: 2, items_from_catalogue: 1, partial: ["zinc_mg"],
  })
  assertEquals(patch.micronutrient_totals, { iron_mg: 3, zinc_mg: 1 }) // sums untouched
  assertEquals(patch.resolution_meta.basis, { matched: 1, ai: 1 })
})
