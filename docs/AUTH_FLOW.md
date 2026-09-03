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
- **Consent:** recorded only by the `ConsentGate` on first authenticated launch (`record_consent` RPC, age 18+ confirmation first). The sign-up checkbox records nothing by design.
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
      session.patientId (from user_metadata.patient_id)
      ?? rpc current_member_patient_id()  → remembered in the Keychain session
      ?? MemberError.notRegistered  → "Almost there" state (sign-up + patient-register land in Phase A)
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
