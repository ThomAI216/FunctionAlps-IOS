// supabase/functions/delete-account/erase.ts
//
// The ORDER of a member's self-erasure, kept apart from the HTTP handler so it can be tested
// with fakes (erase.test.ts). Reviewed 2026-11-13 after the 500-after-vault-shred bug.
//
// Rule: nothing irreversible happens until the database part is KNOWN to succeed, and the
// database part is ONE transaction (CM OS RPC public.member_self_erase, migrations
// 20261113_member_self_erase + 20261113_member_self_erase_v2 in CLINICAL).
//   A. preflight   member_self_erase(dry_run = true): runs the real work and rolls it back.
//                  Any blocker stops us here with NOTHING touched. It also returns
//                  `storage_paths`: the objects whose rows the erasure deletes or blanks.
//   B. storage     member-records (fails closed), meal photos (fails closed), then the RPC's
//                  storage_paths: 'archive' = an invoice / T590 / signed-contract PDF kept for the
//                  10-year accounting retention, moved to the restricted `erasure-archive` bucket
//                  (no storage policy: service role only); 'delete' = an operational object, purged.
//                  Idempotent, so a retry is safe.
//   C. database    member_self_erase(dry_run = false): deletes the operational rows, keeps the
//                  clinical file / invoices / consent evidence without identity, strips email
//                  addresses, crypto-shreds the PII vault, tombstones the patient row. All or
//                  nothing. A path it returns that the dry run did not (a PDF filed in between)
//                  is handled right after it, still before the login.
//   D. auth user   LAST. If it fails, a retry finds no patient linked to the login and only
//                  repeats this step.
// Any failure answers 409 with a "contact support" message: the member is never told to retry
// forever (owner decision 2026-11-13).
//
// Zero imports: Deno and the test load this exact file.

export type RpcError = { message: string; code?: string }
export type RpcResult = { data: unknown; error: RpcError | null }
export type PurgeResult = { ok: true; removed?: number } | { ok: false; error: string }

/** The restricted bucket the migration defines (20261113_member_self_erase_v2). Nothing else is accepted. */
export const ARCHIVE_BUCKET = "erasure-archive"

export type StoragePath = {
  table: string
  column: string
  row_id: string
  bucket: string
  path: string
  action: "delete" | "archive"
  archive_bucket?: string
  archive_path?: string
}

export interface EraseDeps {
  selfErase(patientId: string, dryRun: boolean): Promise<RpcResult>
  purgeMemberRecords(patientId: string): Promise<PurgeResult>
  listMealPhotos(prefix: string): Promise<{ names: string[]; error: string | null }>
  removeMealPhotos(paths: string[]): Promise<{ error: string | null }>
  removeObjects(bucket: string, paths: string[]): Promise<{ error: string | null }>
  archiveObject(entry: StoragePath): Promise<{ error: string | null }>
  logDeletionWithoutPatient(uid: string): Promise<void>
  deleteAuthUser(uid: string): Promise<{ error: string | null }>
}

export type EraseOutcome =
  | { kind: "deleted"; erasure: unknown }
  // The database refused (a blocker, an unclassified table, a missing grant).
  | { kind: "refused"; step: "preflight" | "database"; code: string | null; detail: string }
  // Anything else.
  | { kind: "failed"; step: string; nothingTouched: boolean; detail: string }

// SQLSTATEs member_self_erase raises on purpose: FK blocker, unclassified table, wrong caller.
const REFUSAL_CODES = new Set(["23503", "22023", "42501"])
const DONE = new Set(["erased", "no_patient", "already_erased"])

function statusOf(data: unknown): string | null {
  return data && typeof data === "object" && "status" in data
    ? String((data as { status: unknown }).status)
    : null
}

/** Reads `storage_paths` strictly: an unknown action or an archive outside the restricted bucket is an error. */
export function parseStoragePaths(data: unknown): { paths: StoragePath[]; error: string | null } {
  if (!data || typeof data !== "object" || !("storage_paths" in data)) return { paths: [], error: null }
  const raw = (data as { storage_paths: unknown }).storage_paths
  if (raw == null) return { paths: [], error: null }
  if (!Array.isArray(raw)) return { paths: [], error: "storage_paths is not a list" }
  const paths: StoragePath[] = []
  for (const e of raw) {
    const p = e as Partial<StoragePath>
    if (!p || typeof p.bucket !== "string" || !p.bucket || typeof p.path !== "string" || !p.path) {
      return { paths: [], error: "storage_paths entry without bucket/path" }
    }
    if (p.action === "delete") {
      paths.push(p as StoragePath)
    } else if (p.action === "archive") {
      if (p.archive_bucket !== ARCHIVE_BUCKET || typeof p.archive_path !== "string" || !p.archive_path) {
        return { paths: [], error: `archive target must be ${ARCHIVE_BUCKET}, got ${String(p.archive_bucket)}` }
      }
      paths.push(p as StoragePath)
    } else {
      return { paths: [], error: `unknown storage action ${String(p.action)}` }
    }
  }
  return { paths, error: null }
}

const keyOf = (p: StoragePath) => `${p.bucket}/${p.path}`

/** Archive first (the kept PDFs), then purge the deletable objects, grouped by bucket. */
async function handlePaths(deps: EraseDeps, paths: StoragePath[]): Promise<string | null> {
  for (const p of paths.filter((x) => x.action === "archive")) {
    const r = await deps.archiveObject(p)
    if (r.error) return `archive ${keyOf(p)}: ${r.error}`
  }
  const byBucket = new Map<string, string[]>()
  for (const p of paths.filter((x) => x.action === "delete")) {
    byBucket.set(p.bucket, [...(byBucket.get(p.bucket) ?? []), p.path])
  }
  for (const [bucket, list] of byBucket) {
    const r = await deps.removeObjects(bucket, list)
    if (r.error) return `delete in ${bucket}: ${r.error}`
  }
  return null
}

export async function eraseMember(deps: EraseDeps, uid: string, patientId: string | null): Promise<EraseOutcome> {
  let erasure: unknown = null
  let planned: StoragePath[] = []

  // A) preflight — nothing is touched before this has passed.
  if (patientId) {
    const pre = await deps.selfErase(patientId, true)
    if (pre.error) {
      const code = pre.error.code ?? null
      if (code && REFUSAL_CODES.has(code)) {
        return { kind: "refused", step: "preflight", code, detail: pre.error.message }
      }
      return { kind: "failed", step: "preflight", nothingTouched: true, detail: pre.error.message }
    }
    const s = statusOf(pre.data)
    if (s !== "dry_run_ok" && (s === null || !DONE.has(s))) {
      return { kind: "failed", step: "preflight", nothingTouched: true, detail: `unexpected status ${s}` }
    }
    const parsed = parseStoragePaths(pre.data)
    if (parsed.error) return { kind: "failed", step: "preflight", nothingTouched: true, detail: parsed.error }
    planned = parsed.paths
  }

  // B) storage (does not cascade). Fail closed: an error here leaves the database untouched; files
  //    left behind would be a silent, incomplete erasure.
  if (patientId) {
    const purge = await deps.purgeMemberRecords(patientId)
    if (!purge.ok) return { kind: "failed", step: "shared documents", nothingTouched: false, detail: purge.error }
  }
  // Meal photos: new ones sit under the auth id, older ones under the patient id.
  for (const prefix of [uid, patientId].filter(Boolean) as string[]) {
    const listed = await deps.listMealPhotos(prefix)
    if (listed.error) return { kind: "failed", step: "meal photos", nothingTouched: false, detail: listed.error }
    if (listed.names.length > 0) {
      const rm = await deps.removeMealPhotos(listed.names.map((n) => `${prefix}/${n}`))
      if (rm.error) return { kind: "failed", step: "meal photos", nothingTouched: false, detail: rm.error }
    }
  }
  const handled = new Set(planned.map(keyOf))
  const pathErr = await handlePaths(deps, planned)
  if (pathErr) return { kind: "failed", step: "stored documents", nothingTouched: false, detail: pathErr }

  // C) the database part, one transaction (writes its own deletion_log row).
  if (patientId) {
    const done = await deps.selfErase(patientId, false)
    if (done.error) {
      const code = done.error.code ?? null
      if (code && REFUSAL_CODES.has(code)) {
        return { kind: "refused", step: "database", code, detail: done.error.message }
      }
      return { kind: "failed", step: "database", nothingTouched: false, detail: done.error.message }
    }
    const s = statusOf(done.data)
    if (s === null || !DONE.has(s)) {
      return { kind: "failed", step: "database", nothingTouched: false, detail: `unexpected status ${s}` }
    }
    erasure = done.data
    const after = parseStoragePaths(done.data)
    const late = after.paths.filter((p) => !handled.has(keyOf(p)))
    const lateErr = after.error ?? (late.length > 0 ? await handlePaths(deps, late) : null)
    if (lateErr) return { kind: "failed", step: "stored documents after erasure", nothingTouched: false, detail: lateErr }
  } else {
    await deps.logDeletionWithoutPatient(uid)
  }

  // D) the login, last.
  const auth = await deps.deleteAuthUser(uid)
  if (auth.error) return { kind: "failed", step: "login", nothingTouched: false, detail: auth.error }

  return { kind: "deleted", erasure }
}

// ---- the HTTP answer --------------------------------------------------------------------------
const SUPPORT = "support@functionalps.ch"
export const MSG_NOTHING_DELETED =
  `Your account could not be deleted automatically, and nothing has been deleted. Please contact ${SUPPORT} and we will complete it for you.`
export const MSG_PARTIAL =
  `Your account deletion did not finish. Some of your files may already be removed; your account and records are still there. Please contact ${SUPPORT} and we will complete it for you.`
export const MSG_LOGIN_LEFT =
  `Your data has been erased, but your login could not be removed. Please contact ${SUPPORT} and we will finish it for you.`

export type Answer = {
  status: number
  body: { deleted: false; code: "erasure_refused" | "erasure_failed"; error: string; message: string; step: string }
}

/**
 * Every failure answers 409 with a plain "contact support" message, which every client shows
 * (the iOS app shows a 409 body's message; a 5xx only says "server error"). No 503: a member
 * must never be told to retry something that will keep failing.
 */
export function answerFor(outcome: Exclude<EraseOutcome, { kind: "deleted" }>): Answer {
  const nothingDeleted = outcome.kind === "refused" ? outcome.step === "preflight" : outcome.nothingTouched
  const message = nothingDeleted
    ? MSG_NOTHING_DELETED
    : outcome.kind === "failed" && outcome.step === "login"
    ? MSG_LOGIN_LEFT
    : MSG_PARTIAL
  return {
    status: 409,
    body: {
      deleted: false,
      code: outcome.kind === "refused" ? "erasure_refused" : "erasure_failed",
      error: message,
      message,
      step: outcome.step,
    },
  }
}

// ---- archiving one object into the restricted bucket ----------------------------------------
export interface ObjectStore {
  exists(bucket: string, path: string): Promise<{ exists: boolean; error: string | null }>
  download(bucket: string, path: string): Promise<{ data: Blob | null; error: string | null }>
  upload(bucket: string, path: string, data: Blob): Promise<{ error: string | null }>
  remove(bucket: string, path: string): Promise<{ error: string | null }>
}

/**
 * Copy the object into the restricted archive, then remove the original (never the other way
 * round). On a retry the original is already gone and the archive holds it: success. If the
 * original never existed (a row can point at a PDF that failed to render), there is nothing to
 * keep: success too.
 */
export async function archiveOne(store: ObjectStore, entry: StoragePath): Promise<{ error: string | null }> {
  if (entry.action !== "archive" || entry.archive_bucket !== ARCHIVE_BUCKET || !entry.archive_path) {
    return { error: "not an archive entry for the restricted bucket" }
  }
  const src = await store.exists(entry.bucket, entry.path)
  if (src.error) return { error: src.error }
  if (!src.exists) return { error: null }
  const dl = await store.download(entry.bucket, entry.path)
  if (dl.error || !dl.data) return { error: dl.error ?? "empty download" }
  const up = await store.upload(ARCHIVE_BUCKET, entry.archive_path, dl.data)
  if (up.error) return { error: up.error }
  const copied = await store.exists(ARCHIVE_BUCKET, entry.archive_path)
  if (copied.error || !copied.exists) return { error: copied.error ?? "archived copy not found" }
  const rm = await store.remove(entry.bucket, entry.path)
  return { error: rm.error }
}
