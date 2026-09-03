// Single source of the gut sub-scores (comfort/stool/reactions, 0-100) shared by the
// Trends gutScore AND the Check-in Hub buildGutComposites, so the two never diverge.
// stool: prefer the v2 gut_stool overall, else the legacy mean(stoolQuality, stoolFrequency)
// markers (replicates buildGutComposites' existing fallback byte-for-byte).
import { gutMarkerScore, type GutHistoryEntry } from '../checkin/marker-trends.ts'
import { mealReactionsScore, type MealReaction } from './gut-breakdown.ts'

export interface GutSignals {
  comfort: number | null
  stool: number | null
  reactions: number | null
}

function mean(vals: (number | null)[]): number | null {
  const v = vals.filter((x): x is number => x !== null)
  return v.length ? Math.round(v.reduce((s, x) => s + x, 0) / v.length) : null
}

export function gutSignalsForEntry(entry: GutHistoryEntry | null, meals: MealReaction[]): GutSignals {
  const comfort = entry?.comfort ?? null
  let stool = entry?.stool ?? null
  if (stool == null && entry) {
    stool = mean([gutMarkerScore('stoolQuality', entry.stoolQuality), gutMarkerScore('stoolFrequency', entry.stoolFrequency)])
  }
  return { comfort, stool, reactions: mealReactionsScore(meals) }
}

// Per-field most-recent-non-null reach-back over [...history, today] (mirrors the Hub's
// latestGut: comfort and stool may come from different days).
export function latestGutEntry(today: GutHistoryEntry | null, history: GutHistoryEntry[]): GutHistoryEntry | null {
  const all = today ? [...history, today] : history
  if (!all.length) return null
  const latest = (k: keyof GutHistoryEntry): number | null => {
    for (let i = all.length - 1; i >= 0; i--) {
      const v = all[i][k]
      if (typeof v === 'number') return v
    }
    return null
  }
  return {
    date: '',
    bloating: latest('bloating'), burns: latest('burns'), gasBurden: latest('gasBurden'),
    stoolQuality: latest('stoolQuality'), stoolFrequency: latest('stoolFrequency'),
    comfort: latest('comfort'), gutOverall: latest('gutOverall'), stool: latest('stool'),
  }
}

export function gutSignalsCurrent(today: GutHistoryEntry | null, history: GutHistoryEntry[], meals: MealReaction[]): GutSignals {
  return gutSignalsForEntry(latestGutEntry(today, history), meals)
}
