// Shapes lifted verbatim from lib/stores/daily-store.ts (no zustand here).
import { localDayISO } from '../dates/local-day.ts'
export interface CheckinScores {
  mood: number         // 1–5 mountain scale (functional check-in pick)
  digestion: number    // 1–5 mountain scale
  energy: number       // 1–5 mountain scale
  sleep: number        // 1–5 mountain scale (subjective rest, NOT hours/steps)
  sleepQuality: number // 1–10, 1 = restless, 10 = deeply restored
  stress: number       // 1–5 mountain scale (lower is better — inverted in scoring)
  inflammation: number // 1–5 mountain scale (lower is better; not captured by the functional form)
  bloating: number  // 1-10, default 5
  burns: number     // 1-10, default 5
  stoolType: number // Bristol 1-7, default 4
  stoolQuality: number // 1-5, default 3
  abdominalPain: number // 0-10
  stoolFrequency: number // count per 24h
  stoolUrgency: number // 0-10
  incompleteEvacuation: number // 0-10
  strainingEffort: number // 0-10
  nausea: number // 0-10
  postMealFullness: number // 0-10
  gasBurden: number // 0-10
  redFlagBloodInStool: boolean
  redFlagBlackStool: boolean
  redFlagPersistentVomiting: boolean
  redFlagFever: boolean
  redFlagUnintentionalWeightLoss: boolean
  redFlagSevereWorseningPain: boolean
  // Felt-recovery (check-in v2 — nullable; populated by the check-in track):
  recovery?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
  soreness?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
  recentLoad?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
  recentMentalLoad?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
}

type GutFields = Pick<CheckinScores, 'bloating' | 'burns' | 'stoolType' | 'stoolQuality'>
export type CheckinFormType = 'functional' | 'intelligence'

export interface DailySummary {
  date: string
  title: string
  note: string
  digestion: number
  inflammation: number
  energy: number
  mealsLogged: number
  symptomsLogged: number
  generatedAt: string
}

export interface CheckinHistoryEntry {
  date: string        // YYYY-MM-DD (past days only — today comes from live `checkin`)
  // 1–5 mountain scale, null when the row never captured the axis (the v2
  // functional form intentionally writes neither digestion nor inflammation).
  // NEVER coerce null to 0 — 0 mountain-scores as worst-possible; consumers
  // fall back to NEUTRAL_1_5 (via getCurrentValue) or drop the axis (overallScore).
  mood: number | null
  digestion: number | null
  energy: number | null
  sleep: number | null   // subjective rest — scored raw, no hours mapping
  sleepQuality: number | null // 1–10
  stress: number | null  // lower is better — inverted in scoring
  inflammation: number | null // lower is better; not captured by the functional form
  // Task 11 exact 0-100 headline scores — present when the DB row has them, else null.
  // buildFunctionalSeries prefers these over the 1-5 legacy fields for past days.
  energyOverall?: number | null
  sleepOverall?: number | null
  moodScore?: number | null
  stressScore?: number | null
  recovery?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
  soreness?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
  recentLoad?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
  recentMentalLoad?: number | null // 0-10 felt scale (matches energy/mood/etc.); mapped to 0-100 in trends-derive
}

interface SummaryMetrics {
  mealsLogged: number
  symptomsLogged: number
}

interface DailyStore {
  checkin: CheckinScores | null
  checkinCompletedAt: string | null
  hydrationMl: number
  hydrationDate: string | null
  functionalCompletedAt: string | null
  intelligenceCompletedAt: string | null
  functionalSubmissionCount: number
  intelligenceSubmissionCount: number
  intelligenceAssessmentsToday: number
  lastSubmissionForm: CheckinFormType | null
  checkinHistoryDates: string[]
  checkinAssessmentsToday: number
  dailySummaries: Record<string, DailySummary>
  metricHistory: CheckinHistoryEntry[]
  setMetricHistory: (history: CheckinHistoryEntry[]) => void
  completeCheckin: (
    scores: CheckinScores,
    options?: {
      formType?: CheckinFormType
      completedAt?: string
      functionalCompletedAt?: string | null
      intelligenceCompletedAt?: string | null
      functionalSubmissionCount?: number
      intelligenceSubmissionCount?: number
      lastSubmissionForm?: CheckinFormType | null
    }
  ) => void
  setGutFields: (fields: Partial<GutFields>) => void
  getTrackedDaysCount: () => number
  setDailySummary: (summary: DailySummary) => void
  addHydrationGlass: (glassMl?: number) => void
  setHydrationProgress: (hydrationMl: number, hydrationDate: string) => void
  resetHydrationForToday: (nowISO?: string) => void
  ensureDailySummaryForCurrentCheckin: (metrics: SummaryMetrics, nowISO?: string) => DailySummary | null
  getYesterdaySummary: (nowISO?: string) => DailySummary | null
  resetCheckin: () => void
}

// Patient-local day (M3): the 23:00 summary gate compares this against local
// getHours(), so the date must be local too or the gate misfires near midnight.
function isoDate(dateLike: string | Date): string {
  return localDayISO(new Date(dateLike))
}

function buildDailySummary(
  date: string,
  scores: CheckinScores,
  metrics: SummaryMetrics,
  generatedAt: string
): DailySummary {
  // 1–5 mountain scale: digestion higher-is-better, inflammation lower-is-better.
  const digestionSignal = scores.digestion >= 4 ? 'steady' : scores.digestion >= 3 ? 'mixed' : 'fragile'
  const inflammationSignal = scores.inflammation <= 2 ? 'calmer' : scores.inflammation <= 3 ? 'moderate' : 'reactive'
  const note = `Digestion felt ${digestionSignal} with ${inflammationSignal} inflammation signals. Logged ${metrics.mealsLogged} meal${metrics.mealsLogged === 1 ? '' : 's'} and ${metrics.symptomsLogged} symptom${metrics.symptomsLogged === 1 ? '' : 's'}.`

  return {
    date,
    title: 'Yesterday at a glance',
    note,
    digestion: scores.digestion,
    inflammation: scores.inflammation,
    energy: scores.energy,
    mealsLogged: metrics.mealsLogged,
    symptomsLogged: metrics.symptomsLogged,
    generatedAt,
  }
}

