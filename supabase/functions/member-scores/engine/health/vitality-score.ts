// Vitality score (Trends). Self-report Energy/Mood/Sleep/Stress + a dormant
// wearable Recovery factor. With no wearable, Recovery.value=null is dropped and
// the available-case mean reproduces the legacy mean(energy,mood,sleep,stress).
import { factor, availableCaseScore, type ScoreCore } from './score-core.ts'

export interface VitalityInput {
  energyScore: number | null
  moodScore: number | null
  sleepScore: number | null
  stressScore: number | null
  recoveryScore?: number | null // wearable-only; undefined/null when dormant
}

export function vitalityScore(input: VitalityInput): ScoreCore {
  const factors = [
    factor('energy', 'Energy', input.energyScore, 0.25),
    factor('mood', 'Mood', input.moodScore, 0.25),
    factor('sleep', 'Sleep', input.sleepScore, 0.25),
    factor('stress', 'Stress', input.stressScore, 0.25),
    factor('recovery', 'Recovery', input.recoveryScore ?? null, 0.20),
  ]
  return { score: availableCaseScore(factors), factors }
}
