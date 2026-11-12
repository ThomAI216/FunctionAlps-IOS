// member-daily-focus — Today's focus for the signed-in member.
//
// POST { recompute?: boolean, locale?: "en" | "fr" }
//   →  { day, needsCheckin, offers: [...], readiness, cell: { id, headline, line, tone, practitionerLine, hardMorning, kickoff } | null }
//
// The focus is one cell of the owner's 12-cell matrix (`_shared/focus/matrix.ts`): last night's sleep (the morning
// check-in's `sleep_overall`, `sleep_duration_min`, and — one step down only — the ring's HRV) x how the member feels
// for the day (today's `patient_day_feelings`: energy, mood, motivation, and their pills). The cell gives the card's
// headline and line in the member's language and the habit TYPES to offer; the offers are 1–3 real `habit_bank` cards
// picked for those types, eligible only (`member_can_add`, or already in the member's own plan — `focusEligibleBank`),
// never a type the cell avoids. The practitioner line ("we'll look at it together") appears on P5 and OG3 only, and only
// after 3 or more depleted days (energy < 40 and mood or motivation < 40) among the last 7.
//
// THE DAY HOLDS STILL. The first call after the morning check-in computes the day: the cell id is stored in
// `patient_day_state.focus_cell`, the offers in `habit_offers`; every later call reads them back, so a ring syncing at
// 09:30 never reshuffles the focus. `recompute: true` (the app sends it right after the morning check-in is saved or
// edited) recomputes and retires what changed — `superseded`, never deleted: members hold no DELETE policy there, and a
// retired offer is still a true record of what was put in front of them. Anything the member accepted or completed
// survives every recomputation.
//
// THE DAY'S BAND HOLDS STILL TOO. The readiness band (low · mid · high) is stored in `patient_day_state` with the cell,
// so the habits' faces on the phone (gentler on a low day, a step further on a high one) come from the same read of the
// day as the focus — never from a ring that synced later.
//
// LANGUAGE. The cell's texts live here in English and French; the habits ride in both (the practice's `*_fr` texts, null =
// not translated yet) and `locale` only chooses which one this read returns — see `_shared/focus/present.ts`.
//
// Everything runs under the MEMBER's session (createUserScopedClient): RLS decides what is read and written,
// exactly as if the app had made each call itself. No service role.

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createUserScopedClient } from "../_shared/supabase.ts"
import { loadWearableInputs } from "../_shared/scoring/wearable-inputs.ts"
import { recoveryScore } from "../member-scores/engine/health/recovery-score.ts"
import { type BankHabit, focusEligibleBank, wording } from "../_shared/focus/engine.ts"
import {
  CELLS, type CellId, chooseHabits, countDepletedDays, type FocusSignals, HRV_BELOW_USUAL_RATIO, MIN_HRV_BASELINE_DAYS, pickCell, slotsFor,
} from "../_shared/focus/matrix.ts"
import { bandLevel } from "../member-scores/engine/checkin/score-bands.ts"
import { contentLocale, dayReadiness, type DayStateRow, OFFER_COLUMNS, type OfferRow, present, presentFocus } from "../_shared/focus/present.ts"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } })

const num = (v: unknown): number | null => (typeof v === "number" ? v : v != null && !Number.isNaN(Number(v)) ? Number(v) : null)

/** The habit library columns the focus reads (`member_can_add` decides who may be offered what). */
const BANK_COLUMNS = "id,pillar,category,title,description,default_slot,easy_title,easy_description,rev_title,rev_description,sort_order,title_fr,description_fr,easy_title_fr,easy_description_fr,rev_title_fr,rev_description_fr,member_can_add"

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
    const read = (columns: string) => db.from("patient_day_state").select(columns)
      .eq("patient_id", patientId).eq("day", today).maybeSingle()
    let { data, error } = await read("readiness_band,readiness_vs_baseline,band_source,focus_cell")
    // Deployed before the migration that adds `focus_cell`: read the day as it was, never fail the focus for it.
    if (error) ({ data, error } = await read("readiness_band,readiness_vs_baseline,band_source"))
    if (error) throw error
    return (data ?? null) as unknown as DayStateRow | null
  }

  /** The cards THIS member may be offered: foundation cards (`member_can_add`) and any card their own plan already holds. */
  const loadEligibleBank = async (): Promise<BankHabit[]> => {
    const [{ data: bankRows, error: bErr }, { data: planRows, error: pErr }] = await Promise.all([
      db.from("habit_bank").select(BANK_COLUMNS).eq("active", true),
      db.from("habits").select("habit_bank_id").eq("patient_id", patientId).eq("status", "active").not("habit_bank_id", "is", null),
    ])
    if (bErr) throw bErr
    if (pErr) throw pErr
    const bank: BankHabit[] = (bankRows ?? []).map((b) => ({
      id: b.id, pillar: b.pillar, category: b.category, title: b.title, description: b.description,
      defaultSlot: b.default_slot, easyTitle: b.easy_title, easyDescription: b.easy_description,
      revTitle: b.rev_title, revDescription: b.rev_description, sortOrder: b.sort_order,
      titleFr: b.title_fr, descriptionFr: b.description_fr, easyTitleFr: b.easy_title_fr,
      easyDescriptionFr: b.easy_description_fr, revTitleFr: b.rev_title_fr, revDescriptionFr: b.rev_description_fr,
      memberCanAdd: b.member_can_add,
    }))
    const prescribed = new Set<string>((planRows ?? []).map((r) => r.habit_bank_id as string))
    return focusEligibleBank(bank, prescribed)
  }

  /** Depleted days among the last 7 (today included): patient_day_feelings rows with energy < 40 and mood or motivation < 40. */
  const depletedDaysInLast7 = async (): Promise<number> => {
    const since = new Date(`${today}T00:00:00Z`)
    since.setUTCDate(since.getUTCDate() - 6)
    const { data, error } = await db.from("patient_day_feelings").select("mood,energy,motivation")
      .eq("patient_id", patientId).gte("day", since.toISOString().slice(0, 10)).lte("day", today)
    if (error) { console.warn("member-daily-focus: feelings history unavailable", error.message); return 0 }
    return countDepletedDays((data ?? []).map((r) => ({ mood: num(r.mood), energy: num(r.energy), motivation: num(r.motivation) })))
  }

  try {
    const rows = await readToday()
    const current = rows.filter((r) => !r.superseded)
    const stored = await readDayState()

    // The day was already decided on a cell: read it back, never recompute (a ring syncing at 09:30 reshuffles nothing).
    const storedCell = stored?.focus_cell && Object.hasOwn(CELLS, stored.focus_cell) ? (stored.focus_cell as CellId) : null
    if (!body.recompute && storedCell) {
      const eligible = await loadEligibleBank()
      let sleepKnown = true
      if (CELLS[storedCell].noSleep) {
        const { data: m } = await db.from("patient_checkin_moments").select("sleep_overall,sleep_duration_min")
          .eq("patient_id", patientId).eq("checkin_date", today).eq("slot", "morning").maybeSingle()
        sleepKnown = num(m?.sleep_overall) != null || num(m?.sleep_duration_min) != null
      }
      const band = stored?.readiness_band === "low" || stored?.readiness_band === "mid" || stored?.readiness_band === "high" ? stored.readiness_band : null
      const cell = presentFocus({ cellId: storedCell, locale, depletedDays: await depletedDaysInLast7(), sleepKnown, eligible, band })
      return json({ day: today, needsCheckin: false, offers: present(rows, locale), readiness: dayReadiness(stored), cell })
    }

    // What the morning holds: last night (the morning moment) and how the member feels for the day.
    const [{ data: morning, error: mErr }, { data: feeling, error: fErr }] = await Promise.all([
      db.from("patient_checkin_moments").select("sleep_overall,sleep_duration_min")
        .eq("patient_id", patientId).eq("checkin_date", today).eq("slot", "morning").maybeSingle(),
      db.from("patient_day_feelings").select("mood,energy,motivation,pills")
        .eq("patient_id", patientId).eq("day", today).maybeSingle(),
    ])
    if (mErr) throw mErr
    // The feelings table may not be applied yet: the night alone still gives a card (the row-only cell).
    if (fErr) console.warn("member-daily-focus: feeling unavailable", fErr.message)

    // Readiness, exactly as Trends computes it (member-scores trends-derive `recoveryFor`, minus the felt form
    // the morning doesn't ask). A failed wearable read degrades to "unknown", never to a failed focus.
    let readiness: number | null = null
    let readinessVsBaseline = false
    let hrvBelowUsual = false
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
        const hrv = wd.recovery?.hrvRmssd ?? null, base = w.recoveryBaseline.hrvRmssd
        hrvBelowUsual = baselineOk && hrv != null && base != null && base > 0 && hrv / base <= HRV_BELOW_USUAL_RATIO
      }
    } catch (e) {
      console.warn("member-daily-focus: wearable inputs unavailable", e instanceof Error ? e.message : String(e))
    }

    const sleepOverall = num(morning?.sleep_overall)
    const signals: FocusSignals = {
      sleepOverall, sleepDurationMin: num(morning?.sleep_duration_min),
      mood: num(feeling?.mood), energy: num(feeling?.energy), motivation: num(feeling?.motivation),
      pills: (feeling?.pills ?? null) as Record<string, unknown> | null,
      hrvBelowUsual, depletedDays: await depletedDaysInLast7(),
    }

    // Neither the night nor the feeling answered: the engine never guesses a day it was told nothing about.
    const placed = pickCell(signals)
    if (!placed) return json({ day: today, needsCheckin: true, offers: present(rows, locale), readiness: null, cell: null })

    const eligible = await loadEligibleBank()
    const band = bandLevel(readiness) ?? bandLevel(sleepOverall)
    const chosen = chooseHabits(placed.cell, slotsFor(placed.cell, signals), eligible, band)

    // The day as the engine read it, stored so the cell and the habits' faces hold still. Best effort: a failed write never
    // fails the focus — the next read then computes the day again.
    const bandSource = band == null ? null : readiness != null ? "wearable" : sleepOverall != null ? "self_report" : null
    const dayState: DayStateRow = { readiness_band: band, readiness_vs_baseline: readinessVsBaseline, band_source: bandSource }
    const { error: dsErr } = await db.from("patient_day_state").upsert({
      patient_id: patientId, day: today, ...dayState, focus_cell: placed.cell.id,
      readiness: readiness == null ? null : Math.round(readiness),
    }, { onConflict: "patient_id,day" })
    if (dsErr) console.warn("member-daily-focus: day state not stored", dsErr.message)

    // The offers: one per chosen card, in the cell's order (the first is the lead).
    const offers = chosen.map((c, i) => {
      const w = wording(c.habit, c.variant)
      return {
        offerKey: `bank:${c.habit.id}`, rank: i + 1, title: w.title, description: w.description, titleFr: w.titleFr, descriptionFr: w.descriptionFr,
        pillar: c.habit.pillar, slot: c.habit.defaultSlot, variant: c.variant, trigger: placed.cell.id,
      }
    })

    // Retire what this computation no longer offers — unless the member already said yes to it.
    const wanted = new Set(offers.map((o) => o.offerKey))
    const retire = current.filter((r) => !wanted.has(r.offer_key) && r.accepted !== true && !r.completed).map((r) => r.id)
    if (retire.length > 0) {
      const { error } = await db.from("habit_offers").update({ superseded: true }).in("id", retire)
      if (error) throw error
    }

    // Upsert on the table's own unique key. `accepted` / `completed` are left out of the payload, so a
    // recomputation never undoes what the member did (merge-duplicates updates only the keys it is sent).
    if (offers.length > 0) {
      const { error } = await db.from("habit_offers").upsert(offers.map((o) => ({
        patient_id: patientId, offered_on: today, offer_key: o.offerKey,
        title: o.title, description: o.description, title_fr: o.titleFr, description_fr: o.descriptionFr, state_key: o.trigger, state_response_id: null,
        rank: o.rank, reason: "focus", pillar: o.pillar, slot: o.slot === "morning" || o.slot === "midday" || o.slot === "evening" ? o.slot : null,
        variant: o.variant, superseded: false,
      })), { onConflict: "patient_id,offer_key,offered_on" })
      if (error) throw error
    }

    const sleepKnown = sleepOverall != null || signals.sleepDurationMin != null
    const cell = presentFocus({ cellId: placed.cell.id, locale, depletedDays: signals.depletedDays, sleepKnown, eligible, band })
    return json({ day: today, needsCheckin: false, offers: present(await readToday(), locale), readiness: dayReadiness(dayState), cell })
  } catch (e) {
    const message = e instanceof Error ? e.message : (e as { message?: string })?.message ?? String(e)
    console.error("member-daily-focus", message)
    return json({ error: message }, 500)
  }
})
