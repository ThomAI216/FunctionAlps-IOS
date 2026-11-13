import { assertEquals } from "jsr:@std/assert@1"
import {
  ARCHIVE_BUCKET,
  answerFor,
  archiveOne,
  eraseMember,
  type EraseDeps,
  type ObjectStore,
  type RpcResult,
  type StoragePath,
} from "./erase.ts"

const UID = "11111111-1111-4111-8111-111111111111"
const PID = "74c7d368-8361-4297-bb27-8d3f9a482d7a"

const INVOICE_PDF: StoragePath = {
  table: "client_invoices", column: "pdf_path", row_id: "inv-1", bucket: "invoices", path: `${PID}/F-1.pdf`,
  action: "archive", archive_bucket: ARCHIVE_BUCKET, archive_path: "client_invoices/inv-1/pdf_path/F-1.pdf",
}
const T590_PDF: StoragePath = {
  table: "t590_statements", column: "pdf_path", row_id: "t-1", bucket: "invoices", path: `t590/${PID}/T-1.pdf`,
  action: "archive", archive_bucket: ARCHIVE_BUCKET, archive_path: "t590_statements/t-1/pdf_path/T-1.pdf",
}
const VOICE_NOTE: StoragePath = {
  table: "access_requests", column: "voice_audio_path", row_id: "ar-1", bucket: "access-requests",
  path: `${PID}/voice.webm`, action: "delete",
}

/** Fake deps that record every call in order. */
function fakeDeps(opts: {
  preflight?: RpcResult
  real?: RpcResult
  purgeFails?: boolean
  photos?: Record<string, string[]>
  authFails?: boolean
  archiveFails?: boolean
} = {}) {
  const calls: string[] = []
  const deps: EraseDeps = {
    selfErase(_pid, dryRun) {
      calls.push(dryRun ? "rpc:dry_run" : "rpc:erase")
      return Promise.resolve(
        dryRun
          ? (opts.preflight ?? { data: { status: "dry_run_ok", storage_paths: [] }, error: null })
          : (opts.real ?? { data: { status: "erased", storage_paths: [] }, error: null }),
      )
    },
    purgeMemberRecords() {
      calls.push("storage:member-records")
      return Promise.resolve(opts.purgeFails ? { ok: false, error: "boom" } : { ok: true, removed: 0 })
    },
    listMealPhotos(prefix) {
      calls.push(`storage:list:${prefix}`)
      return Promise.resolve({ names: opts.photos?.[prefix] ?? [], error: null })
    },
    removeMealPhotos(paths) {
      calls.push(`storage:remove:${paths.join(",")}`)
      return Promise.resolve({ error: null })
    },
    removeObjects(bucket, paths) {
      calls.push(`storage:delete:${bucket}:${paths.join(",")}`)
      return Promise.resolve({ error: null })
    },
    archiveObject(entry) {
      calls.push(`storage:archive:${entry.bucket}/${entry.path}->${entry.archive_bucket}/${entry.archive_path}`)
      return Promise.resolve({ error: opts.archiveFails ? "archive down" : null })
    },
    logDeletionWithoutPatient() {
      calls.push("log:no_patient")
      return Promise.resolve()
    },
    deleteAuthUser() {
      calls.push("auth:delete")
      return Promise.resolve({ error: opts.authFails ? "auth down" : null })
    },
  }
  return { deps, calls }
}

Deno.test("order: dry run, then storage, then the erasure RPC, then the login LAST", async () => {
  const f = fakeDeps({ photos: { [UID]: ["a.jpg"] } })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "deleted")
  assertEquals(f.calls, [
    "rpc:dry_run",
    "storage:member-records",
    `storage:list:${UID}`,
    `storage:remove:${UID}/a.jpg`,
    `storage:list:${PID}`,
    "rpc:erase",
    "auth:delete",
  ])
})

Deno.test("storage_paths from the dry run: accounting PDFs archived, operational objects purged, all BEFORE the erasure RPC", async () => {
  const f = fakeDeps({
    preflight: { data: { status: "dry_run_ok", storage_paths: [VOICE_NOTE, INVOICE_PDF, T590_PDF] }, error: null },
    real: { data: { status: "erased", storage_paths: [VOICE_NOTE, INVOICE_PDF, T590_PDF] }, error: null },
  })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "deleted")
  assertEquals(f.calls, [
    "rpc:dry_run",
    "storage:member-records",
    `storage:list:${UID}`,
    `storage:list:${PID}`,
    `storage:archive:invoices/${PID}/F-1.pdf->${ARCHIVE_BUCKET}/client_invoices/inv-1/pdf_path/F-1.pdf`,
    `storage:archive:invoices/t590/${PID}/T-1.pdf->${ARCHIVE_BUCKET}/t590_statements/t-1/pdf_path/T-1.pdf`,
    `storage:delete:access-requests:${PID}/voice.webm`,
    "rpc:erase",
    "auth:delete",
  ])
})

Deno.test("a path the real run returns that the dry run did not is still handled, before the login", async () => {
  const f = fakeDeps({
    preflight: { data: { status: "dry_run_ok", storage_paths: [] }, error: null },
    real: { data: { status: "erased", storage_paths: [INVOICE_PDF] }, error: null },
  })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "deleted")
  assertEquals(f.calls.slice(-3), [
    "rpc:erase",
    `storage:archive:invoices/${PID}/F-1.pdf->${ARCHIVE_BUCKET}/client_invoices/inv-1/pdf_path/F-1.pdf`,
    "auth:delete",
  ])
})

Deno.test("an archive failure stops before the erasure RPC and keeps the login", async () => {
  const f = fakeDeps({
    preflight: { data: { status: "dry_run_ok", storage_paths: [INVOICE_PDF] }, error: null },
    archiveFails: true,
  })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "failed")
  assertEquals(f.calls.includes("rpc:erase"), false)
  assertEquals(f.calls.includes("auth:delete"), false)
})

Deno.test("an archive entry aimed anywhere but the restricted bucket is refused with nothing touched", async () => {
  const f = fakeDeps({
    preflight: { data: { status: "dry_run_ok", storage_paths: [{ ...INVOICE_PDF, archive_bucket: "invoices-public" }] }, error: null },
  })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "failed")
  assertEquals(f.calls, ["rpc:dry_run"])
  if (out.kind !== "deleted") assertEquals(answerFor(out).body.message.includes("nothing has been deleted"), true)
})

Deno.test("a database refusal at preflight touches NOTHING and is a refusal, not a crash", async () => {
  const f = fakeDeps({ preflight: { data: null, error: { message: "erasure blocked by foreign keys on: ...", code: "23503" } } })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "refused")
  assertEquals(f.calls, ["rpc:dry_run"])
})

Deno.test("an unclassified-table refusal (22023) is also a refusal with nothing touched", async () => {
  const f = fakeDeps({ preflight: { data: null, error: { message: "erasure blocked: unclassified table(s) {x}", code: "22023" } } })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "refused")
  assertEquals(f.calls, ["rpc:dry_run"])
})

Deno.test("a transient preflight error stops before anything irreversible", async () => {
  const f = fakeDeps({ preflight: { data: null, error: { message: "canceling statement due to lock timeout", code: "55P03" } } })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out, { kind: "failed", step: "preflight", nothingTouched: true, detail: "canceling statement due to lock timeout" })
  assertEquals(f.calls, ["rpc:dry_run"])
})

Deno.test("any non-refusal error answers 'contact support', never a retry-forever 503", () => {
  const outcomes = [
    { kind: "failed", step: "preflight", nothingTouched: true, detail: "canceling statement due to statement timeout" },
    { kind: "failed", step: "lookup", nothingTouched: true, detail: "connection reset" },
    { kind: "failed", step: "database", nothingTouched: false, detail: "connection reset" },
    { kind: "failed", step: "login", nothingTouched: false, detail: "auth down" },
    { kind: "refused", step: "preflight", code: "22023", detail: "x" },
    { kind: "refused", step: "database", code: "23503", detail: "x" },
  ] as const
  for (const o of outcomes) {
    const a = answerFor(o)
    assertEquals(a.status === 503, false, `${o.kind}/${o.step} answered 503`)
    assertEquals(a.status, 409, `${o.kind}/${o.step} should answer 409 so every client shows the message`)
    assertEquals(a.body.deleted, false)
    assertEquals(a.body.message.includes("support@functionalps.ch"), true, `${o.kind}/${o.step}: ${a.body.message}`)
  }
  assertEquals(answerFor({ kind: "failed", step: "preflight", nothingTouched: true, detail: "x" }).body.message.includes("nothing has been deleted"), true)
})

Deno.test("a storage failure stops before the database erasure and before the login", async () => {
  const f = fakeDeps({ purgeFails: true })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "failed")
  assertEquals(f.calls, ["rpc:dry_run", "storage:member-records"])
})

Deno.test("a database failure keeps the login", async () => {
  const f = fakeDeps({ real: { data: null, error: { message: "connection reset" } } })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "failed")
  assertEquals(f.calls.includes("auth:delete"), false)
})

Deno.test("retry after a failed login deletion: patient already erased, only the login goes", async () => {
  // The tombstone has no auth link, so the handler finds no patient for this uid.
  const f = fakeDeps()
  const out = await eraseMember(f.deps, UID, null)
  assertEquals(out.kind, "deleted")
  assertEquals(f.calls, [`storage:list:${UID}`, "log:no_patient", "auth:delete"])
})

Deno.test("an already-erased patient passes the preflight and is not erased twice by mistake", async () => {
  const f = fakeDeps({ preflight: { data: { status: "already_erased" }, error: null }, real: { data: { status: "already_erased" }, error: null } })
  const out = await eraseMember(f.deps, UID, PID)
  assertEquals(out.kind, "deleted")
  assertEquals(f.calls.at(-1), "auth:delete")
})

// archiveOne: copy into the restricted bucket, then remove the original. Idempotent on retry.
function fakeStore(objects: Record<string, string>, failUpload = false) {
  const calls: string[] = []
  const store: ObjectStore = {
    exists(bucket, path) {
      calls.push(`exists:${bucket}/${path}`)
      return Promise.resolve({ exists: `${bucket}/${path}` in objects, error: null })
    },
    download(bucket, path) {
      calls.push(`download:${bucket}/${path}`)
      const v = objects[`${bucket}/${path}`]
      return Promise.resolve(v === undefined ? { data: null, error: "not found" } : { data: new Blob([v]), error: null })
    },
    upload(bucket, path, data) {
      calls.push(`upload:${bucket}/${path}`)
      if (failUpload) return Promise.resolve({ error: "upload failed" })
      return data.text().then((t) => { objects[`${bucket}/${path}`] = t; return { error: null } })
    },
    remove(bucket, path) {
      calls.push(`remove:${bucket}/${path}`)
      delete objects[`${bucket}/${path}`]
      return Promise.resolve({ error: null })
    },
  }
  return { store, calls, objects }
}

Deno.test("archiveOne copies to the restricted bucket and only then removes the original", async () => {
  const s = fakeStore({ [`invoices/${PID}/F-1.pdf`]: "pdf" })
  assertEquals(await archiveOne(s.store, INVOICE_PDF), { error: null })
  assertEquals(s.objects, { [`${ARCHIVE_BUCKET}/client_invoices/inv-1/pdf_path/F-1.pdf`]: "pdf" })
  assertEquals(s.calls.indexOf(`remove:invoices/${PID}/F-1.pdf`) > s.calls.indexOf(`upload:${ARCHIVE_BUCKET}/client_invoices/inv-1/pdf_path/F-1.pdf`), true)
})

Deno.test("archiveOne keeps the original when the copy fails", async () => {
  const s = fakeStore({ [`invoices/${PID}/F-1.pdf`]: "pdf" }, true)
  const r = await archiveOne(s.store, INVOICE_PDF)
  assertEquals(r.error !== null, true)
  assertEquals(`invoices/${PID}/F-1.pdf` in s.objects, true)
})

Deno.test("archiveOne on retry: already archived, nothing left to move, success", async () => {
  const s = fakeStore({ [`${ARCHIVE_BUCKET}/client_invoices/inv-1/pdf_path/F-1.pdf`]: "pdf" })
  assertEquals(await archiveOne(s.store, INVOICE_PDF), { error: null })
  assertEquals(s.calls.some((c) => c.startsWith("upload:") || c.startsWith("remove:")), false)
})
