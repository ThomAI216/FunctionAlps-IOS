// Shared scoring contract. A score = available-case weighted mean of its present
// factors (value !== null); missing factors drop out and remaining weights
// renormalize. No present factors -> null. All values are 0-100.
export type FactorStatus = 'good' | 'watch' | 'bad'

export interface ScoreFactor {
  key: string
  label: string
  value: number | null // 0-100; null = no data this window
  weight: number
  status: FactorStatus
  detail?: string
}

export interface ScoreCore {
  score: number | null
  factors: ScoreFactor[]
}

// 3-line tip (spec §6.4): summary (white) · good (green) · bad (red).
export interface ScoreTip {
  summary: string
  good: string
  bad: string
}

// The full per-score view consumed by the expansion: core + 14-day series + tip.
export interface ScoreBreakdown extends ScoreCore {
  series14d: (number | null)[]
  tip: ScoreTip | null
}

// Thresholds are central + tunable (spec §1). null reads as 'watch' (neutral).
export function statusFor(value: number | null): FactorStatus {
  if (value === null) return 'watch'
  if (value >= 67) return 'good'
  if (value >= 34) return 'watch'
  return 'bad'
}

export function availableCaseScore(factors: ScoreFactor[]): number | null {
  const present = factors.filter((f) => f.value !== null)
  if (present.length === 0) return null
  const totalW = present.reduce((s, f) => s + f.weight, 0)
  if (totalW === 0) return null
  const weighted = present.reduce((s, f) => s + (f.value as number) * f.weight, 0)
  return Math.round(weighted / totalW)
}

// Convenience: build a ScoreFactor with status derived from value.
export function factor(key: string, label: string, value: number | null, weight: number, detail?: string): ScoreFactor {
  return { key, label, value, weight, status: statusFor(value), detail }
}
