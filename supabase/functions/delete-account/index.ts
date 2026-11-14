// delete-account — GDPR / revFADP right to erasure. The caller can only delete THEMSELVES
// (uid taken from their own JWT).
//
// The order is in ./erase.ts (tested in erase.test.ts): a dry run of the database erasure
// first, then storage, then the database erasure (CM OS RPC public.member_self_erase: ONE
// transaction that deletes the operational rows, keeps the clinical file / invoices / consent
// evidence without identity, crypto-shreds the PII vault and tombstones the patient row), then
// the auth user LAST. Until 2026-11-13 the vault was shredded first and the patient-row delete
// then failed on FK blockers with a 500 for 20 of 37 members.
//
// Since 2026-11-13 (CLINICAL migration 20261113_member_self_erase_v2) the RPC also returns
// `storage_paths`: invoice / T590 / signed-contract PDFs are MOVED to the restricted
// `erasure-archive` bucket (10-year accounting retention, service role only), operational objects
// (access-request voice notes) are purged. Both happen before the database erasure.
//
// Every failure answers 409 with a plain "contact support" message (erase.ts answerFor); there is
// no retryable 503 any more. On success, best-effort
// sends a sovereign confirmation email via the shared mailer. The email is fully isolated
// (sendEmail never throws) so a mailer failure can NEVER block or break the erasure.
//
// Sender profile: `thomas` — an account/legal notice, from a named person, with
// Reply-To pointing at the shared support inbox. See _shared/sender-profiles.ts.
import { createClient } from "jsr:@supabase/supabase-js@2"
import { sendEmail, type EmailResult } from "../_shared/email.ts"
import { purgeMemberRecords } from "../_shared/member-records-purge.ts"
import { answerFor, archiveOne, eraseMember, type ObjectStore } from "./erase.ts"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } })


// Sovereign confirmation email. Delegated to the shared mailer so the SMTP
// config, the 465/TLS rule and the real-error reporting live in ONE place.
async function sendDeletionEmail(to: string): Promise<EmailResult> {
  return await sendEmail({
    sender: "thomas",
    to,
    subject: "Your FunctionAlps account has been deleted",
    text:
      "Your FunctionAlps account has been deleted. Your profile, contact details, meals, photos, diaries and check-ins have been permanently erased. Records we are legally required to keep are retained under that legal duty: your clinical file without your name or contact details, and your invoices for the 10-year accounting period in a restricted archive. If you did not request this, contact support@functionalps.ch immediately.",
    html: `<div style="font-family:system-ui,-apple-system,Arial,sans-serif;max-width:480px;margin:0 auto;color:#1A1A16;line-height:1.5">
  <h2 style="color:#2f5d3a;margin:0 0 12px">Your account has been deleted</h2>
  <p>Your FunctionAlps account has been deleted. Your profile, contact details, meals, photos, diaries and check-ins have been <strong>permanently erased</strong>. Records we are legally required to keep are retained under that legal duty: your clinical file without your name or contact details, and your invoices for the 10-year accounting period in a restricted archive.</p>
  <p>This cannot be undone. If you did <strong>not</strong> request this, please contact <a href="mailto:support@functionalps.ch">support@functionalps.ch</a> immediately.</p>
  <p style="color:#6b7280;font-size:13px;margin-top:20px">FunctionAlps · Switzerland 🇨🇭</p>
</div>`,
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })

  const authHeader = req.headers.get("Authorization")
  if (!authHeader) return json({ error: "Missing Authorization" }, 401)

  const url = Deno.env.get("SUPABASE_URL")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!url || !anonKey || !serviceKey) return json({ error: "Server not configured" }, 500)

  // Identify the caller from their own JWT — they can only erase themselves.
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } })
  const { data: { user }, error: userErr } = await userClient.auth.getUser()
  if (userErr || !user) return json({ error: "Not authenticated" }, 401)
  const uid = user.id
  const userEmail = user.email ?? null

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } })

  // Resolve the CM OS patient row for this auth user. A lookup ERROR must stop us: carrying on
  // with "no patient" would delete the login and leave the whole patient row behind.
  const { data: patientRow, error: lookupErr } = await admin
    .from("patients")
    .select("id")
    .eq("auth_user_id", uid)
    .maybeSingle()
  if (lookupErr) {
    console.error(`[delete-account] failed at lookup: ${lookupErr.message}`)
    const a = answerFor({ kind: "failed", step: "lookup", nothingTouched: true, detail: lookupErr.message })
    return json(a.body, a.status)
  }
  const patientId = (patientRow as { id: string } | null)?.id ?? null

  // Storage operations for the restricted archive (copy, check, then remove the original).
  const store: ObjectStore = {
    exists: async (bucket, path) => {
      const slash = path.lastIndexOf("/")
      const dir = slash >= 0 ? path.slice(0, slash) : ""
      const name = slash >= 0 ? path.slice(slash + 1) : path
      const { data, error } = await admin.storage.from(bucket).list(dir, { limit: 100, search: name })
      if (error) return { exists: false, error: error.message }
      return { exists: (data ?? []).some((f) => f.name === name), error: null }
    },
    download: async (bucket, path) => {
      const { data, error } = await admin.storage.from(bucket).download(path)
      return { data: data ?? null, error: error ? error.message : null }
    },
    upload: async (bucket, path, data) => {
      const { error } = await admin.storage.from(bucket).upload(path, data, {
        upsert: true,
        contentType: data.type || "application/pdf",
      })
      return { error: error ? error.message : null }
    },
    remove: async (bucket, path) => {
      const { error } = await admin.storage.from(bucket).remove([path])
      return { error: error ? error.message : null }
    },
  }

  const outcome = await eraseMember({
    selfErase: async (pid, dryRun) => {
      const { data, error } = await admin.rpc("member_self_erase", { p_patient_id: pid, p_dry_run: dryRun })
      return { data, error: error ? { message: error.message, code: error.code } : null }
    },
    purgeMemberRecords: (pid) => purgeMemberRecords(admin.storage, pid),
    listMealPhotos: async (prefix) => {
      const { data, error } = await admin.storage.from("meal-images").list(prefix, { limit: 1000 })
      return { names: (data ?? []).map((f) => f.name), error: error ? error.message : null }
    },
    removeMealPhotos: async (paths) => {
      const { error } = await admin.storage.from("meal-images").remove(paths)
      return { error: error ? error.message : null }
    },
    // Objects of rows the erasure deletes (a missing object is not an error for remove()).
    removeObjects: async (bucket, paths) => {
      const { error } = await admin.storage.from(bucket).remove(paths)
      return { error: error ? error.message : null }
    },
    archiveObject: (entry) => archiveOne(store, entry),
    // No patient row (never registered, or already erased and only the login is left).
    logDeletionWithoutPatient: async (u) => {
      try {
        await admin.from("deletion_log").insert({ deleted_user_id: u, deleted_patient_id: null, source: "self_serve" })
      } catch (_e) { /* best effort */ }
    },
    deleteAuthUser: async (u) => {
      const { error } = await admin.auth.admin.deleteUser(u)
      return { error: error ? error.message : null }
    },
  }, uid, patientId)

  if (outcome.kind !== "deleted") {
    // The detail stays in the function log (support reads it); the member gets the plain message.
    console.error(
      `[delete-account] ${outcome.kind} at ${outcome.step}` +
        (outcome.kind === "refused" ? ` (${outcome.code})` : "") + `: ${outcome.detail}`,
    )
    const a = answerFor(outcome)
    return json(a.body, a.status)
  }

  // Best-effort sovereign confirmation email — isolated; never blocks the completed erasure.
  let emailResult: EmailResult = { status: "skipped" }
  if (userEmail) {
    try {
      emailResult = await sendDeletionEmail(userEmail)
    } catch (e) {
      emailResult = { status: "failed", error: e instanceof Error ? e.message : String(e) }
    }
  }

  return json({ deleted: true, email: emailResult.status, emailError: emailResult.error })
})
