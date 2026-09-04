# Architecture — FunctionAlps native iOS

## 1. Position in the ecosystem
```
                      CM OS (Supabase: Postgres + Auth + Edge Functions + Storage)
                        ▲               ▲                ▲               ▲
   MEMBERS (web)  CLINICAL (web)   WEBSITE (web)    STUDIO (web)   ┌──── iOS (this) ────┐
   reads member   writes care plans  funnel           knowledge      │ replaces the Expo   │
   data           pushes to app                        library       │ patient app         │
                                                                     └─────────────────────┘
```
The iOS app is the **member's daily client**: the only writer of daily logs (meals,
check-ins), reader of the care plan pushed by clinicians, consumer of the library.
One account system (`auth.users`), one `patients`/`profiles` graph.

## 2. Layering (the rule everything else follows)
```
SwiftUI View            presentation only; switches on view-model state
   ↓
ViewModel (@Observable) per screen; owns loading/error/empty state; calls services
   ↓
Service                 MemberService, DashboardService, …; domain types in/out
   ↓
FunctionAlpsBackend     protocol of domain operations (currentMember, todaySummary, …)
   ↓
SupabaseBackend         the ONLY place that knows tables / RPCs / edge-function names
   ↓
PostgRESTClient · EdgeFunctionClient · SupabaseAuthClient   (plain URLSession, no SDK)
   ↓
CM OS
```
- Swapping CM OS for a FunctionAlps gateway (`api.functionalps.ch`, PRD §7/§40) means
  writing `GatewayBackend: FunctionAlpsBackend` and changing one line in
  `AppDependencies`. Features and view models do not change.
- We deliberately use **no Supabase Swift SDK**: the REST surface we need is four
  auth calls, PostgREST selects on the user's own rows, and edge-function POSTs.
  A vendor SDK in every feature is exactly the coupling PRD §6 forbids.

## 3. Authentication (PRD §17)
- `SupabaseAuthClient` — password grant, refresh grant, logout, user. GoTrue error
  bodies (new `error_code` and legacy `error`) map to `AppError`.
- `SessionManager` (actor) — persisted `AuthSession` in Keychain; `validAccessToken()`
  refreshes when < 60 s remain; a single in-flight refresh is shared so concurrent
  callers never double-rotate a refresh token; a rejected refresh clears the session.
- `AuthorizedRequester` — attaches the bearer, on 401 refreshes once and retries once.
- `AuthService` (main actor) — restore at launch (Keychain only, no network), sign in,
  sign out, `handleUnauthorized()` → flips `AppState.phase` exactly once.
- Face ID later unlocks the *local* session (PRD §18); it never replaces server auth.

## 4. Errors (PRD §43)
`AppError` is the whole vocabulary: offline · unauthorized · forbidden · notFound ·
validation · invalidCredentials · server · decoding · network · configuration · unknown.
`userMessage` is localized and safe; `debugDescription` goes to `os.Logger` only.

## 5. State
- `AppState.phase` (launching / signedOut / signedIn) is the only global state.
- Each screen's view model owns a `Loadable<T>`-style state; no shared caches yet
  (offline caching is Phase G — the seam is the service layer).
- Server is canonical; iOS holds a representation (PRD §12).

## 6. Design system (PRD §19)
`FAColor` / `FATypography` / `FASpacing` / `FACornerRadius` tokens; `FAButton`,
`FATextField`, `FACard`, `FASection`, `FAMetricCard`, `FAListRow`, `FALoadingState`,
`FAErrorState`, `FAEmptyState`, `FABrandMark`. Colour values mirror the Expo theme
(teal `#0D9488` brand — the Expo splash/notification colour) and are corrected from
the theme audit in `APP_MAP.md`.

- **Glass rule (owner, 2026-09-03):** every card on every screen — and the floating tab bar — is the see-through glass, and only that: `FACard` / `FAGlassSurface` (clear Liquid Glass on iOS 26, the web `GlassCard` "seethrough" veil before it). No `.regularMaterial`/`.ultraThinMaterial`, no tinted `.regular` glass (iOS 26 renders it as an opaque grey slab over the Sage wall), no solid card fills. New screens get the wall (`.faWall()`) + `FACard`s, nothing else.

- **Library data rule (2026-09-03):** the library is a SECOND CONSUMER of the members catalog — same tables and RPCs (`library_tracks`, `library_track_lessons`, `member_lesson_progress`, `member_library_list/get/stage`, `member_library_access`, `patient_track_priority`, `care_plans` + goals), read in parallel under the member's session. Only the catalog read may fail the tab (→ the labelled sample library, never an empty screen); every other read fails soft. The activation veils fail CLOSED (no row = every section veiled), the stage gate fails closed to `lead`. Rules live in `LibraryLogic` (pure, tested); `LibraryService` is the only IO.

- **Navigation rule (owner, 2026-09-04):** every screen hides the system navigation bar and draws its own `CenteredHeader`, which makes UIKit drop the edge swipe-back. `SwipeBackEnabler` (`.faSwipeBack()`) restores the interactive pop gesture on each tab's navigation controller, guarded so it never begins on a root screen. `MainTabView` applies it to the five roots and to every pushed route through `destination(_:)`, so a new route gets the gesture without doing anything; a screen presented as a sheet (capture, note editor) is dismissed with its own control, not the edge.

## 7. Environments (PRD §31)
`Config/{Development,Staging,Production}.xcconfig` → Info.plist → `AppEnvironment`.
Only non-secret values. Staging currently points at CM OS because no staging project
exists (flagged for the owner).

## 8. Security (PRD §30)
TLS only (`NSAllowsArbitraryLoads = false`), Keychain `AfterFirstUnlockThisDeviceOnly`,
no service-role or KEK material anywhere near the app, RLS + server-side ownership
checks are the authorization; the client never decides access.

## 9. Testing (PRD §44)
Swift Testing. Covered now: ISO-8601 decoding, `AppError` mapping, GoTrue client
(request shape, error shapes), `SessionManager` (restore, refresh, single-flight,
rejection, offline), `AuthorizedRequester` (401 retry, sign-out). Next: model
decoding fixtures from real rows, `MemberService`/`DashboardService` over
`MockTransport`.

## 10. Decisions log
| Date | Decision | Why |
|---|---|---|
| 2026-09-02 | XcodeGen, not hand-made pbxproj / Tuist | reviewable spec, smallest tool, agent-friendly |
| 2026-09-02 | No Supabase Swift SDK | PRD §6; REST surface is tiny; migration seam |
| 2026-09-02 | Bundle id `com.functionalps.patient` (proposed) | ships as an update to the existing App Store record; owner to confirm before first upload |
| 2026-09-02 | Password login only in v0.01 | the Expo app's Google OAuth needs a native redirect + ASWebAuthenticationSession; Phase A |
| 2026-09-02 | Milestone 1 reads only the member's own rows under RLS + calls existing edge functions | zero backend change for the proof (PRD §22) |
