// meal-analysis — the two halves of a meal analysis, plus the retry schedule,
// shared by BOTH callers so they cannot drift apart:
//
//   analyze-meal          interactive, writes under the CALLER'S JWT
//   retry-meal-analysis   per-minute cron, writes with the service role
//
// The split this module encodes is the same one v56 made inside analyze-meal:
//
//   identifyMeal()  Infomaniak (Geneva) sovereign AI  ->  WHAT is on the plate
//   priceMeal()     _shared/food-resolver.ts          ->  every NUMBER
//
// WHY they are separated here and not just factored for tidiness: only
// identification is EXPOSED. It rides an external connection that hangs at the
// connection level on ~53% of attempts. Pricing reads our own Postgres and
// embeds via `Supabase.ai.Session('gte-small')` inside this runtime, touching
// no external network at all. That asymmetry is the whole retry design — the
// worker only ever re-rolls identification, because pricing has no dice.
//
// It is shared as a MODULE rather than reached over HTTP so that analyze-meal
// can stay behind JWT verification. A worker POSTing to analyze-meal would
// force that function to `--no-verify-jwt` and turn the app's most expensive AI
// call into an unauthenticated endpoint.
// The client type comes from `npm:` because that is what `_shared/supabase.ts`
// builds and what both callers therefore hold. `food-resolver.ts` types its own
// parameter from `https://esm.sh/…` — same library, same runtime object, two
// nominally distinct TS types. That mismatch is absorbed at ONE cast, at the
// resolveItems seam, rather than at every call site. Aligning the specifiers
// across the shared modules is a change to already-deployed code and belongs in
// its own commit.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"
import type { SupabaseClient as ResolverClient } from "https://esm.sh/@supabase/supabase-js@2"
import { scoreMeal, type MealScores } from "./meal-scores.ts"
import { sanitizeFlags, type FoodFlagKey } from "./meal-flags.ts"
import { resolveItems, type EmbeddingSession, type ResolvedItem } from "./food-resolver.ts"
import { matchProtocols, type ProtocolFlag } from "./protocol-foods.ts"
import { sanitiseCoverage, sanitiseCoverageNote, type Coverage } from "./meal-coverage.ts"
import { buildIdentifyUserParts, MAX_IDENTIFY_IMAGES } from "./identify-parts.ts"
import { applyStatedGrams, stripTrailingQuantity, type StatedItem } from "./stated-items.ts"

// The Edge Runtime injects `Supabase.ai`; `deno check` has no types for it. This
// declares exactly the slice we use and is erased at runtime — it is the reason
// `deno check` is clean on both functions instead of reporting a known TS2304.
declare const Supabase: { ai: { Session: new (model: string) => EmbeddingSession } }

// ---------------------------------------------------------------------------
// Retry schedule — ONE source of truth for both callers
// ---------------------------------------------------------------------------
//
// 5s · 15s · 45s · 2m · 5m · 15m · 30m · 1h. Front-loaded because the hangs are
// INDEPENDENT (p implied 0.523 on the 2-attempt config, 0.543 on the
// 3-attempt one — two configurations, one number), so a quick re-roll is a
// genuinely fresh chance rather than a repeat of the same bad outcome. The tail
// is long because by attempt 6 the plausible cause has changed from "bad
// connection" to "upstream is down", and hammering it does not help.
//
// ⚠ THE FIRST ENTRY IS EFFECTIVELY UNREACHABLE, and that is not a bug to
// "fix" by shifting the index. `attempts` is counted at CLAIM time, so by the
// time anything schedules a retry at least one has been spent and the lookup
// starts at 15s. Index 0 is only reached by a row nobody has attempted. The
// real observed schedule is therefore 15s · 45s · 2m · 5m · 15m · 30m · 1h —
// seven retries after the interactive attempt, which is exactly MAX_ATTEMPTS
// identifications in total, spread over about 111 minutes.
//
// 0.53^8 = 0.62%. Whatever survives that goes to `needs_input`, where the
// patient — who always knows what they ate — closes it.
export const RETRY_BACKOFF_S = [5, 15, 45, 120, 300, 900, 1800, 3600] as const
export const MAX_ATTEMPTS = 8

/** Seconds until the next attempt, indexed by attempts already spent, clamped
 *  to the last entry. Never null — exhaustion is the CALLER'S decision
 *  (`attempts >= MAX_ATTEMPTS` -> needs_input), not this function's. */
export function backoffSeconds(attempts: number): number {
  const i = Math.max(0, Math.floor(attempts))
  return RETRY_BACKOFF_S[Math.min(i, RETRY_BACKOFF_S.length - 1)]
}

/** ISO timestamp for `analysis_next_retry_at`. */
export function nextRetryAt(attempts: number, now: Date = new Date()): string {
  return new Date(now.getTime() + backoffSeconds(attempts) * 1000).toISOString()
}

// A row claimed longer ago than this with no result is presumed abandoned: a
// browser tab that backgrounded or closed mid-request, or a killed isolate.
// Two minutes is comfortably longer than the 9s identification deadline plus
// pricing, and short enough that a patient on the confirm screen does not wait
// a whole retry cycle for a row nobody owns.
export const CLAIM_STALE_MS = 120_000

// ---------------------------------------------------------------------------
// PII guard for `analysis_last_error`
// ---------------------------------------------------------------------------
//
// 🚨 That column takes UPSTREAM/TECHNICAL text ONLY — status codes, timeout
// messages, model errors. NEVER the description, the transcript, any part of
// the photo, or model output. `nb_meal_logs` deliberately has exactly two prose
// columns (`patient_note` = the person typed it, `ai_coaching_response` = a
// model wrote it) and this is not a third one.
//
// The rule is enforced STRUCTURALLY, not by discipline: `IdentifyFailure` keeps
// the technical string separate from the `response` body, so the only text that
// can reach the column is text this module built from a status code or an Error
// message. sanitiseError is the second gate, not the only one.
const PII_SHAPED = /[A-Za-z0-9+/=_-]{64,}/g

/**
 * Reduce anything throwable to `CODE: short technical message`, <= 200 chars.
 * Route EVERY `analysis_last_error` write through this.
 */
export function sanitiseError(err: unknown, code = "UNKNOWN"): string {
  // AggregateError before Error — it IS an Error, and its own `message` is the
  // useless "All promises were rejected" while the three hedge failures we
  // actually want to read are in `.errors`.
  const raw = err instanceof AggregateError
    ? err.errors.map(String).join(" | ")
    : err instanceof Error
    ? `${err.name}: ${err.message}`
    : String(err ?? "")
  const msg = raw
    // A multi-line value is a response BODY, not an error. Keep the first line.
    .split("\n")[0]
    .replace(/\s+/g, " ")
    // Any long unbroken token is a base64 fragment, a data: URI or a JWT — none
    // of which belong in a durable column on a patient's meal.
    .replace(PII_SHAPED, "…")
    .trim()
  return `${code}: ${msg}`.slice(0, 200)
}

// ---------------------------------------------------------------------------
// IDENTIFICATION — image or words -> [{ name, estimated_grams, flags }]
// ---------------------------------------------------------------------------
//
// Moved VERBATIM out of analyze-meal v60. The lean prompt is the result of the
// whole v54-v59 arc: a throwaway probe measured it at 692ms / 75 output tokens
// against the old full prompt at 5163ms / 514, and OUTPUT TOKENS were the cause
// of the 150s hangs. Changing it invalidates every measurement quoted here and
// in the Infomaniak escalation package.
//
// 2026-08-04: the coverage keys were added here. Their measured output-token cost
// against the 75-token baseline is recorded in the spike result,
// docs/prd/2026-08-04-multi-photo-meal-coverage-design.md §11 — 66-81 tokens, i.e.
// no material change, which is why this edit was allowed at all. §12 then showed
// the model reports partial correctly on cropped plates and never on a whole one.
// Any further change to this prompt needs the same treatment — measure, then edit.
const PRODUCT = Deno.env.get("INFOMANIAK_AI_PRODUCT_ID") ?? Deno.env.get("INFOMANIAK_PRODUCT_ID") ?? "108797"
const API_KEY = Deno.env.get("INFOMANIAK_AI_API_KEY")
const TEXT_MODEL = Deno.env.get("SOVEREIGN_CHAT_MODEL") ?? "qwen3"
const VISION_MODEL = Deno.env.get("SOVEREIGN_VISION_MODEL") ?? "google/gemma-4-31B-it"
const BASE = `https://api.infomaniak.com/2/ai/${PRODUCT}/openai/v1`

export const IDENTIFY_CONFIGURED = Boolean(API_KEY)

const SYSTEM = `You are a nutrition vision assistant for a functional-health app.
Your ONLY job is to IDENTIFY what is on the plate and estimate each portion in grams. Do NOT estimate calories, macros or micronutrients — a reference nutrition database prices every item afterwards, so a number from you would only be overwritten.
Goal: a good ESTIMATE of what is on the plate so we can understand how the body reacts to food — NOT clinical precision.
Decompose composite dishes and sauces into base ingredients (e.g. pesto -> basil, pine nuts, parmesan, olive oil, garlic).
Name each item AS EATEN, stating cooked/raw when it changes the food: "cooked brown rice" not "brown rice", "boiled lentils" not "lentils", "cooked pasta" not "pasta". Rice, pasta, legumes and grains roughly TRIPLE in weight when cooked, so the state changes the numbers about threefold.
NEVER output an aggregate placeholder such as "dinner items", "lunch items", "breakfast items", "Total Meal" or "snacks". List the actual foods. If ONE food among several is unclear, give your best guess for that single food — but if the input as a whole shows you nothing identifiable (no image, and a description naming no actual food), return "items":[] rather than inventing a plausible meal. An empty list is correct and useful; an invented meal is not.
Portion hints: dinner plate 400-600g; palm of protein 100-130g; fist of starch 150-200g; thumb of fat 15-20g; handful of nuts 30g.
Respond with STRICT minified JSON only (no markdown, no prose), exactly this shape:
{"dish_name":string,"items":[{"name":string,"estimated_grams":number,"flags":[string]}],"confidence":number,"coverage":"full"|"partial","coverage_note":string}
Also judge whether you can see the whole meal. Use "coverage":"partial" when a plate is cut off by the frame, a container's contents are hidden, or food is clearly out of shot; "full" otherwise. When partial, add "coverage_note": one short phrase naming what you cannot see. Never add items for food you cannot see — report it as missing, do not guess it.
"flags" per item: zero or more of EXACTLY these keys (use [] when none clearly apply; judge the food as prepared, not its category):
- "antiInflammatory": actively calms inflammation (oily fish, olive oil, berries, leafy greens, turmeric, ginger)
- "fiber": meaningful fiber, >=3g for the portion
- "protein": solid protein contribution, >=12g for the portion
- "omega3": rich in omega-3 (oily fish, walnuts, chia, flax)
- "probiotic": live cultures (yogurt, kefir, kimchi, sauerkraut, miso, kombucha)
- "micronutrientDense": exceptional micronutrient density (organ meats, shellfish, eggs, sardines)
- "antioxidant": antioxidant-rich (berries, cacao, green tea, colorful plants)
- "healthyFats": predominantly unsaturated fats (olive oil, avocado, nuts, seeds)
- "boneSupport": notable calcium (dairy, sardines with bones, tofu, kale)
- "hydrating": very high water content (cucumber, melon, soups, broths)
- "inflammatory": pro-inflammatory as prepared (deep-fried, cured/processed meat, refined + sugary)
- "fastSugars": fast glucose hit (sweets, syrups, juices, white bread/rice)
- "sodium": salt-heavy (cured, brined, canned, heavily sauced)
- "ultraProcessed": industrial formulation (nuggets, sodas, instant/packaged snacks)
- "allergen": one of the big allergens is the main ingredient (peanut, shellfish, gluten, sesame)`

function stripFences(s: string): string {
  return s.replace(/^\s*```(?:json)?/i, "").replace(/```\s*$/i, "").trim()
}

export type IdentifyInput = {
  imageBase64?: string
  /** Multi-photo meals — several plates, or one plate framed in pieces. The
   *  single-image field above is the one-element form and still takes priority
   *  for every shipped caller. */
  imageBase64s?: string[]
  imageUrl?: string
  description?: string
  /**
   * Foods and portions the MEMBER stated, structured. When present they go into
   * the prompt AS FACTS and are then ENFORCED on the way out (applyStatedGrams),
   * because a prompt is not a guarantee. Empty/absent on every photo capture and
   * on every shipped client, which is what makes the whole field additive.
   * See `_shared/stated-items.ts` for why this exists.
   */
  statedItems?: StatedItem[]
}
export type IdentifiedItem = { name: string; estimated_grams: number; flags: FoodFlagKey[] }

export type IdentifySuccess = {
  ok: true
  dish_name: string
  items: IdentifiedItem[]
  duplicates_dropped: number
  confidence: number | null
  /** Did the model believe it saw the whole meal? Never null — sanitiseCoverage
   *  fails open to "full", so an older model or a malformed response is silent
   *  rather than nagging. */
  coverage: Coverage
  /** One short phrase naming what it could not see. Null when there is nothing
   *  usable; the nudge card carries its own sentence. */
  coverage_note: string | null
  model: string
  elapsed_ms: number
}

export type IdentifyFailure = {
  ok: false
  /** The EXACT body + status analyze-meal has returned for this failure since
   *  v58, carried out of here rather than rebuilt at the call site so the
   *  response contract cannot drift. May contain model output — it goes to the
   *  CALLER, never to the database. */
  response: { body: Record<string, unknown>; status: number }
  /** Already sanitised, safe for `analysis_last_error`. Built only from status
   *  codes and Error messages — never from `raw`. */
  technical: string
  /** `true` => do not retry: the request itself is wrong and eight more rolls
   *  just burn the budget. A hang, a 5xx or a 429 is transient by definition. */
  permanent: boolean
  elapsed_ms: number
}

export type IdentifyResult = IdentifySuccess | IdentifyFailure

export async function identifyMeal(input: IdentifyInput): Promise<IdentifyResult> {
  const { imageBase64, imageBase64s, imageUrl, description, statedItems } = input
  const stated = statedItems ?? []

  // One image or four, the payload is built in exactly one place. At N=1 it is
  // byte-identical to what has shipped since v56 — locked by identify-parts.test.ts,
  // which matters because every latency and hang figure quoted above was measured
  // against those exact strings.
  const base64s = imageBase64s?.length ? imageBase64s : imageBase64 ? [imageBase64] : []
  const imageUrls = imageUrl
    ? [imageUrl]
    : base64s.slice(0, MAX_IDENTIFY_IMAGES).map((b) => `data:image/jpeg;base64,${b}`)
  const userParts = buildIdentifyUserParts({ description, imageUrls, statedItems: stated })

  const model = imageUrls.length ? VISION_MODEL : TEXT_MODEL

  // RELIABILITY IS PRIORITISED OVER LATENCY here, by explicit decision.
  //
  // The upstream hangs at the connection level on roughly HALF of all attempts.
  // A hang never recovers, but a fresh connection succeeds immediately and a
  // success is fast (~1.2s model). So attempts are HEDGED — fired while the
  // previous is still in flight, first answer wins — rather than sequential,
  // which would add each timeout to the worst case.
  //
  // MEASURED, not assumed. Solving for the per-attempt hang rate p across two
  // different attempt counts is what shows the hangs are INDEPENDENT:
  //
  //   v58, 2 attempts   27.3% fail (16/22)   p = 0.523
  //   v59, 3 attempts   16.0% fail ( 4/25)   p = 0.543
  //
  // p is stable across configurations, and v58's p predicts v59 at 85.7% against
  // 84.0% observed. Correlated hangs would have made the third attempt buy far
  // less than that. So the real curve is ~47/72/85 for 1/2/3 attempts.
  //
  // The cost is real and worth stating: up to 3 concurrent upstream calls, so
  // AI spend rises on the slow fraction. The common case is untouched — when the
  // first attempt answers in ~1.2s the hedges never fire.
  //
  // The 9000ms deadline is deliberately ABOVE the old 6-7s target. A rare 10s
  // wait beats a 16% failure rate for someone photographing a meal.
  //
  // Hedging inside ONE request cannot beat ~85%. The remaining 15% is what the
  // retry worker exists for — see docs/plans/2026-07-29-async-meal-pipeline.md.
  const MODEL_DEADLINE_MS = Number(Deno.env.get("ANALYZE_MEAL_TIMEOUT_MS") ?? "9000")
  const HEDGE_AFTER_MS = Number(Deno.env.get("ANALYZE_MEAL_HEDGE_MS") ?? "1800")
  const HEDGE_2_AFTER_MS = Number(Deno.env.get("ANALYZE_MEAL_HEDGE_2_MS") ?? "3600")

  const payload = {
    model,
    messages: [
      { role: "system", content: SYSTEM },
      { role: "user", content: userParts },
    ],
    temperature: 0.2,
    stream: false,
    // qwen3 quirk (mirrors chatbot-message / generate-periodic-report):
    // disable thinking-mode so the JSON lands in message.content.
    reasoning_effort: "none",
  }

  const startedAt = Date.now()
  // ONE shared wall-clock deadline for both attempts. The hedge does not get its
  // own budget on top — it inherits whatever is left, so the ceiling is
  // MODEL_DEADLINE_MS no matter how many attempts are in flight.
  const deadline = startedAt + MODEL_DEADLINE_MS
  let won = false

  const attempt = async (delayMs: number): Promise<Response> => {
    if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs))
    // The primary already came back — do not add a pointless second call to an
    // upstream that is struggling. (Promise.any has resolved; this rejection is
    // absorbed by the race.)
    if (won) throw new Error(`hedge not needed (+${delayMs}ms)`)
    const remaining = deadline - Date.now()
    if (remaining <= 0) throw new Error(`no budget left for attempt (+${delayMs}ms)`)
    const ac = new AbortController()
    const timer = setTimeout(() => ac.abort(), remaining)
    try {
      const r = await fetch(`${BASE}/chat/completions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: ac.signal,
      })
      // Read the body inside the deadline, so a slow stream cannot outlive it —
      // and so whichever attempt wins the race is FULLY materialised, never a
      // header-only response whose stream is still tied to a dying connection.
      const text = await r.text()
      won = true
      return new Response(text, { status: r.status })
    } finally {
      clearTimeout(timer)
    }
  }

  let resp: Response
  try {
    resp = await Promise.any([attempt(0), attempt(HEDGE_AFTER_MS), attempt(HEDGE_2_AFTER_MS)])
  } catch (e) {
    const elapsed = Date.now() - startedAt
    // An honest, fast, RETRYABLE failure — not a gateway 504 the app cannot
    // interpret. The client can offer "try again" instead of hanging.
    const details = e instanceof AggregateError
      ? e.errors.map((x) => String(x)).join(" | ")
      : String(e)
    return {
      ok: false,
      response: {
        status: 503,
        body: {
          error: "The nutrition model did not respond in time",
          code: "UPSTREAM_TIMEOUT",
          retryable: true,
          elapsed_ms: elapsed,
          details: details.slice(0, 200),
        },
      },
      technical: sanitiseError(details, "UPSTREAM_TIMEOUT"),
      permanent: false,
      elapsed_ms: elapsed,
    }
  }

  const raw = await resp.text()
  if (!resp.ok) {
    // A 4xx that is not 429 means the request itself is wrong. A 5xx or a 429 is
    // transient and worth another dice roll.
    const permanent = resp.status >= 400 && resp.status < 500 && resp.status !== 429
    return {
      ok: false,
      response: { status: 502, body: { error: "Vision model error", status: resp.status, details: raw.slice(0, 500) } },
      // Note what is NOT here: `raw`. The caller gets the body, the database
      // gets the status code.
      technical: sanitiseError(`vision model returned HTTP ${resp.status}`, "UPSTREAM_HTTP"),
      permanent,
      elapsed_ms: Date.now() - startedAt,
    }
  }

  // ⚠ The coverage keys are read off THIS parse and no other. The crop spike
  // (spec §12) found the model fences its JSON on the PARTIAL response while the
  // full-frame control returned bare JSON — so a second parser written for
  // coverage would break partial meals ONLY, leaving full meals green and the
  // nudge silently dead. One stripFences, one JSON.parse, everything downstream.
  let parsed: { dish_name?: string; items?: unknown[]; confidence?: number; coverage?: unknown; coverage_note?: unknown }
  try {
    const msg = JSON.parse(raw)?.choices?.[0]?.message ?? {}
    let content = stripFences(String(msg.content ?? ""))
    if (!content && typeof msg.reasoning === "string") {
      // qwen3 sometimes emits into `reasoning` despite reasoning_effort none.
      const m = msg.reasoning.match(/\{[\s\S]*\}/)
      if (m) content = m[0]
    }
    const decoded: unknown = JSON.parse(content)
    // gemma occasionally returns an ARRAY of dish objects instead of the single
    // object the prompt demands — observed on 1 of 8 real photos in the Phase 5
    // benchmark. Without this branch that meal 502s as PARSE_ERROR, is marked
    // retryable, and re-enters the worker against the SAME model and image at
    // temperature 0.2 — a retry loop whose dice are loaded toward the same
    // wrong shape. Folding the array is strictly better than rejecting it: the
    // items are real, only the envelope is wrong. First dish names the meal;
    // all items are kept (a plate photographed as two dishes is still one meal).
    if (Array.isArray(decoded)) {
      const dishes = decoded as { dish_name?: string; items?: unknown[]; confidence?: number; coverage?: unknown; coverage_note?: unknown }[]
      parsed = {
        dish_name: dishes.map((d) => d?.dish_name).find((n) => typeof n === "string" && n),
        items: dishes.flatMap((d) => (Array.isArray(d?.items) ? d.items : [])),
        confidence: dishes[0]?.confidence,
        // ANY dish reporting partial makes the MEAL partial. A model that split
        // its answer per plate and flagged only the cut-off one is right, and
        // taking dishes[0] would throw that away.
        coverage: dishes.some((d) => sanitiseCoverage(d?.coverage) === "partial") ? "partial" : "full",
        coverage_note: dishes.map((d) => d?.coverage_note).find((n) => typeof n === "string" && n),
      }
    } else {
      parsed = decoded as { dish_name?: string; items?: unknown[]; confidence?: number; coverage?: unknown; coverage_note?: unknown }
    }
  } catch (e) {
    return {
      ok: false,
      response: { status: 502, body: { error: "Could not parse model output", details: String(e), raw: raw.slice(0, 500) } },
      // Unparseable output is a bad roll of the same dice, not a bad request —
      // the identical input parses fine on the next attempt. Retryable.
      technical: sanitiseError(e, "PARSE_ERROR"),
      permanent: false,
      elapsed_ms: Date.now() - startedAt,
    }
  }

  // Zero-gram zero-kcal entries are model artifacts, not food: they render as an
  // empty row in the meal-items UI and would reach the food resolver. Dropped
  // deterministically here, server-side — never relying on the prompt.
  const numeric = (v: unknown): number => {
    const x = typeof v === "string" ? Number(v) : v
    return typeof x === "number" && isFinite(x) ? x : 0
  }
  const hasSubstance = (it: { estimated_grams?: unknown; kcal?: unknown }): boolean =>
    numeric(it?.estimated_grams) > 0 || numeric(it?.kcal) > 0

  // Model flags are untrusted — keep only canonical keys (good-first order),
  // drop the field entirely when none survive (the app falls back to its
  // keyword heuristics for flag-less items).
  const identifiedRaw: IdentifiedItem[] = applyStatedGrams(
    (Array.isArray(parsed.items) ? parsed.items : [])
      .map((it) => it as { name?: unknown; estimated_grams?: unknown; kcal?: unknown; flags?: unknown })
      .filter((it) => it && typeof it.name === "string" && it.name.trim() !== "" && hasSubstance(it))
      .map((it) => ({
        // A portion glued onto the NAME is the exact defect this whole path
        // exists to close, and the model is not the only way it can arrive —
        // so it is stripped deterministically here, for every caller, photo
        // included. "16% fat beef" and "87% Dark Chocolate" are untouched: the
        // pattern needs a number AND a unit AND the end of the string.
        name: stripTrailingQuantity(String(it.name).trim()),
        estimated_grams: numeric(it.estimated_grams),
        flags: sanitizeFlags(it.flags),
      })),
    // BEFORE the duplicate collapse below, never after: that collapse is keyed
    // on (name, grams), so re-writing the grams afterwards could leave two rows
    // that are now identical and were let through as distinct.
    stated,
  )

  // The model nondeterministically repeats an item. Measured on v57: 4 of 11
  // responses listed "olive oil" 20 g twice, and the resolver dutifully priced
  // both — 639 kcal became 816. Same input, same deploy.
  //
  // Only an EXACT (name, grams) repeat is collapsed. Two rows of the same food
  // with DIFFERENT grams are kept, because that is how a real second helping
  // looks and merging them would invent a portion the patient did not eat.
  // Summing the grams of an exact duplicate would be equally wrong: two
  // identical 20 g olive-oil rows are one 20 g pour reported twice, not 40 g.
  const seenIdentity = new Set<string>()
  const items: IdentifiedItem[] = []
  for (const it of identifiedRaw) {
    const key = `${it.name.toLowerCase().replace(/\s+/g, " ").trim()}|${it.estimated_grams}`
    if (seenIdentity.has(key)) continue
    seenIdentity.add(key)
    items.push(it)
  }

  return {
    ok: true,
    dish_name: typeof parsed.dish_name === "string" ? parsed.dish_name : "Meal",
    items,
    duplicates_dropped: identifiedRaw.length - items.length,
    confidence: typeof parsed.confidence === "number" ? parsed.confidence : null,
    coverage: sanitiseCoverage(parsed.coverage),
    coverage_note: sanitiseCoverageNote(parsed.coverage_note),
    model,
    elapsed_ms: Date.now() - startedAt,
  }
}

// ---------------------------------------------------------------------------
// PRICING — identified names -> reference-row numbers
// ---------------------------------------------------------------------------
//
// Every number below this line comes from a reference row, never from the
// model. No external network is involved: the resolver reads our own Postgres
// and the query embedding is produced by `Supabase.ai` INSIDE the Edge Runtime.
// That is why the worker never retries this half — a throw here is a bug, not
// a dice roll.
export type MergedItem = ResolvedItem & { flags?: FoodFlagKey[] }
export type MealTotals = { kcal: number; protein_g: number; carbs_g: number; fat_g: number; fiber_g: number }
export type PricedMeal = {
  items: MergedItem[]
  resolved: ResolvedItem[]
  totals: MealTotals
  micros: Record<string, number | null>
  scores: MealScores
}

/** A fresh object every call — the result is handed straight to JSON.stringify
 *  and to a DB write, and a shared frozen singleton is a footgun waiting for
 *  the first caller that decorates it. */
export function emptyPriced(): PricedMeal {
  return {
    items: [],
    resolved: [],
    totals: { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
    micros: {},
    scores: scoreMeal([]),
  }
}

/**
 * `db` must be able to read the reference plane (`nb_food_items`,
 * `nb_food_aliases`, `match_food_items`, `match_food_products`). Both callers
 * pass a SERVICE-ROLE client for this and this only — reference data is not
 * patient data, and the interactive path has always done it this way. The
 * patient's own row is written with a different, user-scoped client.
 *
 * `patientId` turns on the resolver's TIER 0A — the read half of the correction
 * loop, which prices a name from the row this patient themselves pinned to it.
 *
 * 🚨 IT MUST COME FROM THE MEAL ROW (`nb_meal_logs.patient_id`), NOT A REQUEST.
 * Because `db` is service-role, RLS is not the boundary on that read: this
 * argument is. The interactive caller reads the id under the patient's own JWT,
 * so RLS has already proved they own the row; the worker selects its own work and
 * takes no id from anyone. Omit it and tier 0a never issues a query.
 */
export async function priceMeal(
  db: SupabaseClient,
  identified: IdentifiedItem[],
  patientId: string | null = null,
): Promise<PricedMeal> {
  if (!identified.length) return emptyPriced()

  const session = new Supabase.ai.Session("gte-small")
  const resolved = await resolveItems(
    // The one specifier cast — see the import header.
    db as unknown as ResolverClient,
    session,
    identified.map((it) => ({ name: it.name, grams: it.estimated_grams })),
    patientId,
  )

  // MERGE, by index. The resolver returns items in the order it was given them.
  //   from the RESOLVER: macros, micros, basis, food_item_id, needs_review,
  //                      components — everything numeric, plus its provenance
  //   from the MODEL:    the name the patient's plate was identified as, and the
  //                      per-item flags, which are judgements not measurements
  // `estimated_grams` comes from the resolver too, because it is the portion the
  // macros were actually computed at (roundGrams, the declared precision floor);
  // showing the model's raw grams beside a price computed from a rounded one
  // would put two different portions on the same row.
  const items: MergedItem[] = resolved.map((r, i) => {
    const flags = identified[i]?.flags ?? []
    return {
      ...r,
      name: identified[i]?.name ?? r.name,
      ...(flags.length ? { flags } : {}),
    }
  })

  // Totals EXCLUDE `basis: 'unknown'`. That basis means "this name is not a
  // food" (an aggregate placeholder such as "dinner items"), and a placeholder
  // is not a zero-calorie ingredient — it is not an ingredient. Letting one into
  // the sum would license the caller to treat it as one.
  const priced = items.filter((it) => it.basis !== "unknown")
  const sum = (k: "kcal" | "protein_g" | "carbs_g" | "fat_g" | "fiber_g") =>
    priced.reduce((a, it) => a + (typeof it[k] === "number" ? it[k] : 0), 0)
  const totals: MealTotals = {
    kcal: Math.round(sum("kcal")),
    protein_g: Math.round(sum("protein_g")),
    carbs_g: Math.round(sum("carbs_g")),
    fat_g: Math.round(sum("fat_g")),
    fiber_g: Math.round(sum("fiber_g")),
  }

  // Whole-meal micros = the sum of the per-item micros the resolver returned.
  //
  // A nutrient that is null on EVERY contributing item stays null. "Nobody
  // measured iodine in any of these foods" and "there is no iodine in this meal"
  // are different claims, and collapsing the first into 0 is the fabrication this
  // whole restructure exists to stop. Where at least one item carries a number,
  // the nulls are simply not added — same rule the resolver already uses when it
  // sums a decomposed recipe.
  const micros: Record<string, number | null> = {}
  for (const it of items) {
    for (const [k, v] of Object.entries(it.micros ?? {})) {
      if (v === null) {
        if (!(k in micros)) micros[k] = null
        continue
      }
      micros[k] = (micros[k] ?? 0) + v
    }
  }

  // The rules engine sees the RESOLVED macros, not the model's guesses, so the
  // glycemic/digestion arithmetic runs on reference numbers.
  return { items, resolved, totals, micros, scores: scoreMeal(items) }
}

// ---------------------------------------------------------------------------
// The row writes — one definition, both callers
// ---------------------------------------------------------------------------
//
// The patches live here, not at the call sites, for the same reason the
// resolver was extracted: three copies of "which columns is a finished meal"
// drift, and the way you find out is a clinician looking at a meal whose totals
// and whose scores disagree.
//
// TWO WRITES, NOT N. Names land at `identificationPatch`, prices at
// `completionPatch`. N per-item writes would mean N realtime events, N
// re-renders and N times the write load, for an effect visually identical to a
// client-side stagger over data that has already arrived.

export type MealPatch = Record<string, unknown>

/** WRITE 1 of 2 — what the model saw. Unpriced, status `pricing`.
 *  `analysis_started_at` is refreshed so the 2-minute stale-claim clock covers
 *  the pricing phase rather than counting from before identification. */
export function identificationPatch(ident: IdentifySuccess, now: Date = new Date()): MealPatch {
  return {
    name: ident.dish_name,
    ai_identified_foods: ident.items,
    // WRITE 1, not WRITE 2, and that is the point: coverage is an identification
    // fact, and this write is what the confirm screen's realtime subscription
    // already fires on — so the nudge lands in the same frame as the foods.
    analysis_coverage: ident.coverage,
    coverage_note: ident.coverage_note,
    analysis_status: "pricing",
    analysis_started_at: now.toISOString(),
  }
}

/** WRITE 2 of 2 — every number, then `complete`.
 *  `protocolFlags === null` means no active protocol, and the column is then
 *  left untouched: SQL null = "not computed", `[]` = "computed, meal clean".
 *  That distinction is load-bearing in lib/report/protocol-block.ts. */
export function completionPatch(
  ident: IdentifySuccess,
  priced: PricedMeal,
  attempts: number,
  protocolFlags: ProtocolFlag[] | null,
  now: Date = new Date(),
): MealPatch {
  const basis: Record<string, number> = {}
  for (const r of priced.resolved) basis[r.basis] = (basis[r.basis] ?? 0) + 1
  return {
    ai_identified_foods: priced.items,
    // NOT a duplicate of ai_identified_foods. That column carries the name the
    // patient's plate was identified AS; this one carries the reference row it
    // was priced FROM, with basis / food_item_id / needs_review / components.
    // Keeping both is what lets a clinician see that "Low fat Quark" was priced
    // as peanut flour without having to ask the patient anything.
    resolved_foods: priced.resolved,
    resolution_meta: {
      model: ident.model,
      confidence: ident.confidence,
      duplicates_dropped: ident.duplicates_dropped,
      identify_ms: ident.elapsed_ms,
      attempts,
      basis,
      needs_review: priced.resolved.filter((r) => r.needs_review).length,
      resolved_at: now.toISOString(),
    },
    total_calories: priced.totals.kcal,
    total_protein_g: priced.totals.protein_g,
    total_carbs_g: priced.totals.carbs_g,
    total_fat_g: priced.totals.fat_g,
    total_fiber_g: priced.totals.fiber_g,
    micronutrient_totals: priced.micros,
    inflammation_score: priced.scores.inflammation,
    glycemic_score: priced.scores.glycemic,
    gut_score: priced.scores.digestion,
    ...(protocolFlags !== null ? { protocol_flags: protocolFlags } : {}),
    analysis_status: "complete",
    analysis_last_error: null,
    analysis_next_retry_at: null,
    analysis_started_at: null,
  }
}

/** Something went wrong: back to `queued` with a backoff, or `needs_input` once
 *  the budget is spent. A ninth roll of the same dice is not a plan; asking the
 *  patient is. `opts.permanent` short-circuits straight to the terminal state —
 *  a failure no retry can fix.
 *
 *  ⚠ NOTE WHICH TERMINAL STATE, BECAUSE IT IS A DECISION AND NOT AN OVERSIGHT:
 *  a permanent failure resolves to `needs_input`, NOT to `failed`. This whole
 *  pipeline therefore never writes `failed` at all — five of the six statuses
 *  in the CHECK constraint are reachable from here.
 *
 *  `failed` means "nothing more can happen to this row". That is almost never
 *  true of a meal: the model may be permanently unable to read this photo, but
 *  the PATIENT can still say what they ate, and `needs_input` is the state that
 *  asks. Routing a 400 from the vision model to `failed` would close a door that
 *  is demonstrably still open, and would show the patient an error instead of a
 *  question. `failed` is left for a genuine dead end — a row whose photo is
 *  gone and whose patient cannot be reached — which nothing in this pipeline
 *  can currently detect. */
export function retryLaterPatch(
  reason: unknown,
  attempts: number,
  code: string,
  opts: { permanent?: boolean; now?: Date } = {},
): MealPatch {
  const now = opts.now ?? new Date()
  const exhausted = opts.permanent === true || attempts >= MAX_ATTEMPTS
  return {
    analysis_status: exhausted ? "needs_input" : "queued",
    analysis_last_error: sanitiseError(reason, code),
    analysis_next_retry_at: exhausted ? null : nextRetryAt(attempts, now),
    analysis_started_at: null,
  }
}

/** Identification failed. `ident.technical` is already scrubbed and
 *  sanitiseError inside retryLaterPatch is the second gate —
 *  `ident.response.body` may quote model output and is the one thing that must
 *  never reach this column. */
export function failurePatch(ident: IdentifyFailure, attempts: number, now: Date = new Date()): MealPatch {
  return retryLaterPatch(ident.technical, attempts, "IDENTIFY_FAILED", { permanent: ident.permanent, now })
}

/** Terminal, and deliberately not an error state: this is the point where the
 *  patient — who always knows what they ate — is asked. */
export function needsInputPatch(reason: string, code = "NEEDS_INPUT"): MealPatch {
  return {
    analysis_status: "needs_input",
    analysis_last_error: sanitiseError(reason, code),
    analysis_next_retry_at: null,
    analysis_started_at: null,
  }
}

// `resolved_foods` and `resolution_meta` predate this work — they arrived from
// the CLINICAL repo against the same shared Postgres and nothing in APP has
// ever written them. They are PROVENANCE, not results.
const PROVENANCE_KEYS = ["resolved_foods", "resolution_meta"] as const

// Coverage is the SECOND pair of columns this function may legitimately not find.
// The migration and the deploy are separate events, and one unknown column makes
// PostgREST reject the WHOLE update — which would strand every meal in `pricing`
// rather than merely losing a verdict. Degrading is right; failing is not.
const COVERAGE_KEYS = ["analysis_coverage", "coverage_note"] as const

const DROPPABLE_KEYS = [...PROVENANCE_KEYS, ...COVERAGE_KEYS] as const

// PostgREST reports an unknown column as PGRST204 (schema cache) or 42703
// (Postgres undefined_column).
const UNDEFINED_COLUMN = new Set(["PGRST204", "42703"])

// The non-terminal statuses. `complete`, `needs_input` and `failed` are answers;
// these three are a row still being worked on. Must stay the exact complement of
// `TERMINAL_ANALYSIS_STATUSES` in lib/meal-log/analysis-status.ts.
//
// ⚠ KEEP THIS DECLARATION ON ONE LINE, WITH THE STATUSES AS PLAIN QUOTED
// LITERALS. lib/meal-log/__tests__/analysis-status-mirror.test.ts cannot import
// this module — Node chokes on the `npm:` and `https://esm.sh/` specifiers at
// the top of this file — so it enforces the complement by reading THIS FILE AS
// TEXT, matching /IN_FLIGHT_STATUSES\s*=\s*\[([^\]]*)\]/. Reformatting across
// lines, or building the array from a variable, does not silently weaken that
// guard (it fails rather than passing over an empty set) but it does break the
// build until someone updates the regex. Move it deliberately, not incidentally.
export const IN_FLIGHT_STATUSES = ["queued", "identifying", "pricing"] as const

/**
 * Apply a patch to one meal row. `.eq('id', …)` plus RLS is the protection on
 * the interactive path: a caller cannot reach another patient's row, because an
 * id belonging to someone else simply matches zero rows.
 *
 * Both provenance columns DO exist (jsonb, nullable — verified against
 * information_schema on 2026-07-30). The retry is kept anyway because the
 * CLINICAL repo runs its own migration sequence against this same Postgres and
 * the two sequences already collide, so these columns can move under us without
 * anything in this repo changing. One unknown column makes PostgREST reject the
 * WHOLE update, which would silently cost the meal its totals and strand the row
 * in `pricing`. Losing the provenance is a degradation; losing the numbers is
 * the bug this pipeline was built to stop. Never swallow it quietly: the log
 * line is the whole point.
 *
 * `onlyIfInFlight` guards the DOWNGRADES — the failure and needs_input patches.
 * The interactive call and the worker can legitimately be on the same row at
 * once (that is what the compare-and-set claim is for), and without this a
 * worker whose identification hung would flip a meal the patient already has on
 * screen from `complete` back to `queued`, re-analysing a finished meal and
 * rewriting its numbers. Result writes are deliberately NOT guarded: a result is
 * a result, and both writers converge on the same `complete`.
 *
 * Returns true when the row was written.
 */
export async function writeMealPatch(
  db: SupabaseClient,
  mealLogId: string,
  patch: MealPatch,
  label: string,
  opts: { onlyIfInFlight?: boolean } = {},
): Promise<boolean> {
  const run = (p: MealPatch) => {
    const q = db.from("nb_meal_logs").update(p).eq("id", mealLogId)
    return opts.onlyIfInFlight ? q.in("analysis_status", [...IN_FLIGHT_STATUSES]) : q
  }

  const { error } = await run(patch)
  if (!error) return true

  const hasDroppable = DROPPABLE_KEYS.some((k) => k in patch)
  if (hasDroppable && UNDEFINED_COLUMN.has(error.code ?? "")) {
    console.error(
      `[${label}] an optional column (resolved_foods/resolution_meta/analysis_coverage/coverage_note) does not exist on nb_meal_logs — writing results without it. Fix the schema:`,
      error.message,
    )
    const trimmed: MealPatch = { ...patch }
    for (const k of DROPPABLE_KEYS) delete trimmed[k]
    const { error: retryErr } = await run(trimmed)
    if (!retryErr) return true
    console.error(`[${label}] write failed after dropping optional columns:`, retryErr.message)
    return false
  }

  console.error(`[${label}] write failed:`, error.message)
  return false
}

// ---------------------------------------------------------------------------
// Protocol Lens flags
// ---------------------------------------------------------------------------
//
// Used to be computed client-side in `saveMeal`. Once the row is created at
// capture and filled in by the server, the client no longer holds the item list
// at the moment of the write, so this has to happen here or it silently stops
// happening at all — for a feature whose entire job is to warn a patient on an
// elimination protocol.
//
// null means "no active protocol" -> the caller must NOT write the column
// (SQL null = "not computed"). [] means "protocols active, meal clean". That
// distinction is load-bearing in `lib/report/protocol-block.ts`.
//
// Best-effort by design: a protocol read must NEVER cost a patient their meal
// analysis, so every failure returns null and the analysis proceeds.
export async function computeProtocolFlags(
  db: SupabaseClient,
  patientId: string | null,
  items: { name: string }[],
): Promise<ProtocolFlag[] | null> {
  if (!patientId || !items.length) return null
  try {
    const [p, o] = await Promise.all([
      db.from("nb_patient_protocols")
        .select("protocol_key, strictness, patient_visibility")
        .eq("patient_id", patientId)
        .eq("active", true),
      db.from("nb_protocol_overrides")
        .select("protocol_key, food_term, action, severity")
        .eq("patient_id", patientId),
    ])
    if (p.error) return null
    const protocols = p.data ?? []
    if (!protocols.length) return null
    return matchProtocols(items, protocols, o.error ? [] : (o.data ?? []))
  } catch {
    return null
  }
}
