# APP_MAP — the FunctionAlps patient app as it exists today (Phase 0, Task 1)

Scope: the **FunctionAlps patient app** (`FunctionAlps-APP`, Expo / React Native + expo-router, web export on Vercel + native via Expo). This is the app the native iOS build replaces. STUDIO, MEMBERS, WEBSITE and CLINICAL stay web and are out of scope.
Evidence: `audit/app-screens.md` (screens, gating, theme, i18n), `audit/app-backend-census.md` (tables, RPCs, edge functions, client-side logic), `audit/app-auth-data.md` (auth, data model). Repo snapshot: commit `ad44f35`, 2026-09-02.

## 1. Shape of the app
- **Entry:** `index.ts` → `expo-router/entry`; `app/_layout.tsx` (530 lines) holds every provider and gate. `app.json`: name FunctionAlps, slug `functionalps-patient`, scheme `functionalps`, iOS bundle `com.functionalps.patient`, light-only UI, Camera/Photos/Health usage strings.
- **Stack:** Expo ~54, RN 0.81, expo-router, React 19, zustand stores + TanStack Query, `@supabase/supabase-js` (AsyncStorage session), NativeWind declared but screens use inline styles + `lib/theme/tokens.ts`.
- **Gate order on launch:** font load → profile-read splash → language choice (EN/FR) → access window (`member_entitlements`, fails open) → onboarding (`ob-*`, 8 screens, rule in `lib/onboarding/gate.ts`) → consent gate (`member_pending_consents` / `record_consent`, age 18+ step) → tabs.
- **Tabs (5):** Home · Trends · Food · Library · Profile (lucide icons `Home`, `TrendingUp`, `Salad`, `BookOpen`, `User`); hidden `chat` tab (dark). Floating 66 pt glass pill bar; no centre FAB.
- **Feature flags:** AI chat OFF, Habits UI hardcoded OFF, coverage nudge OFF, wearables entry OFF (`SHOW_WEARABLES`), FR ON, consent gate ON, onboarding gate ON.

## 2. Product areas (PRD §10 list → what actually exists)

| PRD area | Exists? | Route(s) / module | Backend | Native plan (see IOS_MIGRATION_MAP) |
|---|---|---|---|---|
| Authentication | ✅ | `(auth)/login` — email-first, password sign-in/sign-up, Google (web-only in practice), forgot-password | GoTrue; RPC `email_exists`; edge fn `patient-register` | **M1** password login; Phase A sign-up + Google via ASWebAuthenticationSession |
| Onboarding | ✅ | `(onboarding)/ob-welcome…ob-ready` (live), `q1-*` (optional Day-1 assessment of the 5-day program), `welcome` (dead) | `nb_patient_app_profiles` (baseline, `onboarding_completed_at`), `q1-complete` | Phase A (ob-*), Phase B (q1) |
| Home / dashboard | ✅ | `(tabs)/index` — functional trend card, protocol review, scan/check-in tiles, latest article, messages | `patient_daily_checkins`, `nb_meal_logs`(+reactions), `patient_notification_preferences`, `wearable_daily_labeled`, `patient_messages`, protocols, library tables; **scores computed client-side** | **M1** (meals + check-in status + unread, no scores) |
| Profile | ✅ | `(tabs)/profile` + `profile-settings`, `profile-privacy`, `privacy-consents`, `privacy-view-data`, `profile-messages`, `profile-care-plan`, `profile-help`, `profile-feedback`, `profile-wearables`; mock: `profile-appointment`, orphans: `profile-{tests,supplements,notifications}` | session `user_metadata` for name; `nb_patient_app_profiles`; `care_plans/_goals/_items`; `member_entitlements` | **M1** header + baseline + sign out; Phase A rest |
| Health assessments / questionnaires | ✅ | `q1-*` (6 screens, radar report), 5-day program days 2–5 (`nutrition-setup`, `movement-*`, `sleep-*`, `mind-*`) | `nb_assessment_responses`; edge fns `q1-complete`, `movement-report`, `sleep-report`, `mind-report` (narrate only; days 3–5 scored client-side) | Phase B |
| Symptoms | ⚠ partial | check-in red flags inside gut check-in; `symptoms/log` is a dead mock screen | `patient_daily_checkins.red_flag_*` (client-only red-flag logic) | Phase B (inside check-ins) |
| Health priorities / goals | ✅ | onboarding goals + complaints; profile chips | `nb_patient_app_profiles.health_goals/current_complaints` | Phase A |
| Tests / test results | ❌ | `biomarkers/*` are mock + dead; `profile-tests` orphan placeholder | (`biomarker_results` exist in CM OS but the app never reads them) | Phase C — needs product decision |
| Programs | ✅ | `program` (5-day pre-call stepper) | `nb_assessment_responses`, `lib/program/gating.ts` | Phase B/D |
| Protocols | ✅ (lens) | `ProtocolReviewCard`, `ProtocolWhySheet` | `nb_patient_protocols`, `nb_protocol_overrides`, `nb_meal_logs.protocol_flags` | Phase D |
| Nutrition | ✅ | `(tabs)/log`, `capture/{camera,analyzing,confirm}`, `meal-detail/[id]`, `nutrition-macros`, `macros-details`, `micronutrients`, `micro-*` | `nb_meal_logs`, `nb_meal_reactions`, `nb_favorite_meals`, `nb_patient_food_aliases`; edge fns `analyze-meal`, `preprocess-meal`, `resolve-foods`, `transcribe-audio`; storage `meal-images`; realtime on `nb_meal_logs` | Phase D (the core daily loop — highest value after M1) |
| Movement / Sleep / Stress | ✅ (program days) | `movement-*`, `sleep-*`, `mind-*`, `health-*` wrappers | as assessments | Phase B/D |
| Supplements | ⚠ | `supplements/index` mock/dead, `log-supplements` orphan (writes legacy `nb_supplement_logs`); live supplements are inside the (flagged-off) plan | `supplement_plans`, `supplement_logs` | Phase D with Plan |
| Tasks / habits | ✅ but OFF | `plan`, `plan-add`, `plan-habit` (Habit Loop v2, `HABITS_UI_ENABLED=false`) | `habits`, `habit_completions`, `habit_offers`, `habit_bank`, `habit_notes`, `care_plan_item_gates`; edge fn `evaluate-gates`; realtime on `habits` | Phase D (when the flag flips) |
| Check-ins | ✅ | `checkin-hub`, `checkin-moment` (current: morning/midday/evening), `daily-checkin` (older full form), `gut-intelligence-checkin`, `gut-intelligence` | `patient_daily_checkins`, `patient_checkin_moments`, `nb_checkin_events`, `nb_checkin_custom_pills`; `fireDailyReport` | Phase B |
| Progress / metrics / trends | ✅ | `(tabs)/health`, `scores`, `score/[key]`, `score-explainer/[score]`, `pillar/[key]`, `dashboard` (legacy) | `nb_score_tips` + edge fn `generate-score-tip`; **all scores computed client-side** (`lib/health/*`) | Phase E — **blocked until the score stack moves server-side** |
| Library / articles / resources | ✅ | `(tabs)/library`, `library/track/[slug]`, `library/read/[slug]`, `guide/*`; parked: `your-resources`, `resource/[id]` | `library_tracks`, `library_track_lessons`, `member_library_access`, `member_lesson_progress`, `patient_track_priority`; RPCs `member_library_stage/list/get` | Phase F |
| Videos | ⚠ | guide chapters link out to video URLs | — | Phase F |
| Documents | ❌ (member side) | reports as PDF export only (`report/*`, `functional-activation`) | `nb_report_content`; `expo-print`/`expo-sharing` | Phase C |
| Notifications | ⚠ | one local post-meal nudge; reminder prefs screen (orphan); email reminders server-side | `patient_notification_preferences`; edge fns `daily-checkin-reminder`, `message-notify` (email); **no push token anywhere** | Phase G — needs a device-token table + APNs backend |
| Settings | ✅ | `profile-settings` (walls, language, privacy, messages, help, wearables, sign out) | `nb_patient_app_profiles.locale` | **M1** skeleton; Phase A |
| Account deletion | ✅ | `DeleteAccountSheet`, `profile-settings` | edge fn `delete-account` (deletion_log, storage purge, `pii_erase_patient`, `patients` delete, auth delete) | Phase A (backend exists; wording/retention to confirm) |
| Messaging | ✅ | `profile-messages` | `patient_messages`; RPC `member_mark_messages_read`; edge fn `message-notify` | Phase A/B |
| Wearables | ✅ built, OFF | `profile-wearables` | Thryve edge fns; `wearable_daily_labeled`; `wearable-ingest` (HealthKit, **no client code exists**) | Phase H |
| AI chat / Nutri AI | ❌ dark | `(tabs)/chat`, `nutrition-ai` behind `AI_CHAT_ENABLED`; backend functions are 410 stubs | — | not planned |

## 3. Dead, orphaned or mock surfaces (do not port)
`shader-demo`, `supplements/index`, `symptoms/log`, `biomarkers/[system]`, `biomarkers/[markerId]`, `capture/day-review`, `diet-detail/[slug]`, `functional-activation`, `log-supplements`, `weekly-theme`, `profile-appointment` (mock practitioner + date), `profile-notifications`, `profile-supplements`, `profile-tests`, `(onboarding)/welcome`, `app/+html.tsx`, `your-resources` + `resource/[id]` (parked), the four AI-chat functions. Also: the Profile tab's "Functional trend" card is hard-coded mock data.

## 4. Theme (reproduced natively in `DesignSystem/Tokens`)
Forest `#2E5438` / forestS `#4A8A5C` / forestM `#C8D9CC` / forestG `#EDF4EF` · cream `#F5F0E8` / cream2 `#EDE8DE` / warm `#FAF7F2` · gold `#C48B35` (retired in-app) · charcoal `#1A1A16` · stone `#7A796F` / stoneLt `#A8A79E`. Macro palette kcal `#2A3B34`, protein `#E0654F`, carbs `#E8A23D`, fat `#6C8AE4`. Food scores inflammation `#D98A2B`, glycemic `#3F7FC4`, digestion `#4A8A5C`. 5-level scale `#C0453A → #4A8A5C`. Radii 12/16/22/24/pill. Fonts DM Serif Display + DM Sans (npm Google fonts; TTFs to bundle). 7 "walls" (default Sage). Glass cards (`GlassCard`) everywhere; `NAVBAR_CLEARANCE = 120`. Light-only.

## 5. i18n
EN + FR only. UI strings keyed by the English sentence (`useT('…')`), ~1,613 generated + ~367 hand-written FR entries; copy modules use dotted-path overlays; legal pack resolves from device locale regardless of flag. Native: `Localizable.xcstrings` with the same two languages; **reuse the FR wording from `lib/i18n/ui/fr.ts` when porting screens** (approved product language, PRD §47).

## 6. State management today (reference for view models)
12 zustand stores (`auth-store`, `log-store`, `daily-store`, `onboarding-store`, `program-store`, `capture-store`, `meal-queue-store`, `day-batch-store`, `favorites-store`, `theme-store`, `chat-store`, i18n `store`) + TanStack Query (`staleTime` 5 min). Per-patient `loadedFor` guards; `clearUserScopedStores()` on sign-out (theme/locale survive). The native app keeps this "one owner per slice" shape as view models + services, with no shared cache in M1.
