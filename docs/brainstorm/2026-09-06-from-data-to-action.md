# From data to action — the next shape of the FunctionAlps app

Brainstorm v0 · 2026-09-06 · owner: Thomas · scope: iOS (primary client) + CM OS (backend) + CLINICAL (clinician side). STUDIO is out of scope for this facet. MEMBERS only renders what iOS and CM OS produce.

This is a brainstorm and a cut into work packages, not a spec. Every "exists" claim below was checked against the repos on 2026-09-06; every "new" item is a proposal. Decisions Thomas must take are collected in §8 with a default each, so work can start under the defaults.

---

## 0. TL;DR

- **The loop we are building:** *I ate this* (photo) → *this is how I reacted 2 h later* (gut, energy, focus) → *this is what my body did at the same moment* (Apple Watch / other wearables) → *this is how I slept, how stressed I was, what habits I did* → **a factual day record for the member** → **a periodic review for the clinician** (facts + later AI hypotheses) → **actions** (habits, a message, a consultation) → back into the app.
- **The one rule that makes it safe:** *facts by code, hypotheses by AI, decisions by the clinician.* The member's daily record is deterministic (no model touches it), so it needs no approval and cannot hallucinate. Anything interpretive is produced for the clinician only, goes through `ai_outputs.approval_status`, and reaches the member only as a clinician-decided action.
- **The spine is one new artefact, the Day Record:** a per-patient, per-day JSON of every event on the member's local timeline with the windows already joined (meal → +2 h reaction → wearable window) and each metric next to the member's own 14-day baseline. iOS, MEMBERS and CLINICAL render it; the clinician review aggregates it; the RAG (later) is trained on its anonymised shape.
- **Less new infrastructure than it looks:** intraday wearable rows (`wearable_epoch`), the +2.5 h reaction prompt (iOS local notification), the habit-loop approval path, the sovereign AI client and the report engine all exist. What is genuinely new: intraday HealthKit sync, four self-assessment additions (focus, skin, stressors, reaction energy/focus), the Day Record builder, the member timeline screen, the clinician review surface, and — later — the hypothesis engine with its RAG.
- **Nine work packages** (§7), three of them iOS-only and startable now (WP1 intraday HealthKit, WP2 self-assessment v2, WP3 habits), one schema package (WP0) that unblocks the rest, and the intelligence layer last.

---

## 1. What we are building

### 1.1 The value layer
Today the app collects. The next shape *connects*: it puts what the member ate, how they reacted, what the wearable measured, how they slept, how stressed they were and which habits they did **on one timeline**, and turns that into two documents:

| Document | Reader | Content | Interpretation? | Cadence |
|---|---|---|---|---|
| **Day Record** | member (and clinician) | every fact of the day, juxtaposed, with a small timeline graph | **none** — only the member's own data and their own baseline | daily, live during the day, closed the next morning |
| **Periodic Review** | clinician | the days aggregated, patterns as facts, AI hypotheses (later), an action composer | yes — for the clinician only | 3 / 7 / 14 days per patient |

The member never receives an interpretation the clinician has not decided on. What the member receives after a review is an **action**: a habit ("try a 10-minute walk after lunch this week"), a message ("you flagged stress on 4 of 7 days — shall we talk about it?"), a consultation proposal, or a protocol adjustment. Each of those already has a gate in CM OS.

### 1.2 The three-layer rule
| Layer | Produced by | Reaches the member? | Gate |
|---|---|---|---|
| **Facts** | deterministic code (Day Record builder) | yes, directly | RLS + `visibility_class` discipline only — no approval needed because nothing is generated |
| **Hypotheses** | sovereign AI (Infomaniak) over facts + RAG | **never directly** | `ai_outputs.approval_status` — clinician reads, accepts, rejects, rewrites |
| **Decisions / actions** | the clinician | yes, as habits / messages / consults | existing habit-loop push, `patient_messages`, appointments |

This rule is what lets the factual report ship without a review queue and what keeps the AI on the clinician's desk.

### 1.3 Why "own baseline", not norms
Comparing a value to the member's own rolling median ("HRV 38 ms — your 14-day median is 46 ms") is arithmetic on their data and stays factual. Comparing it to a population norm ("low HRV") is interpretation. The Day Record does the first and never the second; the clinician and the hypothesis engine do the second.

---

## 2. What already exists (checked 2026-09-06)

### 2.1 iOS (`FunctionAlps-IOS`)
| Piece | State | Where |
|---|---|---|
| HealthKit read: steps, distance, active/basal kcal, exercise min, resting HR, HR, HRV SDNN, respiratory rate, SpO₂, VO₂max, weight — **one value per local day**; sleep nights assembled into stages; workouts as timed rows | ✅ built | `Core/Health/HealthKitReader.swift`, `WearableCatalog.swift` (Thryve-style metric ids), `Services/WearableService.swift` |
| Background delivery (observer queries, hourly for steps) + 30-day backfill + 3-day resync | ✅ | `WearableService` |
| Post-meal "How do you feel after that meal?" local notification **2.5 h** after each meal without a reaction | ✅ | `Core/Notifications/NotificationPlanner.swift` (`reactionDelay`) |
| Check-in moments morning / midday / evening: sleep inputs, `energy_body`, `energy_mind`, `energy_stability`, mood, calmness, pills catalog | ✅ (build 7) | `Features/Checkin/*`, `CheckinEngine` |
| Meals: photo/text/voice capture → `analyze-meal` → confirm; meal detail shows the reaction read from `nb_meal_reactions` | ✅ (build 12) — **rating a reaction is not yet native** | `Features/Food/*`, `Services/MealService.swift` |
| Trends from the `member-scores` edge function | ✅ (build 10) | `Features/Trends` |
| Habits | ⬜ none native (Expo Habit Loop v2 exists behind a flag that is OFF) | — |
| Push notifications | ⬜ none (no APNs anywhere; local notifications only) | — |
| Direct vendors (Oura, WHOOP, Polar, Garmin, Withings, Suunto, Google) via OAuth web session; Thryve as aggregator | ✅ client + server contract | `WearableService.connectVendor`, `wearable_vendors` |

### 2.2 CM OS (Supabase, shared; functions live in `FunctionAlps-APP/supabase/`)
| Piece | State | Notes |
|---|---|---|
| `wearable-ingest` → `wearable_raw_events`, `wearable_daily` (upsert on patient·source·day·type), **`wearable_epoch`** (upsert on patient·source·type·`start_ts`) | ✅ live | **Intraday rows already have a home.** `wearable_daily_labeled` is a view joining the `wearable_data_types` catalog |
| `nb_meal_logs` (photos, `ai_identified_foods`, `confirmed_foods`, macros, scores, `protocol_flags`) | ✅ | vision model: Infomaniak `Mistral-Small-4-119B` |
| `nb_meal_reactions`: `overall, bloating, fullness, gas_burden, responses (jsonb {questionKey: value}), reaction_flags[] (derived tags e.g. bloating, energy_crash, headache), notes, reacted_at` | ✅ | energy exists only as a derived `energy_crash` flag; no graded energy / focus marker |
| `patient_checkin_moments` (UNIQUE patient·date·slot): energy body/mind/stability/overall, mood, stress(=calmness), sleep_*, **`pills` jsonb `{group: [option]}`**, note | ✅ | pills are extensible without DDL |
| `patient_daily_checkins`: gut (Bristol `stool_type`, `stool_quality`, bloating, comfort…), red flags, legacy 1–10 markers | ✅ | |
| `habits`, `habit_completions` (`completed_at` timestamptz, migration 010 — already a timestamp, so completions can sit on the timeline), `habit_offers`, `habit_bank`, `care_plan_item_gates`; `evaluate-gates` (completion arithmetic only) | ✅ | app UI flag OFF |
| `generate-report` → `nb_report_content` (daily / weekly / monthly), deterministic facts narrated by Infomaniak Mistral (rephrase-only), interpretation+actions only when the AI review is approved; crons 12/13/15 | ✅ live | the two older report functions are RETIRED (still show ACTIVE in the console — do not touch) |
| `nb_user_patterns` (kind `pattern` / `trigger_food`, effect, n_obs, consistency, tier hint/confirmed) | ✅ | service-role, computed offline |
| `daily-checkin-reminder` — **email** only | ✅ | no push |
| skin, focus, cycle / menstrual fields | ❌ none anywhere | |

### 2.3 CLINICAL (`FunctionAlps-CLINICAL/clinical-dashboard`)
| Piece | State | Notes |
|---|---|---|
| Patient-facing gates: `ai_outputs.approval_status` + `visibility_class`; `resources` + `patient_resource_assignments`; care plan items `draft → approved → pushed_to_app` creating `habits` rows (`lib/habit-loop/actions.ts`) | ✅ | SOP `06-patient-facing-output.md` |
| Sovereign client `lib/sovereign/client.ts`: tiers `clinical` / `classify` / `non_sensitive`; models qwen3 (Qwen3.5-122B), mistral, whisper, **embedding `bge_multilingual_gemma2` (1024-d) configured but no vector index or retrieval code** | ✅ / ⬜ | RAG = new |
| Routes reading the app plane: `patients/[id]/{checkins, app-activity, timeline, functional-score, symptoms, nutrition/review}` | ✅ | the review surface can grow from `timeline` |
| Crons in `vercel.json` incl. `patient-summaries` 03:00 (unspecified in the wiki) and `care-plan-flags` 04:00 | ✅ | |
| Periodic clinician review / digest | ❌ none | |
| `clinical_tasks` (written by gates and crons — an output queue, not an assignment mechanism) | ✅ | reuse as the review queue |

---

## 3. The spine: the Day Record

### 3.1 Definition
One JSON document per (patient, local day), built server-side by a deterministic function, upserted idempotently, versioned. It is the **only** thing the three clients render for "the day", and the unit the review and the RAG consume.

```jsonc
{
  "patient_id": "…", "day": "2026-09-05", "tz": "Europe/Zurich", "version": 1, "built_at": "…",
  "sleep": { "night_end": "06:52", "asleep_min": 412, "deep_min": 61, "rem_min": 88, "latency_min": 14,
             "interruptions": 2, "efficiency_pct": 89, "source": "apple_health",
             "baseline_14d": { "asleep_min": 438, "deep_min": 70 } },
  "moments": {
    "morning": { "at": "07:42", "energy_body": 62, "sleep_refreshed": 3, "mood": 70, "calmness": 55,
                 "skin": { "score": 3, "pills": ["redness"] } },
    "midday":  { "at": "13:05", "energy_body": 48, "focus": 35, "mood": 60, "stressors": ["work"] },
    "evening": { "at": "21:10", "focus": 40, "calmness": 35, "stressors": ["work"], "note": "big meeting" }
  },
  "meals": [
    { "id": "…", "at": "12:31", "type": "lunch", "photo": "storage/path", "foods": ["…"], "macros": { "kcal": 640, "protein_g": 32 },
      "scores": { "inflammation": 3, "glycemic": 2, "digestion": 4 }, "protocol_flags": [],
      "reaction": { "at": "14:35", "overall": 3, "bloating": 4, "fullness": 3, "gas": 2, "energy": 2, "focus": 2, "flags": ["bloating"] },
      "window": { "hr_pre30_avg": 68, "hr_post120_avg": 79, "hr_post120_max": 91, "steps_post120": 140,
                  "glucose_post120": null, "workout_in_window": false,
                  "habits_in_window": [] } }
  ],
  "gut": { "stool_type": 4, "comfort": 3, "flags": [] },
  "movement": { "steps": 6120, "active_kcal": 310, "exercise_min": 18, "daylight_min": 25, "workouts": [ { "at": "18:20", "kind": "walking", "min": 32 } ] },
  "habits": [ { "id": "…", "title": "Walk 10 min after lunch", "done_at": null, "origin": "clinician" } ],
  "vs_self": [ { "metric": "hrv_sdnn", "value": 38, "median_14d": 46, "delta_pct": -17 } ],
  "completeness": { "meals": 3, "reactions": 2, "moments": 3, "wearable": true, "gut": true }
}
```

Rules:
- Every value carries its source (`apple_health`, `oura`, `self_report`, `meal_photo`) — data-provenance rule, AI output is never a source.
- Times are the member's local clock; `tz` is stored on the record. The builder reads the timezone from `patient_notification_preferences.timezone`, falling back to the `timezone_offset` the phone stamps on wearable rows.
- Windows: **pre** = [meal − 30 min, meal), **post** = [meal, meal + 120 min] in 15-minute buckets from `wearable_epoch`. Any habit completion, workout or self-assessment inside a window is listed in it — that is the "at the same moment on the timeline" join.
- Baselines: 14-day rolling median of the member's own values, per metric, computed in the builder; both value and baseline are stored so the rendering is arithmetic-free.
- The record for *today* is rebuilt on demand (live view); the record for *yesterday* is closed at 04:00 local when sleep has landed, and flagged `closed: true`.

### 3.2 Where it lives
New table **`nb_day_records`** (`patient_id`, `day`, `version`, `facts jsonb`, `completeness jsonb`, `closed boolean`, `built_at`; UNIQUE patient·day), member self-select under RLS (same pattern as `nb_report_content`). Not `nb_report_content`: that table holds narrated report artefacts with their own `content` shape and an AI `model` column; the Day Record is a materialised fact view with a different lifecycle. Later, `generate-report`'s *daily* period should read the Day Record instead of recomputing facts (consolidation, not v1).

### 3.3 Who builds it
Edge function **`build-day-record`** on CM OS (Deno, next to `generate-report` and `member-scores`): service role inside, member JWT verified for on-demand calls, `{patient_id, day}` in, one upsert out. Triggers: nightly pg_cron for every patient with activity (yesterday, close); on-demand from iOS when the timeline screen opens or a moment/reaction is saved; from CLINICAL before a review is assembled. Pure function of the tables; no model call, ever.

---

## 4. Inputs

### 4.1 Apple Health — from daily to intraday
Today the phone reduces HealthKit to one row per day. The meal window needs the shape of the signal *around* a meal, so the sync gains an intraday lane, posted as `epoch` rows (the ingest contract already accepts them):

| Type (HealthKit) | Granularity to post | Why |
|---|---|---|
| `heartRate` | 5-min buckets (avg, min, max via `HKStatisticsCollectionQuery` with a 5-min interval — same code path as the daily query) | the post-meal curve, the stress spike during the meeting |
| `heartRateVariabilitySDNN` | raw samples (the Watch takes them sporadically) | HRV is the recovery / stress signal the clinician reads most |
| `stepCount`, `activeEnergyBurned` | 15-min buckets | "did you walk after lunch?" as a number |
| `bloodGlucose` | raw samples | CGM users (Dexcom writes to Health with a delay; LibreLink depends on region) — the single most direct meal-reaction signal when present |
| `timeInDaylight` (iOS 17, Watch S6+) | daily | light exposure vs sleep and mood |
| `mindfulSession` | epoch | a habit the member may already track elsewhere |
| `menstrualFlow` | daily category | cycle phase — hypotheses depend on sex and phase (§6) |
| `appleSleepingWristTemperature` | nightly | relative temperature deviation, a Watch S8+ signal for illness / cycle |

Mechanics: `HKAnchoredObjectQuery` per intraday type with the anchor persisted (not a secret; app support directory), so each background wake-up sends only what is new; batches capped at ~500 rows; observer + background delivery already armed; a `BGProcessingTask` does the 30-day intraday backfill once after connect. Volume ≈ 300–700 rows per patient per day — trivial for `wearable_epoch` with its existing upsert key. New `wearable_data_types` catalog entries for the intraday HR buckets, glucose, daylight, mindful minutes, menstrual flow, wrist temperature.

Retention is a decision (§8, D4). HealthKit itself keeps the member's history, so a lean retention on CM OS loses nothing that cannot be re-synced.

### 4.2 Meals and the +2 h reaction
Exists: photo → sovereign vision → confirm; the local notification 2.5 h later; `nb_meal_reactions`. Changes:
- Add **`energy`** and **`focus`** (same 0–100 marker convention as the moments, higher = better) to the reaction. The post-prandial dip is the effect people *feel* most and the one Thomas wants the app to be about. Explicit columns, not buried in `responses`, so the Day Record and the review can query them (D6).
- Native reaction screen in iOS (today the meal detail only *reads* a reaction): four dials (overall, bloating, energy, focus) + fullness/gas pills + optional note — ten seconds, as the notification promises. The "Felt fine" notification action should write a neutral reaction in one tap.
- Prompt delay: 2 h (Thomas) vs 2.5 h (current constant). Peak postprandial glucose and the energy dip sit at 60–120 min; 2 h is defensible and matches the copy (D2).
- The reaction and the wearable window are joined in the Day Record, never on the phone.

### 4.3 Self-assessment v2
The four axes Thomas named — **body energy, focus, gut, skin** — plus what already exists, mapped onto the three moments and the reaction. Scalar markers stay 0–100 (higher = better, as the whole plane does); pills stay in the existing `pills` jsonb groups, so most of this is catalog + UI, not DDL.

| Dimension | Where asked | Exists? | Storage |
|---|---|---|---|
| Sleep (duration, latency, wakings, refreshed) | morning | ✅ | `patient_checkin_moments.sleep_*` |
| **Body energy** | morning · midday · evening · reaction | ✅ (`energy_body`) | keep |
| **Focus** (replaces "mind energy" in the UI) | midday · evening · reaction | ❌ | new `focus_score` on moments; `energy_mind` kept for history (D5) |
| Mood | all moments | ✅ | keep |
| Stress / calmness | all moments | ✅ | keep |
| **Stressor** ("why?") | midday · evening | ❌ | new pills group `stressors`: work · family · health · sleep · money · social · none · other+text — this is the "oh, because I had this big meeting" hook |
| **Gut** (comfort, bloating, Bristol, transit) | daily gut check-in · reaction | ✅ | keep |
| **Skin** | morning (best light, before makeup) | ❌ | new `skin_score` on the morning moment + pills group `skin`: breakout · redness · dryness · itch · eczema flare · dull · glow · none |
| Appetite / cravings | midday · evening | ❌ | pills group `cravings`: sugar · salt · none · no appetite |
| Alcohol · caffeine after 14:00 · screens in bed | evening | ❌ | pills group `evening`: three toggles — factual confounders for sleep |
| Cycle phase (self-report fallback when Health has no flow data) | morning, when relevant | ❌ | pills group `cycle` or HealthKit `menstrualFlow` (D7) |
| Pain / headache / joints | red flags exist | ✅ partial | keep in gut / red-flag flow |

Design constraints: each moment stays under 30 seconds; a dimension the member skipped is `null`, never 0; one new dimension per moment at most so the existing engine (`CheckinEngine`, a line-for-line port) is extended, not rewritten. Libido and body-image questions are deliberately out until Thomas decides — sensitive and low signal for the loop.

### 4.4 Skin — a diary, not a diagnosis
- v1 = the morning score + pills above. That already gives the clinician "skin 2/5 with redness on the three mornings after the dairy-heavy dinners" as a fact on the timeline.
- Optional **skin photo**: front camera, same framing guide, same light cue, stored in a **private** bucket keyed like `meal-images`, shown to the member (side-by-side over weeks) and to the clinician. **No AI on faces in v1.** A face photo is biometric data under nFADP/GDPR: separate consent key, explicit retention, never leaves CM OS, and any later vision scoring (redness, lesion count) is a T2 sovereign call with its own notice (`ai_analysis` exists in `consent_definitions`). D8.

### 4.5 Habits — the action channel
The habit loop exists end to end (bank → care plan item → approve → push → `habits`; gates by completion arithmetic). What the timeline needs:
- **Completions already carry `completed_at`**; add an optional **`context_meal_id`**, so "walked after lunch" lands inside that meal's window.
- Native iOS habits: today's list with one-tap done, an "after this meal I…" quick action on the meal detail (walk · rest · nothing), the offers inbox (accept / not now), streaks **server-side** (they were client-side in Expo — a §"server-side moves" item).
- `origin` on each habit: `clinician` · `self` · `ai_suggested` (the last one exists only after a clinician approved it — the three-layer rule).
- The evening moment shows the day's habits as ticks, so the record is complete without a fourth screen.

### 4.6 Other wearables and the CGM
On iOS almost every device writes to Apple Health (Oura, Garmin, Withings, Polar, WHOOP with limits, Dexcom, some Libre apps). So **HealthKit is the aggregator first**; the direct vendor OAuth path that already exists is for members without a Watch-class HealthKit source and for vendor-only metrics (Oura readiness, WHOOP strain). Rule: one metric, one source per day — the `wearable_data_types` layer/priority decides, and the Day Record states which source won. CGM: through HealthKit when the vendor app writes there; vendor API later if a member's setup does not.

---

## 5. Outputs

### 5.1 The member's Day Record screen (iOS first, MEMBERS second)
One screen, one graph, no advice.

**The graph** — a 24-hour strip, lanes top to bottom: last night as a shaded sleep band with stages · heart rate as a 5-minute line · steps as 15-minute bars · meal markers (photo thumbnails at `logged_at`) with the reaction badge at +2 h coloured on the existing 5-level scale (`#C0453A → #4A8A5C`) · the three moments as small dials · habit ticks · workouts as bands. Swift Charts on iOS; the hand-rolled SVG in MEMBERS; CLINICAL's own chart layer.

**Below the graph** — per-meal cards in words the member used: "12:31 lunch → 14:35 bloating 4/5, energy 2/5 · heart rate 79 avg in the 2 h after (68 before) · 140 steps in the 2 h". Then sleep vs your 14-day median, movement, the moments, habits done / not done, and a completeness footer ("2 of 3 meals rated").

**Delivery** — today's record is live (rebuilt on open and after each save). Yesterday's closed record is announced by a **local** notification at the member's morning time (no APNs exists; Phase G adds push). Weekly and monthly narrated reports stay what they are (`generate-report`).

**Gate** — none beyond RLS, because nothing is generated. The builder must select only the member-visible columns (never `rationale`, `instruction_text`, `ai_draft_*`, clinician notes) — same discipline the iOS DATA_MODEL already applies.

### 5.2 The clinician's Periodic Review (CLINICAL)
- **Cadence per patient** (`review_cadence_days` 3 / 7 / 14, default 7; 3 during the first month) — a column on `care_plans` or `patients`, CLINICAL-owned migration.
- **Assembly** — a cron (`/api/cron/patient-reviews`, next to `patient-summaries`) creates a `patient_reviews` row per due patient: period, the Day Records of the period, aggregates computed as facts (meals × reactions matrix, top reaction flags with counts, sleep / HRV / RHR vs baseline per day, habit adherence, stressor counts, skin trend, completeness) and a `clinical_tasks` row as the queue entry.
- **Surface** — `patients/[id]/review` grown from the existing `timeline` route: the period strip, the aggregate panels, the **hypotheses panel** (empty in v1, filled by §6 later, always labelled as AI and pending), and the **action composer**: pick from the habit bank or write a habit → the existing author/approve/push path · write an in-app message (`patient_messages`) · propose a consultation (appointment request + message) · adjust a protocol · "watch" (no action, note why). Every action is stamped with the review id so the next review shows "what we tried → what changed".
- **What the member sees** — only the actions, through the gates that exist. The review document itself is `internal_clinical`.

---

## 6. The intelligence layer (later, designed now so the schema does not fight it)

- **Input unit** = a review bundle: N Day Records + profile facts (`app_sex`, `app_age`, goals, complaints, protocols, cycle phase) + the outcome of previous actions. PII-scrubbed through `lib/pii` before any model sees it; the model runs on Infomaniak via `lib/sovereign` tier `clinical` (qwen3 today).
- **Output** = structured hypotheses, never prose to the member:
  `{ hypothesis, evidence: [{day, event_ids}], confidence, suggested_track: habit | consult | test | watch, questions_for_patient: [] }` → `ai_outputs` (`output_type = review_hypotheses`, `approval_status = pending`). A deterministic validator rejects any evidence pointer that does not resolve to a real event id in the bundle — the anti-hallucination gate is code, not a prompt.
- **RAG** = pgvector on CM OS (`knowledge_chunks`, 1024-d, embedded with the already-configured `bge_multilingual_gemma2` on Infomaniak — sovereign end to end). Corpus, in order: FunctionAlps protocols and library content; Thomas's own clinical reasoning notes; a **synthetic situation corpus** generated offline by big models from literature and the practice's reasoning patterns — *never from real patient data*. That generation prompt is a separate deliverable Thomas asked for.
- **Evaluation before any clinician sees it** — a golden set of ~30 synthetic reviews with expected hypotheses (precision of the top 3; zero unresolved evidence pointers; refusal on thin data). A new test counts only once it has been seen to fail.
- **The "smaller specific model"** Thomas describes = RAG + structured prompting over the sovereign model first; fine-tuning an open model on synthetic + consented-anonymised bundles is a later programme with its own legal review.

---

## 7. Work packages

Tiers follow the CLINICAL effort ladder; specialists are the agents in `FunctionAlps-CLINICAL/.claude/agents/`. Each WP is sized for its own agent session with this document as the brief.

| WP | Title | Repo(s) | Tier | Specialist | Depends on | Done when |
|---|---|---|---|---|---|---|
| **WP0** | Schema for the loop: `focus_score`, `skin_score` on moments; `energy`, `focus` on `nb_meal_reactions`; `habit_completions.context_meal_id`; `nb_day_records`; new `wearable_data_types` rows; consent keys `wearables_processing`, `skin_photos`; RLS; regenerated types in CLINICAL / APP / MEMBERS; iOS `DATA_MODEL.md` updated | CLINICAL (owns numbering) → all | T2 | `db-migrations` + `pii-security` review | D5 D6 D7 D8 | additive DDL applied after `BEGIN…ROLLBACK`, advisors clean, types regenerated, wiki `data/tables.md` updated |
| **WP1** | Intraday HealthKit sync: anchored queries, 5/15-min buckets, HRV/glucose raw, new types (daylight, mindful, menstrual, wrist temp), backfill task, epoch batching | IOS | T2 | iOS session (no CLINICAL agent; use this doc + `WearableService`) | WP0 catalog rows (can start with existing HR/steps ids) | rows visible in `wearable_epoch` for a test member; CI green; `IOS_MIGRATION_MAP` Phase H updated |
| **WP2** | Self-assessment v2: focus, skin, stressors, cravings, evening pills; reaction screen with energy/focus; 2 h delay; "Felt fine" one-tap | IOS | T2 | iOS session + `brand-guardian` review of copy (no invented clinical wording — FR strings from the Expo i18n where they exist) | WP0 columns | moments and reactions land with the new fields; engine tests extended and seen failing first |
| **WP3** | Native habits: today list, one-tap done with timestamp, meal-context quick action, offers inbox; streaks server-side | IOS + CM OS (streak RPC) | T2 | iOS session + `data-access` for the RPC | WP0 `context_meal_id` | a clinician-pushed habit is completable from the meal detail and appears in the Day Record |
| **WP4** | `build-day-record` edge function + `nb_day_records` + nightly pg_cron + on-demand endpoint; windows, baselines, completeness; fixture tests on synthetic days | CM OS (functions live in APP repo) | T2 | `api-integration` + `data-access`; `code-reviewer` before deploy | WP0 | a record for a synthetic day matches the fixture byte-for-byte; the 04:00 close runs; no model call in the code path |
| **WP5** | Day Record screen: timeline graph, meal cards, baseline lines, live rebuild, morning local notification; MEMBERS card second | IOS, then MEMBERS | T2 | iOS session; `ui-brand` for the chart tokens; `patient-output` review | WP4 | renders loading / error / empty / unauthorized; a full day and an empty day both look right; Dynamic Type |
| **WP6** | Periodic Review: cadence column, `patient_reviews`, assembly cron, `patients/[id]/review` surface, action composer wired to habit push / messages / appointments | CLINICAL | T3 | `nextjs-surface` + `data-access` + `api-integration`; `pii-security`; `wiki-maintainer` | WP4 | a review is generated for a test patient, an action pushed from it reaches the app, the review is `internal_clinical` |
| **WP7** | Other wearables: source-priority rule in the catalog, vendor-only metrics (readiness, strain), CGM path when Health has none | IOS + CM OS | T2 | `api-integration` | WP1 | one metric, one source per day, stated in the record |
| **WP8** | Intelligence: hypothesis schema + validator, pgvector + embedding pipeline, corpus loader, review-hypotheses call in `lib/sovereign`, golden-set eval, clinician panel | CLINICAL + CM OS | T3 | `ai-pipeline` + `db-migrations` + `pii-security`; separate prompt deliverable for corpus generation | WP6 | eval passes; every hypothesis in `ai_outputs` pending; nothing reaches the member |
| **WP9** | Privacy & App Review: privacy policy re-disclosure (HealthKit, intraday, skin photos), consent gate additions, retention jobs, App Store review notes, `NSHealthShareUsageDescription` per type | IOS + CLINICAL (consent definitions) | T2 | `pii-security` | WP0 keys | consents recorded before any external tester syncs intraday data |

Sequencing:

```
WP0 ──┬── WP1 (iOS intraday) ──┐
      ├── WP2 (self-assessment) ├── WP4 (Day Record builder) ── WP5 (member screen) ── WP6 (clinician review) ── WP8 (intelligence)
      ├── WP3 (habits) ─────────┘                                        │
      └── WP9 (privacy) ── must land before external testers sync        └── WP7 (other wearables) in parallel
```

WP1, WP2 and WP3 are independent of each other and can run as three parallel iOS sessions once WP0's columns exist (WP1 can even start today against the existing HR/steps type ids). WP4 is the first backend piece and the one worth a written plan before code.

Server-side moves this programme adds to the list in `IOS_MIGRATION_MAP.md`: habit streaks, the reaction question engine's scoring, and the meal-window arithmetic (all in the builder, never on the phone).

---

## 8. Decisions for Thomas (defaults in bold — work starts under them)

| # | Decision | Default |
|---|---|---|
| D1 | Is iOS the only client for this facet, with the Expo app frozen at its current features? Android members would then wait. | **Yes, iOS only; Expo frozen** |
| D2 | Post-meal prompt delay | **2 h** (constant change from 2.5 h) |
| D3 | When is a day "closed" and announced? | **04:00 local close, announced at the member's morning check-in time** |
| D4 | Intraday retention on CM OS | **5/15-min buckets kept 12 months; raw HRV / glucose 6 months; daily rows forever** |
| D5 | Focus: new `focus_score` column (keep `energy_mind` for history) vs relabel `energy_mind` as Focus with no schema change | **new column** — relabelling silently changes the meaning of stored history |
| D6 | Reaction energy/focus as columns vs inside `responses` jsonb | **columns** |
| D7 | Cycle tracking in v1 (HealthKit `menstrualFlow` + self-report phase) | **yes, opt-in, shown only when the profile says it applies** |
| D8 | Skin photo in v1 | **score + pills only; photo diary in v1.1 after the consent text exists** |
| D9 | May the member record compare to the member's own 14-day median? | **yes** (own data = fact); never population norms |
| D10 | Review cadence default | **7 days; 3 days in the first month** |
| D11 | Stressor pill list | **work · family · health · sleep · money · social · none · other (text)** |
| D12 | Where the review lives | **`patients/[id]/review`, grown from `timeline`** |
| D13 | Action catalog v1 | **habit from bank · custom habit · message · consultation proposal · protocol adjustment · watch** |
| D14 | RAG storage | **pgvector in CM OS** (sovereign, one backend) — confirm CM OS region satisfies the data-residency position |
| D15 | Retire `generate-report`'s daily period into the Day Record, or keep both | **keep both until WP5 ships, then consolidate** |
| D16 | Evening confounder pills (alcohol, late caffeine, screens in bed) — in v1? | **yes, three toggles, evening moment** |

---

## 9. Traps already known, to carry into every WP
- The wrapped exit code of `rtk` is not a result; gate on raw exit codes (CLINICAL §3). Seven green tests once passed against broken code — see a new test fail first.
- PostgREST errors are values; a write without `.select('id')` can report success on zero rows.
- `approval_status` exists only on `ai_outputs`; `resources.validation_status` is not a patient-facing gate.
- The two retired report functions still show ACTIVE in the Supabase console — do not deploy or "fix" them.
- `nb_*` + `patient_id` is the canonical plane; never the un-prefixed legacy tables.
- HealthKit never reveals whether read access was granted; "connected" is the member's tap on this phone, not a HealthKit fact.
- No third-party Swift packages without a written justification (`docs/ARCHITECTURE.md`); Swift Charts is first-party.
- Never `git add -A` in CLINICAL (PII sibling directories at the git root).
