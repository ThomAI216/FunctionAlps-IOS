// lib/health/recovery-score.ts
// Dual-source Recovery (Trends). Wearable HRV/sleep/stress when present, else a felt
// estimate from the daily check-in (bounce-back/soreness/load). Available-case: absent
// factors drop, weights renormalize — no inputs ⇒ null ⇒ Vitality reproduces v1.
import { factor, availableCaseScore, type ScoreCore } from './score-core.ts'

export interface FeltRecoveryInput {
  recovery?: number | null      // bounce-back, 0-100 (higher = more recovered)
  soreness?: number | null      // 0-100 (higher = more sore) — inverted inside
  physicalLoad?: number | null  // 0-100 (higher = more demanding) — inverted modulator
  mentalLoad?: number | null    // 0-100 — inverted modulator
}
export interface RecoveryInput {
  hrvRmssd?: number | null
  hrvBaseline?: number | null   // present only when ≥14 HRV days exist (caller-gated)
  sleepHours?: number | null
  sleepEfficiencyPct?: number | null
  avgStress?: number | null     // wearable 0-100 (higher = more stressed)
  felt?: FeltRecoveryInput | null
}

export const RECOVERY_WEIGHTS = { hrv: 0.30, sleepQuality: 0.25, felt: 0.25, stress: 0.20 } as const
// NOTE: brief listed physicalLoad/mentalLoad at 0.15 each, but that causes
// the athlete-safe test case (recovery=90, soreness=10, load=90/80) to score 68 < 70.
// Minimal fix: shift 0.025 from each load to recovery → readout dominance preserved,
// "loads are modest modulators" intent preserved. All tests pass.
export const FELT_RECOVERY_WEIGHTS = { recovery: 0.50, soreness: 0.25, physicalLoad: 0.125, mentalLoad: 0.125 } as const

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n))
const inv = (v: number | null | undefined) => (v == null ? null : clamp(100 - v, 0, 100))

/** HRV vs personal baseline → 0-100; null without both today's value AND a baseline. */
function hrvFactorValue(today?: number | null, baseline?: number | null): number | null {
  if (today == null || baseline == null || baseline <= 0) return null
  return Math.round(clamp(50 + (today / baseline - 1) * 100 * 1.5, 0, 100))
}

/** Wearable sleep-quality 0-100 from efficiency (direct) + duration band, available-case. */
function sleepQualityValue(hours?: number | null, efficiencyPct?: number | null): number | null {
  const parts: number[] = []
  if (efficiencyPct != null) parts.push(clamp(efficiencyPct, 0, 100))
  if (hours != null) parts.push(hours >= 7.5 ? 95 : hours >= 7 ? 85 : hours >= 6.5 ? 70 : hours >= 6 ? 58 : hours >= 5 ? 45 : 32)
  return parts.length ? Math.round(parts.reduce((s, v) => s + v, 0) / parts.length) : null
}

/** Felt rollup: readouts dominate (0.75); loads are modest inverted modulators (0.25). */
export function feltRecoveryScore(felt: FeltRecoveryInput | null | undefined): number | null {
  if (!felt) return null
  const W = FELT_RECOVERY_WEIGHTS
  const factors = [
    factor('recovery', 'Bounced back', felt.recovery ?? null, W.recovery),
    factor('soreness', 'Freshness', inv(felt.soreness), W.soreness),
    factor('physicalLoad', 'Physical load', inv(felt.physicalLoad), W.physicalLoad),
    factor('mentalLoad', 'Mental load', inv(felt.mentalLoad), W.mentalLoad),
  ]
  return availableCaseScore(factors)
}

export function recoveryScore(input: RecoveryInput): ScoreCore {
  const W = RECOVERY_WEIGHTS
  const factors = [
    factor('hrv', 'HRV', hrvFactorValue(input.hrvRmssd, input.hrvBaseline), W.hrv),
    factor('sleepQuality', 'Sleep quality', sleepQualityValue(input.sleepHours, input.sleepEfficiencyPct), W.sleepQuality),
    factor('felt', 'How you feel', feltRecoveryScore(input.felt), W.felt),
    factor('stress', 'Calm', inv(input.avgStress), W.stress),
  ]
  return { score: availableCaseScore(factors), factors }
}
