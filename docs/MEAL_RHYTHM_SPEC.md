# Meal Rhythm — per-member meal reminders that learn

**Status:** 2026-09-25 — **slice 1 live** (table + seed applied to CM OS; iOS in this branch). Slices 2–6 not built. Cross-repo (iOS · CM OS · CLINICAL · MEMBERS), so a T3
programme under CLINICAL's ladder: each slice below follows the SOPs of the repo it lands in.

**One-paragraph answer.** Eating habits are the right first routine. The app already holds the
richest signal: every meal photo is a timestamp. Each member gets their own reminder schedule,
with one row per meal slot per weekday. It is seeded from what they told us (onboarding intake,
the Nutrition pillar questionnaire, a 20-second in-app setup) and then kept honest by what they
do. When the logs disagree with the schedule 3 times out of the last 4, the app asks one short
question at the moment it matters, right after they log the meal: *"Your last dinners were around
21:00 — move your dinner reminder to 21:00?"* Nothing changes without a tap. The learning runs on
the server (deterministic, no LLM), the phone only schedules, and every change is kept so the
practitioner can see the habit, not just the reminder.

---

## 1. What exists today (read before designing)

| Fact | Source | Consequence for this spec |
|---|---|---|
| Meal reminders are the same for everyone: lunch 13:30 if nothing was logged 11:00–13:30, dinner 20:15 if nothing 17:30–20:15. No breakfast, no snacks. | `Sources/Core/Notifications/NotificationPlanner.swift` (`lunchNotLogged`, `dinnerNotLogged`) | The thing to replace. |
| Live CM OS, last 180 days, Zurich hour of `logged_at`: dinners 18h·7 · 19h·22 · 20h·12 · **21h·27**. Lunches peak at **14h·26**, ahead of 12h·18 and 13h·17. Breakfasts 7h·25 · 9h·24 · 10h·13. | `nb_meal_logs`, 11 patients, 235 rows | For many dinners, the 20:15 "not logged" nudge fires **before the member has eaten**. The fixed times are wrong for real people today. |
| 63 of 235 rows have `logged_at` more than 3 h away from `created_at`. A few "lunch" rows sit at 22–23 h. | `nb_meal_logs` | `logged_at` is already used as *when eaten* on some paths. Backfills exist and must not teach the learner. |
| 4 preference rows carry an APNs token. | `patient_notification_preferences` | Tiny population. The rules must work from a handful of meals per member, and outcome metrics will be anecdotal for a while. |
| Quiet hours **move** any reminder inside the window to its end: a 22:15 dinner reminder would fire at 07:30 the next day. | `NotificationPlanner.respectingQuietHours` | Meal reminders must be **dropped**, not moved (§6.3). |
| iOS caps pending local notifications at 64. The planner schedules 7 days ahead. | Apple + `horizonDays = 7` | 5 meal slots × 7 days + check-ins + reactions reaches the cap (§6.4). |
| The phone guesses a meal's type from a fixed clock: <11 breakfast, <15 lunch, <18 snack, else dinner. | `MealService.mealType(at:)` | A 17:45 dinner is labelled snack. With a personal schedule, the default becomes the nearest slot in the member's own day (§6.5). |
| The intake asks `meals` (1-2 / 3 / 4+) and `breakfast` (… / "I usually skip breakfast"). It asks nothing about clock times, weekdays vs weekends, or eating out. | MEMBERS `src/lib/questionnaire/intake-v1.ts`, section `s7` | One zero-cost seed today: skip-breakfast → breakfast reminder off. |
| `nb_patient_app_profiles.meals_per_day` / `snacks_per_day` exist, but nothing in MEMBERS writes them. | MEMBERS types, grants migration `20260819e_…` | A weak seed for snack slots only. |
| The Nutrition pillar questionnaire (L1, 70 items) has **§E Meal timing**: `NUT-Q-040/041` first and last calorie on a *workday* · `042` late meals · `043/044` fasting · `045` shift work. `NUT-Q-013` asks about restaurant/takeaway frequency *for the whole week*. `NUT-Q-016` asks about predictability. | CLINICAL branch `claude/four-pillars-questionnaires-ta9psc`, `docs/wiki/four-pillars/research/02-nutrition/nutrition_questionnaire_final.md` | The questionnaire already asks about timing, but not **per meal, per day type**. §5 adds three items rather than a new questionnaire. |
| Pillar tables are live and empty: `pillar_assessment` (pillar ∈ sleep·nutrition·stress·movement; kind baseline·experiment·reassessment; 7/14/21 days), `pillar_questionnaire_response` (`answers` jsonb, `logged_via` ios·web, member RLS gated on an *active* assessment). Migration 204 adds `nutrition_eating_event`, which carries a member-confirmed `meal_slot`, `occurred_at`, `clock_time` and `day_offset`, plus `nutrition_diary_day.day_closed`. | live catalogue + CLINICAL branch | The best timing evidence we will ever get comes from a closed pillar week (§8). |
| The CLINICAL patient page already has a 24 h meal punch-card built from `nb_meal_logs`, hard-coded to Europe/Zurich. | CLINICAL `components/patients/nutrition/meal-timing.tsx` | The practitioner view extends this card; it does not start from scratch (§7.1). |
| `reminders` is written by the care-plan translator, but no app reads it. `patient_feedback_asks` is a clinician-asked better/same/worse table. | CLINICAL `lib/care-plan/translator.ts:356`; live CHECKs | Neither fits, and building on `reminders` would repeat the CLINICAL lesson `feature-with-no-delivery-path.md`. |
| `member-scores` has a meal-timing score that rewards first meal ≤10 h, last ≤20 h and a window ≤12 h. | `supabase/functions/member-scores/engine/health/meal-timing.ts` | A reminder that follows a 21:00 dinner must not *endorse* it. That is why the copy never comments on the time (§4.5). |

---

## 2. The model: three layers, kept apart

This is the design decision everything else hangs on. There are three different facts, owned by
different people:

```
  STATED  ── what the member told us ───────────── intake · pillar questionnaire · in-app setup
     │        (member-reported, never overwritten)
     ▼ seeds
  SCHEDULE ── when the phone reminds ────────────── member_meal_schedule (member-owned)
     ▲        (operational; every row says where its time came from)
     │ proposes, member confirms
  OBSERVED ── what the logs show ───────────────── computed from nb_meal_logs (+ pillar events)
              (FunctionAlps-derived, server only)

  TARGET  ── what a clinician wants (later) ────── a meal_timing habit in the care plan (§9, deferred)
```

- **The observed layer never writes the schedule directly.** It writes a *proposal*, and the
  member's tap moves it. This is the "agile with the person" loop, and it keeps the member in
  charge of their own phone.
- **The schedule never writes back into the stated layer.** A questionnaire answer from March stays
  what the member said in March, even after the reminders have moved. The practitioner needs both
  what they said and what they did. The gap between the two is often the finding.
- **A target is not a schedule.** If a practitioner wants dinner earlier, the learner must not
  follow the member to 21:30. Targets are deferred (§9), but the layers are kept apart now so they
  can arrive without a redesign.

This mirrors the pillar's provenance rule ("four provenance layers stay four",
`NUTRITION_TRACK_IMPLEMENTATION.md` §2.2 on the pillar branch). A reminder time is never evidence
of when someone eats.

---

## 3. The schedule

### 3.1 Slots and defaults

| Slot | Default time | Default | Why |
|---|---|---|---|
| `breakfast` | 08:00 | on | Thomas's structure |
| `morning_snack` | 10:00 | **off** | A 10:00 nudge to someone who doesn't snack reads as advice to snack. On when stated or learned. |
| `lunch` | 12:00 | on | Thomas's structure. The logs say many members eat later, which is exactly what learning is for. |
| `afternoon_snack` | 16:00 | **off** | "Optional snacks" |
| `dinner` | 20:00 | on | Thomas's structure |

A **row per slot per ISO weekday** (1 = Monday … 7 = Sunday): 35 rows per member, all created on
first sync. Weekday rows are what make *"I never have breakfast, except on Sunday"* one row flip
and not a special case. The UI groups them as **Weekdays · Saturday · Sunday**, and "customise
days" opens per-day rows. `remind_at` is kept when a slot is off, so turning it back on restores
the member's time.

### 3.2 What a meal reminder means

**It fires at `remind_at`, and only if that meal isn't logged yet.** Once `remind_at` has been
learned, it sits about 10 minutes before the member's usual time. The lead time is deliberate: the photo has to be taken *before* the first bite,
so the phone should buzz as they sit down, not after the plate is empty. This is why learning
matters. A lunch reminder at 12:00 for someone who eats at 13:30 fires while they are still at
their desk, and they learn to swipe it away.

Satisfied (the day's reminder is cancelled, or never scheduled) when any of these happens:
- a meal is logged whose type is that slot, whatever the clock says; or
- a meal is logged inside the slot's **window**, which runs from the midpoint with the previous
  enabled slot to the midpoint with the next; or
- the member taps **Skipped** on the notification (§6.2).

The reminder **never comments on the time** ("late", "early", "good"). It is a cue to capture,
not a judgement. The judgement belongs to the score and the practitioner.

### 3.3 Seeding: first sync, highest source wins

1. A submitted Nutrition pillar questionnaire with the rhythm grid (§5.1) → `source = questionnaire`
2. The in-app setup (§5.2) → `source = setup`
3. Intake `breakfast = "I usually skip breakfast"` → breakfast off on all days → `source = intake`
4. `nb_patient_app_profiles.snacks_per_day >= 1` → `morning_snack` on (`>= 2` → both snacks) → `source = profile`
5. Defaults → `source = default`

A **later** stated source (a new questionnaire, a re-run setup) overwrites only rows whose source is
still `default`, `intake` or `profile`. For rows the member set by hand or through an accepted proposal, it
raises one consolidated proposal instead (§4). The member's last explicit word is never silently
replaced.

---

## 4. The adaptive loop

### 4.1 Where it runs

In the edge function **`member-meal-rhythm`**, with the rules in **`_shared/rhythm/engine.ts`**. The
engine is pure, deterministic, needs no LLM, and has fixture tests in `_shared/rhythm/tests/`. This
is exactly the shape of `member-daily-focus` + `_shared/focus/engine.ts`. It runs under the
member's session with `verify_jwt` ON and RLS on every read and write. There is no service role.

Why not on the phone: iOS rule 9 (calculations stay server-side). MEMBERS and CLINICAL need the
same answers. And cooldowns kept on the device would be lost on reinstall and invisible to the
practice.

The phone calls it:
- on foreground, next to the daily focus;
- after a meal is logged, so the response can carry a prompt about *that* meal while the
  member is still looking at it;
- after the member edits their schedule.

### 4.2 Evidence the engine trusts

- **Meal time** is `nb_meal_logs.logged_at` in the member's home timezone
  (`nb_patient_app_profiles.timezone`). When the timezone the phone sends differs from it
  (travelling), the engine makes **no proposals** that day.
  A trip must not teach the schedule (see §10, `local_tz`).
- **Likely backfills are excluded from timing**, though they still count as activity. A row is a
  likely backfill when `logged_at ≈ created_at` (the time was never corrected) and the slot label
  is implausible for the clock: a lunch before 10:00 or after 16:30, a breakfast after 13:00, a
  dinner before 16:00. The 22–23 h lunches in the live data are exactly this.
- **Slot of a meal**: `meal_type` breakfast / lunch / dinner maps to that slot. `snack` / `other`
  maps to the nearest snack slot by clock.
- **An active day for a slot group**: ≥2 meals logged that day, or an explicit skip, or a pillar
  `day_closed = true`. A day with a single logged meal says nothing about the others. This is the
  pillar's §2.6 problem in miniature: *absence is not a skip*.
- **Clock arithmetic** is signed minutes from the slot's current `remind_at`, in (−720, +720]. A
  00:20 dinner is +260 min from 20:00, not −1 180. This is the same bug class as the pillar's
  monotonic clock resolver.

### 4.3 The rules

Groups: **workdays** (Mon–Fri, or the days the member named in `NUT-Q-047`) and **weekend**. Saturday
and Sunday are also checked on their own, because that is where the exceptions live.

| Rule | Fires when | Proposes |
|---|---|---|
| **SHIFT** | Slot on; of its last **4** logged occurrences in the group (28-day window), **≥3** are **≥45 min** off `remind_at` *in the same direction* | the median of those ≥3, minus 10 min, rounded to 15 min. Only if that is ≥30 min from the current time. |
| **STOP** | Slot on; the slot is absent on **≥4** of the group's last **5** active days, or **3** explicit skips in a row | turn the slot off for the group |
| **START** | Slot off; logged on **≥3** of the group's last **5** active days, within an interquartile range of ≤60 min | turn it on at the median minus 10 min, rounded to 15 min |
| **DAY** | None of the above fires for the group, but SHIFT / STOP / START fires for **one weekday** over its last 4 occurrences (in practice Saturday or Sunday) | the same change, for that day only: *"add a Sunday breakfast reminder at 09:45"* |

**Why "3 of the last 4" and not "3 in a row".** Thomas described "2 or 3 times in a row". The
rules keep that evidence but tolerate one ordinary day. With "in a row", a member who ate at 21:00
on Monday, Tuesday and Thursday and at 20:00 on Wednesday never triggers, and the weekend
interleaves anyway. Three of four fires within a week on workdays, within two weeks on weekends,
and within about four weeks for a single weekday.

**Why 45 minutes.** A reminder 30 minutes off still does its job. Below about 45 minutes, a shift
isn't worth interrupting someone to ask about.

All thresholds live in one versioned config object in the engine, and each proposal stores
`engine_version`, so tuning later never makes old proposals unreadable.

### 4.4 Guards, which keep it from nagging

- **One open proposal at a time**, and **at most one shown per day**.
- **Warm-up:** no proposals in the first **7 days** after seeding.
- **Respect a hand edit:** a slot the member edited by hand gets no proposal for **14 days**.
- **Answered "keep"** (or "I eat it, I just don't log it"): that slot, group and rule are snoozed for
  **21 days**.
- **"Don't ask about dinner again"** sets `learning_enabled = false` on the slot. The toggle comes
  back in Settings.
- **Paused while a Nutrition pillar observation is active** (§8).
- **Order when several rules fire:** main meals before snacks; SHIFT, then STOP, then START, then DAY.

### 4.5 The questions: where, and in what words

**Where.** The primary place is **in context**, on the "Your plate, read." confirm screen right after
the meal the proposal is about ("you just logged dinner at 21:10…"). The secondary place is a
**Home card**, needed for STOP proposals because those come from *absence* and have no meal to
attach to. **Not a push notification** in v1: asking about notifications by notification adds to
the load it is trying to reduce (§11, decision 4).

**Words.** These are drafts for Thomas. EN is the source; FR is proposed and goes in
`Localizable.xcstrings` after approval. The copy stays neutral: nothing about late or early,
nothing about what is healthy.

| Kind | EN | FR (draft) | Answers |
|---|---|---|---|
| SHIFT | Your last dinners were around 21:00. Move your dinner reminder from 20:00 to 21:00? | Vos derniers dîners étaient vers 21:00. Déplacer votre rappel du dîner de 20:00 à 21:00 ? | **Move to 21:00** · Keep 20:00 · Another time… |
| STOP | We haven't seen breakfast on weekdays lately. Stop the weekday breakfast reminder? | Nous n'avons pas vu de petit-déjeuner en semaine ces derniers temps. Arrêter le rappel du petit-déjeuner en semaine ? | **Stop on weekdays** · Keep it · I eat it, I just don't log it |
| START / DAY | Your Sunday breakfasts are around 09:45. Add a Sunday breakfast reminder at 09:45? | Vos petits-déjeuners du dimanche sont vers 09:45. Ajouter un rappel le dimanche à 09:45 ? | **Add it** · No thanks |
| overflow | Don't ask about dinner again | Ne plus me demander pour le dîner | — |

**"I eat it, I just don't log it"** is the most valuable answer in the whole feature. It turns an
ambiguous absence into a member-reported fact, a logging gap rather than a skipped meal, and the
practitioner reads it as such (§7.1).

---

## 5. Asking up front: the questionnaire and the setup

### 5.1 Nutrition pillar, §E: three items, not a new questionnaire

These are proposed additions to `nutrition_questionnaire_final.md`. The questionnaire version is
bumped, and the items ride the four-pillars branch. The questionnaire is already 70 items, and its
author has asked for it to shrink (08 spec §12 #4), so this adds one grid and two small items.

| ID | Question | Answers | Shown | Key |
|---|---|---|---|---|
| **NUT-Q-046** | When do you usually eat? | Grid. Rows: breakfast · morning snack · lunch · afternoon snack · dinner. Columns: **Workdays · Saturday · Sunday**. Each cell: a time · "usually skip" · "varies". | Always | `timing.rhythm` |
| **NUT-Q-047** | Which days are your workdays? | Multi-select Mon…Sun, prefilled Mon–Fri | If `NUT-Q-045` ≠ No, or the member edits it | `timing.workdays` |
| **NUT-Q-048** | On a typical weekend, how many main meals are eaten out (restaurant, takeaway, at friends')? | 0 · 1 · 2 · 3 · 4+ | Always | `environment.food_away_weekend` |

- **Saturday and Sunday are separate columns** because Thomas's own example ("never breakfast,
  except Sunday") can't be written in a single "weekend" column.
- **`NUT-Q-040/041` stay** (the engine reads `timing.first_calorie_self` / `last_calorie_self`), but
  the form **prefills** them from the earliest and latest workday cells, and the member confirms.
  They still catch the 06:30 latte that isn't a "meal".
- `048` complements `013` (the whole week). It feeds the food-environment domain, **not** the
  reminders: eating out changes *where*, not *when*.
- On submit, the next rhythm sync seeds the schedule by the §3.3 rules, and the schedule screen
  says "Updated from your questionnaire".

### 5.2 The in-app setup, for everyone not in a pillar

This is the same grid with the same keys, cut to **Weekdays / Weekend**, plus a "Sunday is
different" link. It takes 20 seconds and every cell is prefilled with the defaults. It is offered
**once**, right after notification permission is granted (the first logged meal, per
`NotificationService.askIfNeeded`), and it can be skipped. The answers are written straight into
`member_meal_schedule` as `source = setup`. It is a settings choice, not an assessment answer, so
it creates no questionnaire row, and the practitioner still sees it through the source column.

---

## 6. iOS changes

### 6.1 Code

| Where | Change |
|---|---|
| `Models/` | `MealSlot` (5 cases, raw values = the DB CHECK), `MealScheduleEntry`, `RoutinePrompt` |
| `FunctionAlpsBackend` + `SupabaseBackend` | `mealRhythm(event:tz:locale:) -> MealRhythm` (edge fn) · `saveMealSchedule(_:)` (PostgREST upsert on `patient_id,slot,weekday`) · `answerRoutinePrompt(id:answer:time:)` (RPC) · `recordMealSkip(slot:day:)`. Table and function names stay in `Core/API` (rule 2). |
| `NotificationService` | holds the schedule, passes it to the planner, calls `mealRhythm` on foreground and after a meal is logged, and exposes the open prompt |
| `NotificationPlanner` | per-slot meal kinds from the schedule (§3.2), replacing the fixed 13:30 / 20:15 kinds. `meal.lunch` / `meal.dinner` keep their raw values so pending requests from older builds reconcile. Plus §6.3 and §6.4. |
| `MealService.mealType(at:)` | nearest enabled slot in today's schedule; the fixed clock stays as the fallback |
| `Features/Notifications/` | `MealScheduleView`: Weekdays · Saturday · Sunday, then "customise days". Each slot has a toggle and a time; the source is shown as a caption ("from your questionnaire", "you moved this on 3 Oct"). The "Meal not logged" row in `NotificationsSettingsView` becomes "Meal reminders ›". |
| `Features/Food/` + `Features/Home/` | `RoutinePromptCard` on the confirm screen and on Home (§4.5) |
| `Features/Onboarding/` or `Features/Notifications/` | `MealRhythmSetupView` (§5.2) |
| `Localizable.xcstrings` | every new string in en and fr (rule 7) |

The schedule screen and the prompt card render loading, error, empty and unauthorized states with
`FALoadingState` / `FAErrorState` / `FAEmptyState` (rule 5). Icons are labelled, and a slot's on/off
state is never shown by colour alone (rule 10).

### 6.2 The notification

A new category, `FA_MEAL_SLOT`:
- **Log it** (foreground) opens capture with the slot preselected. This needs a
  `functionalps://capture?slot=` route next to the existing `food` route.
- **Skipped** (background) writes `member_meal_skip` for today, cancels the slot's reminder, and
  opens nothing. It is the same background-write pattern as "Felt fine" (`quickFine`).

Copy (EN / FR draft):
- "Lunch? Snap your plate before you start." / « Déjeuner ? Photographiez votre assiette avant de commencer. »
- Same shape for breakfast, dinner and snacks.
- Nothing on the lock screen says anything about health (the same rule `push-send` follows).

### 6.3 Quiet hours: drop meals, move the rest

`respectingQuietHours` keeps *moving* check-ins, the weekly summary and the stale-sync reminder,
and **drops** meal-slot reminders that fall inside the window. A dinner reminder at 07:30 the next
morning is worse than none. The Settings subtitle "Reminders wait until the window ends" gains
"— meal reminders inside it are skipped". If an accepted SHIFT lands inside quiet hours, the prompt
says so before the member confirms.

### 6.4 Budget and spacing

These are pure passes in the planner, each with its own tests:

1. **Spacing.** No two FunctionAlps notifications within 20 min. Priority runs check-in, then meal
   slot, then post-meal reaction, then weekly, then stale sync. The lower one moves to 20 min after
   the higher, or is dropped if that lands past its window. The collision is real: the default
   morning check-in and the default breakfast reminder are both at 08:00.
2. **Pending cap.** Meal slots are planned **4 days** ahead (not 7), and the whole plan is cut to
   the nearest **60** requests, which keeps the iOS limit of 64 with room for `mealLogged`
   additions. Planning happens on every foreground, so 4 days is plenty, and a member who hasn't
   opened the app for 4 days stops getting meal reminders. That is the right way to back off.
3. **Daily ceiling** (a decision for Thomas, §11 #3): by default, at most **one** post-meal reaction
   nudge per day once meal slots are on. Two check-ins, three meals and several reactions come to
   more than eight buzzes a day, and that is how a member ends up with every notification off.

### 6.5 Tests (Swift Testing, extending `NotificationPlannerTests`)

- A lunch logged at 11:40 (type lunch) cancels today's 12:45 lunch reminder.
- A snack logged at 10:20 does **not** cancel lunch.
- Breakfast off Mon–Sat and on Sunday at 09:45 → exactly one breakfast request in a 7-day plan.
- A 22:15 dinner reminder with quiet hours from 22:00 is dropped, not moved to 07:30.
- A morning check-in at 08:00 and breakfast at 07:50 are spaced ≥20 min apart.
- The whole plan never exceeds 60 requests.
- Pending `meal.lunch.<day>` requests from the old build are reconciled, not duplicated.

Each test must be seen to fail against today's planner before it counts (CLINICAL §8).

---

## 7. CM OS: tables, RPC, edge function

This is a sketch for review, not an applied migration. It is additive only. It lives in
`FunctionAlps-IOS/supabase/migrations/` with a date stamp, like `20260925_patient_day_state.sql`,
because these are app-owned tables and CLINICAL owns the `NNN_` sequence. Before naming it: run
`list_migrations` on CM OS, sweep every branch's migrations folder (CLINICAL SOP 01), dry-run in
`BEGIN … ROLLBACK`, then run `get_advisors(security)`.

```sql
-- The schedule the phone executes. Member-owned; staff read.
create table public.member_meal_schedule (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  slot text not null check (slot in ('breakfast','morning_snack','lunch','afternoon_snack','dinner')),
  weekday smallint not null check (weekday between 1 and 7),          -- ISO: 1 = Monday
  enabled boolean not null,
  remind_at time not null,                                            -- member wall clock; kept when off
  source text not null check (source in
    ('default','intake','profile','setup','questionnaire','member','learned','pillar_observation')),
  learning_enabled boolean not null default true,                     -- false = "don't ask about this slot again"
  updated_via text check (updated_via in ('ios','web','engine')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (patient_id, slot, weekday)
);

-- Proposals and their answers: the audit trail of how a routine adapted.
-- `domain` is the one concession to "the whole routine ecosystem": the question/answer/snooze
-- mechanics are the same for a bedtime or a supplement reminder; the schedule tables are not.
create table public.member_routine_prompt (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  domain text not null default 'meal' check (domain in ('meal')),
  slot text not null,
  weekdays smallint[] not null,                                       -- the rows an acceptance touches
  kind text not null check (kind in ('shift','stop','start','day','consolidate')),
  current_at time,
  proposed_at time,
  evidence jsonb not null,                -- {meal_ids[], local_times[], n, of, window_days, group}
  engine_version text not null,
  status text not null default 'open' check (status in ('open','answered','expired','superseded')),
  answer text check (answer in ('accept','keep','adjust','eats_not_logging','stop_asking')),
  answer_at time,                                                     -- the time picked on 'adjust'
  snooze_until date,
  shown_at timestamptz,
  answered_at timestamptz,
  answered_via text check (answered_via in ('ios','web')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint answered_shape check ((status = 'answered') = (answer is not null))
);
create unique index member_routine_prompt_one_open on public.member_routine_prompt (patient_id) where status = 'open';

-- "Skipped" from the notification: an explicit skip beats an inferred one.
create table public.member_meal_skip (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  local_date date not null,
  slot text not null,
  logged_via text check (logged_via in ('ios','web')),
  created_at timestamptz not null default now(),
  unique (patient_id, local_date, slot)
);
```

**RLS.** It follows `patient_day_state`. The member selects, inserts and updates their own rows
(`patient_id in (select id from patients where auth_user_id = auth.uid())`). The skip table allows
insert and delete for today ± 1 in the member's local calendar. Staff read via
`public.is_nutritionist_or_above()`. **No staff write**: a practitioner does not move a member's
phone reminders. Their lever is the care plan (§9).

**RPC `member_answer_routine_prompt(p_id uuid, p_answer text, p_time time default null, p_via text)`**
is `security invoker`, so RLS applies. In one transaction it marks the prompt answered and applies
the result:
- `accept` / `adjust` update the affected schedule rows (`source = learned` / `member`);
- `keep` / `eats_not_logging` set `snooze_until = current_date + 21`;
- `stop_asking` sets `learning_enabled = false`.

It is one function because it is one write from two surfaces. MEMBERS' own lesson
(`rls-update-policies-are-row-scoped-not-column-scoped.md`) says the same: a member write with rules
beyond row ownership goes through a function, not a raw table update.

**Edge function `member-meal-rhythm`**

```
POST { event: 'foreground'|'meal_logged'|'schedule_edited', mealId?, tz, locale }
→ { schedule: [{slot, weekday, enabled, remindAt, source, learningEnabled}],
    prompt:   {id, kind, slot, weekdays, currentAt, proposedAt, evidence: {n, of, times[]}, text} | null,
    observed: {slot: {workday: {medianAt, n, activeDays}, weekend: {…}}} }
```

1. Seeds the schedule if the member has none (§3.3).
2. Expires the open prompt if it is more than 7 days old or its evidence changed.
3. Evaluates §4.3 under §4.4 and inserts at most one proposal.
4. Returns the schedule, any prompt, and the observed rhythm.

`prompt.text` comes back in `locale`, the same way `member-daily-focus` returns the practice's texts
(rule 6: wording is not invented in Swift). Add the operations to `openapi.yaml` as
`x-status: planned`.

### 7.1 CLINICAL: the practitioner's view (read-only)

This extends `components/patients/nutrition/meal-timing.tsx`, the existing 24 h punch-card:
- **Fix its timezone.** Use the member's timezone (`nb_patient_app_profiles.timezone`) instead of the hard-coded Europe/Zurich.
- **Overlay the schedule.** Show a tick per enabled slot, with its source.
- **Show "Stated".** When a pillar response exists, show the `timing.rhythm` grid beside the observed times.
- **Show a routine timeline.** List every answered prompt as one line, for example: *"3 Oct — dinner reminder 20:00 → 21:00, member confirmed (21:05, 21:20, 21:10 of the last 4)"* or *"weekday breakfast: member says eats but doesn't log it"*.

The timeline is Thomas's "I want to understand the habits": what they said, what they do, and what
they confirmed. Wiki: add the three tables to `docs/wiki/data/tables.md` under "written by the
patient app, read here".

### 7.2 MEMBERS

- The Profile row "Notifications — soon" (`src/app/dashboard/profil/page.tsx:467`) becomes the same
  meal-reminder editor on the same table. It uses a server action with Zod and the member's own
  session (no service role, per MEMBERS rules), plus the prompt card for anyone who answers on the
  web.
- The pillar L1 form gets `NUT-Q-046…048` (§5.1).

---

## 8. With the Nutrition pillar

| Moment | Rule |
|---|---|
| **During an active Nutrition observation** (`pillar_assessment` pillar = nutrition, status = active) | Reminders **stay**: they sit at the member's *own* times, so they describe rather than prescribe, and they are what keeps coverage up. Proposals **pause**, so the week measures habits and not our questions ("we're trying to see your normal week, not your best one"). The pillar's evening day-close prompt goes through the same planner, at check-in priority. |
| **When the observation closes** | Closed days of `nutrition_eating_event` (member-confirmed `meal_slot` + `clock_time` + `day_offset`) are the best timing evidence the system will ever have. The engine makes **one `consolidate` proposal**: *"Your week showed breakfast around 07:40 on workdays and none at the weekend, lunch around 13:15, dinner around 20:45. Use these for your reminders?"* One tap. Accepted rows take `source = pillar_observation`. |
| **Never** | The rhythm engine never writes pillar tables, and the pillar engine never reads the schedule. A reminder at 21:00 is not an observation of dinner at 21:00. |

---

## 9. Later: when a practitioner wants a different time

Deferred until a practitioner prescribes a meal-timing habit that the app must remind for.
The path is already visible:
- `care_plan_domain` has `meal_timing`;
- live `habits` rows already carry `domain = 'meal_timing'`;
- the phone already reads `habits`.

A prescribed timing habit with a target (for example "dinner by 19:30") would add `target_at` to
the slot. The reminder would switch from *capture cue at the usual time* to *routine cue at the
target*. The learner stops shifting that slot and only reports adherence to the practitioner. It
still asks the member nothing, because the target is a clinical decision, not a preference. Do
**not** route this through `reminders`: nothing on the phone reads it.

---

## 10. Deferred, each with the fact that would justify it

| Deferred | Build it when |
|---|---|
| `nb_meal_logs.local_tz` (the phone's timezone at logging) | a proposal is observed that a trip caused, despite the §4.2 guard, or the pillar needs it. Until then the engine uses the stored timezone and stays silent while travelling. |
| A stored observed-rhythm table | CLINICAL needs summaries the punch-card and timeline can't give |
| Proposals delivered as push notifications | in-app prompts sit unanswered for longer than their 7-day life in a majority of cases |
| An evening-snack slot | a member or practitioner asks for it. Late eating matters to the pillar, but reminding someone to snack at 22:00 is not neutral. |
| Practitioner targets (§9) | the first prescribed meal-timing habit that needs a reminder |
| Sleep, movement and supplement routines | meal rhythm has run long enough to show whether the prompt loop is welcome (§12). Then they reuse `member_routine_prompt` with a new `domain`. |

---

## 11. Decisions for Thomas

| # | Decision | Recommendation |
|---|---|---|
| 1 | Default slots on/off | Breakfast 08:00, lunch 12:00 and dinner 20:00 **on**. Snacks at 10:00 and 16:00 **off** until stated or learned. |
| 2 | What a meal reminder means | At the usual time, minus 10 min, as a capture cue ("snap before you start"), and only if not yet logged. It replaces the "not logged" nudges. |
| 3 | Daily ceiling | At most one post-meal reaction nudge per day once meal slots are on |
| 4 | Where proposals appear | In the app only: the confirm screen and the Home card. Never as a push in v1. |
| 5 | Thresholds | 3 of the last 4 · 45 min · 21-day snooze · 7-day warm-up · 14 days after a hand edit |
| 6 | The questionnaire | Add `NUT-Q-046/047/048` to the pillar (version bump) and the 20-second in-app setup for everyone else |
| 7 | During the pillar week | Keep reminders, pause proposals, one consolidated proposal at close |
| 8 | Practitioner control | Read-only view now. Targets later, through care-plan habits, never by editing the member's reminders. |

---

## 12. Order of work: which surface first

**iOS first**, because the reminders fire there and the meals are logged there. Then CLINICAL,
which is cheap and gives Thomas the habit view. The questionnaire rides the pillar branch whenever
that lands.

| Slice | Repo(s) | Ships | Depends on |
|---|---|---|---|
| **1. Your meal times** ✅ | CM OS + iOS | `member_meal_schedule` + RLS. Seeding by the SQL function `member_meal_schedule_seed()` rather than the edge function — the same rule in one place, one RPC fewer to deploy; the slice-3 engine calls it. `MealScheduleView`. The setup (`MealTimesSetupSheet`, offered by a one-time Home card). Planner reads the schedule, with drop-in-quiet-hours, spacing and the 60 cap. Default slot from the schedule. | nothing |
| **2. Skipped** | CM OS + iOS | `member_meal_skip`, the `FA_MEAL_SLOT` actions, the `capture?slot=` route | 1 |
| **3. The loop** | CM OS + iOS | `member_routine_prompt` + RPC, the engine rules §4.3–4.4 with fixture tests, `RoutinePromptCard` on confirm and Home | 1, 2 |
| **4. The habit view** | CLINICAL | punch-card timezone fix + schedule overlay + routine timeline, and the wiki tables page | 3 |
| **5. Asked up front** | MEMBERS + CLINICAL (pillar branch) + engine | `NUT-Q-046…048`, seeding from a submitted response, the pause during observation, the `consolidate` proposal at close | the pillar branch merged |
| **6. On the web** | MEMBERS | the Profile notifications editor + web prompt card | 3 |

Each slice updates `IOS_MIGRATION_MAP.md` (Phase G row) when it lands, along with the owning repo's
wiki per its definition of done.

### 12.1 Acceptance: Thomas's own stories, as engine fixtures

1. Dinner reminder at 20:00; the last 4 workday dinners at 21:05, 21:20, 20:10, 21:10 → SHIFT to **21:00**, workdays.
2. Breakfast on; 5 workdays with lunch and dinner logged and no breakfast → STOP breakfast, workdays. The answer "I eat it, I just don't log it" → kept, snoozed 21 days, and the practitioner sees the answer.
3. Breakfast off Mon–Sat; the last 3 Sundays at 09:40, 10:05, 09:55 → DAY: add a Sunday breakfast at **09:45**.
4. Only dinner ever logged, one meal a day → **no** STOP for breakfast (not an active day).
5. A dinner at 00:20 counts as +260 min against 20:00, not −1 180.
6. A "lunch" logged at 22:40 with `logged_at ≈ created_at` → excluded from timing.
7. A Nutrition observation is active → no proposals. It closes → exactly one `consolidate` proposal.
8. A proposal declined on 1 Oct → the same slot, group and rule are not proposed again before 22 Oct.
9. The phone's timezone differs from the stored one → no proposal that day.

### 12.2 How we'll know it worked

- **Precision:** the share of meal reminders followed by a log for that slot within 90 min. Baseline: today's fixed 13:30 / 20:15.
- **Slot coverage:** meals per active day, by slot, before and after.
- **Fatigue:** members who switch meal reminders (or all notifications) off.
- **Proposal fit:** the accept rate. Mostly "keep" means the thresholds are too eager; tighten them before adding any new rule.

With a handful of iOS members, these are read member by member, not as percentages, for the first
months.

---

## Appendix: the system-change gates (CLINICAL `engineer-system-change`)

- **Gate 1, the grounded problem.** The fixed reminder times don't match members. VERIFIED: the
  planner code, and 27 dinners in the 21 h hour against a 20:15 "not logged" nudge. Breakfast has
  no reminder at all. VERIFIED.
- **Gate 2, the consumers.**
  - `member_meal_schedule`: the planner and `MealService` now; the MEMBERS editor and the CLINICAL overlay next.
  - `member_routine_prompt`: the prompt card, the engine's cooldowns, and the CLINICAL timeline.
  - `member_meal_skip`: the engine's STOP rule.
  - Deferred items (§10) have no committed consumer, so they are not built.
- **Gate 3, the rung.** Rung 5, a new module in an existing pattern: an edge function with a
  `_shared` engine (like `member-daily-focus`) and a member-written, staff-read table (like
  `patient_day_state`). Rung 3, columns on `patient_notification_preferences`, can't hold
  per-weekday exceptions without dozens of columns. Rung 4, learning on the phone, breaks rule 9,
  isn't visible to the practice, and loses cooldowns on reinstall.
- **Gate 4, the consequences.**
  - **Sync risk:** the slot vocabulary exists in Swift, TypeScript (engine, MEMBERS, CLINICAL) and a DB CHECK. The CHECK is the truth, and each repo gets a `db-columns` test (the pillar pattern).
  - **Cost:** 35 rows per member.
  - **Escalation triggers:** schema, and member-visible text.
- **Verdict: REDUCE.** Build slices 1–3. Slices 4–6 follow as their dependencies land. Everything
  in §10 waits for its named fact.
