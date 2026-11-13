// habits — the corrections a member keeps making, applied to their next photo for them.
//
// Owner's decision, 2026-11-10. A member photographs a meal, the model reads the plate, and sometimes the member
// fixes the list: the "yogurt" is kefir, there is milk in the chia pudding the photo cannot show, the bowl of oats is
// 60 g, not 40. Making the SAME fix twice is a habit. From then on it is applied to their PHOTO meals automatically,
// BEFORE pricing, so the numbers they see already include it — and every item a habit added or changed carries
// `from_habit: true`, so the app can say "from your habits" and the member can take it out. Taking it out twice drops
// the habit.
//
// WHERE THE EVIDENCE COMES FROM, and why nothing is written to learn it. Two columns of the same `nb_meal_logs` row:
//
//   resolution_meta.identified   the model's own list, pre-habit (completionPatch) — what the photo SAID
//   ai_identified_foods          the member's final list — completionPatch writes it, the app rewrites it on edit
//
// The difference between the two IS the correction. A meal the member never touched has identical lists (up to the
// resolver's 10 g rounding, which the portion gate below is wider than), so it teaches nothing — that is the point.
// Rules are therefore recomputed from history at every photo, never stored: there is no "learned rule" row that can
// drift from the meals it came from, and a member deleting a meal deletes its evidence with it. Only the clinic writes
// rules down (`nb_patient_meal_habits`, migration 20261110000200), and a clinic rule needs no history at all.
//
// Older meals have no `identified` and are ignored: their `ai_identified_foods` may already be the member's edit, and
// comparing an edit with itself would teach that nobody ever corrects anything. A meal enters the learner only when
// the habits step ran on it (`resolution_meta.habits_applied` present) — which also keeps out a photo row the member
// re-described in words, whose "model list" is their own statement.
//
// ⚠ TEXT AND VOICE MEALS ARE NEVER TOUCHED. The member said what they ate; a habit second-guessing their own words
// would be the app overruling the one source that is always right. The gate is `photo` in withMealHabits below.
//
// The pure half (learnHabits / applyHabits) is tested in tests/habits.test.ts. The I/O half (loadHabits) never throws
// and never blocks a meal: a read error means "no habits this time", logged, and the meal is analysed as before.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"
import { aliasKey } from "./food-resolver.ts"
import type { FoodFlagKey } from "./meal-flags.ts"
import type { IdentifySuccess } from "./meal-analysis.ts"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** One food as the history carries it: a name and a portion. */
export type HabitFood = { name: string; grams: number }

/** One past photo meal, OLDEST FIRST in the array learnHabits takes. Order matters: an undo only counts against
 *  support that came before it. */
export type HabitHistoryEntry = {
  /** `resolution_meta.identified` — the model's list, before any habit. */
  modelList: HabitFood[]
  /** `ai_identified_foods` — what the member ended with. */
  finalList: HabitFood[]
  /** `resolution_meta.habits_applied` — the rule keys applied to this meal. */
  applied: string[]
}

export type HabitKind = "add" | "replace" | "portion"

export type HabitRule = {
  /** Stable identity, also what `habits_applied` records: `add:<X>+<Y>`, `replace:<X>><Y>`, `portion:<X>`. X and Y
   *  are aliasKey()s, which never contain `+` or `>` (aliasKey keeps letters, digits and spaces only). */
  key: string
  kind: HabitKind
  /** aliasKey of the food that triggers the rule: the food that must be present (add), the food that is swapped
   *  (replace), the food whose portion is set (portion). */
  trigger: string
  /** aliasKey of the food added or swapped in. Null for a portion rule. */
  item: string | null
  /** That food as the member named it — what the app shows. Null for a portion rule. */
  itemName: string | null
  /** add: grams of the added food. replace: grams of the new food, or null = keep the model's grams for it.
   *  portion: the portion to set. */
  grams: number | null
  /** Learned portion rules only: the way the member moved the portion. A rule learned from "40 g is really 60 g" is
   *  not evidence that 90 g is really 60 g, so it only ever moves a portion the same way. */
  direction: "up" | "down" | null
  /** `clinic` — written by a clinician; `learned` — from this member's own corrections. */
  source: "clinic" | "learned"
  /** True for a row of nb_patient_meal_habits. A table row needs no history, is not dropped by undos, and wins over a
   *  computed rule with the same key or the same swapped food. */
  fromTable: boolean
  /** Meals behind a computed rule since it was last dropped. 0 for a table row. */
  support: number
}

/** The shape identification produces (IdentifiedItem in meal-analysis.ts), restated here so this module has no
 *  runtime dependency on that one. */
export type HabitItem = { name: string; estimated_grams: number; flags: FoodFlagKey[]; from_habit?: boolean }

// ---------------------------------------------------------------------------
// Thresholds — one place, every kind
// ---------------------------------------------------------------------------

/** The same correction on this many DIFFERENT meals makes a habit. One fix is a meal; two is a pattern. */
export const HABIT_MIN_MEALS = 2
/** This many undos after the last support drop a learned rule. Same number, same reasoning, the other way. */
export const HABIT_MAX_REJECTIONS = 2
/** A portion change counts only when it is at least this many grams AND this fraction of the model's portion. The
 *  resolver rounds every portion over 10 g to the nearest 10 g (food-resolver.ts roundGrams), so an UNEDITED meal can
 *  differ from the model by up to 5 g — the 10 g floor is what keeps that rounding from reading as a correction. */
export const PORTION_MIN_DELTA_G = 10
export const PORTION_MIN_DELTA_RATIO = 0.2
/** How far back loadHabits looks, and how many meals at most. */
export const HABIT_HISTORY_DAYS = 90
export const HABIT_HISTORY_MAX_MEALS = 60

// ---------------------------------------------------------------------------
// Small pure helpers
// ---------------------------------------------------------------------------

export const addKey = (trigger: string, item: string) => `add:${trigger}+${item}`
export const replaceKey = (trigger: string, item: string) => `replace:${trigger}>${item}`
export const portionKey = (trigger: string) => `portion:${trigger}`

/** The inverse of the three builders above, for reading `habits_applied` back. Unknown shapes are null — a key some
 *  later version wrote must not crash an older learner. */
export function parseHabitKey(key: string): { kind: HabitKind; trigger: string; item: string | null } | null {
  if (typeof key !== "string") return null
  const at = (prefix: string, sep: string) => {
    const rest = key.slice(prefix.length)
    const i = rest.indexOf(sep)
    return i > 0 && i < rest.length - 1 ? { trigger: rest.slice(0, i), item: rest.slice(i + 1) } : null
  }
  if (key.startsWith("add:")) {
    const p = at("add:", "+")
    return p ? { kind: "add", ...p } : null
  }
  if (key.startsWith("replace:")) {
    const p = at("replace:", ">")
    return p ? { kind: "replace", ...p } : null
  }
  if (key.startsWith("portion:")) {
    const trigger = key.slice("portion:".length)
    return trigger ? { kind: "portion", trigger, item: null } : null
  }
  return null
}

/** Did the portion really move, and which way? Null = within the noise band (see PORTION_MIN_DELTA_*). */
export function portionShift(from: number, to: number): "up" | "down" | null {
  const d = to - from
  if (!Number.isFinite(d)) return null
  if (Math.abs(d) < PORTION_MIN_DELTA_G) return null
  if (Math.abs(d) < PORTION_MIN_DELTA_RATIO * Math.max(0, from)) return null
  return d > 0 ? "up" : "down"
}

/** Median, to 0.1 g. The member's TYPICAL portion, not their average: one 300 g Sunday does not move it. */
export function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b)
  const m = s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2
  return Math.round(m * 10) / 10
}

const positive = (v: unknown): number => {
  const x = typeof v === "string" ? Number(v) : v
  return typeof x === "number" && Number.isFinite(x) && x > 0 ? x : 0
}

/** A list keyed by aliasKey. Two rows of one food (a second helping) are summed: the correction is about the food,
 *  and comparing "olive oil 20 + 10" with "olive oil 30" must not read as a change. The first spelling is kept. */
function byKey(list: HabitFood[]): Map<string, HabitFood> {
  const m = new Map<string, HabitFood>()
  for (const f of list) {
    const k = aliasKey(f.name ?? "")
    if (!k) continue
    const prev = m.get(k)
    m.set(k, prev ? { name: prev.name, grams: prev.grams + f.grams } : { name: f.name, grams: f.grams })
  }
  return m
}

// ---------------------------------------------------------------------------
// LEARN — history -> rules
// ---------------------------------------------------------------------------
//
// Per meal, model list vs final list, by aliasKey:
//
//   1. The habits APPLIED to that meal are settled first. Kept -> one more meal of support (and the item it added or
//      swapped is consumed, so it is not read again as a fresh correction below). Reversed -> one rejection: the added
//      food removed, the swapped food put back (or the new one removed), the portion left at or moved back toward the
//      model's. Settling them first matters: without it, a kept habit-added milk plus one genuine swap would read as
//      "one removed, two added" and the swap would be lost.
//   2. What is left: exactly one food removed and one added -> a REPLACE X->Y. Anything else -> every added Y is an ADD,
//      counted once against every X the member KEPT from the model's list (the brief: "every X in that meal gets the
//      co-occurrence"). A removed X is not a trigger: the member said it was not there.
//   3. Every food in both lists whose portion moved past the noise band -> a PORTION event, up or down.
//
// Then, per rule key, oldest meal first: a support adds to the streak and clears the undos; HABIT_MAX_REJECTIONS undos
// after the last support DROP it; a support after a drop starts a NEW streak, so a dropped habit has to be shown twice
// again before it comes back — one stray edit must not resurrect what the member removed twice. A portion streak also
// restarts when the direction flips, which is what "no rule from inconsistent directions" means here: 40->60 then
// 40->25 is two meals of noise, not a habit.

type Support = { grams: number; name: string; fromGrams: number }
type Track = { kind: "add" | "replace"; trigger: string; item: string; streak: Support[]; rejects: number; dropped: boolean }
type PortionTrack = { trigger: string; dir: "up" | "down" | null; streak: number[]; rejects: number; dropped: boolean }

export function learnHabits(history: HabitHistoryEntry[]): HabitRule[] {
  const tracks = new Map<string, Track>()
  const portions = new Map<string, PortionTrack>()

  const track = (kind: "add" | "replace", trigger: string, item: string): Track => {
    const key = kind === "add" ? addKey(trigger, item) : replaceKey(trigger, item)
    let t = tracks.get(key)
    if (!t) tracks.set(key, (t = { kind, trigger, item, streak: [], rejects: 0, dropped: false }))
    return t
  }
  const support = (t: Track, s: Support) => {
    if (t.dropped) {
      t.streak = []
      t.dropped = false
    }
    t.streak.push(s)
    t.rejects = 0
  }
  const reject = (t: { rejects: number; dropped: boolean }) => {
    t.rejects++
    if (t.rejects >= HABIT_MAX_REJECTIONS) t.dropped = true
  }
  const portionTrack = (trigger: string): PortionTrack => {
    let t = portions.get(trigger)
    if (!t) portions.set(trigger, (t = { trigger, dir: null, streak: [], rejects: 0, dropped: false }))
    return t
  }

  for (const entry of history) {
    const model = byKey(entry.modelList ?? [])
    const final = byKey(entry.finalList ?? [])
    if (!model.size) continue
    const removed = new Set([...model.keys()].filter((k) => !final.has(k)))
    const added = new Set([...final.keys()].filter((k) => !model.has(k)))
    const portionApplied = new Set<string>()

    // 1. Settle the habits that were applied to this meal.
    for (const raw of entry.applied ?? []) {
      const p = parseHabitKey(raw)
      if (!p) continue
      if (p.kind === "portion") {
        portionApplied.add(p.trigger)
        continue
      }
      const item = p.item as string
      const t = track(p.kind, p.trigger, item)
      if (p.kind === "add") {
        if (added.has(item)) {
          const y = final.get(item) as HabitFood
          support(t, { grams: y.grams, name: y.name, fromGrams: 0 })
          added.delete(item)
        } else if (!final.has(item)) {
          reject(t)
        }
      } else {
        // Kept = the new food is there AND the old one is not. The old one back, or the new one gone, is an undo.
        if (added.has(item) && removed.has(p.trigger)) {
          const y = final.get(item) as HabitFood
          support(t, { grams: y.grams, name: y.name, fromGrams: (model.get(p.trigger) as HabitFood).grams })
          added.delete(item)
          removed.delete(p.trigger)
        } else {
          reject(t)
        }
      }
    }

    // 2. What the member changed beyond the applied habits.
    const kept = [...model.keys()].filter((k) => final.has(k))
    if (removed.size === 1 && added.size === 1) {
      const x = [...removed][0], yk = [...added][0]
      const y = final.get(yk) as HabitFood
      support(track("replace", x, yk), { grams: y.grams, name: y.name, fromGrams: (model.get(x) as HabitFood).grams })
    } else {
      for (const yk of added) {
        const y = final.get(yk) as HabitFood
        for (const x of kept) support(track("add", x, yk), { grams: y.grams, name: y.name, fromGrams: 0 })
      }
    }

    // 3. Portions, on the foods the member kept.
    for (const k of kept) {
      const shift = portionShift((model.get(k) as HabitFood).grams, (final.get(k) as HabitFood).grams)
      const t = portions.get(k)
      if (shift) {
        const pt = t ?? portionTrack(k)
        if (pt.dropped || pt.dir !== shift) {
          pt.streak = []
          pt.dir = shift
          pt.dropped = false
        }
        pt.streak.push((final.get(k) as HabitFood).grams)
        pt.rejects = 0
      } else if (portionApplied.has(k)) {
        // The habit set the portion and the member put it back where the model had it.
        reject(t ?? portionTrack(k))
      }
    }
  }

  // Active rules.
  const rules: HabitRule[] = []
  for (const [key, t] of tracks) {
    if (t.dropped || t.streak.length < HABIT_MIN_MEALS) continue
    const ys = t.streak.map((s) => s.grams)
    const latest = t.streak[t.streak.length - 1]
    let grams: number | null
    if (t.kind === "add") {
      grams = median(ys)
    } else {
      // REPLACE keeps the model's grams for the new food — the photo still shows how much was on the plate — UNLESS
      // the member consistently gave it a portion of its own: every time they moved it past the noise band, AND the
      // portions they gave agree with each other (within 20% of their median). "Yogurt 150 -> kefir 150" twice is
      // a name fix, not a portion; "yogurt 150 -> kefir 250, 180 -> 250" is both.
      const m = median(ys)
      const ownPortion = t.streak.every((s) => portionShift(s.fromGrams, s.grams) !== null) &&
        ys.every((g) => Math.abs(g - m) <= PORTION_MIN_DELTA_RATIO * m)
      grams = ownPortion ? m : null
    }
    rules.push({
      key,
      kind: t.kind,
      trigger: t.trigger,
      item: t.item,
      itemName: latest.name,
      grams,
      direction: null,
      source: "learned",
      fromTable: false,
      support: t.streak.length,
    })
  }
  for (const t of portions.values()) {
    if (t.dropped || t.streak.length < HABIT_MIN_MEALS) continue
    rules.push({
      key: portionKey(t.trigger),
      kind: "portion",
      trigger: t.trigger,
      item: null,
      itemName: null,
      grams: median(t.streak),
      direction: t.dir,
      source: "learned",
      fromTable: false,
      support: t.streak.length,
    })
  }

  // One rule per added food (the brief: several X qualifying for the same Y -> the most frequent X, ties alphabetical),
  // and one per swapped food. Without the first, a member who adds milk to chia pudding twice — with kiwi on top both
  // times — would also get milk added to every bowl of kiwi.
  const best = (group: (r: HabitRule) => string, tie: (r: HabitRule) => string) => {
    const winners = new Map<string, HabitRule>()
    for (const r of rules) {
      const g = group(r)
      const w = winners.get(g)
      if (!w || r.support > w.support || (r.support === w.support && tie(r) < tie(w))) winners.set(g, r)
    }
    return new Set(winners.values())
  }
  const addWinners = best((r) => (r.kind === "add" ? `add|${r.item}` : r.key), (r) => r.trigger)
  const replaceWinners = best((r) => (r.kind === "replace" ? `replace|${r.trigger}` : r.key), (r) => r.item ?? "")
  return rules
    .filter((r) => (r.kind !== "add" || addWinners.has(r)) && (r.kind !== "replace" || replaceWinners.has(r)))
    .sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
}

// ---------------------------------------------------------------------------
// APPLY — rules -> this meal's items
// ---------------------------------------------------------------------------
//
// Order: replace, then portion, then add — a swapped food is the food on the plate, and an add is triggered by what
// is on the plate. One rule per item. A replace whose new food is already listed is skipped (it would list it twice);
// a portion rule applies only to a food listed once (setting two rows of a second helping to the same portion would
// double it) and only when the change clears the same noise band the learner uses, in the learned direction — so
// "applied" always means "visibly changed", and the learner can read leaving it alone as keeping it. An add needs
// its trigger present and the food absent, and grams.
//
// A habit item gets `flags: []`, never the replaced food's flags: yogurt's flags are a judgement about yogurt. The
// app already falls back to its keyword heuristics for a flag-less item.

const ORDER: Record<HabitKind, number> = { replace: 0, portion: 1, add: 2 }

export function applyHabits<T extends HabitItem>(items: T[], rules: HabitRule[]): { items: HabitItem[]; applied: string[] } {
  const out: HabitItem[] = items.map((it) => ({ ...it }))
  const keys = out.map((it) => aliasKey(it.name))
  const touched = new Set<number>()
  const applied: string[] = []
  const ordered = [...rules].sort((a, b) =>
    ORDER[a.kind] - ORDER[b.kind] ||
    Number(b.fromTable) - Number(a.fromTable) ||
    b.support - a.support ||
    (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)
  )

  for (const r of ordered) {
    if (r.kind === "replace") {
      if (!r.item || !r.itemName || keys.includes(r.item)) continue
      let hit = false
      out.forEach((it, i) => {
        if (touched.has(i) || keys[i] !== r.trigger) return
        const grams = positive(r.grams) || it.estimated_grams
        out[i] = { name: r.itemName as string, estimated_grams: grams, flags: [], from_habit: true }
        keys[i] = r.item as string
        touched.add(i)
        hit = true
      })
      if (hit) applied.push(r.key)
    } else if (r.kind === "portion") {
      const target = positive(r.grams)
      if (!target) continue
      const idx = keys.flatMap((k, i) => (k === r.trigger && !touched.has(i) ? [i] : []))
      if (idx.length !== 1 || keys.filter((k) => k === r.trigger).length !== 1) continue
      const i = idx[0]
      // A clinic row is an explicit decision ("her honey is 7 g"), so it applies whenever the model's grams differ —
      // the 20 % / 10 g bar exists to keep rounding noise out of LEARNED rules, and would silence every small food
      // (honey, nut butter, seeds) a clinician writes down.
      const shift = r.fromTable
        ? (out[i].estimated_grams === target ? null : target > out[i].estimated_grams ? "up" : "down")
        : portionShift(out[i].estimated_grams, target)
      if (!shift || (r.direction && shift !== r.direction)) continue
      out[i] = { ...out[i], estimated_grams: target, from_habit: true }
      touched.add(i)
      applied.push(r.key)
    } else {
      const grams = positive(r.grams)
      if (!grams || !r.item || !r.itemName || !keys.includes(r.trigger) || keys.includes(r.item)) continue
      out.push({ name: r.itemName, estimated_grams: grams, flags: [], from_habit: true })
      keys.push(r.item)
      touched.add(out.length - 1)
      applied.push(r.key)
    }
  }
  return { items: out, applied }
}

// ---------------------------------------------------------------------------
// The call-site step — both entry points, one definition
// ---------------------------------------------------------------------------

/** Applies `rules` to a successful identification. `model_items` keeps the model's own list so completionPatch can
 *  still record it as `resolution_meta.identified` (the learner's evidence must stay pre-habit, or the next meal
 *  would learn from the habit instead of from the member), and `habits_applied` is recorded beside it — `[]` when
 *  nothing applied, which is also what marks this meal as one the learner may read. */
export function applyHabitsToIdentification(ident: IdentifySuccess, rules: HabitRule[]): IdentifySuccess {
  const { items, applied } = applyHabits(ident.items, rules)
  return { ...ident, items, model_items: ident.model_items ?? ident.items, habits_applied: applied }
}

export type MealHabitsContext = {
  /** From the MEAL ROW, never from a request — same invariant as priceMeal's patientId. */
  patientId: string | null
  /** True only when the input was photos alone: no description, no stated items. */
  photo: boolean
  /** The meal being analysed: on a re-analysis its old row is complete and must not count as its own history. */
  mealLogId?: string | null
}

/** True when identification read ONLY pictures — the one input habits may touch. Words of any kind mean the member
 *  said what they ate. */
export function isPhotoOnlyInput(input: {
  imageBase64?: string
  imageBase64s?: string[]
  imageUrl?: string
  description?: string
  statedItems?: unknown[]
}): boolean {
  const images = Boolean(input.imageBase64 || input.imageBase64s?.length || input.imageUrl)
  return images && !(input.description ?? "").trim() && !(input.statedItems?.length)
}

/** The habits step both analyze-meal and retry-meal-analysis run between identification and WRITE 1. A text or voice
 *  meal, an unknown patient or an empty plate comes back untouched without a single query. */
export async function withMealHabits(
  db: SupabaseClient | null,
  ident: IdentifySuccess,
  ctx: MealHabitsContext,
): Promise<IdentifySuccess> {
  if (!ctx.photo || !ctx.patientId || !db || !ident.items.length) return ident
  const rules = await loadHabits(db, ctx.patientId, { excludeMealId: ctx.mealLogId ?? null })
  const out = applyHabitsToIdentification(ident, rules)
  if (out.habits_applied?.length) console.log(`[habits] applied ${out.habits_applied.length} of ${rules.length} rule(s)`)
  return out
}

// ---------------------------------------------------------------------------
// LOAD — the member's history and the clinic's rows -> rules
// ---------------------------------------------------------------------------

// The table is created by a migration that ships separately from this code. Until it is applied PostgREST answers
// "relation does not exist" (42P01) or "not in the schema cache" (PGRST205): that is "no clinic rows", not a failure.
const MISSING_TABLE = new Set(["42P01", "PGRST205"])

type MealRow = { ai_identified_foods: unknown; identified: unknown; habits_applied: unknown }
type HabitRow = { kind: unknown; trigger_norm: unknown; item_name: unknown; item_grams: unknown; source: unknown }

function foods(raw: unknown): HabitFood[] {
  if (!Array.isArray(raw)) return []
  return raw.flatMap((x) => {
    const it = x as { name?: unknown; grams?: unknown; estimated_grams?: unknown }
    if (!it || typeof it.name !== "string" || !it.name.trim()) return []
    // The model list says `grams`; the app writes `estimated_grams` on edit. Either is the portion.
    const grams = positive(it.grams) || positive(it.estimated_grams)
    return [{ name: it.name.trim(), grams }]
  })
}

/** A clinic row as a rule, or null when the row cannot be one. `trigger_norm` must be the aliasKey of the food (the
 *  same key `nb_patient_food_aliases.alias_norm` holds) — it is NOT re-normalised here, because aliasKey is not
 *  idempotent ("cheeses" -> "chees" -> "chee") and a stored key must match the way it was written. */
export function ruleFromRow(row: HabitRow): HabitRule | null {
  const kind = row.kind
  const trigger = typeof row.trigger_norm === "string" ? row.trigger_norm.trim().toLowerCase() : ""
  if (!trigger || !/^[\p{L}\p{N} ]+$/u.test(trigger)) return null
  const itemName = typeof row.item_name === "string" && row.item_name.trim() ? row.item_name.trim() : null
  const item = itemName ? aliasKey(itemName) : null
  const grams = positive(row.item_grams) || null
  const source = row.source === "learned" ? "learned" : "clinic"
  const base = { trigger, direction: null, source, fromTable: true, support: 0 } as const
  if (kind === "add") {
    if (!item || !itemName || !grams) return null
    return { ...base, key: addKey(trigger, item), kind, item, itemName, grams }
  }
  if (kind === "replace") {
    if (!item || !itemName || item === trigger) return null
    return { ...base, key: replaceKey(trigger, item), kind, item, itemName, grams }
  }
  if (kind === "portion") {
    if (!grams) return null
    return { ...base, key: portionKey(trigger), kind, item: null, itemName: null, grams }
  }
  return null
}

/** Table rows win: same key, or a learned swap of a food the clinic swaps, or a learned portion of a food the clinic
 *  portions. A learned add of a food the clinic also adds (under another trigger) is kept — the add skips a food
 *  already on the plate, so the two cannot both land. */
export function mergeRules(table: HabitRule[], learned: HabitRule[]): HabitRule[] {
  const keys = new Set(table.map((r) => r.key))
  const swapped = new Set(table.filter((r) => r.kind === "replace").map((r) => r.trigger))
  const portioned = new Set(table.filter((r) => r.kind === "portion").map((r) => r.trigger))
  return [
    ...table,
    ...learned.filter((r) =>
      !keys.has(r.key) &&
      !(r.kind === "replace" && swapped.has(r.trigger)) &&
      !(r.kind === "portion" && portioned.has(r.trigger))
    ),
  ]
}

/**
 * The rules for one member: their last HABIT_HISTORY_DAYS days of complete photo meals (at most
 * HABIT_HISTORY_MAX_MEALS) learned on the fly, merged with their active `nb_patient_meal_habits` rows.
 *
 * NEVER THROWS, NEVER BLOCKS A MEAL. Any read error is logged and returns [] — a member's meal analysed without their
 * habits is the meal they had yesterday; a meal lost to a habits query is a regression. PostgREST errors are values,
 * so each one is checked, not caught.
 *
 * `db` reads `nb_meal_logs` and `nb_patient_meal_habits` for `patientId`: analyze-meal passes the CALLER'S client (RLS
 * own-rows proves the member), the worker its service-role client with the id off the row it selected itself.
 */
export async function loadHabits(
  db: SupabaseClient,
  patientId: string,
  opts: { excludeMealId?: string | null; now?: Date } = {},
): Promise<HabitRule[]> {
  try {
    const since = new Date((opts.now ?? new Date()).getTime() - HABIT_HISTORY_DAYS * 86_400_000).toISOString()
    let meals = db
      .from("nb_meal_logs")
      // Only the two keys the learner reads, not the whole provenance blob.
      .select("ai_identified_foods, identified:resolution_meta->identified, habits_applied:resolution_meta->habits_applied")
      .eq("patient_id", patientId)
      .eq("analysis_status", "complete")
      .eq("source", "photo")
      .gte("logged_at", since)
      .not("resolution_meta->identified", "is", null)
      .not("resolution_meta->habits_applied", "is", null)
    if (opts.excludeMealId) meals = meals.neq("id", opts.excludeMealId)
    const [m, h] = await Promise.all([
      meals.order("logged_at", { ascending: false }).limit(HABIT_HISTORY_MAX_MEALS),
      db
        .from("nb_patient_meal_habits")
        .select("kind, trigger_norm, item_name, item_grams, source")
        .eq("patient_id", patientId)
        .eq("active", true),
    ])
    if (m.error) {
      console.warn(`[habits] could not read meal history (${m.error.code ?? "?"}): ${m.error.message} — no habits this meal`)
      return []
    }
    let tableRows: HabitRow[] = []
    if (h.error) {
      if (!MISSING_TABLE.has(h.error.code ?? "")) {
        console.warn(`[habits] could not read nb_patient_meal_habits (${h.error.code ?? "?"}): ${h.error.message} — no habits this meal`)
        return []
      }
    } else {
      tableRows = (h.data ?? []) as HabitRow[]
    }
    // Newest first off the wire (so the limit keeps the RECENT meals), oldest first into the learner.
    const history: HabitHistoryEntry[] = ((m.data ?? []) as MealRow[]).reverse().map((r) => ({
      modelList: foods(r.identified),
      finalList: foods(r.ai_identified_foods),
      applied: Array.isArray(r.habits_applied) ? r.habits_applied.filter((k): k is string => typeof k === "string") : [],
    }))
    const table = tableRows.map(ruleFromRow).filter((r): r is HabitRule => r !== null)
    return mergeRules(table, learnHabits(history))
  } catch (e) {
    console.warn(`[habits] load failed: ${String(e).slice(0, 200)} — no habits this meal`)
    return []
  }
}
