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
        id: r.id, offerKey: r.offer_key, rank: r.rank, ...words(r, locale),
        pillar: r.pillar, slot: r.slot, variant: r.variant, reason: r.reason, trigger: r.state_key,
        stateTitle: state ? (locale === "fr" && written(state.title_fr) ? state.title_fr : state.title) : null,
        accepted: r.accepted, completed: r.completed,
      }
    })
}
