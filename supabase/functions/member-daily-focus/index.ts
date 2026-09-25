// member-daily-focus — Today's focus for the signed-in member.
//
// POST { recompute?: boolean }  →  { day, needsCheckin, offers: [...] }
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
// Everything runs under the MEMBER's session (createUserScopedClient): RLS decides what is read and written,
// exactly as if the app had made each call itself. No service role.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createUserScopedClient } from "../_shared/supabase.ts"
import { loadWearableInputs } from "../_shared/scoring/wearable-inputs.ts"
import { recoveryScore } from "../member-scores/engine/health/recovery-score.ts"
import { type BankHabit, decideFocus, type StateOffer, type StateResponse } from "../_shared/focus/engine.ts"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

/** A personal HRV baseline needs this many days before "below your usual" means anything (member-scores' gate). */
const MIN_HRV_BASELINE_DAYS = 14

const OFFER_COLUMNS = "id,offer_key,rank,title,description,pillar,slot,variant,reason,state_key,accepted,completed,superseded,state_responses(title)"

interface OfferRow {
  id: string
  offer_key: string
  rank: number | null
  title: string
  description: string | null
  pillar: string | null
  slot: string | null
  variant: string | null
  reason: string | null
  state_key: string
  accepted: boolean | null
  completed: boolean
  superseded: boolean
  state_responses: { title: string } | null
}

/** What the member sees: the day's live offers — current ones, plus any retired one they had already said yes to. */
function present(rows: OfferRow[]) {
  return rows
    .filter((r) => !r.superseded || r.accepted === true || r.completed)
    .sort((a, b) => (a.rank ?? 99) - (b.rank ?? 99))
    .map((r) => ({
      id: r.id, offerKey: r.offer_key, rank: r.rank, title: r.title, description: r.description,
      pillar: r.pillar, slot: r.slot, variant: r.variant, reason: r.reason, trigger: r.state_key,
      stateTitle: r.state_responses?.title ?? null, accepted: r.accepted, completed: r.completed,
    }))
}

const num = (v: unknown): number | null => (typeof v === "number" ? v : v != null && !Number.isNaN(Number(v)) ? Number(v) : null)
const keys = (pills: unknown, group: string): string[] => {
  const v = (pills as Record<string, unknown> | null)?.[group]
  return Array.isArray(v) ? v.filter((k): k is string => typeof k === "string") : []
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })
  if (req.method !== "POST") return json({ error: "POST only" }, 405)

  let body: { recompute?: boolean } = {}
  try { body = await req.json() } catch { /* empty body is fine */ }

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

  try {
    const rows = await readToday()
    const current = rows.filter((r) => !r.superseded)
    if (!body.recompute && current.length > 0) return json({ day: today, needsCheckin: false, offers: present(rows) })

    // No morning check-in, no focus — the engine never guesses a day it was told nothing about.
    const { data: morning, error: mErr } = await db.from("patient_checkin_moments").select("sleep_overall,pills")
      .eq("patient_id", patientId).eq("checkin_date", today).eq("slot", "morning").maybeSingle()
    if (mErr) throw mErr
    if (!morning) return json({ day: today, needsCheckin: true, offers: present(rows) })

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
      db.from("habit_bank").select("id,pillar,category,title,description,default_slot,easy_title,easy_description,rev_title,rev_description,sort_order").eq("active", true),
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
    }))

    const decided = decideFocus({
      sleepOverall: num(morning.sleep_overall),
      intents: keys(morning.pills, "day_intent"),
      priorities: keys(morning.pills, "day_priority"),
      readiness, readinessVsBaseline, states, bank,
    })

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
        title: o.title, description: o.description, state_key: o.trigger, state_response_id: o.stateResponseId,
        rank: o.rank, reason: o.reason, pillar: o.pillar, slot: o.slot, variant: o.variant, superseded: false,
      })), { onConflict: "patient_id,offer_key,offered_on" })
      if (error) throw error
    }

    return json({ day: today, needsCheckin: false, offers: present(await readToday()) })
  } catch (e) {
    const message = e instanceof Error ? e.message : (e as { message?: string })?.message ?? String(e)
    console.error("member-daily-focus", message)
    return json({ error: message }, 500)
  }
})
