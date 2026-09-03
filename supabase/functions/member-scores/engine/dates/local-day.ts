// THE canonical day key for patient activity (check-ins, meals, series
// bucketing): the patient's device-local calendar day, formatted YYYY-MM-DD.
//
// Why local, not UTC: our users are Swiss (UTC+1/+2). With UTC keys, anything
// logged between local midnight and 01:00/02:00 filed under YESTERDAY, so the
// hub showed "no check-in" next morning and re-saving created a duplicate row.
// Every writer and reader of `checkin_date` (and every client-side day
// bucketing) must go through this helper so they can never disagree.
//
// NOT for server-keyed lookups: rows whose day column is stamped by an edge
// function (e.g. nb_score_tips.tip_date, nb_report_content.period_start) must
// be queried with the SERVER's convention until those functions are localized
// (PRD Phase 2) — do not "fix" those call sites to this helper unilaterally.
//
// Migration note (2026-07-08): historical rows keyed before this change used
// UTC days; the ≤2h one-time skew is accepted rather than rewriting rows.
// ── Edge runtime: the member's wall clock ────────────────────────────────────
// This process runs in UTC. The caller sends its UTC offset; every "now" the engine
// reads is shifted by it, so the local-time Date methods used throughout (getHours,
// toDateString, getDate …) read as the member's own clock — the same day boundaries
// the web app applies on the device.
let clockOffsetMs = 0
export function setClockOffsetMinutes(minutes: number): void { clockOffsetMs = minutes * 60_000 }
export function engineNow(): Date { return new Date(Date.now() + clockOffsetMs) }
export function shiftToWallClock(iso: string): string { return new Date(new Date(iso).getTime() + clockOffsetMs).toISOString() }

export function localDayISO(d: Date = engineNow()): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
