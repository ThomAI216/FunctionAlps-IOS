import { localDayISO } from '../dates/local-day.ts'
import type { DimAnswers } from './dimension-types.ts'
import type { CheckinHistoryEntry } from '../types/daily-store.ts'
import type { GutHistoryEntry } from './marker-trends.ts'

// Today's check-in, read from the canonical patient_daily_checkins row (UTC-dated).
// Drives prefill (the detail jsonb) AND the hub's today value (the headline entries).
export interface TodayCheckin {
  functionalDoneAt: string | null
  intelligenceDoneAt: string | null
  functionalAnswers: Record<string, DimAnswers> | null // functional_detail (FLAT)
  gutAnswers: Record<string, DimAnswers> | null         // gut_detail.answers (WRAPPED)
  notes: string | null                                  // gut_detail.notes
  todayFunctional: CheckinHistoryEntry | null
  todayGut: GutHistoryEntry | null
}

const num = (v: unknown): number | null => (typeof v === 'number' ? v : null)

// Pure: map a raw row → TodayCheckin. `hasV2` = the wide select (detail + headline
// columns) succeeded; when false those fields read null (legacy/degraded).
export function parseTodayCheckin(row: Record<string, unknown> | null, hasV2: boolean): TodayCheckin | null {
  if (!row) return null
  const functionalDoneAt = (row.functional_completed_at as string) ?? null
  const intelligenceDoneAt = (row.intelligence_completed_at as string) ?? null
  const date = (row.checkin_date as string) ?? ''

  // functional_detail is the FLAT Record<DimKey, DimAnswers>.
  const fd = hasV2 ? (row.functional_detail as Record<string, DimAnswers> | null) : null
  const functionalAnswers = fd && typeof fd === 'object' ? fd : null

  // gut_detail is WRAPPED { answers, notes }.
  const gd = hasV2 ? (row.gut_detail as { answers?: Record<string, DimAnswers>; notes?: string | null } | null) : null
  const gutAnswers = gd && gd.answers && typeof gd.answers === 'object' ? gd.answers : null
  const notes = gd && typeof gd.notes === 'string' ? gd.notes : null

  const todayFunctional: CheckinHistoryEntry | null = functionalDoneAt
    ? {
        date,
        // Null stays null — 0 would mountain-score as worst-possible (see H1
        // note on CheckinHistoryEntry); consumers neutral-fall-back or drop the axis.
        mood: num(row.mood),
        digestion: num(row.digestion),
        energy: num(row.energy),
        sleep: num(row.sleep),
        sleepQuality: num(row.sleep_quality),
        stress: num(row.stress),
        inflammation: num(row.inflammation),
        energyOverall: hasV2 ? num(row.energy_overall) : null,
        sleepOverall: hasV2 ? num(row.sleep_overall) : null,
        moodScore: hasV2 ? num(row.mood_score) : null,
        stressScore: hasV2 ? num(row.stress_score) : null,
        // Felt-recovery (v2, nullable) — hydrated for edit-mode prefill so re-saving
        // a check-in never wipes a previously-logged felt answer.
        recovery: hasV2 ? num(row.recovery) : null,
        soreness: hasV2 ? num(row.soreness) : null,
        recentLoad: hasV2 ? num(row.recent_load) : null,
        recentMentalLoad: hasV2 ? num(row.recent_mental_load) : null,
      }
    : null

  const todayGut: GutHistoryEntry | null = intelligenceDoneAt
    ? {
        date,
        bloating: num(row.bloating),
        burns: num(row.burns),
        gasBurden: num(row.gas_burden),
        stoolQuality: num(row.stool_quality),
        stoolFrequency: num(row.stool_frequency),
        comfort: hasV2 ? num(row.gut_comfort) : null,
        gutOverall: hasV2 ? num(row.gut_overall) : null,
        stool: hasV2 ? num(row.gut_stool) : null,
      }
    : null

  return { functionalDoneAt, intelligenceDoneAt, functionalAnswers, gutAnswers, notes, todayFunctional, todayGut }
}

