// Golden trace at the core level: canonical rows (as an adapter would return them) → the exact
// `wearable_daily` / `wearable_epoch` upserts, keys and provenance. A recording fake stands in for
// PostgREST. Per-vendor fixture traces (vendor payload → rows) land with each Phase 2 adapter PR.
import { assertEquals } from "jsr:@std/assert@1"
import { NORMALIZATION_VERSION, type RowBatch, persistRows } from "../core.ts"

type Call = { table: string; op: string; rows?: unknown; opts?: unknown; filters?: unknown[] }

function fakeDb(existingEpochs: Record<string, unknown>[] = []) {
  const calls: Call[] = []
  let ids = 0
  const from = (table: string) => {
    const build = (op: string, rows?: unknown, opts?: unknown) => {
      const call: Call = { table, op, rows, opts, filters: [] }
      calls.push(call)
      const result = () => {
        if (op === "upsert") return { data: (rows as Record<string, unknown>[]).map((r) => ({ id: `id-${++ids}`, data_type_id: r.data_type_id, start_ts: r.start_ts, source_record_id: r.source_record_id ?? null })), error: null }
        if (op === "select") return { data: existingEpochs, error: null }
        return { data: null, error: null }
      }
      const chain: Record<string, unknown> = {
        select: () => ({ then: (res: (v: unknown) => void) => res(result()) }),
        eq: (...a: unknown[]) => { call.filters!.push(["eq", ...a]); return chain },
        is: (...a: unknown[]) => { call.filters!.push(["is", ...a]); return chain },
        in: (...a: unknown[]) => { call.filters!.push(["in", ...a]); return chain },
        then: (res: (v: unknown) => void) => res(result()),
      }
      return chain
    }
    return { upsert: (rows: unknown, opts: unknown) => build("upsert", rows, opts), select: () => build("select"), update: (rows: unknown) => build("update", rows) }
  }
  return { db: { from } as unknown as Parameters<typeof persistRows>[0], calls }
}

Deno.test("golden: WHOOP-shaped rows → daily/epoch upserts with keys, provenance and alias rewriting", async () => {
  const fx = JSON.parse(await Deno.readTextFile(new URL("./fixtures/whoop_recovery_sample.json", import.meta.url))) as { rows: RowBatch }
  const { db, calls } = fakeDb()
  const counts = await persistRows(db, "patient-1", "whoop", fx.rows, "raw-1", "acc-1")
  assertEquals(counts, { daily: 3, epoch: 1 })  // the duplicate HeartRateResting collapses on (day, type)
  const daily = calls.find((c) => c.table === "wearable_daily" && c.op === "upsert")!
  assertEquals(daily.opts, { onConflict: "patient_id,data_source_id,day,data_type_id" })
  const rows = daily.rows as Record<string, unknown>[]
  assertEquals(rows.map((r) => [r.data_type_id, r.data_type_name, r.value]), [[3106, "RmssdSleep", 61.5], [3001, "HeartRateResting", 52], [5041, "SkinTemperature", 33.4]])
  assertEquals(rows[0], {
    patient_id: "patient-1", data_source_id: 1000042, day: "2026-09-13", data_type_id: 3106, data_type_name: "RmssdSleep",
    value: 61.5, value_text: null, value_type: "DOUBLE", timezone_offset: 120, details: null, raw_event_id: "raw-1", recorded_at: null,
    source_connection_id: "acc-1", source_resource_type: "recovery", source_record_id: "rec-1", source_field: null, source_device_id: null, source_modified_at: null,
    normalization_version: NORMALIZATION_VERSION, source_offset_minutes: 120, local_date_basis: "vendor_local",
  })
  const ep = calls.find((c) => c.table === "wearable_epoch" && c.op === "upsert")!
  assertEquals(ep.opts, { onConflict: "patient_id,data_source_id,data_type_id,start_ts" })
  const e = (ep.rows as Record<string, unknown>[])[0]
  assertEquals([e.data_type_id, e.start_ts, e.end_ts, e.source_record_id, e.source_resource_type], [1000102, "2026-09-13T06:10:00Z", "2026-09-13T07:00:00Z", "wk-9", "workout"])
})

Deno.test("a moved vendor record supersedes its old row instead of duplicating it", async () => {
  const old = { id: "old-1", data_type_id: 1000102, start_ts: "2026-09-13T05:00:00Z", source_record_id: "wk-9" }
  const { db, calls } = fakeDb([old])
  await persistRows(db, "patient-1", "whoop", { daily: [], epoch: [{ startTs: "2026-09-13T06:10:00Z", dataTypeId: 1000102, dataTypeName: "StrainScore", value: 8.7, sourceRecordId: "wk-9" }] }, null, "acc-1")
  const upd = calls.find((c) => c.table === "wearable_epoch" && c.op === "update")!
  assertEquals(upd.rows, { superseded_by: "id-1" })
  assertEquals(upd.filters, [["eq", "id", "old-1"]])
})

Deno.test("no provenance id → no supersede lookup", async () => {
  const { db, calls } = fakeDb()
  await persistRows(db, "p", "oura", { daily: [], epoch: [{ startTs: "2026-09-13T06:10:00Z", dataTypeId: 3000, dataTypeName: "HeartRate", value: 60 }] }, null)
  assertEquals(calls.filter((c) => c.op === "select").length, 0)
})
