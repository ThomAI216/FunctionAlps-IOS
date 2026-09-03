// Shared view-model helpers for the macros card (dashboard) + macros-details page.
// Pure functions — given a nutrition snapshot / store data, produce the display
// model (ring stats, per-meal nutrient score, today's live summary).
import { colors } from '../theme/tokens.ts'
import { localDayISO, engineNow } from '../dates/local-day.ts'
import { MACRO_HUES } from '../theme/nutrition-macros.ts'
import { getConsumedFromLogs, getOverallCoverage } from '../data/nutrients.ts'
import type { MealLog } from '../types/log-store.ts'
import type { CheckinScores } from '../types/daily-store.ts'

export type Sex = 'male' | 'female'

// Card/ring palette: green kcal + V1 macro hues (user choice).
export const MACRO_RING_COLORS = {
  kcal: colors.forestS,
  protein: MACRO_HUES.protein,
  carbs: MACRO_HUES.carbs,
  fat: MACRO_HUES.fat,
} as const

export interface MacroStat {
  key: 'kcal' | 'protein' | 'carbs' | 'fat'
  label: string
  unit: string
  current: number
  target: number
  color: string
  pct: number
}

// Minimal shape we need from buildNutritionSnapshot().
interface SnapshotLike {
  goalCalories: number
  targets: { proteinG: number; carbsG: number; fatG: number; calories: number }
  consumed: { calories: number; protein: number; carbs: number; fat: number }
}

export function buildMacroStats(snapshot: SnapshotLike): MacroStat[] {
  const mk = (
    key: MacroStat['key'],
    label: string,
    unit: string,
    current: number,
    target: number,
    color: string
  ): MacroStat => ({
    key,
    label,
    unit,
    current: Math.round(current),
    target: Math.round(target),
    color,
    pct: target > 0 ? current / target : 0,
  })
  return [
    mk('kcal', 'Calories', '', snapshot.consumed.calories, snapshot.goalCalories, MACRO_RING_COLORS.kcal),
    mk('protein', 'Protein', 'g', snapshot.consumed.protein, snapshot.targets.proteinG, MACRO_RING_COLORS.protein),
    mk('carbs', 'Carbs', 'g', snapshot.consumed.carbs, snapshot.targets.carbsG, MACRO_RING_COLORS.carbs),
    mk('fat', 'Fat', 'g', snapshot.consumed.fat, snapshot.targets.fatG, MACRO_RING_COLORS.fat),
  ]
}

/**
 * Per-meal micronutrient score (0–100), or null when the meal carries no
 * tracked micronutrient data. A meal is "expected" to contribute its share
 * (1 / mealsToday) of the daily RDA, so the meal's daily-RDA coverage is scaled
 * up by that share to read on a per-meal 0–100 scale.
 */
// Macro adherence /100 = mean proximity of protein/carbs/fat to target (kcal
// excluded, over-target capped at 100%). Extracted from MacrosTodayCard so the
// Trends Nutrition score can reuse it (lib/health/* must not import components).
export function macroProximityScore(stats: { key: string; pct: number }[]): number | null {
  const pcf = stats.filter((m) => m.key !== 'kcal')
  if (!pcf.length) return null
  return Math.round((pcf.reduce((s, m) => s + Math.min(1, m.pct), 0) / pcf.length) * 100)
}

export function mealNutrientScore(meal: Pick<MealLog, 'micros'>, sex: Sex, mealsToday: number): number | null {
  const consumed = getConsumedFromLogs([meal])
  const hasMicro = Object.values(consumed).some((v) => v > 0)
  if (!hasMicro) return null
  const dailyCoverage = getOverallCoverage(sex, consumed) // 0–100 of the full daily RDA
  const share = 1 / Math.max(1, mealsToday)
  return Math.max(0, Math.min(100, Math.round(dailyCoverage / share)))
}

export interface TodaySummaryMetric {
  label: string
  value: string
  tone: 'good' | 'watch'
}
export interface TodaySummary {
  title: string
  note: string
  metrics: TodaySummaryMetric[]
}

function isoDate(d: string | Date): string {
  return localDayISO(new Date(d)) // patient-local — "today" must match the user's clock
}

/**
 * Live "today" summary derived from the current check-in. Returns null when
 * there is no check-in completed today (caller shows an empty state).
 */
export function buildTodaySummary(
  checkin: CheckinScores | null,
  checkinCompletedAt: string | null,
  mealsCount: number,
  nowISO?: string
): TodaySummary | null {
  if (!checkin || !checkinCompletedAt) return null
  const today = isoDate(nowISO ?? engineNow())
  if (isoDate(checkinCompletedAt) !== today) return null

  // 1–5 mountain-scale thresholds (mirrors daily-store's deriveDailySummary;
  // lower is better for inflammation).
  const digestionSignal = checkin.digestion >= 4 ? 'steady' : checkin.digestion >= 3 ? 'mixed' : 'fragile'
  const inflammationSignal = checkin.inflammation <= 2 ? 'calmer' : checkin.inflammation <= 3 ? 'moderate' : 'reactive'
  const note = `Digestion felt ${digestionSignal} with ${inflammationSignal} inflammation signals. You logged ${mealsCount} meal${mealsCount === 1 ? '' : 's'} today.`
  const inflLabel = checkin.inflammation <= 2 ? 'Low' : checkin.inflammation <= 3 ? 'Moderate' : 'High'

  return {
    title: 'Today at a glance',
    note,
    metrics: [
      { label: 'Digestion', value: String(checkin.digestion), tone: checkin.digestion >= 4 ? 'good' : 'watch' },
      { label: 'Inflammation', value: inflLabel, tone: checkin.inflammation <= 3 ? 'good' : 'watch' },
      { label: 'Energy', value: String(checkin.energy), tone: checkin.energy >= 4 ? 'good' : 'watch' },
    ],
  }
}
