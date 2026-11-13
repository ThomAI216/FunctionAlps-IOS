import { assert, assertEquals } from "jsr:@std/assert@1"
import { type BankHabit, focusEligibleBank } from "../engine.ts"
import {
  CELLS, type CellId, chooseHabits, countDepletedDays, feelingColumnFor, type FocusSignals, HARD_MORNING_CELLS, isDepletedDay, KICKOFF,
  kickoffSteps, pickCell, slotsFor, sleepRowFor, TYPE_CARDS,
} from "../matrix.ts"
import { presentFocus } from "../present.ts"

const sig = (over: Partial<FocusSignals> = {}): FocusSignals => ({
  sleepOverall: 55, sleepDurationMin: 450, mood: 60, energy: 55, motivation: 60, pills: null, hrvBelowUsual: false, depletedDays: 0, ...over,
})
const cellOf = (over: Partial<FocusSignals>): CellId | null => pickCell(sig(over))?.cell.id ?? null

// The three sleep rows x the five feelings, as the owner's page draws them (OG1 / OG2 / OG3 span okay and good).
const NIGHT = { short: { sleepOverall: 30 }, okay: { sleepOverall: 50 }, good: { sleepOverall: 80 } }
const FEEL = {
  charged: { mood: 75, energy: 80, motivation: 70 },
  steady: { mood: 60, energy: 55, motivation: 60 },
  low_willing: { mood: 60, energy: 30, motivation: 60 },
  flat: { mood: 30, energy: 60, motivation: 60 },
  depleted: { mood: 30, energy: 30, motivation: 60 },
}

Deno.test("the twelve cells sit where the page puts them", () => {
  const expected: Record<string, Record<string, CellId>> = {
    short: { charged: "P1", steady: "P2", low_willing: "P3", flat: "P4", depleted: "P5" },
    okay: { charged: "O1", steady: "OG1", low_willing: "O2", flat: "OG2", depleted: "OG3" },
    good: { charged: "G1", steady: "OG1", low_willing: "G2", flat: "OG2", depleted: "OG3" },
  }
  for (const [n, night] of Object.entries(NIGHT)) for (const [f, feel] of Object.entries(FEEL)) {
    assertEquals(cellOf({ ...night, ...feel }), expected[n][f], `${n} x ${f}`)
  }
})

Deno.test("sleep bands: < 40 short/poor, 40–60 okay, > 60 good; under 360 min forces short even when refreshed", () => {
  const row = (sleepOverall: number | null, sleepDurationMin: number | null = 450) => sleepRowFor({ sleepOverall, sleepDurationMin, hrvBelowUsual: false })
  assertEquals(row(39), "short"); assertEquals(row(40), "okay"); assertEquals(row(60), "okay"); assertEquals(row(61), "good")
  assertEquals(row(95, 359), "short")   // slept little but feels charged
  assertEquals(row(95, 360), "good")
  assertEquals(row(null, 300), "short") // duration alone, night score unanswered
  assertEquals(row(null, null), null)
})

Deno.test("ring HRV moves a row one step DOWN only — never up, never past short", () => {
  const row = (sleepOverall: number | null, hrvBelowUsual: boolean) => sleepRowFor({ sleepOverall, sleepDurationMin: 450, hrvBelowUsual })
  assertEquals(row(80, true), "okay"); assertEquals(row(50, true), "short"); assertEquals(row(20, true), "short")
  assertEquals(row(80, false), "good")
  assertEquals(row(null, true), null) // night unanswered: the row stays unanswered (the band alone softens the habits)
})

Deno.test("columns: first match wins — Depleted, Flat, Low energy still willing, Charged, Steady", () => {
  const col = (mood: number | null, energy: number | null, motivation: number | null) => feelingColumnFor({ mood, energy, motivation })
  assertEquals(col(30, 30, 60), "depleted"); assertEquals(col(60, 30, 30), "depleted")
  assertEquals(col(30, 60, 60), "flat"); assertEquals(col(60, 90, 30), "flat") // one low slider is enough for Flat
  assertEquals(col(60, 30, 60), "low_willing")
  assertEquals(col(60, 70, 60), "charged"); assertEquals(col(60, 69, 60), "steady")
  assertEquals(col(null, 30, null), "low_willing"); assertEquals(col(null, null, 55), "steady") // a skipped slider is "any"
  assertEquals(col(null, null, null), null)
})

Deno.test("edge cases: feeling unanswered -> the row alone; night unanswered -> the okay row, never mentioning sleep; nothing -> null", () => {
  const none = { mood: null, energy: null, motivation: null }
  assertEquals(cellOf({ ...none, sleepOverall: 30 }), "PX")
  assertEquals(cellOf({ ...none, sleepOverall: 50 }), "GM")
  assertEquals(cellOf({ ...none, sleepOverall: 90 }), "GM")
  assertEquals(cellOf({ sleepOverall: null, sleepDurationMin: null, ...FEEL.charged }), "O1")
  assertEquals(cellOf({ sleepOverall: null, sleepDurationMin: null, ...FEEL.depleted }), "OG3")
  assertEquals(cellOf({ ...none, sleepOverall: null, sleepDurationMin: null }), null)
  // OG3's own line says "Your night doesn't explain it": without a night it is dropped.
  const eligible: BankHabit[] = []
  const withNight = presentFocus({ cellId: "OG3", locale: "en", depletedDays: 0, sleepKnown: true, eligible, band: null })!
  const noNight = presentFocus({ cellId: "OG3", locale: "en", depletedDays: 0, sleepKnown: false, eligible, band: null })!
  assert(withNight.line.includes("night"))
  assert(!noNight.line.toLowerCase().includes("night") && !noNight.line.toLowerCase().includes("sleep"))
  for (const id of ["O1", "OG1", "O2", "OG2"] as CellId[]) assert(!/sleep|night/i.test(CELLS[id].en.line + CELLS[id].fr.line.replace(/nuit/i, "night")), id)
})

Deno.test("every cell has an English and a French headline and line, and offers at least one type", () => {
  for (const c of Object.values(CELLS)) {
    for (const l of [c.en, c.fr]) { assert(l.headline.trim() !== "" && l.line.trim() !== "", c.id) }
    assert(c.types.length >= 1, c.id)
    for (const t of c.types) assert(!c.avoid.includes(t), `${c.id} offers a type it avoids: ${t}`)
  }
  assertEquals(Object.keys(CELLS).sort(), ["G1", "G2", "GM", "O1", "O2", "OG1", "OG2", "OG3", "P1", "P2", "P3", "P4", "P5", "PX"])
})

// MARK: - The depleted day — the contract shared with the clinician dashboard

Deno.test("a depleted day is energy < 40 AND (mood < 40 OR motivation < 40) — nothing else", () => {
  const d = (mood: number | null, energy: number | null, motivation: number | null) => isDepletedDay({ mood, energy, motivation })
  assert(d(39, 39, 80)); assert(d(80, 39, 39)); assert(d(10, 10, 10))
  assert(!d(39, 40, 39))          // energy at 40 is not low
  assert(!d(40, 39, 40))          // mood and motivation both at 40
  assert(!d(null, 10, null)); assert(!d(10, null, 10))   // unanswered counts as not low
  assertEquals(countDepletedDays([{ mood: 10, energy: 10, motivation: 50 }, { mood: 70, energy: 70, motivation: 70 }, { mood: 50, energy: 20, motivation: 20 }]), 2)
})

Deno.test("the practitioner line: P5 and OG3 only, and only from 3 depleted days in 7", () => {
  const eligible: BankHabit[] = []
  const line = (cellId: CellId, depletedDays: number) => presentFocus({ cellId, locale: "en", depletedDays, sleepKnown: true, eligible, band: null })!.practitionerLine
  assertEquals(line("P5", 2), null); assert(line("P5", 3)!.includes("practitioner")); assert(line("OG3", 7) != null)
  for (const id of ["P1", "P2", "P3", "P4", "O1", "OG1", "O2", "OG2", "G1", "G2", "PX", "GM"] as CellId[]) assertEquals(line(id, 7), null, id)
  assert(presentFocus({ cellId: "P5", locale: "fr", depletedDays: 3, sleepKnown: true, eligible, band: null })!.practitionerLine!.includes("praticien"))
})

// MARK: - Habits: types, pills, eligibility

const card = (id: string, over: Partial<BankHabit> = {}): BankHabit => ({
  id, pillar: "exercise", category: null, title: `Card ${id.slice(0, 4)}`, description: "d", defaultSlot: "morning", easyTitle: null, easyDescription: null,
  revTitle: null, revDescription: null, sortOrder: 1, memberCanAdd: true, ...over,
})
const idOf = (type: keyof typeof TYPE_CARDS, n = 0) => TYPE_CARDS[type][n]
/** A library where every card the matrix names exists and is open to members. */
const FULL: BankHabit[] = [...new Set(Object.values(TYPE_CARDS).flat().concat(KICKOFF.steps.flatMap((s) => s.cards)))].map((id) => card(id, TYPE_CARDS.prog.includes(id) ? { revTitle: "A step further" } : {}))
const typesOf = (cellId: CellId, over: Partial<FocusSignals> = {}, bank: BankHabit[] = FULL) => {
  const s = sig(over)
  return chooseHabits(CELLS[cellId], slotsFor(CELLS[cellId], s), bank, null).map((c) => c.type)
}

Deno.test("a cell offers 1–3 cards, picked for its types, in its order", () => {
  assertEquals(typesOf("P2"), ["light", "prot", "move"])
  assertEquals(typesOf("P5"), ["rest", "hyd", "prot"])             // four types, three cards
  assertEquals(typesOf("G1"), ["move", "prog"])
  assertEquals(typesOf("GM"), ["light"])
  for (const id of Object.keys(CELLS) as CellId[]) { const n = typesOf(id).length; assert(n >= 1 && n <= 3, `${id} -> ${n}`) }
})

Deno.test("a prescription-only card never shows — a type with no eligible card offers nothing", () => {
  const closed = FULL.map((h) => h.id === idOf("hyd") ? { ...h, memberCanAdd: false } : h)
  const open = focusEligibleBank(closed, new Set())
  assertEquals(typesOf("P5", {}, open), ["rest", "prot", "conn"])  // hydration drops out, the next type moves up
  const ids = chooseHabits(CELLS.OG1, slotsFor(CELLS.OG1, sig()), open, null).map((c) => c.habit.id)
  assert(!ids.includes(idOf("hyd")))
  // …unless the member's own plan already holds it.
  assert(focusEligibleBank(closed, new Set([idOf("hyd")])).some((h) => h.id === idOf("hyd")))
  assertEquals(typesOf("P5", {}, []), [])
})

Deno.test("never a type the cell avoids: no step further outside G1, no training on a depleted day", () => {
  for (const id of Object.keys(CELLS) as CellId[]) {
    const types = typesOf(id)
    for (const a of CELLS[id].avoid) assert(!types.includes(a), `${id} offered ${a}`)
    if (id !== "G1") assert(!types.includes("prog"), id)
  }
  const high = chooseHabits(CELLS.G1, slotsFor(CELLS.G1, sig()), FULL, "high")
  assertEquals(high.find((c) => c.type === "prog")?.variant, "progression")
  // "a step further" needs a card that HAS a further version.
  assertEquals(typesOf("G1"), ["move", "prog"])
  assertEquals(chooseHabits(CELLS.G1, slotsFor(CELLS.G1, sig()), FULL.map((h) => h.id === idOf("prog", 0) ? { ...h, revTitle: null } : h), null).find((c) => c.type === "prog")?.habit.id, idOf("prog", 1))
})

Deno.test("pills adjust the cell: stress -> Breathing, sick -> rest and no movement, hungry -> protein first", () => {
  const stress = slotsFor(CELLS.P2, sig({ pills: { mood_why: ["stressed_today"] } }))
  assert(stress.some((s) => s[0] === "breath") && stress.length === 3)
  assertEquals(stress[0][0], "light")                              // one chip swapped, the others stay
  const sick = typesOf("P2", { pills: { energy_why: ["sick"] } })
  assert(sick.includes("rest") && !sick.includes("move"), sick.join())
  assertEquals(typesOf("OG2", { pills: { energy_why: ["sick"] } }).includes("move"), false)
  assertEquals(typesOf("P5", { pills: { energy_why: ["hungry"] } })[0], "prot")
  assertEquals(typesOf("OG1", { pills: { energy_why: ["heavy_dinner"] } })[0], "prot")
  // a motivation-only low swaps one chip of OG2 for "one priority" (when the library has a card for it)
  assertEquals(typesOf("OG2", { mood: 60, motivation: 20, energy: 60 }).includes("one"), true)
  assertEquals(typesOf("OG2", { mood: 20, motivation: 60, energy: 60 }).includes("one"), false)
  // …and falls back to the original chip when there is none
  assertEquals(typesOf("OG2", { mood: 60, motivation: 20, energy: 60 }, FULL.filter((h) => h.id !== idOf("one"))), ["breath", "move", "conn"])
})

Deno.test("what helped is not offered again", () => {
  assertEquals(typesOf("OG1", { pills: { energy_helped: ["got_daylight"] } }), ["hyd", "prot"])
  assertEquals(typesOf("P2", { pills: { mood_helped: ["walk_before"], energy_helped: ["breakfast"] } }), ["light"])
  assertEquals(typesOf("OG3", { pills: { mood_helped: ["time_with_someone"] } }).includes("conn"), false)
})

Deno.test("the day's band picks the habit's face: easy on a low day", () => {
  const easy = FULL.map((h) => h.id === idOf("hyd") ? { ...h, easyTitle: "A sip" } : h)
  const low = chooseHabits(CELLS.OG1, slotsFor(CELLS.OG1, sig()), easy, "low").find((c) => c.type === "hyd")
  assertEquals(low?.variant, "easy")
  assertEquals(chooseHabits(CELLS.OG1, slotsFor(CELLS.OG1, sig()), easy, "mid").find((c) => c.type === "hyd")?.variant, "standard")
})

// MARK: - The kickoff morning routine

Deno.test("kickoff: movement, breathing, light, connection, hydration, protein breakfast — in that order, a real card each", () => {
  assertEquals(KICKOFF.steps.map((s) => s.kind), ["movement", "breathing", "light", "connection", "hydration", "protein"])
  const steps = kickoffSteps(FULL, null)
  assertEquals(steps.map((s) => s.kind), ["movement", "breathing", "light", "connection", "hydration", "protein"])
  assertEquals(new Set(steps.map((s) => s.habit.id)).size, 6)
  // a closed card is skipped; the step falls back to its next card, or drops out — order is kept
  const closed = FULL.map((h) => h.id === idOf("hyd") ? { ...h, memberCanAdd: false } : h)
  assertEquals(kickoffSteps(focusEligibleBank(closed, new Set()), null).map((s) => s.kind), ["movement", "breathing", "light", "connection", "protein"])
  assertEquals(kickoffSteps(focusEligibleBank(FULL.slice(0, 1), new Set()), null), []) // fewer than two steps is no routine
})

Deno.test("kickoff is offered on the short-night and depleted/flat cells only, in the member's language", () => {
  const out = (cellId: CellId) => presentFocus({ cellId, locale: "fr", depletedDays: 0, sleepKnown: true, eligible: FULL, band: null })!
  for (const id of Object.keys(CELLS) as CellId[]) assertEquals(out(id).kickoff != null, HARD_MORNING_CELLS.has(id), id)
  for (const id of ["P1", "P2", "P3", "P4", "P5", "PX", "OG2", "OG3"] as CellId[]) assert(HARD_MORNING_CELLS.has(id), id)
  for (const id of ["O1", "OG1", "O2", "G1", "G2", "GM"] as CellId[]) assert(!HARD_MORNING_CELLS.has(id), id)
  const k = out("P5").kickoff!
  assertEquals(k.title, "Routine de démarrage du matin")
  assertEquals(k.steps.length, 6)
  assertEquals(k.steps[0].label, "Mouvement")
})

Deno.test("the card reads in the member's language", () => {
  const en = presentFocus({ cellId: "P5", locale: "en", depletedDays: 0, sleepKnown: true, eligible: [], band: null })!
  const fr = presentFocus({ cellId: "P5", locale: "fr", depletedDays: 0, sleepKnown: true, eligible: [], band: null })!
  assertEquals(en.headline, "Today is for holding steady"); assertEquals(fr.headline, "Aujourd’hui, on tient le cap")
  assertEquals(en.tone, "rest"); assertEquals(en.id, "P5")
  assertEquals(presentFocus({ cellId: "XX" as CellId, locale: "en", depletedDays: 0, sleepKnown: true, eligible: [], band: null }), null)
})

Deno.test("a morning cell never offers an evening wind-down card for rest or calm (2026-11-13)", () => {
  const evening = new Set([idOf("rest", 0), idOf("rest", 1)])
  // The library as stored: the "rest" cards 0 and 1 belong to the evening (NSDR, legs up the wall).
  const bank = FULL.map((h) => evening.has(h.id) || h.id === idOf("wind", 0) ? { ...h, defaultSlot: "evening" } : h)
  for (const id of Object.keys(CELLS) as CellId[]) {
    const chosen = chooseHabits(CELLS[id], slotsFor(CELLS[id], sig()), bank, null)
    for (const c of chosen) assert(c.type === "wind" || c.habit.defaultSlot !== "evening", `${id}: ${c.type} -> ${c.habit.title}`)
  }
  // P5 asks for rest first: the evening NSDR is skipped, the daytime pause (midday) takes its place.
  const p5 = chooseHabits(CELLS.P5, slotsFor(CELLS.P5, sig()), bank, null)
  assert(!p5.some((c) => c.habit.id === idOf("rest", 0)))
  assertEquals(p5[0].habit.id, idOf("rest", 2))
  // P1 keeps its "wind-down tonight".
  const p1 = chooseHabits(CELLS.P1, slotsFor(CELLS.P1, sig()), bank, null)
  assert(p1.some((c) => c.type === "wind" && c.habit.id === idOf("wind", 0)))
})
