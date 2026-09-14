// Wearable → score inputs, server side (strategy 2026-09-14 Phase 4; corpus 21_SCORING_INTEGRATION.md).
//
// What this module guarantees, each pinned by a test in tests/wearable_inputs_test.ts:
//   • every row becomes a typed `ScoreInput` (unit, source, semantic version, quality, coverage) and only
//     `quality === "valid"` rows are eligible — missing ≠ zero, a future or stale day is not a reading;
//   • one PRIMARY SOURCE per metric per member, chosen by `wearable_source_policy` (practice defaults +
//     the member's own rows) over a built-in default: the phone relay (Apple Health) for the cumulative
//     activity metrics and VO₂ max, the session-matched direct vendor for sleep-context physiology (HRV,
//     resting HR, sleep, stress, breathing), Thryve last. Sources are never mixed inside one metric — the
//     mechanical MAX / MEDIAN across sources is gone;
//   • the HRV chain is exactly 3106 RmssdSleep → 3100 Rmssd → 3112 SDNN, chosen ONCE per member for the
//     window (the highest level with enough baseline days), never numerically converted, and today's
//     value only counts when it comes from the chosen level;
//   • the personal baseline is the median of the prior 42 valid local days of the SAME segment
//     (source · metric · semantic version) with a MAD spread (1.4826 · MAD); fewer than 14 days = no
//     baseline (the engine's HRV factor stays off); a source or normalization change starts a new segment;
//   • vendor Recovery / Readiness / Sleep scores are never read here (the engine consumes raw physiology
//     already; feeding both would count the same physiology twice — corpus "Recovery score policy").
//
// The engine under member-scores/engine stays the Expo copy, verbatim: this module only SHAPES its inputs
// (`WearableDay`, `RecoveryBaseline`) and reports how it did so (`WearableInputSummary`) for the app.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"
import type { RecoveryBaseline, WearableDay } from "../../member-scores/engine/wearables/metrics.ts"

// MARK: - Catalogue ids this module reads (mirrors wearable_data_types; never a vendor score, never a risk row)

export const ID = {
  RmssdSleep: 3106, Rmssd: 3100, SDNN: 3112, HeartRateResting: 3001, AverageStress: 6010, RespirationRate: 4000,
  MainSleepDuration: 2300, InBed: 2301, SleepEfficiency: 2200, Interruptions: 2402, Latency: 2307, REM: 2302, Deep: 2303,
  Steps: 1000, ActivityDuration: 1100, ActiveBurnedCalories: 1011, CoveredDistance: 1001, VO2max: 3030, MET: 1012,
} as const
export type MetricId = (typeof ID)[keyof typeof ID]
export const READ_IDS: number[] = Object.values(ID)

/** The HRV chain, in order. Exactly this; SDNN is never converted to RMSSD. */
export const HRV_CHAIN: { id: number; name: "RmssdSleep" | "Rmssd" | "SDNN" }[] = [
  { id: ID.RmssdSleep, name: "RmssdSleep" }, { id: ID.Rmssd, name: "Rmssd" }, { id: ID.SDNN, name: "SDNN" },
]

export const BASELINE_DAYS = 42
export const MIN_BASELINE_DAYS = 14
export const WINDOW_DAYS = 56          // 42 baseline + 14 trend days
export const MAD_SCALE = 1.4826
/** Rows written before provenance existed carry no version; their mapping equals the first versioned one, so the
 *  baseline is NOT reset by the 2026-09-14 deploy. A later, material mapping change gets a new version and does reset. */
export const SEGMENT_ALIAS: Record<string, string> = { legacy: "2026.09.14" }

/** Source ids: the phone relays and the legacy aggregator. Direct vendors are read from `wearable_vendors`. */
export const SOURCE = { apple: 1000001, healthConnect: 1000060 } as const
export const THRYVE_MAX_SOURCE_ID = 999999   // Thryve source ids are small integers; every direct/relay id is ≥ 1000000

/** Where a metric's truth lives by default (the strategy's "provenance-aware source priority"). */
export type SourceKind = "relay" | "vendor" | "thryve"
const ACTIVITY_IDS = new Set<number>([ID.Steps, ID.ActivityDuration, ID.ActiveBurnedCalories, ID.CoveredDistance, ID.VO2max, ID.MET])
export function defaultPriority(typeId: number, kind: SourceKind): number {
  if (ACTIVITY_IDS.has(typeId)) return kind === "relay" ? 30 : kind === "vendor" ? 20 : 10   // the phone counts every step once
  return kind === "vendor" ? 30 : kind === "relay" ? 20 : 10                                  // the ring/strap that saw the night
}

// MARK: - Types

export type Quality = "valid" | "future" | "stale" | "not_finite" | "unknown_metric"

/** The corpus's input contract, one per row. */
export interface ScoreInput {
  type_id: number
  value: number
  unit: string
  local_date: string
  source_id: number
  source_vendor: string
  semantic_version: string
  quality: Quality
  coverage?: number
}

export interface WearableDailyRow {
  day: string
  data_type_id: number
  data_source_id: number
  value: number | string | null
  normalization_version?: string | null
}

export interface SourcePolicyRow { patient_id: string | null; data_type_id: number; source_vendor: string; priority: number }
export interface VendorRow { key: string; data_source_id: number }

export interface MetricSummary {
  typeId: number
  /** `apple_health`, a vendor key, `thryve`, or null when nothing is eligible. */
  source: string | null
  sourceId: number | null
  semanticVersion: string | null
  /** Valid days of the primary source inside the window (any segment). */
  days: number
  /** Valid days of the current segment inside the prior 42 → what the baseline stands on. */
  baselineDays: number
  baseline: number | null
  spread: number | null
  /** Share of the prior 42 days covered by the current segment, 0–1. */
  coverage: number
  eligible: boolean
}

export interface WearableInputSummary {
  hrvMetric: "RmssdSleep" | "Rmssd" | "SDNN" | null
  hrv: MetricSummary | null
  restingHr: MetricSummary | null
  sleep: MetricSummary | null
  steps: MetricSummary | null
  daysWithData: number
  /** Sources that contributed at least one eligible row, by name. */
  sources: string[]
}

export interface WearableInputs {
  wearableByDay: Map<string, WearableDay>
  recoveryBaseline: RecoveryBaseline
  summary: WearableInputSummary
}

// MARK: - Pure helpers

export function median(xs: number[]): number | null {
  if (!xs.length) return null
  const s = [...xs].sort((a, b) => a - b), n = s.length
  return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

/** Median + robust spread (1.4826 · MAD). `spread` is 0 when every value equals the median. */
export function robustBaseline(xs: number[]): { center: number; spread: number } | null {
  const c = median(xs)
  if (c == null) return null
  const mad = median(xs.map((x) => Math.abs(x - c))) ?? 0
  return { center: c, spread: MAD_SCALE * mad }
}

export function addDays(day: string, n: number): string {
  const d = new Date(day + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10)
}

const num = (v: unknown): number | null => { const n = typeof v === "number" ? v : v == null || v === "" ? NaN : Number(v); return Number.isFinite(n) ? n : null }

export function sourceName(sourceId: number, vendors: VendorRow[]): string {
  if (sourceId === SOURCE.apple) return "apple_health"
  if (sourceId === SOURCE.healthConnect) return "health_connect"
  const v = vendors.find((x) => x.data_source_id === sourceId)
  if (v) return v.key
  return sourceId <= THRYVE_MAX_SOURCE_ID ? "thryve" : `source_${sourceId}`
}
export function sourceKind(sourceId: number, vendors: VendorRow[]): SourceKind {
  if (sourceId === SOURCE.apple || sourceId === SOURCE.healthConnect) return "relay"
  if (vendors.some((x) => x.data_source_id === sourceId)) return "vendor"
  return sourceId <= THRYVE_MAX_SOURCE_ID ? "thryve" : "vendor"
}

/** Every row → a typed input with its quality judged (today = the member's local day). */
export function toInputs(rows: WearableDailyRow[], today: string, vendors: VendorRow[]): ScoreInput[] {
  const floor = addDays(today, -WINDOW_DAYS)
  const known = new Set<number>(READ_IDS)
  return rows.map((r) => {
    const value = num(r.value)
    const quality: Quality = !known.has(r.data_type_id) ? "unknown_metric" : value == null ? "not_finite" : r.day > today ? "future" : r.day < floor ? "stale" : "valid"
    return {
      type_id: r.data_type_id, value: value ?? NaN, unit: UNIT[r.data_type_id] ?? "catalogue", local_date: r.day,
      source_id: r.data_source_id, source_vendor: sourceName(r.data_source_id, vendors),
      semantic_version: `${r.data_type_id}:${SEGMENT_ALIAS[r.normalization_version ?? "legacy"] ?? r.normalization_version}`, quality,
    }
  })
}

const UNIT: Record<number, string> = {
  3106: "ms", 3100: "ms", 3112: "ms", 3001: "bpm", 6010: "score", 4000: "count",
  2300: "s", 2301: "s", 2200: "percent", 2402: "count", 2307: "s", 2302: "s", 2303: "s",
  1000: "count", 1100: "min", 1011: "kcal", 1001: "m", 3030: "mL/min/kg", 1012: "met",
}

/** The priority of (type, source) = the most specific policy row, else the built-in default. */
export function priorityFor(typeId: number, sourceId: number, policy: SourcePolicyRow[], vendors: VendorRow[], patientId: string): number {
  const name = sourceName(sourceId, vendors)
  const own = policy.find((p) => p.patient_id === patientId && p.data_type_id === typeId && p.source_vendor === name)
  if (own) return own.priority
  const practice = policy.find((p) => p.patient_id == null && p.data_type_id === typeId && p.source_vendor === name)
  if (practice) return practice.priority
  return defaultPriority(typeId, sourceKind(sourceId, vendors))
}

interface SourcePick { sourceId: number; days: number; latestSegment: string; priority: number }

/** The primary source for one metric: highest priority among sources with ≥ 1 valid day; ties → more days. */
export function pickSource(inputs: ScoreInput[], typeId: number, ctx: { policy: SourcePolicyRow[]; vendors: VendorRow[]; patientId: string }): SourcePick | null {
  const bySource = new Map<number, ScoreInput[]>()
  for (const i of inputs) if (i.type_id === typeId && i.quality === "valid") bySource.set(i.source_id, [...(bySource.get(i.source_id) ?? []), i])
  let best: SourcePick | null = null
  for (const [sourceId, rows] of bySource) {
    const days = new Set(rows.map((r) => r.local_date)).size
    const latest = rows.reduce((a, b) => (a.local_date >= b.local_date ? a : b))
    const cand: SourcePick = { sourceId, days, latestSegment: latest.semantic_version, priority: priorityFor(typeId, sourceId, ctx.policy, ctx.vendors, ctx.patientId) }
    if (!best || cand.priority > best.priority || (cand.priority === best.priority && cand.days > best.days)) best = cand
  }
  return best
}

/** One value per day for (type, source, segment) — the last row wins when a day repeats (it never should). */
function seriesFor(inputs: ScoreInput[], typeId: number, sourceId: number, segment?: string): Map<string, number> {
  const out = new Map<string, number>()
  for (const i of inputs) {
    if (i.type_id !== typeId || i.source_id !== sourceId || i.quality !== "valid") continue
    if (segment && i.semantic_version !== segment) continue
    out.set(i.local_date, i.value)
  }
  return out
}

/** Baseline over the prior 42 days (today excluded) of the pick's CURRENT segment. */
export function metricSummary(inputs: ScoreInput[], typeId: number, today: string, ctx: { policy: SourcePolicyRow[]; vendors: VendorRow[]; patientId: string }): MetricSummary {
  const pick = pickSource(inputs, typeId, ctx)
  if (!pick) return { typeId, source: null, sourceId: null, semanticVersion: null, days: 0, baselineDays: 0, baseline: null, spread: null, coverage: 0, eligible: false }
  const from = addDays(today, -BASELINE_DAYS)
  const seg = seriesFor(inputs, typeId, pick.sourceId, pick.latestSegment)
  const prior = [...seg.entries()].filter(([d]) => d >= from && d < today).map(([, v]) => v)
  const rb = robustBaseline(prior)
  const baselineDays = prior.length
  return {
    typeId, source: sourceName(pick.sourceId, ctx.vendors), sourceId: pick.sourceId, semanticVersion: pick.latestSegment,
    days: pick.days, baselineDays, baseline: rb ? Math.round(rb.center * 10) / 10 : null, spread: rb ? Math.round(rb.spread * 10) / 10 : null,
    coverage: Math.round((baselineDays / BASELINE_DAYS) * 100) / 100, eligible: baselineDays >= MIN_BASELINE_DAYS,
  }
}

/** The HRV level for this member: the highest level whose primary source has a full baseline; else the level with most days. */
export function chooseHRV(inputs: ScoreInput[], today: string, ctx: { policy: SourcePolicyRow[]; vendors: VendorRow[]; patientId: string }): { level: (typeof HRV_CHAIN)[number]; summary: MetricSummary } | null {
  const candidates = HRV_CHAIN.map((level) => ({ level, summary: metricSummary(inputs, level.id, today, ctx) })).filter((c) => c.summary.sourceId != null)
  if (!candidates.length) return null
  return candidates.find((c) => c.summary.eligible) ?? candidates.reduce((a, b) => (b.summary.days > a.summary.days ? b : a))
}

// MARK: - Shaping the engine's inputs

const r1 = (n: number) => Math.round(n * 10) / 10

/** Pure: rows (+ policy, vendors) → the engine's `wearableByDay` + `recoveryBaseline` + the summary. */
export function buildWearableInputs(rows: WearableDailyRow[], opts: { today: string; patientId: string; policy?: SourcePolicyRow[]; vendors?: VendorRow[]; trendDays?: number }): WearableInputs {
  const ctx = { policy: opts.policy ?? [], vendors: opts.vendors ?? [], patientId: opts.patientId }
  const inputs = toInputs(rows, opts.today, ctx.vendors)
  const trendFrom = addDays(opts.today, -(opts.trendDays ?? 13))
  const empty = (): WearableInputs => ({ wearableByDay: new Map(), recoveryBaseline: { restingHr: null, hrvRmssd: null, hrvDays: 0 }, summary: { hrvMetric: null, hrv: null, restingHr: null, sleep: null, steps: null, daysWithData: 0, sources: [] } })
  if (!inputs.some((i) => i.quality === "valid")) return empty()

  const hrv = chooseHRV(inputs, opts.today, ctx)
  const rhr = metricSummary(inputs, ID.HeartRateResting, opts.today, ctx)
  const sleep = metricSummary(inputs, ID.MainSleepDuration, opts.today, ctx)
  const steps = metricSummary(inputs, ID.Steps, opts.today, ctx)
  const pickFor = (typeId: number) => pickSource(inputs, typeId, ctx)
  const series = (typeId: number, pick: SourcePick | null) => (pick ? seriesFor(inputs, typeId, pick.sourceId, pick.latestSegment) : new Map<string, number>())

  // Sleep-context metrics follow the sleep-duration source (one night, one device); activity follows its own picks.
  const sleepPick = pickFor(ID.MainSleepDuration)
  const sleepDur = series(ID.MainSleepDuration, sleepPick)
  const sleepOf = (typeId: number) => (sleepPick ? seriesFor(inputs, typeId, sleepPick.sourceId) : new Map<string, number>())
  const inBed = sleepOf(ID.InBed), eff = sleepOf(ID.SleepEfficiency), inter = sleepOf(ID.Interruptions), lat = sleepOf(ID.Latency), rem = sleepOf(ID.REM), deep = sleepOf(ID.Deep)
  const hrvSeries = hrv ? seriesFor(inputs, hrv.level.id, hrv.summary.sourceId as number, hrv.summary.semanticVersion as string) : new Map<string, number>()
  const rhrSeries = series(ID.HeartRateResting, pickFor(ID.HeartRateResting))
  const stress = series(ID.AverageStress, pickFor(ID.AverageStress))
  const resp = series(ID.RespirationRate, pickFor(ID.RespirationRate))
  const stepsS = series(ID.Steps, pickFor(ID.Steps)), actMin = series(ID.ActivityDuration, pickFor(ID.ActivityDuration))
  const kcal = series(ID.ActiveBurnedCalories, pickFor(ID.ActiveBurnedCalories)), dist = series(ID.CoveredDistance, pickFor(ID.CoveredDistance)), met = series(ID.MET, pickFor(ID.MET))

  const days = new Set<string>()
  for (const i of inputs) if (i.quality === "valid" && i.local_date >= trendFrom) days.add(i.local_date)
  const byDay = new Map<string, WearableDay>()
  const usedSources = new Set<number>()
  for (const day of [...days].sort()) {
    const sd = sleepDur.get(day) ?? null
    const ib = inBed.get(day) ?? null
    const sleepDay = sd == null ? null : {
      hours: r1(sd / 3600),
      efficiencyPct: eff.get(day) != null ? Math.round(eff.get(day) as number) : ib && ib > 0 ? Math.min(100, Math.round((100 * sd) / ib)) : null,
      interruptions: inter.get(day) ?? null,
      latencyMin: lat.get(day) != null ? Math.round((lat.get(day) as number) / 60) : null,
      remMin: rem.get(day) != null ? Math.round((rem.get(day) as number) / 60) : null,
      deepMin: deep.get(day) != null ? Math.round((deep.get(day) as number) / 60) : null,
    }
    const restingHr = rhrSeries.get(day) ?? null, hrvV = hrvSeries.get(day) ?? null, avgStress = stress.get(day) ?? null
    const recovery = restingHr == null && hrvV == null && avgStress == null ? null : { restingHr, hrvRmssd: hrvV == null ? null : r1(hrvV), avgStress }
    const act = { steps: stepsS.get(day) ?? null, activeMinutes: actMin.get(day) ?? null, activeEnergyKcal: kcal.get(day) ?? null, distanceM: dist.get(day) != null ? Math.round(dist.get(day) as number) : null, metMax: met.get(day) ?? null }
    const activity = Object.values(act).every((v) => v == null) ? null : act
    const sourceIds = new Set<number>()
    if (sd != null && sleepPick) sourceIds.add(sleepPick.sourceId)
    if (hrvV != null && hrv) sourceIds.add(hrv.summary.sourceId as number)
    if (restingHr != null) sourceIds.add(rhr.sourceId as number)
    if (act.steps != null && steps.sourceId != null) sourceIds.add(steps.sourceId)
    for (const s of sourceIds) usedSources.add(s)
    if (!sleepDay && !recovery && !activity && resp.get(day) == null) continue
    byDay.set(day, { date: day, sleep: sleepDay, recovery, activity, respirationRate: resp.get(day) ?? null, sourceIds: [...sourceIds] })
  }

  const recoveryBaseline: RecoveryBaseline = {
    restingHr: rhr.eligible ? Math.round(rhr.baseline as number) : null,
    hrvRmssd: hrv?.summary.eligible ? hrv.summary.baseline : null,
    hrvDays: hrv?.summary.baselineDays ?? 0,
  }
  return {
    wearableByDay: byDay,
    recoveryBaseline,
    summary: {
      hrvMetric: hrv?.level.name ?? null, hrv: hrv?.summary ?? null, restingHr: rhr.sourceId != null ? rhr : null,
      sleep: sleep.sourceId != null ? sleep : null, steps: steps.sourceId != null ? steps : null,
      daysWithData: byDay.size, sources: [...usedSources].map((s) => sourceName(s, ctx.vendors)).sort(),
    },
  }
}

// MARK: - Loader (runs under the CALLER's JWT: own rows only; the risk layer is excluded by the RLS policy)

export async function loadWearableInputs(db: SupabaseClient, patientId: string, today: string, trendDays = 13): Promise<WearableInputs> {
  const since = addDays(today, -WINDOW_DAYS)
  const [rowsRes, policyRes, vendorsRes] = await Promise.all([
    db.from("wearable_daily").select("day,data_type_id,data_source_id,value,normalization_version")
      .eq("patient_id", patientId).in("data_type_id", READ_IDS).gte("day", since).lte("day", today).limit(5000),
    db.from("wearable_source_policy").select("patient_id,data_type_id,source_vendor,priority"),
    db.from("wearable_vendors").select("key,data_source_id"),
  ])
  if (rowsRes.error) throw new Error(`wearable_daily: ${rowsRes.error.message}`)
  return buildWearableInputs((rowsRes.data ?? []) as WearableDailyRow[], {
    today, patientId, trendDays,
    policy: (policyRes.data ?? []) as SourcePolicyRow[], vendors: (vendorsRes.data ?? []) as VendorRow[],
  })
}
