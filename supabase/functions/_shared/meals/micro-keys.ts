// The micronutrient keys a meal can carry, and how many of them a given meal actually measured.
//
// ONE LIST. `nb_food_items` has 34 nutrient columns; a matched row contributes all of them (food-resolver.ts `priceItem`
// keeps every `_g/_mg/_mcg` column) and the AI per-100 g estimate (ai-pricing.ts) is asked for the same keys, so the two
// paths cannot drift apart again (before: the AI path asked for 24, so an AI-priced food silently lacked 10).
// Keys use the catalogue's unit-suffix naming; EPA and DHA are `_mg` because the resolver converts `epa_g/dha_g` to mg.
//
// ⚠ PURE LEAF: no imports at all, so tests and any bundle can load it. If the catalogue gains a nutrient column, add it
// HERE and nowhere else.
export const CATALOGUE_MICRO_KEYS = [
  "sugar_g", "saturated_fat_g", "alcohol_g",
  "omega3_g", "omega6_g", "ala_g", "epa_mg", "dha_mg",
  "vitamin_a_mcg", "vitamin_c_mg", "vitamin_d_mcg", "vitamin_e_mg", "vitamin_k_mcg", "vitamin_k2_mcg",
  "thiamin_mg", "riboflavin_mg", "niacin_mg", "b6_mg", "b12_mcg", "folate_mcg", "biotin_mcg", "choline_mg",
  "calcium_mg", "iron_mg", "magnesium_mg", "phosphorus_mg", "potassium_mg", "sodium_mg", "zinc_mg",
  "selenium_mcg", "iodine_mcg", "copper_mg", "manganese_mg", "chromium_mcg",
] as const

export type MicroCoverage = {
  /** How many nutrient keys the catalogue has (the ceiling for any meal). */
  tracked: number
  /** Tracked keys that have a value on at least one item. */
  measured: number
  /** Items that went into the totals (not-a-food `unknown` placeholders are not items). */
  items: number
  /** Of those, items priced from a catalogue row (basis exact / learned / matched / decomposed), not an AI estimate. */
  items_from_catalogue: number
  /** Tracked keys with a value on some items but not all: their meal total is a partial sum. Sorted. */
  partial: string[]
}

const FROM_CATALOGUE = new Set(["exact", "learned", "matched", "decomposed"])

/**
 * Coverage of a meal's micronutrients. Reads the items only; it does not touch how totals are summed.
 * Same item set as the totals: `basis: "unknown"` is excluded. An `estimated` item (not found, no micros) counts as an
 * item, so every key it lacks reads as partial, which is the honest reading.
 */
export function computeMicroCoverage(
  items: ReadonlyArray<{ basis?: string; micros?: Record<string, number | null> | null }>,
): MicroCoverage {
  const counted = items.filter((i) => i.basis !== "unknown")
  const partial: string[] = []
  let measured = 0
  for (const key of CATALOGUE_MICRO_KEYS) {
    const withValue = counted.filter((i) => typeof i.micros?.[key] === "number" && Number.isFinite(i.micros[key])).length
    if (withValue === 0) continue
    measured++
    if (withValue < counted.length) partial.push(key)
  }
  return {
    tracked: CATALOGUE_MICRO_KEYS.length,
    measured,
    items: counted.length,
    items_from_catalogue: counted.filter((i) => FROM_CATALOGUE.has(i.basis ?? "")).length,
    partial: partial.sort(),
  }
}
