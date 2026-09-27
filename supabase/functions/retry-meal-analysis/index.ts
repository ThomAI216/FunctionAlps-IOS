// retry-meal-analysis — the per-minute worker that finishes the meals the
// interactive call could not.
//
// THE WHOLE POINT. Infomaniak hangs at the CONNECTION level on ~53% of
// attempts, and those hangs are INDEPENDENT: solving for the per-attempt rate
// across two different hedge configurations gives 0.523 and 0.543 — two
// configurations, one number. Independence is what makes a retry worth
// anything, because it is a genuinely fresh dice roll rather than a repeat of
// the same bad outcome.
//
//   inside ONE request, 3 hedged attempts   ~85%   <- the synchronous ceiling
//   8 attempts spread over an hour          0.53^8 = 0.62% still failing
//
// Whatever survives that goes to `needs_input`, where the patient — who always
// knows what they ate — closes it. That, not a better model, is the 100% tier.
//
// Only IDENTIFICATION is ever re-run. Pricing reads our own Postgres and embeds
// via `Supabase.ai.Session('gte-small')` inside this runtime, touching no
// external network, so it has no failure mode worth a second roll.
//
// ⚠ DEPLOY WITH --no-verify-jwt.
//   pg_cron sends `x-report-secret` and carries NO Authorization header, so JWT
//   verification would reject every invocation with a 401 that reads like a
//   configuration problem for hours. A SUPABASE_ANON_KEY client cannot verify
//   JWTs on this project either. Authentication here is the shared secret
//   checked below, and nothing else.
//     supabase functions deploy retry-meal-analysis --no-verify-jwt \
//       --project-ref ndojytvvlvlbgtodujkf
//
// ⚠ SERVICE ROLE, deliberately.
//   The worker has no user JWT so it cannot write through RLS. What keeps that
//   safe is that it never accepts a row id from anybody: it SELECTS its own work
//   by `analysis_status` and schedule. There is no input a caller could use to
//   steer it at a particular patient's row, and every query it runs is
//   constrained to in-flight statuses, so the ~all-`complete` back catalogue is
//   unreachable from here.
import { createServiceRoleClient } from "../_shared/meals/supabase.ts"
import {
  CLAIM_STALE_MS,
  completionPatch,
  computeProtocolFlags,
  failurePatch,
  identificationPatch,
  identifyMeal,
  IDENTIFY_CONFIGURED,
  IDENTIFY_NOT_CONFIGURED,
  MAX_ATTEMPTS,
  needsInputPatch,
  priceMeal,
  retryLaterPatch,
  sanitiseError,
  staleClaimExhausted,
  writeMealPatch,
} from "../_shared/meals/meal-analysis.ts"
import { bytesToBase64, photoPathsFor } from "../_shared/meals/identify-parts.ts"

const SECRET = Deno.env.get("REPORT_SECRET") ?? ""

// The private bucket meal photos live in. `lib/meal-log/upload-photo.ts` writes
// `<authUid>/<ts>.jpg` into it and stores that PATH — not a URL — on
// `nb_meal_logs.photo_url`.
const BUCKET = Deno.env.get("MEAL_PHOTO_BUCKET") ?? "meal-images"

// How many rows one tick may look at. The cron fires again in 60 s, so a large
// number buys nothing except a killed isolate mid-batch.
const BATCH = 20

// ...which is why the batch is also bounded by a WALL CLOCK. Each identification
// can ride a 9 s deadline, so 20 of them is 180 s against a runtime that will
// not grant it. Rows are claimed one at a time, immediately before being worked,
// so stopping early leaves the remainder unclaimed and untouched for the next
// tick — no cleanup, no stranded `identifying` rows.
const BUDGET_MS = Number(Deno.env.get("RETRY_WORKER_BUDGET_MS") ?? "100000")

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } })

// Compare the secret without leaking WHERE it first differs. Length is compared
// first and does leak, which is immaterial for a shared secret of fixed length.
function secretMatches(provided: string | null): boolean {
  if (!SECRET || !provided) return false
  const a = new TextEncoder().encode(SECRET)
  const b = new TextEncoder().encode(provided)
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}

type Row = {
  id: string
  patient_id: string | null
  name: string | null
  source: string | null
  photo_url: string | null
  photo_urls: string[] | null
  logged_at: string | null
  analysis_status: string
  analysis_attempts: number | null
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null)
  // FAIL-CLOSED: no secret configured is a refusal, not an open door.
  if (!secretMatches(req.headers.get("x-report-secret"))) return json({ error: "unauthorized" }, 401)
  if (!IDENTIFY_CONFIGURED) return json({ error: IDENTIFY_NOT_CONFIGURED }, 500)

  const db = createServiceRoleClient()
  const startedAt = Date.now()
  const now = new Date()
  const staleBefore = new Date(now.getTime() - CLAIM_STALE_MS).toISOString()

  // Two kinds of work, one pass.
  //
  //  (a) DUE RETRIES — `queued` whose backoff has elapsed. `analysis_next_retry_at
  //      is null` is included because a row created at capture has never been
  //      attempted and therefore has no schedule; without that clause a meal
  //      whose interactive call never even started would sit queued forever.
  //
  //  (b) STALE CLAIMS — `identifying`/`pricing` claimed more than two minutes
  //      ago. A browser tab that backgrounded or closed mid-request leaves a row
  //      stranded exactly like a killed isolate does, and this is the only thing
  //      that unsticks either. Without it one dead request means a patient
  //      watching a spinner that never resolves, with nothing in the logs.
  //
  // The attempt bound applies to (a) only, as specified: a stale claim has
  // already had its attempt counted at claim time, and refusing to unstick it
  // would leave the row in a non-terminal state with nobody coming.
  //
  // Timestamps are double-quoted inside the filter string because a PostgREST
  // value runs to the next comma or paren and an ISO stamp contains neither —
  // but quoting is the documented way to stop that being a coincidence.
  const { data: rows, error: pickErr } = await db
    .from("nb_meal_logs")
    .select("id, patient_id, name, source, photo_url, photo_urls, logged_at, analysis_status, analysis_attempts")
    .or(
      `and(analysis_status.eq.queued,analysis_attempts.lt.${MAX_ATTEMPTS},` +
        `or(analysis_next_retry_at.is.null,analysis_next_retry_at.lte."${now.toISOString()}")),` +
        `and(analysis_status.in.(identifying,pricing),analysis_started_at.lte."${staleBefore}")`,
    )
    .order("logged_at", { ascending: true })
    .limit(BATCH)

  if (pickErr) {
    console.error("[retry-meal-analysis] could not pick work:", pickErr.message)
    return json({ error: pickErr.message }, 500)
  }

  let claimed = 0, succeeded = 0, failed = 0, needs_input = 0

  for (const raw of (rows ?? []) as Row[]) {
    if (Date.now() - startedAt > BUDGET_MS) {
      console.log(`[retry-meal-analysis] budget spent, leaving the rest for the next tick`)
      break
    }

    // NOT READY YET, which is different from broken. The client creates the row
    // first, THEN uploads the photo, THEN patches photo_url, THEN invokes
    // analyze-meal. A young photo row whose photo_url has not landed is a race
    // with an upload that is seconds away — asking the patient what they ate
    // about a photo they successfully took would be absurd. Skipped BEFORE the
    // claim, so no attempt is spent and the next tick simply finds it again.
    //
    // Bounded by the same two minutes as a stale claim: past that the upload did
    // not merely lag, it failed, and the row falls through to the honest
    // no-usable-input branch below.
    const ageMs = raw.logged_at ? Date.now() - new Date(raw.logged_at).getTime() : Infinity
    // The same one function analyze-meal uses — the "never concatenate the two
    // columns" rule lives in exactly one place and is unit-tested there.
    const photoPaths = photoPathsFor(raw)
    if (!photoPaths.length && raw.source === "photo" && ageMs < CLAIM_STALE_MS) {
      console.log(`[retry-meal-analysis] ${raw.id} photo still uploading, leaving it`)
      continue
    }

    // A stale claim that has already spent the whole budget: the isolate died on
    // it every time, so another attempt would die the same way. Ask the member.
    if (staleClaimExhausted(raw)) {
      await writeMealPatch(
        db,
        raw.id,
        needsInputPatch("analysis stopped before finishing on every attempt", "ATTEMPTS_EXHAUSTED"),
        "retry:stale-exhausted",
        { onlyIfInFlight: true },
      )
      needs_input++
      console.log(`[retry-meal-analysis] ${raw.id} stale after ${raw.analysis_attempts}/${MAX_ATTEMPTS} attempts -> needs_input`)
      continue
    }

    const attempts = (raw.analysis_attempts ?? 0) + 1

    // Compare-and-set claim, on BOTH the status we saw and the attempt count we
    // read. If the interactive call or another tick grabbed this row in the
    // microseconds since the SELECT, zero rows match and we skip — no double
    // analysis, no lock table. The increment rides along, so an attempt is
    // counted on ENTRY: a row that kills the isolate every time still burns its
    // budget and reaches needs_input instead of retrying forever.
    const { data: got } = await db
      .from("nb_meal_logs")
      .update({
        analysis_status: "identifying",
        analysis_started_at: new Date().toISOString(),
        analysis_attempts: attempts,
      })
      .eq("id", raw.id)
      .eq("analysis_status", raw.analysis_status)
      .eq("analysis_attempts", raw.analysis_attempts ?? 0)
      .select("id")
    if (!got?.length) {
      console.log(`[retry-meal-analysis] ${raw.id} contended, skipped`)
      continue
    }
    claimed++

    // Rebuild the model input from what the row already carries.
    //
    // A photo meal needs the bytes back out of the private bucket. The `name`
    // fallback is for a row that ALREADY got past identification once and then
    // stalled — a stale `pricing` claim — because by then WRITE 1 has put the
    // AI's dish name there and re-identifying from it is AI voice in, AI voice
    // out.
    //
    // ⚠ THIS COMMENT USED TO SAY THIS FUNCTION HAS NO TEXT/VOICE RETRY. IT DOES.
    // See ~40 lines down: `input = { description: raw.name.trim() }`. The claim
    // was true when written and false by the time it shipped, and it is left
    // here corrected rather than deleted because it very nearly caused someone
    // to "restore" the behaviour it described.
    //
    // What changed: `buildPendingMealRow` now writes the patient's words into
    // `name` at capture (capped, lib/meal-log/save-meal.ts). Without that, a
    // text or voice meal whose FIRST identification failed had nothing on the
    // row and went straight to needs_input — a large minority of meals on this
    // database have no photo to fall back on, so that was not an edge case.
    // Verified end-to-end 2026-07-30: a queued text meal reached `complete` off
    // `name` alone.
    //
    // The objection the old comment raised was real: `name` is the AI's dish
    // name, `patient_note` is the patient's voice, and merging them is the
    // invariant behind docs/wiki/pages/lessons/patient-voice-vs-ai-voice. What
    // resolves it is that the write is TRANSIENT — the words occupy `name` only
    // until identification succeeds, then the model's dish name overwrites them,
    // and `patient_note` is never touched. The alternative was a third prose
    // column on a row that already has two, with no retention rule.
    //
    // The one subtlety worth keeping: re-identifying from `name` AFTER write 1
    // is AI voice in, AI voice out. That is harmless here — a stale `pricing`
    // claim already has its items, and only pricing is missing — but it means
    // `name` is a reliable retry input only while it still holds what the
    // patient said.
    //
    // Client budgets still complement this rather than duplicate it: text/voice
    // keeps all 3 hedged client attempts (lib/meal-log/analyze.ts, locked by
    // analyze-attempts.test.ts) because the first identification is the window
    // the client owns; the worker owns everything after.
    let input: { imageBase64s?: string[]; description?: string } | null = null
    if (photoPaths.length) {
      const images: string[] = []
      let downloadFailed = false
      for (const path of photoPaths) {
        const { data: blob, error: dlErr } = await db.storage.from(BUCKET).download(path)
        if (dlErr || !blob) {
          // ALL OR NOTHING, on purpose. Identifying a three-plate dinner from the
          // two plates that happened to download would file a confidently
          // under-counted meal — the exact failure this whole arc exists to stop.
          //
          // A storage read that fails is a HICCUP, not a missing photo — the object
          // is still there and the next tick will very likely get it. Terminal
          // needs_input on the first blip would ask a patient to re-describe a meal
          // we can still see.
          //
          // The path is deliberately kept OUT of the row: it is `<authUid>/<ts>.jpg`
          // and a uuid is short enough to survive sanitiseError's long-token strip.
          // Operator logs get it; `analysis_last_error` gets a code.
          await writeMealPatch(
            db,
            raw.id,
            retryLaterPatch("photo download failed", attempts, "PHOTO_DOWNLOAD"),
            "retry:photo-download",
            { onlyIfInFlight: true },
          )
          failed++
          console.log(`[retry-meal-analysis] ${raw.id} photo download failed for ${path}: ${dlErr?.message ?? "empty object"}`)
          downloadFailed = true
          break
        }
        images.push(bytesToBase64(new Uint8Array(await blob.arrayBuffer())))
      }
      if (downloadFailed) continue
      input = { imageBase64s: images }
    } else if (raw.name && raw.name.trim()) {
      input = { description: raw.name.trim() }
    }

    // Nothing to analyse AND nothing coming: no photo path on the row at all, and
    // no words. That is PERMANENT — no retry conjures a meal back — so it goes
    // straight to needs_input rather than spending eight attempts on nothing.
    if (!input) {
      await writeMealPatch(
        db,
        raw.id,
        needsInputPatch("row has neither a photo nor a description", "NO_INPUT"),
        "retry:no-input",
        { onlyIfInFlight: true },
      )
      needs_input++
      console.log(`[retry-meal-analysis] ${raw.id} needs_input (no usable input)`)
      continue
    }

    const ident = await identifyMeal(input)

    if (!ident.ok) {
      const patch = failurePatch(ident, attempts)
      await writeMealPatch(db, raw.id, patch, "retry:failure", { onlyIfInFlight: true })
      if (patch.analysis_status === "needs_input") needs_input++
      else failed++
      console.log(
        `[retry-meal-analysis] ${raw.id} attempt ${attempts}/${MAX_ATTEMPTS} -> ${patch.analysis_status} ` +
          `(${ident.elapsed_ms}ms) ${sanitiseError(ident.technical, "IDENTIFY_FAILED")}`,
      )
      continue
    }

    // Same terminal call the interactive path makes: an empty list is the prompt
    // working as designed, and filing a 0 kcal meal as `complete` would be the
    // silent zero rather than the question.
    if (!ident.items.length) {
      await writeMealPatch(
        db,
        raw.id,
        needsInputPatch("model identified no food in this input", "NO_FOOD_IDENTIFIED"),
        "retry:no-food",
        { onlyIfInFlight: true },
      )
      needs_input++
      console.log(`[retry-meal-analysis] ${raw.id} needs_input (no food identified)`)
      continue
    }

    // WRITE 1 of 2 — identification. The same two-write shape analyze-meal uses,
    // from the same builder, so a patient watching the row sees exactly the same
    // sequence whether the interactive call or the worker did the work.
    await writeMealPatch(db, raw.id, identificationPatch(ident), "retry:identification")

    let priced
    try {
      // `raw.patient_id` came off the row this worker SELECTED for itself by
      // status and schedule — there is no request input anywhere in that path, so
      // it cannot be steered at another patient. It scopes the resolver's tier 0a
      // to this patient's learned foods; see the invariant on resolveItems.
      priced = await priceMeal(db, ident.items, raw.patient_id)
    } catch (e) {
      // Pricing has no external dependency, so this is a bug, not a bad roll.
      // The row is left in `pricing` on purpose: the stale-claim branch above
      // reclaims it in two minutes and the log line says why.
      console.error(`[retry-meal-analysis] ${raw.id} resolver threw:`, sanitiseError(e, "RESOLVER"))
      failed++
      continue
    }

    const protocolFlags = await computeProtocolFlags(db, raw.patient_id, priced.items)

    // WRITE 2 of 2 — prices, totals, scores, complete.
    await writeMealPatch(db, raw.id, completionPatch(ident, priced, attempts, protocolFlags), "retry:completion")
    succeeded++
    console.log(
      `[retry-meal-analysis] ${raw.id} complete on attempt ${attempts} ` +
        `(${ident.items.length} items, ${priced.totals.kcal} kcal, ${ident.elapsed_ms}ms)`,
    )
  }

  const summary = { claimed, succeeded, failed, needs_input }
  console.log(`[retry-meal-analysis] tick done in ${Date.now() - startedAt}ms:`, JSON.stringify(summary))
  return json(summary)
})
