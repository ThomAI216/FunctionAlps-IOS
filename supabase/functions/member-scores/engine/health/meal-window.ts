// Window C (spec): today's meals; if today has none, the most recent PRIOR day
// that has meals. Pure — `now` is injected so it is deterministic + testable.
export function windowMeals<T extends { timestamp: string }>(meals: T[], now: Date): T[] {
  if (!meals.length) return []
  const dayKey = (d: Date) => d.toDateString()
  const byDay = new Map<string, T[]>()
  for (const meal of meals) {
    const k = dayKey(new Date(meal.timestamp))
    const arr = byDay.get(k)
    if (arr) arr.push(meal)
    else byDay.set(k, [meal])
  }
  const today = byDay.get(dayKey(now))
  if (today && today.length) return today
  // most recent day at or before `now` with meals
  const candidates = [...byDay.keys()]
    .map((k) => ({ k, t: new Date(k).getTime() }))
    .filter((x) => x.t <= now.getTime())
    .sort((a, b) => b.t - a.t)
  return candidates.length ? (byDay.get(candidates[0].k) as T[]) : []
}
