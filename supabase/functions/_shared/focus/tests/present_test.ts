import { assertEquals } from "jsr:@std/assert@1"
import { contentLocale, type OfferRow, present, words } from "../present.ts"

const row = (over: Partial<OfferRow> = {}): OfferRow => ({
  id: "o1", offer_key: "bank:sit", rank: 1,
  title: "Five sit-to-stands", description: "Half a round still counts.",
  title_fr: "Cinq assis-debout", description_fr: "Une demi-série compte quand même.",
  pillar: "exercise", slot: "midday", variant: "easy", reason: "priority", state_key: "prio_train",
  accepted: null, completed: false, superseded: false, state_responses: null, ...over,
})

Deno.test("the app's locale is read loosely; anything unknown is English", () => {
  assertEquals(contentLocale("fr"), "fr")
  assertEquals(contentLocale("fr-CH"), "fr")
  assertEquals(contentLocale(" FR "), "fr")
  assertEquals(contentLocale("en"), "en")
  assertEquals(contentLocale("de"), "en")
  assertEquals(contentLocale(undefined), "en")
  assertEquals(contentLocale(null), "en")
  // The Accept-Language fallback: its first language decides.
  assertEquals(contentLocale("fr-CH,fr;q=0.9,en;q=0.8"), "fr")
  assertEquals(contentLocale("de-CH,fr;q=0.8"), "en")
  assertEquals(contentLocale(42), "en")
})

Deno.test("an offer is one language — French only when all of it is written in French", () => {
  assertEquals(words(row(), "fr"), { title: "Cinq assis-debout", description: "Une demi-série compte quand même." })
  assertEquals(words(row(), "en"), { title: "Five sit-to-stands", description: "Half a round still counts." })
  // A French title over an English description would be two languages in one line — English instead.
  assertEquals(words(row({ description_fr: null }), "fr"), { title: "Five sit-to-stands", description: "Half a round still counts." })
  // Nothing in French yet — including a blank the practice left.
  assertEquals(words(row({ title_fr: null }), "fr").title, "Five sit-to-stands")
  assertEquals(words(row({ title_fr: "  " }), "fr").title, "Five sit-to-stands")
  // No description in English: the French title alone is the whole offer.
  assertEquals(words(row({ description: null, description_fr: null }), "fr"), { title: "Cinq assis-debout", description: null })
})

Deno.test("the day reads back in rank order, live offers only, heading in the same language", () => {
  const rows = [
    row({ id: "b", rank: 2 }),
    row({ id: "gone", rank: 3, superseded: true }),                       // retired by a re-check-in
    row({ id: "kept", rank: 4, superseded: true, completed: true }),      // retired, but already done — it stays
    row({ id: "a", rank: 1, offer_key: "state:stressed:three_slow_breaths", state_key: "stressed", reason: "state",
          state_responses: { title: "A two-minute reset", title_fr: "Deux minutes pour souffler" } }),
  ]
  const fr = present(rows, "fr")
  assertEquals(fr.map((o) => o.id), ["a", "b", "kept"])
  assertEquals(fr[0].stateTitle, "Deux minutes pour souffler")
  assertEquals(fr[1].stateTitle, null)
  assertEquals(fr[0].trigger, "stressed")
  assertEquals(present(rows, "en")[0].stateTitle, "A two-minute reset")
  // A heading not yet translated reads in English, whatever the offer does.
  const untranslated = present([row({ state_responses: { title: "A two-minute reset", title_fr: null } })], "fr")[0]
  assertEquals(untranslated.stateTitle, "A two-minute reset")
})
