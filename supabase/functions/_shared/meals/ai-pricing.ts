// Pricing the identified foods with OpenAI instead of the reference database (owner, 2026-10-12: the photo was
// identified "super quick" but the foods took ages — "make all the process on OpenAI … it's just for testing").
//
// WHY THIS IS FAST. The database ladder (food-resolver.ts) runs an in-process gte-small embedding and a
// match_food_items RPC per search term, 1–3 terms per food, and on a photo of 8 foods that exhausts the isolate's
// CPU budget ("CPU Time exceeded"), leaving the meal to the 2-minute stale sweep. Here each DISTINCT food is one small
// text call (its name, nothing about the member), all in parallel: no embedding, no CPU, a couple of seconds.
//
// WHAT IT ASKS FOR. Per 100 g of the food as named — a composition table's unit, which the model recalls far better
// than an arbitrary portion — and the server scales it to the identified grams with the resolver's own rounding, so a
// portion edit scales the same way. Only the nutrients something reads: the macros, the three the scorer uses
// (saturated fat, sugar, omega-3), the 21 the app's coverage trend shows, and sodium. A nutrient the model does not
// know stays null ("not measured"), never 0. A USDA category from a fixed list lets meal-scores classify the food
// from data, as it does for a database row.
//
// WHAT IT IS NOT. A measurement: `basis: "ai"`, `food_item_id: null`. A food the model cannot price (timeout, bad
// JSON, implausible numbers, "not a food") comes back null and the caller prices it from the database instead.
import type { ResolvedItem } from "./food-resolver.ts"

/** The categories meal-scores reads (`categoryGroup`): USDA titles, matched case-insensitively. */
export const AI_CATEGORIES = [
  "Vegetables and Vegetable Products", "Legumes and Legume Products", "Nut and Seed Products", "Spices and Herbs",
  "Fruits and Fruit Juices", "Sweets", "Finfish and Shellfish Products", "Poultry Products", "Beef Products",
  "Pork Products", "Lamb, Veal, and Game Products", "Sausages and Luncheon Meats", "Dairy and Egg Products",
  "Fast Foods", "Snacks", "Cereal Grains and Pasta", "Baked Products", "Breakfast Cereals", "Fats and Oils",
  "Beverages", "Soups, Sauces, and Gravies", "Meals, Entrees, and Side Dishes",
] as const

const MACRO_KEYS = ["energy_kcal", "protein_g", "carbs_g", "fat_g", "fiber_g"] as const
type MacroKey = typeof MACRO_KEYS[number]

/** Per-100 g nutrients asked for, in the units of the database columns (EPA/DHA in mg, as the resolver renames them). */
export const AI_MICRO_KEYS = [
  "sugar_g", "saturated_fat_g", "omega3_g", "ala_g", "epa_mg", "dha_mg",
  "vitamin_a_mcg", "vitamin_c_mg", "vitamin_d_mcg", "vitamin_e_mg", "vitamin_k2_mcg", "b12_mcg", "folate_mcg",
  "biotin_mcg", "choline_mg", "calcium_mg", "iron_mg", "magnesium_mg", "phosphorus_mg", "potassium_mg",
  "sodium_mg", "zinc_mg", "selenium_mcg", "iodine_mcg",
] as const

export const AI_PRICING_SYSTEM = `You are a food-composition reference, like USDA FoodData Central and the French CIQUAL table.
For the ONE food the user names, as eaten (cooked or raw as the name says), give its typical nutrient content PER 100 g.
Return ONLY a JSON object with exactly these keys:
"name_fr": the food's usual French name;
"category": one of ${AI_CATEGORIES.map((c) => JSON.stringify(c)).join(", ")} — or null if none fits;
${[...MACRO_KEYS, ...AI_MICRO_KEYS].map((k) => JSON.stringify(k)).join(", ")}: numbers per 100 g, in the unit the key ends with (kcal, g, mg, mcg).
Use null for a nutrient you do not know or that the food is not normally analysed for. Do not add precision you do not have.
If the name is not a food (for example "dinner items"), return {"not_food": true}.`

export type Per100 = {
  nameFr: string | null
  category: string | null
  macros: Record<MacroKey, number>
  micros: Record<string, number | null>
}

const number = (v: unknown): number | null => {
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v
  return typeof n === "number" && Number.isFinite(n) ? n : null
}

/**
 * The model's answer, checked. Null when it cannot be used (not JSON, a macro missing or implausible per 100 g);
 * "not_food" when the model says the name is not a food. A micro that is missing, negative or absurd reads as null.
 */
export function parsePer100(content: string): Per100 | "not_food" | null {
  let raw: unknown
  try {
    raw = JSON.parse(content)
  } catch {
    return null
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  const o = raw as Record<string, unknown>
  if (o.not_food === true) return "not_food"

  const macros = {} as Record<MacroKey, number>
  for (const k of MACRO_KEYS) {
    const v = number(o[k])
    if (v === null) {
      if (k === "fiber_g" && (o[k] === null || o[k] === undefined)) { macros[k] = 0; continue }
      return null
    }
    if (v < 0) return null
    macros[k] = v
  }
  // Per 100 g, nothing is denser than pure fat (~900 kcal), and the solids cannot outweigh the food.
  if (macros.energy_kcal > 902) return null
  if (macros.protein_g > 100 || macros.carbs_g > 100 || macros.fat_g > 100 || macros.fiber_g > 100) return null
  if (macros.protein_g + macros.carbs_g + macros.fat_g + macros.fiber_g > 105) return null

  const micros: Record<string, number | null> = {}
  for (const k of AI_MICRO_KEYS) {
    const v = number(o[k])
    micros[k] = v === null || v < 0 || v > 100_000 ? null : v
  }

  const wanted = typeof o.category === "string" ? o.category.trim().toLowerCase() : ""
  const category = AI_CATEGORIES.find((c) => c.toLowerCase() === wanted) ?? null
  const nameFr = typeof o.name_fr === "string" && o.name_fr.trim() ? o.name_fr.trim() : null
  return { nameFr, category, macros, micros }
}

/** The resolver's precision floor for a portion: 10 g steps, 0.1 g below 10 g (food-resolver.ts `roundGrams`). */
export function roundPortion(g: number): number {
  if (!Number.isFinite(g) || g <= 0) return 0
  if (g < 10) return Math.round(g * 10) / 10
  return Math.round(g / 10) * 10
}

/** One food at its portion, in the resolver's shape. A null micro stays null: scaling "unknown" would invent it. */
export function priceFromPer100(name: string, grams: number, p: Per100): ResolvedItem {
  const g = roundPortion(grams)
  const scale = g / 100
  const micros: Record<string, number | null> = {}
  for (const [k, v] of Object.entries(p.micros)) micros[k] = v === null ? null : v * scale
  return {
    name,
    local_name: p.nameFr,
    category: p.category,
    estimated_grams: g,
    kcal: p.macros.energy_kcal * scale,
    protein_g: p.macros.protein_g * scale,
    carbs_g: p.macros.carbs_g * scale,
    fat_g: p.macros.fat_g * scale,
    fiber_g: p.macros.fiber_g * scale,
    micros,
    basis: "ai",
    food_item_id: null,
  }
}

export type AiPricingOptions = {
  apiKey: string
  model: string
  /** Per call. A food that has not answered by then is priced from the database instead. */
  timeoutMs?: number
  /** Calls in flight at once. */
  concurrency?: number
  fetchImpl?: typeof fetch
}

/** Ask for one food's nutrients per 100 g. Null on any failure — the caller falls back, it never throws. */
async function askPer100(name: string, opts: AiPricingOptions): Promise<Per100 | null> {
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort(), opts.timeoutMs ?? 12_000)
  try {
    const r = await (opts.fetchImpl ?? fetch)("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${opts.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: opts.model,
        messages: [
          { role: "system", content: AI_PRICING_SYSTEM },
          { role: "user", content: name },
        ],
        // As identification: no temperature (the GPT-5 family takes only the default), one JSON object, no reasoning.
        response_format: { type: "json_object" },
        reasoning_effort: "none",
      }),
      signal: ac.signal,
    })
    const text = await r.text()
    if (!r.ok) {
      console.warn(`[ai-pricing] ${r.status} for one food`)
      return null
    }
    const content = (JSON.parse(text) as { choices?: Array<{ message?: { content?: string } }> }).choices?.[0]?.message?.content
    if (typeof content !== "string") return null
    const parsed = parsePer100(content)
    return parsed === "not_food" ? null : parsed
  } catch (e) {
    console.warn(`[ai-pricing] one food failed: ${e instanceof Error ? e.name : "error"}`)
    return null
  } finally {
    clearTimeout(timer)
  }
}

/**
 * Price each item from OpenAI, in the order given. One call per DISTINCT name (two "olive oil" rows share it), at
 * most `concurrency` at once. A null in the result is an item the caller must price another way.
 */
export async function priceItemsWithOpenAI(
  items: Array<{ name: string; grams: number }>,
  opts: AiPricingOptions,
): Promise<Array<ResolvedItem | null>> {
  const keyOf = (name: string) => name.trim().toLowerCase()
  const names = [...new Set(items.map((it) => keyOf(it.name)).filter(Boolean))]
  const answers = new Map<string, Per100 | null>()
  let next = 0
  const worker = async () => {
    while (next < names.length) {
      const key = names[next++]
      answers.set(key, await askPer100(key, opts))
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, Math.min(opts.concurrency ?? 8, names.length)) }, worker))
  return items.map((it) => {
    const per100 = answers.get(keyOf(it.name))
    return per100 ? priceFromPer100(it.name, it.grams, per100) : null
  })
}
