// Warm-surface / clinical-depth pillar model. Each functional check-in signal
// feeds exactly ONE pillar (no double-counting). Nutrition is meal-derived and
// supplied separately (see nutrition-score.ts) — pillarScore returns null for it.
import { HEALTH_DETAILS, type HealthMetricKey } from '../data/health-details.ts'
import type { CheckinHistoryEntry } from '../types/daily-store.ts'
import { overallTrend, type MetricEntry } from './overall-trend.ts'

export type PillarKey = 'vitality' | 'metabolic' | 'nutrition'
export type ClinicalNode = 'Energy' | 'Communication' | 'Defense & Repair' | 'Transport' | 'Assimilation'

export interface PillarDef {
  key: PillarKey
  title: string
  caption: string
  nodes: ClinicalNode[]
  metrics: HealthMetricKey[]
}

export const PILLAR_DEFS: Record<PillarKey, PillarDef> = {
  vitality: {
    key: 'vitality',
    title: 'Vitality',
    caption: 'How you feel & show up',
    nodes: ['Energy', 'Communication'],
    metrics: ['energy', 'mood', 'sleep', 'stress'],
  },
  metabolic: {
    key: 'metabolic',
    title: 'Metabolic',
    caption: 'How your engine runs on fuel',
    nodes: ['Defense & Repair', 'Energy', 'Transport'],
    metrics: ['digestion', 'inflammation'],
  },
  nutrition: {
    key: 'nutrition',
    title: 'Nutrition',
    caption: 'How well you fuel',
    nodes: ['Assimilation'],
    metrics: [],
  },
}

/** Pillar accent pastels — mirror the home top card's V/M/D palette. */
export const PILLAR_TINT: Record<PillarKey, string> = {
  vitality: '#E6CF85', // pastel yellow
  metabolic: '#E0A0A0', // pastel red
  nutrition: '#A6C2E0', // pastel blue
}

/** 0–100 mean of a pillar's metric scores. Null for nutrition (meal-derived). */
export function pillarScore(entry: MetricEntry, key: PillarKey): number | null {
  const { metrics } = PILLAR_DEFS[key]
  if (metrics.length === 0) return null
  const vals = metrics.map((m) => {
    const cfg = HEALTH_DETAILS[m]
    return cfg.scoreFromValue(cfg.getCurrentValue(entry))
  })
  return Math.round(vals.reduce((s, v) => s + v, 0) / vals.length)
}

/** One point per check-in day, today appended last. Empty for nutrition. */
export function buildPillarSeries(
  history: CheckinHistoryEntry[],
  today: MetricEntry | null,
  key: PillarKey,
): number[] {
  if (PILLAR_DEFS[key].metrics.length === 0) return []
  const series = history.map((e) => pillarScore(e, key) as number)
  if (today) series.push(pillarScore(today, key) as number)
  return series
}

export interface PillarSummary {
  score: number | null
  trend: 'up' | 'down' | 'flat' | null
  delta: number | null
  points: number
}

export function pillarSummary(
  history: CheckinHistoryEntry[],
  today: MetricEntry | null,
  key: PillarKey,
): PillarSummary {
  const series = buildPillarSeries(history, today, key)
  if (series.length === 0) return { score: null, trend: null, delta: null, points: 0 }
  let delta: number | null = null
  if (series.length >= 2) {
    const half = Math.floor(series.length / 2)
    const avg = (xs: number[]) => xs.reduce((s, v) => s + v, 0) / xs.length
    delta = Math.round(avg(series.slice(half)) - avg(series.slice(0, half)))
  }
  return { score: series[series.length - 1], trend: overallTrend(series), delta, points: series.length }
}
