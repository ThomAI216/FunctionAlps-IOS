// Nutrition score (Trends). Available-case mean of: meal quality (0-100 I/G/D
// mean, DIRECT — meal scores are 0-100 higher=better), micro coverage, macro
// proximity, meal timing. Caller passes window-C meals + micro/macro percents.
import { factor, availableCaseScore, type ScoreCore } from './score-core.ts'
import { mealTimingScore } from './meal-timing.ts'
import type { MealScores } from '../types/log-store.ts'

export type { MealScores }

export interface NutritionInput {
  meals: { scores?: MealScores | null; timestamp: string }[]
  microCoveragePct: number | null
  macroProximityPct: number | null
}

const clamp = (n: number) => Math.max(0, Math.min(100, n))

/** 0-100 quality of one meal — DIRECT mean of its 0-100 higher=better signals. */
export function mealQuality(s: MealScores): number {
  return clamp((s.inflammation + s.glycemic + s.digestion) / 3)
}

export function nutritionScore(input: NutritionInput): ScoreCore {
  const scored = input.meals.filter((m): m is { scores: MealScores; timestamp: string } => m.scores != null)
  const mealQ = scored.length ? Math.round(scored.reduce((s, m) => s + mealQuality(m.scores), 0) / scored.length) : null
  const timing = mealTimingScore(input.meals)

  const factors = [
    factor('mealQuality', 'Meal quality', mealQ, 0.3),
    factor('micro', 'Micro coverage', input.microCoveragePct, 0.3),
    factor('macro', 'Macro proximity', input.macroProximityPct, 0.25),
    factor('timing', 'Meal timing', timing, 0.15),
  ]
  return { score: availableCaseScore(factors), factors }
}

// Back-compat shim for the pre-Phase-2 health.tsx caller (old calorie-based
// `macroAdherencePct` is mapped into the new macro slot until Phase 2 rewires it).
export interface LegacyNutritionInput {
  microCoveragePct: number | null
  macroAdherencePct: number | null
  meals: { scores?: MealScores | null; timestamp?: string }[]
}
export function nutritionPillarScore(input: LegacyNutritionInput): number | null {
  return nutritionScore({
    meals: input.meals.map((m) => ({ scores: m.scores ?? null, timestamp: m.timestamp ?? new Date(0).toISOString() })),
    microCoveragePct: input.microCoveragePct,
    macroProximityPct: input.macroAdherencePct,
  }).score
}
