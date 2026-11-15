// Meal micronutrients from the FULL nutrient catalogue (`food_lines_nutrition_cat`), merged onto priced meal items.
//
// ── SIGNATURE (the offline replay calls exactly these two) ──────────────────────────────────────────────────────────
//
//   catalogueLines(items: CatalogueItem[]): CatalogueLine[]
//       The `p_lines` for ONE `food_lines_nutrition_cat(p_lines, p_servings => 1)` call (estimates off, flagged kept —
//       the function's defaults). Deterministic from the items alone, so a replay only needs the items + the result.
//
//   mergeCatalogueNutrients<T extends CatalogueItem>(items: T[], rpc: unknown | null): CatalogueMerge<T>
//       `rpc` is the function's jsonb result for catalogueLines(items), or null when it was not called / errored.
//       Returns {
//         items                 same order, same objects except `micros` on the items the catalogue priced
//         micronutrient_totals  key -> sum over the items that carry a finite value; absent when none does (never 0/null);
//                               macro keys (MACRO_KEYS) excluded
//         micro_coverage        { by_key, below_limit, catalogue_tracked, catalogue_measured } — ADDITIONS to
//                               resolution_meta.micro_coverage (computeMicroCoverage keeps the legacy fields)
//         nutrient_metrics?     metric -> { value, status, coverage } over the meal's priced weight (only with a result)
//         catalogue_version?    the function's catalogue_version (only with a result)
//         catalogue_error?      set when a result came back but could not be mapped onto the lines (then ignored)
//         catalogue_items       how many items took their micros from the catalogue
//       }
//
// WHICH ITEMS ARE CATALOGUE LINES. Basis in FROM_CATALOGUE (micro-keys.ts: exact / learned / matched / decomposed) —
// the same set `items_from_catalogue` already counts — with a uuid `food_item_id` and grams > 0. A decomposed item is
// sent as its components (each with its own id and exact grams), and only when EVERY component has one. `matched` and
// `learned` can point at a branded product (nb_food_products) rather than an nb_food_items row; the function knows only
// nb_food_items and silently drops such a line, so that item keeps the micros it was priced with (the product's
// columns). `ai` and `estimated` items are never sent and are left exactly as they are. Nothing here reaches any model.
//
// MAPPING. The function returns one item per KNOWN line, in input order, duplicates kept, unknown ids dropped
// (verified on CM OS 2026-11-14). Lines are matched to items by walking both in order on food_item_id; since a drop
// depends only on the id, two lines with the same id are kept or dropped together, so the walk is exact. The grams
// are checked too: any disagreement means the function changed shape, and the whole result is ignored.
//
// TRACES. A "lt"/"trace" value comes back as amount 0 with its weight in `below_limit_share` (over all lines sent).
// Those grams are capped at the grams of the used lines whose value for that key is 0, then expressed over the meal's
// priced weight, so a "0" in the totals can be told apart: below_limit[key] >= by_key[key] means it is all traces.
//
// ⚠ PURE: imports only the micro-keys.ts leaf. No network, no Supabase, no Deno globals.
import { CATALOGUE_MICRO_KEYS, FROM_CATALOGUE } from "./micro-keys.ts"

export type CatalogueLine = { food_item_id: string; grams: number }
export type CatalogueItem = {
  basis?: string
  estimated_grams?: number
  food_item_id?: string | null
  micros?: Record<string, number | null> | null
  components?: Array<{ grams: number; food_item_id: string | null }>
}
export type NutrientMetric = { value: number; status: "complete" | "partial"; coverage: number }
export type CatalogueMerge<T> = {
  items: T[]
  micronutrient_totals: Record<string, number>
  micro_coverage: {
    by_key: Record<string, number>
    below_limit: Record<string, number>
    catalogue_tracked: number
    catalogue_measured: number
  }
  nutrient_metrics?: Record<string, NutrientMetric>
  catalogue_version?: string
  catalogue_error?: string
  catalogue_items: number
}

/** Stored elsewhere on the meal row (total_calories, total_protein_g, ...), so never in micronutrient_totals. */
export const MACRO_KEYS: ReadonlySet<string> = new Set(["kcal", "energy_kcal", "energy_kj", "protein_g", "fat_g", "carbs_g", "fiber_g"])

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v)
const round3 = (n: number) => Math.round(n * 1000) / 1000
const weightOf = (it: CatalogueItem) => (isNum(it.estimated_grams) && it.estimated_grams > 0 ? it.estimated_grams : 0)
const priced = (it: CatalogueItem) => it.basis !== "unknown"

/** Per item: the lines it is sent as, or null when it is not a catalogue line. */
function planLines(items: ReadonlyArray<CatalogueItem>): Array<CatalogueLine[] | null> {
  const ok = (id: unknown, g: unknown): boolean => typeof id === "string" && UUID.test(id) && isNum(g) && g > 0
  return items.map((it) => {
    if (!FROM_CATALOGUE.has(it.basis ?? "")) return null
    if (it.basis === "decomposed") {
      const parts = it.components ?? []
      if (!parts.length || !parts.every((p) => ok(p.food_item_id, p.grams))) return null
      return parts.map((p) => ({ food_item_id: p.food_item_id as string, grams: p.grams }))
    }
    return ok(it.food_item_id, it.estimated_grams) ? [{ food_item_id: it.food_item_id as string, grams: it.estimated_grams as number }] : null
  })
}

export function catalogueLines(items: ReadonlyArray<CatalogueItem>): CatalogueLine[] {
  return planLines(items).flatMap((l) => l ?? [])
}

type RpcItem = { food_item_id: string; estimated_grams: number; micros: Record<string, number> }
type Rpc = {
  items: RpcItem[]
  below_limit_share: Record<string, number>
  metrics: Record<string, { value?: unknown; complete?: unknown; coverage?: unknown }>
  coverage: Record<string, unknown>
  catalogue_version?: string
}

function asRpc(raw: unknown): Rpc | null {
  if (!raw || typeof raw !== "object") return null
  const r = raw as Record<string, unknown>
  if (!Array.isArray(r.items)) return null
  const obj = (v: unknown) => (v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, never> : {})
  return {
    items: r.items as RpcItem[],
    below_limit_share: obj(r.below_limit_share),
    metrics: obj(r.metrics),
    coverage: obj(r.coverage),
    ...(typeof r.catalogue_version === "string" ? { catalogue_version: r.catalogue_version } : {}),
  }
}

/** Lines -> the function's item for each (null = the function did not know it), or null if the shapes disagree. */
function mapItems(lines: CatalogueLine[], rpc: Rpc): Array<RpcItem | null> | null {
  const out: Array<RpcItem | null> = []
  let j = 0
  for (const line of lines) {
    const cand = rpc.items[j]
    if (cand && cand.food_item_id === line.food_item_id) {
      if (!isNum(cand.estimated_grams) || Math.abs(cand.estimated_grams - Math.round(line.grams * 10) / 10) > 0.051) return null
      out.push(cand)
      j++
    } else out.push(null)
  }
  return j === rpc.items.length ? out : null
}

export function mergeCatalogueNutrients<T extends CatalogueItem>(items: T[], rpcRaw: unknown): CatalogueMerge<T> {
  const plan = planLines(items)
  const lines = plan.flatMap((l) => l ?? [])
  let rpc = rpcRaw === null || rpcRaw === undefined ? null : asRpc(rpcRaw)
  let catalogueError: string | undefined = rpcRaw !== null && rpcRaw !== undefined && !rpc ? "catalogue result malformed" : undefined
  let mapped: Array<RpcItem | null> | null = null
  if (rpc) {
    mapped = mapItems(lines, rpc)
    if (!mapped) {
      catalogueError = "catalogue items did not map onto the lines sent"
      rpc = null
    }
  }

  // Per item: the catalogue micros (or null to keep its own) and, per key, the grams that carry it.
  type Used = { micros: Record<string, number>; carry: Record<string, number>; zero: Record<string, number> }
  const used: Array<Used | null> = items.map(() => null)
  if (rpc && mapped) {
    let cursor = 0
    plan.forEach((itemLines, i) => {
      if (!itemLines) return
      const hits = itemLines.map((_, k) => mapped![cursor + k])
      cursor += itemLines.length
      if (hits.some((h) => !h)) return // a part the function did not know: the item keeps what it was priced with
      const sent = itemLines.reduce((a, l) => a + l.grams, 0)
      const scale = sent > 0 ? weightOf(items[i]) / sent : 0
      const u: Used = { micros: {}, carry: {}, zero: {} }
      hits.forEach((h, k) => {
        for (const [key, v] of Object.entries(h!.micros ?? {})) {
          if (MACRO_KEYS.has(key) || !isNum(v)) continue
          u.micros[key] = (u.micros[key] ?? 0) + v
          u.carry[key] = (u.carry[key] ?? 0) + itemLines[k].grams * scale
          if (v === 0) u.zero[key] = (u.zero[key] ?? 0) + itemLines[k].grams * scale
        }
      })
      used[i] = u
    })
  }

  const outItems = items.map((it, i) => (used[i] ? { ...it, micros: used[i]!.micros } : it))

  // Totals and by-key coverage, over the priced items (`unknown` is not a food and not in the totals).
  const totals: Record<string, number> = {}
  const carried: Record<string, number> = {}
  let pricedWeight = 0
  outItems.forEach((it, i) => {
    if (!priced(it)) return
    const w = weightOf(it)
    pricedWeight += w
    for (const [key, v] of Object.entries(it.micros ?? {})) {
      if (MACRO_KEYS.has(key) || !isNum(v)) continue
      totals[key] = (totals[key] ?? 0) + v
      carried[key] = (carried[key] ?? 0) + (used[i] ? used[i]!.carry[key] ?? 0 : w)
    }
  })
  const by_key: Record<string, number> = {}
  if (pricedWeight > 0) for (const key of Object.keys(totals)) by_key[key] = round3(Math.min(1, carried[key] / pricedWeight))

  const sentGrams = lines.reduce((a, l) => a + l.grams, 0)
  const below_limit: Record<string, number> = {}
  if (rpc && pricedWeight > 0) {
    for (const [key, share] of Object.entries(rpc.below_limit_share)) {
      if (MACRO_KEYS.has(key) || !isNum(share) || share <= 0) continue
      const zeroGrams = used.reduce((a, u) => a + (u?.zero[key] ?? 0), 0)
      const s = round3(Math.min(share * sentGrams, zeroGrams) / pricedWeight)
      if (s > 0) below_limit[key] = s
    }
  }

  const universe = new Set<string>([...CATALOGUE_MICRO_KEYS, ...Object.keys(totals)])
  if (rpc) for (const key of Object.keys(rpc.coverage)) if (!MACRO_KEYS.has(key)) universe.add(key)

  const catalogueItems = used.filter(Boolean).length
  let nutrient_metrics: Record<string, NutrientMetric> | undefined
  if (rpc) {
    // "complete" needs the function's word AND every priced gram to be a catalogue line it priced.
    const allCatalogue = outItems.every((it, i) => !priced(it) || weightOf(it) === 0 || used[i] !== null)
    nutrient_metrics = {}
    for (const [key, m] of Object.entries(rpc.metrics)) {
      const value = Number(m?.value)
      const cov = Number(m?.coverage)
      if (!m || m.value === null || !Number.isFinite(value) || !Number.isFinite(cov)) continue
      nutrient_metrics[key] = m.complete === true && allCatalogue
        ? { value, status: "complete", coverage: round3(cov) }
        : { value, status: "partial", coverage: pricedWeight > 0 ? round3(Math.min(1, (cov * sentGrams) / pricedWeight)) : 0 }
    }
  }

  return {
    items: outItems,
    micronutrient_totals: totals,
    micro_coverage: { by_key, below_limit, catalogue_tracked: universe.size, catalogue_measured: Object.keys(totals).length },
    ...(nutrient_metrics ? { nutrient_metrics } : {}),
    ...(rpc?.catalogue_version ? { catalogue_version: rpc.catalogue_version } : {}),
    ...(catalogueError ? { catalogue_error: catalogueError } : {}),
    catalogue_items: catalogueItems,
  }
}
