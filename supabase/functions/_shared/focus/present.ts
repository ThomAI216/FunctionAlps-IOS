import { type BankHabit, wording } from "./engine.ts"
import { type Cell, CELLS, type CellId, HARD_MORNING_CELLS, kickoffSteps, KICKOFF, PRACTITIONER_LINE, showsPractitionerLine } from "./matrix.ts"

// What the member reads back: today's stored offers, in their language when the practice has written it.
//
// The day is stored ONCE, in both languages (`habit_offers.title` / `title_fr`, …), so the language is chosen
// here, on every read — a phone switched to French mid-morning reads the same offers, not a recomputed day.

export type ContentLocale = "en" | "fr"

/** The app sends `en` or `fr`; an Accept-Language header is read by its FIRST language only ("fr-CH,fr;q=0.9"
 *  is French, "de-CH,fr;q=0.8" is not). Anything else, or nothing, reads English. */
export function contentLocale(v: unknown): ContentLocale {
  return typeof v === "string" && v.trim().toLowerCase().startsWith("fr") ? "fr" : "en"
}

export const OFFER_COLUMNS =
  "id,offer_key,rank,title,description,title_fr,description_fr,pillar,slot,variant,reason,state_key,accepted,completed,superseded,state_responses(title,title_fr)"

export interface OfferRow {
  id: string
  offer_key: string
  rank: number | null
  title: string
  description: string | null
  title_fr: string | null
  description_fr: string | null
  pillar: string | null
  slot: string | null
  variant: string | null
  reason: string | null
  state_key: string
  accepted: boolean | null
  completed: boolean
  superseded: boolean
  state_responses: { title: string; title_fr: string | null } | null
}

const written = (s: string | null | undefined): s is string => typeof s === "string" && s.trim() !== ""

/** One offer is ONE language: French only when every text it has in English is also written in French — never a
 *  French title over an English description. Anything short of that reads as the practice wrote it, in English. */
export function words(r: Pick<OfferRow, "title" | "description" | "title_fr" | "description_fr">, locale: ContentLocale) {
  const french = locale === "fr" && written(r.title_fr) && (!written(r.description) || written(r.description_fr))
  return french
    ? { title: r.title_fr as string, description: written(r.description) ? r.description_fr : null }
    : { title: r.title, description: r.description }
}

/** The day's live offers — current ones, plus any retired one the member had already said yes to — in rank order. */
export function present(rows: OfferRow[], locale: ContentLocale) {
  return rows
    .filter((r) => !r.superseded || r.accepted === true || r.completed)
    .sort((a, b) => (a.rank ?? 99) - (b.rank ?? 99))
    .map((r) => {
      const state = r.state_responses
      return {
        id: r.id, offerKey: r.offer_key, cardId: r.offer_key.startsWith("bank:") ? r.offer_key.slice(5) : null, rank: r.rank, ...words(r, locale),
        pillar: r.pillar, slot: r.slot, variant: r.variant, reason: r.reason, trigger: r.state_key,
        stateTitle: state ? (locale === "fr" && written(state.title_fr) ? state.title_fr : state.title) : null,
        accepted: r.accepted, completed: r.completed,
      }
    })
}

// MARK: - The day's readiness (`patient_day_state`)

/** `patient_day_state` as selected — the day as the engine read it, stored once after the morning check-in. */
export interface DayStateRow {
  readiness_band: string | null
  readiness_vs_baseline: boolean
  band_source: string | null
  /** The matrix cell the day was decided on (`patient_day_state.focus_cell`), stored so the card holds still. */
  focus_cell?: string | null
}

export interface DayReadiness {
  /** The check-in engine's own bands: <40 low, 40–60 mid, >60 high. */
  band: "low" | "mid" | "high"
  /** True only when a personal HRV baseline backs the band — the condition for saying "below your usual". */
  vsBaseline: boolean
  /** Where the band came from: a wearable's recovery, or the member's own read of the night. */
  source: "wearable" | "self_report" | null
}

/** What the app reads back — null when the day has no band (no morning yet, or a morning that gave none). */
export function dayReadiness(row: DayStateRow | null | undefined): DayReadiness | null {
  if (!row) return null
  const band = row.readiness_band
  if (band !== "low" && band !== "mid" && band !== "high") return null
  const source = row.band_source === "wearable" || row.band_source === "self_report" ? row.band_source : null
  return { band, vsBaseline: row.readiness_vs_baseline === true, source }
}

// MARK: - The card itself (the matrix cell, in the member's language)

/** A habit's words in one language: French only when everything it has in English is also written in French. */
export function cardWords(h: BankHabit, variant: "easy" | "standard" | "progression", locale: ContentLocale): { title: string; description: string | null } {
  const w = wording(h, variant)
  return words({ title: w.title, description: w.description, title_fr: w.titleFr, description_fr: w.descriptionFr }, locale)
}

/** The kickoff routine as the app walks it: title, subtitle and one step per card, in the owner's order. Null when
 *  fewer than two of its cards are eligible for this member. */
export function presentKickoff(eligible: BankHabit[], band: "low" | "mid" | "high" | null, locale: ContentLocale) {
  const steps = kickoffSteps(eligible, band)
  if (steps.length === 0) return null
  return {
    key: KICKOFF.key,
    title: KICKOFF.title[locale],
    subtitle: KICKOFF.subtitle[locale],
    finishTitle: KICKOFF.finish[locale].title,
    finishLine: KICKOFF.finish[locale].line,
    steps: steps.map((s) => ({ kind: s.kind, label: s.label[locale], cardId: s.habit.id, ...cardWords(s.habit, s.variant, locale) })),
  }
}

/** What `member-daily-focus` returns beside the offers, as `cell`: the cell's headline and line, its tone (what the card is drawn
 *  in), the practitioner line when it applies, and the kickoff routine on a hard morning. `sleepKnown` false = the
 *  member left the night blank, so the card never mentions it. */
export function presentFocus(opts: {
  cellId: CellId
  locale: ContentLocale
  depletedDays: number
  sleepKnown: boolean
  eligible: BankHabit[]
  band: "low" | "mid" | "high" | null
}) {
  const cell: Cell | undefined = CELLS[opts.cellId]
  if (!cell) return null
  const text = cell[opts.locale]
  const line = !opts.sleepKnown && cell.noSleep ? cell.noSleep[opts.locale] : text.line
  const hard = HARD_MORNING_CELLS.has(cell.id)
  return {
    id: cell.id,
    headline: text.headline,
    line,
    tone: cell.tone,
    practitionerLine: showsPractitionerLine(cell, opts.depletedDays) ? PRACTITIONER_LINE[opts.locale] : null,
    hardMorning: hard,
    kickoff: hard ? presentKickoff(opts.eligible, opts.band, opts.locale) : null,
  }
}
