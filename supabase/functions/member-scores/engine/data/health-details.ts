import type { CheckinScores } from '../types/daily-store.ts'

export type HealthMetricKey = 'digestion' | 'inflammation' | 'mood' | 'energy' | 'sleep' | 'stress'
// Any object carrying the six functional axes — the live CheckinScores (plain
// numbers) or a DB-loaded history entry, where an axis the v2 form never
// captures (digestion, inflammation) is null and must fall back to NEUTRAL_1_5,
// never to 0 (0 mountain-scores as worst-possible, not absent).
export type HealthMetricSource = { [K in HealthMetricKey]?: number | null } | null

export interface HealthMetricConfig {
  title: string
  subtitle: string
  accentColor: string
  accentBg: string
  chartColor: string
  chartType: 'sparkline' | 'bar'
  higherIsBetter: boolean
  deltaSuffix: string
  formatValue: (value: number) => string
  scoreFromValue: (value: number) => number
  getCurrentValue: (checkin: HealthMetricSource) => number
  insightTitle: string
  explanation: string
  focusAreas: Array<{ title: string; description: string }>
  todayInContext: Array<{ label: string; description: string }>
}

// 1–5 mountain scale → 0–100, clamped. Mirrors the canonical DB producer
// (`fa_mountain_score`) and `overall-trend.ts`'s `mtn`: every functional axis is
// a 1–5 subjective pick (the `FunctionalScale` picker), persisted raw to
// `patient_daily_checkins`. Lower-is-better axes (stress, inflammation) invert.
function mountain(value: number, invert = false): number {
  const pct = ((invert ? 5 - value : value - 1) / 4) * 100
  return Math.round(Math.max(0, Math.min(100, pct)))
}

// Neutral midpoint of the 1–5 scale — used when a check-in field is absent so an
// empty axis reads as "middle of the road" (score 50) rather than best/worst.
const NEUTRAL_1_5 = 3

export const HEALTH_DETAILS: Record<HealthMetricKey, HealthMetricConfig> = {
  digestion: {
    title: 'Digestion',
    subtitle: 'How calm, comfortable, and steady your gut feels',
    accentColor: '#0d9488',
    accentBg: '#f0fdfa',
    chartColor: '#14b8a6',
    chartType: 'sparkline',
    higherIsBetter: true,
    deltaSuffix: ' pts',
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.digestion ?? NEUTRAL_1_5,
    insightTitle: 'Digestion gives the clearest day-to-day feedback',
    explanation:
      'Digestion reflects how comfortably your system is handling meals, routine, and stress right now. A steadier digestion score usually means your gut is tolerating the day with less irritation and less reactivity.',
    focusAreas: [
      {
        title: 'Meal simplicity',
        description: 'Simpler meals often make it easier to tell which foods or habits are helping and which ones are stirring things up.',
      },
      {
        title: 'Eating pace',
        description: 'Slowing the pace of a meal can reduce digestive load more than people expect, especially when stress is high.',
      },
      {
        title: 'Timing of symptoms',
        description: 'Patterns become clearer when bloating, reflux, or discomfort are linked back to a meal window rather than treated as random.',
      },
    ],
    todayInContext: [
      { label: 'Inflammation', description: 'When digestion feels rough for several days in a row, inflammatory load often feels louder too.' },
      { label: 'Mood', description: 'Digestive discomfort can quietly pull mood down by making the whole day feel more effortful.' },
      { label: 'Energy', description: 'When meals are harder to tolerate, energy often feels less usable even if calories are technically adequate.' },
      { label: 'Sleep', description: 'Late digestive discomfort or reflux can make sleep lighter and recovery weaker overnight.' },
      { label: 'Stress', description: 'Stress can tighten digestion quickly, so pressure often shows up in the gut before it shows up anywhere else.' },
    ],
  },
  sleep: {
    title: 'Sleep',
    subtitle: 'How rested and recovered you feel',
    accentColor: '#6366f1',
    accentBg: '#eef2ff',
    chartColor: '#7c3aed',
    chartType: 'bar',
    higherIsBetter: true,
    deltaSuffix: ' pts',
    // Sleep is the same 1–5 subjective pick as every other functional axis
    // (the `FunctionalScale` picker → `patient_daily_checkins.sleep`). There is
    // no hours/step input anywhere, so it's modelled identically here.
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.sleep ?? NEUTRAL_1_5,
    insightTitle: 'Sleep drives the rest of the dashboard',
    explanation:
      'Sleep is your recovery foundation. When sleep is deeper and more consistent, energy, stress resilience, digestion, and overall stability usually improve with it.',
    focusAreas: [
      {
        title: 'Wind-down consistency',
        description: 'Keep the hour before bed quieter and dimmer so your nervous system can downshift properly.',
      },
      {
        title: 'Morning light',
        description: 'Getting daylight early anchors circadian rhythm and makes evening sleep pressure stronger.',
      },
      {
        title: 'Late caffeine cutoff',
        description: 'A firm cutoff earlier in the afternoon often improves sleep depth more than people expect.',
      },
    ],
    todayInContext: [
      { label: 'Digestion', description: 'A restless night often makes digestion feel more reactive and less forgiving the next day.' },
      { label: 'Inflammation', description: 'Poor sleep can amplify inflammatory noise even when food choices are reasonable.' },
      { label: 'Mood', description: 'Mood usually becomes less resilient when recovery is shallow or inconsistent.' },
      { label: 'Energy', description: 'Energy is often the first place poor sleep becomes visible in the day.' },
      { label: 'Stress', description: 'When sleep drops, the same daily load often feels much heavier than usual.' },
    ],
  },
  stress: {
    title: 'Stress',
    subtitle: 'Load, pressure, and recovery capacity',
    accentColor: '#e11d48',
    accentBg: '#fff1f2',
    chartColor: '#ec4899',
    chartType: 'sparkline',
    higherIsBetter: false,
    deltaSuffix: ' pts',
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value, true),
    getCurrentValue: (checkin) => checkin?.stress ?? NEUTRAL_1_5,
    insightTitle: 'Stress is a multiplier, not an isolated score',
    explanation:
      'Stress is a load signal. When stress climbs, it tends to amplify digestive sensitivity, reduce emotional flexibility, and make energy less stable across the day.',
    focusAreas: [
      {
        title: 'Short resets',
        description: 'Two or three intentional breath or walking breaks often change the whole shape of a day.',
      },
      {
        title: 'Calendar load',
        description: 'Back-to-back commitments can quietly keep your system in a higher-alert state for hours.',
      },
      {
        title: 'Evening decompression',
        description: 'A calmer evening improves both stress recovery and the next night of sleep.',
      },
    ],
    todayInContext: [
      { label: 'Digestion', description: 'Stress often shows up in digestion quickly through tightness, discomfort, or symptom flares.' },
      { label: 'Inflammation', description: 'Higher stress can make the whole system feel more reactive, especially when recovery is already low.' },
      { label: 'Mood', description: 'When pressure stays high, mood usually gets flatter, more fragile, or less resilient.' },
      { label: 'Energy', description: 'Stress can make energy feel jagged by pulling attention and recovery in too many directions at once.' },
      { label: 'Sleep', description: 'A busy nervous system at night often turns into lighter sleep and weaker recovery.' },
    ],
  },
  energy: {
    title: 'Energy',
    subtitle: 'How steady and usable your output feels',
    accentColor: '#d97706',
    accentBg: '#fffbeb',
    chartColor: '#f59e0b',
    chartType: 'sparkline',
    higherIsBetter: true,
    deltaSuffix: ' pts',
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.energy ?? NEUTRAL_1_5,
    insightTitle: 'Energy is where nutrition becomes visible',
    explanation:
      'Energy reflects how usable your output feels, not just how awake you are. Stronger energy usually means food, recovery, and daily load are working together instead of competing.',
    focusAreas: [
      {
        title: 'Protein first',
        description: 'A stronger protein anchor early in the day often smooths out hunger and energy swings.',
      },
      {
        title: 'Stable blood sugar',
        description: 'Big peaks and crashes usually feel like low energy, even when calories are technically adequate.',
      },
      {
        title: 'Recovery versus output',
        description: 'If output keeps climbing while recovery stays flat, energy debt accumulates fast.',
      },
    ],
    todayInContext: [
      { label: 'Digestion', description: 'If digestion is unsettled, energy often feels less steady even before symptoms become obvious.' },
      { label: 'Inflammation', description: 'Higher inflammatory load can make energy feel heavier, slower, and less reliable.' },
      { label: 'Mood', description: 'Low or unstable energy often drags mood down because everything feels more effortful.' },
      { label: 'Sleep', description: 'Sleep quality still shapes the ceiling of how strong and stable energy can feel.' },
      { label: 'Stress', description: 'Stress can burn through energy by pushing the system into output mode without enough recovery.' },
    ],
  },
  inflammation: {
    title: 'Inflammation',
    subtitle: 'How noisy or reactive the system feels',
    accentColor: '#0d9488',
    accentBg: '#f0fdfa',
    chartColor: '#14b8a6',
    chartType: 'sparkline',
    higherIsBetter: false,
    deltaSuffix: ' pts',
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value, true),
    getCurrentValue: (checkin) => checkin?.inflammation ?? NEUTRAL_1_5,
    insightTitle: 'Inflammation should feel actionable, not abstract',
    explanation:
      'Inflammation reflects how noisy or reactive the system feels in the background. It is influenced by food quality, recovery, stress load, and how well the body is handling daily demands over time.',
    focusAreas: [
      {
        title: 'Meal simplicity',
        description: 'Cleaner meals with fewer triggers usually make patterns easier to spot and inflammation easier to calm.',
      },
      {
        title: 'Training load',
        description: 'Hard weeks can make inflammation scores look worse even when food is decent.',
      },
      {
        title: 'Baseline recovery',
        description: 'Sleep, hydration, and digestion often shift inflammation more reliably than one supplement does.',
      },
    ],
    todayInContext: [
      { label: 'Digestion', description: 'Digestive irritation and inflammatory load often rise together when the system is under more pressure.' },
      { label: 'Mood', description: 'When inflammation is elevated, mood can feel heavier and less adaptable even without an obvious trigger.' },
      { label: 'Energy', description: 'Inflammation often lowers the quality of energy by making the whole day feel louder and less efficient.' },
      { label: 'Sleep', description: 'Sleep is one of the strongest background levers for lowering inflammatory noise.' },
      { label: 'Stress', description: 'Chronic pressure can keep inflammation elevated by reducing recovery and increasing system load.' },
    ],
  },
  mood: {
    title: 'Mood',
    subtitle: 'Emotional steadiness, resilience, and outlook',
    accentColor: '#db2777',
    accentBg: '#fdf2f8',
    chartColor: '#ec4899',
    chartType: 'sparkline',
    higherIsBetter: true,
    deltaSuffix: ' pts',
    formatValue: (value) => `${Math.round(value)}/5`,
    scoreFromValue: (value) => mountain(value),
    getCurrentValue: (checkin) => checkin?.mood ?? NEUTRAL_1_5,
    insightTitle: 'Mood is where recovery becomes personal',
    explanation:
      'Mood reflects how emotionally steady, resilient, and flexible the day feels. It is often shaped by sleep, stress, digestion, and energy more than by one isolated event.',
    focusAreas: [
      {
        title: 'Recovery load',
        description: 'Mood usually gets more fragile when sleep debt and daily pressure pile up at the same time.',
      },
      {
        title: 'Food stability',
        description: 'Regular meals with enough protein and fewer crashes often make mood feel steadier across the day.',
      },
      {
        title: 'Small lifts',
        description: 'Light movement, daylight, and social contact can all shift mood more reliably than waiting to feel better first.',
      },
    ],
    todayInContext: [
      { label: 'Digestion', description: 'A more irritated gut can quietly lower mood by making the day feel physically harder to move through.' },
      { label: 'Inflammation', description: 'Higher inflammatory load often makes mood feel flatter, heavier, or less resilient.' },
      { label: 'Energy', description: 'When energy is steady, mood usually feels more flexible and easier to protect.' },
      { label: 'Sleep', description: 'Sleep is one of the strongest levers for emotional steadiness across the whole day.' },
      { label: 'Stress', description: 'Stress and mood move together quickly, especially when recovery is already stretched.' },
    ],
  },
}

// (French overlay + React hooks removed for the edge runtime)
