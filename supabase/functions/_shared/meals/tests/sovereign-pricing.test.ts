// The sovereign pricing (sovereign-pricing.ts): what the Infomaniak answer is allowed to say, which reference rows are
// accepted, and that a whole meal is priced from USDA / CIQUAL rows without a single call leaving for OpenAI.
// The candidate lists below are what match_food_reference returned on the live table on 2026-11-10.
import { assert, assertEquals } from "jsr:@std/assert@1"
import {
  chooseCandidate,
  energyClose,
  parseReferences,
  priceSovereign,
  requiredWords,
  stateConflict,
  type Candidate,
  type ReferenceDb,
  type SovereignTarget,
} from "../sovereign-pricing.ts"

const cand = (term: string, name: string, kcal: number, sim: number, id = name): Candidate => ({ term, id, name, energy_kcal: kcal, sim })

Deno.test("parseReferences: one entry per food, in order; fences tolerated; mixes normalised; junk refused", () => {
  const content = "```json\n" + JSON.stringify({
    foods: [
      { i: 2, ref: "Nuts, walnuts, english", parts: null, kcal: 654 },
      { i: 1, ref: null, parts: [{ ref: "Seeds, chia seeds, dried", fraction: 0.2 }, { ref: "Milk, whole", fraction: 0.8 }], kcal: 150 },
      { i: 3, not_food: true },
      { i: 4, ref: null, parts: [{ ref: "Rice, white, cooked", fraction: 0.1 }, { ref: "Butter", fraction: 0.1 }], kcal: 200 },
    ],
  }) + "\n```"
  const out = parseReferences(content, 5)
  assertEquals(out[1], { notFood: false, refName: "Nuts, walnuts, english", components: null, kcalPer100: 654 })
  assertEquals(out[0]?.components?.map((c) => c.refName), ["Seeds, chia seeds, dried", "Milk, whole"])
  assertEquals(out[0]?.refName, null)
  assertEquals(out[2]?.notFood, true)
  // Fractions summing to 0.2 are not a recipe: the parts are dropped, the kcal kept.
  assertEquals(out[3], { notFood: false, refName: null, components: null, kcalPer100: 200 })
  assertEquals(out[4], null)
  assertEquals(parseReferences("not json", 2), [null, null])
})

Deno.test("requiredWords: the food words a row must contain, never the descriptors", () => {
  assertEquals(requiredWords("Seeds, chia seeds, dried"), ["seed", "chia"])
  assertEquals(requiredWords("Kefir, plain"), ["kefir"])
  assertEquals(requiredWords("Milk, whole"), ["milk"])
  assertEquals(requiredWords("Pork, shoulder, braised"), ["pork", "shoulder"])
  assertEquals(requiredWords("Honey"), ["honey"])
})

Deno.test("stateConflict and energyClose", () => {
  assert(stateConflict("Pork, shoulder, braised", "Pork shoulder, raw"))
  assert(!stateConflict("Pork, shoulder, braised", "Pork, shoulder, cooked"))
  assert(stateConflict("Fennel, bulb, raw", "Fennel, boiled/cooked in water"))
  assert(!stateConflict("Milk, whole", "Milk, whole, UHT"))
  assert(energyClose(486, 442))
  assert(!energyClose(150, 486)) // chia pudding is not dried chia
  assert(!energyClose(15, 185)) // broth is not canned chicken
  assert(energyClose(null, 900))
})

Deno.test("chooseCandidate on live candidates: the right row, or none", () => {
  const chia = [cand("Seeds, chia seeds, dried", "Seeds, chia, dried", 442, 1), cand("x", "Seeds, chia seeds, dried", 486, 1)]
  assertEquals(chooseCandidate("Seeds, chia seeds, dried", chia, 486)?.name, "Seeds, chia, dried")

  const broth = [cand("b", "Chicken, canned, no broth", 185, 0.61), cand("b", "Soup, chicken broth cubes, dry", 198, 0.5)]
  assertEquals(chooseCandidate("Broth, chicken", broth, 15), null)

  const pork = [cand("p", "Brain, pork, braised", 174, 0.54), cand("p", "Pork shoulder, raw", 208, 0.54), cand("p", "Pork, shoulder, cooked", 253, 0.5)]
  assertEquals(chooseCandidate("Pork, shoulder, braised", pork, 240)?.name, "Pork, shoulder, cooked")

  const oatMilk = [cand("o", "Oil, oat", 884, 0.33), cand("o", "Goat milk, whole, UHT", 56, 0.32)]
  assertEquals(chooseCandidate("Milk, oat", oatMilk, 45), null)

  const honey = [cand("h", "Honey", 304, 1), cand("h", "Ham, honey, smoked, cooked", 122, 0.3)]
  assertEquals(chooseCandidate("Honey", honey, 304)?.name, "Honey")

  const kefir = [cand("k", "Kefir", 62, 0.5), cand("k", "Tofu, plain", 148, 0.35)]
  assertEquals(chooseCandidate("Kefir, plain", kefir, 60)?.name, "Kefir")
})

// ── end to end, with a fake Infomaniak and a fake reference table ──────────────────────────────────────────────────

const row = (id: string, name: string, kcal: number, p: number, c: number, f: number, extra: Record<string, number | null> = {}) => ({
  id, name, name_fr: null, category: "Test", energy_kcal: kcal, protein_g: p, carbs_g: c, fat_g: f, fiber_g: 0,
  calcium_mg: null, ...extra,
})
const TABLE = [
  row("chia", "Seeds, chia seeds, dried", 486, 17, 42, 31, { calcium_mg: 631 }),
  row("milk", "Milk, whole, UHT", 65, 3.3, 4.8, 3.6, { calcium_mg: 120 }),
  row("walnut", "Nuts, walnuts, english", 654, 15, 14, 65),
  // In the table on purpose: the energy check, not a missing row, is what keeps broth off it.
  row("canned", "Chicken, canned, no broth", 185, 25, 0, 8),
]
const CANDIDATES: Record<string, Candidate[]> = {
  "Seeds, chia seeds, dried": [cand("Seeds, chia seeds, dried", "Seeds, chia seeds, dried", 486, 1, "chia")],
  "Milk, whole": [cand("Milk, whole", "Milk, whole, UHT", 65, 0.73, "milk")],
  "Nuts, walnuts, english": [cand("Nuts, walnuts, english", "Nuts, walnuts, english", 654, 1, "walnut")],
  "Broth, chicken": [cand("Broth, chicken", "Chicken, canned, no broth", 185, 0.61, "canned")],
}
const fakeDb = (): ReferenceDb & { asked: string[][] } => {
  const asked: string[][] = []
  return {
    asked,
    async candidates(terms) {
      asked.push(terms)
      return terms.flatMap((t) => CANDIDATES[t] ?? [])
    },
    async rows(ids) {
      return TABLE.filter((r) => ids.includes(r.id))
    },
  }
}

const REFS = {
  foods: [
    { i: 1, ref: null, parts: [{ ref: "Seeds, chia seeds, dried", fraction: 0.2 }, { ref: "Milk, whole", fraction: 0.8 }], kcal: 150 },
    { i: 2, ref: "Nuts, walnuts, english", parts: null, kcal: 654 },
    { i: 3, ref: "Broth, chicken", parts: null, kcal: 15 },
  ],
}
const BROTH_PER100 = { name_fr: "Bouillon de poule", category: "Soups, Sauces, and Gravies", energy_kcal: 15, protein_g: 1.5, carbs_g: 1, fat_g: 0.5, fiber_g: 0 }

const IK = "https://api.infomaniak.com/2/ai/108797/openai/v1"
const TARGETS: SovereignTarget[] = [
  { base: IK, key: "ik", model: "Qwen/Qwen3.8-27B-FP8" },
  { base: IK, key: "ik", model: "google/gemma-4-31B-it" },
]

function fakeInfomaniak(opts: { firstModelDown?: boolean } = {}) {
  const calls: Array<{ url: string; model: string; system: string }> = []
  const impl = (async (url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body))
    calls.push({ url: String(url), model: body.model, system: body.messages[0].content })
    if (opts.firstModelDown && body.model === "Qwen/Qwen3.8-27B-FP8") return new Response("busy", { status: 429 })
    const isReference = String(body.messages[0].content).includes("USDA SR Legacy and CIQUAL")
    const content = isReference ? JSON.stringify(REFS) : JSON.stringify(BROTH_PER100)
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 })
  }) as typeof fetch
  return { calls, impl }
}

const ITEMS = [
  { name: "chia seeds soaked in milk", grams: 150 },
  { name: "raw walnut halves", grams: 20 },
  { name: "chicken broth", grams: 300 },
]

Deno.test("priceSovereign: Barbara's chia pudding from the table, walnuts from the table, broth estimated — never zero, never OpenAI", async () => {
  const ik = fakeInfomaniak()
  const db = fakeDb()
  const { resolved, model, counts } = await priceSovereign(ITEMS, TARGETS, db, { fetchImpl: ik.impl })

  assertEquals(model, "Qwen/Qwen3.8-27B-FP8")
  assertEquals(counts, { matched: 1, decomposed: 1, ai: 1, unpriced: 0 })
  assert(ik.calls.every((c) => c.url.startsWith("https://api.infomaniak.com/")))
  assertEquals(db.asked.length, 1) // one round trip for every description

  const [pudding, walnuts, broth] = resolved
  assertEquals(pudding?.basis, "decomposed")
  assertEquals(pudding?.name, "chia seeds soaked in milk")
  // 30 g chia (146 kcal) + 120 g milk (78 kcal) = 224 kcal — not the 36 the zero-fallback wrote.
  assertEquals(Math.round(pudding?.kcal ?? 0), 224)
  assertEquals(pudding?.components?.map((c) => c.food_item_id), ["chia", "milk"])
  assertEquals(Math.round(pudding?.micros.calcium_mg ?? 0), 333) // 189 + 144: the table's micros, carried
  assertEquals(walnuts?.basis, "matched")
  assertEquals(walnuts?.food_item_id, "walnut")
  assertEquals(Math.round(walnuts?.kcal ?? 0), 131)
  assertEquals(broth?.basis, "ai") // "Chicken, canned, no broth" refused by the energy check
  assertEquals(Math.round(broth?.kcal ?? 0), 45)
})

Deno.test("priceSovereign: the second Infomaniak model answers when the first is rate-limited", async () => {
  const ik = fakeInfomaniak({ firstModelDown: true })
  const { model, counts } = await priceSovereign(ITEMS, TARGETS, fakeDb(), { fetchImpl: ik.impl })
  assertEquals(model, "google/gemma-4-31B-it")
  assertEquals(counts.unpriced, 0)
})

Deno.test("priceSovereign: no answer anywhere hands every food back to the ladder (null), never a zero", async () => {
  const down = (async () => new Response("down", { status: 503 })) as typeof fetch
  const { resolved, counts } = await priceSovereign(ITEMS, TARGETS, fakeDb(), { fetchImpl: down })
  assertEquals(resolved, [null, null, null])
  assertEquals(counts.unpriced, 3)
})

Deno.test("priceSovereign: a table failure falls to the estimate, not to zero", async () => {
  const ik = fakeInfomaniak()
  const broken: ReferenceDb = {
    candidates: () => Promise.reject(new Error("boom")),
    rows: () => Promise.resolve([]),
  }
  const { resolved, counts } = await priceSovereign([{ name: "chicken broth", grams: 300 }], TARGETS, broken, { fetchImpl: ik.impl })
  assertEquals(resolved[0]?.basis, "ai")
  assertEquals(counts.ai, 1)
})
