# Audit — Patient App authentication, data model, account lifecycle (raw)

Source repo: `FunctionAlps-APP` (`/home/user/functionalps-app`, commit ad44f35, cloned 2026-09-02). Expo SDK 54, `@supabase/supabase-js` ^2.101.1. Backend: shared Supabase "CM OS" `ndojytvvlvlbgtodujkf`. Produced by a read-only exploration agent; kept verbatim as the evidence base for `AUTH_FLOW.md` and `DATA_MODEL.md`.

## 12-line summary
1. **Auth surface** = email+password and Google OAuth only (`lib/supabase/auth.ts`); **no magic link** and **no biometrics** (`expo-local-authentication` absent).
2. **Tokens live in AsyncStorage** (`lib/supabase/client.ts:28`) — `expo-secure-store` is a dependency and plugin but **imported by zero files**.
3. **Google OAuth is web-only in practice**: `redirectTo` is `window.location.origin`, `undefined` on native; no `expo-web-browser`/`expo-auth-session`/deep-link handler exists, so the `functionalps` scheme is declared but unused.
4. **`patientId` is CM OS `public.patients.id`, never `auth.uid()`**, resolved 3 tiers deep: `user_metadata.patient_id` → `current_member_patient_id()` RPC → `patient-register` edge fn (idempotent; creates `patients` + `nb_patient_app_profiles`, vaults PII, grants `discovery`).
5. **`public.profiles` exists (mig 057) but the app never reads it** — the live profile table is `nb_patient_app_profiles` (26 columns, column-scoped grants, must be UPDATE-then-INSERT, never upsert).
6. **Gating order in `app/_layout.tsx`**: splash → language → access window (`member_entitlements`, fails open) → onboarding (members target only) → consent gate (`member_pending_consents`/`record_consent`) → app. `DEV_BYPASS_AUTH = false` hard-coded.
7. **Entitlements**: `full_access`/`paid` (open) > `beta` (to `expires_at`) > `discovery` (3 days from `starts_at`, app-side rule). No `tier`/`funnel_status`/`trial_*` columns are read.
8. **`evaluate-gates`** is habit-completion arithmetic only, fire-and-forget after habit check-off; not an access gate.
9. **Two parallel data planes**: the auth-user-keyed 057 tables (`meals`, `checkins`, `gut_checkins`, `consents`, `reports`, `assessment_responses`, `user_patterns`) were ETL'd into the patient_id-keyed `nb_*`/`patient_*` plane by mig 061 and made read-only; **only the nb_ plane is live**.
10. **Home** needs 6 reads: `nb_meal_logs`(+`nb_meal_reactions`), `patient_daily_checkins` today + 6d + 13d gut, `patient_notification_preferences`, `wearable_daily_labeled`, plus card-local reads.
11. **Dates**: `localDayISO()` (device-local `YYYY-MM-DD`) is canonical for `checkin_date`/day buckets; timestamps are ISO UTC; server-stamped day columns keep the server convention.
12. **Account lifecycle**: password reset via `resetPasswordForEmail` (web-origin redirect only), logout clears all user-scoped stores, delete via `delete-account` edge fn. `profile-appointment.tsx` is **entirely mock data**.

---

## 1. Authentication flow, end to end

### 1.1 Client construction — `lib/supabase/client.ts`
`storage: AsyncStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: Platform.OS === 'web'`. URL/key fall back to hard-coded CM OS values. **Session persistence: AsyncStorage, not SecureStore.** No `AppState` → `startAutoRefresh()/stopAutoRefresh()` wiring.

### 1.2 Login methods — `lib/supabase/auth.ts`, `app/(auth)/login.tsx`
`Flow` state machine: `'email' | 'login' | 'signup' | 'signup-done' | 'forgot' | 'forgot-sent'`. Email-first: `emailExists(email)` → RPC `email_exists(p_email)` → `true` → login, `false`/`null` → signup.

| Method | Function | Notes |
|---|---|---|
| Email + password | `signInWithEmail` (auth.ts:9) | `signInWithPassword` with `normalizeEmail()` (strips `+alias`, gmail dots) |
| Email sign-up | `signUpPatient` (auth.ts:25) | `signUp` with `options.data = { first_name, last_name, phone? }`; every email sign-up returns no session → `signup-done` |
| Google OAuth | `signInWithGoogle` (auth.ts:136) | `signInWithOAuth({ provider: 'google', options: { redirectTo, skipBrowserRedirect: false } })` — **non-functional on native** as written |
| Magic link | not found | |
| Biometric | not found | |

Password rules (client-side, login.tsx:63): ≥8 chars, ≥1 uppercase, ≥1 special. Sign-up requires first name, last name, phone, consent checkbox. **The sign-up consent tick records nothing** — the durable record is the `ConsentGate` on first authenticated launch (D-21, 2026-08-19).

### 1.3 Sign-up path → `patient-register` (`supabase/functions/patient-register/index.ts`)
Invoked from `ensurePatientId` (auth.ts:119). Byte-for-byte duplicated in three repos.
**Input**: `{ firstName, lastName, email, onboardingData? }` (app sends the first three). **Output**: `{ patientId, created, linked?, note? }` — 201/200/400/401/500.
Logic: verify JWT → dedup by `patients.auth_user_id` → dedup by RPC `canonical_email_hash(p_email)` on `patients.email_canonical_hash` (link clinician-created row, or point at canonical record) → create `patients` (`clinic_id = 00000000-0000-0000-0000-000000000010`, names/email NULL, `status:'active'`, `care_stage:'onboarding'`) → `nb_patient_app_profiles` insert → PII vault `pii_insert_patient(...)` (AES-256-GCM, `SOVEREIGN_KEK_HEX`; plaintext fallback on failure) → `auth.admin.updateUserById(user.id, { user_metadata: { patient_id, role: 'patient' } })` → `ensureDiscoveryAccess` (RPC `grant_member_entitlement(... 'discovery' ...)` + upsert `member_library_access { foundations_enabled: true, tracks_enabled: false, supplements_enabled: false }`).
**Tables written:** `patients`, `nb_patient_app_profiles`, `pii.patients`, `member_entitlements`, `member_library_access`, `auth.users.user_metadata`.

### 1.4 `patientId` derivation — the single most important convention
**`patientId` = CM OS `public.patients.id`. Never `auth.uid()`.** Ladder (`ensurePatientId`, auth.ts:105):
1. `session.user.user_metadata.patient_id` (zero network)
2. RPC `current_member_patient_id()` (SECURITY DEFINER, from JWT)
3. `functions.invoke('patient-register', ...)` — idempotent creation
4. Re-read `current_member_patient_id()`
`getCurrentPatientId()` = tiers 1–2 only. `app/_layout.tsx:188-208` runs `ensurePatientId` on session establish and retries on every `AppState → active` while null.
Legacy: `ensure_patient_for_auth_user()` (mig 034) auto-creates a `patients` row with plaintext PII — **never called by the app**; superseded by `patient-register`.

### 1.5 `resolve-patient` — not app-facing (clinician-side consent-gated PII reveal, `x-resolve-secret`).

### 1.6 The `profiles` trigger — **not found.** `public.profiles` (mig 057) has no populating trigger and the app never reads/writes it. Working equivalents: `patients.email_canonical_hash` trigger (DDL not in this repo); `trg_nb_patient_app_profiles_updated_at` (mig 024).

### 1.7 Consent capture — three layers
**(a) Legal record — `lib/legal/consents.ts`:** `fetchConsents` → RPC `member_pending_consents(p_locale, p_include_drafts)` → `{ consent_key, version, title, summary, body_md, required, display_order, review_status, basis, accepted }`; `recordConsentDecision` → RPC `record_consent(p_consent_key, p_version, p_granted, p_locale, p_user_agent, p_app_version, p_ui_template_version, p_privacy_notice_version, p_presented_keys, p_default_state, p_channel)`; `recordConsentDecisions` → `record_consent_batch`; `revokeConsent` → `revoke_consent` (refuses `contract_core`). `CONSENT_UI_TEMPLATE_VERSION = 'consent-gate-1'`. Flag `CONSENT_GATE_ENABLED` default ON since 2026-08-19.
**(b) `nb_app_consents`** — `recordConsent()` deleted 2026-08-19; table still read by `resolve-patient` and the export.
**(c) Age gate — `lib/legal/age-gate.ts`:** RPCs `confirm_member_adult(...)`, `current_member_is_adult()`; `record_consent()` refuses a member not confirmed 18+ (error X0018).
**Catalog keys:** consents `terms_of_use`, `health_data_processing` (required, explicit consent), `usage_analytics`, `marketing_comms`; notices `privacy_policy`, `legal_notice`, `ai_analysis`.
**Retired:** first-run AI-consent gate removed 2026-08-20.

### 1.8 Root gating — `app/_layout.tsx`
`DEV_BYPASS_AUTH = false` hard-coded (line 46). Flags: `ONBOARDING_GATE_ENABLED`, `ONBOARDING_TARGET`, `EXPO_PUBLIC_DISABLE_ACCESS_GATE`, `FR_UI_ENABLED`, `HABITS_UI_ENABLED`. Effects: `onAuthStateChange` (`SIGNED_OUT` → `clearUserScopedStores()`); per-user reset; `ensurePatientId`; routing effect with module-level `pendingRoute`; `loadProfile()` → `resolveOnboardingStatus(profile)` (fail open on throw). Render order: splash → `LanguageChoiceScreen` → `AccessWindowGate` → `OnboardingRequiredGate` (members target only) → `ConsentGate` → `<Slot/>`.

### 1.9 Password reset, logout, delete-account
- Reset: `resetPasswordForEmail(normalizeEmail(email), { redirectTo: window.location.origin })` — swallows all errors; `redirectTo` undefined on native; no in-app password-update screen.
- Logout: `signOut()` then `useAuthStore.reset()` + `clearUserScopedStores()`; `SIGNED_OUT` event also clears.
- Delete: `functions.invoke('delete-account', { body: {} })` (two call sites; `profile-settings.tsx:88` inlines and does **not** check `result.deleted`). Function: `deletion_log` insert → purge `meal-images` under `uid/` and `patientId/` → RPC `pii_erase_patient` → `delete from patients` (FK to auth is SET NULL) → `auth.admin.deleteUser` → best-effort email. Returns `{ deleted: true, email, emailError? }`.
- Export: `gatherUserData(patientId)` — 10 parallel own-RLS selects, JSON download/share.

## 2. Roles / entitlements — `lib/access/*`
`lib/access/entitlement.ts` reads `member_entitlements` (`access_type, status, starts_at, expires_at`). `AppAccessTier = 'full_access' | 'paid' | 'beta' | 'discovery' | 'unknown'`; `RANK = { full_access: 3, paid: 2, beta: 1, discovery: 0.5, trial: 0 }`; `DISCOVERY_APP_DAYS = 3`. `isLive(row)`: `status ∈ {'active','grace'}` and not expired. **Fails open on every unknown.** `useAppAccess` returns `{ access, checked, recheck }`; `countdown.ts::describeAccessWindow` → null for paid/full_access/unknown. `nb_patient_app_profiles.tier/funnel_status/trial_*` are never read by this app (MEMBERS revoked write grants 2026-08-19). Also read: `member_library_access`, `member_library_*` RPCs, `patient_track_priority`, `member_lesson_progress`.
`evaluate-gates` (607L): Habit Loop unlock evaluator; reads completion arithmetic only; auth via `resolvePatientId` on the service client; `COMPLETIONS_LOOKBACK_DAYS = 70`, `PROMOTION_WINDOW_DAYS = 28`, `PROMOTION_MIN_ACCEPTS = 3`; `rule_kind ∈ streak | count_in_window | adherence_pct | manual`.

## 3. Data model

### 3.1 Two planes — read this first
Mig 057 created auth-user-keyed tables (`profiles`, `meals`, `meal_reactions`, `checkins`, `checkin_events`, `gut_checkins`, `consents`, `reports`, `assessment_responses`, `user_patterns`). Mig 061 ETL'd them into the patient_id-keyed `nb_*`/`patient_*` plane and revoked writes. **The client reads/writes only the nb_/patient_ plane.**

### 3.2 Live tables the app touches (reference counts)
`patient_daily_checkins` 17 · `nb_meal_logs` 16 · `nb_report_content` 5 · `nb_patient_app_profiles` 5 · `nb_checkin_events` 5 · `nb_meal_reactions` 4 · `nb_favorite_meals` 4 · `habits` 4 · `habit_offers` 4 · `care_plans` 4 · `supplement_logs` 3 · `patients` 3 · `patient_messages` 3 · `patient_checkin_moments` 3 · `nb_score_tips` 3 · `nb_patient_food_aliases` 3 · `nb_assessment_responses` 3 · `nb_app_consents` 3 · `member_lesson_progress` 3 · `habit_notes` 3 · `habit_completions` 3 · `patient_notification_preferences` 2 · `nb_user_patterns` 2 · `nb_reports` 2 · `nb_checkin_custom_pills` 2 · `care_plan_items` 2 · and 1 each: `wearable_daily_labeled`, `wearable_connections`, `supplement_plans`, `state_responses`, `patient_track_priority`, `patient_resource_assignments`, `patient_notifications`, `patient_intake_questionnaire`, `patient_daily_checkin_events`, `nb_weekly_themes`, `nb_supplement_logs`, `nb_report_interpretations`, `nb_protocol_overrides`, `nb_patient_protocols`, `nb_food_products`, `nb_food_items`, `member_library_access`, `member_entitlements`, `library_tracks`, `library_track_lessons`, `habit_bank`, `care_plan_phases`, `care_plan_item_gates`, `care_plan_goals`.

### 3.3 Field lists

#### `public.nb_patient_app_profiles` — mig 024, +052 (`locale`), + forward columns
| Column | Type | Null |
|---|---|---|
| `id` | uuid PK | no |
| `patient_id` | uuid UNIQUE → patients CASCADE | no |
| `app_sex` | text CHECK in ('male','female','other') | yes |
| `app_age` | integer | yes |
| `app_weight_kg` | numeric | yes |
| `app_height_cm` | numeric | yes |
| `estimated_body_fat_percent` | numeric | yes |
| `activity_level` | text | yes |
| `weekly_workout_frequency` | text (`'0'|'1-2'|'3-4'|'5+'`) | yes |
| `workout_type` | text (`strength|cardio|mixed|sport|none`) | yes |
| `session_duration_min` | integer (30|45|60|90) | yes |
| `health_goals` | text[] default '{}' | yes |
| `current_complaints` | text[] default '{}' | yes |
| `dietary_pattern` | text | yes |
| `self_reported_supplements` | text[] default '{}' | yes |
| `custom_supplements` | text | yes |
| `tdee_kcal` | integer | yes |
| `target_calories` | integer | yes |
| `target_protein_g` / `target_carbs_g` / `target_fat_g` | integer | yes |
| `goal_mode` | text CHECK in ('build','cut','maintain') | yes |
| `onboarding_completed_at` | timestamptz | yes |
| `visibility_class` | text not null default 'patient_visible' | no |
| `created_at` / `updated_at` | timestamptz not null | no |
| `locale` | text (mig 052) | yes |
Also read/written (added by other repos' migrations; `PROFILE_COLUMNS` auth.ts:207): `macros_customized` (boolean), `onboarding_source` (text), `avg_steps_per_day` (integer, read-only here), `custom_calorie_offset_kcal` (integer), `meals_per_day`, `snacks_per_day` (integer). `FORWARD_COLUMNS = { macros_customized, avg_steps_per_day, target_calories }` are stripped on PGRST204/42703 and the save retried.
**Write shape is load-bearing** (auth.ts:290-318): never `.upsert(..., { onConflict: 'patient_id' })` — `authenticated` has column-scoped grants and `patient_id` is INSERT-able but not UPDATE-able → `42501`. Implemented: `UPDATE ... WHERE patient_id = ?`; if 0 rows, `INSERT`; on `23505`, re-`UPDATE`.

#### `public.patients` — mig 003 (+ later)
`id`, `clinic_id` NOT NULL, `first_name`*, `last_name`*, `date_of_birth`, `sex`, `phone`, `email`*, `preferred_language` default 'fr', `status` default 'active', `care_stage` default 'onboarding', `created_at`, `updated_at`; later: `auth_user_id` (FK auth.users ON DELETE SET NULL), `pii_internal_id`, `email_canonical_hash` (trigger-maintained, UNIQUE). \* NULL in vault-first phase. App reads: `select('id, clinic_id').eq('auth_user_id', uid)` (self-read RLS, mig 036).

#### `public.patient_daily_checkins` — mig 022 + 028/029/032/033/070/071/077
One row per (patient_id, checkin_date), UNIQUE.
| Column | Type | Source |
|---|---|---|
| `id`, `patient_id`, `checkin_date` (date) | | 022 |
| `mood`,`digestion`,`energy`,`sleep`,`stress`,`inflammation` | integer 1–10 (legacy) | 022 |
| `bloating`,`burns` | integer 1–10 | 022 |
| `stool_type` (Bristol 1–7), `stool_quality` (1–5), `notes`, `completed_at`, `visibility_class` | | 022 |
| `functional_completed_at`, `intelligence_completed_at`, `functional_submission_count`, `intelligence_submission_count`, `last_submission_form` | | 028 |
| `hydration_ml` | integer default 0 | 029 |
| `sleep_quality` | integer | 032 |
| `abdominal_pain`,`stool_urgency`,`incomplete_evacuation`,`straining_effort`,`nausea`,`post_meal_fullness`,`gas_burden` (0–10), `stool_frequency` (0–15), 6 × `red_flag_*` boolean | | 033 |
| `energy_body`,`energy_mind`,`energy_stability`,`energy_overall`,`mood_score`,`stress_score`,`sleep_overall`,`sleep_refreshed`,`sleep_duration_min` | smallint 0–100 | 070 |
| `sleep_latency_band`, `sleep_wake_count` | text | 070 |
| `functional_detail` | jsonb (flat `Record<DimKey, DimAnswers>`) | 070 |
| `gut_comfort`,`gut_stool`,`gut_reactions`,`gut_overall` | smallint | 071 |
| `gut_detail` | jsonb `{ answers, notes }` | 071 |
| `recovery`,`soreness`,`recent_load`,`recent_mental_load` | smallint 0–10 | 077 |
**Marker contract:** every 0–100 marker is **higher = better**, including `stress_score` (stores **calmness**). Readers do a wide select and fall back to the legacy column list on a PostgREST 400. Null stays null.

#### `public.patient_daily_checkin_events` — mig 028: `{ patient_id, checkin_date, form_type: 'functional'|'intelligence', submitted_at, payload jsonb }`.
#### `public.nb_checkin_events` — per-dimension event stream (created outside this repo).
#### `public.patient_checkin_moments` — `20260817c`: `id, patient_id, checkin_date, slot ('morning'|'midday'|'evening'), submitted_at, energy_body, energy_mind, energy_stability, energy_overall, mood_score, stress_score, sleep_overall, sleep_refreshed, sleep_duration_min, sleep_latency_band, sleep_wake_count, pills jsonb, note, created_at, updated_at`; UNIQUE (patient_id, checkin_date, slot). Roll-up = median per marker; sleep from the morning moment. `TREND_EPSILON = 8`.

#### `public.nb_meal_logs` — mig 021 + 052/061 + 20260730 + 20260804
| Column | Type |
|---|---|
| `id` uuid PK, `patient_id` → patients CASCADE, `logged_at` timestamptz default now() | |
| `meal_type` | text CHECK in ('breakfast','lunch','dinner','snack','other') |
| `photo_url` | text — **a storage PATH in the private `meal-images` bucket, not a URL** |
| `ai_identified_foods` | jsonb `[{food, estimated_g, measure, confidence}]` |
| `confirmed_foods` | jsonb |
| `total_calories`,`total_protein_g`,`total_carbs_g`,`total_fat_g`,`total_fiber_g`,`total_sugar_g` | numeric |
| `micronutrient_totals` | jsonb |
| `inflammation_score`,`energy_score`,`gut_score`,`digestibility_score` | numeric 0–100 |
| `micronutrient_coverage` | numeric |
| `ai_coaching_response`, `model_used` | text |
| `visibility_class`, `created_at` | |
| `name` | text |
| `source` | text `'photo'|'text'|'voice'` |
| `glycemic_score` | numeric |
| `analysis_status` | text `'queued'|'pending'|'analyzing'|'complete'|'failed'` |
| `patient_note` | text (may be absent) |
| `protocol_flags` | jsonb (null = not computed, `[]` = clean) |
Pending-row insert writes exactly: `patient_id, logged_at, meal_type, source, photo_url, name (≤300), analysis_status: 'queued'`.

#### `public.nb_meal_reactions` — mig 021 + 052 + 059 + 068
`id, meal_log_id → nb_meal_logs, patient_id, bloating 0–10, burning 0–10, fatigue 0–10, mood_change ('better'|'same'|'worse'), notes, reaction_time, created_at, fullness, gas_burden, overall, responses jsonb, reaction_flags text[]`. Insert: `{ patient_id, meal_log_id, overall, bloating ?? 0, fullness ?? 0, gas_burden ?? 0, responses, reaction_flags, reaction_time }`.

#### `public.nb_app_consents` — mig 052: `id, patient_id, consent_type ('ai_analysis'|'combined_v2'|'q1_health_v1'|'data_processing'), version, granted, granted_at, revoked_at, ai_processing_scope jsonb, created_at`. Grants: select, insert only.
#### `public.consent_definitions` / `public.consent_audit` — `20260811_consent_arc` (+ later).
#### `public.deletion_log` — mig 052: `id, deleted_user_id, deleted_patient_id, source, deleted_at`. service_role only.
#### `public.habits` — mig 010 + habit-loop: `id, patient_id, care_plan_item_id, title, description, frequency_rule, status ('active'|'paused'|'completed'|'cancelled'), created_at, updated_at`; extended: `source ('prescribed'|'self_initiated'), domain, slot, appears_after_habit_id, easy_title, easy_description, rev_title, rev_description, pillar, learn_more_url, learn_more_kind, general_why, resources jsonb`.
#### `public.habit_completions` — app selects `id, habit_id, completion_date` (**`completion_date` is the live column**).
#### `public.habit_bank`, `habit_offers` (`id, state_key, offer_key, title, description, offered_on, accepted, completed`), `habit_notes`, `state_responses`, `care_plan_item_gates` (`id, unlocks_item_id, source_habit_ids, rule_kind, required_n, window_days, release_mode, teaser_text, state`).
#### `public.reminders` — mig 010; **never used by the app**.
#### `public.care_plans` — app selects `id, title, start_date, objective_line` where `status = 'active'`, latest.
#### `public.care_plan_items` — patient-safe columns only: `id, title, objective, patient_safe_explanation, is_weekly_focus, domain`. **`rationale` and `instruction_text` are clinician-voice: never selected.**
#### `public.care_plan_phases` — `phase_key, week_start, week_end, title, summary` (never `gate_criteria`). `care_plan_goals` — `statement, sort_order`.
#### `public.supplement_plans` — `id, patient_id, care_plan_item_id, supplement_catalog_id, dosage_text, frequency_text, start_date, review_date, status`; name from `supplement_catalog(name)` join. `supplement_logs` — `id, supplement_plan_id, taken_date`. `nb_supplement_logs` — legacy, orphan screen only.
#### `public.nb_symptom_logs` — mig 022; **no client refs**.
#### `public.patient_notifications` — mig 023; one insert from the dark chat screen.
#### `public.patient_notification_preferences` — `patient_id, daily_checkin_reminder_enabled, daily_checkin_time (HH:MM:SS), email_reminder_enabled, timezone`; defaults `{ enabled: true, time: '19:00', email: false, timezone: 'Europe/Zurich' }`.
**Device / push-token table: not found.**
#### `public.nb_reports` — retired (mig 080). `nb_report_content` — mig 074: `id, patient_id, period ('daily'|'weekly'|'monthly'), period_start, content jsonb, rag_refs, model, created_at`; UNIQUE (patient_id, period, period_start). `nb_report_interpretations` — mig 079.
#### `public.nb_score_tips` — mig 069/075: `id, patient_id, score_key ('functional'|'vitality'|'metabolic'|'nutrition'|'gut' + raw 'energy'|'sleep'|'mood'|'stress'), tip_date, summary, good, bad, factors jsonb, rag_refs, model, created_at`; UNIQUE (patient_id, score_key, tip_date).
#### `public.nb_user_patterns` — `kind ('pattern'|'trigger_food'), subject, reaction, direction ('better'|'worse'), effect, n_obs, consistency, tier ('hint'|'confirmed'), window_days, computed_at`.
#### `public.nb_assessment_responses` — one row per `patient_id + day`; shape per legacy twin: `day, answers_json, report_json, flags_json, created_at, updated_at`.
#### `public.patient_messages` — patient-visible columns listed explicitly: `id, sender_type, body, created_at, read_by_patient_at, visibility_class, context_kind, context_meal_id, context_day`. Insert: `{ patient_id, clinic_id, sender_type: 'patient', sender_user_id: null, body, visibility_class: 'patient_visible', ...context }`. Read filter `visibility_class in ('patient_visible','patient_visible_after_approval')`, asc, limit 200. Unread: `count exact head` where `sender_type = 'clinician'` and `read_by_patient_at is null`. Mark-read via RPC `member_mark_messages_read()` (no args).
#### Wearables — migs 062–067, 078: `wearable_accounts`, `wearable_connections`, `wearable_raw_events`, `wearable_daily`, `wearable_epoch`, `wearable_sync_queue`, `wearable_data_types`; views `wearable_daily_labeled`, `wearable_epoch_labeled`. App reads only `wearable_daily_labeled` (`day, metric, value, data_source_id, layer`) and `wearable_connections`. **Wearables are switched off in the UI** (`SHOW_WEARABLES`, 2026-08-13); re-enabling requires restoring Privacy Policy disclosure of Thryve.
#### `lib/types/index.ts` — 274 lines of largely **aspirational** interfaces; not a schema contract. Live shapes: `lib/plan/types.ts`, `lib/checkin/moment-types.ts`, `lib/stores/daily-store.ts`, `lib/supabase/auth.ts::PatientAppProfile`.
#### `review_flags` — not found. `appointments` — exists (mig 006) but never queried; `profile-appointment.tsx` is mock.
#### 057 legacy tables (read-only): `profiles`, `meals`, `meal_reactions`, `checkins`, `checkin_events`, `gut_checkins`, `consents`, `reports`, `assessment_responses`, `user_patterns` — field lists in the source migration; documentation only.

### 3.4 Enumerations
| Enum | Values | Where |
|---|---|---|
| Score keys | `functional`, `vitality`, `metabolic`, `nutrition`, `gut` (+ raw `energy`, `sleep`, `mood`, `stress`) | mig 069/075 |
| Pillar keys | `vitality`, `metabolic`, `nutrition` | `lib/health/pillars.ts` |
| Clinical nodes | `Energy`, `Communication`, `Defense & Repair`, `Transport`, `Assimilation` | same |
| Pillar tints | vitality `#E6CF85`, metabolic `#E0A0A0`, nutrition `#A6C2E0` | `PILLAR_TINT` |
| Check-in slots | `morning`, `midday`, `evening` | `lib/plan/types.ts` |
| Day states | `slept_poorly`, `stressed`, `low_energy`, `feeling_strong`, `slept_well` | same |
| Day trend | `rising`, `falling`, `steady` | `moment-types.ts` |
| Check-in forms | `functional`, `intelligence` | `daily-store.ts` |
| Pill groups / pillars | `day_intent`, `fuelled`, `drained` / `nutrition`, `exercise`, `mind`, `emotion`, `recovery`, `sleep` | `pill-catalog.ts` |
| Meal types / sources | `breakfast`, `lunch`, `dinner`, `snack` (+`other`) / `photo`, `text`, `voice` | `save-meal.ts` |
| Analysis status | `queued`, `pending`, `analyzing`, `complete`, `failed` | mig 20260730 |
| Reaction score keys | `glycemic`, `inflammation`, `digestion` | `use-scores-overview.ts` |
| Access tiers | `full_access`, `paid`, `beta`, `discovery`, `unknown` | `entitlement.ts` |
| Entitlement status | `active`, `grace` live | `isLive()` |
| Gate rule kinds | `streak`, `count_in_window`, `adherence_pct`, `manual` | `lib/plan/types.ts` |
| Habit status / source | `active|paused|completed|cancelled` / `prescribed|self_initiated` | mig 010 |
| Consent keys / notices | `terms_of_use`, `health_data_processing`, `usage_analytics`, `marketing_comms` / `privacy_policy`, `legal_notice`, `ai_analysis` | `consent-catalog.ts` |
| Consent status | `unknown`, `satisfied`, `required` | `use-consent-status.ts` |
| Report periods | `daily`, `weekly`, `monthly` | migs 057/074 |
| Message sender types | `patient`, `clinician` | `lib/messaging/*` |
| Visibility classes | `patient_visible`, `patient_visible_after_approval` | throughout |
| Stool scales | Bristol 1–7; quality 1–5 | mig 022 |
| Wearable layers | `raw`, `analytics` | `wearable-daily.ts` |

### 3.5 `supabase/migrations/` — 108 files
Numbered core 001–020 (CM OS clinical base: organizations/clinics/users, **patients**, encounters, **care_plans/items**, clinical_tasks/**appointments**, biomarkers, symptoms/questionnaires, **supplement_plans/logs**, **habits/habit_completions/reminders**, resources, documents, AI, audit/**access_logs**, RLS, indexes, seeds). App plane 021–037 (**nb_meal_logs/nb_meal_reactions**, **patient_daily_checkins**, **patient_notifications/preferences**, **nb_patient_app_profiles**, checkin split/hydration/sleep/gut columns, auto-provision, RLS, self-read). Repoint/parity 052–081 (**nb_app_consents/deletion_log**, care plans, **057 app tables**, daily stats RPC, **061 ETL**, wearables 062–067/078, reactions 068, **nb_score_tips** 069/075, checkin v2 070/071/077, reminder prefs 072/073, **nb_report_content** 074, report crons 076/079/080, protocol lens 081). Dated 20260729–20260821 (patient_messages, async meal analysis + **nb_patient_food_aliases**, multi-photo, **nb_favorite_meals**, **nb_checkin_custom_pills**, **consent arc**, **habit loop** tables, **habit_bank**, **patient_checkin_moments**, **habit_notes**, age gate, consent batch/seed/versions, profile write grants, member locale/library stage/entitlements read-only, score-tip + report-content locale steps, kb_nodes cover image).
**Not created by any migration in this repo** (live in MEMBERS/CLINICAL): `member_entitlements`, `member_library_access`, `patient_track_priority`, `member_lesson_progress`, `library_tracks`, `library_track_lessons`, `nb_reports`, `nb_weekly_themes`, `nb_checkin_events`, `nb_user_patterns`, `nb_assessment_responses`, `nb_food_products`, `patient_messages`, `patient_intake_questionnaire`, `patient_resources`, `pii.patients`.

## 4. The "Today" / Home data set — `app/(tabs)/index.tsx`
Direct reads: (1) `loadCheckinHistory` → `patient_daily_checkins` 7 rows (`checkin_date, mood, digestion, energy, sleep, sleep_quality, stress, inflammation, energy_overall, sleep_overall, mood_score, stress_score`; `functional_completed_at not null`, `< today`, `>= today-6d`); (2) `loadTodayCheckin` → today, `.maybeSingle()`; (3) `loadGutCheckinHistory` → 13-day gut window; (4) `loadReminderPrefs`; (5) `useWearableHistory(14)`. From stores: `useLogStore.meals` (`nb_meal_logs` 30 days limit 100 + `nb_meal_reactions`), `useOnboardingStore` (profile). Computed: `deriveTrends(...)` → composite/vitality/metabolic/nutrition scores (client-side); `buildOverallSeries`; `buildFunctionalSeries`; `shouldPromptCheckin`. Child cards: `ProtocolReviewCard` (`nb_patient_protocols`, `nb_protocol_overrides`), `MessagesCard` (`patient_messages` unread), `PlanTodayCard` (habits bundle, flagged off), `LatestArticleCard` (library tables).

### Minimal query set for a native Home
1. `patient_daily_checkins` — today (`checkin_date = localDayISO()`), wide column list with legacy fallback
2. `patient_daily_checkins` — trailing 13 days (`functional_completed_at NOT NULL`)
3. `patient_daily_checkins` — trailing 13 days (`intelligence_completed_at NOT NULL`) *(2+3 can be one select with `.or()`)*
4. `nb_meal_logs` — 30 days, limit 100, plus `nb_meal_reactions`
5. `patient_notification_preferences` — one row
6. `patient_messages` — unread count
All scores are computed **client-side** from 1+4 — no score table is read on Home.

## 5. Profile screen — `app/(tabs)/profile.tsx`
Reads: `useAuthStore.user` — display name from `user_metadata.full_name` → `user_metadata.name` → `email.split('@')[0]` → `'Client'` (**no PII fetch**; copy says "client", never "patient", D-18); `useOnboardingStore().currentComplaints` via `COMPLAINT_LABELS`; `useCarePlan()` → `care_plans`, `care_plan_goals`, `care_plan_items`; `<AccessWindowStrip/>` → `member_entitlements`. Renders avatar + first name + "FunctionAlps client" → `profile-settings`; access strip; a **hard-coded** "Functional trend" sparkline (literal 72) → `dashboard`; care-plan preview or honest waiting state; baseline edit → `ob-baseline?edit=1`; feedback; guide.

## 6. Date/time, ID and pagination conventions
- **`localDayISO()`** (`lib/dates/local-day.ts`): device-local `YYYY-MM-DD`, canonical for `checkin_date` and day buckets (Swiss UTC+1/+2 bug history). Server-stamped day columns (`tip_date`, `period_start`) keep the server convention. Timestamps `toISOString()` (UTC). `shiftDayISO` for day arithmetic. Pure modules never call `new Date()`. Timezone stored on `patient_notification_preferences.timezone`. Meal type by hour: `<11` breakfast, `<15` lunch, `<18` snack, else dinner. RRULE subset `FREQ=DAILY|WEEKLY`, `BYDAY`, `INTERVAL`.
- IDs: all uuid. **`patientId` = `public.patients.id`**; `auth.users.id` only for `patients.auth_user_id`, RLS, meal-photo storage prefix (`uid/` current, `patientId/` legacy), `deletion_log`. Natural keys for upserts listed above. Dedup key `patients.email_canonical_hash`; client `normalizeEmail()`.
- Pagination: **none** — bounded windows with fixed `.limit()` (1/12/24/50/100/200) and time windows (meals 30d, checkins 6/13/14d, completions 70d, wearables 14d). Counts via `count: 'exact', head: true`. TanStack `staleTime: 5 min`, `retry: 2`.

## 7. Notable risks and inconsistencies
1. Tokens in AsyncStorage, not SecureStore.
2. Google OAuth and password reset are structurally web-only.
3. No `startAutoRefresh`/`stopAutoRefresh` on `AppState`.
4. No push notification registration; email-only reach.
5. `DEV_BYPASS_AUTH` hard-coded constant.
6. Duplicate delete-account implementation; settings path ignores `result.deleted`.
7. `useSyncLocaleToProfile` called twice.
8. Profile "Functional trend" card is mock data.
9. `profile-appointment.tsx` entirely mock while `appointments` exists.
10. `lib/types/index.ts` substantially stale.
11. `ensure_patient_for_auth_user()` (mig 034) writes plaintext PII — confirm EXECUTE revoked.
12. `nb_symptom_logs` has a screen but no query in the census.
