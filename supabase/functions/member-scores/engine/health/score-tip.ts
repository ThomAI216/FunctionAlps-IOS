// Deterministic rule-based tip (spec §6.2 fallback). Used CLIENT-SIDE as the
// interim tip in Phase 2, and SERVER-SIDE as the generate-score-tip fallback
// when AI consent is off / the model fails. Names the strongest driver + the
// weak point from the factor breakdown.
import type { ScoreCore, ScoreTip } from './score-core.ts'

// ⚠ No `label` parameter any more. `summary` is a TEMPLATE with a `{label}`
// placeholder, filled by the caller through `tr(summary, { label })` —
// `translate()` interpolates on the English path too, so one form serves both
// languages and the catalog holds three keys instead of three per metric.
export function ruleBasedTip(core: ScoreCore): ScoreTip {
  const present = core.factors.filter((f) => f.value !== null)
  if (core.score === null || present.length === 0) {
    return { summary: 'Log a little more and your {label} reading appears here.', good: '', bad: '' }
  }
  const sorted = [...present].sort((a, b) => (b.value as number) - (a.value as number))
  const best = sorted[0]
  const worst = sorted[sorted.length - 1]

  const summary =
    // ⚠ A PLACEHOLDER, not an interpolation. The caller renders this through
    // `tr(summary, { label })`, and `translate()` interpolates on the English
    // path as well, so one form serves both languages and the catalog holds
    // three keys instead of one per metric name.
    core.score >= 67 ? 'Your {label} is strong today.'
    : core.score >= 34 ? 'Your {label} is holding steady.'
    : 'Your {label} needs attention today.'

  if (present.length === 1) {
    return { summary, good: `${best.label} (${best.value}/100) is the only signal so far.`, bad: '' }
  }

  const good = `${best.label} is your strongest driver (${best.value}/100).`
  const bad =
    (worst.value as number) < 67
      ? `${worst.label} is the weak point (${worst.value}/100) · focus here.`
      : `Nothing's dragging it down · keep it going.`
  return { summary, good, bad }
}
