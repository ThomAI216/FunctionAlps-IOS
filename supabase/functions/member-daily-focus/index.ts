// member-daily-focus — Today's focus for the signed-in member.
//
// POST { recompute?: boolean, locale?: "en" | "fr" }  →  { day, needsCheckin, offers: [...], readiness }
//
// Reads what the morning already holds (sleep score, day_intent, day_priority), today's readiness exactly as
// Trends computes it (`recoveryScore` over the wearable row and the 42-day HRV baseline), the practice's state
// responses and habit library — and hands them to `_shared/focus/engine.ts`, which decides. This file only
// loads and stores.
//
// THE DAY HOLDS STILL. The first call after the morning check-in computes the day and stores it in
// `habit_offers`; every later call reads it back, so a ring syncing at 09:30 never reshuffles the focus.
// `recompute: true` (the app sends it right after the morning check-in is saved or edited) recomputes and
// retires what changed — `superseded`, never deleted: members hold no DELETE policy there, and a retired
// offer is still a true record of what was put in front of them. Anything the member accepted or completed
// survives every recomputation.
//
// THE DAY'S BAND HOLDS STILL TOO. The readiness band the engine decided on (low · mid · high) is stored in
// `patient_day_state` with the offers and read back with them, so the habits' faces on the phone (gentler on a
// low day, a step further on a high one) come from the same read of the day as the focus — never from a ring
// that synced later.
//
// LANGUAGE. The day is stored in English and French side by side (the practice's `*_fr` texts, null = not
// translated yet); `locale` only chooses which one this read returns — see `_shared/focus/present.ts`.
//
// Everything runs under the MEMBER's session (createUserScopedClient): RLS decides what is read and written,
// exactly as if the app had made each call itself. No service role.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createUserScopedClient } from "../_shared/supabase.ts"
import { loadWearableInputs } from "../_shared/scoring/wearable-inputs.ts"
import { recoveryScore } from "../member-scores/engine/health/recovery-score.ts"
import { type BankHabit, decideFocus, type StateOffer, type StateResponse } from "../_shared/focus/engine.ts"
import { contentLocale, dayReadiness, type DayStateRow, OFFER_COLUMNS, type OfferRow, present } from "../_shared/focus/present.ts"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

/** A personal HRV baseline needs this many days before "below your usual" means anything (member-scores' gate). */
const MIN_HRV_BASELINE_DAYS = 14

const num = (v: unknown): number | null => (typeof v === "number" ? v : v != null && !Number.isNaN(Number(v)) ? Number(v) : null)
const keys = (pills: unknown, group: string): string[] => {
  const v = (pills as Record<string, unknown> | null)?.[group]
  return Array.isArray(v) ? v.filter((k): k is string => typeof k === "string") : []
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "POST only" }, 405)

  let body: { recompute?: boolean; locale?: string } = {}
  try { body = await req.json() } catch { /* empty body is fine */ }
  // The app's own word first; builds from before it sent one still carry the Accept-Language iOS adds itself.
  const locale = contentLocale(body.locale ?? req.headers.get("accept-language"))

  const db = createUserScopedClient(req)
  const { data: patientId, error: pidErr } = await db.rpc("current_member_patient_id")
  if (pidErr) return json({ error: pidErr.message }, 401)
  if (!patientId) return json({ error: "No patient profile for this account" }, 404)

  // The member's own day — the same one the check-in RPC and the habit_offers update policy use.
  const { data: day, error: dayErr } = await db.rpc("patient_local_today", { p_patient: patientId })
  if (dayErr || !day) return json({ error: dayErr?.message ?? "no local day" }, 500)
  const today = String(day)

  const readToday = async (): Promise<OfferRow[]> => {
    const { data, error } = await db.from("habit_offers").select(OFFER_COLUMNS)
      .eq("patient_id", patientId).eq("offered_on", today)
    if (error) throw error
    return (data ?? []) as unknown as OfferRow[]
  }
  const readDayState = async (): Promise<DayStateRow | null> => {
    const { data, error } = await db.from("patient_day_state").select("readiness_band,readiness_vs_baseline,band_source")
      .eq("patient_id", patientId).eq("day", today).maybeSingle()
    if (error) throw error
    return (data ?? null) as DayStateRow | null
  }

  try {
    const rows = await readToday()
    const current = rows.filter((r) => !r.superseded)
    if (!body.recompute && current.length > 0) return json({ day: today, needsCheckin: false, offers: present(rows, locale), readiness: dayReadiness(await readDayState()) })

    // No morning check-in, no focus — the engine never guesses a day it was told nothing about.
    const { data: morning, error: mErr } = await db.from("patient_checkin_moments").select("sleep_overall,pills")
      .eq("patient_id", patientId).eq("checkin_date", today).eq("slot", "morning").maybeSingle()
    if (mErr) throw mErr
    if (!morning) return json({ day: today, needsCheckin: true, offers: present(rows, locale), readiness: null })

    // Readiness, exactly as Trends computes it (member-scores trends-derive `recoveryFor`, minus the felt form
    // the morning doesn't ask). A failed wearable read degrades to "unknown", never to a failed focus.
    let readiness: number | null = null
    let readinessVsBaseline = false
    try {
      const w = await loadWearableInputs(db, patientId, today)
      const wd = w.wearableByDay.get(today) ?? null
      const baselineOk = w.recoveryBaseline.hrvDays >= MIN_HRV_BASELINE_DAYS
      if (wd) {
        readiness = recoveryScore({
          hrvRmssd: wd.recovery?.hrvRmssd ?? null,
          hrvBaseline: baselineOk ? w.recoveryBaseline.hrvRmssd : null,
          sleepHours: wd.sleep?.hours ?? null,
          sleepEfficiencyPct: wd.sleep?.efficiencyPct ?? null,
          avgStress: wd.recovery?.avgStress ?? null,
          felt: null,
        }).score
        readinessVsBaseline = baselineOk && wd.recovery?.hrvRmssd != null
      }
    } catch (e) {
      console.warn("member-daily-focus: wearable inputs unavailable", e instanceof Error ? e.message : String(e))
    }

    // RLS returns only what this member may see: the practice-wide responses and their own care plan's.
    const [{ data: stateRows, error: sErr }, { data: bankRows, error: bErr }] = await Promise.all([
      db.from("state_responses").select("id,state_key,title,care_plan_id,offers").eq("active", true),
      db.from("habit_bank").select("id,pillar,category,title,description,default_slot,easy_title,easy_description,rev_title,rev_description,sort_order,title_fr,description_fr,easy_title_fr,easy_description_fr,rev_title_fr,rev_description_fr").eq("active", true),
    ])
    if (sErr) throw sErr
    if (bErr) throw bErr

    const states: StateResponse[] = (stateRows ?? []).map((s) => ({
      id: s.id, stateKey: s.state_key, title: s.title, carePlanId: s.care_plan_id,
      offers: Array.isArray(s.offers) ? (s.offers as StateOffer[]).filter((o) => o && typeof o.key === "string" && typeof o.title === "string") : [],
    }))
    const bank: BankHabit[] = (bankRows ?? []).map((b) => ({
      id: b.id, pillar: b.pillar, category: b.category, title: b.title, description: b.description,
      defaultSlot: b.default_slot, easyTitle: b.easy_title, easyDescription: b.easy_description,
      revTitle: b.rev_title, revDescription: b.rev_description, sortOrder: b.sort_order,
      titleFr: b.title_fr, descriptionFr: b.description_fr, easyTitleFr: b.easy_title_fr,
      easyDescriptionFr: b.easy_description_fr, revTitleFr: b.rev_title_fr, revDescriptionFr: b.rev_description_fr,
    }))

    const sleepOverall = num(morning.sleep_overall)
    const decided = decideFocus({
      sleepOverall,
      intents: keys(morning.pills, "day_intent"),
      priorities: keys(morning.pills, "day_priority"),
      readiness, readinessVsBaseline, states, bank,
    })

    // The day as the engine read it, stored so the habits' faces hold still with the focus. Best effort: a
    // failed write never fails the focus — the phone then shows the habits as written.
    const bandSource = decided.readinessBand == null ? null : readiness != null ? "wearable" : sleepOverall != null ? "self_report" : null
    const dayState: DayStateRow = { readiness_band: decided.readinessBand, readiness_vs_baseline: readinessVsBaseline, band_source: bandSource }
    const { error: dsErr } = await db.from("patient_day_state").upsert({
      patient_id: patientId, day: today, ...dayState,
      readiness: readiness == null ? null : Math.round(readiness), states: decided.states,
    }, { onConflict: "patient_id,day" })
    if (dsErr) console.warn("member-daily-focus: day state not stored", dsErr.message)

    // Retire what this computation no longer offers — unless the member already said yes to it.
    const wanted = new Set(decided.offers.map((o) => o.offerKey))
    const retire = current.filter((r) => !wanted.has(r.offer_key) && r.accepted !== true && !r.completed).map((r) => r.id)
    if (retire.length > 0) {
      const { error } = await db.from("habit_offers").update({ superseded: true }).in("id", retire)
      if (error) throw error
    }

    // Upsert on the table's own unique key. `accepted` / `completed` are left out of the payload, so a
    // recomputation never undoes what the member did (merge-duplicates updates only the keys it is sent).
    if (decided.offers.length > 0) {
      const { error } = await db.from("habit_offers").upsert(decided.offers.map((o) => ({
        patient_id: patientId, offered_on: today, offer_key: o.offerKey,
        title: o.title, description: o.description, title_fr: o.titleFr, description_fr: o.descriptionFr, state_key: o.trigger, state_response_id: o.stateResponseId,
        rank: o.rank, reason: o.reason, pillar: o.pillar, slot: o.slot, variant: o.variant, superseded: false,
      })), { onConflict: "patient_id,offer_key,offered_on" })
      if (error) throw error
    }

    return json({ day: today, needsCheckin: false, offers: present(await readToday(), locale), readiness: dayReadiness(dayState) })
  } catch (e) {
    const message = e instanceof Error ? e.message : (e as { message?: string })?.message ?? String(e)
    console.error("member-daily-focus", message)
    return json({ error: message }, 500)
  }
})
