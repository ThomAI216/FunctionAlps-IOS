// Per-marker 0-100 daily trend series for the Check-in Hub. Pure + unit-tested.
//
// Two domains, each a fixed set of markers the daily check-ins collect:
//   • functional — energy · sleep · mood · stress (4 markers; digestion lives in
//     Gut Intelligence). Raw check-in values normalised to 0-100, higher = better.
//     Stress is shown as CALMNESS: raw 5 (calm) → 100, raw 1 (tense) → 0.
//   • gut intelligence — bloating · heartburn · gas · stool quality · regularity
//     (raw markers normalised here to a 0-100 "calm/comfortable" score)
// The hub grid has 6 slots; 4 functional markers leave 2 free for future use.
import { HEALTH_DETAILS } from '../data/health-details.ts'
import type { CheckinScores, CheckinHistoryEntry } from '../types/daily-store.ts'
import { lastNDays } from '../health/score-series.ts'
import { localDayISO } from '../dates/local-day.ts'

export interface MarkerDef {
  key: string
  label: string
  color: string
}

// The 4 functional markers (digestion lives in Gut Intelligence; colours = each metric's distinct accent).
export const FUNCTIONAL_MARKERS: MarkerDef[] = [
  { key: 'energy', label: 'Energy', color: HEALTH_DETAILS.energy.accentColor },
  { key: 'sleep', label: 'Sleep', color: HEALTH_DETAILS.sleep.accentColor },
  { key: 'mood', label: 'Mood', color: HEALTH_DETAILS.mood.accentColor },
  { key: 'stress', label: 'Calmness', color: HEALTH_DETAILS.stress.accentColor },
]

export type GutMarkerKey = 'bloating' | 'burns' | 'gasBurden' | 'stoolQuality' | 'stoolFrequency'

// The 5 main gut markers we track (the columns the intelligence form persists).
export const GUT_MARKERS: (MarkerDef & { key: GutMarkerKey })[] = [
  { key: 'bloating', label: 'Bloating', color: '#14b8a6' },
  { key: 'burns', label: 'Heartburn', color: '#f97316' },
  { key: 'gasBurden', label: 'Gas', color: '#84cc16' },
  { key: 'stoolQuality', label: 'Stool quality', color: '#0ea5e9' },
  { key: 'stoolFrequency', label: 'Regularity', color: '#a78bfa' },
]

const clamp01 = (v: number) => Math.min(1, Math.max(0, v))
const isoDate = (d: Date) => localDayISO(d) // patient-local — matches checkin_date

// ── functional: 1-5 mountain check-in -> 0-100 (full axis, 5 = 100) ───────────
// The functional check-in is a 1-5 scale, so we map straight to 0-100 (5 -> 100;
// dividing by 10 was what pinned the charts at ~50). Stress is shown as CALMNESS:
// 5 = calm (best) -> 100 (high line), 1 = tense (worst) -> 0. Sleep is shown in
// HOURS with the chart top = 10h: raw 5 -> 100 -> 10h (use sleepHoursFromScore).
type FuncKey = 'energy' | 'sleep' | 'mood' | 'stress'
// Live CheckinScores (plain numbers) or a DB history entry (nullable axes).
type FunctionalSource = { [K in FuncKey]?: number | null }

const FN_MIN = 1
const FN_MAX = 5

// Sleep chart axis top, in hours. A 0-100 sleep score maps linearly onto 0-10h.
export const SLEEP_TOP_HOURS = 10
export const sleepHoursFromScore = (score: number) => (score / 100) * SLEEP_TOP_HOURS

function functionalScore(src: FunctionalSource, key: FuncKey): number | null {
  const v = src[key]
  if (typeof v !== 'number') return null // axis never captured — a gap, not a 0
  const raw = Math.min(FN_MAX, Math.max(FN_MIN, v))
  // Sleep: raw/5 of the 10h axis (5 -> 100 -> 10h). Others: full 0-100, 5 = best.
  // Stress = calmness: raw 5 (calm) -> 100, same direction as energy/mood.
  if (key === 'sleep') return Math.round((raw / FN_MAX) * 100)
  return Math.round(((raw - FN_MIN) / (FN_MAX - FN_MIN)) * 100)
}

// Map from marker key to the CheckinHistoryEntry field that holds the exact 0-100 score.
// These are written by Task 11 and preferred over the legacy 1-5 mapping when present.
const EXACT_SCORE_FIELD: Record<FuncKey, keyof CheckinHistoryEntry> = {
  energy: 'energyOverall',
  sleep: 'sleepOverall',
  mood: 'moodScore',
  stress: 'stressScore',
}

/** Per-day 0-100 series for each functional marker over the last `days`
 *  (oldest first). `today` supplies the final day when the functional form was
 *  completed today, else that day (and any day without a check-in) is null.
 *
 *  For PAST days: if the history entry carries an exact 0-100 headline score
 *  (energyOverall / sleepOverall / moodScore / stressScore), that value is used
 *  directly. Otherwise the legacy 1-5 → 0-100 mapping via `functionalScore` is
 *  applied. The TODAY slot uses `todayHeadline` if supplied (same headline-or-legacy
 *  path as past days), else falls back to the live `today` CheckinScores via
 *  `functionalScore`. */
export function buildFunctionalSeries(
  history: CheckinHistoryEntry[],
  today: FunctionalSource | null,
  now: Date,
  days = 14,
  todayHeadline?: CheckinHistoryEntry | null,
): Record<string, (number | null)[]> {
  const byDate = new Map<string, CheckinHistoryEntry>(history.map((e) => [e.date, e]))
  const out: Record<string, (number | null)[]> = {}
  for (const m of FUNCTIONAL_MARKERS) out[m.key] = []
  for (const day of lastNDays(now, days)) {
    const isToday = day.toDateString() === now.toDateString()
    if (isToday) {
      for (const m of FUNCTIONAL_MARKERS) {
        if (todayHeadline) {
          // Same headline-or-legacy path as a past-day entry.
          const exactField = EXACT_SCORE_FIELD[m.key as FuncKey]
          const exact = todayHeadline[exactField] as number | null | undefined
          out[m.key].push(typeof exact === 'number' ? exact : functionalScore(todayHeadline, m.key as FuncKey))
        } else {
          out[m.key].push(today ? functionalScore(today, m.key as FuncKey) : null)
        }
      }
    } else {
      const entry = byDate.get(isoDate(day)) ?? null
      for (const m of FUNCTIONAL_MARKERS) {
        if (!entry) {
          out[m.key].push(null)
        } else {
          const exactField = EXACT_SCORE_FIELD[m.key as FuncKey]
          const exact = entry[exactField] as number | null | undefined
          out[m.key].push(typeof exact === 'number' ? exact : functionalScore(entry, m.key as FuncKey))
        }
      }
    }
  }
  return out
}

// ── gut: raw marker -> 0-100 "calm/comfortable" (higher always = better) ──────
function freqBadness(perDay: number): number {
  if (perDay >= 1 && perDay <= 3) return 0
  if (perDay === 0) return 0.6
  if (perDay <= 5) return 0.3
  return 1
}

export function gutMarkerScore(key: GutMarkerKey, v: number | null): number | null {
  if (v == null) return null
  switch (key) {
    case 'bloating':
    case 'burns':
      return Math.round((1 - clamp01((v - 1) / 9)) * 100) // 1-10, high = worse
    case 'gasBurden':
      return Math.round((1 - clamp01(v / 10)) * 100) // 0-10, high = worse
    case 'stoolQuality':
      return Math.round(clamp01((v - 1) / 4) * 100) // 1-5, high = better
    case 'stoolFrequency':
      return Math.round((1 - freqBadness(v)) * 100) // 1-3/day ideal
    default:
      return null
  }
}

export interface GutHistoryEntry {
  date: string
  bloating: number | null
  burns: number | null
  gasBurden: number | null
  stoolQuality: number | null
  stoolFrequency: number | null
  // v2 headline columns (mig 071); null when pre-migration or not yet answered.
  comfort: number | null
  gutOverall: number | null
  stool: number | null
}

type GutSource = Pick<CheckinScores, GutMarkerKey>

/** Per-day 0-100 series for each gut marker over the last `days` (oldest first).
 *  `today` supplies the final day when the intelligence form was completed
 *  today, else that day (and any day without a check-in) is null. */
export function buildGutSeries(
  history: GutHistoryEntry[],
  today: GutSource | null,
  now: Date,
  days = 14,
): Record<GutMarkerKey, (number | null)[]> {
  const byDate = new Map<string, GutHistoryEntry>(history.map((e) => [e.date, e]))
  const out = { bloating: [], burns: [], gasBurden: [], stoolQuality: [], stoolFrequency: [] } as Record<GutMarkerKey, (number | null)[]>
  for (const day of lastNDays(now, days)) {
    const isToday = day.toDateString() === now.toDateString()
    const entry: GutHistoryEntry | null = isToday
      ? today
        ? { date: isoDate(day), bloating: today.bloating, burns: today.burns, gasBurden: today.gasBurden, stoolQuality: today.stoolQuality, stoolFrequency: today.stoolFrequency, comfort: null, gutOverall: null, stool: null }
        : null
      : byDate.get(isoDate(day)) ?? null
    for (const m of GUT_MARKERS) {
      out[m.key].push(entry ? gutMarkerScore(m.key, entry[m.key]) : null)
    }
  }
  return out
}

/** Most recent non-null value of a series (the marker's current standing). */
export function latestOf(series: (number | null)[]): number | null {
  for (let i = series.length - 1; i >= 0; i--) {
    if (series[i] !== null) return series[i]
  }
  return null
}
