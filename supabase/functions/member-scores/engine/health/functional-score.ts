// The crown composite. Weighted mean of the three pillars with available-case
// renormalization: missing pillars drop out and remaining weights rescale to
// sum to 1. Longevity is intentionally NOT part of this.
import type { PillarKey } from './pillars.ts'

export type ConfidenceBasis = 'none' | 'checkins' | 'checkins+nutrition' | 'checkins+nutrition+wearable'

export interface CompositeInput {
  vitality: number | null
  metabolic: number | null
  nutrition: number | null
  hasWearable?: boolean
}

export interface Composite {
  score: number | null
  basis: ConfidenceBasis
  pillars: Record<PillarKey, number | null>
}

export const PILLAR_WEIGHTS: Record<PillarKey, number> = {
  vitality: 0.42,
  metabolic: 0.33,
  nutrition: 0.25,
}

export function functionalComposite(input: CompositeInput): Composite {
  const pillars: Record<PillarKey, number | null> = {
    vitality: input.vitality,
    metabolic: input.metabolic,
    nutrition: input.nutrition,
  }
  const present = (Object.keys(pillars) as PillarKey[]).filter((k) => pillars[k] !== null)
  let score: number | null = null
  if (present.length) {
    const totalW = present.reduce((s, k) => s + PILLAR_WEIGHTS[k], 0)
    const weighted = present.reduce((s, k) => s + (pillars[k] as number) * PILLAR_WEIGHTS[k], 0)
    score = Math.round(weighted / totalW)
  }

  let basis: ConfidenceBasis = 'none'
  if (present.length) {
    if (input.hasWearable) basis = 'checkins+nutrition+wearable'
    else if (pillars.nutrition !== null) basis = 'checkins+nutrition'
    else basis = 'checkins'
  }
  return { score, basis, pillars }
}
