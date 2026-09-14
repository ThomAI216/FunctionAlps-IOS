import { assert, assertEquals } from "jsr:@std/assert@1"
import { BASELINE_DAYS, ID, MIN_BASELINE_DAYS, SOURCE, addDays, buildWearableInputs, chooseHRV, metricSummary, pickSource, robustBaseline, toInputs, type SourcePolicyRow, type VendorRow, type WearableDailyRow } from "../wearable-inputs.ts"

const TODAY = "2026-09-14"
const WHOOP = 1000042, OURA = 1000018
const vendors: VendorRow[] = [{ key: "whoop", data_source_id: WHOOP }, { key: "oura", data_source_id: OURA }]
const ctx = { policy: [] as SourcePolicyRow[], vendors, patientId: "p1" }

/** `n` daily rows ending yesterday (or `endOffset` days before today), one value per day. */
function daysBack(n: number, typeId: number, source: number, value: (i: number) => number, opts: { endOffset?: number; nv?: string | null } = {}): WearableDailyRow[] {
  const out: WearableDailyRow[] = []
  for (let i = 0; i < n; i++) out.push({ day: addDays(TODAY, -(opts.endOffset ?? 1) - i), data_type_id: typeId, data_source_id: source, value: value(i), normalization_version: opts.nv === undefined ? "2026.09.14" : opts.nv })
  return out
}

Deno.test("robust baseline = median with a 1.4826·MAD spread; empty → null", () => {
  assertEquals(robustBaseline([]), null)
  const b = robustBaseline([50, 52, 48, 51, 49, 90])!   // one outlier night barely moves the centre
  assertEquals(b.center, 50.5)
  assert(b.spread > 1 && b.spread < 3)
  assertEquals(robustBaseline([7, 7, 7])!.spread, 0)
})

Deno.test("quality: future and stale days are not readings; unknown metrics and non-numbers are dropped", () => {
  const inputs = toInputs([
    { day: TODAY, data_type_id: ID.Steps, data_source_id: SOURCE.apple, value: 8000 },
    { day: addDays(TODAY, 1), data_type_id: ID.Steps, data_source_id: SOURCE.apple, value: 8000 },
    { day: addDays(TODAY, -60), data_type_id: ID.Steps, data_source_id: SOURCE.apple, value: 8000 },
    { day: TODAY, data_type_id: 1000100, data_source_id: OURA, value: 80 },
    { day: TODAY, data_type_id: ID.Steps, data_source_id: SOURCE.apple, value: "n/a" },
  ], TODAY, vendors)
  assertEquals(inputs.map((i) => i.quality), ["valid", "future", "stale", "unknown_metric", "not_finite"])
  // an unversioned (pre-provenance) row shares the first versioned segment — no baseline reset at the deploy
  assertEquals(inputs[0], { type_id: 1000, value: 8000, unit: "count", local_date: TODAY, source_id: SOURCE.apple, source_vendor: "apple_health", semantic_version: "1000:2026.09.14", quality: "valid" })
})

Deno.test("source priority: the phone wins steps, the strap wins HRV; a policy row overrides", () => {
  const rows = [
    ...daysBack(20, ID.Steps, SOURCE.apple, () => 9000), ...daysBack(20, ID.Steps, WHOOP, () => 7000),
    ...daysBack(20, ID.RmssdSleep, SOURCE.apple, () => 40), ...daysBack(20, ID.RmssdSleep, WHOOP, () => 60),
  ]
  const inputs = toInputs(rows, TODAY, vendors)
  assertEquals(pickSource(inputs, ID.Steps, ctx)!.sourceId, SOURCE.apple)
  assertEquals(pickSource(inputs, ID.RmssdSleep, ctx)!.sourceId, WHOOP)
  const policy: SourcePolicyRow[] = [{ patient_id: "p1", data_type_id: ID.RmssdSleep, source_vendor: "apple_health", priority: 99 }]
  assertEquals(pickSource(inputs, ID.RmssdSleep, { ...ctx, policy })!.sourceId, SOURCE.apple)
  const practice: SourcePolicyRow[] = [{ patient_id: null, data_type_id: ID.Steps, source_vendor: "whoop", priority: 99 }]
  assertEquals(pickSource(inputs, ID.Steps, { ...ctx, policy: practice })!.sourceId, WHOOP)
})

Deno.test("sources are never mixed inside one metric: the baseline uses the primary source only", () => {
  const rows = [...daysBack(20, ID.RmssdSleep, WHOOP, () => 60), ...daysBack(20, ID.RmssdSleep, SOURCE.apple, () => 40)]
  const s = metricSummary(toInputs(rows, TODAY, vendors), ID.RmssdSleep, TODAY, ctx)
  assertEquals([s.source, s.baseline, s.baselineDays, s.eligible], ["whoop", 60, 20, true])
})

Deno.test("HRV chain: 3106 first; SDNN only when nothing better has a baseline; never converted", () => {
  const a = chooseHRV(toInputs([...daysBack(20, ID.RmssdSleep, WHOOP, () => 60), ...daysBack(20, ID.SDNN, SOURCE.apple, () => 45)], TODAY, vendors), TODAY, ctx)!
  assertEquals([a.level.name, a.summary.baseline], ["RmssdSleep", 60])
  const b = chooseHRV(toInputs(daysBack(20, ID.SDNN, SOURCE.apple, () => 45), TODAY, vendors), TODAY, ctx)!
  assertEquals([b.level.name, b.summary.baseline, b.summary.source], ["SDNN", 45, "apple_health"])
  // 3106 with too few days does not win over an SDNN series that has a full baseline
  const c = chooseHRV(toInputs([...daysBack(5, ID.RmssdSleep, WHOOP, () => 60), ...daysBack(20, ID.SDNN, SOURCE.apple, () => 45)], TODAY, vendors), TODAY, ctx)!
  assertEquals(c.level.name, "SDNN")
  // nothing eligible anywhere → the level with the most days, reported but not eligible
  const d = chooseHRV(toInputs([...daysBack(3, ID.RmssdSleep, WHOOP, () => 60), ...daysBack(6, ID.Rmssd, OURA, () => 50)], TODAY, vendors), TODAY, ctx)!
  assertEquals([d.level.name, d.summary.eligible, d.summary.days], ["Rmssd", false, 6])
})

Deno.test("14-day minimum, 42-day window, today excluded from the baseline", () => {
  const thirteen = metricSummary(toInputs(daysBack(13, ID.HeartRateResting, WHOOP, () => 52), TODAY, vendors), ID.HeartRateResting, TODAY, ctx)
  assertEquals([thirteen.baselineDays, thirteen.eligible, thirteen.baseline], [13, false, 52])
  const fourteen = metricSummary(toInputs(daysBack(14, ID.HeartRateResting, WHOOP, () => 52), TODAY, vendors), ID.HeartRateResting, TODAY, ctx)
  assertEquals([fourteen.baselineDays, fourteen.eligible], [MIN_BASELINE_DAYS, true])
  const fifty = metricSummary(toInputs(daysBack(50, ID.HeartRateResting, WHOOP, (i) => (i < 42 ? 50 : 90)), TODAY, vendors), ID.HeartRateResting, TODAY, ctx)
  assertEquals([fifty.baselineDays, fifty.baseline], [BASELINE_DAYS, 50])   // the 90s are older than 42 days
  const withToday = metricSummary(toInputs([...daysBack(20, ID.HeartRateResting, WHOOP, () => 50), { day: TODAY, data_type_id: ID.HeartRateResting, data_source_id: WHOOP, value: 99 }], TODAY, vendors), ID.HeartRateResting, TODAY, ctx)
  assertEquals([withToday.baseline, withToday.baselineDays], [50, 20])
})

Deno.test("a normalization change starts a new segment: the old days no longer count", () => {
  const rows = [...daysBack(5, ID.RmssdSleep, WHOOP, () => 62, { nv: "2026.10.01" }), ...daysBack(30, ID.RmssdSleep, WHOOP, () => 60, { endOffset: 6, nv: "2026.09.14" })]
  const s = metricSummary(toInputs(rows, TODAY, vendors), ID.RmssdSleep, TODAY, ctx)
  assertEquals([s.semanticVersion, s.baselineDays, s.eligible, s.days], ["3106:2026.10.01", 5, false, 35])
})

Deno.test("the engine's inputs: units, one night one device, the baseline gate, the summary", () => {
  const rows = [
    ...daysBack(20, ID.MainSleepDuration, WHOOP, () => 7.5 * 3600, { endOffset: 0 }), ...daysBack(20, ID.InBed, WHOOP, () => 8 * 3600, { endOffset: 0 }),
    ...daysBack(20, ID.Latency, WHOOP, () => 600, { endOffset: 0 }), ...daysBack(20, ID.RmssdSleep, WHOOP, (i) => 60 + (i % 3), { endOffset: 0 }),
    ...daysBack(20, ID.HeartRateResting, WHOOP, () => 52, { endOffset: 0 }), ...daysBack(20, ID.Steps, SOURCE.apple, () => 8000, { endOffset: 0 }),
    ...daysBack(20, ID.MainSleepDuration, SOURCE.apple, () => 6 * 3600, { endOffset: 0 }),  // the phone's shorter night is ignored (one device per night)
  ]
  const out = buildWearableInputs(rows, { today: TODAY, patientId: "p1", vendors })
  const today = out.wearableByDay.get(TODAY)!
  assertEquals(today.sleep, { hours: 7.5, efficiencyPct: 94, interruptions: null, latencyMin: 10, remMin: null, deepMin: null })
  assertEquals(today.recovery, { restingHr: 52, hrvRmssd: 60, avgStress: null })
  assertEquals(today.activity!.steps, 8000)
  assertEquals(today.sourceIds.sort(), [WHOOP, SOURCE.apple].sort())
  assertEquals(out.wearableByDay.size, 14)   // 13 trend days + today
  assertEquals(out.recoveryBaseline, { restingHr: 52, hrvRmssd: 61, hrvDays: 19 })
  assertEquals(out.summary.hrvMetric, "RmssdSleep")
  assertEquals(out.summary.sources, ["apple_health", "whoop"])
  assertEquals(out.summary.steps!.source, "apple_health")
})

Deno.test("no eligible rows → empty map, zero baseline days, nothing invented", () => {
  const out = buildWearableInputs([{ day: addDays(TODAY, 2), data_type_id: ID.Steps, data_source_id: SOURCE.apple, value: 1 }], { today: TODAY, patientId: "p1" })
  assertEquals(out.wearableByDay.size, 0)
  assertEquals(out.recoveryBaseline, { restingHr: null, hrvRmssd: null, hrvDays: 0 })
  assertEquals(out.summary.hrv, null)
})
