// Meal COMPOSITION scoring — v2, rule-based, deterministic.
//
// WHAT CHANGED FROM v1, AND WHY IT HAD TO
// ---------------------------------------
// v1 scored three things it named `inflammation`, `glycemic` and `digestion`.
// Both halves of that were wrong.
//
// 1. THE NAMES WERE CLAIMS ABOUT A PERSON. "Your inflammation is 72/100" asserts a
//    physiological measurement taken from a photograph of a plate. The app cannot
//    make it, and the number never described the body in the first place — it
//    described the food. See docs/legal/40-code-compliance/score-rename-brief.md.
//
// 2. THE ENGINE MATCHED SUBSTRINGS. Classification was `name.includes(keyword)`
//    over hand-written word lists, which produced, measurably:
//      goat cheese      -> anti-inflammatory   ("oat" inside "g-OAT")
//      doughnut         -> anti-inflammatory AND pro-inflammatory ("nut")
//      sugar snap peas  -> refined carbohydrate ("sugar")
//      butternut squash -> anti-inflammatory + heavy ("nut", "butter")
//      honeydew melon   -> refined carbohydrate ("honey")
//    Across 189 real logged meals the result was a score that discriminated
//    almost nothing: 184/190 meals scored >=60 on inflammation, 171/190 on
//    glycemic, which never once fell below 55.
//
// v2 replaces both. It scores THREE CHARACTERISTICS OF THE MEAL, each named for
// what is actually computed, each higher-is-better, and it classifies foods from
// `nb_food_items.category` — a column populated on 100% of the 10,978 reference
// rows — falling back to WORD-BOUNDARY tokens, never substrings, so "goat" can
// no longer contain "oat".
//
//   plants_fibre — fibre content and plant variety in the recorded meal
//   fat_quality  — the fat SOURCES the meal draws on, and its saturated share
//   carb_quality — how much of the carbohydrate comes with fibre intact
//
// WHAT THIS MODULE DELIBERATELY DOES NOT COMPUTE
// ----------------------------------------------
// * NOT glycaemic load. `nb_food_items.glycemic_index` exists as a column and is
//   populated on 0 of 10,978 rows, and the branded plane carries no GI either.
//   A score named "glycaemic load" without GI data would repeat v1's sin pointed
//   the other way: a name asserting precision the data cannot support.
// * NOT a processing/NOVA score. `nova_score` is likewise 0% populated, and
//   nb_food_products has neither NOVA nor an ingredient list. Where processing
//   matters here it enters as an explicitly-labelled CATEGORY PROXY (a food
//   filed under "Fast Foods" or "Sweets"), never as a NOVA claim.
// * NOT a universal health grade. Three numbers that can disagree are the point;
//   collapsing them hides the trade-off the member is meant to see.
// * NOT personalised. The same meal scores the same for every member. Individual
//   physiology belongs to the separate longitudinal-reaction layer.
//
// Pure module (no imports) -> runs in Deno (Edge Function), Node, and the browser.

export type MealItem = {
  name: string
  estimated_grams?: number | null
  kcal?: number | null
  protein_g?: number | null
  carbs_g?: number | null
  fat_g?: number | null
  fiber_g?: number | null
  /** nb_food_items.category, when the item resolved to a reference row. */
  category?: string | null
  /** Per-item micronutrients from the resolver; `saturated_fat_g` and `sugar_g` live here. */
  micros?: Record<string, number | null> | null
  /** How the item was priced. Drives confidence, never the score itself. */
  basis?: 'exact' | 'learned' | 'matched' | 'decomposed' | 'estimated' | 'unknown' | null
}

/** Legacy triple, still the shape written to the three nb_meal_logs columns. */
export type MealScores = {
  inflammation: number
  glycemic: number
  digestion: number
}

export type ScoreKey = 'plants_fibre' | 'fat_quality' | 'carb_quality'
/** Qualitative band. This is the primary read; the number is secondary. */
export type Band = 'limited' | 'moderate' | 'strong' | 'very_strong'
/** How far the score can be trusted, given how the items were priced. */
export type Confidence = 'low' | 'moderate' | 'high'

export type ScoreResult = {
  /** 0-100, higher is better on ALL THREE. No score here is lower-is-better. */
  value: number
  band: Band
  confidence: Confidence
  /** Short driver labels for the explain card — what lifted it, what held it back. */
  drivers: { positive: string[]; limiting: string[] }
}

export type MealCompositionScores = {
  plants_fibre: ScoreResult
  fat_quality: ScoreResult
  carb_quality: ScoreResult
}

// ---------------------------------------------------------------------------
// Food classification
// ---------------------------------------------------------------------------
// PRIMARY SIGNAL IS `category`, because it is real data on 100% of reference
// rows. Names are only consulted to REFINE a category that is too coarse to
// score (CIQUAL files peas, apples, walnuts and lentils all under one heading)
// or to rescue an item that never matched a reference row at all.

export type FoodGroup =
  | 'vegetable' | 'fruit' | 'legume' | 'whole_grain' | 'refined_grain' | 'nut_seed' | 'herb_spice'
  | 'fish_oily' | 'fish_lean' | 'poultry' | 'red_meat' | 'processed_meat' | 'egg' | 'dairy'
  | 'oil_unsat' | 'oil_sat'
  | 'sweet' | 'sweet_drink' | 'fried_fast'
  | 'other'

/** The groups that count as a plant food for diversity and plant-mass share. */
const PLANT_GROUPS = new Set<FoodGroup>(['vegetable', 'fruit', 'legume', 'whole_grain', 'nut_seed'])

// Word-boundary tokens. `tokenise` splits on anything that is not a letter, so
// membership is an EXACT token match: "goat" never matches "oat", "doughnut"
// never matches "nut". This one change is why v2 exists.
const tokenise = (s: string): string[] =>
  (s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .split(/[^a-z]+/).filter(Boolean)

const has = (t: string[], ...words: string[]) => words.some((w) => t.includes(w))

// --- name-level refiners ---------------------------------------------------
const OILY_FISH = ['salmon', 'sardine', 'sardines', 'mackerel', 'herring', 'anchovy', 'anchovies', 'trout', 'kipper', 'saumon', 'maquereau', 'hareng']
const WHOLE_GRAIN = ['wholegrain', 'wholemeal', 'wholewheat', 'complet', 'complets', 'complete', 'completes', 'brown', 'oat', 'oats', 'oatmeal', 'porridge', 'barley', 'rye', 'quinoa', 'buckwheat', 'bulgur', 'spelt', 'farro', 'millet', 'sorghum', 'freekeh', 'avoine', 'seigle', 'orge', 'sarrasin', 'epeautre']
const REFINED_GRAIN = ['white', 'baguette', 'croissant', 'brioche', 'bagel', 'pastry', 'cracker', 'crackers', 'blanc', 'blanche']
const UNSAT_OIL = ['olive', 'rapeseed', 'canola', 'sunflower', 'linseed', 'flaxseed', 'walnut', 'avocado', 'sesame', 'colza', 'tournesol']
const SAT_OIL = ['butter', 'ghee', 'lard', 'tallow', 'dripping', 'suet', 'coconut', 'palm', 'margarine', 'shortening', 'beurre', 'saindoux']
const PROCESSED_MEAT = ['sausage', 'sausages', 'bacon', 'salami', 'pepperoni', 'chorizo', 'ham', 'prosciutto', 'pancetta', 'frankfurter', 'hotdog', 'mortadella', 'saucisse', 'saucisson', 'jambon', 'lardon', 'lardons', 'charcuterie', 'nugget', 'nuggets']
// NOTE "squash" is deliberately absent: it names both a soft drink and a
// vegetable, and butternut squash was being filed as a sweetened beverage.
const SWEET_DRINK = ['soda', 'cola', 'lemonade', 'cordial', 'juice', 'smoothie', 'milkshake', 'jus', 'limonade', 'sirop']
const FRIED_FAST = ['fried', 'deepfried', 'fries', 'chips', 'crisps', 'burger', 'cheeseburger', 'pizza', 'kebab', 'tempura', 'battered', 'breaded', 'frite', 'frites', 'pane', 'panee']
const SWEET = ['cake', 'biscuit', 'cookie', 'doughnut', 'donut', 'candy', 'sweets', 'chocolate', 'brownie', 'muffin', 'icecream', 'sorbet', 'jam', 'honey', 'syrup', 'sugar', 'gateau', 'bonbon', 'confiture', 'miel', 'sucre']
const LEGUME = ['lentil', 'lentils', 'chickpea', 'chickpeas', 'bean', 'beans', 'pea', 'peas', 'soy', 'soya', 'tofu', 'tempeh', 'edamame', 'hummus', 'houmous', 'lentille', 'lentilles', 'poischiche', 'haricot', 'haricots', 'feve', 'feves', 'pois']
const NUT_SEED = ['almond', 'almonds', 'walnut', 'walnuts', 'cashew', 'cashews', 'pecan', 'pecans', 'pistachio', 'pistachios', 'hazelnut', 'hazelnuts', 'peanut', 'peanuts', 'macadamia', 'seed', 'seeds', 'chia', 'flax', 'linseed', 'sesame', 'tahini', 'sunflower', 'pumpkinseed', 'amande', 'amandes', 'noix', 'noisette', 'graine', 'graines']
const FRUIT = ['apple', 'banana', 'orange', 'pear', 'peach', 'plum', 'grape', 'grapes', 'berry', 'berries', 'strawberry', 'strawberries', 'blueberry', 'blueberries', 'raspberry', 'raspberries', 'blackberry', 'mango', 'melon', 'watermelon', 'pineapple', 'kiwi', 'apricot', 'cherry', 'cherries', 'fig', 'figs', 'date', 'dates', 'avocado', 'pomme', 'banane', 'poire', 'peche', 'raisin', 'fraise', 'myrtille', 'framboise', 'abricot', 'cerise', 'figue', 'datte', 'avocat']
const EGG = ['egg', 'eggs', 'omelette', 'omelet', 'oeuf', 'oeufs']
const FISH_ANY = ['fish', 'cod', 'haddock', 'tuna', 'sole', 'hake', 'pollock', 'bass', 'bream', 'prawn', 'prawns', 'shrimp', 'crab', 'lobster', 'mussel', 'mussels', 'scallop', 'squid', 'poisson', 'cabillaud', 'thon', 'crevette', 'crevettes', 'moule', 'moules']
const POULTRY = ['chicken', 'turkey', 'duck', 'poulet', 'dinde', 'canard', 'volaille']
const RED_MEAT = ['beef', 'steak', 'pork', 'lamb', 'veal', 'venison', 'mutton', 'boeuf', 'porc', 'agneau', 'veau']
const DAIRY = ['milk', 'yogurt', 'yoghurt', 'cheese', 'cream', 'creme', 'quark', 'skyr', 'kefir', 'ricotta', 'mozzarella', 'cheddar', 'parmesan', 'feta', 'lait', 'fromage', 'yaourt']
const HERB_SPICE = ['herb', 'herbs', 'spice', 'spices', 'basil', 'parsley', 'coriander', 'cilantro', 'mint', 'thyme', 'rosemary', 'oregano', 'dill', 'chive', 'chives', 'sage', 'turmeric', 'cumin', 'paprika', 'cinnamon', 'ginger', 'pepper', 'peppercorn', 'basilic', 'persil', 'menthe', 'thym', 'romarin', 'aneth', 'curcuma', 'cannelle', 'gingembre']

// A category string from either taxonomy, lowercased for matching. USDA is
// title-case ("Vegetables and Vegetable Products"), CIQUAL lowercase
// ("fruits, vegetables, legumes and nuts") — both are matched here.
const VEGETABLE = ['vegetable', 'vegetables', 'potato', 'potatoes', 'sweetcorn', 'corn', 'squash', 'pumpkin', 'courgette', 'zucchini', 'aubergine', 'eggplant', 'tomato', 'tomatoes', 'carrot', 'carrots', 'broccoli', 'cauliflower', 'cabbage', 'kale', 'spinach', 'lettuce', 'salad', 'rocket', 'arugula', 'leek', 'leeks', 'onion', 'onions', 'garlic', 'celery', 'cucumber', 'beetroot', 'beet', 'turnip', 'parsnip', 'radish', 'asparagus', 'artichoke', 'fennel', 'mushroom', 'mushrooms', 'pepper', 'peppers', 'sprouts', 'chard', 'okra', 'legume', 'legumes', 'pommedeterre', 'courgettes', 'aubergines', 'chou', 'epinard', 'epinards', 'laitue', 'poireau', 'oignon', 'ail', 'concombre', 'betterave', 'champignon', 'champignons', 'poivron', 'carotte', 'carottes', 'salade', 'legume']
// Plant "milks" and "yoghurts" take the head noun of a dairy food while being a
// grain, nut or legume. Without this, oat milk scores as dairy and vanishes from
// plant diversity — and coconut yoghurt lands in the wrong fat class entirely.
const DAIRY_HEAD = ['milk', 'yogurt', 'yoghurt', 'cream', 'lait', 'yaourt', 'creme']
const PLANT_MILK_SOURCE: Array<[string, FoodGroup]> = [
  ['oat', 'whole_grain'], ['oats', 'whole_grain'], ['rice', 'refined_grain'], ['spelt', 'whole_grain'],
  ['almond', 'nut_seed'], ['cashew', 'nut_seed'], ['hazelnut', 'nut_seed'], ['walnut', 'nut_seed'],
  ['soy', 'legume'], ['soya', 'legume'], ['pea', 'legume'],
  ['coconut', 'oil_sat'], ['avoine', 'whole_grain'], ['amande', 'nut_seed'], ['soja', 'legume'], ['coco', 'oil_sat'],
]

const cat = (c: string | null | undefined) => (c || '').toLowerCase()

/**
 * The reference category, when it is specific enough to decide on its own.
 *
 * Category BEATS the name, because it is real data and the name is prose. Getting
 * this order wrong is exactly how v1 filed "strawberry jam" as fruit and
 * "sugar snap peas" as confectionery. Returns null for the coarse CIQUAL headings
 * ("fruits, vegetables, legumes and nuts") that genuinely need the name to split.
 */
function categoryGroup(c: string, t: string[]): FoodGroup | null {
  if (!c) return null
  if (c.includes('vegetables and vegetable products')) return 'vegetable'
  if (c.includes('legumes and legume')) return 'legume'
  if (c.includes('nut and seed')) return 'nut_seed'
  if (c.includes('spices and herbs')) return 'herb_spice'
  if (c.includes('fruits and fruit juices')) return has(t, ...SWEET_DRINK) ? 'sweet_drink' : 'fruit'
  if (c.includes('sweets') || c.includes('sugar and confectionery') || c.includes('ice cream')) return 'sweet'
  if (c.includes('finfish')) return has(t, ...OILY_FISH) ? 'fish_oily' : 'fish_lean'
  if (c.includes('poultry')) return 'poultry'
  if (c.includes('beef products') || c.includes('pork products') || c.includes('lamb, veal')) return 'red_meat'
  if (c.includes('sausages and luncheon')) return 'processed_meat'
  if (c.includes('dairy and egg')) return has(t, ...EGG) ? 'egg' : 'dairy'
  if (c.includes('milk and milk products')) return 'dairy'
  if (c.includes('fast foods') || c.includes('snacks')) return 'fried_fast'
  if (c.includes('cereal') || c.includes('baked products') || c.includes('breakfast cereals') || c.includes('grains and pasta'))
    return has(t, ...WHOLE_GRAIN) ? 'whole_grain' : 'refined_grain'
  // "Fats and Oils" holds olive oil, lard and chicken fat alike, so the name has
  // to split it; an unrecognised fat stays neutral rather than assuming the worst.
  if (c.includes('fats and oils')) return has(t, ...SAT_OIL) ? 'oil_sat' : has(t, ...UNSAT_OIL) ? 'oil_unsat' : 'other'
  return null
}

/**
 * Classify one item into a scoring group.
 *
 * Order of authority:
 *   1. preparation that changes the food's character (deep-fried, cured)
 *   2. the reference category, when specific
 *   3. the HEAD NOUN of the name — the last token in English, which is what
 *      makes "strawberry jam" a sweet and "sugar snap peas" a legume
 *   4. any recognised token anywhere in the name
 */
export function classifyItem(name: string, category?: string | null): FoodGroup {
  const t = tokenise(name)
  const c = cat(category)

  // 1. Preparation and cure beat provenance: a deep-fried potato is not a
  //    vegetable for fat-source purposes, and cured pork is not fresh meat.
  if (has(t, ...FRIED_FAST)) return 'fried_fast'
  if (has(t, ...PROCESSED_MEAT)) return 'processed_meat'

  // 2. Real data, where it is specific enough to be decisive.
  const byCategory = categoryGroup(c, t)
  if (byCategory) return byCategory

  // 3. Head noun. English compounds put it last ("sugar snap PEAS", "strawberry
  //    JAM"), which resolves the ambiguous cases the token sweep gets wrong.
  const head = t[t.length - 1] ?? ''
  const isHead = (arr: string[]) => arr.includes(head)
  if (isHead(SWEET_DRINK)) return 'sweet_drink'
  if (isHead(SWEET)) return 'sweet'
  if (isHead(LEGUME)) return 'legume'
  if (isHead(NUT_SEED)) return 'nut_seed'
  if (isHead(FRUIT)) return 'fruit'
  if (isHead(OILY_FISH)) return 'fish_oily'
  // "peanut butter" and "almond butter" are nuts, not butter. The head noun rule
  // has to yield to the qualifier here, because the qualifier IS the food.
  if (head === 'butter' && has(t, ...NUT_SEED)) return 'nut_seed'
  if (DAIRY_HEAD.includes(head)) {
    const plant = PLANT_MILK_SOURCE.find(([w]) => t.includes(w))
    if (plant) return plant[1]
    return 'dairy'
  }
  if (isHead(DAIRY)) return 'dairy'

  // 4. Any recognised token, most specific class first.
  if (has(t, ...SWEET_DRINK)) return 'sweet_drink'
  if (c.includes('fats and oils') || has(t, 'oil', 'huile')) {
    if (has(t, ...SAT_OIL)) return 'oil_sat'
    if (has(t, ...UNSAT_OIL)) return 'oil_unsat'
  }
  if (has(t, ...SAT_OIL)) return 'oil_sat'
  if (has(t, ...SWEET)) return 'sweet'
  if (has(t, ...OILY_FISH)) return 'fish_oily'
  if (has(t, ...FISH_ANY)) return 'fish_lean'
  if (has(t, ...EGG)) return 'egg'
  if (has(t, ...POULTRY)) return 'poultry'
  if (has(t, ...RED_MEAT)) return 'red_meat'
  if (has(t, ...DAIRY)) return 'dairy'
  if (has(t, ...NUT_SEED)) return 'nut_seed'
  if (has(t, ...LEGUME)) return 'legume'
  if (has(t, ...HERB_SPICE)) return 'herb_spice'
  // Grains BEFORE fruit: "banana bread" is a bread. A fruit word can qualify a
  // baked good, but a grain word rarely qualifies a fruit.
  if (has(t, ...WHOLE_GRAIN)) return 'whole_grain'
  if (has(t, ...REFINED_GRAIN, 'bread', 'pasta', 'rice', 'risotto', 'noodle', 'noodles', 'couscous', 'pain', 'riz')) return 'refined_grain'
  if (has(t, ...FRUIT)) return 'fruit'
  if (has(t, ...VEGETABLE)) return 'vegetable'

  // CIQUAL's combined plant heading, reached only when no name refiner fired.
  if (c.includes('fruits, vegetables, legumes and nuts')) return 'vegetable'
  if (c.includes('vegetable')) return 'vegetable'
  return 'other'
}

// ---------------------------------------------------------------------------
// Numeric helpers
// ---------------------------------------------------------------------------
const num = (v: unknown): number => (typeof v === 'number' && Number.isFinite(v) ? v : 0)
const clamp01 = (v: number): number => (v < 0 ? 0 : v > 1 ? 1 : v)
const pct = (v: number): number => Math.max(0, Math.min(100, Math.round(v * 100)))

/** 0 at `lo`, 1 at `hi`, linear between. Used wherever evidence gives a range. */
const ramp = (v: number, lo: number, hi: number): number => (hi === lo ? 0 : clamp01((v - lo) / (hi - lo)))

/**
 * Diminishing returns: 0 at 0, ~0.63 at k, ~0.86 at 2k, never quite 1.
 * Plant variety plateaus — the sixth vegetable adds less than the second — and a
 * linear count would let one over-itemised salad max the score.
 */
const saturating = (v: number, k: number): number => (v <= 0 ? 0 : 1 - Math.exp(-v / k))

const band = (v: number): Band => (v >= 80 ? 'very_strong' : v >= 60 ? 'strong' : v >= 40 ? 'moderate' : 'limited')

// How much a score can be trusted, per item, from how the resolver priced it.
// This is CONFIDENCE ONLY — it never moves the score itself, because a poorly
// matched food should read as "we are unsure", not as a worse meal.
const BASIS_TRUST: Record<string, number> = {
  exact: 1, learned: 0.95, matched: 0.85, decomposed: 0.75, estimated: 0.35, unknown: 0.1,
}

const confidenceBand = (t: number): Confidence => (t >= 0.8 ? 'high' : t >= 0.5 ? 'moderate' : 'low')

type Feat = {
  group: FoodGroup
  grams: number
  kcal: number
  carbs: number
  fiber: number
  fat: number
  satFat: number | null
  sugar: number | null
  omega3: number | null
  name: string
  trust: number
}

/** Distinct plant foods, by head noun, so "cherry tomatoes" and "tomato" are one plant. */
function distinctPlants(feats: Feat[]): { count: number; herbs: number } {
  const seen = new Set<string>()
  let herbs = 0
  for (const f of feats) {
    if (f.group === 'herb_spice') { herbs++; continue }
    if (!PLANT_GROUPS.has(f.group)) continue
    const t = tokenise(f.name)
    // The last token is usually the head noun in English ("red bell pepper"),
    // the first in French ("poivron rouge"). Keying on the SET of tokens sorted
    // would over-split; the longest token is a stable, cheap proxy for the noun.
    const head = t.slice().sort((a, b) => b.length - a.length)[0] ?? f.name.toLowerCase()
    seen.add(head)
  }
  return { count: seen.size, herbs }
}

// ---------------------------------------------------------------------------
// Score 1 — Plants & Fibre
// ---------------------------------------------------------------------------
// "How much fibre, and how many different plant foods, this meal contains."
//
// Three parts, because any one alone is gameable or unfair:
//   fibre amount   45%  — density per 1000 kcal (portion-fair) blended with the
//                         absolute grams (so a 30 kcal side of leaves is not a
//                         100 for containing 1 g of fibre in 30 calories)
//   plant variety  35%  — distinct plant foods, saturating
//   plant share    20%  — plant grams as a fraction of the plate
//
// ANCHORS. Fibre density 14 g/1000 kcal is the US Dietary Guidelines adequate-
// intake reference expressed per energy. 10 g in a main meal is roughly a third
// of the 25-30 g/day EFSA and WHO both land on. Both are POPULATION references
// for a day's eating, used here only to set the top of a 0-100 range for one
// meal — this is not a claim about the member's requirement.
function scorePlantsFibre(feats: Feat[], totals: { kcal: number; grams: number; fiber: number }): ScoreResult {
  const positive: string[] = []
  const limiting: string[] = []

  const density = totals.kcal > 0 ? totals.fiber / (totals.kcal / 1000) : 0
  const densityPart = ramp(density, 0, 14)
  const absolutePart = ramp(totals.fiber, 0, 10)
  const fibrePart = 0.6 * densityPart + 0.4 * absolutePart

  const { count, herbs } = distinctPlants(feats)
  // Herbs and spices are real plant diversity but come in gram quantities, so
  // they contribute at a quarter each and cannot carry the variety score alone.
  const varietyCount = count + Math.min(herbs * 0.25, 1)
  const varietyPart = saturating(varietyCount, 2.5)

  const plantGrams = feats.filter((f) => PLANT_GROUPS.has(f.group)).reduce((a, f) => a + f.grams, 0)
  const sharePart = totals.grams > 0 ? clamp01(plantGrams / totals.grams) : 0

  const value = pct(0.45 * fibrePart + 0.35 * varietyPart + 0.20 * sharePart)

  if (totals.fiber >= 8) positive.push(`${Math.round(totals.fiber)} g of fibre`)
  if (count >= 4) positive.push(`${count} different plant foods`)
  else if (count >= 2) positive.push(`${count} plant foods`)
  if (herbs > 0) positive.push('herbs and spices add variety')
  const topPlant = feats.filter((f) => PLANT_GROUPS.has(f.group)).sort((a, b) => b.fiber - a.fiber)[0]
  if (topPlant && topPlant.fiber >= 3) positive.push(`${topPlant.name} is a strong fibre source`)

  if (totals.fiber < 5) limiting.push('little fibre in this meal')
  if (count === 0) limiting.push('no plant foods recorded')
  else if (count === 1) limiting.push('all the plant content came from one food')
  if (sharePart < 0.25 && count > 0) limiting.push('plants are a small part of the plate')

  const trust = weightedTrust(feats)
  return { value, band: band(value), confidence: confidenceBand(trust), drivers: trim(positive, limiting) }
}

// ---------------------------------------------------------------------------
// Score 2 — Fat Quality
// ---------------------------------------------------------------------------
// "Where this meal's fat comes from" — NOT how much fat it contains.
//
// The PRD is explicit that this must not become a low-fat score, so total fat
// is deliberately absent from the formula: a handful of walnuts and a spoon of
// olive oil should score well while being almost entirely fat.
//
//   source quality 55%  — grams-weighted score of the fat-BEARING foods
//   unsaturated share 35% — (fat - saturated) / fat, when saturated fat is known
//   omega-3 present 10% — a bonus only; its ABSENCE is never a penalty, because
//                         omega3_g is populated on only 24-45% of reference rows
//                         and "unmeasured" must not read as "none".
//
// A meal with no fat at all is not scored on fat: it returns a neutral value at
// low confidence rather than a 0, because "no fat here" is not "poor-quality fat".
const FAT_SOURCE_QUALITY: Partial<Record<FoodGroup, number>> = {
  nut_seed: 1, oil_unsat: 1, fish_oily: 1,
  fruit: 0.9,            // avocado and olives land here
  fish_lean: 0.8, legume: 0.8, whole_grain: 0.75, vegetable: 0.75,
  egg: 0.65, poultry: 0.6,
  dairy: 0.45, red_meat: 0.4, oil_sat: 0.3,
  refined_grain: 0.3, sweet: 0.2, fried_fast: 0.1, processed_meat: 0.1,
  other: 0.5, herb_spice: 0.5, sweet_drink: 0.3,
}

function scoreFatQuality(feats: Feat[], totals: { fat: number }): ScoreResult {
  const positive: string[] = []
  const limiting: string[] = []
  const fatBearing = feats.filter((f) => f.fat > 0.5)

  if (totals.fat < 3 || fatBearing.length === 0) {
    return {
      value: 60, band: 'strong', confidence: 'low',
      drivers: { positive: [], limiting: ['very little fat in this meal to assess'] },
    }
  }

  const fatGrams = fatBearing.reduce((a, f) => a + f.fat, 0) || 1
  const sourcePart = clamp01(
    fatBearing.reduce((a, f) => a + (FAT_SOURCE_QUALITY[f.group] ?? 0.5) * f.fat, 0) / fatGrams,
  )

  // Saturated fat is known for the item only when the resolver priced it from a
  // reference row carrying the column. Items missing it are excluded from the
  // ratio rather than counted as zero, and their share lowers confidence.
  const withSat = fatBearing.filter((f) => f.satFat !== null)
  const satCoverage = withSat.reduce((a, f) => a + f.fat, 0) / fatGrams
  let unsatPart = sourcePart // fall back to the source read when satfat is unknown
  let satShare: number | null = null
  if (satCoverage >= 0.5) {
    const satSum = withSat.reduce((a, f) => a + (f.satFat ?? 0), 0)
    const fatSum = withSat.reduce((a, f) => a + f.fat, 0) || 1
    satShare = clamp01(satSum / fatSum)
    // EFSA and WHO both frame saturated fat as "as low as practicable"; a third
    // of total fat is the pragmatic anchor used here for the top of the range.
    unsatPart = 1 - ramp(satShare, 0.33, 0.75)
  }

  const o3 = feats.reduce((a, f) => a + (f.omega3 ?? 0), 0)
  const o3Part = ramp(o3, 0, 1.5)

  const value = pct(0.55 * sourcePart + 0.35 * unsatPart + 0.10 * o3Part)

  const best = fatBearing.slice().sort((a, b) => (FAT_SOURCE_QUALITY[b.group] ?? 0.5) - (FAT_SOURCE_QUALITY[a.group] ?? 0.5))[0]
  const worst = fatBearing.slice().sort((a, b) => (FAT_SOURCE_QUALITY[a.group] ?? 0.5) - (FAT_SOURCE_QUALITY[b.group] ?? 0.5))[0]
  if (best && (FAT_SOURCE_QUALITY[best.group] ?? 0) >= 0.8) positive.push(`fat mostly from ${best.name}`)
  if (o3 >= 0.5) positive.push('contains omega-3 fats')
  if (satShare !== null && satShare <= 0.33) positive.push('mostly unsaturated fat')
  if (satShare !== null && satShare >= 0.5) limiting.push('a large share of the fat is saturated')
  if (worst && (FAT_SOURCE_QUALITY[worst.group] ?? 1) <= 0.3) limiting.push(`${worst.name} contributes lower-quality fat`)

  const trust = weightedTrust(fatBearing) * (satCoverage >= 0.5 ? 1 : 0.6)
  return { value, band: band(value), confidence: confidenceBand(trust), drivers: trim(positive, limiting) }
}

// ---------------------------------------------------------------------------
// Score 3 — Carb Quality
// ---------------------------------------------------------------------------
// "How much of this meal's carbohydrate arrives with its fibre intact."
//
// THIS IS NOT GLYCAEMIC LOAD, and is deliberately not named as such. Glycaemic
// load requires a glycaemic index per food; `nb_food_items.glycemic_index` is
// populated on 0 of 10,978 rows. What CAN be computed honestly is the quality of
// the carbohydrate as composition data describes it:
//
//   carb:fibre ratio 40% — the 10:1 rule (Mozaffarian et al., and the basis of
//                          the AHA/Harvard "carbohydrate quality" heuristic):
//                          a food with at least 1 g fibre per 10 g carbohydrate
//                          is behaving like an intact whole food.
//   whole source     35% — carbohydrate grams from intact sources (whole grains,
//                          legumes, vegetables, whole fruit) over total carb grams
//   free-sugar proxy 25% — sugar from confectionery, sweetened drinks and baked
//                          sweets. Sugar inside whole fruit, vegetables and plain
//                          dairy is NOT counted against the meal, which is the
//                          whole-fruit-versus-juice distinction the PRD asks for.
//
// A meal with almost no carbohydrate is not scored on carbohydrate: like the fat
// score it returns neutral at low confidence rather than a spurious 100.
const WHOLE_CARB_GROUPS = new Set<FoodGroup>(['whole_grain', 'legume', 'vegetable', 'fruit', 'nut_seed'])
const FREE_SUGAR_GROUPS = new Set<FoodGroup>(['sweet', 'sweet_drink', 'fried_fast', 'refined_grain'])

function scoreCarbQuality(feats: Feat[], totals: { carbs: number; fiber: number }): ScoreResult {
  const positive: string[] = []
  const limiting: string[] = []

  if (totals.carbs < 5) {
    return {
      value: 60, band: 'strong', confidence: 'low',
      drivers: { positive: [], limiting: ['very little carbohydrate in this meal to assess'] },
    }
  }

  // 10:1 carbohydrate-to-fibre is the "intact" threshold; 5:1 is exceptional.
  const ratio = totals.fiber / totals.carbs
  const ratioPart = ramp(ratio, 0.02, 0.20)

  const carbGrams = feats.reduce((a, f) => a + f.carbs, 0) || 1
  const wholeCarbs = feats.filter((f) => WHOLE_CARB_GROUPS.has(f.group)).reduce((a, f) => a + f.carbs, 0)
  const wholePart = clamp01(wholeCarbs / carbGrams)

  // Free-sugar PROXY: sugar measured on items whose category marks them as
  // confectionery, sweetened drinks or sweet baked goods. Labelled a proxy in
  // every user-facing string, because no ingredient list is available to
  // separate added from intrinsic sugar properly.
  const freeSugar = feats
    .filter((f) => FREE_SUGAR_GROUPS.has(f.group))
    .reduce((a, f) => a + (f.sugar ?? 0), 0)
  // 25 g is the WHO conditional guideline for free sugars across a whole DAY;
  // reaching it in one meal is the bottom of this component's range.
  const freeSugarPart = 1 - ramp(freeSugar, 5, 25)

  const value = pct(0.40 * ratioPart + 0.35 * wholePart + 0.25 * freeSugarPart)

  if (ratio >= 0.1) positive.push('carbohydrate comes with its fibre')
  const topWhole = feats.filter((f) => WHOLE_CARB_GROUPS.has(f.group)).sort((a, b) => b.carbs - a.carbs)[0]
  if (topWhole && topWhole.carbs >= 5) positive.push(`${topWhole.name} is an intact carbohydrate source`)
  if (freeSugar > 0 && freeSugar < 5) positive.push('little added sugar')

  if (ratio < 0.05) limiting.push('carbohydrate arrives with little fibre')
  if (wholePart < 0.4) {
    const topRefined = feats.filter((f) => !WHOLE_CARB_GROUPS.has(f.group) && f.carbs > 0).sort((a, b) => b.carbs - a.carbs)[0]
    limiting.push(topRefined ? `most carbohydrate came from ${topRefined.name}` : 'most carbohydrate came from refined sources')
  }
  if (freeSugar >= 10) limiting.push(`about ${Math.round(freeSugar)} g sugar from sweetened foods`)

  const carbBearing = feats.filter((f) => f.carbs > 0.5)
  return { value, band: band(value), confidence: confidenceBand(weightedTrust(carbBearing)), drivers: trim(positive, limiting) }
}

// ---------------------------------------------------------------------------
// Assembly
// ---------------------------------------------------------------------------

/** Grams-weighted mean trust. An unmatched garnish should not sink a whole meal. */
function weightedTrust(feats: Feat[]): number {
  const w = feats.reduce((a, f) => a + f.grams, 0)
  if (w <= 0) return feats.length ? feats.reduce((a, f) => a + f.trust, 0) / feats.length : 0
  return feats.reduce((a, f) => a + f.trust * f.grams, 0) / w
}

/** At most three drivers a side — the PRD's rule, and the card only has room for three. */
const trim = (positive: string[], limiting: string[]) => ({
  positive: positive.slice(0, 3),
  limiting: limiting.slice(0, 3),
})

function featurise(items: MealItem[]): Feat[] {
  return items.map((it) => {
    const m = it.micros ?? {}
    const pick = (k: string): number | null => {
      const v = m[k]
      return typeof v === 'number' && Number.isFinite(v) ? v : null
    }
    return {
      name: it.name || 'item',
      group: classifyItem(it.name || '', it.category),
      // 50 g when the portion is unknown, so an unweighed item still participates
      // in the share and diversity terms instead of silently vanishing.
      grams: num(it.estimated_grams) || 50,
      kcal: num(it.kcal),
      carbs: num(it.carbs_g),
      fiber: num(it.fiber_g),
      fat: num(it.fat_g),
      satFat: pick('saturated_fat_g'),
      sugar: pick('sugar_g'),
      omega3: pick('omega3_g'),
      trust: BASIS_TRUST[it.basis ?? 'matched'] ?? 0.85,
    }
  })
}

/**
 * The three composition scores for one meal.
 *
 * Deterministic and pure: the same items always produce the same numbers, on any
 * runtime, for any member. No language model participates — the model identifies
 * foods and portions, and everything below is arithmetic over reference data.
 */
export function scoreMealComposition(items: MealItem[]): MealCompositionScores {
  const feats = featurise(items ?? [])
  if (feats.length === 0) {
    const empty = (): ScoreResult => ({ value: 60, band: 'strong', confidence: 'low', drivers: { positive: [], limiting: ['no foods recorded'] } })
    return { plants_fibre: empty(), fat_quality: empty(), carb_quality: empty() }
  }
  const totals = {
    kcal: feats.reduce((a, f) => a + f.kcal, 0),
    grams: feats.reduce((a, f) => a + f.grams, 0),
    carbs: feats.reduce((a, f) => a + f.carbs, 0),
    fiber: feats.reduce((a, f) => a + f.fiber, 0),
    fat: feats.reduce((a, f) => a + f.fat, 0),
  }
  // kcal is occasionally absent on manually added items; derive it so the
  // per-1000-kcal fibre density stays meaningful rather than dividing by zero.
  if (totals.kcal <= 0) {
    totals.kcal = feats.reduce((a, f) => a + f.carbs * 4 + f.fat * 9, 0)
  }
  return {
    plants_fibre: scorePlantsFibre(feats, totals),
    fat_quality: scoreFatQuality(feats, totals),
    carb_quality: scoreCarbQuality(feats, totals),
  }
}

// ---------------------------------------------------------------------------
// The boundary mapper — new concepts out, legacy columns in
// ---------------------------------------------------------------------------
// `nb_meal_logs.inflammation_score` / `.glycemic_score` / `.gut_score` are read by
// CLINICAL and the members dashboard, which live in SEPARATE REPOSITORIES. Renaming
// the columns here would break them silently, so the columns stay and the
// translation happens exactly here, once.
//
// POLARITY CHECK (the trap flagged in the rename brief): all three legacy columns
// are already higher-is-better — higher inflammation_score meant "calmer", higher
// glycemic_score meant "steadier", higher gut_score meant "easier". All three new
// scores are higher-is-better too. This mapping therefore does NOT invert the
// meaning of any stored number, and a historical row and a new row can sit in the
// same chart without one of them reading backwards.
//
// Which new score lands in which old column follows what each column's arithmetic
// was actually driven by in v1, so trend history stays roughly continuous:
//   gut_score          <- plants_fibre  (v1's digestion term was fibre and fat load)
//   inflammation_score <- fat_quality   (v1's anti/pro lists were mostly fat sources)
//   glycemic_score     <- carb_quality  (v1's term was net carbs and refined share)
export const SCORE_COLUMN_MAP: Record<ScoreKey, 'inflammation_score' | 'glycemic_score' | 'gut_score'> = {
  plants_fibre: 'gut_score',
  fat_quality: 'inflammation_score',
  carb_quality: 'glycemic_score',
}

/**
 * Legacy triple, for the DB write and the callers that still speak it.
 *
 * Kept so `scoreMeal` remains drop-in: the field NAMES here are storage keys, not
 * claims. Nothing user-facing may read these words — the app reads
 * `scoreMealComposition` and `lib/scores/score-content.ts`.
 */
export function scoreMeal(items: MealItem[]): MealScores {
  const s = scoreMealComposition(items)
  return {
    inflammation: s.fat_quality.value,
    glycemic: s.carb_quality.value,
    digestion: s.plants_fibre.value,
  }
}

/** Read the legacy columns back out as the three named concepts. */
export function fromLegacyColumns(row: {
  inflammation_score?: number | null
  glycemic_score?: number | null
  gut_score?: number | null
}): Partial<Record<ScoreKey, number>> {
  const out: Partial<Record<ScoreKey, number>> = {}
  if (typeof row.gut_score === 'number') out.plants_fibre = row.gut_score
  if (typeof row.inflammation_score === 'number') out.fat_quality = row.inflammation_score
  if (typeof row.glycemic_score === 'number') out.carb_quality = row.glycemic_score
  return out
}
