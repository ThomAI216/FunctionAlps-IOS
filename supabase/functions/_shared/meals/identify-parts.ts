// The multimodal user-content array for one identification call.
//
// PURE LEAF — same rule as meal-coverage.ts: no `npm:` / `https://esm.sh/`
// imports, ever. It lives here rather than inline in meal-analysis.ts so the cap,
// the ordering and the exact wording are testable from vitest — and the
// single-photo payload, which every latency measurement in this codebase was
// taken against, is regression-locked by identify-parts.test.ts.

/**
 * Hard cap on images per identification call.
 *
 * MEASURED, not guessed — see the spike result in
 * docs/prd/2026-08-04-multi-photo-meal-coverage-design.md §11. Latency turned out
 * NOT to be the binding constraint (p50 is flat at ~1.5 s from one image to four,
 * against a 9 s deadline), so this is set by what was actually exercised rather
 * than by a deadline calculation. Four is clean on every run; beyond four is
 * untested and must not be assumed.
 */
export const MAX_IDENTIFY_IMAGES = 4

/**
 * The stated-items half of the prompt.
 *
 * ⚠ STRUCTURALLY typed, not imported. `_shared/stated-items.ts` owns
 * `StatedItem` and everything that VALIDATES or ENFORCES it; this file owns the
 * words that go to the model. They are not merged because this file must keep
 * ZERO imports: `lib/` reaches it, `tsc --noEmit` type-checks whatever `lib/`
 * reaches, and a Deno `./stated-items.ts` specifier is TS5097 there. A
 * structural parameter costs nothing and still fails the build at the call site
 * if `StatedItem` ever loses a field this reads.
 */
export type StatedPortion = { name: string; grams: number; volume_measure?: string }

/**
 * ⚠ Emitted ONLY when there are stated items, which is what keeps every latency
 * and hang figure in `meal-analysis.ts` valid: with none, the payload is
 * byte-identical to what it has been since v56 (locked by the tests beside this
 * file). Same discipline as the multi-photo sentence — a new clause pays for
 * itself or it is not there.
 */
export function statedItemsInstruction(stated: readonly StatedPortion[]): string {
  const lines = stated
    .map((it) => `- ${it.name}: ${it.grams} g${it.volume_measure ? ` (${it.volume_measure})` : ""}`)
    .join("\n")
  return [
    "The person stated these foods and these portions themselves:",
    lines,
    "Those grams are FACTS the person gave you, not estimates: return each of these foods with EXACTLY the grams listed above, and never re-estimate one of them.",
    "Give each one its proper food name (state cooked/raw where it changes the food) and its flags. Never put a quantity inside a name.",
  ].join("\n")
}

export type UserPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } }

export type IdentifyPartsInput = {
  description?: string | null
  /** `data:` or `https:` URLs, in the order the patient picked them. */
  imageUrls?: string[]
  /** Foods and portions the MEMBER stated — see _shared/stated-items.ts. */
  statedItems?: readonly StatedPortion[]
}

/** The text part. Split out so the N>1 sentence can be asserted on its own. */
export function identifyInstruction(
  description: string | undefined,
  imageCount: number,
  stated: readonly StatedPortion[] = [],
): string {
  // ⚠ The free-text description is DROPPED when a structured list is present,
  // and that is the fix rather than an optimisation. On the voice path the
  // description IS that list flattened — `"chicken 100g, parmigiano 30g"` — so
  // sending both would hand the model the same facts twice, once in the form
  // that made it read "chicken 100g" as a food name. The structured block
  // carries strictly more (names, grams and volume, each in its own field), so
  // nothing is lost by letting it supersede the prose it came from.
  const desc = stated.length ? undefined : description
  const base = desc
    ? `Analyse this meal. The person described it as: "${desc}". Identify each food and estimate its portion in grams.`
    : stated.length && imageCount === 0
    ? "Analyse this meal. Identify each food and estimate its portion in grams."
    : "Analyse this meal photo. Identify each food and estimate its portion in grams."
  // Only when it earns its tokens. At one photo the payload must stay exactly
  // what it has been since v56.
  const withPhotos = imageCount < 2
    ? base
    : `${base} This meal was photographed in ${imageCount} photos. The SAME food may appear in more than one photo — count each portion ONCE.`
  return stated.length ? `${withPhotos}\n\n${statedItemsInstruction(stated)}` : withPhotos
}

export function buildIdentifyUserParts(input: IdentifyPartsInput): UserPart[] {
  const images = (input.imageUrls ?? [])
    .filter((u): u is string => typeof u === "string" && u.length > 0)
    .slice(0, MAX_IDENTIFY_IMAGES)
  const description = input.description?.trim() || undefined
  const stated = input.statedItems ?? []
  return [
    { type: "text", text: identifyInstruction(description, images.length, stated) },
    ...images.map((url) => ({ type: "image_url" as const, image_url: { url } })),
  ]
}

// Storage hands back bytes; the model wants base64. Chunked because
// String.fromCharCode(...bytes) blows the argument limit on a real photo — a
// meal photo is hundreds of kilobytes.
export function bytesToBase64(bytes: Uint8Array): string {
  let binary = ""
  const CHUNK = 0x8000
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK))
  }
  return btoa(binary)
}

/**
 * Which storage paths make up this meal, from a row.
 *
 * ⚠ `photo_urls` is the FULL ordered set and its element 0 IS `photo_url`. They
 * are never concatenated — a caller that adds them together re-analyses the first
 * plate twice, which is the single most likely way this pair of columns gets
 * misused. One function, used by analyze-meal and by the retry worker, so the
 * rule exists in exactly one place.
 */
export function photoPathsFor(row: { photo_url?: string | null; photo_urls?: string[] | null }): string[] {
  const many = (row.photo_urls ?? []).filter((p): p is string => typeof p === "string" && p.length > 0)
  if (many.length) return many.slice(0, MAX_IDENTIFY_IMAGES)
  return row.photo_url ? [row.photo_url] : []
}
