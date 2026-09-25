# AUTH_FLOW — how a member signs in today, and how the native app does it

Evidence: `audit/app-auth-data.md` §1. Backend: Supabase Auth (GoTrue) on CM OS.

## 1. Today (Expo app)
```
Launch
 → supabase-js restores session from AsyncStorage (plaintext)      ⚠ not SecureStore
 → onAuthStateChange → useAuthStore.setSession
 → ensurePatientId(session):
      user_metadata.patient_id
      ?? rpc current_member_patient_id()
      ?? functions.invoke('patient-register', {firstName,lastName,email})   (idempotent)
      ?? rpc current_member_patient_id()
 → gates: language → access window (member_entitlements) → onboarding (nb_patient_app_profiles) → consent (member_pending_consents)
 → tabs
```
- **Login screen:** email-first (`email_exists` RPC decides sign-in vs sign-up) → password sign-in (`signInWithPassword`, `normalizeEmail`) or sign-up (`signUp` with `user_metadata {first_name,last_name,phone}` → "check your email") or Google (`signInWithOAuth`, `redirectTo = window.location.origin` → **web-only**; no native deep-link handler despite the `functionalps` scheme). Forgot password → `resetPasswordForEmail` (web redirect only).
- **Password rules (client):** ≥8 chars, 1 uppercase, 1 special.
- **Registration side effects (`patient-register`):** `patients` row (or link to a clinician-created one via `email_canonical_hash`), `nb_patient_app_profiles`, PII vaulted via `pii_insert_patient` (AES-256-GCM, server KEK), `user_metadata.patient_id` + `role: 'patient'`, `discovery` entitlement (3 days), `member_library_access` seed.
- **Consent:** recorded only by the `ConsentGate` on first authenticated launch (`record_consent` RPC). The sign-up checkbox records nothing by design. Since 2026-09-25 the Terms tick **is** the 18+ declaration: `record_consent` stamps `adult_confirmed_at` (`source = terms_declaration`) on a granted `terms_of_use` instead of refusing with X0018 (migration `20260925_record_consent_terms_is_the_declaration.sql`, applied on CM OS). There is no age check and no age screen; the practice vets its members itself.
- **Logout:** `auth.signOut()` + `clearUserScopedStores()`.
- **Delete:** `delete-account` edge fn (see DATA_MODEL / APP_MAP).

## 2. Native iOS (implemented in `FunctionAlps/Sources/Core/Authentication`)
```
Launch
 → KeychainSessionStore.load()            (no network — offline-safe launch)
 → AppState.phase = signedIn | signedOut
 → LoginView (signedOut): SupabaseAuthClient.signIn(email, password)   POST /auth/v1/token?grant_type=password
     ↳ AuthSession { accessToken, refreshToken, expiresAt, userId, email, patientId?, displayName? }
     ↳ Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
 → MemberService.currentMember():
      rpc current_member_patient_id()          → the server's answer wins; user_metadata.patient_id is a cache corrected FROM it, never trusted over it
      ?? functions.invoke('patient-register')  → .patient(id): rpc current_member_patient_id() AGAIN — an id the server does not confirm is never used
                                               → 409 existing-identity → MemberError.registeredElsewhere(providers) → "This email already has an account" (sign out, use the other door)
      ?? MemberError.notRegistered             → "We couldn't find your membership"
 → Home / Profile
 → Logout: POST /auth/v1/logout (best effort) + Keychain clear + phase = signedOut
```
- **Token lifecycle:** `SessionManager` (actor) refreshes when < 60 s remain (`grant_type=refresh_token`); one in-flight refresh is shared across concurrent callers (refresh-token rotation safety); a rejected refresh clears the session; an offline refresh keeps it. `AuthorizedRequester` retries once after a 401, then signs out.
- **Errors:** GoTrue `invalid_credentials`/`invalid_grant` → `.invalidCredentials`; `email_not_confirmed`, 422, 429 → user-safe validation messages; nothing technical is shown (PRD §43).
- **Not in M1, planned:** sign-up (+ `patient-register`), Google via `ASWebAuthenticationSession` + `functionalps://` callback + PKCE code exchange, password reset with a native `updateUser` screen, the consent and access gates, Face ID local unlock (PRD §18), `AppState`-driven refresh pause/resume.

## 3. Security notes carried into the design
- No secret leaves the server: the app holds the publishable key and the member's JWT only (PRD §30/§36).
- Ownership is enforced by RLS keyed on `patients.auth_user_id`; the client never passes a `patient_id` it did not obtain from the backend for the signed-in user.
- Logs never contain tokens; `Log.auth` prints at most the first 8 chars of a user id.
- The audit's finding that the Expo app keeps tokens in AsyncStorage is a reason to move members to the native app, not something to replicate.

## 4. One mailbox, two auth users (2026-09-25)
Gmail ignores dots in the local part (`first.last@` and `firstlast@` are one inbox); GoTrue does not, and it only links
a new OAuth identity to an existing user by itself when the two emails match **exactly**. So a member who registers with
a password under one spelling and later taps "Continue with Google" (which reports the spelling their Google account
carries) gets a **second** auth user that owns nothing. `patient-register` recognises the person through
`email_canonical_hash` (dots stripped), but a `patients` row has exactly one `auth_user_id`.

What happens now:
- `patient-register` (v57, this repo's `supabase/functions/patient-register/`) answers **409 `existing-identity`** with the
  owning account's providers and records nothing — no `user_metadata.patient_id` claim, no grant on a row the session does
  not own. The "one email = one patient" key is the **verified** session email, never the request body.
- The app shows *"This email already has an account. You registered before with an email address and password…"* with
  **Sign out** as the primary action. It also re-reads `current_member_patient_id()` after any registration, so an older
  copy of the function (four repos carry it) that still answers 200 with the other account's id lands on the same screen.
- Before 2026-09-25 the app trusted the returned id, showed the consent gate with nothing ticked, and every "Agree and
  continue" was refused with 403 `no member context` — read by the member as "check your connection".

What the operator can do for a member who wants both doors: move the Google identity onto the account that owns the
record (`auth.identities.user_id` → the email/password user, then delete the empty user), so the next Google sign-in
lands on the existing account. Do it once per member, on request; the app cannot.
