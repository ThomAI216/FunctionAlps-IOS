// Live slider colour bands: red -> orange -> yellow -> blue -> green at 20-step
// thresholds. Untouched (null) is grey, never a real 0.
export const BAND_GREY = '#9CA3AF'

const BANDS: { max: number; color: string }[] = [
  { max: 20, color: '#DB5A4B' }, // red
  { max: 40, color: '#E08A3C' }, // orange
  { max: 60, color: '#E2BE3A' }, // yellow
  { max: 80, color: '#4F86C6' }, // blue
  { max: 100, color: '#4A8A5C' }, // green
]

const clamp = (v: number) => Math.max(0, Math.min(100, v))

export function bandColor(v: number | null): string {
  if (v === null) return BAND_GREY
  const c = clamp(v)
  // boundary (20/40/60/80) belongs to the UPPER band
  return (BANDS.find((b) => c < b.max) ?? BANDS[BANDS.length - 1]).color
}

export function bandLevel(v: number | null): 'low' | 'mid' | 'high' | null {
  if (v === null) return null
  const c = clamp(v)
  if (c < 40) return 'low'
  if (c <= 60) return 'mid'
  return 'high'
}

// 5-step "state" ramp — green → blue → purple → yellow → red (good → bad). Shared by
// the meal-reaction (ReactionSlider) + daily/gut (FunctionalSlider) sliders and the
// DimensionCard header score, so the whole check-in surface uses ONE palette.
export const STATE_RAMP = ['#4A8A5C', '#4F86C6', '#8E7CC3', '#E2BE3A', '#DB5A4B']
// Pastel "veil" gradients (~33% alpha) for the resting track, in both orientations.
export const STATE_RAMP_VEIL_GOOD_TO_BAD = ['#4A8A5C55', '#4F86C655', '#8E7CC355', '#E2BE3A55', '#DB5A4B55'] as [string, string, string, string, string] // green→red (reaction: good on the left)
export const STATE_RAMP_VEIL_BY_VALUE = ['#DB5A4B55', '#E2BE3A55', '#8E7CC355', '#4F86C655', '#4A8A5C55'] as [string, string, string, string, string] // red→green (functional 0-100: low on the left)
// Ramp INDEX (0=green..4=red) for a 0-100 value where HIGHER = BETTER (100→green, 0→red).
export function stateColorIndexForValue(v: number): number {
  return STATE_RAMP.length - 1 - Math.round((clamp(v) / 100) * (STATE_RAMP.length - 1))
}
export function stateColorForValue(v: number): string {
  return STATE_RAMP[stateColorIndexForValue(v)]
}
