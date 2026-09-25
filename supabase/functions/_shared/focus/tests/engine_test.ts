import { assert, assertEquals } from "jsr:@std/assert@1"
import {
  type BankHabit, decideFocus, detectStates, type FocusInput, leadOffer, MAX_OFFERS, pickHabit, PRIORITIES,
  responseFor, sameIdea, type StateResponse, variantFor,
} from "../engine.ts"

// The practice's own content, as CM OS holds it on 2026-09-25 (`state_responses`, all five practice-wide).
const STATES: StateResponse[] = [
  { id: "sr-strong", stateKey: "feeling_strong", title: "Turn it up a notch", carePlanId: null, offers: [
    { key: "rev_walk_20", title: "Stretch today's walk to 20 minutes", description: "Same walk, a little further — bank the good day.", easy: false },
    { key: "rev_extra_set", title: "One extra set of push-ups", description: "Form over count, as always.", easy: false },
  ] },
  { id: "sr-low", stateKey: "low_energy", title: "Low-battery mode", carePlanId: null, offers: [
    { key: "daylight_pause", title: "Five minutes outside in daylight", description: "A short reset — no workout required.", easy: true },
    { key: "lift_move_flat_day", title: "Five minutes of easy movement", description: "It sounds backwards on a flat day…", easy: false, lift: true },
  ] },
  { id: "sr-poor", stateKey: "slept_poorly", title: "A gentler start", carePlanId: null, offers: [
    { key: "fruit_within_reach", title: "Keep a piece of fruit within reach", description: "When the afternoon dip hits…", easy: true },
    { key: "lift_walk_short_night", title: "A short walk outside", description: "Ten minutes of daylight…", easy: false, lift: true },
  ] },
  { id: "sr-well", stateKey: "slept_well", title: "Ride the good night", carePlanId: null, offers: [
    { key: "morning_walk", title: "A 10-minute morning walk", description: "Lock in the good night with light movement.", easy: false },
    { key: "pushup_set", title: "One set of push-ups", description: "Whatever number feels doable — form over count.", easy: false },
  ] },
  { id: "sr-stress", stateKey: "stressed", title: "A two-minute reset", carePlanId: null, offers: [
    { key: "three_slow_breaths", title: "Three slow breaths, three times today", description: "Before meals works well…", easy: true },
    { key: "lift_walk_tension", title: "A walk around the block", description: "Tension moves out faster…", easy: false, lift: true },
  ] },
]

const h = (id: string, pillar: string, category: string, title: string, slot: string, sort: number, easy?: string, rev?: string): BankHabit => ({
  id, pillar, category, title, description: `${title}.`, defaultSlot: slot, sortOrder: sort,
  easyTitle: easy ?? null, easyDescription: null, revTitle: rev ?? null, revDescription: null,
})

// A slice of `habit_bank`: titles, pillars, categories, default slots and WHICH variants exist are as stored.
// Sort orders, and the variant wordings not quoted below, are stand-ins. Quoted as stored: "Five sit-to-stands" /
// "Two rounds of ten", "Five minutes outside" / "Stretch it to 20 minutes", "Two sets — rest a minute between",
// "Two stretches at the counter".
const BANK: BankHabit[] = [
  h("walk-lunch", "exercise", "movement", "A 10-minute walk after lunch", "midday", 1, "Five minutes outside", "Stretch it to 20 minutes"),
  h("stretch", "exercise", "mobility", "Morning stretch, five minutes", "morning", 2, "Two stretches at the counter"),
  h("pushups", "exercise", "strength", "One set of push-ups", "morning", 3, undefined, "Two sets — rest a minute between"),
  h("sit-stand", "exercise", "strength", "Ten sit-to-stands", "midday", 6, "Five sit-to-stands", "Two rounds of ten"),
  h("protein", "nutrition", "food rhythm", "Protein at breakfast", "morning", 2, "Something with protein before noon"),
  h("veg", "nutrition", "food rhythm", "Vegetables on half the plate", "midday", 3),
  h("water", "nutrition", "hydration", "A glass of water before coffee", "morning", 1),
  h("single-task", "mind", "focus", "Single-task the first work hour", "morning", 4, "Single-task the first 20 minutes"),
  h("phone-free", "mind", "focus", "One phone-free coffee", "morning", 3),
  h("lunch-pause", "recovery", "breaks", "A real pause at lunch, no screens", "midday", 1, "Ten screen-free minutes at lunch"),
  h("legs-up", "recovery", "rest", "Legs up the wall, five minutes", "evening", 3),
  h("daylight", "recovery", "nature", "Five minutes outside in daylight", "midday", 2),
  h("nature-walk", "recovery", "nature", "A 20-minute nature walk", "midday", 6, undefined, "Make it 40 minutes"),
  h("screens-off", "sleep", "wind-down", "Screens off 30 minutes before bed", "evening", 3, "Screens off 10 minutes before bed"),
  h("message", "emotion", "connection", "One message to someone you like", "midday", 2),
]

const base = (over: Partial<FocusInput> = {}): FocusInput => ({
  sleepOverall: 55, intents: [], priorities: [], readiness: 55, readinessVsBaseline: true, states: STATES, bank: BANK, ...over,
})

// MARK: - States

Deno.test("states are read from the morning with the check-in's own bands, hardest first", () => {
  assertEquals(detectStates({ sleepOverall: 30, intents: ["intent_tense"], readiness: null }), ["stressed", "slept_poorly"])
  assertEquals(detectStates({ sleepOverall: 80, intents: ["intent_motivated"], readiness: 75 }), ["feeling_strong", "slept_well"])
  assertEquals(detectStates({ sleepOverall: 50, intents: [], readiness: 50 }), [])
  // Low readiness is low energy even when the member didn't say so…
  assertEquals(detectStates({ sleepOverall: 50, intents: [], readiness: 30 }), ["low_energy"])
  // …and it vetoes "feeling strong" when the body disagrees with the mood.
  assertEquals(detectStates({ sleepOverall: 50, intents: ["intent_determined"], readiness: 30 }), ["low_energy"])
  // The boundaries are the engine's: 40 is mid, 39 is low, 61 is high.
  assertEquals(detectStates({ sleepOverall: 40, intents: [], readiness: null }), [])
  assertEquals(detectStates({ sleepOverall: 39, intents: [], readiness: null }), ["slept_poorly"])
  assertEquals(detectStates({ sleepOverall: 61, intents: [], readiness: null }), ["slept_well"])
})

Deno.test("a care plan's own response outranks the practice-wide default", () => {
  const own: StateResponse = { id: "sr-own", stateKey: "stressed", title: "Your reset", carePlanId: "cp-1", offers: [{ key: "own", title: "Your own breathing", easy: true }] }
  assertEquals(responseFor([...STATES, own], "stressed")?.id, "sr-own")
  assertEquals(responseFor(STATES, "stressed")?.id, "sr-stress")
  // A response with nothing to offer is no response.
  assertEquals(responseFor([{ ...own, offers: [] }], "stressed"), null)
})

Deno.test("on a low day the state leads with the practice's gentle offer", () => {
  const strongish: StateResponse = { id: "x", stateKey: "slept_well", title: "t", carePlanId: null, offers: [
    { key: "a", title: "Harder", easy: false }, { key: "b", title: "Gentler", easy: true },
  ] }
  assertEquals(leadOffer(strongish, "low").key, "b")
  assertEquals(leadOffer(strongish, "mid").key, "a")
})

// MARK: - The library

Deno.test("readiness picks the intensity — only when the habit has that variant", () => {
  const sit = BANK.find((b) => b.id === "sit-stand")!
  assertEquals(variantFor(sit, "low"), "easy")
  assertEquals(variantFor(sit, "mid"), "standard")
  assertEquals(variantFor(sit, "high"), "progression")
  assertEquals(variantFor(sit, null), "standard")
  const veg = BANK.find((b) => b.id === "veg")!
  assertEquals(variantFor(veg, "low"), "standard")   // no gentler version written → the habit as it is
  assertEquals(variantFor(veg, "high"), "standard")
})

Deno.test("a priority finds its habit by fitting category, then an unused moment, then the practice's order", () => {
  const taken = { ids: new Set<string>(), titles: [] as string[], slots: new Set<string>() }
  assertEquals(pickHabit(BANK, PRIORITIES.prio_train, taken)?.id, "pushups")           // strength before movement
  assertEquals(pickHabit(BANK, PRIORITIES.prio_outside, taken)?.id, "daylight")        // nature, lowest sort order
  taken.slots.add("morning")
  assertEquals(pickHabit(BANK, PRIORITIES.prio_train, taken)?.id, "sit-stand")         // strength, and not the morning again
  taken.ids.add("sit-stand")
  assertEquals(pickHabit(BANK, PRIORITIES.prio_train, taken)?.id, "pushups")           // morning again beats nothing
})

Deno.test("the same idea is the same idea however it is written", () => {
  assert(sameIdea("Five minutes outside in daylight", "five minutes outside, in daylight."))
  assert(!sameIdea("Fruit within reach", "Keep a piece of fruit within reach"))
})

// MARK: - The decision

Deno.test("a stressed morning with priorities: the practice's reset leads, the day's intentions follow", () => {
  const r = decideFocus(base({ intents: ["intent_tense"], priorities: ["prio_eat_well", "prio_deep_work"] }))
  assertEquals(r.states, ["stressed"])
  assertEquals(r.offers.map((o) => [o.rank, o.offerKey, o.reason]), [
    [1, "state:stressed:three_slow_breaths", "state"],
    [2, "bank:protein", "priority"],
    [3, "bank:phone-free", "priority"],       // both focus habits are mornings; the practice's order decides
  ])
  assertEquals(r.offers[0].stateTitle, "A two-minute reset")
  assertEquals(r.offers[0].stateResponseId, "sr-stress")
  assertEquals(r.offers[0].variant, "easy")
})

Deno.test("never more than one focus and two more", () => {
  const r = decideFocus(base({ intents: ["intent_tense"], priorities: ["prio_train", "prio_eat_well", "prio_deep_work", "prio_people"] }))
  assertEquals(r.offers.length, MAX_OFFERS)
  assertEquals(r.offers.map((o) => o.rank), [1, 2, 3])
})

Deno.test("'Train hard' on a low day: honoured, made gentler, said why, and one thing that restores", () => {
  const r = decideFocus(base({ priorities: ["prio_train"], readiness: 25, readinessVsBaseline: true }))
  // Low readiness is also a detected state — the practice's low-battery offer leads.
  assertEquals(r.offers[0].offerKey, "state:low_energy:daylight_pause")
  const train = r.offers.find((o) => o.trigger === "prio_train")!
  assertEquals(train.offerKey, "bank:sit-stand")        // push-ups have no gentler version; sit-to-stands do
  assertEquals(train.variant, "easy")
  assertEquals(train.title, "Five sit-to-stands")
  assertEquals(train.reason, "readiness_low")
  const rest = r.offers.find((o) => o.reason === "recovery_support")!
  assertEquals(rest.pillar, "recovery")
  // The daylight habit is already the focus (same idea) — the restorative add is a different one.
  assert(!sameIdea(rest.title, "Five minutes outside in daylight"))
})

Deno.test("'below your usual' is only said when a personal baseline backs it", () => {
  const r = decideFocus(base({ priorities: ["prio_train"], readiness: 25, readinessVsBaseline: false }))
  const train = r.offers.find((o) => o.trigger === "prio_train")!
  assertEquals(train.variant, "easy")          // still gentler…
  assertEquals(train.reason, "priority")       // …but no claim the data can't support
})

Deno.test("with no wearable, the member's own read of the night sets the intensity", () => {
  const poor = decideFocus(base({ sleepOverall: 25, readiness: null, readinessVsBaseline: false, priorities: ["prio_train"] }))
  assertEquals(poor.readinessBand, "low")
  assertEquals(poor.offers[0].offerKey, "state:slept_poorly:fruit_within_reach")
  const train = poor.offers.find((o) => o.trigger === "prio_train")!
  assertEquals(train.variant, "easy")
  assertEquals(train.reason, "priority")
  assert(poor.offers.some((o) => o.reason === "recovery_support"))   // a low day by the member's own measure counts
})

Deno.test("a strong morning goes a step further where the practice wrote one", () => {
  const r = decideFocus(base({ sleepOverall: 80, intents: ["intent_motivated"], readiness: 78, priorities: ["prio_train"] }))
  assertEquals(r.states, ["feeling_strong", "slept_well"])
  assertEquals(r.offers[0].offerKey, "state:feeling_strong:rev_walk_20")
  assertEquals(r.offers[0].variant, "progression")
  const train = r.offers.find((o) => o.trigger === "prio_train")!
  assertEquals(train.variant, "progression")
  assertEquals(train.title, "Two sets — rest a minute between")
})

Deno.test("no priorities: the next state the morning revealed has its say — never filler", () => {
  const r = decideFocus(base({ sleepOverall: 25, intents: ["intent_tense"] }))
  assertEquals(r.offers.map((o) => o.trigger), ["stressed", "slept_poorly"])
  const quiet = decideFocus(base({ sleepOverall: 50, intents: [], readiness: 50 }))
  assertEquals(quiet.offers, [])
})

Deno.test("priorities alone make a day: the first one leads", () => {
  const r = decideFocus(base({ priorities: ["prio_early_night", "prio_people"] }))
  assertEquals(r.offers.map((o) => [o.rank, o.offerKey]), [[1, "bank:screens-off"], [2, "bank:message"]])
})

Deno.test("the same idea is never offered twice, whoever wrote it", () => {
  // Low battery → the practice offers "Five minutes outside in daylight"; the member also wants to get outside,
  // and the library's best "outside" habit is that very sentence. It must not come back as the second offer.
  const r = decideFocus(base({ readiness: 30, priorities: ["prio_outside"] }))
  assertEquals(r.offers[0].offerKey, "state:low_energy:daylight_pause")
  assertEquals(r.offers.find((o) => o.trigger === "prio_outside")?.offerKey, "bank:nature-walk")
  const titles = r.offers.map((o) => o.title.toLowerCase())
  assertEquals(new Set(titles).size, titles.length)
})

Deno.test("on a low day the habit chosen is one that HAS a gentler version; on a high day, a further one", () => {
  const taken = () => ({ ids: new Set<string>(), titles: [] as string[], slots: new Set<string>() })
  assertEquals(pickHabit(BANK, PRIORITIES.prio_train, taken(), null)?.id, "pushups")       // no preference: the order
  assertEquals(pickHabit(BANK, PRIORITIES.prio_train, taken(), "low")?.id, "sit-stand")    // push-ups have no easy form
  assertEquals(pickHabit(BANK, PRIORITIES.prio_train, taken(), "high")?.id, "pushups")     // both go further; order
  // Fit to the intention still comes first: a rest day never becomes a walk because the walk has an easy form.
  assertEquals(pickHabit(BANK, PRIORITIES.prio_rest, taken(), "low")?.id, "legs-up")
})

Deno.test("unknown priority keys are ignored, not fatal", () => {
  const r = decideFocus(base({ priorities: ["prio_unheard_of", "prio_eat_well"] }))
  assertEquals(r.offers.map((o) => o.trigger), ["prio_eat_well"])
})

Deno.test("deterministic: the same morning always yields the same focus", () => {
  const input = base({ intents: ["intent_tense"], priorities: ["prio_eat_well", "prio_deep_work"], sleepOverall: 30 })
  assertEquals(decideFocus(input), decideFocus(input))
})
