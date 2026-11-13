import { assertEquals } from "jsr:@std/assert@1"
import { purgeMemberRecords, type StorageLike } from "./member-records-purge.ts"

const PID = "74c7d368-8361-4297-bb27-8d3f9a482d7a"

/** In-memory bucket: object paths, list by prefix (one level), remove by path. */
function fakeStorage(paths: string[], opts: { failRemove?: boolean; ignoreRemove?: boolean } = {}) {
  const objects = new Set(paths)
  const removed: string[] = []
  const buckets: string[] = []
  const storage: StorageLike = {
    from(bucket) {
      buckets.push(bucket)
      return {
        list(prefix, { limit }) {
          const names = [...objects]
            .filter((p) => p.startsWith(`${prefix}/`) && !p.slice(prefix.length + 1).includes("/"))
            .map((p) => ({ name: p.slice(prefix.length + 1), id: "obj" }))
            .slice(0, limit)
          return Promise.resolve({ data: names, error: null })
        },
        remove(ps) {
          if (opts.failRemove) return Promise.resolve({ data: null, error: { message: "boom" } })
          if (!opts.ignoreRemove) for (const p of ps) { objects.delete(p); removed.push(p) }
          return Promise.resolve({ data: ps, error: null })
        },
      }
    },
  }
  return { storage, objects, removed, buckets }
}

Deno.test("removes every document and voice note of the member, in pages", async () => {
  const mine = [
    ...Array.from({ length: 5 }, (_, i) => `${PID}/files/doc-${i}.pdf`),
    `${PID}/voice/a.webm`,
    `${PID}/voice/b.m4a`,
  ]
  const someoneElse = "11111111-1111-4111-8111-111111111111/files/x.pdf"
  const f = fakeStorage([...mine, someoneElse])
  const res = await purgeMemberRecords(f.storage, PID, 2)
  assertEquals(res, { ok: true, removed: 7 })
  assertEquals([...f.objects], [someoneElse])
  assertEquals(new Set(f.buckets), new Set(["member-records"]))
})

Deno.test("a member with nothing shared is a clean no-op", async () => {
  const f = fakeStorage([])
  assertEquals(await purgeMemberRecords(f.storage, PID), { ok: true, removed: 0 })
})

Deno.test("a failed remove is reported, never swallowed", async () => {
  const f = fakeStorage([`${PID}/files/a.pdf`], { failRemove: true })
  const res = await purgeMemberRecords(f.storage, PID)
  assertEquals(res.ok, false)
})

Deno.test("a folder that will not empty is reported instead of looping forever", async () => {
  const f = fakeStorage([`${PID}/files/a.pdf`], { ignoreRemove: true })
  const res = await purgeMemberRecords(f.storage, PID, 1000, 3)
  assertEquals(res, { ok: false, error: "files did not empty after 3 rounds" })
})

Deno.test("refuses anything that is not a patient id (no prefix games)", async () => {
  const f = fakeStorage([`${PID}/files/a.pdf`])
  const res = await purgeMemberRecords(f.storage, "")
  assertEquals(res.ok, false)
  assertEquals(f.objects.size, 1)
})
