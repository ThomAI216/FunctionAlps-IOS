# Audit — Patient App backend dependency census (raw)

Source repo: `FunctionAlps-APP` (`/home/user/functionalps-app`, commit ad44f35, cloned 2026-09-02). Backend: shared Supabase "CM OS" `ndojytvvlvlbgtodujkf`. Produced by a read-only exploration agent; kept verbatim as the evidence base for `SUPABASE_DEPENDENCY_MAP.md` and `API_MAP.md`.

## 12-line summary

1. **41 distinct tables** touched from the client across ~45 files; 20 are legacy `nb_*` (meal logs, checkin events, reports, score tips, protocols, aliases, favorites) and 21 are CM OS clinical-plane tables (`patient_*`, `care_plan*`, `habit*`, `supplement_*`, `library_*`, `member_*`, `wearable_*`).
2. **Dead/orphan data paths found**: `nb_reports` (retired by mig 080) is still read by `lib/report/useDailyReport.ts` — a hook with **zero importers**; `nb_report_interpretations` read by `use-interpretation.ts`, also **zero importers**; `nb_weekly_themes` and `nb_supplement_logs` are only touched by unreachable screens (`app/(screens)/weekly-theme.tsx`, `log-supplements.tsx` — no route links in).
3. **14 RPCs** called from the client (`current_member_patient_id`, `email_exists`, `member_library_*`, consent/age-gate family, `member_mark_messages_read`) — all in `lib/supabase/auth.ts`, `lib/library/data.ts`, `lib/legal/*`, `lib/messaging/*`.
4. **17 edge functions are invoked from the app**; 4 of them (`chatbot-message`, `chatbot-execute-action`, `nutri-plan-chat`, `nutri-ai-generate`) are deployed as 410 refusal stubs and gated dark by `AI_CHAT_ENABLED`. No `fetch()` to `/functions/v1/` anywhere — every call goes through `functions.invoke`.
5. **Every invoked name has a repo directory**; no deployed-only names. 11 repo functions are server-only (crons `retry-meal-analysis`, `daily-checkin-reminder`, `send-review-digest`, `thryve-sync`; webhook `thryve-webhook`; ops `member-pii`, `clinician-pii`, `pii-backfill`, `resolve-patient`, `wearable-ingest`) and 2 are RETIRED (`generate-daily-report`, `generate-periodic-report`).
6. **`generate-report` has no live client caller** — the invoke in `use-report-content.ts:67` and `fire-daily-report.ts:39` are both commented out; the pipeline is cron-only now.
7. **AI provider is uniformly Infomaniak (Geneva)**: `mistralai/Mistral-Small-4-119B-2603` for narrative/report/tips, `google/gemma-4-31B-it` vision + `qwen3` text for meal analysis, `whisper` for transcription. No OpenAI in any live path (`preprocess-meal` was silently on OpenAI `gpt-5.4` in prod until 2026-08-20 per its header).
8. **Storage**: one bucket, `meal-images` (upload / createSignedUrl / remove). **Realtime**: two channels — `plan-habits-${patientId}` on `habits`, `meal-analysis-${id}` on `nb_meal_logs`.
9. **Hardcoded fallbacks in `lib/supabase/client.ts`** — project URL `ndojytvvlvlbgtodujkf.supabase.co` and publishable key `sb_publishable_LVGwAdT4rrdto0hTMHUhrw_ikue9GGM` are baked in when env is blank. Deliberate and documented, but it means the app cannot be pointed elsewhere by env alone.
10. **Health-relevant math is computed client-side**: the Functional/Vitality/Metabolic/Nutrition/Recovery/Longevity composites (`lib/health/*`), gut scores, marker trends, day-3/4/5 assessment scores, meal reaction scoring, and streaks. Only Q1 (`q1-complete`) recomputes loads + red flags server-side; days 3/4/5 send client-computed scores **to** the edge function.
11. **Client-side red flags exist in two places with no server mirror**: `lib/checkin/red-flags.ts` (blood in stool, black stool, vomiting, fever, weight loss, severe pain) and `lib/assessment/red-flags.ts` (only the latter is re-derived server-side).
12. **Notifications are essentially unimplemented**: one local `scheduleNotificationAsync` in `lib/checkin/meal-reaction-nudge.ts`, native-only, no-op on web. **No device/push token is ever obtained or stored — no token table exists.** `daily-checkin-reminder` and `message-notify` are both **email over SMTP**, not push.

---

## 1. Table census

### 1a. Per (table, file)

**Legacy `nb_*` tables**

| Table | File | Op | Notes |
|---|---|---|---|
| `nb_patient_app_profiles` | `lib/supabase/auth.ts:222` | select `*` | by patient_id |
| | `lib/i18n/profile-locale.ts:44,53` | select `locale` / update `{locale}` | |
| | `lib/account/user-data.ts:23` | select `*` | GDPR export |
| `nb_meal_logs` | `lib/stores/log-store.ts:226,329` | select | columns list, `.eq(patient_id).gte(logged_at)` |
| | `lib/meal-log/save-meal.ts:134,233,322` | insert | pending row / full row |
| | `lib/meal-log/save-meal.ts:151,170,187,365,401` | update | photo_url, photo_urls, meal_type, analysis, patient_note |
| | `lib/meal-log/save-meal.ts:348` | delete | by id |
| | `lib/meal-log/reanalyze.ts:109` | update | `coverage_resolved_at` |
| | `lib/hooks/useMealAnalysisStatus.ts:311` | select | + realtime UPDATE subscription |
| | `lib/report/use-report-content.ts:39` | select `logged_at` | staleness probe |
| | `lib/components/home/ProtocolReviewCard.tsx:47` | select `logged_at, protocol_flags` | |
| | `lib/account/user-data.ts:24` | select `*` | |
| `nb_meal_reactions` | `lib/stores/log-store.ts:236,330` | select | `meal_log_id, overall, bloating, gas_burden, fullness, reaction_flags` |
| | `lib/checkin/meal-reaction.ts:26` | insert | |
| | `lib/account/user-data.ts:25` | select `*` | |
| `nb_checkin_events` | `lib/checkin/functional-persistence.ts:74,184` | insert | event rows |
| | `lib/checkin/gut-persistence-v2.ts:94` | insert | |
| | `lib/checkin/moment-persistence.ts:507` | insert | |
| | `lib/account/user-data.ts:27` | select `*` | |
| `nb_checkin_custom_pills` | `lib/checkin/custom-pills-store.ts:13,32` | select `group_key, option_key, label` / upsert | |
| `nb_assessment_responses` | `lib/stores/program-store.ts:31,52` | select `day, created_at` / upsert | 5-day program |
| | `lib/account/user-data.ts:28` | select `*` | |
| `nb_reports` | `lib/report/useDailyReport.ts:27` | select `stats,status,period_start` | ⚠ **RETIRED table** (mig 080, last write 2026-07-16) and the hook has **no importers** |
| | `lib/account/user-data.ts:29` | select `*` | export still drains it |
| `nb_report_content` | `lib/report/use-report-content.ts:74` | select `content,updated_at,period_start` | key `(patient,period,locale[,period_start])` |
| | `lib/report/use-reports-index.ts:50,51,52` | select | daily / weekly / monthly |
| | `lib/account/user-data.ts:32` | select `*` | |
| `nb_report_interpretations` | `lib/report/use-interpretation.ts:22` | select `content,status,reviewed_at` | ⚠ hook has **no importers** |
| `nb_user_patterns` | `lib/patterns/use-patterns.ts:32` | select `kind, subject, reaction, direction, effect, n_obs, consistency, tier` | |
| | `lib/account/user-data.ts:31` | select `*` | |
| `nb_app_consents` | `lib/legal/consent-update.ts:70` | select `consent_type, version, created_at, revoked_at` | |
| | `lib/account/user-data.ts:30` | select `*` | |
| `nb_score_tips` | `lib/health/use-score-tips.ts:45` | select `score_key, summary, good, bad` | |
| | `lib/health/use-raw-score-tip.ts:26` | select `summary, good, bad` | |
| | `lib/health/use-gut-composite-tips.ts:32` | select `score_key, summary` | |
| `nb_patient_protocols` | `lib/health/protocol-load.ts:27` | select `protocol_key, strictness, patient_visibility` | |
| `nb_protocol_overrides` | `lib/health/protocol-load.ts:32` | select `protocol_key, food_term, action, severity` | |
| `nb_food_items` | `lib/meal-log/patient-aliases.ts:193` | select `id, name` | |
| `nb_food_products` | `lib/meal-log/patient-aliases.ts:200` | select `off_code, name` | |
| `nb_patient_food_aliases` | `lib/meal-log/patient-aliases.ts:226,245,258` | select / update / insert | learned corrections |
| `nb_favorite_meals` | `lib/meal-log/favorites.ts:93,109,123,132` | select / insert / delete / update | |
| `nb_weekly_themes` | `app/(screens)/weekly-theme.tsx:106` | select `title, rationale, picks` | ⚠ screen has **no inbound route link** |
| `nb_supplement_logs` | `app/(screens)/log-supplements.tsx:57` | insert | ⚠ screen has **no inbound route link**; note the *live* plan uses `supplement_logs` (no prefix) |

**CM OS clinical-plane tables (no prefix)**

| Table | File | Op |
|---|---|---|
| `patient_daily_checkins` | `lib/checkin/persistence.ts:36,165,225,276` | select |
| | `lib/checkin/persistence.ts:89` | upsert (`onConflict patient_id,checkin_date`) |
| | `lib/checkin/functional-persistence.ts:46,117` | upsert |
| | `lib/checkin/gut-persistence.ts:24`, `gut-persistence-v2.ts:50`, `hydration-persistence.ts:19` | upsert |
| | `lib/checkin/moment-persistence.ts:486,494` | select / upsert |
| | `lib/checkin/load-today.ts:90` | select |
| | `lib/plan/data.ts:243,374` | select `sleep_overall, stress_score, energy_overall, mood_score, energy_body, energy_mind` |
| | `lib/report/use-report-content.ts:38` | select `functional_completed_at` |
| | `lib/account/user-data.ts:26` | select `*` |
| `patient_daily_checkin_events` | `lib/checkin/persistence.ts:130` | insert |
| `patient_checkin_moments` | `lib/checkin/moment-persistence.ts:391,412` | select |
| | `lib/checkin/moment-persistence.ts:473` | upsert (`patient_id,checkin_date,slot`) |
| `patient_notification_preferences` | `lib/checkin/reminder-prefs.ts:36` | select `daily_checkin_reminder_enabled, daily_checkin_time, email_reminder_enabled, timezone` |
| | `lib/checkin/reminder-prefs.ts:61` | upsert (`onConflict patient_id`) |
| `patient_messages` | `lib/messaging/patient-messages.ts:43,64,95` | select / insert / count-head |
| `patient_notifications` | `app/(tabs)/chat.tsx:1456` | insert (`type:'care_plan_update'`, `trigger_type:'realtime'`, `priority:'high'`) — reachable only when AI chat is on (dark) |
| `patients` | `lib/messaging/patient-messages.ts:31` | select `id, clinic_id` |
| | `lib/resources/use-resources.ts:187` | select `id` |
| | `lib/onboarding/intake-baseline.ts:183` | select `date_of_birth` |
| `patient_intake_questionnaire` | `lib/onboarding/intake-baseline.ts:176` | select `answers, submitted_at, updated_at` |
| `patient_resource_assignments` | `lib/resources/use-resources.ts:194` | select |
| `patient_track_priority` | `lib/library/data.ts:237` | select `track_id, position` |
| `care_plans` | `lib/plan/data.ts:205,393`, `lib/library/data.ts:239`, `lib/care-plan/use-care-plan.ts:164` | select |
| `care_plan_items` | `lib/plan/data.ts:330`, `lib/care-plan/use-care-plan.ts:187` | select |
| `care_plan_item_gates` | `lib/plan/data.ts:324` | select `rule_kind, required_n, window_days, release_mode, teaser_text, state` |
| `care_plan_phases` | `lib/plan/data.ts:317` | select |
| `care_plan_goals` | `lib/library/data.ts:352` | select `statement, sort_order` |
| `habits` | `lib/plan/data.ts:213` | select |
| | `lib/plan/data.ts:569,598` | insert (self-habit, from bank) |
| | `lib/plan/data.ts:617` | update |
| `habit_completions` | `lib/plan/data.ts:221` | select |
| | `lib/plan/data.ts:487,492` | delete / insert (toggle) |
| `habit_offers` | `lib/plan/data.ts:237,406` | select |
| | `lib/plan/data.ts:445` | upsert |
| | `lib/plan/data.ts:538` | update `{completed}` |
| `habit_bank` | `lib/plan/data.ts:552` | select |
| `habit_notes` | `lib/plan/data.ts:641,656,664` | select / delete / upsert (`patient_id,habit_id`) |
| `supplement_plans` | `lib/plan/data.ts:227` | select (+ join `supplement_catalog_id(name)`) |
| `supplement_logs` | `lib/plan/data.ts:232` | select |
| | `lib/plan/data.ts:516,521` | delete / insert |
| `state_responses` | `lib/plan/data.ts:401` | select |
| `library_tracks` | `lib/library/data.ts:226` | select |
| `library_track_lessons` | `lib/library/data.ts:229` | select |
| `member_library_access` | `lib/library/data.ts:233` | select `tracks_enabled, foundations_enabled, supplements_enabled` |
| `member_lesson_progress` | `lib/library/data.ts:230` | select |
| | `lib/library/data.ts:480,493` | insert (track lesson / standalone) |
| `member_entitlements` | `lib/access/entitlement.ts:128` | select `access_type, status, starts_at, expires_at` |
| `wearable_daily_labeled` | `lib/wearables/use-wearable-history.ts:24` | select `day, metric, value, data_source_id, layer` (view) |
| `wearable_connections` | `app/(screens)/profile-wearables.tsx:38` | select `data_source_id, status, connected_at` |

### 1b. Deduped summary

| Table | Access | Files |
|---|---|---|
| `nb_meal_logs` | R/W | 7 |
| `patient_daily_checkins` | R/W | 10 |
| `nb_checkin_events` | R/W | 4 |
| `nb_report_content` | R | 3 |
| `nb_score_tips` | R | 3 |
| `patient_checkin_moments` | R/W | 1 |
| `nb_meal_reactions` | R/W | 3 |
| `habits` / `habit_completions` / `habit_offers` / `habit_notes` | R/W | 1 each (`lib/plan/data.ts`) |
| `habit_bank`, `state_responses`, `care_plan_*` | R | 1–2 |
| `supplement_plans` (R) / `supplement_logs` (R/W) | | 1 |
| `nb_patient_app_profiles` | R/W | 3 |
| `nb_patient_food_aliases`, `nb_favorite_meals` | R/W | 1 each |
| `nb_assessment_responses` | R/W | 2 |
| `nb_app_consents`, `nb_user_patterns`, `nb_reports`, `nb_report_interpretations`, `nb_food_items`, `nb_food_products`, `nb_patient_protocols`, `nb_protocol_overrides`, `nb_weekly_themes` | R | 1–2 each |
| `nb_checkin_custom_pills`, `patient_notification_preferences` | R/W | 1 each |
| `patient_messages` | R/W | 1 |
| `patient_notifications`, `patient_daily_checkin_events`, `nb_supplement_logs`, `member_lesson_progress` | W (+R for lesson progress) | 1 each |
| `patients`, `patient_intake_questionnaire`, `patient_resource_assignments`, `patient_track_priority`, `library_tracks`, `library_track_lessons`, `member_library_access`, `member_entitlements`, `wearable_daily_labeled`, `wearable_connections` | R | 1–3 each |

**Flagged as legacy/dead:**
- `nb_reports` — pipeline retired by migration 080 per `supabase/functions/generate-daily-report/index.ts` header and `lib/report/use-reports-index.ts:28`. Still read by an orphan hook and by the GDPR export.
- `nb_report_interpretations` — read only by an orphan hook.
- `nb_weekly_themes`, `nb_supplement_logs` — only orphan screens.
- 20 of 41 tables carry the `nb_` prefix, i.e. the app's own legacy plane grafted onto CM OS; the plan/care-plan/library/entitlement surfaces use the unprefixed clinical plane. That split is the single biggest structural inconsistency in the data layer.

## 2. RPC census

| RPC | Args | File:line |
|---|---|---|
| `email_exists` | `{ p_email }` | `lib/supabase/auth.ts:52` |
| `current_member_patient_id` | none | `lib/supabase/auth.ts:99,113,130` (3 call sites — initial, post-register, retry) |
| `member_library_stage` | none | `lib/library/data.ts:210` |
| `member_library_list` | none | `lib/library/data.ts:231` |
| `member_library_get` | `{ p_slug }` | `lib/library/data.ts:402` |
| `confirm_member_adult` | (args at `age-gate.ts:89`) | `lib/legal/age-gate.ts:89` |
| `current_member_is_adult` | none | `lib/legal/age-gate.ts:102` |
| `member_pending_consents` | object | `lib/legal/consents.ts:79` |
| `record_consent` | object | `lib/legal/consents.ts:105` |
| `record_consent_batch` | object | `lib/legal/consents.ts:142` |
| `revoke_consent` | object | `lib/legal/consents.ts:185` |
| `member_mark_messages_read` | none | `lib/messaging/patient-messages.ts:119` |

Server-side RPCs (not client): `canonical_email_hash`, `grant_member_entitlement`, `pii_insert_patient`, `pii_get_patient`, `pii_get_patient_full`, `pii_update_member_fields`, `pii_erase_patient`, `app_daily_stats`, `match_food_items`, `match_food_products`.

## 3. Edge-function calls from the client

`fetch()` to `/functions/v1/`: **none found.** Every call is `supabase.functions.invoke`.

| Function | Payload | File:line |
|---|---|---|
| `analyze-meal` | `{ ...body }` (photo/items/mealLogId) | `lib/meal-log/analyze.ts:124` |
| | `{ mealLogId, reanalyze: true, description?, items? }` | `lib/meal-log/reanalyze.ts:84` |
| `preprocess-meal` | `{ transcript, mealType, locale }` | `lib/stores/meal-preprocess-store.ts:77` |
| `resolve-foods` | `{ items: [{name, grams}] }` | `lib/meal-log/patient-aliases.ts:169`, `lib/meal-log/reprice.ts:208` |
| `transcribe-audio` | `{ audioBase64, mimeType, language }` | `lib/hooks/useWhisperMic.ts:119` |
| `patient-register` | `{ firstName, lastName, email }` | `lib/supabase/auth.ts:119` |
| `q1-complete` | `{ answers, firstName }` | `lib/assessment/submit.ts:50` |
| `member-feedback` | `{ message, appVersion }` | `lib/feedback/send-feedback.ts:27` |
| `evaluate-gates` | `{ today }` — fire-and-forget | `lib/plan/data.ts:462,504` |
| `delete-account` | `{}` | `lib/account/delete-account.ts:8`, `app/(screens)/profile-settings.tsx:88` |
| `message-notify` | `{ message_id }` | `lib/messaging/patient-messages.ts:82` |
| `generate-score-tip` | `{ score_key, locale, label, score, factors[] }` | `lib/health/use-score-tips.ts:59`, `use-raw-score-tip.ts:37`, `use-gut-composite-tips.ts:46` |
| `thryve-connect` | `{ locale? }` | `lib/wearables/thryve-connect.ts:40` |
| `movement-report` / `sleep-report` / `mind-report` | opaque `body` via `fetchAiNarrative(fn, body)` | `lib/report/ai-narrative.ts:17` |
| `nutri-ai-generate` | `{ context }` | `app/(screens)/nutrition-ai.tsx:49` — **DARK** |
| `nutri-plan-chat` | `{ context, messages, userMessage }` | `app/(tabs)/chat.tsx:1180` — **DARK** |
| `chatbot-message` | `{ message, context, history }` | `app/(tabs)/chat.tsx:1216` — **DARK** |
| `chatbot-execute-action` | action payload | `app/(tabs)/chat.tsx:1342` — **DARK** |
| `generate-report` | `{ period, date, tz, locale }` | **COMMENTED OUT** at `lib/report/use-report-content.ts:67` and `lib/report/fire-daily-report.ts:39` — no live client caller |

**Cross-check against `supabase/functions/*`:**
- Called AND in repo: all 17 above (+ `generate-report` only as dead commented code).
- In repo, NOT called by app (server-only): `retry-meal-analysis` (cron, every minute), `daily-checkin-reminder` (cron */30), `send-review-digest` (cron), `thryve-sync` (cron), `thryve-webhook` (Thryve callback), `wearable-ingest` (native iOS HealthKit — **no `lib/healthkit/` exists in this repo**, so no caller here at all), `member-pii`, `clinician-pii`, `pii-backfill`, `resolve-patient` (the wiki claims `use-resources.ts` reaches it; **no invoke found in code** — stale doc), `generate-daily-report` + `generate-periodic-report` (RETIRED).
- Called with no directory: **none.**

## 4. Edge function inventory

`config.toml` contains **no `[functions.*]` blocks** — `verify_jwt` is set at deploy time, not in the repo. Derived from each function's own auth code and header.

| Function | Purpose | Trigger | Auth | AI | Tables | External |
|---|---|---|---|---|---|---|
| `analyze-meal` | Vision identifies foods+grams; `_shared/food-resolver` prices from CIQUAL/SR/OFF. `mealLogId` optional → lifecycle writes | client | resolvePatientId; service-role for writes | Infomaniak gemma-4-31B (vision) + qwen3 | `nb_meal_logs` (+ shared: `nb_patient_protocols`, `nb_protocol_overrides`) | Infomaniak |
| `retry-meal-analysis` | Per-minute worker retrying hung identifications (~53% connection-hang rate) | pg_cron | `--no-verify-jwt`, `x-report-secret` | same as above | `nb_meal_logs` | Infomaniak |
| `preprocess-meal` | Voice transcript → structured items + typed clarifications, strict JSON | client | — | Infomaniak `INFOMANIAK_TEXT_MODEL` ?? Mistral-Small-4-119B | none | Infomaniak |
| `resolve-foods` | HTTP skin over the pricing ladder; embeddings via `Supabase.ai` in-runtime | client | service-role client | none (local `gte-small`) | via resolver: `match_food_items`, `match_food_products` RPCs | none |
| `transcribe-audio` | Speech-to-text, async submit+poll | client | — | Infomaniak `whisper` | none | Infomaniak `/1/ai/{product}` |
| `generate-report` (1139L) | Daily/weekly/monthly `ReportContent`; daily = deterministic assembly + one narrate-only AI call; weekly/monthly fully deterministic; locale part of cache key | **cron 12/13/15 only** | service-role | Infomaniak Mistral-Small (narrate only) | `nb_report_content`, `nb_report_interpretations`, `nb_meal_logs`, `patient_daily_checkins`, `care_plans/_items/_phases`, `habits`, `habit_completions`, `supplement_plans/_logs`, `nb_patient_protocols`, `nb_patient_app_profiles`, `nb_app_consents`, `patients`, `wearable_daily_labeled` | Infomaniak |
| `generate-daily-report` | ⚠ **RETIRED** — writes `nb_reports`; repo copy is *behind* prod | none | — | Infomaniak | `nb_reports`, `nb_app_consents`, `nb_patient_app_profiles`, RPC `app_daily_stats` | — |
| `generate-periodic-report` | ⚠ **RETIRED** — same | none | — | Infomaniak | `nb_reports`, `nb_meal_logs`, `patient_daily_checkins`, … | — |
| `generate-score-tip` | AI tip per score expansion; upserts one row per (patient, score_key, tip_date, locale); rule-based fallback if no `ai_analysis` consent | client | verify_jwt ON, reads `Authorization`, service-role for the write | Infomaniak Mistral-Small | `nb_score_tips`, `nb_app_consents`, `nb_patient_app_profiles`, `patients` | ⚠ repo copy older than prod v18 |
| `q1-complete` | Day 1 Functional Snapshot: **recomputes system loads + red flags server-side**, AI narrative on rails, writes review flag, emails team | client | reads `Authorization` → userClient; service-role for writes | Infomaniak Mistral-Small | `nb_assessment_responses`, `nb_review_flags`, `nb_app_consents`, `patients` | SMTP |
| `sleep-report` / `movement-report` / `mind-report` | Day 4/3/5 narrative only — **scores arrive already computed by the client** | client (via `fetchAiNarrative`) | reads `Authorization`; service-role write | Infomaniak Mistral-Small | `nb_assessment_responses`, `nb_app_consents`, `patients` | — |
| `evaluate-gates` (607L) | Habit-loop gate evaluator; explicit regulatory firewall — completion arithmetic only, never physiology; auto-release or file a clinician task | client fire-and-forget | verified member JWT → `resolvePatientId` | none | `care_plan_item_gates`, `care_plan_items`, `care_plans`, `habits`, `habit_completions`, `habit_offers`, `clinical_tasks`, `app_events` | — |
| `patient-register` (361L) | Create/link patient row, grant `discovery` entitlement, seed library veil, vault PII. ⚠ **byte-identical copy in 3 repos** | client on sign-up | `Authorization` header | none | `patients`, `member_entitlements`, `member_library_access`, `nb_patient_app_profiles`; RPCs `canonical_email_hash`, `grant_member_entitlement`, `pii_insert_patient` | — |
| `delete-account` | GDPR erasure, self-only from JWT uid; wipes storage photos; confirmation email isolated so it can never block erasure | client | `Authorization`; service-role | none | `deletion_log`, `patients`, RPC `pii_erase_patient` | SMTP |
| `member-feedback` | Product feedback → `beta_feedback` on the caller's JWT; tier resolved with service-role; best-effort email | client | `Authorization` | none | `beta_feedback`, `member_entitlements`, `patients` | SMTP |
| `message-notify` | Content-free "a message arrived" notification, both directions; idempotent via `notified_at` | client + cron 16 + clinical | **verify_jwt=false**, hand-checks bearer; cron uses service role | none | `patient_messages`, `patients` | SMTP :465 |
| `daily-checkin-reminder` | Emails opted-in patients +2h after their ideal hour if check-in incomplete | cron 11 | **verify_jwt=false**, fail-closed `x-report-secret`, service-role | none | `patient_notification_preferences`, `patient_daily_checkins`, `patients` | SMTP |
| `send-review-digest` | Nightly de-identified digest of new `nb_review_flags` | cron 3 | `REPORT_SECRET` | none | `nb_review_flags`, `patients` | SMTP; `REVIEW_EMAIL_TO` |
| `thryve-connect` | Start a wearable connection, return session token | client | Bearer → `resolvePatientId` | none | `wearable_accounts` | Thryve `/widget/v6/connection` |
| `thryve-sync` | Drain `wearable_sync_queue`, pull values, store raw + upsert normalized | cron 10 | verify_jwt off, `x-report-secret`, service-role | none | `wearable_sync_queue`, `wearable_accounts`, `wearable_raw_events`, `wearable_daily`, `wearable_epoch` | Thryve |
| `thryve-webhook` | Inbound notification receiver; must ACK <2s | Thryve webhook | static `Authorization` header (`THRYVE_WEBHOOK_AUTH`) | none | `wearable_raw_events`, `wearable_sync_queue`, `wearable_accounts`, `wearable_connections` | Thryve |
| `wearable-ingest` | Device-submitted (Apple HealthKit) samples; `data_source_id=1000001` sentinel, `data_type_id=0` + `data_type_name` | native app | `resolvePatientId`, then service-role (RLS is SELECT-only for patients) | none | `wearable_raw_events`, `wearable_daily`, `wearable_epoch` | — |
| `member-pii` | Self-only vault get/set; identity from JWT only | members/patient dashboards | `Authorization`; service-role | none | `patients`; RPCs `pii_get_patient_full`, `pii_insert_patient`, `pii_update_member_fields` | — |
| `clinician-pii` | Batch vault decryption for the clinical console; role-checked | clinical dashboard | `Authorization` + role check | none | `patients`, `users`, `access_logs`; PII RPCs | — |
| `pii-backfill` | Idempotent plaintext→vault encryption; `dry-run` default | pg_net / manual | `x-backfill-secret` | none | `patients`, `patient_intake_questionnaire`; PII RPCs | — |
| `resolve-patient` | Consent-gated, audited reveal of a flagged patient's identity | ops | `RESOLVE_SECRET` | none | `patients`, `nb_app_consents`, `nb_patient_app_profiles`, `access_logs`, RPC `pii_get_patient` | — |
| `chatbot-message` · `nutri-plan-chat` · `nutri-ai-generate` · `chatbot-execute-action` | **410 refusal stubs.** The first three previously ran `verify_jwt=false` with **no auth** | none (client gated dark) | verify_jwt now ON | none reached | none reached | none |

### `_parked/` contents (real implementations preserved, not deployed)
`chatbot-execute-action` (321L), `chatbot-message` (276L), `library-content` (276L, STUDIO `kb_nodes` path, RETIRED), `nutri-ai-generate` (288L), `nutri-plan-chat` (234L).

### `_shared/` summary
- **`meal-scores.ts` (655L)** — deterministic v2 meal *composition* scoring. v1's `inflammation`/`glycemic`/`digestion` names were renamed because they asserted a physiological measurement from a photo of a plate (`docs/legal/40-code-compliance/score-rename-brief.md`). **Imported directly by the client** (`lib/meal-log/normalize-analysis.ts`, `recompute.ts`) — one implementation, both planes.
- **`food-resolver.ts` (1691L)** — the pricing ladder (learned → curated alias → recipe → hybrid retrieval → OFF branded). Shared by `resolve-foods` and `analyze-meal`.
- **`meal-analysis.ts`** — the identification half, shared verbatim by `analyze-meal` and `retry-meal-analysis`.
- **Pure leaves**: `meal-coverage.ts`, `meal-flags.ts`, `identify-parts.ts`, `stated-items.ts`, `sender-profiles.ts`, `guardrails.ts`.
- **`guardrails.ts` (88L)** — strips clinical/diagnostic/dosing language from AI report text and sets `tripped`.
- **`protocol-foods.ts`** — Deno mirror of `lib/health/protocol-foods.ts`. Header: "🚨 CHANGE ONE, CHANGE BOTH". **Live drift risk.**
- **`email.ts` + `sender-profiles.ts`** — the single mailer; `SMTP_PORT` must be 465.
- **`sovereign-crypto.ts`** — AES-256-GCM, `SOVEREIGN_KEK_HEX`. Must stay byte-identical across patient app / members / clinical repos. `member-pii`, `clinician-pii`, `resolve-patient` and `pii-backfill` each **inline-copy** this.
- **`supabase.ts`** — `resolvePatientId(req)`: `getUser(token)` on the **service** client, because legacy JWT anon keys are disabled on this project (an anon-keyed client 401s).
- **`thryve.ts`** — dual Basic-Auth.
- **`patient-run-context.ts`, `adapters.ts`, `context-renderer.ts`, `memory/`, `prompts/`, `protocol-packs/`** — the chat/memory stack; reachable only from the parked functions, i.e. **dead in production**.

## 5. Storage & Realtime

**Storage — one bucket, `meal-images`:**
- `lib/meal-log/upload-photo.ts:44` — `.upload(path, bytes, {contentType:'image/jpeg', upsert:false})`
- `lib/meal-log/photo-url.ts:44` — `.createSignedUrl(path, SIGNED_TTL_SECONDS)`
- `lib/meal-log/photo-url.ts:59` — `.remove([path])`
- Also wiped server-side by `delete-account`.

**Realtime — two channels:**
- `lib/hooks/usePlan.ts:402-404` — `plan-habits-${patientId}`, `postgres_changes` INSERT + UPDATE on `public.habits` filtered `patient_id=eq.…`
- `lib/hooks/useMealAnalysisStatus.ts:336-339` — `meal-analysis-${mealLogId}`, `postgres_changes` UPDATE on `public.nb_meal_logs` filtered `id=eq.…`

## 6. Environment variables

| Var | Where | Default / fallback |
|---|---|---|
| `EXPO_PUBLIC_SUPABASE_URL` | `lib/supabase/client.ts:14` | ⚠ **hardcoded** `https://ndojytvvlvlbgtodujkf.supabase.co` |
| `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY` / `EXPO_PUBLIC_SUPABASE_ANON_KEY` | `client.ts:16-18` | ⚠ **hardcoded** `sb_publishable_LVGwAdT4rrdto0hTMHUhrw_ikue9GGM` |
| `EXPO_PUBLIC_ENABLE_AI_CHAT` | `lib/config/ai-chat-flag.ts:24` | OFF unless exactly `'true'` |
| `EXPO_PUBLIC_ENABLE_FR` | `lib/i18n/feature-flag.ts:21` | ON unless `'false'` |
| `EXPO_PUBLIC_ENABLE_CONSENT_GATE` | `lib/legal/consents.ts:43` | ON unless `'false'` |
| `EXPO_PUBLIC_CONSENT_INCLUDE_DRAFTS` | `lib/legal/consents.ts:44` | OFF |
| `EXPO_PUBLIC_ENABLE_ONBOARDING_GATE` | `app/_layout.tsx:57` | ON unless `'false'` |
| `EXPO_PUBLIC_ONBOARDING_TARGET` | `app/_layout.tsx:65` | `'app'` unless `'members'` |
| `EXPO_PUBLIC_DISABLE_ACCESS_GATE` | `lib/access/useAppAccess.ts:24` | kill switch, OFF |
| `EXPO_PUBLIC_ENABLE_COVERAGE_NUDGE` | `lib/meal-log/coverage-flag.ts:13` | OFF |
| `EXPO_PUBLIC_BOOKING_URL` | `lib/config/booking.ts:5` | Calendly link |
| `EXPO_PUBLIC_MEMBERS_ONBOARDING_URL` | `lib/components/account/OnboardingRequiredGate.tsx:22` | prod members route |
| `EXPO_PUBLIC_MEMBERS_REQUEST_URL` | `lib/components/account/AccessWindowGate.tsx:18` | prod URL |

Server-side (Deno): `INFOMANIAK_AI_API_KEY`, `INFOMANIAK_PRODUCT_ID`/`INFOMANIAK_AI_PRODUCT_ID` (default `108797`), `REPORT_MODEL`, `INFOMANIAK_TEXT_MODEL`, `SOVEREIGN_CHAT_MODEL`, `SOVEREIGN_VISION_MODEL`, `INFOMANIAK_WHISPER_MODEL`/`SOVEREIGN_TRANSCRIPTION_MODEL`, `REPORT_SECRET`, `RESOLVE_SECRET`, `REVIEW_CONSENT_TYPE`, `REVIEW_EMAIL_TO`, `SOVEREIGN_KEK_HEX`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `APP_URL`, `CLINICAL_URL`, `SMTP_*`, `THRYVE_GLOBAL_USERNAME/PASSWORD`, `THRYVE_APP_AUTH_ID/SECRET`, `THRYVE_WEBHOOK_AUTH`.

## 7. Client-side business logic inventory

Legend: **P** = pure (no I/O). "Server equivalent" = whether an edge function recomputes the same thing.

### `lib/health/` — the score stack (health-relevant, all client-side)
| Module | Computes | P | Inputs | Server equivalent |
|---|---|---|---|---|
| `score-core.ts` | The scoring contract: available-case weighted mean, missing factors renormalize | P | — | none |
| `functional-score.ts` | ⚠ **"The crown composite"** — weighted mean of Vitality/Metabolic/Nutrition + `ConfidenceBasis` | P | derived | **none** |
| `vitality-score.ts` | energy·mood·sleep·stress (+ dormant wearable recovery) | P | `patient_daily_checkins` | none |
| `metabolic-score.ts` | Digestion = 65% feltGut + 35% meal I/G/D; inflammation/glycemic = meal means | P | `nb_meal_logs`, checkins | none |
| `nutrition-score.ts` | meal quality + micro coverage + macro proximity + timing | P | `nb_meal_logs` | none |
| `recovery-score.ts` | Dual-source: wearable HRV/sleep/stress else felt bounce-back/soreness/load | P | `wearable_daily_labeled`, checkins | none |
| `compound-scores.ts` | Vitality/Metabolism derived because "the backend has no first-class columns" | P | per-signal scores | **none — explicitly acknowledged as a client-only derivation** |
| `longevity.ts` | VO2max-driven north star, locked until a wearable supplies input | P | wearables | none |
| `gut-composites.ts` | 3 gut composites + interim rule-based observation | P | checkins, `nb_meal_reactions` | tip text only via `generate-score-tip` |
| `pillars.ts` | signal→pillar mapping, clinical node labels | P | — | none |
| `protocol-week.ts` | wins-first weekly protocol stats from `protocol_flags` | P | `nb_meal_logs` | `generate-report` has its own `buildProtocolWeekBlock` (parallel impl) |
| `protocol-foods.ts` | severity-tiered elimination term matching | P | — | ⚠ **mirrored** in `_shared/protocol-foods.ts` (untested copy) |
| `score-tip.ts` | rule-based tip | P | — | ✅ mirrored inside `generate-score-tip` as the AI-off fallback |
| `trends-derive.ts`, `score-series.ts`, `raw-metric-series.ts`, `overall-trend.ts`, `measured-vs-felt.ts`, `meal-timing.ts`, `meal-window.ts`, `food-felt.ts`, `gut-signals.ts`, `gut-breakdown.ts`, `pillar-detail.ts` | series/derivation helpers | P | mixed | none |
| `protocol-load.ts`, `use-*-tips.ts`, `use-gut-scores.ts`, `use-scores-overview.ts` | I/O hooks | not P | `nb_patient_protocols`, `nb_score_tips` | — |

### `lib/scoring/`
`composite.ts` (`calculateDailyScore` — "V1: arbitrary scoring, will be refined per condition"), `metabolism.ts` (7 weighted inputs), `score-history.ts` (7-day per-score average + trend from meals), `score-personalization.ts` (187L). All pure, no server equivalent.

### `lib/checkin/`
- `functional-engine.ts`, `gut-engine.ts` — pure scoring + conditional pill selection.
- `gut-score.ts` — "the deterministic formula that makes the gut check-in move the Digestion score"; gut-intelligence markers **override** the functional slider when present. Pure, tested, **no server mirror**.
- ⚠ **`red-flags.ts`** — `blood_in_stool`, `black_stool`, `persistent_vomiting`, `fever`, `unintentional_weight_loss`, `severe_worsening_pain`. **Client-only; no edge function reads or re-derives these.**
- `marker-trends.ts` (198L) — per-marker 0–100 daily series; stress rendered as *calmness*.
- `felt-recovery.ts` — capture only, canonical stored scale 0–10.
- `should-prompt.ts`, `day-strip.ts`, `moments.ts`, `moment-sections.ts`, `pill-catalog.ts`, `pillar-colors.ts`, `score-bands.ts`, `custom-pills.ts`, `meal-reaction-nudge.ts`, `wearable-context.ts` — pure UI/derivation.
- `*-persistence.ts`, `load-today.ts`, `reminder-prefs.ts` — I/O onto `patient_daily_checkins` / `nb_checkin_events` / `patient_checkin_moments`.

### `lib/assessment/`
`scoring.ts` (probe→0–100 system load), `red-flags.ts`, `narrative.ts`. ✅ **This is the one place with a real server mirror** — `q1-complete` recomputes loads and flags "SERVER-SIDE (can't be bypassed)". `submit.ts` is best-effort I/O.

### `lib/recovery/day4.ts`, `lib/movement/day3.ts`, `lib/mind/day5.ts`
Each: structured pickers → 6 deterministic 0–100 scores, pure, vitest-tested. ⚠ **Computed on the client and POSTed to `sleep-report`/`movement-report`/`mind-report`, which only narrate.**

### `lib/access/`
`entitlement.ts` (136L) — tier windows (discovery = 3 days from `starts_at`, an **app rule** not a DB rule), reads `member_entitlements` on the member's own session. `countdown.ts` — pure copy. `useAppAccess.ts` — the gate + `EXPO_PUBLIC_DISABLE_ACCESS_GATE` kill switch. **No server enforcement of the app window.**

### `lib/program/`
`gating.ts` — pure 5-day program gating. `clock.ts` — ⚠ in `__DEV__`, "now" is **+2 days**.

### `lib/plan/` (habit loop)
`gates.ts` (103L) — pure gate evaluation, "the REGULATORY FIREWALL". ✅ **Server equivalent: `evaluate-gates`.** `streaks.ts`, `promotion.ts`, `day-state.ts` (146L), `day-math.ts`, `derive.ts`, `home-actions.ts`, `offers.ts`, `plan-headline.ts`, `self-habits.ts`, `slots.ts`, `today.ts`, `week-streak.ts`, `resources.ts`. `data.ts` (664L) is all the I/O.

### `lib/report/`
Six modules explicitly marked **"INLINE-COPIED into generate-report — keep in sync"**: `daily-assembler.ts`, `plan-block.ts`, `protocol-block.ts`, `interpretation.ts`, `rrule-lite.ts`, `wearable-report-block.ts`. Plus `patient-words-block.ts`, `report-calendar.ts`, `report-content.ts`, `stale-check.ts`, `pdf.ts`, `report-export.ts`. **Largest sync-drift surface in the codebase.**

### `lib/nutrition/`, `lib/meal-reaction/`, `lib/patterns/`, `lib/care-plan/`
- `canonical-targets.ts` — macro targets; DB trigger `compute_macro_targets()` on `nb_patient_app_profiles` is the authority, with an **identical client formula** in `lib/utils/tdee.ts` as fallback. ✅ server-authoritative.
- ⚠ `meal-reaction/question-engine.ts` (222L) — **score-driven** selection of post-meal follow-ups and mapping to the `nb_meal_reactions` write. Pure, client-only, **no server mirror**.
- `patterns/pattern-text.ts` — renders the server-side `compute_user_patterns` engine's rows as sentences. ✅ engine server-side.
- `care-plan/use-care-plan.ts` — I/O only.

### Health-relevant calculations done on the client — flag list
1. **Functional Score** (the crown composite) and all four pillar scores — `lib/health/*`, no server equivalent.
2. **Gut score / digestion override** — `lib/checkin/gut-score.ts`.
3. **Check-in red flags** — `lib/checkin/red-flags.ts`, no server re-derivation.
4. **Day 3/4/5 assessment scores** — computed client-side and *sent to* the edge function.
5. **Meal reaction scoring + which symptom questions to ask** — `lib/meal-reaction/question-engine.ts`.
6. **Streaks and habit-gate arithmetic** — mirrored in `evaluate-gates`.
7. **Entitlement/trial window arithmetic** — `lib/access/entitlement.ts`, app-side rule only.
8. **Recovery/longevity from wearables** — `lib/health/recovery-score.ts`, `longevity.ts`.

Meal composition scoring is the counter-example done right: `_shared/meal-scores.ts` is imported by both planes.

## 8. Notifications & wearables

**Notifications — near-absent.**
- `expo-notifications@^55` is a dependency; **exactly one usage**: `lib/checkin/meal-reaction-nudge.ts` schedules a local "How did your {mealType} sit?" reminder at +9000s (2.5h). Native only.
- **No `getExpoPushToken`, no push token anywhere.** No device-token table.
- `daily-checkin-reminder` sends **email** via SMTP, driven by `patient_notification_preferences` (`daily_checkin_reminder_enabled`, `daily_checkin_time`, `email_reminder_enabled`, `timezone`) which the app writes at `lib/checkin/reminder-prefs.ts:61`.
- `message-notify` sends **email** (content-free, link-only), fired from `lib/messaging/patient-messages.ts:82` and swept every 15 min by cron.

**Wearables.**
- Client: `lib/wearables/thryve-connect.ts`, `use-wearable-history.ts` (reads the `wearable_daily_labeled` view), `wearable-daily.ts`, `metrics.ts` (`AGG_RULE`: MAX for Steps, ActiveBurnedCalories, CoveredDistance; MEDIAN for HeartRateResting, Rmssd, RmssdSleep, AverageStress, RespirationRate, MetabolicEquivalentMax5Min), `catalog.ts`, `logos.ts`.
- `app/(screens)/profile-wearables.tsx` reads `wearable_connections`.
- Server: `thryve-connect` → `wearable_accounts`; `thryve-webhook`; `thryve-sync`; `wearable-ingest` → for Apple HealthKit with `data_source_id=1000001`, `data_type_id=0`, `data_type_name` in (`steps`, `heart_rate`, `hrv_sdnn`, `sleep_analysis`, `workout`).
- ⚠ `wearable-ingest` references `lib/healthkit/` — **does not exist in this repo.** No caller.

## 9. `lib/config/*` and `lib/app-version.ts`

- `lib/config/ai-chat-flag.ts` — `AI_CHAT_ENABLED`, **dark by default**. Locked by `lib/config/__tests__/ai-chat-stays-dark.test.ts`.
- `lib/config/booking.ts` — `BOOKING_URL`, Calendly fallback.
- `lib/deploy/` — contains only `__tests__/parked-endpoints-stay-secured.test.ts`.
- `lib/app-version.ts` — `APP_VERSION = '1.0.0'`, hardcoded. ⚠ Stamped onto every consent record as `app_version` (audit trail) and sent to `member-feedback`. Must be bumped in lockstep with `app.json`; nothing enforces that.
- **No version gating / force-upgrade mechanism exists.**

## Cross-cutting risks

1. **Six `lib/report/*` modules are inline-copied into `generate-report`**, plus `protocol-foods.ts` mirrored into `_shared/`, plus three narrative contracts. All maintained by comment convention.
2. **`generate-score-tip` in the repo is older than production v18** — deploying the checkout silently reverts. Documented at `docs/wiki/pages/architecture/live-surfaces.md`.
3. **`generate-daily-report` / `generate-periodic-report` are behind production too** and RETIRED but still `ACTIVE` in the console.
4. **`patient-register` is byte-duplicated across three repos**.
5. **Four PII functions inline-copy `sovereign-crypto.ts`**.
6. **`nb_*` vs unprefixed tables** is an unresolved two-plane data model; the GDPR export (`lib/account/user-data.ts`) covers only the 10 `nb_*` + `patient_daily_checkins` tables — not habits, care plans, messages, library progress, entitlements, wearables, moments, or notification preferences.
