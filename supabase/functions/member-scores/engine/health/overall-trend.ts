// Overall functional trend — pure helpers shared by the home "Functional
// trend" card and the Health Trends top summary. One number per check-in day:
// the canonical Functional Score (0.70·checkin + 0.30·gut on the 1–5 mountain
// scale), IDENTICAL to the DB producer `compute_patient_metrics`, plus a small
// rule-based phrase for the headline.

import { HEALTH_DETAILS, type HealthMetricKey } from '../data/health-details.ts'
import type { CheckinHistoryEntry } from '../types/daily-store.ts'

const METRICS: HealthMetricKey[] = ['digestion', 'inflammation', 'mood', 'energy', 'sleep', 'stress']

/** The six fields the composite needs — CheckinScores (plain numbers) and
 *  CheckinHistoryEntry (nullable: axes the v2 form doesn't capture) both satisfy it. */
export type MetricEntry = { [K in HealthMetricKey]?: number | null }

/** 1–5 mountain scale → 0–100 (mirrors the DB producer's `fa_mountain_score`). */
const mtn = (v: number, invert = false): number =>
  Math.max(0, Math.min(100, ((invert ? 5 - v : v - 1) / 4) * 100))

/** 0–100 functional composite for one check-in — IDENTICAL to the canonical DB
 *  producer (`compute_patient_metrics`): `0.70·checkin + 0.30·gut`, where
 *  `checkin = mean(energy, sleep, mood, stress)` on the 1–5 mountain scale and
 *  `gut` = the gut-intelligence score (0–100) when it overrode digestion that
 *  day, else the digestion slider mountain-scored. Wearable recovery (`bio`)
 *  isn't available client-side, so the 0.70/0.30 fallback applies (the spine
 *  shifts to 0.50/0.20/0.30 once wearables flow). Present-aware, like the producer. */
export function overallScore(entry: MetricEntry): number {
  const present = (v: number | null | undefined): v is number =>
    typeof v === 'number' && Number.isFinite(v)
  const axes: number[] = []
  if (present(entry.energy)) axes.push(mtn(entry.energy))
  if (present(entry.sleep)) axes.push(mtn(entry.sleep))
  if (present(entry.mood)) axes.push(mtn(entry.mood))
  if (present(entry.stress)) axes.push(mtn(entry.stress, true))
  const checkin = axes.length ? axes.reduce((s, v) => s + v, 0) / axes.length : null
  const dig = entry.digestion
  const gut = !present(dig) ? null : dig > 10 ? Math.min(100, dig) : mtn(dig)
  const wC = checkin != null ? 0.7 : 0
  const wG = gut != null ? 0.3 : 0
  const total = wC + wG
  return total === 0 ? 0 : Math.round(((checkin ?? 0) * wC + (gut ?? 0) * wG) / total)
}

/** Past days from Supabase history + today's live check-in (when present).
 *  Renders from the very first point — a one-entry series is still a trend. */
export function buildOverallSeries(
  history: CheckinHistoryEntry[],
  todayCheckin: MetricEntry | null,
): number[] {
  const series = history.map((e) => overallScore(e))
  if (todayCheckin) series.push(overallScore(todayCheckin))
  return series
}

/** Recent half vs prior half; ±3 points = flat. Null = not enough data. */
export function overallTrend(series: number[]): 'up' | 'down' | 'flat' | null {
  if (series.length < 2) return null
  const half = Math.floor(series.length / 2)
  const avg = (xs: number[]) => xs.reduce((s, v) => s + v, 0) / xs.length
  const delta = avg(series.slice(half)) - avg(series.slice(0, half))
  if (delta >= 3) return 'up'
  if (delta <= -3) return 'down'
  return 'flat'
}

/** Biggest mover (by score delta, recent half vs prior half) among the six
 *  metrics — used to make the phrase feel specific rather than generic. */
function biggestMovers(history: CheckinHistoryEntry[], todayCheckin: MetricEntry | null) {
  const entries: MetricEntry[] = [...history, ...(todayCheckin ? [todayCheckin] : [])]
  if (entries.length < 2) return null
  const half = Math.floor(entries.length / 2)
  const avg = (xs: number[]) => xs.reduce((s, v) => s + v, 0) / xs.length
  let best: { key: HealthMetricKey; delta: number } | null = null
  let worst: { key: HealthMetricKey; delta: number } | null = null
  for (const m of METRICS) {
    const cfg = HEALTH_DETAILS[m]
    const scores = entries.map((e) => cfg.scoreFromValue(cfg.getCurrentValue(e)))
    const delta = avg(scores.slice(half)) - avg(scores.slice(0, half))
    if (!best || delta > best.delta) best = { key: m, delta }
    if (!worst || delta < worst.delta) worst = { key: m, delta }
  }
  return best && worst ? { best, worst } : null
}

export interface MetricDelta {
  key: HealthMetricKey
  title: string
  delta: number
  direction: 'up' | 'down' | 'flat'
}

/** Per-metric score deltas (recent half vs prior half), biggest movers first —
 *  drives the live chips on the home trend card. Empty when <2 entries. */
export function metricDeltas(
  history: CheckinHistoryEntry[],
  todayCheckin: MetricEntry | null,
): MetricDelta[] {
  const entries: MetricEntry[] = [...history, ...(todayCheckin ? [todayCheckin] : [])]
  if (entries.length < 2) return []
  const half = Math.floor(entries.length / 2)
  const avg = (xs: number[]) => xs.reduce((s, v) => s + v, 0) / xs.length
  return METRICS.map((m) => {
    const cfg = HEALTH_DETAILS[m]
    const scores = entries.map((e) => cfg.scoreFromValue(cfg.getCurrentValue(e)))
    const delta = avg(scores.slice(half)) - avg(scores.slice(0, half))
    const direction = delta >= 3 ? ('up' as const) : delta <= -3 ? ('down' as const) : ('flat' as const)
    return { key: m, title: cfg.title, delta, direction }
  }).sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))
}

/** Little rule-based "AI" phrase under the overall trend chart. */
export function overallTrendPhrase(
  history: CheckinHistoryEntry[],
  todayCheckin: MetricEntry | null,
): string {
  const series = buildOverallSeries(history, todayCheckin)
  if (series.length === 0) return 'Do your first check-in and your trend starts building right here.'
  if (series.length === 1) {
    return `Baseline set at ${series[0]} · every check-in from here shows you where it moves.`
  }

  const trend = overallTrend(series)
  const movers = biggestMovers(history, todayCheckin)
  const bestName = movers ? HEALTH_DETAILS[movers.best.key].title.toLowerCase() : null
  const worstName = movers ? HEALTH_DETAILS[movers.worst.key].title.toLowerCase() : null

  if (trend === 'up') {
    return bestName
      ? `Trending up · ${bestName} is doing the heavy lifting this week. Keep that rhythm.`
      : 'Trending up · your recent days are stronger than your earlier ones.'
  }
  if (trend === 'down') {
    return worstName
      ? `Slightly off baseline · ${worstName} is pulling the average down. Worth a gentle look.`
      : 'Slightly off baseline · your recent days dipped versus earlier ones.'
  }
  return bestName && worstName && bestName !== worstName
    ? `Holding steady · ${bestName} is up while ${worstName} drifts. Balance is the story this week.`
    : 'Holding steady · no big swings, which is its own kind of progress.'
}
