// supabase/functions/_shared/member-records-purge.ts
//
// Erase what a member shared from the members dashboard's Lab Results ›
// Previous records: documents under `<patientId>/files/` and voice notes under
// `<patientId>/voice/` in the private `member-records` bucket (MEMBERS migration
// 20261021000100). Storage does not cascade; the member_record_* ROWS do
// (patient_id FK, ON DELETE CASCADE), so after the patient row is gone nothing
// would point at these objects any more. They must go BEFORE the row.
//
// Copies the care team saved to the clinical record live in `lab-reports`, under
// a different layout, and are not touched here.
//
// Zero imports: Deno and the test below load this exact file, with a fake client.

export const MEMBER_RECORDS_BUCKET = "member-records"
export const MEMBER_RECORDS_FOLDERS = ["files", "voice"] as const

/** The slice of the Supabase storage client this needs. */
export interface StorageLike {
  from(bucket: string): {
    list(
      prefix: string,
      opts: { limit: number },
    ): Promise<{ data: Array<{ name: string; id: string | null }> | null; error: { message: string } | null }>
    remove(paths: string[]): Promise<{ data: unknown; error: { message: string } | null }>
  }
}

export type PurgeResult = { ok: true; removed: number } | { ok: false; error: string }

/**
 * Remove every object under the member's two folders. Re-lists until a folder
 * is empty (a list returns at most `pageSize`), and fails — never silently —
 * when a list or a remove errors, or when a folder will not empty.
 */
export async function purgeMemberRecords(
  storage: StorageLike,
  patientId: string,
  pageSize = 1000,
  maxRounds = 50,
): Promise<PurgeResult> {
  if (!/^[0-9a-f-]{36}$/i.test(patientId)) return { ok: false, error: "invalid patient id" }
  const bucket = storage.from(MEMBER_RECORDS_BUCKET)
  let removed = 0
  for (const folder of MEMBER_RECORDS_FOLDERS) {
    const prefix = `${patientId}/${folder}`
    let emptied = false
    for (let round = 0; round < maxRounds; round++) {
      const { data, error } = await bucket.list(prefix, { limit: pageSize })
      if (error) return { ok: false, error: `list ${folder}: ${error.message}` }
      // Folders come back with id null; only objects are removable.
      const paths = (data ?? []).filter((o) => o.id !== null && o.name).map((o) => `${prefix}/${o.name}`)
      if (paths.length === 0) {
        emptied = true
        break
      }
      const { error: rmErr } = await bucket.remove(paths)
      if (rmErr) return { ok: false, error: `remove ${folder}: ${rmErr.message}` }
      removed += paths.length
    }
    if (!emptied) return { ok: false, error: `${folder} did not empty after ${maxRounds} rounds` }
  }
  return { ok: true, removed }
}
