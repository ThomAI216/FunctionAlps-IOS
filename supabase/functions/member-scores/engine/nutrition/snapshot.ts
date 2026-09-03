import { getConsumedFromLogs, getNutrientGaps, getOverallCoverage } from '../data/nutrients.ts'
import type { MealLog } from '../types/log-store.ts'
import { calculateGoalMacros, calculateTDEE } from '../utils/tdee.ts'

export type Sex = 'male' | 'female'

interface SnapshotArgs {
  meals: MealLog[]
  sex: Sex
  weightKg: number
  heightCm: number
  age: number
  activityLevel: string
  goal: 'build' | 'cut' | 'maintain'
  bfPercent?: number | null
  customMacros?: { proteinG?: number; carbsG?: number; fatG?: number; calories?: number } | null
  customCalorieOffset?: number | null
  // DB-authoritative targets (compute_macro_targets trigger) — preferred over the
  // client formula when present, so every snapshot surface reads the single source.
  dbMacroTargets?: { tdee: number; calories: number; proteinG: number; carbsG: number; fatG: number } | null
}

export function buildNutritionSnapshot({
  meals,
  sex,
  weightKg,
  heightCm,
  age,
  activityLevel,
  goal,
  bfPercent,
  customMacros,
  customCalorieOffset,
  dbMacroTargets,
}: SnapshotArgs) {
  const computedTdee = calculateTDEE(weightKg, heightCm, age, sex, activityLevel, bfPercent ?? null)
  const calculated = calculateGoalMacros(computedTdee, weightKg, sex, goal, bfPercent ?? null)
  const customApplied = customMacros
    ? {
        proteinG: customMacros.proteinG ?? calculated.proteinG,
        carbsG: customMacros.carbsG ?? calculated.carbsG,
        fatG: customMacros.fatG ?? calculated.fatG,
        calories: customMacros.calories ?? calculated.calories,
      }
    : calculated
  // DB-authoritative when the trigger has computed the row (single source of
  // truth); else the identical client formula with any custom overrides.
  const tdee = dbMacroTargets?.tdee ?? computedTdee
  const targets = dbMacroTargets
    ? {
        proteinG: dbMacroTargets.proteinG,
        carbsG: dbMacroTargets.carbsG,
        fatG: dbMacroTargets.fatG,
        calories: dbMacroTargets.calories,
      }
    : customApplied
  // goalCalories: DB target wins; else a custom offset over the goal-derived offset.
  const goalCalories = dbMacroTargets
    ? dbMacroTargets.calories
    : customCalorieOffset != null
      ? computedTdee + customCalorieOffset
      : customApplied.calories

  const consumedCalories = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedCalories ?? 0), 0))
  const consumedProtein = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedProtein ?? 0), 0))
  const consumedCarbs = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedCarbs ?? 0), 0))
  const consumedFat = Math.round(meals.reduce((sum, meal) => sum + (meal.estimatedFat ?? 0), 0))
  const consumedFiber = Math.round(meals.reduce((sum, meal) => sum + (meal.micros?.fiber_g ?? 0), 0))

  const consumedMicros = getConsumedFromLogs(meals)
  const microPct = getOverallCoverage(sex, consumedMicros)
  const microGaps = getNutrientGaps(0.7, sex, 10, consumedMicros)

  const fiberTarget = Math.max(25, Math.round((targets.calories / 1000) * 14))

  return {
    tdee,
    goalCalories,
    targets,
    consumed: {
      calories: consumedCalories,
      protein: consumedProtein,
      carbs: consumedCarbs,
      fat: consumedFat,
      fiber: consumedFiber,
      micros: consumedMicros,
    },
    micronutrients: {
      overallPct: microPct,
      gaps: microGaps,
    },
    fiberTarget,
  }
}
