// Coverage — "did I see the whole meal?" — as a PURE LEAF.
//
// ⚠ NO `npm:` OR `https://esm.sh/` IMPORTS MAY EVER BE ADDED HERE. This module is
// imported by vitest from lib/meal-log/__tests__/, and Node chokes on those
// specifiers. `_shared/meal-analysis.ts` has them, which is exactly why this
// logic lives apart from it rather than inside it — the same reason
// analysis-status-mirror.test.ts has to read that file as TEXT.

export const COVERAGE_VALUES = ["full", "partial"] as const
export type Coverage = (typeof COVERAGE_VALUES)[number]

/** Longest coverage note we persist. It is one phrase, not an essay. */
export const MAX_COVERAGE_NOTE_CHARS = 80

// The same shape-scrub meal-analysis.ts runs over analysis_last_error: any long
// unbroken token could be a base64 fragment, an id, or a signed URL. This string
// lands in a durable column that a clinician reads.
const PII_SHAPED = /[A-Za-z0-9+/=_-]{64,}/g

/**
 * FAIL OPEN — anything that is not recognisably "partial" becomes "full".
 *
 * The failure mode that matters is not a missed partial plate. It is a stale
 * deploy, an older model, or a malformed response making the app nag every
 * patient about every meal. Silence is the safe default here; a nudge is not.
 *
 * Measured, not assumed: on a full plate the model omits the `coverage_note` key
 * entirely rather than sending "" (spike §11), and it reports `partial` reliably
 * on a cropped one (spike §12) — so "absent" genuinely means full.
 */
export function sanitiseCoverage(raw: unknown): Coverage {
  return typeof raw === "string" && raw.trim().toLowerCase() === "partial" ? "partial" : "full"
}

/**
 * The short human phrase the nudge quotes. Null whenever there is nothing
 * usable — the card carries its own fallback sentence, and an empty quote reads
 * worse than no quote at all.
 *
 * Scrub BEFORE the cap: truncating first could leave the head of a long opaque
 * token in the column, which is the thing the scrub exists to keep out.
 */
export function sanitiseCoverageNote(raw: unknown): string | null {
  if (typeof raw !== "string") return null
  const cleaned = raw.replace(PII_SHAPED, "…").replace(/\s+/g, " ").trim()
  return cleaned ? cleaned.slice(0, MAX_COVERAGE_NOTE_CHARS) : null
}
