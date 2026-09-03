// TDEE and macro calculation helpers

type ActivityLevel =
  | 'sedentary'
  | 'lightly_active'
  | 'moderately_active'
  | 'very_active'
  | 'extremely_active'

export const ACTIVITY_LEVELS = [
  { key: 'sedentary' as const, label: 'Sedentary' },
  { key: 'lightly_active' as const, label: 'Lightly Active' },
  { key: 'moderately_active' as const, label: 'Moderately Active' },
  { key: 'very_active' as const, label: 'Very Active' },
  { key: 'extremely_active' as const, label: 'Extremely Active' },
] as const

const NEAT_FACTORS: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  lightly_active: 1.35,
  moderately_active: 1.55,
  very_active: 1.7,
  extremely_active: 1.9,
}

function harrisBenedictBMR(
  weightKg: number,
  heightCm: number,
  age: number,
  sex: 'male' | 'female'
): number {
  if (sex === 'male') {
    return 88.362 + 13.397 * weightKg + 4.799 * heightCm - 5.677 * age
  }
  return 447.593 + 9.247 * weightKg + 3.098 * heightCm - 4.33 * age
}

export function katchMcArdleBMR(weightKg: number, bfPercent: number): number {
  const lbm = weightKg * (1 - bfPercent / 100)
  return 370 + 21.6 * lbm
}

// Exported so the onboarding Energy Compass can show the BMR that sits under the
// TDEE it displays. Same function the TDEE path uses — never a second formula.
export function calculateBMR(
  weightKg: number,
  heightCm: number,
  age: number,
  sex: 'male' | 'female',
  bfPercent?: number | null
): number {
  if (bfPercent != null && bfPercent > 0) {
    return katchMcArdleBMR(weightKg, bfPercent)
  }
  return harrisBenedictBMR(weightKg, heightCm, age, sex)
}

export function calculateTDEE(
  weightKg: number,
  heightCm: number,
  age: number,
  sex: 'male' | 'female',
  activityLevel: string,
  bfPercent?: number | null
): number {
  const bmr = calculateBMR(weightKg, heightCm, age, sex, bfPercent)
  const factor = NEAT_FACTORS[activityLevel as ActivityLevel] ?? 1.55
  return Math.round(bmr * factor)
}

export interface MacroTargets {
  proteinG: number
  carbsG: number
  fatG: number
  calories: number
}

/**
 * Returns BF%-scaled calorie offset for a goal.
 * Larger deficits are safer when BF% is higher (more fat to lose).
 * Larger surpluses are appropriate when BF% is lower (leaner individuals can gain more cleanly).
 */
export function getGoalOffset(
  goal: 'cut' | 'maintain' | 'build',
  bfPercent: number
): number {
  if (goal === 'maintain') return 0
  if (goal === 'cut') {
    if (bfPercent < 18) return -300
    if (bfPercent <= 25) return -400
    return -500
  }
  // build
  if (bfPercent > 25) return +150
  if (bfPercent >= 18) return +250
  return +300
}

/**
 * Daily macro model:
 * - Women: 1.5g protein per kg
 * - Men: 1.8g protein per kg
 * - Fat: 40% of daily calories
 * - Carbs: remaining calories
 * - Carbs floor: 0g
 * - Calorie offset is scaled by body fat % via getGoalOffset()
 */
export function calculateGoalMacros(
  tdee: number,
  weightKg: number,
  sex: 'male' | 'female',
  goal: 'cut' | 'maintain' | 'build',
  bfPercent?: number | null
): MacroTargets {
  const bf = bfPercent ?? 22
  const offset = getGoalOffset(goal, bf)
  const goalCalories = tdee + offset

  const proteinPerKg = sex === 'female' ? 1.5 : 1.8
  const proteinG = Math.round(weightKg * proteinPerKg)
  const proteinKcal = proteinG * 4

  const fatKcal = goalCalories * 0.4
  const fatG = Math.round(fatKcal / 9)

  const carbsKcal = goalCalories - proteinKcal - fatKcal
  const carbsG = Math.max(0, Math.round(carbsKcal / 4))

  return {
    proteinG,
    carbsG,
    fatG,
    calories: Math.round(goalCalories),
  }
}

/**
 * Legacy helper - returns simple protein/carbs/fat percentages of TDEE.
 * Used in older components. Prefer calculateGoalMacros for new code.
 */
export function calculateMacros(tdee: number) {
  return {
    protein: Math.round((tdee * 0.3) / 4),
    carbs: Math.round((tdee * 0.4) / 4),
    fat: Math.round((tdee * 0.3) / 9),
  }
}

export function explainCalories(tdee: number, goal: 'cut' | 'maintain' | 'build'): string {
  const target = goal === 'cut' ? tdee - 400 : goal === 'build' ? tdee + 250 : tdee
  if (goal === 'cut') {
    return `Your body burns ~${tdee} kcal/day at your activity level. We set your target at ${target} kcal to create a moderate deficit for steady, sustainable fat loss without muscle loss.`
  }
  if (goal === 'build') {
    return `Your body burns ~${tdee} kcal/day. We add ${target - tdee} kcal above maintenance to fuel muscle synthesis and training recovery, without excess fat gain.`
  }
  return `Your body burns ~${tdee} kcal/day. Your target matches this to maintain your current body composition while optimising nutrient quality.`
}

export function explainProtein(proteinG: number, weightKg: number, sex: 'male' | 'female'): string {
  const gPerKg = sex === 'female' ? 1.5 : 1.8
  return `Protein is your anchor macro. Women are set at 1.5g/kg/day and men at 1.8g/kg/day. At ${Math.round(weightKg)}kg, your target is ${proteinG}g/day to support lean mass, satiety, and recovery.`
}

export function explainCarbs(carbsG: number, goal: 'cut' | 'maintain' | 'build'): string {
  if (goal === 'build') {
    return `Carbohydrates are your primary fuel source for training and recovery. Your target is ${carbsG}g/day, calculated from the calories remaining after protein and fat are set.`
  }
  if (goal === 'cut') {
    return `Carbohydrates are set from the calories remaining after protein and fat are assigned. Your target is ${carbsG}g/day, which keeps your intake coherent during a cut.`
  }
  return `Carbohydrates fuel your brain and daily activity. Your target is ${carbsG}g/day based on the calories remaining after protein and fat.`
}

export function explainFat(fatG: number, goal: 'cut' | 'maintain' | 'build'): string {
  return `Dietary fat is essential for hormone production, fat-soluble vitamin absorption (A, D, E, K), and sustained energy. Your target of ${fatG}g/day is ${goal === 'cut' ? 'moderate, prioritising satiety without excess calories' : goal === 'build' ? 'set to support anabolic hormones and joint health without crowding out carbs and protein' : 'balanced to support hormone health and energy stability'}.`
}
