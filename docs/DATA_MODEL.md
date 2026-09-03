# DATA_MODEL — domain concepts and the CM OS rows behind them

Derived from the real backend (audit/app-auth-data.md §3), not from the PRD's example list. Domain names are what Swift models use; the table column is the wire truth. Only the member-facing subset is listed; clinician-only columns (`rationale`, `instruction_text`, `gate_criteria`, `ai_draft_*`) are never selected.

## Conventions
- **Identity:** `Member.patientId` = `public.patients.id` (uuid). `auth.users.id` is used only for the auth link, RLS and the meal-photo storage prefix. Never mix them.
- **Days:** `YYYY-MM-DD` in the **member's local calendar** (`ISO8601.dayString`) for `checkin_date` and day buckets; server-stamped day columns (`tip_date`, `period_start`) keep the server convention. Timestamps are ISO-8601 UTC; Postgres emits up to 6 fractional digits (`JSON.decoder` handles it).
- **Markers:** 0–100, **higher = better**, including `stress_score` which stores *calmness*. Null stays null (never 0). Legacy 1–10 columns exist as fallback.
- **Pagination:** none upstream; bounded windows with `limit` (meals 30 d / 100 rows, check-ins 6–14 d, messages 200, completions 70 d).
- **Enums:** see audit/app-auth-data.md §3.4 for the full list; the Swift enums below mirror them verbatim.

## Domain → row map

| Domain (Swift) | Table / source | Key columns (member-facing) | Status |
|---|---|---|---|
| `AuthSession` | GoTrue token response | `access_token`, `refresh_token`, `expires_at`, `user.id`, `user.email`, `user.user_metadata.{patient_id, full_name, name, first_name}` | M1 |
| `Member` | session + `patients` (id via RPC) | `patientId`, `displayName` (never from the PII vault) | M1 |
| `MemberProfile` | `nb_patient_app_profiles` | `app_sex`, `app_age`, `app_height_cm`, `app_weight_kg`, `activity_level`, `health_goals[]`, `current_complaints[]`, `dietary_pattern`, `target_calories/protein_g/carbs_g/fat_g`, `goal_mode`, `onboarding_completed_at`, `locale` (+ `tdee_kcal`, `estimated_body_fat_percent`, `weekly_workout_frequency`, `workout_type`, `session_duration_min`, `self_reported_supplements[]`, `custom_supplements`, `macros_customized`, `custom_calorie_offset_kcal`, `meals_per_day`, `snacks_per_day`, `avg_steps_per_day`) | M1 read; Phase A write (UPDATE-then-INSERT) |
| `MealLog` | `nb_meal_logs` | `id`, `logged_at`, `meal_type`, `name`, `source`, `analysis_status`, `total_calories`, `total_protein_g`, `total_carbs_g`, `total_fat_g`, `total_fiber_g`, `total_sugar_g`, `photo_url` (storage **path**), `photo_urls`, `ai_identified_foods`, `confirmed_foods`, `micronutrient_totals`, `micronutrient_coverage`, score columns, `protocol_flags`, `patient_note` | M1 read; Phase D full |
| `MealReaction` | `nb_meal_reactions` | `meal_log_id`, `overall`, `bloating`, `fullness`, `gas_burden`, `responses`, `reaction_flags[]`, `reaction_time` | Phase D |
| `FavoriteMeal`, `FoodAlias` | `nb_favorite_meals`, `nb_patient_food_aliases` | — | Phase D |
| `DailyCheckin` | `patient_daily_checkins` | `checkin_date`, `functional_completed_at`, `intelligence_completed_at`, `energy_overall`, `mood_score`, `sleep_overall`, `stress_score` (calmness), `sleep_refreshed`, `sleep_duration_min`, `gut_comfort/stool/reactions/overall`, `hydration_ml`, `recovery`, `soreness`, gut 0–10 columns, `red_flag_*`, `functional_detail`, `gut_detail`; legacy `mood/digestion/energy/sleep/stress/inflammation` 1–10 | M1 read (today); Phase B write |
| `CheckinMoment` | `patient_checkin_moments` | `checkin_date`, `slot` (morning/midday/evening), markers, `pills` jsonb, `note`; UNIQUE (patient, date, slot); writes limited to today/yesterday | Phase B |
| `CheckinEvent` | `nb_checkin_events`, `patient_daily_checkin_events` | per-dimension raw values / form payloads | Phase B |
| `Assessment` (Q1, days 2–5) | `nb_assessment_responses` | `day`, `answers_json`, `report_json`, `flags_json` | Phase B |
| `CarePlan`, `CarePlanItem`, `CarePlanPhase`, `CarePlanGoal` | `care_plans`, `care_plan_items`, `care_plan_phases`, `care_plan_goals` | plans: `id, title, start_date, objective_line, status`; items: `id, title, objective, patient_safe_explanation, is_weekly_focus, domain`; phases: `phase_key, week_start, week_end, title, summary`; goals: `statement, sort_order` | Phase A (profile card) / D |
| `Habit`, `HabitCompletion`, `HabitOffer`, `HabitNote`, `Gate` | `habits`, `habit_completions` (`completion_date`), `habit_offers`, `habit_notes`, `habit_bank`, `care_plan_item_gates`, `state_responses` | see audit §3.3 | Phase D (flag OFF today) |
| `SupplementPlan`, `SupplementLog` | `supplement_plans` (+ `supplement_catalog.name`), `supplement_logs` (`taken_date`) | — | Phase D |
| `Protocol` | `nb_patient_protocols`, `nb_protocol_overrides`, `nb_meal_logs.protocol_flags` | `protocol_key, strictness, patient_visibility` / `food_term, action, severity` | Phase D |
| `ScoreTip`, `Pattern`, `Report` | `nb_score_tips`, `nb_user_patterns`, `nb_report_content` (+ interpretations) | server-written | Phase E |
| `Track`, `Lesson`, `LessonProgress`, `LibraryAccess` | `library_tracks`, `library_track_lessons`, `member_lesson_progress`, `member_library_access`, `patient_track_priority`; RPCs `member_library_*` | `body_md` via `member_library_get` | Phase F |
| `Entitlement` | `member_entitlements` | `access_type` (full_access/paid/beta/discovery), `status` (active/grace), `starts_at`, `expires_at` | Phase A (gate) — window rule is app-side today |
| `Consent`, `ConsentDefinition` | `consent_definitions`, `consent_audit` via RPCs; legacy `nb_app_consents` | keys `terms_of_use`, `health_data_processing`, `usage_analytics`, `marketing_comms`; notices `privacy_policy`, `legal_notice`, `ai_analysis` | Phase A (gate before external testers) |
| `Message` | `patient_messages` | `id, sender_type, body, created_at, read_by_patient_at, visibility_class, context_kind, context_meal_id, context_day` | M1 unread count; Phase A/B thread |
| `NotificationPreferences` | `patient_notification_preferences` | `daily_checkin_reminder_enabled`, `daily_checkin_time`, `email_reminder_enabled`, `timezone` | Phase G |
| `WearableDay`, `WearableConnection` | `wearable_daily_labeled`, `wearable_connections` | `day, metric, value, data_source_id, layer` | Phase H |
| `Document` / `TestResult` / `Appointment` | not member-facing today (`appointments` exists, unused; biomarkers screens are mock) | — | product decision |

## Not modelled on purpose
`lib/types/index.ts` in the Expo app is aspirational and contradicts live tables (`MealItem`, `NutritionProfile`, `Appointment`, `HealthScore`, `WearableData`) — do not port it. The 057 legacy tables (`meals`, `checkins`, …) are read-only history.

## Server-side vs client-side truth (what the Swift app must NOT recompute)
Authoritative server-side today: Q1 loads + red flags (`q1-complete`), habit-gate arithmetic (`evaluate-gates`), macro targets (`compute_macro_targets` trigger), user patterns (`compute_user_patterns`), report content (`generate-report`), score tips text, meal composition scores (`_shared/meal-scores.ts`, one implementation imported by both planes), food resolution.
Client-only today (**must move server-side before the native Trends/Progress phase**): Functional Score crown composite and pillar scores (`lib/health/*`), gut score / digestion override, check-in red flags (`lib/checkin/red-flags.ts`), day 3/4/5 assessment scores, meal-reaction question engine, streaks, entitlement window arithmetic, recovery/longevity from wearables. See IOS_MIGRATION_MAP §"Server-side moves".
