// patient-register — create/link the clinical patient row for a signed-in member.
//
// DEPLOYED 2026-08-13, after migration 20260811000100 widened the entitlement
// CHECK constraints. That order is load-bearing: deployed before the migration,
// every discovery grant below fails silently against the old constraint and
// every new member lands blocked, which is the bug this exists to fix.
//
//   supabase functions deploy patient-register --project-ref ndojytvvlvlbgtodujkf
//
// ⚠️ THIS SOURCE IS DUPLICATED BYTE-FOR-BYTE IN FOUR REPOS: MEMBERS, CLINICAL,
// APP and (since 2026-09-25) FunctionAlps-IOS, which deployed v57 and is the
// copy the iOS app is written against. Any edit must be synced to all four and
// deployed once. Before deploying, grep the copies for `vaultPii`,
// `canonical_email_hash` and `existing-identity` and confirm they match: the
// first two are the PII vault write and the "one email, one patient" dedup key,
// the third is the refusal the iOS app models; a copy that has drifted will
// either strand plaintext identity in `patients`, create duplicate patient
// rows, or hand a session an id it does not own.
//
// WHAT CHANGED IN v57 (2026-09-25, FunctionAlps-IOS):
//   1. The "one email = one patient" key is the VERIFIED email from the session
//      (`user.email`, confirmed), never the request body. The body's email is
//      what goes into the member's own vault and nothing else. Before, any
//      signed-in caller could put someone else's address in the body and, on
//      Case A, be LINKED to that person's clinician-created record.
//   2. Case B (the mailbox already owns a patient under a different auth user)
//      answers 409 `{ error: "existing-identity", providers }` and records
//      NOTHING. It used to stamp `user_metadata.patient_id` with the other
//      account's id, grant discovery on that row and answer 200 — and the apps
//      trusted the id, minting sessions every RLS policy denies. Seen live
//      2026-09-25: a member's Gmail dot alias through Google after an
//      email/password account, four consent saves refused with 403.
//
// WHAT CHANGED IN v-NEXT (2026-08-11 access-tier redesign):
//   ensureDiscoveryAccess() grants the `discovery` tier and seeds the library
//   veil on every path that ends with a patient this auth user owns. This is the
//   fix for the incident that started this work: creation paths that produced a
//   patient row and no entitlement, leaving real people signed in and stuck on a
//   waitlist screen nobody was watching.
//
// The PII vault behaviour is UNCHANGED: identity columns stay NULL and the
// encrypted vault is the only identity store, with plaintext written only when
// the vault write fails so a patient is never nameless.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

// Default clinic for all self-registered app patients
const DEFAULT_CLINIC_ID = "00000000-0000-0000-0000-000000000010"

// ── Sovereign PII crypto (mirror supabase/functions/_shared/sovereign-crypto.ts) ──
// AES-256-GCM, key = SOVEREIGN_KEK_HEX (32 bytes). Output: base64(iv(12) | ct | tag(16)).
function hexToBytes(hex: string): Uint8Array {
  const clean = hex.trim().replace(/^0x/i, "")
  const out = new Uint8Array(clean.length / 2)
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16)
  return out
}
function bytesToB64(bytes: Uint8Array): string {
  let s = ""
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s)
}
async function encryptField(plain: string, kekHex: string): Promise<string> {
  const raw = hexToBytes(kekHex)
  if (raw.length !== 32) throw new Error(`SOVEREIGN_KEK_HEX must be 32 bytes (got ${raw.length})`)
  const key = await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["encrypt"])
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plain)))
  const out = new Uint8Array(iv.length + ct.length)
  out.set(iv, 0)
  out.set(ct, iv.length)
  return bytesToB64(out)
}

// Encrypt name/email into the pii.* vault and link it to the patient.
// PHASE-3 STEADY STATE: the vault is the ONLY identity store — the plaintext
// patients columns stay NULL. Returns whether the vault write succeeded; the
// caller writes plaintext ONLY as a fallback when it didn't (a patient must
// never end up nameless everywhere).
async function vaultPii(
  adminClient: SupabaseClient, patientId: string, authUserId: string,
  firstName: string, lastName: string, email: string,
): Promise<boolean> {
  try {
    const kek = Deno.env.get("SOVEREIGN_KEK_HEX")
    if (!kek) return false
    const fullName = `${firstName} ${lastName}`.trim()
    const { data: internalId, error } = await adminClient.rpc("pii_insert_patient", {
      p_full_name_enc: await encryptField(fullName, kek),
      p_email_enc: await encryptField(email.trim(), kek),
      p_phone_enc: null,
      p_dob_enc: null,
      p_jurisdiction: "CH",
      p_created_by: authUserId,
    })
    if (error) throw error
    if (!internalId) return false
    const { error: linkErr } = await adminClient.from("patients").update({ pii_internal_id: internalId }).eq("id", patientId)
    if (linkErr) throw linkErr
    return true
  } catch (e) {
    console.error("[patient-register] PII vault failed (plaintext fallback will be written):", e instanceof Error ? e.message : e)
    return false
  }
}

// ── Discovery access (2026-08-11 access-tier redesign) ──────────────────────
// Every path out of this function must leave the member ABLE TO GET IN. Before
// this, a patient row could exist with no entitlement at all, which resolved to
// no_access and dead-ended on the waitlist screen.
//
// Idempotent and non-destructive by construction:
//   - grants ONLY when the patient has no live entitlement, so a client who was
//     already granted full_access (clinician-created, or a pending grant claimed
//     at login) never collects a redundant discovery row;
//   - seeds `member_library_access` with ignoreDuplicates, so a practitioner who
//     has already opened tracks for this member never has it reset to false by a
//     later re-registration.
//
// FAIL-SOFT: a failure here logs and returns. A patient row must never be lost
// because a grant failed; the clinical Blocked list is the reconcile net that
// surfaces anyone who slips through.
//
// No new grant path: this calls the same grant_member_entitlement the clinical
// dashboard uses.
async function ensureDiscoveryAccess(
  adminClient: SupabaseClient, patientId: string,
): Promise<void> {
  try {
    const { data: rows, error } = await adminClient
      .from("member_entitlements")
      .select("status, expires_at")
      .eq("patient_id", patientId)

    // On a read error do NOT grant: a duplicate grant is harder to notice than a
    // missing one, and reconcile catches the missing case by design.
    if (error) {
      console.error("[patient-register] entitlement read failed, skipping grant:", error.message)
      return
    }

    // Mirrors isLive() in src/lib/member/access-core.ts. Keep them in step.
    const now = Date.now()
    const hasLive = (rows ?? []).some((r: { status: string; expires_at: string | null }) => {
      if (r.status !== "active" && r.status !== "grace") return false
      if (!r.expires_at) return true
      const exp = new Date(r.expires_at).getTime()
      return Number.isNaN(exp) ? true : exp > now
    })
    if (hasLive) return

    // p_days null => expires_at null. Discovery never expires for the dashboard;
    // the 3-day window is enforced app-side (Expo) off starts_at.
    const { error: grantErr } = await adminClient.rpc("grant_member_entitlement", {
      p_patient_id: patientId,
      p_access_type: "discovery",
      p_plan_code: "discovery",
      p_days: null,
      p_source: "self_signup",
    })
    if (grantErr) console.error("[patient-register] discovery grant failed:", grantErr.message)
  } catch (e) {
    console.error("[patient-register] discovery grant threw:", e instanceof Error ? e.message : e)
  }

  // Library veil: EVERYTHING closed. The practitioner opens sections per member
  // from CLINICAL's LibraryActivationPanel. Foundations were seeded open from
  // 2026-08-11 to 2026-09-10; closed since, because the foundation articles are
  // not written yet and every new sign-up was reading the stubs. The row is
  // still seeded (all false) so ignoreDuplicates keeps protecting a
  // practitioner's later toggles. Separate try block so a failed seed never
  // masks a successful grant, or vice versa.
  try {
    await adminClient
      .from("member_library_access")
      .upsert(
        {
          patient_id: patientId,
          foundations_enabled: false,
          tracks_enabled: false,
          supplements_enabled: false,
        },
        { onConflict: "patient_id", ignoreDuplicates: true },
      )
  } catch (e) {
    console.error("[patient-register] library seed failed:", e instanceof Error ? e.message : e)
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS })

  const authHeader = req.headers.get("Authorization")
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { ...CORS, "Content-Type": "application/json" },
    })
  }

  let body: {
    firstName: string
    lastName: string
    email: string
    onboardingData?: Record<string, unknown>
  }

  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400, headers: { ...CORS, "Content-Type": "application/json" },
    })
  }

  const { firstName, lastName, email, onboardingData } = body
  if (!firstName || !lastName || !email || !email.trim()) {
    return new Response(JSON.stringify({ error: "firstName, lastName, email required" }), {
      status: 400, headers: { ...CORS, "Content-Type": "application/json" },
    })
  }

  const anonClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    (Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY"))!,
    { global: { headers: { Authorization: authHeader } } }
  )

  const { data: { user }, error: userError } = await anonClient.auth.getUser()
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Could not verify user" }), {
      status: 401, headers: { ...CORS, "Content-Type": "application/json" },
    })
  }

  // The identity used for "one email = one patient" is the VERIFIED one on the
  // session — never the request body, which any signed-in caller can fill with
  // someone else's address. GoTrue only sets email_confirmed_at when the
  // provider verified the address (Google, Apple) or the member confirmed it.
  const verifiedEmail = user.email && user.email_confirmed_at ? user.email.trim() : null

  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    (Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"))!
  )

  // ── Dedup #1: this auth user already has a patient. ──
  const { data: existingPatient } = await adminClient
    .from("patients")
    .select("id")
    .eq("auth_user_id", user.id)
    .single()

  if (existingPatient) {
    // Self-heal: if a previous run created this patient but the grant failed,
    // this is the invocation that fixes it.
    await ensureDiscoveryAccess(adminClient, existingPatient.id)
    return new Response(
      JSON.stringify({ patientId: existingPatient.id, created: false }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } }
    )
  }

  // ── Dedup #2: canonical-email identity (the durable, vault-safe dedup key). ──
  // `patients.email_canonical_hash` is auto-maintained by a DB trigger and backed
  // by a UNIQUE index, so it is the single source of truth for "one email = one
  // patient" — it works even though the plaintext `email` column is NULL in the
  // vault-first steady state (the old ilike("email") link path could never match).
  const { data: emailHash } = verifiedEmail
    ? await adminClient.rpc("canonical_email_hash", { p_email: verifiedEmail })
    : { data: null }

  if (emailHash) {
    const { data: hashMatch } = await adminClient
      .from("patients")
      .select("id, auth_user_id")
      .eq("email_canonical_hash", emailHash)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle()

    if (hashMatch) {
      // Case A — a clinically-created (or otherwise unlinked) record for this
      // person already exists: LINK it to this auth user instead of creating a
      // duplicate (which the unique index would now reject outright).
      if (!hashMatch.auth_user_id) {
        const { error: linkError } = await adminClient
          .from("patients").update({ auth_user_id: user.id }).eq("id", hashMatch.id)
        if (linkError) {
          console.error("Failed to link patient:", linkError)
          return new Response(
            JSON.stringify({ error: "Failed to link patient record", details: linkError.message }),
            { status: 500, headers: { ...CORS, "Content-Type": "application/json" } }
          )
        }
        await adminClient
          .from("nb_patient_app_profiles")
          .upsert({ ...(onboardingData ?? {}), patient_id: hashMatch.id }, { onConflict: "patient_id" })
        await adminClient.auth.admin.updateUserById(user.id, {
          user_metadata: { patient_id: hashMatch.id, role: "patient" },
        })
        // Clinically-created patient is managed (and may be vaulted) on the clinical side — do NOT re-vault.
        // A clinician-created patient normally already holds full_access, in
        // which case this is a no-op; it only bites when that grant was missed.
        await ensureDiscoveryAccess(adminClient, hashMatch.id)
        return new Response(
          JSON.stringify({ patientId: hashMatch.id, created: false, linked: true }),
          { status: 200, headers: { ...CORS, "Content-Type": "application/json" } }
        )
      }

      // Case B — this mailbox already owns a patient under a DIFFERENT auth
      // identity: the same person, signed in another way (a Gmail dot alias
      // through Google after an email/password account is the case seen live,
      // 2026-09-25). A patient row has ONE auth_user_id, and GoTrue only links
      // two identities by itself when their emails match exactly — nothing here
      // can make this session the owner. So say so, with HOW the owning account
      // signs in, and record nothing: no metadata claim (the apps used to trust
      // it and minted sessions every RLS policy denies), no grant on a row this
      // session does not own.
      const { data: owner } = await adminClient.auth.admin.getUserById(hashMatch.auth_user_id)
      const providers = Array.from(new Set(
        (owner?.user?.identities ?? []).map((i: { provider: string }) => i.provider),
      ))
      return new Response(
        JSON.stringify({ error: "existing-identity", providers }),
        { status: 409, headers: { ...CORS, "Content-Type": "application/json" } }
      )
    }
  }

  // ── Create patient record — VAULT-FIRST (phase-3): identity columns stay NULL;
  // the encrypted vault is the only PII store. The email_canonical_hash column is
  // populated automatically by the DB trigger from auth.users.email. Plaintext is
  // written below ONLY if the vault write fails. ──
  const { data: patient, error: patientError } = await adminClient
    .from("patients")
    .insert({
      clinic_id: DEFAULT_CLINIC_ID,
      first_name: null,
      last_name: null,
      email: null,
      auth_user_id: user.id,
      status: "active",
      care_stage: "onboarding",
    })
    .select("id")
    .single()

  if (patientError || !patient) {
    console.error("Failed to create patient:", patientError)
    return new Response(
      JSON.stringify({ error: "Failed to create patient record", details: patientError?.message }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } }
    )
  }

  const profileData = onboardingData ?? {}
  const { error: profileError } = await adminClient
    .from("nb_patient_app_profiles")
    .insert({
      ...profileData,
      patient_id: patient.id,
    })

  if (profileError) {
    console.error("Failed to create profile (non-fatal):", profileError)
  }

  // Sovereign PII vault — the ONLY identity store (phase 3). If the vault write
  // fails, fall back to the plaintext columns so the patient is never nameless;
  // the next pii-backfill run migrates such rows into the vault.
  const vaulted = await vaultPii(adminClient, patient.id, user.id, firstName, lastName, email)
  if (!vaulted) {
    await adminClient.from("patients").update({ first_name: firstName, last_name: lastName, email }).eq("id", patient.id)
  }

  await adminClient.auth.admin.updateUserById(user.id, {
    user_metadata: { patient_id: patient.id, role: "patient" },
  })

  // The path that matters most: a brand-new self-registered person. They leave
  // this function with discovery access and a closed library (the practitioner
  // opens it), never with a patient row and nothing to sign into.
  await ensureDiscoveryAccess(adminClient, patient.id)

  return new Response(
    JSON.stringify({ patientId: patient.id, created: true }),
    { status: 201, headers: { ...CORS, "Content-Type": "application/json" } }
  )
})
