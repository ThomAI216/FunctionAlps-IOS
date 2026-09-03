// Pure Trends derivation: raw store data -> the 4 ScoreBreakdowns + crown
// composite. Keeps app/(tabs)/health.tsx thin and makes the whole pipeline
// unit-testable. Type-only imports from stores, so the module stays pure.
import type { MealLog } from '../types/log-store.ts'
import type { CheckinScores, CheckinHistoryEntry } from '../types/daily-store.ts'
import { HEALTH_DETAILS, type HealthMetricKey } from '../data/health-details.ts'
import type { GutHistoryEntry } from '../checkin/marker-trends.ts'
import type { TodayCheckin } from '../checkin/load-today.ts'
import { buildNutritionSnapshot } from '../nutrition/snapshot.ts'
import { buildMacroStats, macroProximityScore } from '../nutrition/macros-view.ts'
import { getConsumedFromLogs } from '../data/nutrients.ts'
import { functionalComposite, type Composite } from './functional-score.ts'
import { nutritionScore } from './nutrition-score.ts'
import { metabolicScore } from './metabolic-score.ts'
import { vitalityScore } from './vitality-score.ts'
import { gutScore } from './gut-breakdown.ts'
import { gutSignalsForEntry, gutSignalsCurrent } from './gut-signals.ts'
import { ruleBasedTip } from './score-tip.ts'
import { lastNDays } from './score-series.ts'
import { localDayISO } from '../dates/local-day.ts'
import { windowMeals } from './meal-window.ts'
import type { ScoreBreakdown, ScoreCore } from './score-core.ts'
import { recoveryScore, type FeltRecoveryInput } from './recovery-score.ts'
import type { WearableDay, RecoveryBaseline } from '../wearables/metrics.ts'

export interface TrendsProfile {
  sex: 'male' | 'female' | null
  weight: string
  height: string
  age: string
  activityLevel: string | null
  goalMode: 'build' | 'maintain' | 'cut' | null
  estimatedBfPercent: number | null
  customMacros: { proteinG?: number; carbsG?: number; fatG?: number; calories?: number } | null
  customCalorieOffset: number | null
}

export interface DeriveTrendsInput {
  meals: MealLog[]
  metricHistory: CheckinHistoryEntry[]
  gutHistory: GutHistoryEntry[]
  today: TodayCheckin | null
  checkin: CheckinScores | null // legacy fallback only
  gutCompletedToday: boolean
  profile: TrendsProfile
  now: Date
  wearableByDay?: Map<string, WearableDay>
  recoveryBaseline?: RecoveryBaseline
}

export interface TrendsResult {
  vitality: ScoreBreakdown
  metabolic: ScoreBreakdown
  nutrition: ScoreBreakdown
  gut: ScoreBreakdown
  composite: Composite
  /** 14-day per-day composite (same formula as `composite.score`) — THE crown
   *  sparkline, so the headline number always equals the series' last point. */
  compositeSeries14d: (number | null)[]
}

// v2 0-100 overall columns for the 4 functional metrics (digestion/inflammation are
// handled through gut signals, not here).
const OVERALL_FIELD: Partial<Record<HealthMetricKey, keyof CheckinHistoryEntry>> = {
  energy: 'energyOverall', mood: 'moodScore', sleep: 'sleepOverall', stress: 'stressScore',
}

// Felt metric 0-100: prefer the v2 overall column; fall back to the legacy native-scale
// value only for pre-v2 rows that lack it (those columns were genuinely native, so the
// HEALTH_DETAILS path is correct for them).
function feltMetric(entry: CheckinHistoryEntry | null, key: HealthMetricKey): number | null {
  if (!entry) return null
  const field = OVERALL_FIELD[key]
  if (field !== undefined) {
    const o = entry[field]
    if (typeof o === 'number') return o
  }
  const cfg = HEALTH_DETAILS[key]
  return cfg.scoreFromValue(cfg.getCurrentValue(entry))
}

function mealsOnDay(meals: MealLog[], day: Date): MealLog[] {
  const k = day.toDateString()
  return meals.filter((m) => new Date(m.timestamp).toDateString() === k)
}

function hasMicro(meals: MealLog[]): boolean {
  if (!meals.length) return false
  const consumed = getConsumedFromLogs(meals)
  return Object.values(consumed).some((v) => typeof v === 'number' && v > 0)
}

function snapshotSafe(meals: MealLog[], p: TrendsProfile) {
  const weightKg = Number(p.weight)
  const heightCm = Number(p.height)
  if (!weightKg || !heightCm) return null
  return buildNutritionSnapshot({
    meals,
    sex: p.sex ?? 'male',
    weightKg,
    heightCm,
    age: Number(p.age) || 34,
    activityLevel: p.activityLevel ?? 'moderately_active',
    goal: p.goalMode ?? 'maintain',
    bfPercent: p.estimatedBfPercent ?? 18,
    customMacros: p.customMacros ?? null,
    customCalorieOffset: p.customCalorieOffset ?? null,
  })
}

// micro coverage + macro proximity for a set of meals. Both null when there are
// no meals (no data — never a degenerate 0) or no body profile.
function nutritionPcts(meals: MealLog[], p: TrendsProfile): { micro: number | null; macro: number | null } {
  if (!meals.length) return { micro: null, macro: null }
  const snap = snapshotSafe(meals, p)
  if (!snap) return { micro: null, macro: null }
  return {
    micro: hasMicro(meals) ? snap.micronutrients.overallPct : null,
    macro: macroProximityScore(buildMacroStats(snap)),
  }
}

const to100 = (v: number | null | undefined) => (v == null ? null : Math.round((v / 10) * 100))

function feltFrom(src: CheckinScores | CheckinHistoryEntry | null): FeltRecoveryInput | null {
  if (!src) return null
  const s = src as Partial<{ recovery: number; soreness: number; recentLoad: number; recentMentalLoad: number }>
  const f = { recovery: to100(s.recovery), soreness: to100(s.soreness), physicalLoad: to100(s.recentLoad), mentalLoad: to100(s.recentMentalLoad) }
  return Object.values(f).some((v) => v != null) ? f : null
}

function recoveryFor(src: CheckinScores | CheckinHistoryEntry | null, day: string, opts: { wearableByDay?: Map<string, WearableDay>; recoveryBaseline?: RecoveryBaseline }): number | null {
  const w = opts.wearableByDay?.get(day) ?? null
  const felt = feltFrom(src)
  if (!w && !felt) return null
  const hrvBaseline = (opts.recoveryBaseline && opts.recoveryBaseline.hrvDays >= 14) ? opts.recoveryBaseline.hrvRmssd : null
  return recoveryScore({
    hrvRmssd: w?.recovery?.hrvRmssd ?? null, hrvBaseline,
    sleepHours: w?.sleep?.hours ?? null, sleepEfficiencyPct: w?.sleep?.efficiencyPct ?? null,
    avgStress: w?.recovery?.avgStress ?? null, felt,
  }).score
}

// One day's four pillar scalars (for the 14-day series). Vitality scores even on a
// wearable/felt-recovery-only day (no functional check-in) via the recovery factor.
function dayScores(dayMeals: MealLog[], fnEntry: CheckinHistoryEntry | null, gutEntry: GutHistoryEntry | null, p: TrendsProfile, recovery: number | null) {
  const energy = feltMetric(fnEntry, 'energy')
  const vitality = (fnEntry || recovery != null)
    ? vitalityScore({ energyScore: energy, moodScore: feltMetric(fnEntry, 'mood'), sleepScore: feltMetric(fnEntry, 'sleep'), stressScore: feltMetric(fnEntry, 'stress'), recoveryScore: recovery }).score
    : null
  const { micro, macro } = nutritionPcts(dayMeals, p)
  const g = gutSignalsForEntry(gutEntry, dayMeals)
  return {
    vitality,
    metabolic: metabolicScore({ meals: dayMeals, feltDigestion: g.comfort, energyScore: energy }).score,
    nutrition: nutritionScore({ meals: dayMeals, microCoveragePct: micro, macroProximityPct: macro }).score,
    gut: gutScore({ comfort: g.comfort, stool: g.stool, reactions: g.reactions }).score,
  }
}

export function deriveTrends(input: DeriveTrendsInput): TrendsResult {
  const { meals, metricHistory, gutHistory, today, checkin, profile, now } = input
  const todayFn = today?.todayFunctional ?? null
  const todayGut = today?.todayGut ?? null

  // ---- current standing (window C for meal-derived factors) ----
  const win = windowMeals(meals, now)
  const energyToday = feltMetric(todayFn, 'energy')
  const { micro: winMicro, macro: winMacro } = nutritionPcts(win, profile)
  const gutNow = gutSignalsCurrent(todayGut, gutHistory, win)

  // Patient-local day keys — same convention as checkin_date writers AND
  // mealsOnDay's toDateString bucketing, so a column never mixes two windows.
  const isoDate = (d: Date) => localDayISO(d)
  const wopts = { wearableByDay: input.wearableByDay, recoveryBaseline: input.recoveryBaseline }
  const todayRecovery = recoveryFor(checkin, isoDate(now), wopts)

  const vitalityCore = vitalityScore(
    (todayFn || todayRecovery != null)
      ? { energyScore: energyToday, moodScore: feltMetric(todayFn, 'mood'), sleepScore: feltMetric(todayFn, 'sleep'), stressScore: feltMetric(todayFn, 'stress'), recoveryScore: todayRecovery }
      : { energyScore: null, moodScore: null, sleepScore: null, stressScore: null, recoveryScore: todayRecovery },
  )
  const metabolicCore = metabolicScore({ meals: win, feltDigestion: gutNow.comfort, energyScore: energyToday })
  const nutritionCore = nutritionScore({ meals: win, microCoveragePct: winMicro, macroProximityPct: winMacro })
  const gutCore = gutScore({ comfort: gutNow.comfort, stool: gutNow.stool, reactions: gutNow.reactions })

  // ---- 14-day series (recompute each pillar over THAT day's data) ----
  const fnByDate = new Map(metricHistory.map((e) => [e.date, e]))
  const gutByDate = new Map(gutHistory.map((e) => [e.date, e]))
  const series = { vitality: [] as (number | null)[], metabolic: [] as (number | null)[], nutrition: [] as (number | null)[], gut: [] as (number | null)[] }
  for (const day of lastNDays(now, 14)) {
    const isToday = day.toDateString() === now.toDateString()
    const fnEntry = isToday ? todayFn : fnByDate.get(isoDate(day)) ?? null
    const gutEntry = isToday ? todayGut : gutByDate.get(isoDate(day)) ?? null
    const rec = recoveryFor(isToday ? checkin : fnEntry, isoDate(day), wopts)
    const s = dayScores(mealsOnDay(meals, day), fnEntry, gutEntry, profile, rec)
    series.vitality.push(s.vitality)
    series.metabolic.push(s.metabolic)
    series.nutrition.push(s.nutrition)
    series.gut.push(s.gut)
  }
  // Per-day composite from the SAME per-day pillar scalars (hasWearable only
  // affects the confidence basis, never the score).
  const compositeSeries14d = series.vitality.map((v, i) =>
    functionalComposite({ vitality: v, metabolic: series.metabolic[i], nutrition: series.nutrition[i] }).score
  )

  const hasWearable = !!input.wearableByDay && input.wearableByDay.size > 0
  const composite = functionalComposite({ vitality: vitalityCore.score, metabolic: metabolicCore.score, nutrition: nutritionCore.score, hasWearable })
  // Pin today's column to the headline composite: the standing pillars use the
  // current meal window (not just today's meals), and the crown's big number
  // must equal the endpoint of the line under it (M2).
  if (compositeSeries14d.length && composite.score != null) {
    compositeSeries14d[compositeSeries14d.length - 1] = composite.score
  }

  const view = (core: ScoreCore, label: string, s: (number | null)[]): ScoreBreakdown => ({ ...core, series14d: s, tip: ruleBasedTip(core) })
  return {
    vitality: view(vitalityCore, 'Vitality', series.vitality),
    metabolic: view(metabolicCore, 'Metabolic', series.metabolic),
    nutrition: view(nutritionCore, 'Nutrition', series.nutrition),
    gut: view(gutCore, 'Gut', series.gut),
    composite,
    compositeSeries14d,
  }
}
