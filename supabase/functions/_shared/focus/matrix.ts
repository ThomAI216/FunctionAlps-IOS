// Today's focus — the 12-cell matrix (owner-approved 2026-11-12) and the rules that pick a cell.
//
// Last night's sleep (the ROW) x how the member feels for the day (the COLUMN) = one cell. Each cell has a
// state, the card's headline and line in English and French ("vous"), the habit TYPES to offer and the ones to
// AVOID. Pure: no I/O, no clock, no randomness — the same morning always yields the same cell, which is also what
// lets the day hold still once computed. The page the owner approved is the source of every text below; the
// words marked "proposed" at the bottom (the two row-only cells, the no-sleep line, the practitioner line, the
// kickoff routine) are NEW and wait for the owner's approval.
//
// Nothing here is a language model and nothing reads a wearable value except through the one-step-down rule.

import { bandLevel } from "../../member-scores/engine/checkin/score-bands.ts"
import { type BankHabit, type Variant, variantFor } from "./engine.ts"

export type HabitType = "light" | "move" | "breath" | "hyd" | "prot" | "caf" | "rest" | "wind" | "conn" | "one" | "nap" | "prog"
export type SleepRow = "short" | "okay" | "good"
export type FeelingColumn = "charged" | "steady" | "low_willing" | "flat" | "depleted"
/** go with it · a step further · steady · pace yourself · hold steady — what the app draws the card in. */
export type Tone = "go" | "peak" | "soft" | "care" | "rest"
export type CellId = "P1" | "P2" | "P3" | "P4" | "P5" | "O1" | "OG1" | "O2" | "OG2" | "OG3" | "G1" | "G2" | "PX" | "GM"

export interface CellText { headline: string; line: string }
export interface Cell {
  id: CellId
  /** `okay_good` = one cell spanning both rows (OG1 · OG2 · OG3, and the "Good morning" row-only cell). */
  row: SleepRow | "okay_good"
  /** `unanswered` = the member skipped "Feeling for the day": the cell is picked by the row alone. */
  column: FeelingColumn | "unanswered"
  tone: Tone
  en: CellText
  fr: CellText
  /** Habit types in the order they are offered; at most MAX_CARDS become cards. */
  types: HabitType[]
  /** Types this cell never offers, whatever else adjusts it. */
  avoid: HabitType[]
  /** A cell that never mentions sleep (the member left the night blank). */
  noSleep?: { en: string; fr: string }
}

// MARK: - Cut-offs (owner, 2026-11-12)

/** Under this many minutes of sleep the night is "short or poor", even when the member feels refreshed. */
export const SHORT_NIGHT_MIN = 360
/** The check-in's own bands: < 40 low, 40–60 mid, > 60 high (`bandLevel`). Feeling: low < 40, high >= 70. */
export const FEELING_LOW = 40
export const FEELING_HIGH = 70
/** A personal HRV baseline needs this many days; below it, no ring reading may move the row. */
export const MIN_HRV_BASELINE_DAYS = 14
/** Tonight's HRV at or below this share of the personal baseline moves the sleep row ONE step down (never up). */
export const HRV_BELOW_USUAL_RATIO = 0.9
/** "We'll look at it together" needs this many depleted days among the last 7 (today included). */
export const PRACTITIONER_MIN_DEPLETED_DAYS = 3
/** One focus, then up to two more — a day, not a to-do list. */
export const MAX_CARDS = 3

export const CELLS: Record<CellId, Cell> = {
  P1: {
    id: "P1", row: "short", column: "charged", tone: "go",
    en: { headline: "Good energy on a short night", line: "Go with the flow, and leave yourself some slack: daylight now, an easy lunch, a calmer evening." },
    fr: { headline: "De l’énergie malgré une nuit courte", line: "Suivez votre élan, mais gardez un peu de marge : de la lumière dès maintenant, un déjeuner léger, une soirée plus calme." },
    types: ["light","caf","wind"],
    avoid: ["prog", "nap"],
  },
  P2: {
    id: "P2", row: "short", column: "steady", tone: "soft",
    en: { headline: "A lighter day, and that’s fine", line: "Protect the afternoon dip: daylight, a proper breakfast, a short walk after lunch." },
    fr: { headline: "Une journée plus légère, et c’est très bien", line: "Protégez le creux de l’après-midi : de la lumière, un vrai petit-déjeuner, une courte marche après le déjeuner." },
    types: ["light","prot","move"],
    avoid: ["prog"],
  },
  P3: {
    id: "P3", row: "short", column: "low_willing", tone: "care",
    en: { headline: "Your drive is there, pace the body", line: "Do the one thing that matters most, then take a real break. Light and a good breakfast help." },
    fr: { headline: "L’envie est là, ménagez le corps", line: "Faites d’abord l’essentiel, puis offrez-vous une vraie pause. La lumière et un bon petit-déjeuner aident." },
    types: ["one","rest","light"],
    avoid: ["prog"],
  },
  P4: {
    id: "P4", row: "short", column: "flat", tone: "care",
    en: { headline: "Be gentle with yourself today", line: "After a short night things feel heavier. Some air, some light, a friendly voice: that’s enough." },
    fr: { headline: "Soyez doux avec vous-même aujourd’hui", line: "Après une nuit courte, tout pèse un peu plus. De l’air, de la lumière, une voix amie : cela suffit." },
    types: ["light","breath","conn"],
    avoid: ["prog"],
  },
  P5: {
    id: "P5", row: "short", column: "depleted", tone: "rest",
    en: { headline: "Today is for holding steady", line: "Keep one priority, lighten the rest, and rest when you can. Water and a proper breakfast first." },
    fr: { headline: "Aujourd’hui, on tient le cap", line: "Gardez une seule priorité, allégez le reste et reposez-vous dès que possible. De l’eau et un vrai petit-déjeuner d’abord." },
    types: ["rest","hyd","prot","conn"],
    avoid: ["prog", "move", "caf"],
  },
  O1: {
    id: "O1", row: "okay", column: "charged", tone: "go",
    en: { headline: "Good energy to use", line: "You’re running well. Spend it on something that matters to you today." },
    fr: { headline: "De l’énergie à bien utiliser", line: "Vous êtes en forme. Mettez-la au service de ce qui compte pour vous aujourd’hui." },
    types: ["move","one"],
    avoid: ["prog"],
  },
  G1: {
    id: "G1", row: "good", column: "charged", tone: "peak",
    en: { headline: "You’re set for a great day", line: "A good night and good energy: this is the day for a step further." },
    fr: { headline: "Vous êtes prêt pour une belle journée", line: "Une bonne nuit et une bonne énergie : c’est le jour d’aller un cran plus loin." },
    types: ["move","prog"],
    avoid: [],
  },
  OG1: {
    id: "OG1", row: "okay_good", column: "steady", tone: "soft",
    en: { headline: "A steady start", line: "A little daylight and a glass of water can lift the morning even more." },
    fr: { headline: "Un bon départ tranquille", line: "Un peu de lumière et un verre d’eau peuvent encore améliorer votre matinée." },
    types: ["light","hyd","prot"],
    avoid: ["prog"],
  },
  O2: {
    id: "O2", row: "okay", column: "low_willing", tone: "soft",
    en: { headline: "A slow start, a willing mind", line: "Water, light and a proper breakfast, then let the energy build through the morning." },
    fr: { headline: "Un départ lent, mais l’envie est là", line: "De l’eau, de la lumière et un vrai petit-déjeuner, puis laissez l’énergie monter au fil de la matinée." },
    types: ["hyd","light","prot"],
    avoid: ["prog"],
  },
  G2: {
    id: "G2", row: "good", column: "low_willing", tone: "soft",
    en: { headline: "Low on energy, even after a good night", line: "It happens. Water, light and a bite, and let the day warm up. A short walk later if you feel like it." },
    fr: { headline: "Peu d’énergie, même après une bonne nuit", line: "Cela arrive. De l’eau, de la lumière et une collation, puis laissez la journée se mettre en route. Une courte marche plus tard si l’envie vient." },
    types: ["hyd","light","prot"],
    avoid: ["prog"],
  },
  OG2: {
    id: "OG2", row: "okay_good", column: "flat", tone: "care",
    en: { headline: "Be gentle with yourself today", line: "You have some energy: use a little of it on something kind: air, light or a friendly voice." },
    fr: { headline: "Soyez doux avec vous-même aujourd’hui", line: "Vous avez un peu d’énergie : utilisez-en une part pour quelque chose de doux : de l’air, de la lumière ou une voix amie." },
    types: ["breath","move","conn"],
    avoid: ["prog"],
  },
  OG3: {
    id: "OG3", row: "okay_good", column: "depleted", tone: "rest",
    en: { headline: "Go gently, and look after the basics", line: "Your night doesn’t explain it, so there is nothing to fix. Eat well, get outside, tell someone how you feel." },
    fr: { headline: "Allez-y doucement, soignez l’essentiel", line: "Votre nuit ne l’explique pas, il n’y a donc rien à corriger. Mangez bien, sortez un peu, dites à quelqu’un comment vous allez." },
    types: ["light","prot","conn","breath"],
    avoid: ["prog", "move"],
  },
  // PROPOSED (owner to approve): the member answered the night but skipped "Feeling for the day" — the row decides alone.
  PX: {
    id: "PX", row: "short", column: "unanswered", tone: "soft",
    en: { headline: "A gentler start", line: "A short night calls for a lighter start. A little daylight is a good first step." },
    fr: { headline: "Un départ plus doux", line: "Une nuit courte appelle un départ plus léger. Un peu de lumière du jour est un bon premier pas." },
    types: ["light", "prot"], avoid: ["prog", "nap"],
  },
  GM: {
    id: "GM", row: "okay_good", column: "unanswered", tone: "soft",
    en: { headline: "Good morning", line: "Start the day with a little daylight." },
    fr: { headline: "Bonjour", line: "Commencez la journée avec un peu de lumière du jour." },
    types: ["light"], avoid: ["prog"],
  },
}

// PROPOSED: OG3 reads "Your night doesn't explain it" — a member who left the night blank gets the same card without it.
CELLS.OG3.noSleep = {
  en: "There is nothing to fix. Eat well, get outside, tell someone how you feel.",
  fr: "Il n’y a rien à corriger. Mangez bien, sortez un peu, dites à quelqu’un comment vous allez.",
}

/** The cells whose morning was hard: a short or poor night, or a flat / depleted feeling. They offer the kickoff
 *  routine, and — in the evening — the "how was the rest of your day?" follow-up. */
export const HARD_MORNING_CELLS: ReadonlySet<CellId> = new Set<CellId>(["P1", "P2", "P3", "P4", "P5", "PX", "OG2", "OG3"])

/** The cells that may carry the practitioner line (only after PRACTITIONER_MIN_DEPLETED_DAYS depleted days in 7). */
export const PRACTITIONER_CELLS: ReadonlySet<CellId> = new Set<CellId>(["P5", "OG3"])

// PROPOSED wording — shown on P5 and OG3 only, after 3 or more depleted days in the last 7.
export const PRACTITIONER_LINE = {
  en: "We’ll look at it together with your practitioner.",
  fr: "Nous en parlerons ensemble avec votre praticien.",
}

// MARK: - Which cell

export interface FocusSignals {
  /** The morning check-in's own `sleep_overall`, 0–100. Null = the night was not answered. */
  sleepOverall: number | null
  /** The morning's `sleep_duration_min`. */
  sleepDurationMin: number | null
  /** Today's `patient_day_feelings`. A skipped slider is null and counts as "any". */
  mood: number | null
  energy: number | null
  motivation: number | null
  /** `patient_day_feelings.pills`, by group (`mood_why`, `energy_helped`, …). */
  pills: Record<string, unknown> | null
  /** Ring HRV is at or below HRV_BELOW_USUAL_RATIO of a personal baseline of 14+ days. False without a baseline. */
  hrvBelowUsual: boolean
  /** Depleted days among the last 7, today included (`countDepletedDays`). */
  depletedDays: number
}

const isLow = (v: number | null): boolean => v != null && v < FEELING_LOW

/** The sleep row, or null when the night is unanswered. Duration under 6 h forces "short"; the ring's HRV may move
 *  the row one step DOWN (good -> okay -> short), never up. */
export function sleepRowFor(i: Pick<FocusSignals, "sleepOverall" | "sleepDurationMin" | "hrvBelowUsual">): SleepRow | null {
  const short = i.sleepDurationMin != null && i.sleepDurationMin < SHORT_NIGHT_MIN
  const band = bandLevel(i.sleepOverall)
  let row: SleepRow | null = short ? "short" : band == null ? null : band === "low" ? "short" : band === "mid" ? "okay" : "good"
  if (row && i.hrvBelowUsual) row = row === "good" ? "okay" : "short"
  return row
}

/** The feeling column, first match wins: Depleted -> Flat -> Low energy still willing -> Charged -> Steady.
 *  Null when no slider was answered ("no feeling is ever guessed"). */
export function feelingColumnFor(f: Pick<FocusSignals, "mood" | "energy" | "motivation">): FeelingColumn | null {
  if (f.mood == null && f.energy == null && f.motivation == null) return null
  const energyLow = isLow(f.energy)
  const moodOrMotivationLow = isLow(f.mood) || isLow(f.motivation)
  if (energyLow && moodOrMotivationLow) return "depleted"
  if (!energyLow && moodOrMotivationLow) return "flat"
  if (energyLow) return "low_willing"
  if (f.energy != null && f.energy >= FEELING_HIGH) return "charged"
  return "steady"
}

const GRID: Record<SleepRow, Record<FeelingColumn, CellId>> = {
  short: { charged: "P1", steady: "P2", low_willing: "P3", flat: "P4", depleted: "P5" },
  okay: { charged: "O1", steady: "OG1", low_willing: "O2", flat: "OG2", depleted: "OG3" },
  good: { charged: "G1", steady: "OG1", low_willing: "G2", flat: "OG2", depleted: "OG3" },
}

export interface Placement {
  cell: Cell
  row: SleepRow | null
  column: FeelingColumn | null
}

/** The cell for this morning, or null when nothing was answered ("Do your check-in").
 *  Feeling unanswered -> the row alone ("A gentler start" / "Good morning"). Night unanswered -> the column alone, in the
 *  okay-night row. */
export function pickCell(s: FocusSignals): Placement | null {
  const row = sleepRowFor(s)
  const column = feelingColumnFor(s)
  if (row == null && column == null) return null
  if (column == null) return { cell: CELLS[row === "short" ? "PX" : "GM"], row, column }
  return { cell: CELLS[GRID[row ?? "okay"][column]], row, column }
}

// MARK: - The depleted day (a CONTRACT shared with the clinician dashboard — do not change)

/** A depleted day is a `patient_day_feelings` row with energy < 40 AND (mood < 40 OR motivation < 40). */
export function isDepletedDay(r: { mood: number | null; energy: number | null; motivation: number | null }): boolean {
  return isLow(r.energy) && (isLow(r.mood) || isLow(r.motivation))
}

/** Depleted days among the rows given (one row per day). The caller passes the last 7 days, today included. */
export function countDepletedDays(rows: Array<{ mood: number | null; energy: number | null; motivation: number | null }>): number {
  return rows.filter(isDepletedDay).length
}

export const showsPractitionerLine = (cell: Cell, depletedDays: number): boolean =>
  PRACTITIONER_CELLS.has(cell.id) && depletedDays >= PRACTITIONER_MIN_DEPLETED_DAYS

// MARK: - Which habit types (the pills adjust the cell, never replace it)

const STRESS_PILLS = ["worried", "stressed_today", "irritable", "overwhelmed"]
/** "What helped" already happened this morning: that habit is not offered again. */
const HELPED_RETIRES: Record<string, HabitType[]> = {
  got_daylight: ["light"], walk_before: ["move", "prog"], exercise: ["move", "prog"], breakfast: ["prot"],
  meditation_breathwork: ["breath"], time_with_someone: ["conn"],
}

/** Every pill key the member picked, whatever the group. */
export function pickedPills(pills: Record<string, unknown> | null | undefined): Set<string> {
  const out = new Set<string>()
  for (const v of Object.values(pills ?? {})) if (Array.isArray(v)) for (const k of v) if (typeof k === "string") out.add(k)
  return out
}

/** The slots a cell offers: each slot is a habit type with fallbacks (the first that has an eligible card wins).
 *  Stress pills swap one chip for Breathing; sick = rest, no movement; hungry / heavy dinner = protein breakfast first;
 *  a motivation-only low swaps one chip of OG2 for "one priority"; "what helped" pills retire that habit. */
export function slotsFor(cell: Cell, s: Pick<FocusSignals, "pills" | "mood" | "motivation">): HabitType[][] {
  const picked = pickedPills(s.pills)
  const retired = new Set<HabitType>(cell.avoid)
  for (const [pill, types] of Object.entries(HELPED_RETIRES)) if (picked.has(pill)) for (const t of types) retired.add(t)
  const sick = picked.has("sick")
  if (sick) { retired.add("move"); retired.add("prog") }

  let slots: HabitType[][] = cell.types.filter((t) => !retired.has(t)).map((t) => [t])

  if (sick && !slots.some((x) => x[0] === "rest") && !retired.has("rest")) slots.splice(1, 0, ["rest"])
  if ((picked.has("hungry") || picked.has("heavy_dinner")) && !retired.has("prot")) {
    slots = [["prot"], ...slots.filter((x) => x[0] !== "prot")]
  }
  if (STRESS_PILLS.some((k) => picked.has(k)) && !retired.has("breath")) {
    const at = slots.findIndex((x) => x[0] === "breath")
    if (at < 0) {
      const last = Math.min(MAX_CARDS, slots.length) - 1
      if (last >= 0) slots[last] = ["breath", ...slots[last]]
    } else if (at >= MAX_CARDS) {
      const last = MAX_CARDS - 1
      slots[last] = ["breath", ...slots[last]]
    }
  }
  const motivationOnlyLow = isLow(s.motivation) && !isLow(s.mood)
  if (cell.id === "OG2" && motivationOnlyLow && !retired.has("one")) {
    const at = slots.findIndex((x) => x[0] === "move")
    if (at >= 0) slots[at] = ["one", ...slots[at]]
  }
  return slots
}

// MARK: - Which cards (habit_bank)

/** The library holds no "type" column, so each type names the cards that serve it, best fit first (ids as stored in
 *  `habit_bank` on 2026-11-12). The first one that is ELIGIBLE (member_can_add, or already in the member's plan) and
 *  not already taken wins; a type with no eligible card simply offers nothing — never a card the practice has not
 *  cleared for a member. "nap" has no card in the library. */
export const TYPE_CARDS: Record<HabitType, string[]> = {
  light: ["afa499c9-5033-43d3-bf0c-81f2b8e70819", "e9c25572-8e38-4c7d-9ad8-4c9fb7af925b", "8ece2b6b-5aa0-4c5a-8626-ec053e922882"],
  move: ["623658e7-bea0-41a9-9fe5-d646a3340dda", "f74cb52f-5103-42c6-83ff-4b0347f484d5", "202b9ea7-75a6-41d8-8655-c19042ca6232", "3a3e9dbd-d0ea-46cf-8046-bfaa546740fc"],
  prog: ["eb7923e5-def2-4243-a265-1d9d8c4c4634", "3eecac9b-5b76-4933-b452-4f5ec150db08"],
  breath: ["3779f8d5-2b4c-4a1d-9182-b9e0a9785176", "7fc3d878-6d2f-40f1-957e-038d33f6d60f", "3ca4a693-d097-4a1b-92a2-95343120d2db", "2972e060-88b0-4666-86ab-3e93ec4824d9"],
  hyd: ["fd592c9e-34d9-4a8c-b548-e7b6605aab04"],
  prot: ["8ba3035e-a61f-4458-b078-9918624b8b18", "344f6f65-5661-44b9-9eb7-20465c435a43"],
  caf: ["09934b99-c538-4afb-80fb-c3606e58a7c7", "c19ca45f-34c7-49ce-8699-1eb9db94ebec"],
  rest: ["8b2ec07f-8d5e-4358-a89a-a88a4838bf61", "34716796-4631-4799-8009-4d30cdbb6671", "91d45430-f6e4-456f-8db7-031155eec97d"],
  wind: ["47613f35-cb86-4122-b168-ea3135a7a208", "d76c26e1-2e7c-42f8-8ea1-204413c96916", "e6d548a9-37a5-45a0-9412-0201b660085a"],
  conn: ["21bdbd09-0448-4d1d-b9e3-9c8652fb0fb0", "ce750ffc-7eb8-4819-8433-781ea892cf42"],
  one: ["0a09ce7a-9a86-460a-a9ec-d38e6c5a568c"],
  nap: [],
}

/** A cell's own preference for a type, ahead of the default list (P2: "a short walk after lunch"). */
const CELL_PREFERS: Partial<Record<CellId, Partial<Record<HabitType, string[]>>>> = {
  P2: { move: ["3a3e9dbd-d0ea-46cf-8046-bfaa546740fc", "7e6ee768-30fe-4781-ba62-52669aeab7c3"] },
}

export interface ChosenHabit {
  type: HabitType
  habit: BankHabit
  variant: Variant
}

/** Walk the slots in order and take the first eligible, untaken card of each; stop at MAX_CARDS. `band` is the day's
 *  readiness band (the intensity the habit's face shows); "a step further" is always the progression face, and only
 *  from a card that HAS one. */
export function chooseHabits(cell: Cell, slots: HabitType[][], eligible: BankHabit[], band: "low" | "mid" | "high" | null): ChosenHabit[] {
  const byId = new Map(eligible.map((h) => [h.id, h]))
  const taken = new Set<string>()
  const out: ChosenHabit[] = []
  for (const slot of slots) {
    if (out.length >= MAX_CARDS) break
    for (const type of slot) {
      if (cell.avoid.includes(type)) continue
      const ids = [...(CELL_PREFERS[cell.id]?.[type] ?? []), ...TYPE_CARDS[type]]
      const habit = ids.map((id) => byId.get(id)).find((h): h is BankHabit => !!h && !taken.has(h.id) && (type !== "prog" || !!h.revTitle))
      if (!habit) continue
      taken.add(habit.id)
      out.push({ type, habit, variant: type === "prog" ? "progression" : variantFor(habit, band) })
      break
    }
  }
  return out
}

// MARK: - The kickoff morning routine (PROPOSED wording; owner decision 2026-11-12: this order)

export interface KickoffStepDef { kind: string; label: { en: string; fr: string }; cards: string[] }

export const KICKOFF = {
  key: "kickoff_morning",
  title: { en: "Kickoff morning routine", fr: "Routine de démarrage du matin" },
  subtitle: {
    en: "Small steps for a slow morning, in this order. Tick each one to go on.",
    fr: "De petites étapes pour un matin lent, dans cet ordre. Cochez chacune pour continuer.",
  },
  /** The last screen, after the final tick. */
  finish: {
    en: { title: "Your morning has started", line: "That is the kickoff done. Take the rest of the day at your own pace." },
    fr: { title: "Votre matinée est lancée", line: "Le démarrage est fait. Prenez le reste de la journée à votre rythme." },
  },
  /** 1 movement · 2 breathing · 3 light · 4 connection & positivity · 5 hydration · 6 high-protein breakfast.
   *  Each step names its card first (the one free for members today), then the next best. */
  steps: [
    { kind: "movement", label: { en: "Movement", fr: "Mouvement" }, cards: ["623658e7-bea0-41a9-9fe5-d646a3340dda", "f74cb52f-5103-42c6-83ff-4b0347f484d5"] },
    { kind: "breathing", label: { en: "Breathing", fr: "Respiration" }, cards: ["3779f8d5-2b4c-4a1d-9182-b9e0a9785176", "7fc3d878-6d2f-40f1-957e-038d33f6d60f"] },
    { kind: "light", label: { en: "Daylight", fr: "Lumière du jour" }, cards: ["afa499c9-5033-43d3-bf0c-81f2b8e70819", "e9c25572-8e38-4c7d-9ad8-4c9fb7af925b"] },
    { kind: "connection", label: { en: "Connection & positivity", fr: "Lien et positivité" }, cards: ["21bdbd09-0448-4d1d-b9e3-9c8652fb0fb0", "ce750ffc-7eb8-4819-8433-781ea892cf42"] },
    { kind: "hydration", label: { en: "Hydration", fr: "Hydratation" }, cards: ["fd592c9e-34d9-4a8c-b548-e7b6605aab04"] },
    { kind: "protein", label: { en: "High-protein breakfast", fr: "Petit-déjeuner riche en protéines" }, cards: ["8ba3035e-a61f-4458-b078-9918624b8b18", "344f6f65-5661-44b9-9eb7-20465c435a43"] },
  ] satisfies KickoffStepDef[],
}

/** The routine's steps with a card each, in order; a step with no eligible card is left out (never a card the member
 *  may not see). Fewer than two steps is no routine. */
export function kickoffSteps(eligible: BankHabit[], band: "low" | "mid" | "high" | null): Array<{ kind: string; label: { en: string; fr: string }; habit: BankHabit; variant: Variant }> {
  const byId = new Map(eligible.map((h) => [h.id, h]))
  const out = []
  for (const step of KICKOFF.steps) {
    const habit = step.cards.map((id) => byId.get(id)).find((h): h is BankHabit => !!h)
    if (habit) out.push({ kind: step.kind, label: step.label, habit, variant: variantFor(habit, band) })
  }
  return out.length >= 2 ? out : []
}
