# SUPABASE_DEPENDENCY_MAP — everything the patient app depends on in CM OS

Project: Supabase **CM OS** `ndojytvvlvlbgtodujkf` (eu-north-1, Postgres 17), shared by all five FunctionAlps apps. Raw evidence and per-file line numbers: `audit/app-backend-census.md`, `audit/app-auth-data.md`.

Legend for "belongs in": **Frontend** = client concern, **Backend** = server logic (edge fn / RPC / trigger), **API** = should sit behind the FunctionAlps API boundary, **Infra** = hosting/config.

## 1. Database queries (PostgREST from the client, RLS-scoped to the member's own `patient_id`)
41 tables. Full per-file table in the census §1. Summary by plane:

| Plane | Tables | Belongs in | iOS M1 |
|---|---|---|---|
| App profile | `nb_patient_app_profiles` (R/W; column-scoped grants, UPDATE-then-INSERT never upsert) | Frontend read / **API** for writes | read |
| Meals | `nb_meal_logs` (R/W), `nb_meal_reactions` (R/W), `nb_favorite_meals`, `nb_patient_food_aliases`, `nb_food_items`, `nb_food_products` | Frontend read; writes stay client-side under RLS for now | read `nb_meal_logs` |
| Check-ins | `patient_daily_checkins` (R/W, 10 files), `patient_daily_checkin_events`, `patient_checkin_moments`, `nb_checkin_events`, `nb_checkin_custom_pills` | Frontend read/write under RLS | read today |
| Reports / tips / patterns | `nb_report_content`, `nb_report_interpretations`, `nb_score_tips`, `nb_user_patterns`, `nb_reports` (RETIRED), `nb_weekly_themes` (orphan) | Backend-written, client read | — |
| Plan / habits | `care_plans`, `care_plan_items` (patient-safe columns only), `care_plan_phases`, `care_plan_goals`, `care_plan_item_gates`, `habits`, `habit_completions`, `habit_offers`, `habit_bank`, `habit_notes`, `state_responses`, `supplement_plans`, `supplement_logs` | mixed; gate logic is Backend (`evaluate-gates`) | — |
| Library | `library_tracks`, `library_track_lessons`, `member_library_access`, `member_lesson_progress`, `patient_track_priority` | via RPCs (below) | — |
| Access / consent | `member_entitlements` (R), `nb_app_consents` (legacy R), `consent_definitions`/`consent_audit` (via RPCs) | **Backend** — entitlement window is currently an app-side rule (3-day discovery) | — |
| Messaging | `patient_messages` (explicit column list — never `*`, AI-draft columns live in the same table), `patient_notifications` (dark), `patient_notification_preferences` | Frontend read; mark-read via RPC | unread count |
| Identity | `patients` (`id, clinic_id` by `auth_user_id`), `patient_intake_questionnaire`, `patient_resource_assignments` | — | — |
| Wearables | `wearable_daily_labeled` (view), `wearable_connections` | Backend | — |
| Legacy 057 plane | `profiles`, `meals`, `checkins`, `gut_checkins`, `consents`, `reports`, `assessment_responses`, `user_patterns` — read-only since mig 061, **not used** | — | never |

Direct browser/app → table interactions that a future API boundary should absorb first: all **writes** (`nb_meal_logs`, `nb_meal_reactions`, `patient_daily_checkins`, `patient_checkin_moments`, `habit_*`, `supplement_logs`, `nb_patient_app_profiles`) because each carries schema-shape knowledge (column grants, upsert rules, PGRST204 traps) that today lives in client comments.

## 2. Authentication
- Supabase Auth (GoTrue): password grant, sign-up with `user_metadata {first_name,last_name,phone}`, Google OAuth (web-only as written), `resetPasswordForEmail` (web redirect only). No magic link, no biometrics.
- Session storage: **AsyncStorage** (plaintext) — `expo-secure-store` installed but unused. iOS: Keychain.
- Identity convention: `patientId = public.patients.id` from `user_metadata.patient_id` → RPC `current_member_patient_id()` → edge fn `patient-register`.
- Belongs in: Frontend (token handling) + Backend (`patient-register`, metadata stamping). API-boundary candidate: `/auth/*` façade later.

## 3. Storage
One bucket, **`meal-images`** (private): `upload` (`uid/…jpg`), `createSignedUrl`, `remove`; purged by `delete-account`. Belongs in: Frontend (upload) + Backend (signed URL policy). iOS Phase D.

## 4. Realtime
Two channels: `plan-habits-${patientId}` (`habits` INSERT/UPDATE) and `meal-analysis-${mealLogId}` (`nb_meal_logs` UPDATE while analysis runs). Belongs in: Frontend. iOS Phase D (polling is an acceptable first implementation; Supabase Realtime is websockets + Phoenix protocol — not needed for M1).

## 5. RPC / Postgres functions (client-called)
`current_member_patient_id()`, `email_exists(p_email)`, `member_pending_consents(p_locale,p_include_drafts)`, `record_consent(...)`, `record_consent_batch(...)`, `revoke_consent(...)`, `confirm_member_adult(...)`, `current_member_is_adult()`, `member_library_stage()`, `member_library_list()`, `member_library_get(p_slug)`, `member_mark_messages_read()`. Server-only: `canonical_email_hash`, `grant_member_entitlement`, `pii_*`, `app_daily_stats`, `match_food_items/products`, `compute_macro_targets` (trigger), `compute_user_patterns`. Belongs in: Backend. iOS M1 uses `current_member_patient_id`.

## 6. RLS policies
On for every table; dual pattern `service_role_bypass_*` + member self-select on `patient_id` (via `patients.auth_user_id = auth.uid()`); column-scoped grants on `nb_patient_app_profiles` (patient_id INSERT-only), `member_entitlements` read-only for clients, `patient_messages` row-scoped (hence explicit column lists), `patient_checkin_moments` writes limited to today/yesterday in the member's timezone. Belongs in: Backend/Infra. **Never trust the client**: the iOS app relies on these, adds nothing.

## 7. Edge Functions (33 in repo; 17 invoked by the app)
Client-invoked: `analyze-meal`, `preprocess-meal`, `resolve-foods`, `transcribe-audio`, `patient-register`, `q1-complete`, `member-feedback`, `evaluate-gates`, `delete-account`, `message-notify`, `generate-score-tip`, `thryve-connect`, `movement-report`, `sleep-report`, `mind-report` (+ 4 dark AI stubs). Server-only: `retry-meal-analysis`, `daily-checkin-reminder`, `send-review-digest`, `thryve-sync`, `thryve-webhook`, `wearable-ingest`, `member-pii`, `clinician-pii`, `pii-backfill`, `resolve-patient`, `generate-report` (cron), retired `generate-daily-report`/`generate-periodic-report`. AI provider: **Infomaniak** only (Mistral-Small, Gemma vision, Qwen, Whisper). Belongs in: Backend. These ARE the de-facto FunctionAlps API today; iOS calls them through `EdgeFunctionClient` (none needed in M1).
Repo-vs-prod drift flagged: `generate-score-tip` and the retired report functions are behind production; `patient-register` and `sovereign-crypto.ts` are copy-pasted across repos.

## 8. Cron / scheduled jobs
pg_cron → edge functions: `retry-meal-analysis` (every minute), `daily-checkin-reminder` (*/30), `send-review-digest` (nightly), `thryve-sync`, `generate-report` (crons 12/13/15), `message-notify` sweep (15 min). Belongs in: Infra/Backend. No iOS impact.

## 9. Webhooks
`thryve-webhook` (static `THRYVE_WEBHOOK_AUTH`). Belongs in: Backend.

## 10. SDK usage
`@supabase/supabase-js` everywhere (`lib/supabase/client.ts` singleton): `.from`, `.rpc`, `.functions.invoke`, `.storage`, `.channel`, `auth.*`. iOS: **no SDK** — `SupabaseAuthClient`, `PostgRESTClient`, `EdgeFunctionClient` over URLSession, confined to `Core/`.

## 11. Direct REST usage
None (`fetch` to `/functions/v1/` not found).

## 12. Environment variables
Client: `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`/`_ANON_KEY` (**hard-coded CM OS fallbacks in source**), feature flags (`ENABLE_AI_CHAT`, `ENABLE_FR`, `ENABLE_CONSENT_GATE`, `CONSENT_INCLUDE_DRAFTS`, `ENABLE_ONBOARDING_GATE`, `ONBOARDING_TARGET`, `DISABLE_ACCESS_GATE`, `ENABLE_COVERAGE_NUDGE`), `BOOKING_URL`, `MEMBERS_ONBOARDING_URL`, `MEMBERS_REQUEST_URL`. Server (Deno): Infomaniak keys/models, `REPORT_SECRET`, `RESOLVE_SECRET`, `SOVEREIGN_KEK_HEX`, `SUPABASE_SERVICE_ROLE_KEY`, SMTP, Thryve. iOS: `FA_SUPABASE_URL`, `FA_SUPABASE_PUBLISHABLE_KEY`, `FA_API_BASE_URL`, `FA_ENVIRONMENT_NAME` via xcconfig; **no server secret ever**.

## 13. Admin / service-role operations
Only inside edge functions (`resolvePatientId` uses `getUser(token)` on the service client because legacy anon JWTs are disabled on this project; writes after ownership checks). Never in any client. iOS: same rule, enforced by `CLAUDE.md` rule 4 and `.claude/settings.json` deny list.
