// Food-flag keys — the single canonical list shared by the analyze-meal edge
// function (the model emits these per item) and the app (icons + fallback
// heuristics in lib/meal-log/food-flags.ts). Pure module (no imports) → runs
// in Deno (Edge Function), Node (vitest) and the app bundle alike.

export const FOOD_FLAG_KEYS = [
  // good signals first — this order is also the display order on items
  'antiInflammatory',
  'fiber',
  'protein',
  'omega3',
  'probiotic',
  'micronutrientDense',
  'antioxidant',
  'healthyFats',
  'boneSupport',
  'hydrating',
  // watch-outs
  'inflammatory',
  'fastSugars',
  'sodium',
  'ultraProcessed',
  'allergen',
] as const

export type FoodFlagKey = (typeof FOOD_FLAG_KEYS)[number]

const VALID = new Set<string>(FOOD_FLAG_KEYS)

/** Model output is untrusted: keep only known keys, dedupe, and re-order to
 *  the canonical good-first order. Anything else → dropped silently. */
export function sanitizeFlags(value: unknown): FoodFlagKey[] {
  if (!Array.isArray(value)) return []
  const present = new Set(value.filter((v): v is FoodFlagKey => typeof v === 'string' && VALID.has(v)))
  return FOOD_FLAG_KEYS.filter((k) => present.has(k))
}
