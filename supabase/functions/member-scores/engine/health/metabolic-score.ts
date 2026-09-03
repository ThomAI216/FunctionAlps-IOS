// Metabolic score (Trends): meal-driven + gut-driven. Digestion = 65% feltGut +
// 35% meal I/G/D avg; Inflammation/Glycemic = meal means; Energy shared w/ Vitality.
import { factor, availableCaseScore, type ScoreCore } from './score-core.ts'
import { mealQuality, type MealScores } from './nutrition-score.ts'

export interface MetabolicInput {
  meals: { scores?: MealScores | null }[]
  feltDigestion: number | null // gutDigestionScore today, else digestionSlider*10 (caller resolves)
  energyScore: number | null
}

const round = (n: number) => Math.round(n)
const mean = (xs: number[]) => xs.reduce((s, v) => s + v, 0) / xs.length

export function metabolicScore(input: MetabolicInput): ScoreCore {
  const scored = input.meals.map((m) => m.scores).filter((s): s is MealScores => s != null)
  const mealIGD = scored.length ? round(mean(scored.map(mealQuality))) : null
  const inflammation = scored.length ? round(mean(scored.map((s) => s.inflammation))) : null
  const glycemic = scored.length ? round(mean(scored.map((s) => s.glycemic))) : null

  // Digestion: available-case blend of feltGut (0.65) + mealIGD (0.35).
  let digestion: number | null = null
  const fg = input.feltDigestion
  if (fg !== null && mealIGD !== null) digestion = round(0.65 * fg + 0.35 * mealIGD)
  else if (fg !== null) digestion = fg
  else if (mealIGD !== null) digestion = mealIGD

  const factors = [
    factor('digestion', 'Digestion', digestion, 0.20),
    factor('inflammation', 'Inflammation', inflammation, 0.25),
    factor('glycemic', 'Glycemic', glycemic, 0.25),
    factor('energy', 'Energy', input.energyScore, 0.30),
  ]
  return { score: availableCaseScore(factors), factors }
}
