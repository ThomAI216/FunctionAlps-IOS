# Sleep Track — implementation brief

**For the Swift coding agent working in this repo.** Read this before touching
`Sources/Features/SleepTrack/`. It is self-contained: you do not need the
CLINICAL wiki to build from it.

Status: **four screens drafted, nothing compiled, nothing wired.** No Swift
toolchain existed where they were written. Your first job is `cd FunctionAlps &&
xcodegen generate`, build, and fix what the compiler finds.

---

## 1. What this is

The Sleep pillar's **14-night observation**. A member logs one 90-second morning
diary for fourteen days while their watch supplies duration and physiology
passively. At day 14 — never before — the pattern opens.

The phone is **one of two surfaces**. The members web dashboard runs the same
track against the same rows. §6 is the contract between them, and it is the part
most likely to be got wrong.

Five layers, for vocabulary:

| | | Where |
|---|---|---|
| **L1** | Deep questionnaire, once per cycle | MEMBERS web |
| **L2** | **The 14-night observation** | **this app** (primary) + web fallback |
| **L3** | Profile — deterministic, versioned | server; both surfaces read |
| **L4** | Protocol — one hypothesis, 1–3 actions | MEMBERS web; adherence here |
| **L5** | Reassessment | all three |

**You are building L2**, plus the read-only cards that show L3/L4 state.

---

## 2. Five rules you may not break

These are not style preferences. Each one has a reason and each one is checkable
in review.

### 2.1 No score. Ever.

Not a Sleep Score, not a grade, not a fitness age, not a streak. **`FAColor.scale`
— the five-level ramp the functional check-in uses — must never touch anything in
this feature.**

A 3 on "how restorative did it feel" is an observation, not a failing grade. And
a ramp repeated down a list lets a member assemble a total with their own eye,
which is the score we are refusing to give. The design system already agrees, in
its own words: *signals are never the only carrier of status — pair with text or
icon (PRD §50)*.

Concretely: one accent for a selected value, neutral for the rest. No red→green.
No progress ring that implies a target. No "6 days in a row".

### 2.2 Three provenance layers stay three

**Member-reported · device-derived · FunctionAlps-derived.** They are shown
separately, and where they disagree the disagreement is the finding.

- **A device value never prefills a member field.** Not "tap to accept", not
  greyed-in, not as a placeholder. If the member is to answer, they answer.
- The watch's readings render in `FAGlassSurface(inset:)` — the pane this design
  system already reserves for Apple Health tiles — so the layer is legible before
  the label is read.
- **Never average the two.** Diary 6 h 03 and watch 6 h 44 are two numbers, and
  both are true.

The sample night in `SleepTrackPreviews.swift` carries `latencySeconds: 0` on
purpose. That is a value a real device really sends. Had we prefilled M03 from
it we would have written a false zero into a clinical record as the member's own
answer.

### 2.3 NULL, never 0

"Not sure" is an answer the diary deliberately offers on M03 and M05. It is
carried as `nil`, never as a sentinel, and it costs that one metric for that one
night — **never the night, and never the fortnight's coverage**.

A night counts toward the period when it can be placed on a timeline: all four
clock fields present (`MorningLog.hasTiming`). Everything else is per-metric.

### 2.4 Safety is deterministic and this app does not decide it

Red flags are raised by a rule engine from **structured fields only**. No model,
on device or off, decides whether a flag exists. This app may *render* a flag the
server raised; it may never create, clear or downgrade one.

Diary-side rules that exist today (server evaluates, app displays):

| Trigger | Result |
|---|---|
| ≥3 mornings at M09 ≥ 8, or ≥5 at M09 ≥ 7 | `DIARY_SEVERE_SLEEPINESS`, shown to the member, re-asks the drowsy-driving item |
| ≥2 nights tagged `breathing` in M11 | `DIARY_BREATHING_CONCERN` |
| ≥2 nights tagged `parasomnia` in M11 | `DIARY_PARASOMNIA_CONCERN` |

**The M11 option keys are a contract.** Copy may change; `breathing`,
`parasomnia`, `alcohol`, `medication`, `travel`, `nothing` may not.

A flag is never cleared by a later number improving. It is resolved by a named
human action, server side.

### 2.5 Nothing is shown before night 14

No running average, no trend line, no "your sleep so far". Seven nights cannot
separate a pattern from a bad week, and a number the member sees mid-track
changes how they sleep for the rest of it.

What may be shown mid-track: **counts**. Mornings logged, nights the watch
covered, free days covered. `SleepTrackProgressView` is built this way and says
why out loud — keep that copy, it is doing work.

---

## 3. The eleven fields

`SLP_ASSESS_M01`–`M11`. Ids are stable and appear in the UI beside each question
so a bug report can name the field.

| Id | Question | Type |
|---|---|---|
| M01 | Into bed | clock |
| M02 | Tried to sleep (lights out — not M01) | clock |
| M03 | How long to fall asleep | band → minutes, **or nil** |
| M04 | Times you remember waking | 0–5+, or nil |
| M05 | Awake in the night, added up | band → minutes, **or nil** |
| M06 | Final waking (after which sleep did not resume) | clock |
| M07 | Out of bed | clock |
| M08 | How restorative did it feel | 0–10 |
| M09 | How sleepy are you right now | 0–10 |
| M10 | The night overall | 0–10 |
| M11 | Anything unusual | multi-select, optional |

M01/M02 and M06/M07 are **two distinct pairs**. Reading in bed lives between M01
and M02; lying awake before getting up lives between M06 and M07. Collapsing
either pair destroys sleep efficiency and terminal wakefulness.

---

## 4. Reuse, do not reinvent

This repo already has most of what the feature needs.

**The clock selector exists.** `Features/Checkin/SleepInputsView.swift` is the
shipped bed/wake picker: `DatePicker(.compact)` on `.hourAndMinute`, bridged to
`"HH:mm"`. `MorningLogView` calls its statics rather than copying them:

```swift
SleepInputsView.date(from: "22:40")      // "HH:mm" → Date
SleepInputsView.string(from: date)       // Date → "HH:mm"
SleepInputsView.windowMinutes(bed:wake:) // (w - b + 1440) % 1440
```

`windowMinutes` is the correct **two-point** wrap. The diary needs the same idea
**chained across four points** (M01 → M02 → M06 → M07), each advanced to be at
least the previous. Do not reach for a fixed evening anchor: a single 18:00
anchor produces **negative durations for any bedtime before 18:00**, which is
exactly the shift worker the day classification exists to describe. The server's
`resolveSequence` is the general case; mirror it if you compute anything locally.

**The check-in already collects four of the eleven.** `SleepSpecials` carries
`bedTime · wakeTime · durationMin · latency · wakeCount`. So the morning log
extends a shipped habit rather than adding a ritual.

> **Decide before wiring:** while a track is running, the morning log should
> **replace** the functional check-in's sleep block, not run beside it. One
> morning ask, not two. The functional check-in is about *today* and belongs in
> the evening; the morning log is about *last night* and must happen on waking.

**HealthKit already gives real sleep timestamps.** `Core/Health/WearableCatalog.swift`
assembles samples into `SleepNight` with genuine `start`/`end` Dates, stages,
latency, interruptions and per-sample provenance (`SleepAssembler`, 3-hour session
gap, naps under 3 hours dropped).

This is better than the Thryve path the server was designed around, which has
daily scalars only. It does **not** reduce the need for the diary: the device's
`start` is when it *thinks* sleep began — it is neither M01 nor M02 — and no watch
will ever produce M08–M10.

**Components:** `FACard` (the one glass), `PillGroupView`/`PillButton`,
`FlowLayout`, `FATypography`, `FASpacing`, `FACornerRadius`, `FAButton`,
`FAGlassSurface(inset:)`.

---

## 5. What is drafted, and what is missing

```
Sources/Features/SleepTrack/
  SleepTrackModel.swift      SleepTrack · MorningLog · intent · protocol length
  SleepTrackOptions.swift    answer bands · ChoiceRow · ZeroToTenRow · SleepFieldLabel
  MorningLogView.swift       M01–M11 + the watch pane
  SleepTrackCards.swift      the four Home-card states + NightDots
  SleepTrackStartView.swift  the two doors in
  SleepTrackProgressView.swift  mid-fortnight
  SleepTrackPreviews.swift   sample data + four #Previews
```

### Still to do

1. **Make it compile.** Nothing here has seen a compiler. Expect API drift.
2. **A store.** `SleepTrackStore` (`@Observable`, in `Services/` beside
   `WearableService`) owning: the active track, today's log, the sync queue, and
   a `refresh()` that both `.task` and foreground re-entry call.
3. **Persistence.** §6.
4. **Offline.** The phone is frequently offline at 07:00. Writes queue locally
   and flush on connectivity; the UI shows a night as logged the moment the
   member saves, with a quiet pending marker until it lands. The web surface
   cannot do this, which is one reason the phone is the default.
5. **HealthKit join.** `WearableService.readSnapshot` already produces
   `SleepNight`. Pass last night's into `MorningLogView(night:)` and store its
   `sourceRecordId`/`sourceDeviceId` alongside the diary row as the **device**
   layer — never merged into member fields.
6. **A route.** The Home card is built but not placed. It belongs above the
   existing check-in card while a track is running.
7. **Notification.** One morning push. Not a streak reminder, not a nag — it
   fires once, and the copy is the ask, not encouragement.
8. **The 48-hour backfill.** `MorningLog.isBackfillable` exists. A recalled night
   is saved with `recallDelayMin` and marked lower-confidence, never discarded.
   One missed morning must not equal one lost night.

### Not yours

L1 (deep questionnaire), L3 (results) and L4 (protocol) live on MEMBERS web. The
app links out to them and shows read-only state. Do not rebuild them here.

---

## 6. Two surfaces, one track — the contract

**The database is the only source of truth.** Neither surface may assume it is
the only writer.

### The rows

`sleep_diary_night`, natural key **`(member_id, assessment_id, local_date)`**.

| Column | Note |
|---|---|
| `local_date` | the member's **own local date**, never a UTC date |
| `timezone` | IANA zone the member was in **for that night** |
| `m01_in_bed … m11_unusual` | the eleven, nullable |
| `logged_via` | `'ios'` \| `'web'` — which surface wrote it |
| `logged_at`, `recall_delay_min` | when, and how long after waking |
| `updated_at`, `updated_via` | last edit, and from where |

**`local_date` must come from the member's calendar, not `Date()` in UTC.** At
00:30 in Zurich a UTC date is yesterday. The old Expo app had this bug; do not
inherit it.

### Rules

1. **Always upsert** on the natural key. Never insert-only — the other surface
   may already hold the night.
2. **Last write wins**, inside the 48-hour correction window only.
3. **Never clobber silently.** If the row was last written by the *other*
   surface, say so before overwriting: *"You logged this on the web at 21:04.
   Replace it?"*
4. **Refetch on appear and on foreground.** A member who logged on their laptop
   must not be asked again on their phone.
5. **Show where a night came from.** Both surfaces render the other's state —
   *"logged at 07:12 on your phone"* appears on the web, and vice versa.
6. **One active track per member per pillar.** Two overlapping windows make
   coverage arithmetic and the baseline↔experiment comparison meaningless.

### Writes and RLS

`sleep_diary_night` is **member-owned** data, in the same class as
`patient_daily_checkins` — which this app already writes directly today. So both
surfaces write under the member's own session with self-scoped RLS: insert and
update own rows, for an active assessment, inside the correction window.

> This is a deliberate, narrow departure from the MEMBERS rule that the web app
> never writes clinical data. That rule protects **clinician-owned** tables. A
> member's own morning diary is not one, and routing it through a service-role
> server route would give the web surface more privilege than it needs, not less.
> Flag it in review rather than assuming it; the server team owns the policy.

Practitioner-only fields (`practitioner_message`, flag internals) are never
member-readable, on either surface.

### Who owns what

| | iOS | MEMBERS web |
|---|---|---|
| L1 questionnaire | link out | **primary** |
| **L2 morning log** | **primary** — push, HealthKit, offline | fallback, backfill, desktop |
| Wearable | **HealthKit, primary** | reads what synced |
| L3 results | read | **primary** |
| L4 protocol | adherence ticks | **primary** |

The web surface exists because the whole pillar otherwise sits behind app
installation plus fourteen consecutive mornings of retention — and without the
diary there is no timing data at all. It is the fallback, not the equal.

---

## 7. Copy rules

The language contract is a product requirement, not a tone preference.

**Use:** pattern · signal · trend · we are exploring · may be contributing ·
worth testing · appeared together · this device estimates · your reported sleep.

**Never:** caused · proved · diagnosed by your watch · cortisol · adrenal ·
your nervous system is dysregulated · low deep sleep · your sleep score.

Two specific bans, each forbidden in three separate places in the research:

- A recurring same-time awakening is **never** labelled cortisol, adrenal,
  hormonal or blood-sugar — not in the UI, not in a field name, not in a
  practitioner note.
- Night waking is **never** interpreted as hypoglycaemia.

And the platform never generates a medication taper, never advises stopping a
prescription, never suggests an extra overnight dose. It documents use and routes
to the prescriber.

---

## 8. The two doors, and why it matters clinically

A member starts a fortnight in one of two intents:

- **`.focus`** — they named a complaint.
- **`.baseline`** — nothing is obviously wrong; they want to see the pattern.

Same fourteen nights, same diary, **same safety screen**. Only the framing of the
opening question and the shape of the closing report differ.

That the safety screen is identical is the argument for the second door existing
at all. An asymptomatic member is precisely the person who would never book an
appointment about their sleep — so the optimisation track is the only route by
which they are ever screened for breathing during sleep, restless legs, or
sleepiness at the wheel.

Do not let `.baseline` become a lighter mode that skips the screen.

---

## 9. Done means

- It compiles, and `xcodegen generate` picks the files up.
- The four `#Preview`s render.
- No `FAColor.scale`, no ramp, no streak, no score anywhere in the feature.
- No device value reaches a member field, in any code path.
- "Not sure" round-trips as `nil` and loses only its own metric.
- A night logged on the web shows as logged here, without being re-asked.
- `local_date` is the member's local date on every write.
- Offline at 07:00 still logs, and flushes later.
