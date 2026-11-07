// Vendor deletions (2026-11-06): `deleteVendorRecord` removes ONLY the rows stored from one vendor record — this member,
// this vendor's source id, this `source_record_id`, this resource type — from both row tables, reads back what it
// deleted (`.select("id")`, so zero rows is never reported as success), and throws on a PostgREST error.
import { assertEquals, assertRejects } from "jsr:@std/assert@1"
import type { SupabaseClient } from "npm:@supabase/supabase-js@2"
import { VENDOR_SOURCE_IDS, deleteVendorRecord } from "../core.ts"

type Call = { table: string; op: string; filters: [string, unknown][]; selected: string | null }
function fakeDb(result: (table: string) => { data: unknown[] | null; error: { message: string } | null }) {
  const calls: Call[] = []
  const db = {
    from(table: string) {
      const call: Call = { table, op: "", filters: [], selected: null }
      calls.push(call)
      const b = {
        delete() { call.op = "delete"; return b },
        eq(col: string, v: unknown) { call.filters.push([col, v]); return b },
        select(cols: string) { call.selected = cols; return Promise.resolve(result(table)) },
      }
      return b
    },
  }
  return { db: db as unknown as SupabaseClient, calls }
}

Deno.test("deletes from both tables, scoped to member + vendor source + record + resource type, and counts what went", async () => {
  const { db, calls } = fakeDb((t) => ({ data: t === "wearable_daily" ? [{ id: 1 }, { id: 2 }] : [{ id: 3 }], error: null }))
  const out = await deleteVendorRecord(db, "patient-1", "whoop", "sleep-uuid", "sleep")
  assertEquals(out, { daily: 2, epoch: 1 })
  assertEquals(calls.map((c) => c.table), ["wearable_daily", "wearable_epoch"])
  for (const c of calls) {
    assertEquals(c.op, "delete")
    assertEquals(c.filters, [["patient_id", "patient-1"], ["data_source_id", VENDOR_SOURCE_IDS.whoop], ["source_record_id", "sleep-uuid"], ["source_resource_type", "sleep"]])
    assertEquals(c.selected, "id")
  }
})

Deno.test("without a resource type only the record id narrows it (still member + source scoped); an error is thrown, not swallowed", async () => {
  const ok = fakeDb(() => ({ data: [], error: null }))
  await deleteVendorRecord(ok.db, "patient-1", "whoop", "w-1")
  assertEquals(ok.calls[0].filters.map(([c]) => c), ["patient_id", "data_source_id", "source_record_id"])
  const bad = fakeDb(() => ({ data: null, error: { message: "permission denied" } }))
  await assertRejects(() => deleteVendorRecord(bad.db, "patient-1", "whoop", "w-1", "workout"), Error, "permission denied")
})
