// Gut Intelligence score (Trends, standalone card). Ties the gut check-in markers
// (symptoms), how-meals-felt (reactions), and meal digestibility together. The
// wearable Recovery factor is dormant. Sub-scores are resolved by the caller.
import { factor, availableCaseScore, type ScoreCore } from './score-core.ts'

export interface GutInput {
  comfort: number | null    // felt gut_comfort
  reactions: number | null  // mealReactionsScore (meals-only)
  stool: number | null      // felt gut_stool, legacy marker-mean fallback
}

export function gutScore(input: GutInput): ScoreCore {
  const factors = [
    factor('comfort', 'Digestion comfort', input.comfort, 0.4),
    factor('reactions', 'Post-meal reactions', input.reactions, 0.3),
    factor('stool', 'Stool quality', input.stool, 0.3),
  ]
  return { score: availableCaseScore(factors), factors }
}

export interface MealReaction {
  reactionOverall?: number // 0-10 positive felt reaction
  reactionBloating?: number // 0-10, higher = worse
  reactionGasBurden?: number // 0-10, higher = worse
  reactionFullness?: number // 0-10, higher = worse
}

const clampR = (n: number) => Math.max(0, Math.min(100, n))

/** 0-100 "how meals felt" from nb_meal_reactions: overall felt (x10) minus a
 *  modest discomfort penalty from bloating/gas/fullness. Null when no reactions. */
export function mealReactionsScore(meals: MealReaction[]): number | null {
  const reacted = meals.filter((m) => typeof m.reactionOverall === 'number')
  if (!reacted.length) return null
  const per = reacted.map((m) => {
    const felt = (m.reactionOverall as number) * 10
    const disc = [m.reactionBloating, m.reactionGasBurden, m.reactionFullness].filter(
      (v): v is number => typeof v === 'number',
    )
    const penalty = disc.length ? (disc.reduce((s, v) => s + v, 0) / disc.length) * 3 : 0
    return clampR(felt - penalty)
  })
  return Math.round(per.reduce((s, v) => s + v, 0) / per.length)
}
