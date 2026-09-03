// lib/wearables/metrics.ts
// Single source of truth for which Thryve metrics the algorithm reads + how multiple
// device sources collapse per (patient, day). Mirrors the SQL in migration 067.
// Risk layer (2251-2258, 6406) intentionally absent — clinical-only.

export const SECONDS_PER_HOUR = 3600 // ThryveMainSleep*Duration are LONG seconds (validate unit on first real data)

/** Metric name (catalog `name`) → how to collapse across device sources. */
export const AGG_RULE = {
  // cumulative → MAX across sources (avoid double-count)
  Steps: 'max', StepsManual: 'max',
  ActiveDurationManual: 'max', ActivityDuration: 'max',
  ActiveBurnedCalories: 'max', CoveredDistance: 'max',
  // point-in-time → MEDIAN across sources
  HeartRateResting: 'median', Rmssd: 'median', RmssdSleep: 'median',
  AverageStress: 'median', RespirationRate: 'median', MetabolicEquivalentMax5Min: 'median',
  // sleep (single Thryve source) → MAX is a no-op collapse
  ThryveMainSleepDuration: 'max', ThryveMainSleepInBedDuration: 'max',
  ThryveMainSleepAwakeDuration: 'max', ThryveMainSleepInterruptions: 'max',
  ThryveMainSleepLatency: 'max', ThryveMainSleepREMDuration: 'max',
  ThryveMainSleepDeepDuration: 'max',
} as const

export type WearableMetric = keyof typeof AGG_RULE

export interface WearableDay {
  date: string // YYYY-MM-DD
  sleep: { hours: number; efficiencyPct: number | null; interruptions: number | null; latencyMin: number | null; remMin: number | null; deepMin: number | null } | null
  recovery: { restingHr: number | null; hrvRmssd: number | null; avgStress: number | null } | null
  activity: { steps: number | null; activeMinutes: number | null; activeEnergyKcal: number | null; distanceM: number | null; metMax: number | null } | null
  respirationRate: number | null
  sourceIds: number[]
}

export interface RecoveryBaseline {
  restingHr: number | null
  hrvRmssd: number | null
  hrvDays: number // count of days with HRV in the window → gates the personal-baseline HRV factor
}
