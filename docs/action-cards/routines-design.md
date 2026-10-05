# Routines, weekly priorities and evolutions: design proposal (2026-10-05)

Status: **brainstorm for the owner.** No table is created yet: the owner holds off on the database until the
design settles. The draft `supabase/migrations/20261005_action_tracks.sql` (not applied) will be replaced by
whatever comes out of this.

This supersedes the "tracks as lists of cards" idea in `tracks-design.md`. In this design a track becomes a
**sequence of 2-week priority blocks**, and the actions live in **routines**.

## 1. The process (one cycle = 1 or 2 weeks)

1. **Objective.** The member says what they focus on: energy, sleep, focus, brain fog, muscle, weight, stress.
   - That picks a track.
   - Every member also runs the Basic track.
2. **Priorities.** Each cycle sets **1 to 3 weekly priorities**, e.g. "Same bedtime on weekdays · No caffeine
   after 14:00 · Screens off 30 minutes before bed".
   - **Autopilot** (trial, free): the track's next block.
   - **Clinician** (prescribed care): set in CLINICAL. The existing `care_plan_items.is_weekly_focus` already
     marks plan priorities.
3. **Placement.** Each priority becomes an action placed in a routine (morning, during the day, evening),
   within the caps (§4).
4. **Daily.** The member runs the routines.
   - The card's gentle / standard / further versions still flex day to day with readiness: this is the
     existing daily focus, unchanged.
5. **Evolution.** When an action has been done enough times at its level (§4, rule 3), the app offers the
   next level.
6. **Review** at the end of the cycle. The review shows:
   - completion per routine;
   - streaks;
   - level-ups;
   - which priorities held.

   Then: keep, level up, swap, or take the next block. The autopilot does this with fixed rules; a clinician
   does it in CLINICAL.

Two kinds of actions on a day:
- **Priority actions** (this cycle's 1–3): starred, shown first, counted in the review.
- **Overall actions**: everything already installed that the member keeps doing.

## 2. Routines

| Routine | When (anchor) | Cap | What goes in it |
|---|---|---|---|
| **Morning** | from waking to the first work block | 3 | hydrate · light · move (+ breath, breakfast, caffeine timing as swaps) |
| **Work** | around focused work | day cap | focus set-up, breaks between blocks, task switches |
| **Energy reset** | the afternoon dip, after lunch | day cap | short walk, daylight, sigh, deep rest |
| **Sport** | training days only | day cap | warm-up, session, attention, post-training meal |
| **Meals** | at each main meal | day cap | plate, order of eating, pace |
| **Evening** | the last 1–3 hours before bed | 3 | screens, light, wind-down (+ bedroom, kitchen, bedtime as swaps) |

The day routines share **one cap of 6** across them. Proposed contents, using cards we already have:

**Morning routine (3)**
1. *Hydrate*: A glass of water before coffee.
2. *Light*: Morning light within an hour of waking.
3. *Move*: Morning stretch, five minutes. This step climbs the "morning movement" ladder (§3).
- Swaps:
  - Ten focused breaths on waking;
  - Protein at breakfast;
  - First coffee 30 minutes after waking;
  - Same wake-up time, weekends too. This works as the routine's start time rather than a separate tick.

**Evening routine (3)**
1. *Screens*: Screens off 30 minutes before bed. Ladder: phone out of the bedroom → 30 min → 60 min.
2. *Light*: Dim the lights after 21:00.
3. *Wind-down*: one of:
   - Five minutes of cyclic sighing;
   - Tomorrow's list before bed;
   - A mental walk at lights-out;
   - Slow eye movements at lights-out.
- Swaps:
  - A cool bedroom for the night;
  - A hot shower before bed;
  - Kitchen closed after 21:00;
  - Same bedtime on weekdays, which also works as the routine's end time.

**Work routine**
- Phone in another room while you focus;
- Single-task the first work hour, rising to "A two-hour focus block, then a break";
- A two-minute pause between tasks, or Walk five minutes every half hour;
- The same small ritual at each switch.

**Energy reset**
- A 10-minute walk after lunch;
- Five minutes outside in daylight;
- The double-inhale sigh;
- Ten minutes of guided deep rest;
- A short nap (prescription).

**Sport routine** (training days)
- warm-up (Morning stretch);
- the session: strength or cardio cards, prescription;
- Full attention on every rep;
- A proper meal after training;
- Hard workouts end 3–4 hours before bed.

**Meals**
- Vegetables on half the plate;
- Protein first, then the rest;
- Slow first five bites;
- Three slow breaths before meals.

**Week 1 (trial).** The Basic track starts at **2 morning + 2 evening**, then grows. Nobody gets 12 actions
on day one.

## 3. Evolutions (ladders)

A **ladder** is an ordered chain of levels. Each level is a card. A level can offer a choice: "or".
- **Flex** is the card's gentle, standard and further versions. They change day to day with readiness: a
  bad night means today's gentle version. Flex is not a level.
- **Levels** change over weeks, through the rules in §4.

On the member side, tapping an action shows its ladder:
- the levels;
- where the member is;
- "2 of 3 done to unlock level 3";
- the date each level was reached.

| Ladder | L1 | L2 | L3 | L4 |
|---|---|---|---|---|
| Screens before bed | Phone out of the bedroom | Screens off 30 min before bed | **Screens off 60 min before bed** *(new card)* | |
| Morning movement | Morning stretch, five minutes | Stretch **+ one strength circuit** *(new)* **or** stretch + 10-min walk *(new)* | A brisk walk, 20 → 30 → 40 min (A brisk 30-minute walk, with its versions) | Warm-up + an easy run *(new; probably cleared-only)* |
| Walking | A 10-minute walk after lunch | Walk five minutes every half hour | A brisk 30-minute walk | Long, easy cardio (prescription) |
| Bodyweight strength | Ten sit-to-stands | One set of push-ups | Stretch + one strength circuit *(new)* | Strength sessions (prescription) |
| Caffeine | No caffeine after 14:00 | First coffee 30 minutes after waking | **First coffee 60–90 minutes after waking** *(new; book: ramp 30, then 60)* | |
| Bedtime | Same bedtime on weekdays | Same wake-up time, weekends too | | |
| Light | Five minutes of daylight | Morning light within an hour of waking | + Afternoon light before sunset | |
| Calm | The double-inhale sigh | Five minutes of cyclic sighing | Five minutes sitting with your breath | |
| Focus | Phone in another room while you focus | Single-task the first work hour | A two-hour focus block, then a break | |
| Plate | Vegetables on half the plate | Protein first, then the rest | One meal from single-ingredient foods | |
| Kitchen | Kitchen closed after 21:00 | **Kitchen closed 3 hours before bed** *(new; book: 2–3 h)* | | |

"New card" means content to write with the action-card guide, then review like the Huberman set. Where a
level comes from the book, the number is the book's.

## 4. Rules (proposed numbers, to settle)

1. **Caps.** Morning ≤ 3 · day ≤ 6 · evening ≤ 3.
   - Week 1–2 of a new member: ≤ 2 + 2 + 2.
   - A clinician can raise a cap for one member.
2. **Self-added actions.**
   - Trial ≤ 3 active at once; member ≤ 6.
   - At most one new self-added action every 3 days.
   - Prescribed actions do not count against the self-added limit, but they do count against the routine caps.
3. **Level-up.**
   - Daily actions: 3 completions at the current level within 7 days.
   - Actions done 2–3 times a week: 2 completed weeks.
   - The app *offers* the next level; the member accepts or stays.
   - A clinician can lock a level or set 2 instead of 3.
4. **One level-up per routine per week**, so a routine changes one thing at a time.
5. **Stack only on a stable base.** A new action enters a routine only when that routine was ≥ 70 % complete
   over the last 7 days. Otherwise the app suggests a gentler level or a swap.
6. **Step down, never punish.** After 3 misses in a row the app offers the level below or a pause.
   - Never automatic.
   - Streaks are never shown as "lost".
7. **Streaks.**
   - Per action: consecutive due days done. Weekly actions count weeks.
   - One grace day per 7 days.
   - Routine streak: days with the whole routine done.
   - The best streak is kept.
8. **Priorities.** 1–3 per cycle, a cycle being 1 or 2 weeks.
9. **Tiers apply everywhere:**
   - trial cards in the trial;
   - members-only cards for paying members;
   - prescription cards placed by a clinician only.
10. **Who wins.** A clinician's placement beats the member's.
    - The member can pause a prescribed action for today.
    - Removing a prescribed action asks the clinician.

These rules read **completions only**, never health data. This is the doctrine of the existing habit loop
(`lib/habit-loop/arithmetic.ts`, `care_plan_item_gates`): "gates read behaviour, not health". Rule 3 is a
gate: `required_n = 3`, `window_days = 7`.

## 5. Member side (app)

- **Today** shows the cycle's priorities on top (1–3, starred). Below them come the routines, as stacks the
  member can run:
  - Morning;
  - the day routines that apply today (Sport only on training days);
  - Evening.

  Ticking an action marks it done. "Start routine" walks through it one action at a time.
- **Action sheet** shows:
  - the card;
  - today's version (flex);
  - the **ladder**;
  - the streak;
  - the history ("30 min since 3 Oct · 60 min since 20 Oct").
- **Progress** shows:
  - streaks;
  - a routine completion calendar;
  - the level-ups timeline;
  - priorities kept per cycle;
  - the cycle review.
- **Manage**:
  - add from the bank, within the caps;
  - move between routines;
  - reorder;
  - pause.

  At a cap, the app explains why and offers a swap.

## 6. Clinician side (CLINICAL)

- **Patient → Routines**:
  - three columns: Morning / Day (Work, Energy, Sport, Meals) / Evening;
  - drag cards in, set the level, star the priorities for this cycle (1 or 2 weeks);
  - see adherence and streaks;
  - lock a level;
  - raise a cap.
- **Action cards → Ladders**: chain cards into levels, with "or" choices at a level.
- **Action cards → Routine templates**: the default morning and evening per objective, and the track as a
  sequence of 2-week blocks of priorities.
- **Settings → Rules**: the numbers in §4, practice-wide, overridable per patient.

## 7. What already exists and will be reused

| Need | Already there |
|---|---|
| Priorities | `care_plan_items.is_weekly_focus` (iOS "My health plan" priorities) |
| Routine moment | `habit_bank.default_slot` / `habits` slot (morning · midday · evening). Still needed: routine kind and order. |
| Level-up rule | `care_plan_item_gates` (`required_n`, `window_days`, `unlocks_item_id`) + `evaluate-gates` |
| Streaks and adherence | `lib/habit-loop/arithmetic.ts` (+ its copies in the app repo) |
| Day-to-day flex | `easy_*` / `rev_*` + `member-daily-focus` `variantFor` |
| Tiers | `member_can_add` (+ `members_only`, proposed) · `member_entitlements` (+ `trial_14_day`, owner's choice) |

## 8. Open questions for the owner

1. Cycle length: always 2 weeks, or does the clinician pick 1 or 2?
2. Does the Sport routine count against the day cap of 6, or is it separate on training days?
3. Is "Same bedtime" / "Same wake-up time" an action to tick, or the routine's start/end time?
4. Level-up: offer (member accepts) or automatic?
5. Streak grace day: yes or no?
6. Which ladders to write first: the new cards marked above.
