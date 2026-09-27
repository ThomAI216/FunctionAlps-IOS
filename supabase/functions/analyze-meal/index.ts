// analyze-meal — the model IDENTIFIES, the resolver PRICES.
//
// v56 split a job that used to be one model call in two:
//
//   Infomaniak (Geneva) sovereign AI  ->  what is on the plate, in grams, and
//                                          the per-item judgement flags
//   _shared/food-resolver.ts          ->  every number, from CIQUAL / SR Legacy
//                                          / Open Food Facts reference rows
//
// WHY. Until v55 the prompt asked the vision model for each item's macros AND a
// 22-field micronutrient block: 500+ output tokens, measured as the cause of the
// 5-8 s latency and the hangs. A names+grams-only probe came back in 692-1163 ms
// with 75-84 output tokens. The macros were never the model's to give anyway —
// a language model asked for "iodine in mcg" produces a plausible number, not a
// measurement, and the resolver has 10,978 real reference rows sitting behind an
// RPC.
//
// Both halves now live in `../_shared/meal-analysis.ts`, shared verbatim with
// `retry-meal-analysis` so the interactive path and the cron path cannot drift.
//
// v61 adds LIFECYCLE WRITES, and `mealLogId` being OPTIONAL is the entire
// rollout strategy:
//
//   mealLogId ABSENT   exactly today's behaviour. Same response, no database
//                      access, no client constructed. The shipped app still
//                      calls it this way and must not break.
//   mealLogId PRESENT  the same response, plus the row is driven through
//                      identifying -> pricing -> complete (or back to queued
//                      with a backoff, for the worker to finish).
//
// De-identified: only the image/description leaves; never a name.
// North-star: a good ESTIMATE to mirror how the body reacts — not clinical precision.
import { createServiceRoleClient, createUserScopedClient } from "../_shared/meals/supabase.ts"
import {
  completionPatch,
  computeProtocolFlags,
  emptyPriced,
  failurePatch,
  identificationPatch,
  identifyMeal,
  IDENTIFY_CONFIGURED,
  needsInputPatch,
  priceMeal,
  writeMealPatch,
  type PricedMeal,
} from "../_shared/meals/meal-analysis.ts"
import { bytesToBase64, photoPathsFor } from "../_shared/meals/identify-parts.ts"
import { sanitiseStatedItems } from "../_shared/meals/stated-items.ts"

// Same bucket the client uploads to and the retry worker reads from.
const PHOTO_BUCKET = Deno.env.get("MEAL_PHOTO_BUCKET") ?? "meal-images"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

// WHY the caller's JWT and not the service role, for every write below:
//
// This app's entire security boundary is own-rows RLS — there is no service key
// anywhere in the client, and `patient_id` is resolved through ensurePatientId
// rather than trusted from a request. If this function wrote with the service
// role, a bug in mealLogId validation would let any authenticated caller
// overwrite any patient's meal. Writing as the caller means Postgres enforces
// the boundary for us: `.eq('id', mealLogId)` against a row belonging to someone
// else matches zero rows, and every update is a silent no-op.
//
// The cost is that this path cannot serve the cron worker, which has no user
// JWT. That is deliberate — the worker has its own function, and reaching
// identification through THIS one over HTTP would force it to --no-verify-jwt
// and turn the app's most expensive AI call into an unauthenticated endpoint.
//
// The service-role client further down is a DIFFERENT thing and touches no
// patient row: the resolver reads the reference plane (nb_food_items,
// nb_food_aliases, match_food_items, match_food_products), which is not patient
// data and has always been read that way.

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (!IDENTIFY_CONFIGURED) return json({ error: "INFOMANIAK_AI_API_KEY not configured in Supabase secrets" }, 500)

  let body: {
    imageBase64?: string
    imageBase64s?: string[]
    imageUrl?: string
    description?: string
    /**
     * ADDITIVE, 2026-08-21. The foods and portions the MEMBER stated, structured
     * — `[{ name, grams, volume_measure? }]`. `description` keeps working
     * unchanged and is what the photo flow and every shipped client still send;
     * this is the voice flow's way of saying a quantity WITHOUT flattening it
     * into prose the model has to re-parse. See `_shared/stated-items.ts`.
     */
    items?: unknown
    mealType?: string
    mealLogId?: string
    /** Patient-initiated do-over: re-read this row's photos from storage and
     *  start the attempt budget again. */
    reanalyze?: boolean
  }
  try {
    body = await req.json()
  } catch {
    return json({ error: "Invalid JSON" }, 400)
  }
  const { imageBase64, imageBase64s, imageUrl, description, mealLogId, reanalyze } = body
  // Validated at the boundary, never trusted: names are trimmed and stripped of
  // a glued-on portion, grams must be a positive number, and the list is capped.
  const statedItems = sanitiseStatedItems(body.items)
  // A re-analysis carries no image bytes at all — the photos are already in the
  // bucket and the server re-reads them below. Requiring the client to re-upload
  // them is what would make meal-detail impossible: three days later there is no
  // base64 anywhere in that browser.
  const hasInlineInput = Boolean(imageBase64 || imageBase64s?.length || imageUrl || description || statedItems.length)
  if (!hasInlineInput && !(reanalyze && mealLogId)) {
    return json({ error: "imageBase64, imageBase64s, imageUrl, description or items required" }, 400)
  }

  // Built ONCE, and only when there is a row to write. Without a mealLogId this
  // function never constructs a client and never touches the database — which is
  // exactly what makes the rollout safe for the currently shipped app.
  const db = mealLogId ? createUserScopedClient(req) : null

  // ── 1. CLAIM ──────────────────────────────────────────────────────────────
  //
  // The attempt is counted HERE, at claim time, not on failure. A row whose
  // input kills the isolate every time would otherwise never report a failure,
  // never increment, and retry forever. Counting on entry means an
  // identification costs a life whether or not anyone survives to write it down.
  //
  // PostgREST cannot express `attempts = attempts + 1`, so this is a read then a
  // compare-and-set on the value read. If the worker claimed the same row in the
  // gap, the update matches zero rows and `claimed` stays false: we still run the
  // analysis and still write the RESULT — a result is a result, and both writers
  // converge on the same `complete` — but we leave the schedule bookkeeping to
  // whoever owns it, so the attempt is never double-counted.
  //
  // `patient_id` is read on the SAME select, and this is the only place it may
  // come from. It turns on the resolver's tier 0a (this patient's own learned
  // foods) and it later drives Protocol Lens. The read runs under the CALLER'S
  // JWT, so own-rows RLS has already proved they own this meal — a mealLogId
  // belonging to someone else matches zero rows and the id stays null, which
  // makes tier 0a a no-op rather than a cross-patient read. It must NEVER be
  // taken from the request body; see the invariant on resolveItems.
  let attempts = 0
  let claimed = false
  let patientId: string | null = null
  let storedPhotos: string[] = []
  if (db && mealLogId) {
    const { data: row } = await db
      .from("nb_meal_logs")
      .select("analysis_attempts, patient_id, photo_url, photo_urls")
      .eq("id", mealLogId)
      .maybeSingle()
    const prior = (row?.analysis_attempts as number | null) ?? 0
    // A patient-initiated re-analysis is a NEW question, not a continuation. A
    // meal that burned four attempts on its first life would otherwise get a
    // stub of a retry budget for its second.
    attempts = reanalyze ? 1 : prior + 1
    patientId = (row?.patient_id as string | null) ?? null
    storedPhotos = photoPathsFor({
      photo_url: row?.photo_url as string | null,
      photo_urls: row?.photo_urls as string[] | null,
    })
    const { data: got } = await db
      .from("nb_meal_logs")
      .update({
        analysis_status: "identifying",
        analysis_started_at: new Date().toISOString(),
        analysis_attempts: attempts,
      })
      .eq("id", mealLogId)
      // Compare-and-set on the value READ, not on `attempts` — those differ on a
      // re-analysis and using the wrong one would make every re-analysis lose the
      // claim to itself.
      .eq("analysis_attempts", prior)
      .select("id")
    claimed = Boolean(got?.length)
  }

  // ── 1b. RE-ANALYSIS INPUT ─────────────────────────────────────────────────
  //
  // Downloaded under the CALLER'S JWT, exactly like every other read on this
  // path: bucket RLS keys the folder on auth.uid(), so someone else's meal is a
  // 404 rather than a leak. The retry worker does the same thing with the service
  // role in its own function — this is the interactive twin of that, not a copy
  // of the pipeline.
  const reanalyzeImages: string[] = []
  if (db && mealLogId && reanalyze && storedPhotos.length) {
    for (const path of storedPhotos) {
      const { data: blob, error: dlErr } = await db.storage.from(PHOTO_BUCKET).download(path)
      if (dlErr || !blob) {
        // ALL OR NOTHING. Re-analysing a complete meal from a subset of its
        // photos would overwrite good numbers with worse ones and look like the
        // model changing its mind. Leave the row for the stale-claim sweep.
        return json({ error: "Could not re-read this meal's photos", retryable: true }, 503)
      }
      reanalyzeImages.push(bytesToBase64(new Uint8Array(await blob.arrayBuffer())))
    }
  }

  // ── 2. IDENTIFY (hedged, 3 attempts, one shared 9 s deadline) ─────────────
  const ident = await identifyMeal({
    imageBase64,
    imageBase64s: reanalyzeImages.length ? reanalyzeImages : imageBase64s,
    imageUrl,
    description,
    statedItems,
  })

  // ── 6. IDENTIFICATION FAILED ──────────────────────────────────────────────
  if (!ident.ok) {
    if (db && mealLogId && claimed) {
      await writeMealPatch(db, mealLogId, failurePatch(ident, attempts), "analyze-meal:failure", {
        onlyIfInFlight: true,
      })
    }
    // The response contract is UNCHANGED: the same 503 UPSTREAM_TIMEOUT
    // (retryable: true) and 502 bodies this function has returned since v58,
    // carried out of identifyMeal rather than rebuilt here so they cannot drift.
    return json(ident.response.body, ident.response.status)
  }

  // An empty identification is the prompt working as designed — "an empty list is
  // correct and useful; an invented meal is not". The input showed nothing
  // identifiable, and no number of retries conjures food into a photo of a table,
  // so this is terminal. `needs_input` ASKS; `complete` would file a 0 kcal meal
  // as finished, which is precisely the silent zero this pipeline exists to stop.
  // The response body is untouched either way.
  if (db && mealLogId && claimed && !ident.items.length) {
    await writeMealPatch(
      db,
      mealLogId,
      needsInputPatch("model identified no food in this input", "NO_FOOD_IDENTIFIED"),
      "analyze-meal:no-food",
      { onlyIfInFlight: true },
    )
  }

  // ── 3. WRITE 1 of 2 — identification ──────────────────────────────────────
  //
  // Names and grams land NOW, unpriced, and the row flips to `pricing`. The
  // patient's realtime subscription fires here, so the confirm screen can show
  // WHAT it saw while the numbers are still being fetched — which is most of the
  // perceived speed.
  if (db && mealLogId && ident.items.length) {
    await writeMealPatch(db, mealLogId, identificationPatch(ident), "analyze-meal:identification")
  }

  // ── 4. PRICE ──────────────────────────────────────────────────────────────
  //
  // Every number below this line comes from a reference row, never from the
  // model. An empty identification skips the resolver entirely rather than paying
  // for a client and an embedding session it would not use.
  let priced: PricedMeal = emptyPriced()
  if (ident.items.length) {
    if (!Deno.env.get("SUPABASE_URL") || !Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) {
      return json({ error: "server misconfigured: SUPABASE_SERVICE_ROLE_KEY missing" }, 500)
    }
    try {
      // The service-role client reads the reference plane, as it always has.
      // `patientId` is what scopes tier 0a to this patient's own pantry — it came
      // off the meal row under the caller's JWT above, never off the request.
      priced = await priceMeal(createServiceRoleClient(), ident.items, patientId)
    } catch (e) {
      // Pricing touches no external network — it reads our own Postgres and
      // embeds inside this runtime. A throw here is a BUG, not a dice roll, so
      // the row is deliberately left in `pricing`: the worker's stale-claim sweep
      // reclaims it two minutes from now, and someone gets a log line instead of
      // a meal stuck forever with nothing to explain it.
      return json({ error: "Food resolver failed", details: String(e).slice(0, 300) }, 502)
    }
  }

  // ── 5. WRITE 2 of 2 — prices, totals, scores, complete ────────────────────
  if (db && mealLogId && ident.items.length) {
    // Protocol Lens. Read under the caller's JWT like everything else here: the
    // own-rows policy on nb_patient_protocols is what makes patient_id safe to
    // take from the row rather than re-derive. The id is the one already read at
    // claim time — a second identical select bought nothing but a round trip.
    const protocolFlags = await computeProtocolFlags(db, patientId, priced.items)

    // A failed write is NOT a failed analysis — the patient still gets their meal
    // on screen from the response body. The row stays in `pricing` and the worker
    // finishes it. Never turn a display success into an error page.
    await writeMealPatch(
      db,
      mealLogId,
      completionPatch(ident, priced, attempts, protocolFlags),
      "analyze-meal:completion",
    )
  }

  // The response is byte-identical whether or not mealLogId was supplied. Every
  // key here is validated by `lib/meal-log/normalize-analysis.ts`; losing one
  // makes `checkedAnalysis` null every response and the confirm screen falls back
  // to the labelled sample for every meal.
  return json({
    dish_name: ident.dish_name,
    items: priced.items,
    totals: priced.totals,
    micros: priced.micros,
    scores: priced.scores,
    duplicates_dropped: ident.duplicates_dropped,
    confidence: ident.confidence,
    // ADDITIVE, 2026-08-04. The row is the nudge's source of truth — confirm
    // gates on the watched row, not on this body — but normalizeMealAnalysis
    // reads these two keys at the client boundary, and a field the client parses
    // that the server never sends is a contract that quietly lies: it would
    // report `full` for every meal forever. Older clients ignore unknown keys.
    coverage: ident.coverage,
    coverage_note: ident.coverage_note,
    model: ident.model,
  })
})
