# IOS_MIGRATION_MAP — from the Expo patient app to native SwiftUI, slice by slice

Status legend: ✅ done · 🟡 partial · ⬜ not started · 🚫 blocked (reason).

## Milestone 1 — end-to-end proof (PRD §22–23)
| Criterion | Status | Note |
|---|---|---|
| Xcode project builds | ✅ | GitHub Actions macOS runner (Xcode 16.4, Swift 6.1): XcodeGen → `xcodebuild build` green on run 4 (2026-09-02) |
| Runs in simulator / on iPhone | 🟡 | unit tests execute in the iPhone 16 Pro simulator on CI (35 pass); no interactive simulator without a Mac; iPhone via TestFlight next |
| User can authenticate | ✅ code | password grant, GoTrue error mapping, tests |
| Auth state survives relaunch | ✅ code | Keychain-backed `AuthSession`, restore without network |
| Credentials securely stored | ✅ | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Real FunctionAlps data retrieved | ✅ code | `nb_patient_app_profiles`, `nb_meal_logs`, `patient_daily_checkins`, `patient_messages` via PostgREST under RLS; `current_member_patient_id` RPC |
| Home shows real member data | ✅ code | greeting, today's meals + macro sums vs targets, check-in status/markers, unread badge |
| Logout works | ✅ code | server logout best-effort + Keychain clear |
| API errors → user-safe states | ✅ | `AppError.userMessage`, `FAErrorState`, unauthorized → login exactly once |
| Uploads to App Store Connect / TestFlight | ✅ | build 1 uploaded 2026-09-03 via the CI lane (Xcode 26, match-created certificate); install via internal TestFlight group |

## Phase map (PRD §24, adjusted to what exists)
| Phase | Expo surface | Native slice | Backend prerequisite | Status |
|---|---|---|---|---|
| A | login (sign-up, Google, reset), profile-settings, language, consent gate, access window, onboarding `ob-*`, care-plan card, messages thread, account deletion | Sign-up + `patient-register`; Google via `ASWebAuthenticationSession`; consent gate (`member_pending_consents`/`record_consent`, age gate) **before any external tester**; entitlement gate; onboarding wizard writing `nb_patient_app_profiles`; Settings; delete via `delete-account` | `member_save_profile` RPC recommended (column-grant trap) | ⬜ |
| B | checkin-hub, checkin-moment, daily-checkin, gut-intelligence(-checkin), q1-*, program days 2–5 | Check-in moments + gut check-in + daily roll-up; Q1 questionnaire + radar; 5-day program | `member_submit_checkin` RPC recommended; **day 3/4/5 scoring + check-in red flags moved server-side** | ⬜ |
| C | report/*, functional-activation (PDF), profile-tests (mock) | Reports viewer (server `nb_report_content`), PDF share; tests/results only after a product decision (no live screen exists) | — | ⬜ |
| D | (tabs)/log, capture/*, meal-detail, nutrition-macros, micronutrients, protocols, plan/* (flag), supplements | Camera/photos → `meal-images` upload → `analyze-meal` → status (poll, later Realtime) → confirm; favorites; macros; protocol lens; habits + supplements when `HABITS_UI_ENABLED` flips | none for read; `member_log_meal` recommended for the pending-row shape | 🟡 **step 1 shipped 2026-09-03** (build 6): Food tab (30-day history grouped by day, today's macros vs targets), photo (camera / library, ≤1280 px JPEG 0.6) and text capture through the Expo async pipeline (queued row → upload → `analyze-meal` with `mealLogId` → 3 s polling), "Your plate, read." screen with needs_input retry, meal detail (signed photo, macros, 3 food scores + verdicts, items, patient note edit, delete). Not yet: voice, multi-photo grouping, favorites/re-log, reactions, micronutrients, protocol lens, Realtime |
| E | (tabs)/health, scores, score/*, score-explainer, pillar/*, dashboard | Trends with Swift Charts | 🚫 **Functional Score, pillar scores, gut score, streaks are client-only TS today** — port to an RPC/edge function (`member_scores`) first, then both apps read one truth (PRD §41) | 🚫 |
| F | (tabs)/library, library/track, library/read, guide/* | Tracks, lessons, reader (markdown → AttributedString), progress | none (`member_library_*` RPCs) | ⬜ |
| G | profile-notifications (orphan), email reminders | Push: device-token table + APNs sender on the backend (nothing exists); local reminders; offline cache; Face ID unlock | new table + edge fn | ⬜ |
| H | profile-wearables (OFF), `wearable-ingest` | HealthKit → `wearable-ingest` (server contract exists, no client anywhere); Thryve connect via web auth session | Privacy Policy must re-disclose wearables first | ⬜ |

## Server-side moves required (the PRD §41 debt the audit exposed)
1. `lib/health/*` score stack (crown composite, vitality/metabolic/nutrition/recovery/longevity, gut composites) → `member_scores(p_day)` RPC or edge function; `nb_score_tips` already assumes such keys.
2. `lib/checkin/red-flags.ts` → evaluated server-side on check-in write (mirror of what `q1-complete` already does for Q1).
3. `lib/{movement,recovery,mind}/day{3,4,5}.ts` → scored inside `movement-report`/`sleep-report`/`mind-report` instead of trusting client numbers.
4. `lib/access/entitlement.ts` 3-day discovery window → DB rule (`expires_at` at grant time).
5. `lib/report/*` six inline-copied modules → single source in the edge function (already server-side; the client copies can be deleted once native reads `nb_report_content` only).
6. Fragile write shapes → RPCs: `member_save_profile`, `member_log_meal`, `member_submit_checkin`.

## Decisions for the owner
- **Bundle id**: keep `com.functionalps.patient` (ship as an update to the existing record) or start `ch.functionalps.app` (parallel app). Default in `Config/Base.xcconfig` is the former.
- **Staging**: no staging Supabase project exists; `Staging.xcconfig` points at CM OS.
- **Where this folder lives** long-term (APP repo vs new IOS repo) — see `README.md`.
- **Consent gate before external TestFlight testers** (legal record is only written by the gate).
