// The foods a MEMBER stated, carried structured all the way to identification.
//
// ⚠ PURE LEAF — same rule as meal-coverage.ts and identify-parts.ts: no `npm:`
// and no `https://esm.sh/` imports, ever. `lib/` imports this file directly so
// the client and the edge function share ONE implementation of the guard below,
// and so it is testable from vitest rather than only from a deployed function.
//
// ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
//
// The voice flow already knows, exactly, what the member said. `preprocess-meal`
// returns `{ name, quantity, estimated_g, volume_measure, confidence }` per item
// and the preprocess store keeps all five fields. Then, at one line, every one
// of them collapsed into a single free-text string:
//
//   items.map((i) => `${i.name} ${i.estimated_g}g`).join(', ')
//
// and that string — "chicken 100g, parmigiano 30g" — was the ONLY thing that
// left the voice flow. `analyze-meal` had no structured input at all, so a
// number the member had stated OUT LOUD was handed to a language model as prose
// and re-parsed. The model, reasonably, read "chicken 100g" as a food NAME.
//
// Thomas, 2026-08-20: "When I said 100 g of chicken, it's not changing the
// number of grams that is going to be passed to the AI for analysis with the
// database. It is putting the 100 g in the title, like 'chicken 100 g.' By the
// way, it disappeared from my final count."
//
// The disappearance was measured on 2026-08-21 and it is not a coincidence — a
// glued-on quantity actively poisons the food resolver:
//
//   · `normalise()` keeps digits (`\p{N}` is in its keep-class), so the search
//     core stays "chicken 100 g".
//   · Measured against the live nb_food_items: word_similarity drops from 1.000
//     to 0.571 and trigram similarity from 0.667 to 0.444 for every top
//     candidate.
//   · `headMatches` compares the query's LAST token to the candidate's first —
//     so the head becomes "g" and the 0.25 head bonus is spent on nothing.
//   · Below tau the ladder falls to its TERMINAL tier: `kcal: 0`,
//     `needs_review: true`. Zero, not null. The row looks priced and contributes
//     nothing. See [[lessons/a-zero-is-not-a-price]].
//
// This is the same shape as [[lessons/a-cache-key-is-a-language-boundary]]:
// information that WAS structured gets flattened at a boundary, and has to be
// re-derived by guessing on the other side.
//
// ── THE RULE ────────────────────────────────────────────────────────────────
//
// A member-stated quantity is a FACT, not a hint. The prompt asks the model to
// respect it; `applyStatedGrams` then ENFORCES it in code, because a prompt is
// not a guarantee and a guarantee is what a stated number deserves.

// ⚠ NO IMPORTS, AND NOTHING MAY IMPORT ONE INTO THIS FILE. `lib/` reaches this
// module directly and `tsc --noEmit` type-checks whatever it reaches, where a
// Deno-style `./x.ts` specifier is TS5097. That is also why the PROMPT half of
// this feature lives in `identify-parts.ts` beside the rest of the prompt text,
// rather than here beside the type it renders.

/** One food the member stated, with the portion they stated for it. */
export type StatedItem = {
  name: string
  grams: number
  /** "1 cup", "2 tbsp" — what they actually said, when they said a volume. */
  volume_measure?: string
}

/**
 * Cap on stated items per meal. `preprocess-meal` already caps its extraction at
 * 8; this is the looser bound that also covers rows the member added by hand on
 * the confirmation card, and it exists so a malformed body cannot push an
 * unbounded list into a model prompt.
 */
export const MAX_STATED_ITEMS = 20

const toFiniteNumber = (v: unknown): number => {
  const n = typeof v === 'string' ? Number(v) : v
  return typeof n === 'number' && Number.isFinite(n) ? n : 0
}

/**
 * A trailing portion glued onto a food name: "chicken 100 g", "rice 200g",
 * "yogurt 250 ml".
 *
 * Anchored at the END and requiring BOTH a number and a unit, which is what
 * keeps it away from the names that legitimately carry digits — the live table
 * holds "16% fat beef" and "87% Dark Chocolate", and both survive this untouched.
 */
const TRAILING_QUANTITY =
  /[\s,·-]+\d+(?:[.,]\d+)?\s*(?:g|gr|gram|grams|gramme|grammes|kg|mg|ml|cl|dl|l|oz|lb)\.?$/i

/**
 * Strip a portion the model glued onto a food name.
 *
 * Deterministic and server-side, exactly like the zero-gram drop and the
 * duplicate collapse next to it: the prompt is asked not to do this, and the
 * prompt is not a guarantee. Applied on EVERY identification path, photo
 * included — a vision model naming a row "rice 200 g" is a defect there too.
 */
export function stripTrailingQuantity(name: string): string {
  const out = name.replace(TRAILING_QUANTITY, '').trim()
  // Never strip a name down to nothing. "100 g" as an entire name is a broken
  // row, but an EMPTY row is broken in a way the caller cannot even report.
  return out.length ? out : name.trim()
}

/** Validate whatever arrived in a request body into stated items. */
export function sanitiseStatedItems(v: unknown): StatedItem[] {
  if (!Array.isArray(v)) return []
  const out: StatedItem[] = []
  for (const raw of v) {
    if (!raw || typeof raw !== 'object') continue
    const r = raw as { name?: unknown; grams?: unknown; estimated_g?: unknown; volume_measure?: unknown }
    const name = typeof r.name === 'string' ? stripTrailingQuantity(r.name) : ''
    if (!name) continue
    // `estimated_g` accepted alongside `grams` because that is the key the
    // preprocess store's own PreprocessItem uses; a caller that forwards its
    // items verbatim should not silently lose every portion.
    const grams = Math.round(toFiniteNumber(r.grams) || toFiniteNumber(r.estimated_g))
    if (grams <= 0) continue
    const volume = typeof r.volume_measure === 'string' ? r.volume_measure.trim() : ''
    out.push(volume ? { name, grams, volume_measure: volume } : { name, grams })
    if (out.length >= MAX_STATED_ITEMS) break
  }
  return out
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

const UNIT_TOKENS = new Set([
  'g', 'gr', 'gram', 'grams', 'gramme', 'grammes', 'kg', 'mg',
  'ml', 'cl', 'dl', 'l', 'oz', 'lb', 'tbsp', 'tsp', 'cup', 'cups',
])

/**
 * The tokens two names are compared on: lowercased, punctuation-free, with pure
 * numbers and bare units dropped. Dropping them is what lets a stated "chicken
 * 100 g" — from an older client, or typed that way by the member — still match
 * an identified "grilled chicken breast".
 */
function matchTokens(s: string): string[] {
  return s
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter((t) => t && !UNIT_TOKENS.has(t) && !/^\d+([.,]\d+)?$/.test(t))
}

const isSubset = (a: string[], b: string[]): boolean => {
  const set = new Set(b)
  return a.length > 0 && a.every((t) => set.has(t))
}

/**
 * Force member-stated portions back onto an identification.
 *
 * Each stated item claims AT MOST ONE identified row and each identified row is
 * claimed at most once, in two passes:
 *
 *   1. the same food, token for token ("chicken" ↔ "Chicken")
 *   2. exactly ONE unclaimed row whose tokens contain the stated ones, or are
 *      contained by them ("chicken" ↔ "grilled chicken breast")
 *
 * ⚠ AMBIGUITY IS LEFT ALONE, ON PURPOSE. Two unclaimed candidates for one
 * stated name ("chicken" against "chicken breast" AND "chicken stock") means we
 * do not know which portion the member meant, and writing 100 g onto the wrong
 * one is worse than leaving the model's estimate standing.
 *
 * ⚠ AN UNMATCHED STATED ITEM IS NOT APPENDED, also on purpose. It is tempting —
 * it would guarantee that every stated food survives — but it cannot tell a
 * DROPPED food from a DECOMPOSED one. A member who says "pesto pasta 300 g" gets
 * back basil · pine nuts · parmesan · olive oil · garlic · pasta, none of which
 * matches; appending the stated row on top would double-count the whole plate at
 * 300 g. The confirmation card is where a genuinely dropped food gets added
 * back, by the one person who knows it is missing.
 *
 * Rows nothing claims are returned AS THE SAME OBJECTS, so a caller can tell by
 * identity that they were not touched.
 */
export function applyStatedGrams<T extends { name: string; estimated_grams: number }>(
  identified: T[],
  stated: StatedItem[],
): T[] {
  if (!identified.length || !stated.length) return identified

  const out = identified.slice()
  const claimed = new Set<number>()
  const idTokens = identified.map((it) => matchTokens(it.name))
  const stTokens = stated.map((st) => matchTokens(st.name))
  const pending: number[] = []

  // Pass 1 — the same food, token for token.
  stated.forEach((st, s) => {
    const key = stTokens[s].join(' ')
    const idx = out.findIndex((_, i) => !claimed.has(i) && idTokens[i].join(' ') === key && key !== '')
    if (idx < 0) {
      pending.push(s)
      return
    }
    claimed.add(idx)
    out[idx] = { ...out[idx], estimated_grams: st.grams }
  })

  // Pass 2 — one unambiguous containment match, or nothing.
  for (const s of pending) {
    const want = stTokens[s]
    if (!want.length) continue
    const candidates: number[] = []
    for (let i = 0; i < out.length; i++) {
      if (claimed.has(i)) continue
      if (isSubset(want, idTokens[i]) || isSubset(idTokens[i], want)) candidates.push(i)
    }
    if (candidates.length !== 1) continue
    const idx = candidates[0]
    claimed.add(idx)
    out[idx] = { ...out[idx], estimated_grams: stated[s].grams }
  }

  return out
}
