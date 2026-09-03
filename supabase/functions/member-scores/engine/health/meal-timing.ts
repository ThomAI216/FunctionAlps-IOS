// v1 heuristic (spec §2.2, tunable). breakfast: first meal <=10h ideal.
// late-night: last meal <=20h ideal. window: first->last span <=12h ideal.
const clamp = (n: number) => Math.max(0, Math.min(100, n))
const hourOf = (iso: string) => {
  const d = new Date(iso)
  return d.getHours() + d.getMinutes() / 60
}

export function mealTimingScore(meals: { timestamp: string }[]): number | null {
  if (!meals.length) return null
  const hours = meals.map((m) => hourOf(m.timestamp)).sort((a, b) => a - b)
  const first = hours[0]
  const last = hours[hours.length - 1]

  // breakfast: 100 at <=10h, linear down to ~60 by 13h
  const breakfast = clamp(first <= 10 ? 100 : 100 - (first - 10) * (40 / 3))
  // late-night: 100 at <=20h, linear down to ~40 by 23h
  const lateNight = clamp(last <= 20 ? 100 : 100 - (last - 20) * 20)

  if (meals.length === 1) return Math.round((breakfast + lateNight) / 2)

  // window: 100 at <=12h span, linear penalty above (10pts/h)
  const span = last - first
  const windowScore = clamp(span <= 12 ? 100 : 100 - (span - 12) * 10)
  return Math.round((breakfast + lateNight + windowScore) / 3)
}
