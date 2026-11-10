// SOVEREIGN PRICING (Thomas, 2026-11-10): the calories, macros and micros of every identified food come from our own
// reference plane — USDA SR Legacy and CIQUAL in nb_food_items — with Infomaniak models (Geneva) doing only what a
// database cannot: understanding what the food name means. No food name goes to OpenAI on this path.
//
// WHY. Until now the numbers came from OpenAI (ai-pricing.ts, MEAL_PRICING=openai) with the embedding ladder
// (food-resolver.ts) as the fallback. On 2026-11-08 OpenAI started answering 429; every food fell to the ladder, which
// matches a free-text name like "chia seeds soaked in milk" poorly and prices what it cannot match at ZERO — Barbara's
// chia pudding read 36 kcal. And the ladder's in-process embedding is what exhausts the isolate's CPU on an eight-food
// plate, the reason OpenAI pricing was introduced in the first place.
//
// HOW, per meal:
//   A. ONE Infomaniak call (Qwen 3.8, gemma as the second model) for all the meal's foods. For each it returns a
//      USDA-style reference description ("Seeds, chia seeds, dried"), or — for a mix or a dish — its components with
//      weight fractions ("chia seeds soaked in milk" → chia 0.2 + whole milk 0.8), plus its kcal per 100 g as eaten.
//      Short answers, so the call is fast.
//   B. ONE Postgres round trip (match_food_reference, trigram, no embedding) returns ranked candidates for every
//      description. A candidate is accepted only if it passes three checks: the food words of the description are in
//      its name (pork is never veal), raw versus cooked agree, and its energy density is close to the model's kcal per
//      100 g (dried chia is not chia pudding). Accepted rows are priced by the resolver's own priceItem.
//   C. Only foods the database could not price get a full per-100 g estimate from Infomaniak (basis "ai").
// Whatever still has no price returns null, and the caller sends it down the existing ladder, which never invents a
// number: an honest, visible zero stays the last resort, not the first.
import { priceItem, type ResolvedItem } from "./food-resolver.ts"
import { AI_PRICING_SYSTEM, parsePer100, priceFromPer100, roundPortion, type Per100 } from "./ai-pricing.ts"

export type SovereignTarget = { base: string; key: string; model: string }

export type ReferenceAnswer = {
  notFood: boolean
  /** USDA SR Legacy-style description of a single food, or null for a mix. */
  refName: string | null
  /** Weight fractions summing to 1, for a mix or a dish. */
  components: Array<{ refName: string; fraction: number }> | null
  /** kcal per 100 g of the food AS EATEN — the energy check, and the decomposition's sanity check. */
  kcalPer100: number | null
}

export const REFERENCE_SYSTEM = `You map foods to the USDA SR Legacy and CIQUAL food-composition tables.
The user lists foods as eaten, numbered. For EACH food return one object:
"i": its number;
"ref": a USDA SR Legacy-style description of the food as eaten — "Food, descriptor, state" — for example "Seeds, chia seeds, dried", "Nuts, walnuts, english", "Rice, white, long-grain, cooked", "Milk, whole", "Cheese, parmesan, grated", "Pork, shoulder, cooked"; or null when the food is a mix or a dish;
"parts": null for a single food; for a mix or a dish (for example "chia seeds soaked in milk", "tortellini soup", "vegetable stir-fry") a list of 2 to 6 objects {"ref": USDA-style description of the ingredient as eaten, "fraction": its share of the WEIGHT}, fractions summing to 1;
"kcal": typical kcal per 100 g of the food as eaten (the whole mix for a dish);
"not_food": true only when the name is not a food at all.
Return ONLY a JSON object {"foods": [ ... ]} with one object per food, in order.`

const num = (v: unknown): number | null => {
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v
  return typeof n === "number" && Number.isFinite(n) ? n : null
}

const cleanRef = (v: unknown): string | null => {
  if (typeof v !== "string") return null
  const s = v.replace(/\s+/g, " ").trim()
  return s.length >= 2 && s.length <= 120 ? s : null
}

export function stripFences(s: string): string {
  return s.replace(/^\s*```(?:json)?/i, "").replace(/```\s*$/i, "").trim()
}

/** The batch answer, checked; one entry per food in order, null where the model gave nothing usable. */
export function parseReferences(content: string, n: number): Array<ReferenceAnswer | null> {
  const out: Array<ReferenceAnswer | null> = Array.from({ length: n }, () => null)
  let raw: unknown
  try {
    raw = JSON.parse(stripFences(content))
  } catch {
    return out
  }
  const list = Array.isArray(raw) ? raw : (raw as { foods?: unknown })?.foods
  if (!Array.isArray(list)) return out
  list.forEach((entry, pos) => {
    if (!entry || typeof entry !== "object") return
    const o = entry as Record<string, unknown>
    const i = num(o.i)
    const idx = i !== null && Number.isInteger(i) && i >= 1 && i <= n ? i - 1 : pos
    if (idx < 0 || idx >= n || out[idx]) return
    if (o.not_food === true) {
      out[idx] = { notFood: true, refName: null, components: null, kcalPer100: null }
      return
    }
    const kcal = num(o.kcal)
    const kcalPer100 = kcal !== null && kcal >= 0 && kcal <= 902 ? kcal : null
    let components: ReferenceAnswer["components"] = null
    if (Array.isArray(o.parts) && o.parts.length >= 2 && o.parts.length <= 6) {
      const parts = o.parts.map((p) => {
        const q = (p ?? {}) as Record<string, unknown>
        return { refName: cleanRef(q.ref), fraction: num(q.fraction) }
      })
      const total = parts.reduce((a, p) => a + (p.fraction ?? 0), 0)
      const valid = parts.every((p) => p.refName && p.fraction !== null && p.fraction > 0)
      // Fractions that do not roughly sum to 1 are not a recipe; normalising a 0.3 total would invent the rest.
      if (valid && total >= 0.8 && total <= 1.25) {
        components = parts.map((p) => ({ refName: p.refName as string, fraction: (p.fraction as number) / total }))
      }
    }
    const refName = components ? null : cleanRef(o.ref)
    if (!refName && !components && kcalPer100 === null) return
    out[idx] = { notFood: false, refName, components, kcalPer100 }
  })
  return out
}

// ---------------------------------------------------------------------------
// Choosing a reference row — pure, so every gate is tested
// ---------------------------------------------------------------------------

const singular = (t: string): string => {
  if (t.length <= 3) return t
  if (t.endsWith("ies")) return `${t.slice(0, -3)}y`
  if (t.endsWith("oes")) return t.slice(0, -2)
  if (t.endsWith("ses") || t.endsWith("xes") || t.endsWith("zes") || t.endsWith("ches") || t.endsWith("shes")) return t.slice(0, -2)
  if (t.endsWith("s") && !t.endsWith("ss") && !t.endsWith("us")) return t.slice(0, -1)
  return t
}
const words = (s: string): string[] =>
  s.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "").split(/[^a-z0-9]+/).filter(Boolean).map(singular)

/** Descriptors: how a food is prepared or sold, not what it is. Never required, never enough. */
const DESCRIPTORS = new Set([
  "raw", "cooked", "fresh", "dried", "dry", "plain", "whole", "unsweetened", "sweetened", "salted", "unsalted",
  "boiled", "baked", "roasted", "grilled", "fried", "steamed", "braised", "stewed", "poached", "sauteed", "toasted",
  "canned", "frozen", "prepared", "regular", "low", "lowfat", "nonfat", "fat", "free", "reduced", "skim", "light",
  "homemade", "organic", "natural", "ground", "sliced", "chopped", "grated", "shredded", "with", "without", "and",
  "or", "in", "of", "from", "ready", "to", "eat", "drink", "mature", "commercial", "generic", "type", "style", "all",
  "variety", "enriched", "unenriched", "added", "salt", "water",
].map(singular))

const COOKED = new Set(["cooked", "boiled", "baked", "roasted", "grilled", "fried", "steamed", "braised", "stewed",
  "poached", "sauteed", "microwaved", "simmered", "broiled", "toasted"].map(singular))

/** The words a matching row must contain: every food word of the first segment, and the first food word of the
 *  second ("Seeds, chia seeds, dried" → seed + chia; "Kefir, plain" → kefir; "Pork, shoulder" → pork + shoulder). */
export function requiredWords(refName: string): string[] {
  const [first = "", second = ""] = refName.split(",")
  const req = words(first).filter((w) => !DESCRIPTORS.has(w))
  const next = words(second).find((w) => !DESCRIPTORS.has(w))
  if (next && !req.includes(next)) req.push(next)
  return req
}

/** Raw versus cooked disagree: a braised pork shoulder is not priced from the raw row, nor the reverse. */
export function stateConflict(refName: string, candidateName: string): boolean {
  const ref = words(refName), cand = words(candidateName)
  const refCooked = ref.some((w) => COOKED.has(w)), candCooked = cand.some((w) => COOKED.has(w))
  const refRaw = ref.includes("raw") || ref.includes("uncooked"), candRaw = cand.includes("raw") || cand.includes("uncooked")
  return (refCooked && candRaw && !candCooked) || (refRaw && candCooked && !candRaw)
}

/** Energy density within the band, the +25 floor keeping it meaningful near zero (water, broth, black coffee). */
export const ENERGY_BAND = 1.6
export function energyClose(expectedKcal: number | null, rowKcal: number | null): boolean {
  if (expectedKcal === null || rowKcal === null) return true
  const ratio = (rowKcal + 25) / (expectedKcal + 25)
  return ratio <= ENERGY_BAND && ratio >= 1 / ENERGY_BAND
}

export type Candidate = { term: string; id: string; name: string; energy_kcal: number | string | null; sim: number }

/** First candidate, in the database's ranking, that passes every gate. Null: the database cannot price this name. */
export function chooseCandidate(refName: string, ranked: Candidate[], expectedKcal: number | null, minSim = 0.4): Candidate | null {
  const req = requiredWords(refName)
  if (!req.length) return null
  for (const c of ranked) {
    if (!(c.sim >= minSim)) continue
    const have = new Set(words(c.name))
    if (!req.every((w) => have.has(w))) continue
    if (stateConflict(refName, c.name)) continue
    if (!energyClose(expectedKcal, num(c.energy_kcal))) continue
    return c
  }
  return null
}

// ---------------------------------------------------------------------------
// Pricing from the chosen rows
// ---------------------------------------------------------------------------

/** A mix priced component by component, each at a 100 g base then scaled (the resolver's conservation-of-mass rule). */
export function priceDecomposed(
  name: string,
  grams: number,
  parts: Array<{ row: Record<string, unknown>; fraction: number }>,
): ResolvedItem {
  const priced = parts.map((p) => priceItem(p.row, 100, { basis: "matched", foodItemId: String(p.row.id ?? "") || null }))
  const share = (i: number) => (grams * parts[i].fraction) / 100
  const sum = (f: (it: ResolvedItem) => number) => priced.reduce((a, it, i) => a + f(it) * share(i), 0)
  const micros: Record<string, number | null> = {}
  priced.forEach((it, i) => {
    for (const [k, v] of Object.entries(it.micros)) {
      if (v === null) {
        if (!(k in micros)) micros[k] = null
        continue
      }
      micros[k] = (micros[k] ?? 0) + v * share(i)
    }
  })
  return {
    name,
    local_name: null,
    category: null,
    estimated_grams: roundPortion(grams),
    kcal: sum((i) => i.kcal),
    protein_g: sum((i) => i.protein_g),
    carbs_g: sum((i) => i.carbs_g),
    fat_g: sum((i) => i.fat_g),
    fiber_g: sum((i) => i.fiber_g),
    micros,
    basis: "decomposed",
    food_item_id: null,
    components: priced.map((it, i) => ({
      name: it.name,
      grams: grams * parts[i].fraction,
      kcal: it.kcal * share(i),
      fraction: parts[i].fraction,
      food_item_id: it.food_item_id,
    })),
  }
}

// ---------------------------------------------------------------------------
// The calls
// ---------------------------------------------------------------------------

type CallOpts = { timeoutMs?: number; fetchImpl?: typeof fetch }

/** One chat call to an Infomaniak model. The text of the answer, or null on any failure (status, timeout, shape). */
async function chat(t: SovereignTarget, system: string, user: string, opts: CallOpts): Promise<string | null> {
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort(), opts.timeoutMs ?? 15_000)
  try {
    const r = await (opts.fetchImpl ?? fetch)(`${t.base}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${t.key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: t.model,
        messages: [{ role: "system", content: system }, { role: "user", content: user }],
        temperature: 0,
        stream: false,
        // Qwen 3.8 thinks by default; the JSON must land in message.content.
        reasoning_effort: "none",
      }),
      signal: ac.signal,
    })
    const text = await r.text()
    if (!r.ok) {
      console.warn(`[sovereign-pricing] ${t.model} HTTP ${r.status}`)
      return null
    }
    const msg = (JSON.parse(text) as { choices?: Array<{ message?: { content?: string; reasoning?: string } }> }).choices?.[0]?.message
    const content = typeof msg?.content === "string" && msg.content.trim() ? msg.content : msg?.reasoning
    return typeof content === "string" ? content : null
  } catch (e) {
    console.warn(`[sovereign-pricing] ${t.model} failed: ${e instanceof Error ? e.name : "error"}`)
    return null
  } finally {
    clearTimeout(timer)
  }
}

/** Step A for all the meal's distinct foods, the second model taking over when the first gives nothing usable. */
export async function askReferences(
  names: string[],
  targets: SovereignTarget[],
  opts: CallOpts = {},
): Promise<{ answers: Array<ReferenceAnswer | null>; model: string | null }> {
  const user = names.map((n, i) => `${i + 1}. ${n}`).join("\n")
  for (const t of targets) {
    const content = await chat(t, REFERENCE_SYSTEM, user, opts)
    if (content === null) continue
    const answers = parseReferences(content, names.length)
    if (answers.some((a) => a !== null)) return { answers, model: t.model }
  }
  return { answers: names.map(() => null), model: null }
}

/** Step C for one food: the full per-100 g estimate (the OpenAI prompt, now answered in Geneva). */
export async function askPer100Sovereign(name: string, targets: SovereignTarget[], opts: CallOpts = {}): Promise<Per100 | null> {
  for (const t of targets) {
    const content = await chat(t, AI_PRICING_SYSTEM, name, opts)
    if (content === null) continue
    const m = stripFences(content).match(/\{[\s\S]*\}/)
    const parsed = parsePer100(m ? m[0] : content)
    if (parsed === "not_food") return null
    if (parsed) return parsed
  }
  return null
}

/** The database calls this module needs — injected, so the tests run without a database. */
export type ReferenceDb = {
  candidates(terms: string[]): Promise<Candidate[]>
  rows(ids: string[]): Promise<Array<Record<string, unknown>>>
}

export type SovereignCounts = { matched: number; decomposed: number; ai: number; unpriced: number }

/**
 * Price the given foods sovereignly, in order. A null is a food this path could not price: the caller sends it down
 * the resolver's ladder. `model` is the Infomaniak model that answered step A (null when none did).
 */
export async function priceSovereign(
  items: Array<{ name: string; grams: number }>,
  targets: SovereignTarget[],
  db: ReferenceDb,
  opts: CallOpts = {},
): Promise<{ resolved: Array<ResolvedItem | null>; model: string | null; counts: SovereignCounts }> {
  const counts: SovereignCounts = { matched: 0, decomposed: 0, ai: 0, unpriced: 0 }
  const keyOf = (n: string) => n.trim().toLowerCase()
  const names = [...new Set(items.map((it) => keyOf(it.name)).filter(Boolean))]
  if (!names.length || !targets.length) {
    counts.unpriced = items.length
    return { resolved: items.map(() => null), model: null, counts }
  }

  // A — what each food is.
  const { answers, model } = await askReferences(names, targets, opts)
  const answerOf = new Map(names.map((n, i) => [n, answers[i]]))

  // B — ranked candidates for every description in one round trip, then the full rows of the chosen ones.
  const terms = new Set<string>()
  for (const a of answers) {
    if (!a || a.notFood) continue
    if (a.refName) terms.add(a.refName)
    for (const c of a.components ?? []) terms.add(c.refName)
  }
  const byTerm = new Map<string, Candidate[]>()
  if (terms.size) {
    try {
      for (const c of await db.candidates([...terms])) {
        const list = byTerm.get(c.term) ?? []
        list.push(c)
        byTerm.set(c.term, list)
      }
    } catch (e) {
      console.warn(`[sovereign-pricing] reference lookup failed: ${e instanceof Error ? e.message : "error"}`)
    }
  }
  type Plan = { single?: Candidate; parts?: Array<{ c: Candidate; fraction: number }> }
  const plan = new Map<string, Plan>()
  for (const [n, a] of answerOf) {
    if (!a || a.notFood) continue
    if (a.refName) {
      const c = chooseCandidate(a.refName, byTerm.get(a.refName) ?? [], a.kcalPer100)
      if (c) plan.set(n, { single: c })
    } else if (a.components) {
      // A component has no energy of its own to check against, so its name must match more strictly.
      const parts = a.components.map((p) => ({ c: chooseCandidate(p.refName, byTerm.get(p.refName) ?? [], null, 0.5), fraction: p.fraction }))
      if (parts.every((p) => p.c)) plan.set(n, { parts: parts as Array<{ c: Candidate; fraction: number }> })
    }
  }
  const ids = new Set<string>()
  for (const p of plan.values()) {
    if (p.single) ids.add(p.single.id)
    for (const part of p.parts ?? []) ids.add(part.c.id)
  }
  const rowById = new Map<string, Record<string, unknown>>()
  if (ids.size) {
    try {
      for (const r of await db.rows([...ids])) rowById.set(String(r.id), r)
    } catch (e) {
      console.warn(`[sovereign-pricing] reference rows failed: ${e instanceof Error ? e.message : "error"}`)
    }
  }

  // C — a full estimate only for the foods the table could not price, in parallel.
  const priceOne = (n: string, grams: number): ResolvedItem | null => {
    const p = plan.get(n)
    if (p?.single) {
      const row = rowById.get(p.single.id)
      if (row) return priceItem(row, grams, { basis: "matched", foodItemId: p.single.id })
    }
    if (p?.parts) {
      const rows = p.parts.map((part) => ({ row: rowById.get(part.c.id), fraction: part.fraction }))
      if (rows.every((r) => r.row)) {
        const item = priceDecomposed(n, grams, rows as Array<{ row: Record<string, unknown>; fraction: number }>)
        // The parts must add up to roughly what the whole is: a recipe guess that lands far off is not used.
        const expected = answerOf.get(n)?.kcalPer100 ?? null
        const g = roundPortion(grams)
        if (g === 0 || energyClose(expected, (item.kcal / g) * 100)) return item
      }
    }
    return null
  }
  const missing = names.filter((n) => !answerOf.get(n)?.notFood && !priceOne(n, 100))
  const per100 = new Map<string, Per100 | null>()
  await Promise.all(missing.map(async (n) => per100.set(n, await askPer100Sovereign(n, targets, opts))))

  const resolved = items.map((it) => {
    const n = keyOf(it.name)
    const fromTable = priceOne(n, it.grams)
    if (fromTable) {
      counts[fromTable.basis === "decomposed" ? "decomposed" : "matched"]++
      return { ...fromTable, name: it.name }
    }
    const est = per100.get(n)
    if (est) {
      counts.ai++
      return priceFromPer100(it.name, it.grams, est)
    }
    counts.unpriced++
    return null
  })
  return { resolved, model, counts }
}
