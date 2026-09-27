// food-resolver — the deterministic pricing ladder, shared by TWO edge
// functions: `resolve-foods` (the standalone endpoint) and `analyze-meal`
// (the patient capture path).
//
// It turns ingredient names into priced items. Every returned item carries a
// `basis` saying how it was priced.
//
//   Tier 0a  patient default    -> basis 'learned'    (this patient corrected it)
//   Tier 0b  curated alias      -> basis 'exact'
//   Tier 0c  curated recipe     -> basis 'decomposed'
//   Tier 1   hybrid retrieval   -> basis 'matched'
//   Tier 2   branded products   -> basis 'matched'    (Open Food Facts plane)
//   Tier 4   TERMINAL           -> basis 'estimated', ZERO macros, flagged red
//
// The three 0-tiers are all HAND-WRITTEN decisions about what a name means, so
// they rank together and ahead of retrieval. Curated decomposition sat behind
// Tier 1 in v10 and lost 'mixed nuts' to a generic row containing PEANUTS.
//
// Tier 0a ranks ahead of even the curated alias, because a correction from the
// person who ate the food outranks a curator's default for everybody. It is also
// the only tier that gets FASTER with use: a hit skips the embedding call and
// both retrieval RPCs entirely.
//
// THE GUARANTEE (revised 2026-07-28): this function always returns an ITEM, and
// never invents a number for one it could not identify.
//
// It used to always return a PRICED item, falling back to a category median.
// A held-out run over unseen patients showed that median doing real damage:
// 550 g of "mixed berries" priced from the Breakfast Cereals median fabricated
// ~2,040 kcal, and whey protein from the Baked Products median carried 8 g
// protein/100 g against a real ~80. A category median is a confirmation the
// system gives itself.
//
// So an unidentified ingredient now comes back with zero macros and
// needs_review/red. The meal total understates — VISIBLY — and a human closes
// the gap through the correction loop or the clinical lookup queue.
//
// This is not a return to the original bug. That bug was a SILENT zero, with
// nothing recording that an ingredient had gone unpriced, so a real meal read
// 220 kcal and looked like a snack. The difference between then and now is
// entirely in whether anyone can tell.
//
// CODE DUPLICATION IS DELIBERATE HERE. Edge functions run in Deno and cannot
// import from `lib/`, which is a React-Native/Node tree. The pure modules are
// therefore inlined below, exactly as `generate-report` inlines
// `wearable-report-block.ts` — the established pattern in this repo. The `lib/`
// copies are the TESTED source of truth; when one changes, both change.
//
// Sovereignty: the query embedding is produced by `Supabase.ai` INSIDE the Edge
// Runtime. No text leaves Supabase, so no external provider is involved at all.
// The caller passes the session in, so this module never touches a global and
// stays importable from any function bundle.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ---------------------------------------------------------------------------
// Inlined from lib/nutrition/resolve/types.ts
// ---------------------------------------------------------------------------
export type Basis = 'exact' | 'learned' | 'matched' | 'decomposed' | 'estimated' | 'unknown'
export type ReviewReason = 'not_found' | 'not_a_food' | 'low_confidence'
export type ReviewSeverity = 'red' | 'orange'

export type ResolvedItem = {
  name: string
  local_name: string | null
  // The reference row's own food category (nb_food_items.category, 100% populated
  // across both taxonomies — USDA title-case "Vegetables and Vegetable Products",
  // CIQUAL lowercase "fruits, vegetables, legumes and nuts"). Carried so meal
  // scoring classifies foods from DATA rather than guessing from the name; the
  // engine it replaced read `name.includes('oat')` and scored goat cheese as oats.
  // null when the item was never matched to a reference row.
  category: string | null
  estimated_grams: number
  kcal: number
  protein_g: number
  carbs_g: number
  fat_g: number
  fiber_g: number
  micros: Record<string, number | null>
  basis: Basis
  food_item_id: string | null
  alternatives?: string[]
  // Present only on a decomposed item: what it was broken into, so the review
  // surface can show the recipe and a clinician can correct a component rather
  // than the whole entry.
  components?: Array<{ name: string; grams: number; kcal: number; fraction: number; food_item_id: string | null }>
  needs_review?: boolean
  review_reason?: ReviewReason
  review_severity?: ReviewSeverity
}

// ---------------------------------------------------------------------------
// Inlined from lib/nutrition/resolve/normalise.ts (tested there, not here)
// ---------------------------------------------------------------------------
const PREPARATION = new Set([
  'raw', 'fresh', 'frozen', 'canned', 'dried', 'dry',
  'cooked', 'uncooked', 'boiled', 'baked', 'roasted', 'roast', 'grilled',
  'fried', 'sauteed', 'sautéed', 'steamed', 'poached', 'braised', 'toasted',
  'melted', 'marinated', 'smoked', 'cured', 'caramelized', 'caramelised',
  'chopped', 'sliced', 'diced', 'minced', 'shredded', 'grated', 'crushed',
  'mixed', 'whole', 'halved', 'peeled', 'unpeeled',
  'homemade', 'organic', 'plain', 'natural',
  'creamy', 'crispy', 'crunchy', 'soft', 'hard',
  'hot', 'cold', 'warm', 'drizzle', 'topping', 'garnish',
  'cru', 'crue', 'cuit', 'cuite', 'frais', 'fraiche', 'fraîche',
  'grille', 'grillee', 'grillée', 'grillé', 'roti', 'rotie', 'rôti', 'rôtie',
  'surgele', 'surgelee', 'surgelé', 'surgelée', 'maison', 'nature',
])

// No stem-length guard: the live table holds "Oat, raw" and "Egg, whole,
// cooked, poached", both SINGULAR. The guard it replaced protected nothing real
// and stopped `eggs` resolving at all.
const singular = (t: string): string => {
  if (t.length <= 3) return t
  if (t.endsWith('ies')) return `${t.slice(0, -3)}y`
  if (t.endsWith('oes')) return t.slice(0, -2)
  if (t.endsWith('ses') || t.endsWith('xes') || t.endsWith('zes')) return t.slice(0, -2)
  if (t.endsWith('s') && !t.endsWith('ss') && !t.endsWith('us')) return t.slice(0, -1)
  return t
}

// Shared by normalise() and by the curated recipe lookup — lib/ carries an
// identical copy in each module; here one definition serves both.
const clean = (s: string): string =>
  s.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim()

function reduceTerm(raw: string): string {
  const kept = clean(raw).split(' ').filter((t) => t && !PREPARATION.has(t)).map(singular)
  return kept.length ? kept.join(' ') : clean(raw).split(' ').map(singular).join(' ')
}

function normalise(raw: string): { core: string; alternatives: string[] } {
  const alternatives: string[] = []
  let head = raw
  const paren = raw.match(/^([^(]+)\(([^)]+)\)/)
  if (paren) {
    head = paren[1]
    const gloss = reduceTerm(paren[2])
    if (gloss) alternatives.push(gloss)
  }
  const parts = head.split('/').map((p) => p.trim()).filter(Boolean)
  const core = reduceTerm(parts[0] ?? head)
  for (const p of parts.slice(1)) {
    const alt = reduceTerm(p)
    if (alt) alternatives.push(alt)
  }
  // Some preparation words are part of the food's IDENTITY: "roast beef" is its
  // own catalogued row with its own composition, and reducing it to "beef"
  // throws that away. Keep both readings and let retrieval pick the better.
  const unstripped = clean(parts[0] ?? head).split(' ').map(singular).join(' ')
  if (unstripped && unstripped !== core) alternatives.push(unstripped)

  return { core, alternatives }
}

// ---------------------------------------------------------------------------
// Inlined from lib/nutrition/resolve/fuse.ts
// ---------------------------------------------------------------------------
type Candidate = {
  id: string; name: string; name_fr: string | null; category: string | null
  source: string; vecSim: number; lexSim: number; wordSim: number
}

// A branded product from Open Food Facts. Separate from Candidate because it
// carries no vector score — branded lookup is literal, so retrieval is trigram
// and FTS only — and because it carries a trust signal that generic reference
// rows do not need.
type ProductCandidate = {
  id: string
  name: string
  brand: string | null
  lexSim: number
  wordSim: number
  // OFF's own 0..1 completeness. Crowd-sourced data varies enormously in
  // quality and a half-filled row should not win on name alone.
  completeness: number | null
}

const PRESENCE_FLOOR = 0.55
const AGREEMENT_WEIGHT = 0.15
const DEFAULT_TAU = 0.70

// A candidate the LEXICAL arm never saw is held to a much higher bar, because a
// plain cosine score cannot be trusted alone: gte-small returns a nearest
// neighbour for ANY input and its similarities sit compressed in a high band,
// so "confidently wrong" and "correct" are not separable by score. Smoke-testing
// v1 of this function produced three vector-only candidates that each outranked
// the right answer:
//   "myrtilles"               -> Mushrooms, Chanterelle, raw
//   "marinated salmon/tuna"   -> Fish oil, salmon  (1082 kcal/120 g vs ~250)
//   "zzqqxx nonexistent food" -> Quail, meat only, raw
const VECTOR_ONLY_TAU = 0.95

// Both CIQUAL and USDA name foods HEAD-FIRST: the first token is what the food
// IS, everything after qualifies. "Jam, blueberry" is a jam; "Fish oil, salmon"
// is an oil; "Blueberry, raw" is a blueberry. Without this signal the fused
// scores for Fish-oil-salmon (0.929/0.438) and Salmon-raw (0.934/0.389) sit
// within 0.005 of each other, which is noise — the resolver would pick salmon
// OIL over salmon FILLET by coin-flip, at 900 kcal/100 g against 200.
const HEAD_MATCH_BONUS = 0.25

// The two naming conventions run in OPPOSITE directions, which is the trick:
//   English compounds are HEAD-FINAL  — "roast beef" is a beef, "goat cheese"
//                                       is a cheese, "cherry tomato" a tomato.
//   Food catalogues are HEAD-INITIAL  — "Beef, roast beef, roasted/baked".
// So the query's LAST token is compared to the candidate's FIRST. Matching
// first-to-first gave "roast beef" the bonus on "Roast beef SPREAD", a pate,
// over the real roast beef row — the head noun is "beef", not "roast".
const tokens = (s: string): string[] =>
  s.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').trim().split(/\s+/).filter(Boolean)

const headMatches = (c: Candidate, query: string): boolean => {
  const q = tokens(query)
  const head = q[q.length - 1]
  if (!head) return false
  const nameHead = (x: string) => tokens(x)[0] ?? ''
  return nameHead(c.name).startsWith(head) || nameHead(c.name_fr ?? '').startsWith(head)
}

const lexicalScore = (c: Candidate): number =>
  c.wordSim <= 0 ? 0 : c.wordSim * (PRESENCE_FLOOR + (1 - PRESENCE_FLOOR) * c.lexSim)

function bestMatch(candidates: Candidate[], query: string, tau = DEFAULT_TAU): (Candidate & { score: number }) | null {
  const [top] = candidates
    .map((c) => {
      const lex = lexicalScore(c)
      const strongest = Math.max(c.vecSim, lex)
      const weakest = Math.min(c.vecSim, lex)
      // Each bonus consumes only the headroom still remaining, so the total
      // stays inside 0..1 without a clamp AND stays strictly ordered. The clamp
      // was the original bug: Math.min(1, …) flattened both salmon candidates to
      // exactly 1.0, after which the winner was whichever row came back first.
      let score = strongest
      score += AGREEMENT_WEIGHT * weakest * (1 - score)
      if (headMatches(c, query)) score += HEAD_MATCH_BONUS * (1 - score)
      return { ...c, score }
    })
    .filter((c) => c.wordSim > 0 || c.vecSim >= VECTOR_ONLY_TAU)
    .sort((a, b) => b.score - a.score)
  return !top || top.score < tau ? null : top
}

// ---------------------------------------------------------------------------
// Inlined from lib/nutrition/resolve/guards.ts (183 unit tests live there)
// ---------------------------------------------------------------------------
// Hard constraints on what may be considered a match.
//
// These are GUARDS, not weights. A held-out run over 4 unseen patients found
// 37.8% of ingredient grams resolving to semantically wrong food while still
// reporting `basis: matched` — the resolver claiming confidence. Adding another
// tuned coefficient would have moved a percentage; the failures needed to be
// made impossible instead.
//
// The measured failures sort into exactly three mechanisms:
//
//   A  a FORM word converts a whole food into a concentrate
//        sardines   -> Sardine oil          (900 vs ~200 kcal/100 g)
//        Whole Eggs -> Egg, whole, dried    (4.2x over)
//        Linseeds   -> Linseed oil
//
//   B  the match is carried by MODIFIERS, not the food noun
//        Low fat Quark -> Peanut flour, low fat   ("low fat" matched; QUARK is
//                                                  absent — dairy read as a nut)
//        Kidney Bohnen -> Kidney, pork, raw       ("bohnen" absent entirely)
//
//   C  a DIET qualifier is ignored
//        Butter Chicken vegan -> Chicken fat
//
// B and C are patient-safety failures, not accuracy failures: one crosses into a
// top-9 allergen, the others put meat in a vegetarian meal. They are blocked
// outright rather than scored down.

// --- X-lang — one canonical food vocabulary across the practice's languages
// Ported from lib/nutrition/resolve/food-terms.ts on feat/meal-vision-
// correction-loop; no lib/ copy exists on this branch, so this inline IS the
// deployed source of truth until that branch lands.
//
// Switzerland has four national languages and the reference planes are a mix:
// nb_food_items is English + French (CIQUAL), and the branded plane is
// overwhelmingly French with a solid German minority. Counting heads in the
// loaded Swiss products:
//
//   yogourt 177 · lait 121 · pain 101 · crème 92 · jus 83 · salade 71
//   fromage 66 · jambon 61 · huile 54 · beurre 52 · joghurt 56 · skyr 49
//
// So an English query reaches almost none of it, and vice versa. "Almond Milk"
// could not find "Mandel Drink Natur" or "Lait d'amande" — not a guard defect,
// a vocabulary gap.
//
// THE DESIGN POINT: one canonical form, used by BOTH sides. Retrieval needs
// translated readings so it can find foreign-named rows (crossLanguageTerms
// below), and the guards need the SAME mapping or they veto exactly what
// retrieval just found: the head noun of "Almond Milk" is "milk", which appears
// nowhere in "Lait d'amande". tokenise() folds every token through this map, so
// guard comparisons happen in canonical English whatever language either side
// was written in. It also has to fold BOTH ways for the form guard: "beurre"
// folds to "butter", so a patient who writes it has "asked for" the butter form
// and the FORM_WORDS additions below cannot reject her own food (rule 3).
//
// The fold lives at RETRIEVAL and in GUARD comparisons — NEVER inside
// normalise(). `aliasKey = normalise(rawName).core` keys the live
// nb_patient_food_aliases table, and normalise-agreement.test.ts mutation-checks
// agreement with the client copy; folding there would orphan every stored
// alias. (The feature branch folded inside normalise; this port deliberately
// moved it out.)
//
// Deliberately small and grounded. Every entry is a term that appears in the
// loaded data or is an everyday word in a Swiss kitchen — this is not an
// attempt at a general dictionary, and a wrong entry here silently mis-prices
// food. ORDERING CONVENTION: within each canonical group the FRENCH spelling is
// listed FIRST — FRENCH_OF, and so the one foreign retrieval variant, depends
// on that order.

// Foreign term -> canonical English token.
const TO_CANONICAL: Record<string, string> = {
  // dairy — the largest and most error-prone group
  lait: 'milk', milch: 'milk', latte: 'milk',
  yogourt: 'yogurt', yaourt: 'yogurt', joghurt: 'yogurt', jogurt: 'yogurt',
  fromage: 'cheese', kase: 'cheese', käse: 'cheese', formaggio: 'cheese',
  creme: 'cream', crème: 'cream', rahm: 'cream', sahne: 'cream', panna: 'cream',
  beurre: 'butter', quark: 'quark', sere: 'quark', séré: 'quark',
  // staples
  pain: 'bread', brot: 'bread', pane: 'bread',
  oeuf: 'egg', œuf: 'egg', oeufs: 'egg', ei: 'egg', eier: 'egg', uovo: 'egg',
  riz: 'rice', reis: 'rice', riso: 'rice',
  pates: 'pasta', pâtes: 'pasta', nudeln: 'pasta', teigwaren: 'pasta',
  avoine: 'oat', hafer: 'oat', flocons: 'flakes', flocken: 'flakes',
  // proteins
  poulet: 'chicken', huhn: 'chicken', hahnchen: 'chicken', hähnchen: 'chicken',
  boeuf: 'beef', bœuf: 'beef', rind: 'beef', rindfleisch: 'beef', manzo: 'beef',
  porc: 'pork', schwein: 'pork', schweinefleisch: 'pork',
  jambon: 'ham', schinken: 'ham', prosciutto: 'ham',
  poisson: 'fish', fisch: 'fish', pesce: 'fish',
  saumon: 'salmon', lachs: 'salmon', thon: 'tuna', thunfisch: 'tuna',
  // plant
  amande: 'almond', amandes: 'almond', mandel: 'almond', mandeln: 'almond',
  noix: 'walnut', walnuss: 'walnut', noisette: 'hazelnut', haselnuss: 'hazelnut',
  soja: 'soy', pois: 'pea', erbsen: 'pea', haricot: 'bean', bohnen: 'bean',
  lentille: 'lentil', linsen: 'lentil', pomme: 'apple', apfel: 'apple',
  banane: 'banana', fraise: 'strawberry', erdbeere: 'strawberry',
  myrtille: 'blueberry', heidelbeere: 'blueberry', framboise: 'raspberry',
  himbeere: 'raspberry', peche: 'peach', pêche: 'peach', pfirsich: 'peach',
  carotte: 'carrot', karotte: 'carrot', ruebli: 'carrot', rüebli: 'carrot',
  tomate: 'tomato', epinard: 'spinach', épinard: 'spinach', spinat: 'spinach',
  // forms and liquids
  huile: 'oil', ol: 'oil', öl: 'oil', olio: 'oil',
  jus: 'juice', saft: 'juice', sirop: 'syrup', sirup: 'syrup',
  confiture: 'jam', konfitüre: 'jam', marmelade: 'jam',
  salade: 'salad', salat: 'salad', soupe: 'soup', suppe: 'soup',
  sucre: 'sugar', zucker: 'sugar', sel: 'salt', salz: 'salt',
  eau: 'water', wasser: 'water', miel: 'honey', honig: 'honey',
  chocolat: 'chocolate', schokolade: 'chocolate', cioccolato: 'chocolate',
  // sources guard G polices. These spellings used to live in SOURCE_WORDS as a
  // second, language-aware mapping; the fold owns ALL translation now and G
  // keys on canonical tokens only — one mapping, not two that can disagree.
  soya: 'soy', coco: 'coconut', cajou: 'cashew', chanvre: 'hemp',
  chevre: 'goat', chèvre: 'goat', brebis: 'sheep', bufflonne: 'buffalo',
}

// Canonical -> the FRENCH spelling: the one foreign retrieval variant worth its
// RPC, because the branded plane is overwhelmingly French (counts above).
// Built by inverting TO_CANONICAL so the two can never drift apart; "French
// spelling first in each group" is the ordering that makes first-wins correct.
const FRENCH_OF: Record<string, string> = (() => {
  const out: Record<string, string> = {}
  for (const [foreign, canonical] of Object.entries(TO_CANONICAL)) {
    if (!(canonical in out)) out[canonical] = foreign
  }
  return out
})()

// Plurals must fold too, and ONE stem rule cannot serve both "tomates" ->
// "tomate" (drop the "s") and "tomatoes" -> "tomato" (drop the "es"): the first
// version applied the "es" rule to French plurals, produced "myrtill", and the
// fold silently did nothing for every French plural — the most common shape a
// patient writes. So try SEVERAL candidate stems and take the first that the
// map actually holds.
function stemCandidates(t: string): string[] {
  if (t.length <= 3) return [t]
  const out = [t]
  if (t.endsWith('ies')) out.push(`${t.slice(0, -3)}y`)
  if (t.endsWith('es')) out.push(t.slice(0, -2))
  if (t.endsWith('s') && !t.endsWith('ss') && !t.endsWith('us')) out.push(t.slice(0, -1))
  return out
}

// Fold any token to its canonical English form. Unknown tokens pass through
// UNCHANGED — this must never invent a translation it does not hold.
function canonicalTerm(t: string): string {
  for (const st of stemCandidates(t)) {
    const hit = TO_CANONICAL[st]
    if (hit) return hit
  }
  return t
}

// Spelling variants folded to one form before any guard compares tokens.
// The reference table is American-spelled; patients are not. "soy yoghurt" was
// being rejected as if the head noun were missing, because "yoghurt" and
// "yogurt" do not prefix-match in either direction — a British spelling would
// have failed against every yogurt row in the table.
const SPELLING = new Map([
  ['yoghurt', 'yogurt'], ['yoghourt', 'yogurt'], ['yaourt', 'yogurt'],
  ['joghurt', 'yogurt'], ['jogurt', 'yogurt'],
  ['doughnut', 'donut'], ['courgette', 'zucchini'], ['aubergine', 'eggplant'],
  ['rocket', 'arugula'], ['coriander', 'cilantro'], ['maize', 'corn'],
  ['chickpeas', 'chickpea'], ['garbanzo', 'chickpea'],
  ['wholemeal', 'wholewheat'], ['wholegrain', 'wholewheat'],
])
const fold = (t: string): string => SPELLING.get(t) ?? t

// Every guard comparison happens on this composed fold: spelling variants
// first, then the cross-language canonical.
const canonicalToken = (t: string): string => canonicalTerm(fold(t))

const tokenise = (s: string): string[] =>
  s.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').trim().split(/\s+/).filter(Boolean).map(canonicalToken)

// --- X-lang retrieval — bounded cross-language search terms
// Search-term expansion for the ladder (tiers 1 and 2), from normalise().core.
// AT MOST TWO extra readings per name, because every term is another embedding
// call plus a retrieval RPC:
//
//   1. the canonical-ENGLISH fold — a French/German query's road into the
//      English-headed generic plane          ("myrtilles" -> "blueberry")
//   2. the FRENCH fold            — an English/German query's road into the
//      French-named branded plane            ("almond milk" -> "amande lait")
//
// DELIBERATELY DROPPED from the feature branch's per-token fan-out: the German
// and Italian sibling variants (a German query still reaches the generic plane
// via fold 1; what is given up is EN->German-branded reachability, the smallest
// slice of the plane) and the one-swap-per-token combinations. Word order stays
// as the query wrote it — trigram + word similarity absorb "amande lait" vs
// "Lait d'amande" — and the guards judge every candidate against the RAW name,
// so a reading can only ever widen the search, never change what is accepted.
const canonicalFold = (phrase: string): string =>
  phrase.split(' ').map(canonicalToken).join(' ')

const frenchFold = (phrase: string): string =>
  phrase.split(' ').map((t) => FRENCH_OF[canonicalToken(t)] ?? t).join(' ')

// Token-by-token folding is wrong for the two non-compositional idioms in the
// vocabulary's range: a "pomme de terre" is a potato, not an "apple de terre",
// and "noix de coco" is a coconut, not a walnut. Emit no reading rather than a
// wrong-food one.
const NON_COMPOSITIONAL = /(?:pommes?\s+de\s+terre|noix\s+de\s+coco)/

function crossLanguageTerms(core: string): string[] {
  if (NON_COMPOSITIONAL.test(core)) return []
  const out: string[] = []
  const push = (t: string) => {
    if (t && t !== core && !out.includes(t)) out.push(t)
  }
  push(canonicalFold(core))
  push(frenchFold(core))
  return out
}

// --- A — form words --------------------------------------------------------
// Words that describe a PROCESSED FORM rather than a variety. If the candidate
// carries one and the query does not, the candidate is a different food from
// the one the patient ate, almost always far more energy-dense.
//
// Variety words ("cherry", "wild", "farmed", "raw", "whole") are deliberately
// NOT here: they narrow a food without changing it.
const FORM_WORDS = new Set([
  'oil', 'fat', 'tallow', 'lard', 'ghee', 'shortening',
  'flour', 'powder', 'powdered', 'meal', 'starch',
  'dried', 'dehydrated', 'desiccated', 'freeze',
  // 'concentrate' lives in BASE_NOUNS, not here: whey protein concentrate IS
  // whey protein, differing by source rather than processing. Holding it in
  // both sets rejected 'Whey Protein Concentrate' for the query 'Whey
  // Protein' — the same food, and one of the commonest forms it is sold in.
  'extract', 'essence', 'syrup', 'paste', 'puree', 'jam', 'jelly', 'marmalade',
  'juice', 'drink', 'beverage', 'liquid', 'brine',
  'crisp', 'chip', 'bar', 'biscuit', 'cookie', 'cake', 'pie', 'crumble',
  'turnover', 'muffin', 'pastry', 'spread', 'sauce',
  // Found by the held-out run, each a real mis-resolution:
  //   Peach        -> Peach NECTAR
  //   Whey Protein -> Soy protein ISOLATE   (dairy -> soy, an allergen swap)
  //   apple chunks -> Apple STRUDEL          (274 kcal/100 g)
  'nectar', 'strudel', 'tart', 'pudding', 'mousse', 'sorbet',
  'ice', 'candy', 'chocolate', 'snack',
  // BOTH of these were assumed to be here and were NOT, which is why
  // "cinnamon" resolved to "Bread, cinnamon" and "Chia Seeds" reached a sesame
  // BUTTER (tahini — a top-9 allergen crossing). A query that genuinely asks
  // for butter or bread stays exempt — in any language, because tokenise folds
  // "beurre"/"pain" to these tokens first — since formMismatch only fires on a
  // form word the QUERY did not use.
  'butter', 'bread', 'loaf', 'roll', 'bun', 'cracker', 'wafer',
  // French equivalents — CIQUAL names reach the same comparison
  'huile', 'graisse', 'farine', 'poudre', 'sechee', 'séchée', 'jus', 'sirop',
  'confiture', 'concentre', 'concentré',
])

// Compared on a singular stem, because the guard missed "Beverages, POWERADE,
// Zero, Mixed Berry" purely because the row says "beverages" and the set said
// "beverage" — 550 g of mixed berries priced as a zero-calorie sports drink.
const stem = (t: string): string => (t.length > 3 && t.endsWith('s') && !t.endsWith('ss') ? t.slice(0, -1) : t)

// Grade words. "low fat yogurt" is still yogurt — the fat is a GRADE, not the
// food. Without this, "soy yoghurt" was rejected against "Yogurt, plain, low
// fat" because the candidate contains "fat", which the set holds for the sake
// of "Chicken fat" and "beef tallow". A form word preceded by a grade word is
// describing the same food, not a different one.
// The only form words that a grade word can legitimately qualify.
const GRADEABLE_FORM = new Set(['fat', 'oil'])

const GRADE_BEFORE_FORM = new Set([
  'low', 'reduced', 'whole', 'full', 'half', 'semi', 'non', 'nonfat', 'skim',
  'skimmed', 'light', 'lite', 'zero', 'high', 'extra', 'virgin',
  'faible', 'demi', 'entier', 'riche',
])

// The liquid-form words exist to stop a SOLID query matching its drink form —
// "Peach" must not price "Peach NECTAR". But a query whose head noun IS a
// liquid is asking for a drink, and rejecting drink rows for it inverts the
// guard's purpose. Found live 2026-08-04: every SR Legacy generic drink row is
// prefixed "Beverages," (a category label, not a form), so "Almond Milk" had
// its entire generic plane form-rejected, fell to branded, and priced Cailler's
// "Lait Amandes" MILK CHOCOLATE at 568 kcal/100 g. The head list is small and
// unambiguous — liquids only; "cocoa" is deliberately absent (powder-first in
// a nutrition context). tokenise folds lait→milk / jus→juice first, so the
// check is cross-language for free.
const LIQUID_FORM = new Set(['juice', 'drink', 'beverage', 'liquid', 'nectar', 'jus'])
const LIQUID_HEAD = new Set([
  'milk', 'juice', 'drink', 'beverage', 'smoothie', 'kefir',
  'tea', 'coffee', 'water', 'cola', 'soda', 'lemonade',
])

function formMismatch(candidateName: string, query: string): string | null {
  const qTokens = tokenise(query)
  const q = new Set(qTokens.map(stem))
  // FIRST or last token, not just last: English compounds are head-final
  // ("almond MILK") but French is head-initial ("LAIT amande"), and the
  // cross-language fold generates French-ordered search terms that pass
  // through this same guard. Checking only the last token rejected the
  // beverages rows for the folded term and killed the match the fold existed
  // to make.
  const liquidQuery =
    LIQUID_HEAD.has(stem(qTokens[qTokens.length - 1] ?? '')) ||
    LIQUID_HEAD.has(stem(qTokens[0] ?? ''))
  const cand = tokenise(candidateName)
  for (let i = 0; i < cand.length; i++) {
    const st = stem(cand[i])
    if (!FORM_WORDS.has(st) || q.has(st)) continue
    // A drink query asking for a drink row is not a form mismatch — but only
    // the LIQUID form words are excused; "Milk chocolate bar" for "milk" must
    // still be rejected on "chocolate" and "bar".
    if (liquidQuery && LIQUID_FORM.has(st)) continue
    // Only FAT can be graded. "low fat" is a grade; "whole dried" is not —
    // an earlier version skipped any form word after any grade word, which
    // let "Egg, whole, dried" through because "whole" preceded "dried".
    if (GRADEABLE_FORM.has(st) && i > 0 && GRADE_BEFORE_FORM.has(cand[i - 1])) continue
    return cand[i]
  }
  return null
}

// --- B — the head noun must actually be present ----------------------------
// English compounds are head-final, so the LAST token of the query is the food
// itself. If it appears nowhere in the candidate's name, whatever matched was a
// modifier, and the two are not the same food.
//
// This is the single most valuable guard: it is what stops "low fat quark"
// resolving to peanut flour on the strength of "low fat", and "Kidney Bohnen"
// resolving to pork kidney on the strength of "kidney".
//
// Prefix matching both ways, so egg/eggs, tomato/tomatoes and myrtille/
// myrtilles all still count as present.
// Trailing words that are NOT the food. Head-final only holds for real noun
// compounds, and these break it:
//   "apple chunks"        head would be "chunks"  (a shape, not a food)
//   "butter chicken vegan" head would be "vegan"  (a diet, not a food)
// Both were caught by the guard tests: the candidate was correctly rejected but
// for the wrong reason, which would have hidden the real defect.
const NOT_A_FOOD_NOUN = new Set([
  // CUT words. Added after the head-noun guard CAUSED a fish->meat error:
  // "Salmon Fillet" took head "fillet", which rejected "Salmon, raw" (no
  // "fillet" token) and accepted "Veal fillet, raw". A cut is not a food.
  'fillet', 'fillets', 'filet', 'filets', 'breast', 'breasts', 'thigh', 'thighs',
  'leg', 'legs', 'loin', 'steak', 'steaks', 'chop', 'chops', 'cutlet', 'cutlets',
  'mince', 'minced', 'ground', 'shank', 'rib', 'ribs', 'wing', 'wings',
  'escalope', 'pave', 'pavé', 'darne',
  'chunks', 'chunk', 'strips', 'strip', 'slices', 'slice', 'pieces', 'piece',
  'cubes', 'cube', 'wedges', 'wedge', 'halves', 'half', 'bits', 'portion',
  'portions', 'serving', 'servings', 'mix', 'mixed', 'assorted', 'selection',
  'morceaux', 'tranches', 'lamelles',
  'vegan', 'vegetarian', 'veggie', 'plantbased',
  'vegetalien', 'végétalien', 'vegetarien', 'végétarien',
  // FRENCH AND GERMAN GRADE WORDS. "lait entier" took head "entier" — French
  // for "whole" — so the guard demanded every candidate contain "entier" and
  // rejected every milk row. The English grade words were already covered; a
  // French-speaking patient was not.
  'entier', 'entiere', 'entière', 'ecreme', 'écrémé', 'ecremee', 'écrémée',
  'demi', 'allege', 'allégé', 'allegee', 'allégée', 'maigre', 'gras', 'grasse',
  'complet', 'complete', 'complète', 'bio', 'frais', 'fraiche', 'fraîche',
  'vollmilch', 'halbfett', 'fettarm', 'mager', 'vollkorn', 'natur',
])

// Singularise for comparison. The guard judges the RAW name (so it can see
// "cooked", which normalise() strips), but that means it must do its own
// singularisation or plurals become unmatchable: "blueberries" and "blueberry"
// are prefixes of each other in NEITHER direction, so 350 g of Blueberries
// priced at ZERO while "Blueberry" matched fine.
const singularise = (t: string): string => {
  if (t.length <= 3) return t
  if (t.endsWith('ies')) return `${t.slice(0, -3)}y`
  if (t.endsWith('oes')) return t.slice(0, -2)
  if (t.endsWith('ses') || t.endsWith('xes') || t.endsWith('zes')) return t.slice(0, -2)
  if (t.endsWith('s') && !t.endsWith('ss') && !t.endsWith('us')) return t.slice(0, -1)
  return t
}

// The query's food noun.
//
// Head-final only identifies the food once everything that ISN'T a food noun is
// removed, and the raw last token frequently is not one. Each of these was a
// live mis-resolution, and the guard did not merely fail to help — it REJECTED
// every correct candidate and handed the match to whatever row contained the
// junk token:
//
//   "Tortellini (cheese filled)"  -> head "filled" -> Surimi, filled w cheese
//   "Butter Chicken (home made)"  -> head "made"   -> prepared potato salad
//   "banana (1/4)"                -> head "4"      -> WENDY'S 1/4 LB burger
//   "Oats (Gluten free)"          -> head "free"   -> gluten-free bread
//
// So: drop parentheticals (glosses and portion notes, never the food), drop
// numerals and single letters, drop the shape/diet/cut words, then singularise.
function headNoun(query: string): string {
  const withoutGloss = query.replace(/\([^)]*\)/g, ' ')
  const q = tokenise(withoutGloss)
    .filter((t) => !NOT_A_FOOD_NOUN.has(t))
    // A numeral or a stray letter is never a food. "McDONALD'S" tokenises to
    // include "s", which prefix-matches almost any query head — that is how
    // "Strawberries" matched a McDonald's sundae. The guard was trivially
    // satisfiable by any row containing a one-letter token.
    .filter((t) => t.length > 1 && !/^\d+$/.test(t))
    .map(singularise)
  const fallback = tokenise(query).filter((t) => t.length > 1 && !/^\d+$/.test(t)).map(singularise)
  return q[q.length - 1] ?? fallback[fallback.length - 1] ?? ''
}

function headNounPresent(c: Candidate, query: string): boolean {
  const head = headNoun(query)
  if (!head) return false
  const names = [c.name, c.name_fr ?? ''].join(' ')
  // Singularised on BOTH sides, and one-letter tokens excluded so a stray "s"
  // in a brand name cannot satisfy the guard for an arbitrary query.
  return tokenise(names)
    .filter((t) => t.length > 1)
    .map(singularise)
    .some((t) => t.startsWith(head) || head.startsWith(t))
}

// --- C — diet qualifiers are binding ---------------------------------------
const DIET_QUALIFIERS = new Set([
  'vegan', 'vegetarian', 'veggie', 'plantbased',
  'vegetalien', 'végétalien', 'vegetarien', 'végétarien', 'maigre',
])

// Categories that are animal-derived, taken from the values actually present in
// nb_food_items rather than invented.
const ANIMAL_CATEGORY = /(meat|fish|poultry|beef|pork|lamb|veal|sausage|shellfish|finfish|egg)/i

// Meat nouns, for rows whose category is missing or generic.
const ANIMAL_WORD = /\b(chicken|beef|pork|lamb|veal|turkey|duck|bacon|ham|sausage|salmon|tuna|sardine|anchovy|prawn|shrimp|gelatin|lard|tallow|poulet|boeuf|porc|jambon)\b/i

function dietViolation(c: Candidate, query: string): string | null {
  const q = tokenise(query)
  const wantsPlant = q.some((t) => DIET_QUALIFIERS.has(t)) || /\bsans viande\b/i.test(query)
  if (!wantsPlant) return null
  const hay = `${c.name} ${c.name_fr ?? ''}`
  // The category check is the reliable one; the word check catches rows whose
  // category is generic ("Fats and Oils" holds chicken fat).
  if (ANIMAL_CATEGORY.test(c.category ?? '')) return `animal category "${c.category}"`
  if (ANIMAL_WORD.test(hay)) return 'animal-derived name'
  return null
}

// --- D — names that are not foods at all -----------------------------------
// The vision model emits aggregate placeholders. On the held-out set these were
// 22% of all grams and resolved to real foods with real numbers: "dinner items"
// (3.6 kg) became "Rolls, dinner, egg" at 11,052 kcal, and "breakfast items"
// (2.6 kg) became a breakfast biscuit at 11,574.
//
// Resolving these at all is the error. They are not ingredients, so no
// composition is correct, and pricing them fabricates most of a day's energy.
// The real repair is in the analyze-meal prompt (spec P1-P7); until then they
// must not be priced.
const PLACEHOLDER = /^(total|whole)?\s*(meal|day|lunch|dinner|breakfast|snack|brunch|supper|plate|dish|food|item)s?(\s+items?)?$/i

function isPlaceholder(name: string): boolean {
  const n = name.trim()
  if (!n) return true
  if (PLACEHOLDER.test(n)) return true
  // "lunch items", "dinner items", "breakfast items", "misc items"
  if (/\bitems?\b/i.test(n) && tokenise(n).length <= 3) return true
  return false
}

// --- F — a source modifier on a generic base is part of the identity --------
// The mirror image of guard B, and the reason "Almond Milk" resolved to DAIRY
// milk at roughly 8x the energy.
//
// B catches the case where the head noun is ABSENT ("low fat quark" ->
// "Peanut flour, low fat": quark is nowhere in it). This catches the opposite:
// the head noun is PRESENT and matches perfectly, but it is a generic BASE that
// several completely different foods share. Milk, cheese, cream, flour, oil and
// yoghurt are all bases like this — what makes almond milk almond is the word
// "almond", and dropping it leaves a food with different macros, a different
// allergen profile, and in this practice a different dietary meaning.
//
//   "Almond Milk"  -> Milk, whole          head "milk" present, almond gone
//   "Soy yoghurt"  -> Yogurt, plain        head "yoghurt" present, soy gone
//   "Coconut cream"-> Cream, heavy         head "cream" present, coconut gone
//
// Deliberately narrow: it fires only when the query's LAST token is one of
// these bases and the query carries a qualifier in front of it. A general
// "every query token must appear" rule was tempting but rejects far too much —
// reference names are terse and omit words a patient naturally writes.
const BASE_NOUNS = new Set([
  'milk', 'milks', 'yoghurt', 'yogurt', 'yaourt',
  'cream', 'creme', 'crème', 'cheese', 'fromage',
  'flour', 'farine', 'oil', 'huile', 'butter', 'beurre',
  'drink', 'boisson', 'lait',
  // 'whey protein' vs 'soy protein' differ by SOURCE, not by form. Treating
  // 'protein'/'isolate' as processed forms rejected 'Whey Protein Isolate' for
  // the query 'Whey Protein' — which is the same food. The base guard is the
  // right tool: it demands the source word be present.
  'protein', 'proteins', 'isolate', 'concentrate',
  // "Chia Seeds" matched "Seeds, sesame butter, tahini, from unroasted
  // kernels" — the head noun "seed" was present, but "chia" appeared nowhere.
  // Seeds differ by SOURCE exactly as milk does, and this one crossed into
  // sesame, an allergen. (nb_food_items holds NO chia row at all, so falling
  // through to the branded plane or the red flag IS the complete correct
  // outcome, not a partial one.)
  'seed', 'seeds', 'nut', 'nuts', 'flake', 'flakes', 'powder',
])

// Words that qualify a base without changing its source ("low fat milk" is
// still milk). Kept separate from PREPARATION because these are about grade,
// not about how the food was cooked.
const PREPARATION_ISH = new Set([
  'low', 'lowfat', 'full', 'whole', 'skimmed', 'semi', 'half', 'fat', 'fats',
  'reduced', 'light', 'lite', 'nonfat', 'skim', 'demi', 'ecreme', 'écrémé',
  'entier', 'entiere', 'entière', 'maigre', 'plain', 'natural', 'nature',
])

function baseModifierMissing(c: Candidate, query: string): string | null {
  const q = tokenise(query).filter((t) => !NOT_A_FOOD_NOUN.has(t) && !PREPARATION_ISH.has(t))
  const base = q[q.length - 1]
  if (!base || !BASE_NOUNS.has(base)) return null

  // Qualifiers are everything before the base that is not itself a base word.
  const qualifiers = q.slice(0, -1).filter((t) => !BASE_NOUNS.has(t))
  if (qualifiers.length === 0) return null // plain "milk" is genuinely plain milk

  const hay = tokenise(`${c.name} ${c.name_fr ?? ''}`)
  const present = qualifiers.some((mod) => hay.some((t) => t.startsWith(mod) || mod.startsWith(t)))
  return present ? null : `"${qualifiers.join(' ')}" is missing from "${c.name}"`
}

// --- G — a source the query never asked for --------------------------------
// The other direction of guard F, found LIVE by the Phase 5 benchmark: bare
// "yogurt" (and "natural yogurt") resolved to "Tofu yogurt" — soy silently
// substituted for dairy, reported as a confident `matched`, in a practice
// where dairy-vs-soy drives protocols. F cannot see it: F fires when the QUERY
// carries a qualifier the candidate lost ("Almond Milk" -> dairy milk). Here
// the query is bare and the CANDIDATE is the one adding a source ("yogurt" ->
// "TOFU yogurt"); the head-noun guard passes because "Tofu yogurt" contains
// "yogurt", and no guard inspected tokens the query never said.
//
// Scoped exactly like F, deliberately: it fires only when the query's head is
// one of the generic BASE_NOUNS that several different-source foods share.
// That scoping is what keeps "basmati" -> "Rice, basmati" alive — there,
// "rice" IS the food, not a source bolted onto a base ("basmati" is no base
// noun, so this guard never looks). And per the arc's rule 3 it fires only on
// a source the QUERY did not say: a patient who writes "tofu yogurt" still
// reaches the tofu row, "goat cheese" still reaches goat cheese.
//
// The list is deliberately SMALL and grounded in the live reference data
// (verified against nb_food_items 2026-08-03: soja 48 rows, chèvre 34, riz 40,
// brebis 11, coco 16, avoine 7, amande 13, cajou 5, chanvre 1, bufflonne 1).
// Grade, variety and flavour words do not belong here — a wrong entry silently
// mis-prices food.
//
// Tokens reach this map ALREADY FOLDED to canonical English by tokenise(): the
// French spellings that used to sit here as a second language mapping (soja,
// coco, avoine, amande, cajou, riz, chanvre, chèvre, brebis, bufflonne) now
// route through TO_CANONICAL above, so translation has exactly ONE home and
// "coconut milk" is still not rejected against "Lait de coco" — coco folds to
// coconut before this map ever sees it. What stays here is source-GROUPING of
// same-language synonyms ('ewe' is not a translation of 'sheep').
const SOURCE_WORDS = new Map([
  // plant bases
  ['tofu', 'soy'], ['soy', 'soy'],
  ['coconut', 'coconut'], ['oat', 'oat'], ['almond', 'almond'],
  ['cashew', 'cashew'], ['rice', 'rice'], ['hemp', 'hemp'], ['pea', 'pea'],
  // non-default dairy animals — goat cheese for "cheese" is the same silent
  // substitution as tofu yogurt for "yogurt"
  ['goat', 'goat'], ['sheep', 'sheep'], ['ewe', 'sheep'], ['buffalo', 'buffalo'],
])

// --- G2 — substitute markers ------------------------------------------------
// Found live the moment guard E was fixed: rejecting the RAW chicken row for
// "roasted chicken" exposed the next-ranked candidate — "Chicken, MEATLESS", a
// soy substitute priced as if it were the bird. Same disease as tofu-yogurt,
// different marker word, and guard G could not see it: G is scoped to BASE_NOUN
// queries because sources (goat, oat, soy...) are only "wrong" against a
// generic base. A substitute marker is disqualifying against ANY query that
// did not ask for it — "meatless" on a row means the row is not the food, full
// stop — so this guard is deliberately unscoped.
//
// Raw-name regex, same shape as guard E and for the same reason: guards judge
// RAW names (normalise() once silently killed the state guard), and Unicode
// lookarounds rather than \b because \b is ASCII and can never match at the
// end of "végétal". Every word verified against live nb_food_items 2026-08-03:
// végétal 48 rows · plant-based 20 · substitute 16 · imitation 12 · vegan 10 ·
// meatless 9 · vegetarian 7. ("substitute" also covers salt/egg substitutes —
// query "egg" must not price "Egg substitute, liquid".)
//
// Rule 3 exemption: a patient who writes "vegetarian chicken", "vegan yogurt"
// or "salt substitute" said the word, so the candidate carrying it survives.
const SUBSTITUTE_WORDS =
  /(?<![\p{L}\p{N}])(meatless|vegetarian|vegan|imitation|substitute|plant-based|soy-based|v[ée]g[ée]tal(?:e|es|aux)?|v[ée]g[ée]tarien(?:ne|nes)?|v[ée]gane?s?)(?![\p{L}\p{N}])/iu

function substituteMismatch(c: Candidate, query: string): string | null {
  if (SUBSTITUTE_WORDS.test(query)) return null
  const m = `${c.name} ${c.name_fr ?? ''}`.match(SUBSTITUTE_WORDS)
  return m ? `"${m[1]}" in "${c.name}" marks a substitute the query did not ask for` : null
}

function sourceMismatch(c: Candidate, query: string): string | null {
  const q = tokenise(query).filter((t) => !NOT_A_FOOD_NOUN.has(t) && !PREPARATION_ISH.has(t))
  const base = q[q.length - 1]
  if (!base || !BASE_NOUNS.has(base)) return null

  // Every source the query itself names, as a group — so any spelling or
  // language of the same source in the candidate is "asked for".
  const asked = new Set(q.map((t) => SOURCE_WORDS.get(singularise(t))).filter(Boolean))
  for (const t of tokenise(`${c.name} ${c.name_fr ?? ''}`)) {
    // Exact token equality on a singularised stem, NOT prefix matching: the
    // head-noun guard's prefix rule would make "oat" claim "goat" here.
    const source = SOURCE_WORDS.get(singularise(t))
    if (source && !asked.has(source)) {
      return `"${t}" in "${c.name}" is a source the query did not ask for`
    }
  }
  return null
}

// --- E — cooked/raw state --------------------------------------------------
// The word boundaries below are load-bearing, not decoration: without them
// "cru" matches inside "crumble" and "dry" inside "dryer", so unrelated rows
// would be rejected as raw. Shell escaping stripped them twice.
//
// A raw grain or legume is ~3x the energy of its cooked form per 100 g, because
// cooking is mostly water uptake. The held-out run had "cooked rice" and "Reis
// gekocht" resolve to "Rice, raw" — 352 against ~130 kcal/100 g, on 540 g.
//
// The Phase 5 benchmark then caught the list itself being too narrow: "roasted
// chicken" sailed straight past this guard onto "Chicken, meat, raw" (~120
// kcal/100 g raw vs ~165-190 cooked), because the guard knew "cooked" and
// "boiled" but none of the words patients actually write — roasted, grilled,
// baked, fried, and their FR/DE equivalents. Hence the widened list below.
//
// COOKED_WORDS uses Unicode lookarounds instead of \b, and that is load-bearing
// too: \b is ASCII-word-based, so after a trailing accented letter there is no
// word/non-word transition — /\bgrillé\b/ can NEVER match "poulet grillé",
// because "é" already counts as a non-word character and the closing \b
// silently fails at the end of the word. The French cooked vocabulary this
// guard needs ("grillé", "poêlé", "rôti") ends in exactly those letters.
const COOKED_WORDS =
  /(?<![\p{L}\p{N}])(cooked|boiled|steamed|stewed|prepared|roasted|roast|grilled|baked|fried|sautéed|sauteed|poached|braised|seared|gekocht|gekochte|gebraten|gegrillt|gebacken|geröstet|cuit|cuite|rôti|rôtie|grillé|grillée|poêlé|poêlée|au four)(?![\p{L}\p{N}])/iu
// "unprepared" is how USDA labels an uncooked mix, and neither \bprepared\b
// nor the lookaround COOKED list above matches inside it — so 1,200 g of "Rice
// Mix (cooked)" landed on a "...white and wild, flavored, UNPREPARED" row. The
// number happened to be right, which is worse than being wrong: it was luck,
// not a guard. German rows spell the same state "roh" / "nicht zubereitet".
// Unicode lookarounds for the same reason as COOKED_WORDS — and so "roh" can
// never fire inside "Rohrzucker", nor "cru" inside "crumble".
const RAW_WORDS =
  /(?<![\p{L}\p{N}])(raw|uncooked|unprepared|dry|dried|cru|crue|roh|nicht zubereitet)(?![\p{L}\p{N}])/iu

function stateMismatch(candidateName: string, query: string): string | null {
  if (COOKED_WORDS.test(query) && RAW_WORDS.test(candidateName) && !COOKED_WORDS.test(candidateName)) {
    return 'query is cooked but candidate is raw'
  }
  return null
}

type GuardRejection = { guard: 'form' | 'head' | 'diet' | 'state' | 'base' | 'source' | 'substitute'; reason: string }

// Runs every guard. Returns why the candidate is unusable, or null if it is
// acceptable. Order is cheapest-first; the reason is kept so a rejection can be
// explained rather than being an unexplained miss.
function rejectCandidate(c: Candidate, query: string): GuardRejection | null {
  if (!headNounPresent(c, query)) {
    return { guard: 'head', reason: `query head noun absent from "${c.name}"` }
  }
  const diet = dietViolation(c, query)
  if (diet) return { guard: 'diet', reason: `query is plant-only but candidate is ${diet}` }

  const form = formMismatch(c.name, query)
  if (form) return { guard: 'form', reason: `candidate is a "${form}" form the query did not ask for` }

  const state = stateMismatch(c.name, query)
  if (state) return { guard: 'state', reason: state }

  const base = baseModifierMissing(c, query)
  if (base) return { guard: 'base', reason: base }

  const source = sourceMismatch(c, query)
  if (source) return { guard: 'source', reason: source }

  const substitute = substituteMismatch(c, query)
  if (substitute) return { guard: 'substitute', reason: substitute }

  return null
}

// ── Energy-density anchor for the branded plane ─────────────────────────────
// A name can lie about what a food is; its energy density cannot. Found live
// the day the cross-language fold shipped: "Almond Milk" folded to the French
// branded plane and matched "Lait Amandes" — Cailler's MILK CHOCOLATE WITH
// ALMONDS, whose product name is literally just "milk almonds". Every guard
// passed (the name contains no chocolate word, no substitute marker, and
// milk+almond are exactly what was asked), the lexical score was near-perfect,
// and the patient's drink was priced at 568 kcal/100 g instead of ~15.
//
// The tell was sitting one tier up: generic retrieval had already surfaced
// guard-PASSING almond-milk rows (15-38 kcal/100 g) — they merely scored under
// tau because their long CIQUAL/SR names dilute lexical similarity. A row that
// is semantically eligible but lexically weak is exactly what an ANCHOR is:
// evidence of what this food's energy density should roughly be.
//
// So: when tier 1 produced a guard-passing candidate (any score), a branded
// winner whose kcal/100 g is more than 4x off the anchor's — either direction —
// is rejected and the next-ranked product gets its turn. The +25 floor keeps
// the ratio meaningful near zero (water, black coffee) without muting the
// chocolate-vs-drink case: (568+25)/(15+25) = 14.8, rejected; a 10%-fat Greek
// yogurt against a 60 kcal anchor is (130+25)/(60+25) = 1.8, accepted. Absent
// evidence — no anchor row, or either kcal null — the veto never fires: this
// guard needs proof to act, because "Whey Protein" style queries whose generic
// candidates ALL fail the guards must keep reaching the branded plane exactly
// as before.
const ENERGY_ANCHOR_BAND = 4
const ENERGY_ANCHOR_FLOOR = 25
function energyDensitySane(anchorKcal: number | null, productKcal: number | null): boolean {
  if (anchorKcal == null || productKcal == null) return true
  const ratio = (productKcal + ENERGY_ANCHOR_FLOOR) / (anchorKcal + ENERGY_ANCHOR_FLOOR)
  return ratio <= ENERGY_ANCHOR_BAND && ratio >= 1 / ENERGY_ANCHOR_BAND
}

// ---------------------------------------------------------------------------
// Inlined from lib/nutrition/resolve/decompose.ts
// ---------------------------------------------------------------------------
// Curated decomposition (Tier 0c).
//
// Some ingredient names are not ONE food. "mixed nuts" is four nuts; "Shiro" is
// chickpea flour, onion, oil and spice. Retrieval cannot win on these no matter
// how good it gets, because there is no single row that means them — the
// held-out run showed "mixed berries" landing on a sports drink, then on a
// breakfast cereal, neither of which is berries.
//
// THE RULE THAT MAKES THIS SAFE: decomposition decides WHAT IS IN the food.
// It never decides the NUMBERS. Every component is priced from the local
// reference table like any other ingredient, so a decomposed item is as
// traceable as a matched one — `basis: 'decomposed'` rather than a guess.
//
// Two sources of recipes, in order:
//
//   1. CURATED (here). Deterministic, unit-tested, no model call. Covers the
//      generic mixes that appear constantly in real logs.
//   2. AI-PROPOSED (phase 1b, via Infomaniak). For named dishes. The model
//      returns a component list ONLY; the numbers still come from the table.
//      Sovereign, and it cannot invent a calorie count.
//
// Fractions are by WEIGHT and must sum to 1. They are approximations of a
// typical mix, not a claim about a specific packet — which is exactly why a
// decomposed item is still worth confirming with the patient.
type Component = { name: string; fraction: number }

// Curated mixes. Every entry is a food whose name genuinely denotes a
// COMBINATION, not a food we simply failed to find. Adding a single food here
// to paper over a retrieval miss would hide the miss.
const CURATED: Record<string, Component[]> = {
  // Roughly the composition of a supermarket mixed-nut pack. Nuts differ enough
  // in fat (cashew ~44 g/100 g, walnut ~65) that guessing one stands in badly
  // for the mix.
  'mixed nuts': [
    { name: 'almonds', fraction: 0.3 },
    { name: 'cashew nuts', fraction: 0.25 },
    { name: 'walnuts', fraction: 0.25 },
    { name: 'hazelnuts', fraction: 0.2 },
  ],
  'nut mix': [
    { name: 'almonds', fraction: 0.3 },
    { name: 'cashew nuts', fraction: 0.25 },
    { name: 'walnuts', fraction: 0.25 },
    { name: 'hazelnuts', fraction: 0.2 },
  ],
  'mixed berries': [
    { name: 'strawberry', fraction: 0.3 },
    { name: 'blueberry', fraction: 0.3 },
    { name: 'raspberry', fraction: 0.2 },
    { name: 'blackberry', fraction: 0.2 },
  ],
  'berry mix': [
    { name: 'strawberry', fraction: 0.3 },
    { name: 'blueberry', fraction: 0.3 },
    { name: 'raspberry', fraction: 0.2 },
    { name: 'blackberry', fraction: 0.2 },
  ],
  'forest fruits': [
    { name: 'blueberry', fraction: 0.35 },
    { name: 'raspberry', fraction: 0.25 },
    { name: 'blackberry', fraction: 0.25 },
    { name: 'redcurrant', fraction: 0.15 },
  ],
  'mixed vegetables': [
    { name: 'carrot', fraction: 0.3 },
    { name: 'green peas', fraction: 0.3 },
    { name: 'green beans', fraction: 0.2 },
    { name: 'sweet corn', fraction: 0.2 },
  ],
  'mixed salad': [
    { name: 'lettuce', fraction: 0.5 },
    { name: 'tomato', fraction: 0.3 },
    { name: 'cucumber', fraction: 0.2 },
  ],
  'mixed seeds': [
    { name: 'sunflower seeds', fraction: 0.35 },
    { name: 'pumpkin seeds', fraction: 0.35 },
    { name: 'flaxseed', fraction: 0.3 },
  ],
  'trail mix': [
    { name: 'almonds', fraction: 0.25 },
    { name: 'cashew nuts', fraction: 0.2 },
    { name: 'raisins', fraction: 0.3 },
    { name: 'sunflower seeds', fraction: 0.25 },
  ],
  'onion and garlic': [
    { name: 'onion', fraction: 0.8 },
    { name: 'garlic', fraction: 0.2 },
  ],
  'carrots and zucchini mix': [
    { name: 'carrot', fraction: 0.5 },
    { name: 'zucchini', fraction: 0.5 },
  ],
}

// A curated recipe, or null. Never guesses: an unknown mix returns null and the
// caller falls through, rather than being decomposed into something plausible.
function decomposeCurated(name: string): Component[] | null {
  // A parenthetical that NAMES foods is the patient telling us what was in it,
  // and that beats our generic average. "Mixed vegetables (broccoli, carrots,
  // cauliflower, beans)" was being decomposed into carrot/peas/green-beans/
  // sweet-corn — overriding three of the four foods actually listed — because
  // the recipe lookup tolerates surrounding words and now runs ahead of
  // retrieval. Defer to the patient; let retrieval or the AI proposer handle it.
  if (/\([^)]*,[^)]*\)/.test(name)) return null

  const n = clean(name)
  const hit = CURATED[n]
  if (hit) return hit

  // Tolerate a leading/trailing qualifier the patient added ("frozen mixed
  // berries", "mixed berries fresh") without matching on a mere substring,
  // which would decompose "berry yoghurt" as berries.
  for (const [key, components] of Object.entries(CURATED)) {
    const words = n.split(' ')
    const keyWords = key.split(' ')
    const idx = words.findIndex((_, i) => keyWords.every((kw, j) => words[i + j] === kw))
    if (idx !== -1) return components
  }
  return null
}

// ---------------------------------------------------------------------------
// Tier 2 scoring — inlined from lib/nutrition/resolve/ladder.ts
// ---------------------------------------------------------------------------
// A branded candidate must clear a HIGHER bar than a generic one. It is
// crowd-sourced, there are far more rows to collide with, and a wrong branded
// match is indistinguishable from a right one to the patient reading it.
const PRODUCT_TAU = 0.82

// Reuses the generic guards by presenting the product as a Candidate. The
// guards are source-agnostic by design — head noun, form words, diet and state
// are properties of the NAME, not of where the row came from.
const asCandidate = (p: ProductCandidate): Candidate => ({
  id: p.id,
  name: p.name,
  name_fr: null,
  category: null,
  source: 'off',
  vecSim: 0,
  lexSim: p.lexSim,
  wordSim: p.wordSim,
})

const rejectProduct = (p: ProductCandidate, query: string) => rejectCandidate(asCandidate(p), query)

// All products clearing PRODUCT_TAU, best first — a LIST, not a single winner,
// because the caller now has one more question to ask of each (energy sanity,
// below) and must be able to fall to the runner-up when the top row fails it.
function rankedProducts(products: ProductCandidate[]): ProductCandidate[] {
  return products
    .map((p) => {
      const lex = lexicalScore(asCandidate(p))
      // A half-filled OFF row should not win on its name alone, so completeness
      // trims the score rather than being ignored. Missing completeness is
      // treated as middling, not as perfect.
      const trust = 0.7 + 0.3 * (p.completeness ?? 0.5)
      return { p, score: lex * trust }
    })
    .filter((s) => s.score >= PRODUCT_TAU)
    .sort((a, b) => b.score - a.score)
    .map((s) => s.p)
}

// energyDensitySane lives up in the guards block ("Inlined from
// lib/nutrition/resolve/guards.ts") so the extract-and-compile drift suites
// can reach it like every other guard.

// ---------------------------------------------------------------------------
// Inlined from lib/nutrition/resolve/to-item.ts
// ---------------------------------------------------------------------------
// Reference columns whose app-facing name and unit differ from storage. The
// table stores grams; the app payload names milligrams. Unconverted this is a
// silent 1000x error in a clinically meaningful nutrient.
const RENAMED: Record<string, { as: string; factor: number }> = {
  epa_g: { as: 'epa_mg', factor: 1000 },
  dha_g: { as: 'dha_mg', factor: 1000 },
}
const MACRO_FIELDS = ['energy_kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g']

// ALLOWLIST by unit suffix, not a denylist of known junk. v1 used a denylist and
// leaked six non-nutrient columns into the micros payload (subcategory,
// nova_score, is_fermented, is_raw, glycemic_index, serving_description),
// because a denylist silently admits every column added later. Every real
// nutrient column in this table ends in its unit.
const IS_NUTRIENT = /_(g|mg|mcg|kcal)$/

// Columns that END IN A UNIT SUFFIX but describe the PACKAGE, not the food.
// They were being scaled by portion and emitted as micronutrients — a 500 g tub
// of whey surfaced as "quantity_g: 272.1" alongside real nutrients, which is a
// fabricated measurement in a payload whose entire purpose is trustworthy ones.
// `common_serving_g` on nb_food_items leaked the same way and predates the
// branded plane.
const NOT_A_NUTRIENT = new Set(['quantity_g', 'common_serving_g', 'serving_size_g', 'net_weight_g'])

const num = (v: unknown): number => (typeof v === 'number' && Number.isFinite(v) ? v : 0)

// 10 g is the declared precision floor (D7), but rounding to it FLOORS anything
// under 5 g to zero — which prices it at 0 kcal. Harmless for parsley, wrong
// for sugar, honey, oil or cinnamon, where a few grams is the whole entry. The
// held-out run had 52 portions drift and several small ones vanish entirely.
// Below 10 g the actual value is kept to 0.1 g.
const roundGrams = (g: number): number => {
  if (!Number.isFinite(g) || g <= 0) return 0
  if (g < 10) return Math.round(g * 10) / 10
  return Math.round(g / 10) * 10
}

type Row = Record<string, unknown>

function priceItem(
  row: Row,
  grams: number,
  opts: { basis: Basis; foodItemId?: string | null; alternatives?: string[] },
): ResolvedItem {
  const g = roundGrams(grams)
  const scale = g / 100

  const micros: Record<string, number | null> = {}
  for (const [col, raw] of Object.entries(row)) {
    if (!IS_NUTRIENT.test(col) || MACRO_FIELDS.includes(col) || NOT_A_NUTRIENT.has(col)) continue
    const v = typeof raw === 'string' ? Number(raw) : raw
    const rename = RENAMED[col]
    const key = rename ? rename.as : col
    // null stays null — scaling an unmeasured value would invent a measurement,
    // and "nobody measured iodine" is a different claim from "there is none".
    micros[key] = v === null || v === undefined || !Number.isFinite(v as number)
      ? null
      : (v as number) * scale * (rename ? rename.factor : 1)
  }

  const n = (k: string) => num(typeof row[k] === 'string' ? Number(row[k]) : row[k])
  return {
    name: String(row.name ?? ''),
    local_name: (row.name_fr as string | null) ?? null,
    category: (row.category as string | null) ?? null,
    estimated_grams: g,
    kcal: n('energy_kcal') * scale,
    protein_g: n('protein_g') * scale,
    carbs_g: n('carbs_g') * scale,
    fat_g: n('fat_g') * scale,
    fiber_g: n('fiber_g') * scale,
    micros,
    basis: opts.basis,
    food_item_id: opts.foodItemId ?? null,
    ...(opts.alternatives?.length ? { alternatives: opts.alternatives } : {}),
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
// The embedding session is INJECTED rather than constructed here, so this
// module never touches the `Supabase.ai` global and stays importable from any
// function bundle. Callers pass `new Supabase.ai.Session('gte-small')`.
export type EmbeddingSession = { run(t: string, o: unknown): Promise<unknown> }

export async function resolveItems(
  db: SupabaseClient,
  session: EmbeddingSession,
  items: Array<{ name: string; grams: number }>,
  // 🚨 INVARIANT — WHERE THIS ID IS ALLOWED TO COME FROM. Not a TODO; a rule.
  //
  // Tier 0a reads ONE patient's learned pantry, and every caller hands this
  // module a SERVICE-ROLE client (the reference plane is not patient data and has
  // always been read that way). So RLS is NOT the boundary on this read — this
  // parameter is the boundary, and it is the only one.
  //
  // Legal sources, both of which have already established who the caller is:
  //   * `nb_meal_logs.patient_id`, read under the CALLER'S OWN JWT — RLS has
  //     already proved they own that row, so the id is theirs by construction.
  //   * the service-role retry worker, which SELECTS its own work by status and
  //     schedule and accepts no row id from anybody.
  //
  // NEVER the request body. `resolve-foods` is a patient-facing endpoint; an id
  // taken from its body would let any authenticated caller read another patient's
  // food history one name at a time. That is why it passes nothing and gets null,
  // and why null means tier 0a does not issue a single query.
  patientId: string | null = null,
): Promise<ResolvedItem[]> {
  // One embedding per DISTINCT term per call. A meal routinely repeats a term
  // across items — "olive oil" on the salad and again on the bread, or two
  // readings that share a core — and each repeat is another gte-small inference
  // inside this worker. Scoped to the call, so nothing is cached across patients
  // or across deploys.
  const embeddingCache = new Map<string, number[]>()
  const embed = async (term: string): Promise<number[]> => {
    const hit = embeddingCache.get(term)
    if (hit) return hit
    const vec = (await session.run(term, { mean_pool: true, normalize: true })) as number[]
    embeddingCache.set(term, vec)
    return vec
  }

  const searchCandidates = async (term: string): Promise<Candidate[]> => {
    const embedding = await embed(term)
    const { data, error } = await db.rpc('match_food_items', {
      q_text: term,
      q_embedding: JSON.stringify(embedding),
      match_count: 20,
    })
    if (error) throw new Error(`match_food_items: ${error.message}`)
    return (data ?? []).map((r: Record<string, unknown>) => ({
      id: String(r.id),
      name: String(r.name),
      name_fr: (r.name_fr as string | null) ?? null,
      category: (r.category as string | null) ?? null,
      source: String(r.source),
      vecSim: Number(r.vec_sim) || 0,
      lexSim: Number(r.lex_sim) || 0,
      wordSim: Number(r.word_sim) || 0,
    }))
  }

  const getRow = async (id: string): Promise<Row | null> => {
    const { data } = await db.from('nb_food_items').select('*').eq('id', id).maybeSingle()
    return (data as Row) ?? null
  }

  // Tier 0a deps ------------------------------------------------------------
  //
  // ONE indexed read on (patient_id, alias_norm) — the table's own unique key —
  // so a MISS costs a single round trip and a HIT skips the embedding call plus
  // both retrieval RPCs. This is the tier that makes the pipeline cheaper and
  // more accurate the more a patient uses it.
  type LearnedAlias = {
    id: string
    food_item_id: string | null
    off_code: string | null
    grams_default: number | null
    hit_count: number | null
  }

  const lookupLearned = async (key: string): Promise<LearnedAlias | null> => {
    if (!patientId || !key) return null
    // The error is deliberately ignored, exactly as `lookupAlias` ignores its
    // own: if this table is unreachable — CLINICAL runs an independent migration
    // sequence against this same Postgres — the right outcome is the ladder
    // continuing without its learned tier, not a meal that fails to price.
    const { data } = await db
      .from('nb_patient_food_aliases')
      .select('id, food_item_id, off_code, grams_default, hit_count')
      .eq('patient_id', patientId)
      .eq('alias_norm', key)
      .maybeSingle()
    return (data as LearnedAlias | null) ?? null
  }

  // `hit_count` is a CONFIDENCE LEDGER, not a gate (see lib/meal-log/patient-
  // aliases.ts): it lets a clinician reading a pantry tell "said once" from
  // "said eleven times". So a failed increment must never cost the resolution.
  //
  // AWAITED rather than floated, on purpose. It is one primary-key update
  // against the Postgres we just read, an order of magnitude cheaper than the
  // embedding + two RPCs this tier just skipped — while a floating promise can
  // be torn down with the isolate, which would make the ledger a coin flip.
  const bumpLearned = async (row: LearnedAlias): Promise<void> => {
    try {
      await db
        .from('nb_patient_food_aliases')
        .update({ hit_count: (row.hit_count ?? 0) + 1, updated_at: new Date().toISOString() })
        .eq('id', row.id)
    } catch {
      // A lost increment is a lost statistic. Never a lost meal.
    }
  }

  const lookupAlias = async (term: string): Promise<Row | null> => {
    const { data } = await db
      .from('nb_food_aliases')
      .select('food_item_id')
      .eq('alias', term)
      .limit(1)
      .maybeSingle()
    const id = (data as { food_item_id?: string } | null)?.food_item_id
    return id ? await getRow(id) : null
  }

  // Tier 2 deps. Trigram + FTS only, NO embeddings: branded lookup is literal,
  // so a semantic nearest neighbour over 1.3M product names is noise, not help.
  const searchProducts = async (term: string): Promise<ProductCandidate[]> => {
    const { data, error } = await db.rpc('match_food_products', {
      q_text: term,
      match_count: 20,
    })
    if (error) throw new Error(`match_food_products: ${error.message}`)
    return (data ?? []).map((r: Record<string, unknown>) => ({
      id: String(r.id),
      name: String(r.name),
      brand: (r.brand as string | null) ?? null,
      lexSim: Number(r.lex_sim) || 0,
      wordSim: Number(r.word_sim) || 0,
      completeness:
        r.completeness === null || r.completeness === undefined ? null : Number(r.completeness),
    }))
  }

  // Keyed by COLUMN because two tiers need this same row by two different keys,
  // and the branded plane must not end up priced two ways:
  //   tier 2   holds the product's `id`, straight from match_food_products
  //   tier 0a  holds an `off_code` — because `nb_patient_food_aliases.food_item_id`
  //            has a hard FK to nb_food_items, so a product id there is a rejected
  //            insert, which is exactly why that table has an `off_code` column
  // `off_code` is UNIQUE on nb_food_products (verified against the live indexes
  // 2026-07-30), so both are single-row reads and `maybeSingle` is safe on either.
  const getProductBy = async (col: 'id' | 'off_code', value: string): Promise<Row | null> => {
    const { data } = await db.from('nb_food_products').select('*').eq(col, value).maybeSingle()
    return (data as Row) ?? null
  }
  const getProduct = (id: string): Promise<Row | null> => getProductBy('id', id)

  const resolveOne = async (rawName: string, grams: number): Promise<ResolvedItem> => {
    // A placeholder is not an ingredient, so NO composition is correct for it and
    // pricing one fabricates energy. On the held-out set these were 22% of all
    // grams: "dinner items" (3.6 kg) priced as "Rolls, dinner, egg" at 11,052
    // kcal, "breakfast items" (2.6 kg) as a breakfast biscuit at 11,574.
    //
    // This is the one case that deliberately breaks the never-unpriced rule,
    // because the rule assumes the name denotes a food. `unknown` is distinct
    // from `estimated`: an estimate is a real food we could not pin down, this is
    // not a food at all, and a caller must exclude it from meal totals rather
    // than treat it as a zero-calorie ingredient.
    if (isPlaceholder(rawName)) {
      return {
        name: rawName, local_name: null, estimated_grams: roundGrams(grams),
        kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0,
        micros: {}, category: null, basis: 'unknown', food_item_id: null,
        needs_review: true, review_reason: 'not_a_food', review_severity: 'orange',
      }
    }

    const q = normalise(rawName)
    const alternatives = q.alternatives.length ? q.alternatives : undefined

    // Tier 0a — THE PATIENT'S OWN CORRECTION, ahead of everything else.
    //
    // This is the READ half of the learning loop. `lib/meal-log/patient-aliases.ts`
    // writes `nb_patient_food_aliases` the moment a patient fixes a food, keyed by
    // `aliasKey(rawName)` — which is exactly `normalise(rawName).core`, the value
    // used below. That equality is not a convention anyone can be trusted to
    // remember: `lib/nutrition/resolve/__tests__/normalise-agreement.test.ts`
    // extracts THIS FILE'S normalise() and compares it to the client's, because a
    // one-character drift produces a write nothing ever reads — a learning loop
    // that looks like it works and teaches nothing.
    //
    // Without a patientId not one query is issued. That is the whole isolation
    // story for `resolve-foods`, which has no meal row and passes nothing.
    const learned = await lookupLearned(q.core)
    if (learned) {
      // GRAMS: THIS PLATE WINS. `grams_default` is a remembered portion and is
      // only ever a fallback — an answer to "what is this food" must not also
      // overrule how much of it is in front of the patient today.
      const g = grams > 0 ? grams : (learned.grams_default ?? grams)

      // A HIT SKIPS THE GUARDS, DELIBERATELY. The guards (head noun, form word,
      // diet, cooked state) exist to stop a RETRIEVAL mistake — a similarity
      // score handing "Low fat Quark" to peanut flour. Nothing was retrieved
      // here. The patient told us what their food is, against a row they picked
      // themselves. Running that through constraints written to police a scoring
      // function would let the system overrule the one participant in this loop
      // who actually ate the meal.
      const row = learned.food_item_id
        ? await getRow(learned.food_item_id)
        : learned.off_code
        ? await getProductBy('off_code', learned.off_code)
        : null

      if (row) {
        await bumpLearned(learned)
        // basis 'learned', NOT 'exact'. Both are hand-written decisions, but a
        // clinician reading `resolution_meta.basis` has to be able to tell "this
        // patient taught us this" from "a curator did": the first is one person's
        // word about their own food, the second is a practice-wide default.
        //
        // `foodItemId` carries the ROW's id either way, the same convention tier 2
        // already uses for a product — which is what lets the client's
        // classifyAliasTarget recognise a learned item if it is corrected again.
        return priceItem(row, g, { basis: 'learned', foodItemId: String(row.id), alternatives })
      }
      // THE ALIAS POINTS AT A ROW THAT IS GONE. Fall through to the rest of the
      // ladder rather than returning an unpriced item. Reference data moves under
      // us — CLINICAL runs its own migration sequence against this same database
      // and the two sequences already collide — so a stale pointer is a thing that
      // will happen. It costs one wasted read and the patient still gets a priced
      // meal, instead of a red flag caused by bookkeeping they never saw.
    }

    // Tier 0b — curated alias. (Tier 0a, the patient's own, ran above.)
    const alias = await lookupAlias(q.core)
    if (alias) {
      return priceItem(alias, grams, { basis: 'exact', foodItemId: String(alias.id), alternatives })
    }

    // Tier 0c — CURATED DECOMPOSITION. Runs with the aliases, not behind
    // retrieval, because a curated recipe is the same KIND of thing as an alias:
    // a deliberate human decision about what a name means.
    //
    // Behind retrieval it lost to lucky collisions. "mixed nuts" matched the
    // generic row "Nuts, mixed nuts, dry roasted, WITH PEANUTS, with salt added"
    // and returned before the recipe was ever consulted. That row is not wrong
    // exactly, but the curated recipe deliberately excludes peanuts, and in a
    // practice that tracks allergens the difference is not cosmetic.
    //
    // Some names are not one food.
    //
    // "mixed nuts" is four nuts and "mixed berries" is four berries; no single row
    // means either, so retrieval cannot win however good it gets. On the held-out
    // set "mixed berries" landed on a zero-calorie sports drink, and after the
    // form guard removed that, on a 371 kcal/100 g breakfast cereal. Neither is
    // berries.
    //
    // The safety rule: decomposition decides WHAT IS IN the food, never the
    // NUMBERS. Every component is resolved through this same ladder and priced
    // from the reference table, so a decomposed item is exactly as traceable as a
    // matched one.
    //
    // If any component fails to resolve, the whole decomposition is abandoned
    // rather than returning a partial total — a partial sum is the understating
    // bug in a new costume, and it would be indistinguishable from a real one.
    const recipe = decomposeCurated(rawName)
    if (recipe) {
      // Resolve each component at a 100 g BASE and scale exactly, rather than
      // resolving it at its share of the portion.
      //
      // roundGrams snaps to 10 g, which is right for a portion a patient sees but
      // breaks CONSERVATION OF MASS when applied per component: 100 g of mixed
      // nuts resolved as 30+25+25+20 came back as 30+30+30+20 = 110 g, a silent
      // 10% inflation of the whole entry. Pricing at 100 g and multiplying keeps
      // the parts summing to the portion the patient actually logged.
      const parts: ResolvedItem[] = []
      for (const comp of recipe) parts.push(await resolveOne(comp.name, 100))
      const share = (i: number) => (grams * recipe[i].fraction) / 100
      const priced = parts.filter((pt) => pt.basis !== 'estimated' && pt.basis !== 'unknown')
      if (priced.length === recipe.length) {
        const sum = (f: (i: ResolvedItem) => number) =>
          parts.reduce((a, i, idx) => a + f(i) * share(idx), 0)
        const micros: Record<string, number | null> = {}
        parts.forEach((part, idx) => {
          for (const [k, v] of Object.entries(part.micros)) {
            if (v === null) { if (!(k in micros)) micros[k] = null; continue }
            micros[k] = (micros[k] ?? 0) + v * share(idx)
          }
        })
        return {
          name: rawName,
          local_name: null,
          // A decomposed item is a recipe, not a catalogued food, so it has no
          // single category of its own. Scoring reads its `components` instead.
          category: null,
          estimated_grams: roundGrams(grams),
          kcal: sum((i) => i.kcal),
          protein_g: sum((i) => i.protein_g),
          carbs_g: sum((i) => i.carbs_g),
          fat_g: sum((i) => i.fat_g),
          fiber_g: sum((i) => i.fiber_g),
          micros,
          basis: 'decomposed',
          food_item_id: null,
          // Component grams are EXACT, not snapped to 10 g, so they sum to the
          // portion. Rounding them for display is the UI's call, not ours.
          components: parts.map((pt, i) => ({
            name: pt.name,
            grams: grams * recipe[i].fraction,
            kcal: pt.kcal * share(i),
            fraction: recipe[i].fraction,
            food_item_id: pt.food_item_id,
          })),
          ...(alternatives ? { alternatives } : {}),
        }
      }
    }

    // Tier 1 — hybrid retrieval over the core reading, then any alternatives.
    // Take the BEST reading rather than the first that clears the bar: "Roast
    // Beef" yields "beef" and "roast beef", and iteration order must not decide
    // which composition the patient is charged.
    //
    // CROSS-LANGUAGE readings are appended HERE, at retrieval, and never inside
    // normalise(): q.core is also the tier-0a alias key, and the response's
    // `alternatives` payload must not change shape either — these terms exist
    // only to be searched. Bounded to at most two (see crossLanguageTerms).
    const searchTerms = [q.core, ...q.alternatives, ...crossLanguageTerms(q.core)]
    let best: (Candidate & { score: number }) | null = null
    let anchor: (Candidate & { score: number }) | null = null
    for (const term of searchTerms) {
      if (!term) continue
      const candidates = await searchCandidates(term)
      // Guards run BEFORE scoring, so a semantically wrong candidate can never
      // win no matter how well it scores. These are hard constraints, not
      // weights: a held-out run found 37.8% of grams resolving to the wrong food
      // while still reporting `matched`, including dairy -> peanut flour and
      // beans -> pork kidney. Another coefficient would have moved a percentage;
      // these make the failures impossible.
      // Judge against BOTH the raw name and the normalised term.
      //
      // normalise() strips preparation words so retrieval can find candidates —
      // that is its job — but it therefore destroys the information the guards
      // enforce. "cooked rice" normalises to "rice", so COOKED_WORDS never
      // fires and Rice-raw (352 kcal/100 g) beats the cooked form (~130).
      // Filtering on `term` alone left the state guard correct, present, and
      // completely dead in production.
      const kept = candidates.filter((c) => !rejectCandidate(c, rawName) && !rejectCandidate(c, term))
      const hit = bestMatch(kept, term)
      if (hit && (!best || hit.score > best.score)) best = hit
      // Track the best guard-passing candidate even when it is under tau: it
      // cannot win, but it is the energy-density anchor the branded tier needs
      // (see energyDensitySane). The 0.35 floor keeps a barely-related row from
      // becoming "evidence"; 0 would let retrieval noise veto real products.
      const anyHit = bestMatch(kept, term, 0.35)
      if (anyHit && (!anchor || anyHit.score > anchor.score)) anchor = anyHit
    }
    if (best) {
      const row = await getRow(best.id)
      if (row) {
        return priceItem(row, grams, { basis: 'matched', foodItemId: best.id, alternatives })
      }
    }

    // Tier 2 — BRANDED PRODUCTS (Open Food Facts).
    //
    // Consulted only now, after generic retrieval and curated decomposition have
    // both failed, because this plane is much larger and lower-trust. CIQUAL and
    // SR Legacy are generic food databases; "Whey Protein" (1,225 g in the
    // held-out set), "Emmi lactose-free kefir" and "Spelt Protein Pancakes" are
    // branded groceries that will never appear in them, and no amount of tuning
    // closes that gap.
    //
    // The SAME guards apply. The branded plane needs them more, not less: "Whey
    // Protein" must not match "Soy Protein Isolate Bar" any more than it matched
    // "Soy protein isolate" in the generic plane — that is a dairy-to-soy allergen
    // swap either way. The cross-language readings matter MOST here: this is the
    // plane where "Almond Milk" finds "Lait d'amande" via the French fold.
    // The anchor's kcal is fetched ONCE, lazily, only now that the branded tier
    // is actually being consulted — tier-1 successes never pay for it.
    const anchorKcal: number | null = anchor
      ? (((await getRow(anchor.id))?.energy_kcal as number | null) ?? null)
      : null

    for (const term of searchTerms) {
      if (!term) continue
      const products = (await searchProducts(term)).filter(
        (p) => !rejectProduct(p, rawName) && !rejectProduct(p, term),
      )
      // Ranked list, not a single winner: the energy veto needs the runner-up.
      // For "Almond Milk" the top-ranked product IS the chocolate bar; the real
      // drink ("Lait d'amande bio non sucré", 15 kcal) is next in line.
      for (const top of rankedProducts(products)) {
        const prow = await getProduct(top.id)
        if (!prow) continue
        if (!energyDensitySane(anchorKcal, (prow.energy_kcal as number | null) ?? null)) {
          console.log(
            `[resolver] energy veto: "${top.name}" ${prow.energy_kcal} kcal/100g vs anchor ` +
              `"${anchor?.name}" ${anchorKcal} for query "${term}"`,
          )
          continue
        }
        return priceItem(prow, grams, { basis: 'matched', foodItemId: top.id, alternatives })
      }
    }

    // Tier 4 — TERMINAL. We could not identify this food, so we do NOT price it.
    //
    // This deliberately replaces the category-median fallback, on the evidence.
    // The median was inventing numbers that looked plausible and were badly
    // wrong: 550 g of "mixed berries" priced from the Breakfast Cereals median at
    // 371 kcal/100 g fabricated ~2,040 kcal; whey protein from the Baked Products
    // median carried 8 g protein/100 g against a real ~80.
    //
    // A category median is a confirmation the system gives ITSELF. Returning zero
    // with a flag is honest: the meal total understates, visibly, and a human
    // closes the gap. That is what the correction loop and the clinical lookup
    // queue exist for.
    //
    // This is NOT a return to the original bug. That bug was a SILENT zero with
    // no record that anything was missing. This zero is flagged red, surfaced to
    // the patient, and queued for the clinician.
    return {
      name: rawName,
      local_name: null,
      // roundGrams, not a second inline copy — the two had already drifted apart
      // once, so a 3 g portion was floored to 0 here while preserved elsewhere.
      estimated_grams: roundGrams(grams),
      kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0,
      micros: {},
      category: null,
      basis: 'estimated',
      food_item_id: null,
      needs_review: true,
      review_reason: 'not_found',
      review_severity: 'red',
      ...(alternatives ? { alternatives } : {}),
    }
  }

  // CONCURRENTLY, but BOUNDED. Every item is an independent walk down the ladder
  // and nothing downstream of item N depends on item N-1, so a sequential `for`
  // loop costs the SUM of every round-trip — that is the latency this was written
  // to avoid and the pool below keeps that win for any normal meal.
  //
  // Bounded only as a memory guard on pathological meals. `searchTerms` is the
  // core reading PLUS alternatives PLUS cross-language terms, and each one runs
  // `session.run(...)` — gte-small inference INSIDE this worker — so an unbounded
  // `Promise.all` over a 12-item meal fires ~40 in-process inferences at once.
  //
  // ⚠ THIS BOUND DOES NOT FIX THE 546. Measured against the deployed function on
  // 2026-08-05, before and after: a 12-item meal is killed either way, and the
  // same cliff appears on the TEXT path, which runs no vision model at all —
  //     3 items  200 (~3 s) · 6 items 200 (~4 s) · 9 items 200 (~9 s) · 12 items 546
  // Deterministic, monotonic in item count, indifferent to scheduling. So the
  // binding constraint is the isolate's CUMULATIVE per-request budget, not peak
  // concurrency, and no arrangement of the same total work will clear it. The real
  // fix has to cut total inferences per request or split pricing across requests;
  // this pool only stops a huge meal spiking memory on the way to that limit.
  //
  // Keep it generous: at 4 a nine-item meal took three waves and ~9 s, which is
  // slower than the unbounded version for no benefit.
  //
  // Order is preserved BY INDEX, which the caller relies on to merge the model's
  // flags back onto the priced items.
  const RESOLVE_POOL = 8
  const resolved: ResolvedItem[] = new Array(items.length)
  let cursor = 0
  await Promise.all(
    Array.from({ length: Math.min(RESOLVE_POOL, items.length) }, async () => {
      for (;;) {
        const i = cursor++
        if (i >= items.length) return
        const it = items[i]
        resolved[i] = await resolveOne(it.name, Number.isFinite(it.grams) ? it.grams : 0)
      }
    }),
  )
  return resolved
}
