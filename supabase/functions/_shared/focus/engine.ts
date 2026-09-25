// Today's focus — the decision engine behind the member's morning.
//
// What it does, in one line: the PRACTICE's own state offers (`state_responses`, practitioner-written),
// shaped by what the member said today is FOR (`day_priority`), at the intensity their READINESS can carry
// (`habit_bank` easy · standard · progression).
//
// What it deliberately is not: a language model. `_shared/wearables/ai-policy.ts` (D5) denies every
// wearable reading to an LLM, and readiness is built from wearable physiology — so the engine is rules,
// written down, tested, and the same every time. Pure: no I/O, no clock, no randomness. The same morning
// always yields the same focus, which is also what makes the day able to hold still once computed.
//
// Nothing here invents member-facing words (rule 6): every title and description comes from the practice's
// content tables. The engine returns a REASON CODE; the app owns the one sentence per code, localised.
// Every decision is made on the ENGLISH text (the practice's source); the French rides along beside it
// (`*_fr`, null = not translated yet), and `present.ts` picks the language the member reads.

import { bandLevel } from "../../member-scores/engine/checkin/score-bands.ts"

export type Band = "low" | "mid" | "high"
export type Slot = "morning" | "midday" | "evening"
export type Variant = "easy" | "standard" | "progression"
export type StateKey = "stressed" | "slept_poorly" | "low_energy" | "feeling_strong" | "slept_well"
/**
 * state            — the practice's offer for a state detected this morning (the focus, usually)
 * priority         — a habit for something the member said today is for
 * readiness_low    — same, made gentler because readiness is below the member's OWN baseline
 * recovery_support — one restorative habit added when an effortful day meets low readiness
 */
export type Reason = "state" | "priority" | "readiness_low" | "recovery_support"

export interface StateOffer {
  key: string
  title: string
  description?: string | null
  /** The French, beside the English inside the same `offers` element (keys named like the tables' columns). */
  title_fr?: string | null
  description_fr?: string | null
  easy?: boolean | null
  lift?: boolean | null
}

export interface StateResponse {
  id: string
  stateKey: string
  /** The practice's heading for the state ("A gentler start") — shown above the focus. */
  title: string
  /** null = the practice-wide default; a care plan's own response outranks it. */
  carePlanId: string | null
  offers: StateOffer[]
}

export interface BankHabit {
  id: string
  pillar: string
  category: string | null
  title: string
  description: string | null
  defaultSlot: string | null
  easyTitle: string | null
  easyDescription: string | null
  revTitle: string | null
  revDescription: string | null
  sortOrder: number | null
  /** The French of each text above; absent or null = not translated yet. */
  titleFr?: string | null
  descriptionFr?: string | null
  easyTitleFr?: string | null
  easyDescriptionFr?: string | null
  revTitleFr?: string | null
  revDescriptionFr?: string | null
}

export interface FocusInput {
  /** This morning's sleep score, 0–100 (the check-in's own `sleep_overall`). */
  sleepOverall: number | null
  /** `day_intent` pill keys — how the member is walking into the day. */
  intents: string[]
  /** `day_priority` pill keys, in the order they were tapped — what today is for. */
  priorities: string[]
  /** Today's recovery score, 0–100 (`recoveryScore`, exactly as Trends computes it). Null = unknown. */
  readiness: number | null
  /** True only when a ≥14-day HRV baseline backs `readiness` — the condition for saying "below your usual". */
  readinessVsBaseline: boolean
  /** Active responses the member may see (their care plan's + the practice-wide defaults). */
  states: StateResponse[]
  /** Active habits from the practice library. */
  bank: BankHabit[]
}

export interface FocusOffer {
  /** Stable per day: `state:<state_key>:<offer.key>` or `bank:<habit_bank.id>`. */
  offerKey: string
  /** 1 = the day's focus, 2–3 = also today. */
  rank: number
  title: string
  description: string | null
  /** The same words in French, when the practice has them — null otherwise. */
  titleFr: string | null
  descriptionFr: string | null
  pillar: string | null
  slot: Slot | null
  variant: Variant
  reason: Reason
  /** What triggered it — a state key, a priority pill key, or `readiness_low` (habit_offers.state_key is NOT NULL). */
  trigger: string
  stateResponseId: string | null
  stateTitle: string | null
}

export interface FocusResult {
  states: StateKey[]
  readinessBand: Band | null
  offers: FocusOffer[]
}

/** One focus, then up to two more — a day, not a to-do list (owner decision 2026-09-25). */
export const MAX_OFFERS = 3

// MARK: - States

const STRESS_INTENTS = ["intent_tense", "intent_rushed", "intent_heavy"]
const LOW_INTENTS = ["intent_low", "intent_foggy"]
const STRONG_INTENTS = ["intent_motivated", "intent_determined", "intent_ecstatic"]

/** Hardest first: a stressed or short-slept morning is addressed before a good one is amplified. */
export const STATE_ORDER: StateKey[] = ["stressed", "slept_poorly", "low_energy", "feeling_strong", "slept_well"]

/**
 * The five states the practice wrote responses for, read from what the morning already holds. The cut-offs
 * are the check-in engine's own bands (`bandLevel`: <40 low, 40–60 mid, >60 high) — no new threshold here.
 */
export function detectStates(i: Pick<FocusInput, "sleepOverall" | "intents" | "readiness">): StateKey[] {
  const sleep = bandLevel(i.sleepOverall)
  const ready = bandLevel(i.readiness)
  const has = (keys: string[]) => i.intents.some((k) => keys.includes(k))
  const found = new Set<StateKey>()
  if (has(STRESS_INTENTS)) found.add("stressed")
  if (sleep === "low") found.add("slept_poorly")
  if (has(LOW_INTENTS) || ready === "low") found.add("low_energy")
  if (has(STRONG_INTENTS) && ready !== "low") found.add("feeling_strong")
  if (sleep === "high") found.add("slept_well")
  return STATE_ORDER.filter((s) => found.has(s))
}

// MARK: - Priorities → the library

interface PriorityRule {
  pillar: string
  /** Library categories that fit the intention best, most fitting first. */
  categories: string[]
  /** Asks something of the body or the mind — the case where low readiness should be spoken to. */
  effortful: boolean
}

/** The morning's priority pills (FunctionSchema.swift `dayPriority`) mapped onto the library's pillars. */
export const PRIORITIES: Record<string, PriorityRule> = {
  prio_train: { pillar: "exercise", categories: ["strength", "movement"], effortful: true },
  prio_move: { pillar: "exercise", categories: ["mobility", "movement"], effortful: false },
  prio_eat_well: { pillar: "nutrition", categories: ["food rhythm", "hydration", "mindful eating"], effortful: false },
  prio_deep_work: { pillar: "mind", categories: ["focus", "reset"], effortful: true },
  prio_rest: { pillar: "recovery", categories: ["rest", "breaks", "tension"], effortful: false },
  prio_people: { pillar: "emotion", categories: ["connection"], effortful: false },
  prio_outside: { pillar: "recovery", categories: ["nature"], effortful: false },
  prio_early_night: { pillar: "sleep", categories: ["wind-down", "regularity"], effortful: false },
}

const SLOTS: Slot[] = ["morning", "midday", "evening"]
const asSlot = (s: string | null): Slot | null => (SLOTS as string[]).includes(s ?? "") ? (s as Slot) : null

/** Case, punctuation and spacing folded — "Five minutes outside in daylight" is one idea wherever it is written. */
export function sameIdea(a: string, b: string): boolean {
  const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
  return norm(a) === norm(b)
}

/** Readiness picks the intensity: low → easy, high → progression, otherwise the habit as written. */
export function variantFor(h: BankHabit, band: Band | null): Variant {
  if (band === "low" && h.easyTitle) return "easy"
  if (band === "high" && h.revTitle) return "progression"
  return "standard"
}

type Wording = Pick<FocusOffer, "title" | "description" | "titleFr" | "descriptionFr">

/** A variant's words in both languages. The French falls back EXACTLY where the English does — it follows the
 *  English text it translates, never its own ladder — so the two can never name different versions of a habit
 *  (the gentle one in English, the standard one in French). */
export function wording(h: BankHabit, v: Variant): Wording {
  const [title, titleFr, description, descriptionFr] =
    v === "easy" ? [h.easyTitle, h.easyTitleFr, h.easyDescription, h.easyDescriptionFr]
    : v === "progression" ? [h.revTitle, h.revTitleFr, h.revDescription, h.revDescriptionFr]
    : [null, null, null, null]
  return {
    title: title ?? h.title,
    titleFr: (title != null ? titleFr : h.titleFr) ?? null,
    description: description ?? h.description,
    descriptionFr: (description != null ? descriptionFr : h.descriptionFr) ?? null,
  }
}

/** A state offer's words in both languages. */
const offerWording = (o: StateOffer): Wording => ({
  title: o.title, description: o.description ?? null, titleFr: o.title_fr ?? null, descriptionFr: o.description_fr ?? null,
})

/** The library habit that best serves a priority, deterministically: fitting category, then — on a low or
 *  a high day — one that HAS the gentler or the further version (a low day that lands on a habit with no
 *  gentler version cannot offer one), then an unused moment of the day, the practice's order, the title. */
export function pickHabit(bank: BankHabit[], rule: PriorityRule, taken: { ids: Set<string>; titles: string[]; slots: Set<string> }, band: Band | null = null): BankHabit | null {
  const catRank = (h: BankHabit) => { const i = rule.categories.indexOf(h.category ?? ""); return i < 0 ? 99 : i }
  const lacksIntensity = (h: BankHabit) => band === "low" ? Number(!h.easyTitle) : band === "high" ? Number(!h.revTitle) : 0
  const candidates = bank.filter((h) =>
    h.pillar === rule.pillar && !taken.ids.has(h.id) && !taken.titles.some((t) => sameIdea(t, h.title))
  )
  candidates.sort((a, b) =>
    catRank(a) - catRank(b)
    || lacksIntensity(a) - lacksIntensity(b)
    || Number(taken.slots.has(a.defaultSlot ?? "")) - Number(taken.slots.has(b.defaultSlot ?? ""))
    || (a.sortOrder ?? 999) - (b.sortOrder ?? 999)
    || a.title.localeCompare(b.title)
  )
  return candidates[0] ?? null
}

// MARK: - The decision

/** The response to use for a state: the member's own care plan first, the practice-wide default next. */
export function responseFor(states: StateResponse[], key: StateKey): StateResponse | null {
  const matching = states.filter((s) => s.stateKey === key && s.offers.length > 0)
  return matching.find((s) => s.carePlanId !== null) ?? matching[0] ?? null
}

/** Which of a state's offers leads: the gentle one when readiness is low, otherwise the practice's first. */
export function leadOffer(r: StateResponse, band: Band | null): StateOffer {
  if (band === "low") { const easy = r.offers.find((o) => o.easy === true); if (easy) return easy }
  return r.offers[0]
}

function stateVariant(o: StateOffer): Variant {
  if (o.easy === true) return "easy"
  if (o.key.startsWith("rev_")) return "progression"   // the practice's own convention: rev_ = a step further
  return "standard"
}

export function decideFocus(input: FocusInput): FocusResult {
  const states = detectStates(input)
  // Readiness when there is any; otherwise the member's own read of the night decides the intensity.
  const band: Band | null = bandLevel(input.readiness) ?? bandLevel(input.sleepOverall)
  const offers: FocusOffer[] = []
  const taken = { ids: new Set<string>(), titles: [] as string[], slots: new Set<string>() }
  const bankTwin = (title: string) => input.bank.find((h) => sameIdea(h.title, title)) ?? null
  const push = (o: Omit<FocusOffer, "rank">, bankId?: string) => {
    if (offers.length >= MAX_OFFERS || taken.titles.some((t) => sameIdea(t, o.title))) return
    offers.push({ ...o, rank: offers.length + 1 })
    taken.titles.push(o.title)
    if (bankId) taken.ids.add(bankId)
    if (o.slot) taken.slots.add(o.slot)
  }

  // 1. The focus: the practice's answer to the hardest thing about this morning.
  const lead = states.map((s) => ({ key: s, response: responseFor(input.states, s) })).find((s) => s.response)
  if (lead?.response) {
    const offer = leadOffer(lead.response, band)
    const twin = bankTwin(offer.title)
    push({
      offerKey: `state:${lead.key}:${offer.key}`, ...offerWording(offer),
      pillar: twin?.pillar ?? null, slot: asSlot(twin?.defaultSlot ?? null), variant: stateVariant(offer),
      reason: "state", trigger: lead.key, stateResponseId: lead.response.id, stateTitle: lead.response.title,
    }, twin?.id)
  }

  // 2. What today is for — one habit per priority, at the intensity readiness can carry.
  let effortfulOnLowDay = false
  for (const key of input.priorities) {
    const rule = PRIORITIES[key]
    if (!rule) continue
    const habit = pickHabit(input.bank, rule, taken, band)
    if (!habit) continue
    const variant = variantFor(habit, band)
    // Say why only when it is TRUE: made gentler, and a personal baseline says this is below the usual.
    const gentler = variant === "easy" && bandLevel(input.readiness) === "low" && input.readinessVsBaseline
    // A low day by either measure — wearable readiness, or the member's own read of the night.
    if (rule.effortful && band === "low") effortfulOnLowDay = true
    push({
      offerKey: `bank:${habit.id}`, ...wording(habit, variant), pillar: habit.pillar, slot: asSlot(habit.defaultSlot),
      variant, reason: gentler ? "readiness_low" : "priority", trigger: key, stateResponseId: null, stateTitle: null,
    }, habit.id)
  }

  // 3. The member asked for an effortful day on a low one: honour it, and add one thing that restores.
  if (effortfulOnLowDay) {
    const rest = pickHabit(input.bank, PRIORITIES.prio_rest, taken, band)
    if (rest) {
      const variant = variantFor(rest, band)
      push({
        offerKey: `bank:${rest.id}`, ...wording(rest, variant), pillar: rest.pillar, slot: asSlot(rest.defaultSlot),
        variant, reason: "recovery_support", trigger: "readiness_low", stateResponseId: null, stateTitle: null,
      }, rest.id)
    }
  }

  // 4. No priorities given: the next state the morning revealed gets its say — never filler.
  if (input.priorities.length === 0) {
    for (const s of states.slice(1)) {
      const r = responseFor(input.states, s)
      if (!r) continue
      const offer = leadOffer(r, band)
      const twin = bankTwin(offer.title)
      push({
        offerKey: `state:${s}:${offer.key}`, ...offerWording(offer),
        pillar: twin?.pillar ?? null, slot: asSlot(twin?.defaultSlot ?? null), variant: stateVariant(offer),
        reason: "state", trigger: s, stateResponseId: r.id, stateTitle: r.title,
      }, twin?.id)
    }
  }

  return { states, readinessBand: band, offers }
}
