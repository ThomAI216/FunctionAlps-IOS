# Nutrition Track — implementation brief

**For the Swift coding agent working in this repo.** Read this before touching
`Sources/Features/NutritionTrack/`. It is self-contained: you do not need the
CLINICAL wiki to build from it.

Status: **model and day-close screen drafted, nothing compiled, nothing wired.**
No Swift toolchain existed where they were written. Your first job is
`cd FunctionAlps && xcodegen generate`, build, and fix what the compiler finds.

---

## 0. Read this section before anything else

**This feature does not build a meal logger. One exists, it is good, and it is
in use.**

`Features/Food/` — `CaptureView`, `MealCaptureCoordinator`, `MealDetailView`,
`MealReactionSheet` — plus `Services/MealService` and the `MealLog` model are the
food-capture surface, and the Nutrition track does not replace, duplicate or
fork any of it. It **annotates** it.

Concretely, when a track is running:

| | What happens |
|---|---|
| Photographing a meal | **unchanged** — same `CaptureView`, same `nb_meal_logs` row |
| The AI analysis and retry pipeline | **unchanged** |
| The five meal scores | **unchanged, and never read by this feature** (§2.1) |
| A small row alongside each meal | **new** — `nutrition_eating_event`, keyed to the meal log |
| One record per day | **new** — `nutrition_diary_day` |
| Stool / symptom events | **new**, and only when the digestive module is on |

If you find yourself writing a second photo picker, a second meal list, or a
second analysis poller, stop: something has gone wrong with the design and it is
worth raising rather than building.

---

## 1. What this is

The Nutrition pillar's **7-day observation**. A member keeps photographing meals
exactly as they already do, adds one or two taps at the moment of logging, and
spends about thirty seconds closing the day in the evening. At day 7 the picture
opens.

The phone is **one of two surfaces**. The members web dashboard runs the same
track against the same rows. §6 is the contract between them.

Five layers, for vocabulary:

| | | Where |
|---|---|---|
| **L1** | Deep questionnaire, once per cycle | MEMBERS web |
| **L2** | **The 7-day observation** | **this app** (primary) + web |
| **L3** | Profile — deterministic, versioned | server; both surfaces read |
| **L4** | Protocol — one hypothesis, 1–3 actions | MEMBERS web; adherence here |
| **L5** | Reassessment | all three |

**You are building L2**, plus the read-only cards that show L3/L4 state.

---

## 2. Six rules you may not break

Five are shared with the Sleep track. The sixth is this pillar's own and has no
Sleep equivalent.

### 2.1 No score. Ever. And the meal scores stay where they are.

Not a Nutrition Score, not a grade, not a streak. **`FAColor.scale` — the
five-level ramp the functional check-in uses — must never touch anything in this
feature.**

The five per-meal scores (`inflammationScore`, `energyScore`, `gutScore`,
`digestibilityScore`, `glycemicScore`) **stay exactly as they are in
`Features/Food/`**. They are part of the app and they are not going anywhere.

What they may never do is reach the track. No meal score is averaged into a
domain, and no total, streak or "nutrition score" is assembled from them. If you
need a reason beyond "because": a judgement about one plate and a description of
seven days are different objects, reversible on different timescales, read by
different people.

**Enforcement you should keep:** the track's own models must not have a score
field. If `NutritionTrackEvent` grows one, the rule is already broken.

### 2.2 Four provenance layers stay four

Sleep had three — member, device, derived. Nutrition inserts one:

| Layer | Example | Rule |
|---|---|---|
| Member-reported | hunger 7/10 before lunch | raw, never overwritten |
| **AI-inferred** | `aiIdentifiedFoods: [chicken, rice]` | **provisional**, always labelled |
| Member-confirmed | `confirmedFoods` / `resolvedFoods` | a member-reported value that began as a guess |
| FunctionAlps-derived | 4.2 protein events a day | server only; this app computes none of it |

The middle two are the pair that matters. **Never render an unconfirmed
inference as though a person had agreed with it.** A model that says "chicken" at
0.31 confidence and a watch that reports a sleep latency of zero are the same
failure: a number with the shape of an answer.

Where the track shows a meal's contents, an unconfirmed one must look different
from a confirmed one — and the one-tap confirmation ("we think this has chicken,
rice and vegetables — anything missing?") is the single highest-value
interaction in the whole feature. Coverage depends on it (§5).

### 2.3 Clinical risk is its own card

Never inside a list of things to improve, never cleared by a number improving
later, never decided by a model. This app **displays** flags the server raised
and never creates or resolves one.

### 2.4 One to three drivers, one to three actions

Rendered read-only from L3/L4. If you find yourself building a list of everything
that could be better, the server is not sending that and should not.

### 2.5 Associative language only

"Appeared together", "worth testing". Never "caused", never "your cortisol",
never a mechanism nobody measured.

### 2.6 **A day the member did not close contributes to no count.** ← this pillar's own

This is the rule the whole pillar rests on, and it is the reason the day-close
screen exists.

A missed morning of the sleep diary is **visibly** missing: the row is not there,
the night drops out of the denominator, everyone can see it. A missed lunch is
**invisible** — the day still has meals in it, so it reads as a day the member
ate less.

And every error that follows points the **same way**: fewer eating occasions,
less protein, fewer plants, less alcohol, a shorter eating window. Every one of
those looks exactly like a finding the assessment exists to produce. A pillar
that got this wrong would not fail loudly; it would quietly tell people
flattering things about weeks they had under-logged.

So the member states, once a day, whether that was everything:

```swift
/// true = closed · false = explicitly not · nil = "not sure", which is neither
var dayClosed: Bool?
```

Three states, not two, and `nil` is stored distinctly from `false`. Both behave
as not-closed for every gated metric; the distinction is for the practitioner.

**What you must get right on this screen:**

- Answering "no" must cost the member nothing. No warning colour, no
  exclamation, no "you broke your streak" — there is no streak.
- The consequence is stated the moment it applies, plainly: today will not count
  toward *how often* or *when* you eat, and everything else still counts.
- The day's logged meals appear **above** the question, so it is answerable
  without scrolling back through the feed.
- **No nagging reminder.** One gentle evening prompt at most, dismissible, never
  repeated. A member who closes five days out of seven gets a real result; one
  who feels watched stops logging, and then there is nothing.

---

## 3. The day close — six fields, thirty seconds

| ID | Field | Type | Shown when |
|---|---|---|---|
| **D01** | "Is that everything you ate and drank today?" | yes / no / not sure | always — **the §2.6 field** |
| D02 | Day type | obligation / free | always |
| D03 | Anything unusual? | multi-select | always |
| D04 | Overall digestive comfort | 0–10 | digestion tap on |
| D05 | Roughly how much plain fluid? | 5 bands + not sure | hydration relevant |
| D06 | Anything to note? | short text, optional | always |

D02 is the **same `dayType` the Sleep track uses**, for the same reason: eating
differs between a Tuesday and a Saturday as much as sleep does, and free-vs-
obligation is the most reusable contrast in the programme. Reuse the type, do not
redeclare it.

D05 is banded on purpose. A litre figure recalled at 22:00 is not a measurement,
and a free-text number would invite a precision the data cannot carry.

D06 is free text and the server raises a read-me obligation on it. Never parse
it, never summarise it, never feed it to a model. Say plainly that a person
reads it — because a person does, and that is the only route from something a
member writes to somebody seeing it.

---

## 4. The signal taps — and the sheet that already exists

The per-event signals are: `hungerPre`, `fullnessPost`, `energyAfter`,
`sleepinessAfter`, `cravingBefore`, `giSymptomAfter`. Each appears **only** if
the member opted into it at setup. Burden is chosen, never imposed.

### ⚠ `MealReactionSheet` already exists and partially overlaps

`Features/Food/MealReactionSheet.swift` asks *"How did that meal feel?"* about
2.5 h after eating — overall 0–10 plus bloating, fullness and gas — and writes
`nb_meal_reactions`. That is a different table, a different moment and a
different job, and it stays.

The overlap is real and needs handling rather than ignoring:

| | `MealReactionSheet` (exists) | Track signal taps (new) |
|---|---|---|
| When | ~2.5 h after the meal | at the moment of logging (`hungerPre`, `cravingBefore`) and shortly after |
| Writes | `nb_meal_reactions` | `nutrition_eating_event` |
| Has | overall, bloating, fullness, gas | hunger **before**, fullness, energy, sleepiness, craving, GI |
| Runs | always | only during a track, and only the opted-in taps |

**What to do, and what not to do:**

- **Do not** ship a second sheet that asks the same member about the same meal
  twice. If a reaction row already carries a fullness answer for this meal,
  pre-fill from it and let them confirm.
- **Do** put `hungerPre` and `cravingBefore` on the *capture* flow, not on a
  later sheet. They are about the moment before eating and cannot be recalled
  accurately at 2.5 h — asking then would fabricate data.
- **Do** extend the existing sheet with the track's extra fields when a track is
  active, rather than forking it. One sheet, conditionally longer.

This is the most likely place for this feature to go wrong, and it is worth
raising a design question rather than guessing.

---

## 5. Coverage — two gates, and the app can move both

The member never sees a raw tier without what it rests on, but you should
understand what drives it, because two of the three inputs are things this app
can influence:

1. **Days confirmed complete.** `high` needs 6 of a 7-day window. Driven entirely
   by the day-close screen.
2. **Meals whose contents a human checked.** `high` needs ≥80 %. Driven entirely
   by the one-tap confirmation (§2.2).
3. Both day types present, no unresolved anomalies. Mostly out of your hands.

A member who photographs every meal, never confirms a single one and never closes
a day gets **moderate** coverage for ever. Not a failure state — a real report,
narrower than it could be. The copy for it is fixed and you should not improvise
around it:

> We need a little more observation before drawing a conclusion.

Never a percentage presented as a mark, never a red state, never "you failed".

---

## 6. Two surfaces, one track — the contract

The members web dashboard runs the same track against the same rows.

| | iOS (this app) | MEMBERS web |
|---|---|---|
| Photograph a meal | **primary** — camera, offline, already shipped | upload |
| Signal taps | inline on the log sheet | inline on the log form |
| **Close the day** | evening prompt | a card on the track page |
| Stool / symptom event | quick-add | quick-add |
| Read the results | yes | yes |
| Start / stop a track | yes | yes |

Six rules:

1. **The local date is the member's own**, never a UTC date. At 00:30 in Zurich a
   UTC date is yesterday, and a day-boundary bug in a food log silently moves
   meals between days.
2. **Neither surface may assume it is the only writer.** A member photographs
   lunch on the phone and closes the day on a laptop. That is a normal Tuesday.
3. **Writes are upserts on the natural key**, never insert-only —
   `(patient_id, assessment_id, local_date)` for the day,
   `(assessment_id, meal_log_id)` for an event that annotates a photographed
   meal.
4. **Stamp `logged_via` / `updated_via`** (`"ios"`), so each surface can show what
   happened on the other.
5. **Show the other surface's state.** The web track page shows which days came
   from the phone; do the same in reverse.
6. **A closed window is not editable.** Insert and update require an *active*
   assessment, enforced in RLS. Handle the refusal rather than assuming success.

### An event after midnight

An event logged at 00:20 that belongs to the day which started at 07:30 carries
`dayOffset: 1`. **Set it explicitly from the real timestamp against the assigned
local date — never infer it from the clock.** A heuristic ("anything before 04:00
is yesterday") guesses wrong for shift workers and makes a 00:20 breakfast
indistinguishable from a 00:20 nightcap.

---

## 7. Copy rules

Never:

- "bad meal", "cheat meal", "clean" or "dirty" food
- "you failed your protein"
- "glucose spike = unhealthy"
- any streak, any "X days in a row", any percentage presented as a mark

Prefer:

- "This meal was lower in protein than your usual lunch."
- "You tended to become very hungry on days when lunch was delayed."
- "Bloating was more common after your later, larger dinners."
- "This is a pattern worth testing, not a diagnosis."

And the one sentence that governs the whole week, shown at setup:

> Don't change what you eat because you're logging it. We're trying to see your
> normal week, not your best one.

---

## 8. What is drafted, and what is missing

Drafted, uncompiled, in `Sources/Features/NutritionTrack/`:

| File | What |
|---|---|
| `NutritionTrackModel.swift` | the domain types, the day-close state, the `dayClosed` three-state rule |
| `DayCloseView.swift` | D01–D06, the screen §2.6 exists for |

Not written, and deliberately:

- **The service layer.** `MealService` is the pattern to follow, and the shapes
  it needs are settled — but it should be written against the real Supabase
  client by someone who can compile it.
- **The capture-flow taps.** They belong inside the existing
  `MealCaptureCoordinator` flow, and editing live product code blind is worse
  than leaving a clear note. §4 is that note.
- **Everything the server owns**: derivation, coverage, flags, the profile. All
  of it lives in `clinical-dashboard/lib/nutrition-pillar/` and is already built
  and tested. This app computes no metric and decides no flag.

---

## 9. Done means

- `xcodegen generate` and the project builds.
- A track can be started, run for seven days and finished **without ever opening
  the web dashboard** — and equally without ever opening this app.
- A member can close a day in under thirty seconds, and answering "no" feels
  like nothing.
- No `FAColor.scale` anywhere in the feature. No meal score anywhere in the
  feature's own models.
- A day logged on the web shows here as logged on the web.
- Nothing is shown before day 7, and the screen says why.
