// Per-score daily series helper. lastNDays returns the N day-anchors
// [now-(N-1) … now] (oldest first), so callers can recompute a ScoreCore over
// each day's data for the expansion trend chart (14 days — Thomas, 2026-06-21).
export function lastNDays(now: Date, n: number): Date[] {
  return Array.from({ length: n }, (_, i) => {
    const d = new Date(now)
    d.setDate(d.getDate() - (n - 1 - i))
    return d
  })
}

/** Drop null gaps (line charts that can't render a missing day). */
export function compactSeries(series: (number | null)[]): number[] {
  return series.filter((v): v is number => v !== null)
}

/**
 * Average of the non-null values among the LAST `n` elements of a series (the
 * recent window). Returns null when the window has no data. Rounded to a whole
 * number. Powers the Library "last 7 days average, computed over whatever days
 * exist" card — series14d is anchored newest-last, so slice(-7) is the last week.
 */
export function seriesLastNAverage(series: (number | null)[], n: number): number | null {
  const window = series.slice(-n)
  const vals = window.filter((v): v is number => v !== null && v !== undefined && !Number.isNaN(v))
  if (vals.length === 0) return null
  return Math.round(vals.reduce((sum, v) => sum + v, 0) / vals.length)
}
