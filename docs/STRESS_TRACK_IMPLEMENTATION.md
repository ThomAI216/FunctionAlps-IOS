# Stress Track — implementation brief

**For the Swift coding agent working in this repo.** Read this before touching
`Sources/Features/StressTrack/` or the check-in. It is self-contained: you do not
need the CLINICAL wiki to build from it.

Status: **model, wire shapes, service and the check-in block drafted; nothing
compiled, nothing wired.** No Swift toolchain existed where they were written.
Every design-system and app identifier they use was verified by grep against this
repo (§10). Your first job is §9: wire, `cd FunctionAlps && xcodegen generate`,
build, and fix what the compiler finds.

Sources this brief follows, in order of authority:
`FunctionAlps-CLINICAL/clinical-dashboard/docs/wiki/four-pillars/09_STRESS_MENTAL_HEALTH_SCOPE.md`
(binding) · `10_STRESS_PILLAR_SPEC.md` §3 · migration
`205_four_pillars_stress.sql` (applied on CM OS 2026-09-25) · the engine in
`clinical-dashboard/lib/stress/` · the MEMBERS web mockup
`functionalps-members/src/app/devpreview/pillars/stress/checkin/page.tsx`, whose
wording and keys this app matches so one instrument reads the same on both
surfaces.

---

## 0. Read this section before anything else

**This feature does not build a daily form. One exists, it is good, and it is in
use: the check-in.** The Stress track **extends** it.

`Features/Checkin/` — `CheckinMomentView`, `CheckinMomentViewModel`,
`DimensionCardView` — plus `Services/CheckinService`, `Core/Checkin/CheckinEngine`
and `Models/Checkin.swift` are the daily check-in, and the track does not replace,
duplicate or fork any of it.

While a Stress track runs:

| | What happens |
|---|---|
| The morning / midday / evening check-in | **unchanged** — same screen, same sections, same `member_submit_checkin` write |
| Mood and calm (0–100) | **unchanged and not asked again** — the server reads them from `patient_checkin_moments` |
| `stress_score` | **unchanged: it stores CALMNESS, higher = calmer, never inverted.** This feature never reads, writes or relabels it |
| The check-in's own computed scores | **unchanged, and never read by the pillar** |
| Three items at the end of the **morning** check-in | **new** → `stress_diary_day` |
| Six items at the end of the **evening** check-in | **new** → the same row |
| Midday | nothing added |

If you find yourself writing a second daily screen, a second calm slider, a copy of
mood or calm into `stress_diary_day`, or anything that computes `100 − calm`: stop.
Something has gone wrong with the design, and it is worth raising rather than
building.

---

## 1. What this is

Pillar three — **Stress, Recovery & Connection**. Same arc as Sleep and Nutrition:
questionnaire → observed period → a profile of seven domains → 1–3 drivers → one
testable experiment → reassessment. Same refusals: no pillar score, layers that
never merge, clinical risk in its own card, associative language only.

| | | Where |
|---|---|---|
| **L1** | The questionnaire, once per cycle (61 items, conditional) | **MEMBERS web** — §7 |
| **L2** | **The observed period: 14 days by default (7 or 21), on the check-in** | **this app** (primary) + web |
| **L3** | Profile — 7 domains, state words, no score | server (`lib/stress`); web renders it |
| **L4** | Protocol — one hypothesis, 1–3 actions | MEMBERS web |
| **L5** | Reassessment | all |

**You are building the L2 additions only**: nine items, a service, and their place
in the check-in. Nothing here reads a result, a flag or a screener.

---

## 2. Rules you may not break

Each one is checkable in review, and each is a product defect if broken.

### 2.1 No score. Ever.

No stress score, no resilience score, no recovery score, no streak, no number
summarising a day, a domain or the pillar. The server's domains are a state word +
confidence + observations; this app shows none of them. `FAColor.scale` — the
check-in's five-level ramp — never touches this feature: one accent for the chosen
value, neutral for the rest. Nothing typed into the additions is ever shown back as
a figure.

**Enforcement you should keep:** none of the feature's types has a score field. If
`StressDiaryDay` or `StressCheckinDraft` grows one, the rule is already broken.

### 2.2 Calm is calm

`patient_checkin_moments.stress_score` stores **calmness** (0–100, higher =
calmer). `CheckinEngine` says so twice (`// stress = calmness`,
`// CALMNESS — never inverted`) and the RPC agrees. The pillar reads it as `calm`.
This app never inverts it, never labels a calm number "stress", and never copies it
into the sidecar. (§12 Q2 is about the check-in card that already shows it next to
the word "Stress".)

### 2.3 Three layers stay three

Member-reported · device-derived · FunctionAlps-derived. Apple Health HRV and
resting heart rate are a **device overlay** on the server, read by nothing in the
profile — **the wearable moves no domain**. So: no HealthKit value prefills,
suggests or replaces any of the nine items, and no device number appears in this
block. Where the two disagree, the server shows the disagreement; the phone does not
reconcile anything.

### 2.4 Clinical risk is not this app's

Flags are raised server-side by deterministic rules from structured fields — never
by a model, never by this app. The only priority-level rule in the pillar (chest
pain, fainting or severe breathlessness during stress episodes → medical review,
drivers withheld) lives in the **questionnaire**, on the web. This app creates no
flag, reads no flag (`pillar_safety_flag` has no member policy) and never renders a
"things to improve" list.

### 2.5 Mental health is a surface, handed to a person

Binding scope decision. On iOS, concretely:

- The two published screeners (GAD-2, PHQ-2) are **not shown in this app** (§7).
- **No screener total, item score, "positive/negative" or clinical label** ("anxiety",
  "depression") is ever displayed, stored locally, logged or sent to analytics.
- `pillar_instrument_result` is **never read and never written** by this app. It
  has no member policy by design; a read returns zero rows, which means "not
  visible to you" — **never** "negative".
- **No self-harm question, no violence-at-home / safe-at-home question, no support
  card, no crisis numbers** — anywhere in this feature.

### 2.6 Social connection is gentle, and never a priority

S9 is one yes/no about a conversation. Never a rating of anyone's relationships,
never "lonely", never a nudge. The server caps the social domain at `mixed` and
never makes it a driver; nothing here may frame it as something to fix.

### 2.7 Our words, associative only

FunctionAlps-original wording throughout. No PSS, WHO-5, UCLA, BRS, PSQI or ISI
item or name. Never "caused", "because", "your cortisol", "adrenal", "burnout",
"nervous system dysregulation". The nine items describe the day; they explain
nothing.

### 2.8 NULL, never 0 — and every item skippable

A skipped item costs that one metric on that one day, never the day. Tapping a
chosen answer again clears it. `nil` round-trips as SQL `NULL`, never a sentinel.

---

## 3. Scope

| iOS does | iOS does not |
|---|---|
| Show the nine additions inside the morning / evening check-in while a Stress track is active and today is in its window | Build a second daily form, a track home screen, or a results view |
| Prefill them from today's row (so a day answered on the web is shown, not re-asked) | Re-ask or copy mood / calm |
| Upsert one half of today's row per save, on the natural key | Write `day_type`, `day_modifiers` or `note` |
| Stamp `updated_via = 'ios'` (and `logged_via` / `logged_at` on the first write) | Compute any metric, coverage, association, domain state or driver |
| Hide S7 for members whose questionnaire never opened the work section | Read or display GAD-2 / PHQ-2, a flag, or an instrument result |
| Show "you last saved these on the web at …" when the web wrote the row | Start, stop or extend a track (web-first for now — §12 Q7) |
| | Send a push. The check-in's existing reminders are the only prompt |

---

## 4. The data contract

### 4.1 `stress_diary_day` — one row per member per assessment per local date

Natural key **`(patient_id, assessment_id, local_date)`** (unique index
`stress_diary_day_natural_key`). Columns, verified against the live CM OS schema and
against the server's own read (`STRESS_DAY_COLUMNS` in `lib/stress/db.ts`) — same
24 columns, same order as `StressDiaryDay.CodingKeys`:

| Column | Type | Item | Written by iOS |
|---|---|---|---|
| `id` | uuid | — | never |
| `patient_id` | uuid | — | every write (key) |
| `assessment_id` | uuid | — | every write (key) |
| `local_date` | date | — | every write (key) — the member's own date, §4.3 |
| `timezone` | text | — | every write — `calendar.timeZone.identifier` |
| `day_type` | text `obligation`\|`free` | — | **never** — §12 Q1 |
| `day_modifiers` | text[] NOT NULL `'{}'` | — | never |
| `am_recovered` | smallint 0–10 | **S1** | morning save |
| `am_unwell` | boolean | **S2** | morning save |
| `alcohol_last_evening` | boolean | **S3** | morning save |
| `pm_peak` | smallint 0–10 | **S4** | evening save |
| `pm_recovery_latency` | text, 7 values (§4.2) | **S5** | evening save |
| `pm_carryover` | smallint 0–10 | **S6** | evening save |
| `pm_work_detachment` | smallint 0–10 | **S7** follow-up | evening save — NULL unless "worked today" |
| `pm_restorative` | boolean | **S8** | evening save |
| `pm_restorative_types` | text[] NOT NULL `'{}'` | S8 follow-up | evening save — `[]` unless S8 = yes |
| `pm_restorative_effect` | smallint 0–10 | S8 follow-up | evening save — NULL unless S8 = yes (DB CHECK `stress_diary_day_effect_needs_action`) |
| `pm_meaningful_connection` | boolean | **S9** | evening save |
| `note` | text | — | **never** (the additions ask no free text) |
| `logged_via` | `ios`\|`web` | — | first write only |
| `logged_at` | timestamptz | — | first write only |
| `updated_via` | `ios`\|`web` | — | every write |
| `created_at`, `updated_at` | timestamptz | — | never (default / trigger) |

**Not columns, and never to be added:** mood, calm, `stress_score`, any score.

### 4.2 Enumerations — contracts; labels may change, values may not

**`pm_recovery_latency`** — exactly the seven values the CHECK constraint accepts.
Ordinal: the server ranks the first six 0–5 and summarises a **median band** —
never minutes, never an average. `no_stressor` is not a fast recovery; it is the
absence of the thing measured, and the server excludes it.

| Raw value | Swift case | Label | Rank (server) |
|---|---|---|---|
| `under_10m` | `.under10m` | Under 10 min | 0 |
| `10_30m` | `.from10to30m` | 10–30 min | 1 |
| `30_60m` | `.from30to60m` | 30–60 min | 2 |
| `1_3h` | `.from1to3h` | 1–3 hours | 3 |
| `over_3h` | `.over3h` | Over 3 hours | 4 |
| `never` | `.never` | Not yet today | 5 |
| `no_stressor` | `.noStressor` | Nothing really stressful today | excluded |

The app never computes a rank. `RecoveryLatencyBand.measured` is the six in order,
for display only.

**`pm_restorative_types`** — the MEMBERS web keys, verbatim and in its order (13);
they follow the questionnaire's `recovery_activities` keys wherever one exists:
`walking`, `outdoors`, `exercise`, `breathing`, `meditation`, `alone`, `family`,
`friends`, `creative`, `heat`, `sleep`, `screens`, `other`. `breathing` (*Slow
breathing or relaxation*) and `meditation` are two keys, as in the questionnaire —
merged, a member who meditated would read "Most often: breathing" in the profile.
The column has **no CHECK**, so the draft keeps
raw strings and **preserves a key it does not know** (one the web added later)
through an edit made here. §12 Q4: this list has no canonical home yet.

**`logged_via` / `updated_via`** — `'ios'` \| `'web'`. This app always sends `ios`.

### 4.3 Writes: an upsert of ONE half of the day

PostgREST `resolution=merge-duplicates` **writes every key in the body and leaves
every absent key alone.** So `StressDiaryWrite` (the only body this app sends):

1. carries the natural key and `timezone`;
2. carries **only its own half's columns, every one explicitly** — a skipped item
   is sent as JSON `null`, so clearing an answer really clears it;
3. carries **none of the other half's columns** — the morning save cannot null the
   evening, the evening cannot null the morning, and a half answered on the web
   survives a save of the other half here;
4. stores a follow-up only behind its "yes" (`Evening.stored…`), so "I didn't work
   today" writes `pm_work_detachment = NULL` (the same NULL a skip writes: a day off
   is not "switched off well") and "No" to S8 writes `[]` and `NULL`;
5. is **not sent at all** when the half is unchanged from what was loaded — so a
   member who only moved the calm slider does not re-stamp the web's answers.

`StressDiaryDay`'s synthesized `Encodable` omits nil keys and is therefore
**never** an upsert body — it would let a cleared answer silently survive.

**The local date is the member's own, never UTC**, and it is computed exactly as
the check-in computes its own `checkin_date` — `ISO8601.dayString(now(),
calendar:)`, at **save** time — because the server joins this row to that day's
evening moment (mood, calm) and morning moment (sleep duration) on it. One known
consequence, inherited from the check-in and kept on purpose so the join holds: an
evening check-in finished after midnight lands on the next date in both tables.

### 4.4 RLS, and what this app adds on top

Member policies (verified live): **select** own rows; **insert** and **update** own
rows **only while the assessment is `active`**. `pillar_instrument_result` has no
member policy at all; `pillar_safety_flag` neither.

Two things the policies do **not** check, which this app therefore checks itself:

- **That the assessment is a Stress one.** The policy checks `status = 'active'`,
  not `pillar = 'stress'`, so a member-session write could attach a row to a running
  Sleep window. The only guard on this path is the id the app sends: it comes from a
  query filtered on `pillar=eq.stress&status=eq.active`, and
  `StressTrackWindow(row:)` re-checks both (reported upstream — §12, engine notes).
- **That `local_date` is inside the window.** An assessment stays `active` until
  something closes it; the additions show only while `started_on ≤ today ≤ last
  day`, where the last day is exactly the engine's `stressAssessmentWindow`:
  `actual_end_on`, else `planned_end_on`, else `started_on + protocol_days − 1`.
  The server reads only rows inside that window, so a row written outside it would
  be stored and never used. "Day N of M" takes M from the same window, never from
  `protocol_days` alone, so it cannot read "Day 16 of 14".

A refusal (assessment closed mid-screen) arrives as `AppError.forbidden` (403). It is
handled, not assumed away — §5, §9 step 4.

### 4.5 What this app reads — and never reads

| Reads (own rows, member session) | Why |
|---|---|
| `pillar_assessment` — `id, pillar, status, protocol_days, started_on, planned_end_on, actual_end_on, timezone_default`, filtered `pillar=stress, status=active` | is a track running, and where today falls |
| `stress_diary_day` — today's row | prefill; provenance line |
| `pillar_questionnaire_response` — **only** `status` and two answer keys via JSON path: `stress_sources:answers->stress_sources`, `stress_goal:answers->stress_goal` | the S7 gate (§5) |

| Never reads | Why |
|---|---|
| `pillar_instrument_result` | staff-only by construction; the member never sees a screener result |
| `pillar_safety_flag` | staff-only; flags are the practitioner's |
| any other questionnaire answer, including `gad2_*`, `phq2_*` | nothing here needs them |

### 4.6 ⚠ The decoding trap

`JSON.decoder` (used by `PostgRESTClient.select` / `selectOne` / `rpc`) sets
`.convertFromSnakeCase`, which rewrites the JSON key `am_recovered` to
`amRecovered` **before** matching it against a CodingKey. The Stress wire types'
CodingKeys **are the column names** (`"am_recovered"`), so under that decoder every
optional column decodes as `nil` — an answered item indistinguishable from a
skipped one — and every required one throws.

So: read with `rest.selectRaw(...)` and decode with `StressWire.decode(...)` (a plain
`JSONDecoder`, no key strategy, timestamps kept as strings). Write with
`snakeCase: false`. §11 has the regression test to watch fail.

---

## 5. Gating — when the additions appear

The block renders only when **all** of these hold, evaluated once when the check-in
screen loads (`StressTrackService.load`) — **after** the check-in's own prefill has
finished, never before it, so the track adds no round trip in front of the check-in
(§9 step 4):

1. the moment is **morning** (S1–S3) or **evening** (S4–S9) — never midday;
2. the member has an **active Stress** assessment (`pillar = 'stress'`, `status =
   'active'`; at most one exists — partial unique index);
3. **today is inside its window** — `StressTrackWindow.contains(today)`;
4. **today's row was read successfully** (prefill).

Anything else — no track, a closed window, a read that failed — and the check-in
renders **exactly as it does today**. A failed read fails **closed** (no block),
because an empty block over a row the web already filled would invite an overwrite.
The track must never block, slow or break the check-in.

**S7 ("Did you work today?")** additionally shows only when the questionnaire's work
section opened — the mirror of `WORK_TRIGGER` in `lib/stress/questionnaire.ts`:
`stress_sources` contains `workload`, `work_control`, `work_relationships` or
`business`, or `stress_goal` contains `work_follows_me` (`StressWorkGate`). The
server's results then say "Not asked — you did not mention work", which stays true.
This gate fails **open**: a questionnaire that cannot be read or is not yet submitted
shows S7. **If `WORK_TRIGGER` changes, change `StressWorkGate`.**

At save, the window is checked again with the date taken at save time; outside it,
nothing is written for the track (`.windowClosed`) and the member is **told**, with
the same card and the same way out as an RLS refusal — "Save my check-in without
these" (§9 steps 4–5). Typed answers are never dropped silently.

---

## 6. UI spec for the additions

`StressCheckinAdditionsView(context:draft:)` — a block, not a screen. It sits at the
**end** of the check-in, after every existing section (in the morning, after the
"Tell us a bit more" expander) and before the error card and Save. The one Save
button saves both.

**Frame.** A thin divider labelled *added while your track runs*, then one `FACard`
(the one glass — no nested glass inside it). Header: eyebrow *For your 14-day stress
track* · *Day 6 of 14* (a count, never a conclusion); then *Three quick ones · about
ten seconds* (morning) or *A few more · under a minute* (evening); then *Skip any you
like. These go away by themselves after day 14.* When the web last wrote the row: *You
last saved these on the web at 21:04. Change anything that's off.*

**Items.** Each carries its stable field id (S1…S9) beside the question — the Sleep
track's M01…M11 idiom, so a bug report can name the field.

| Id | When | Question | Control | Stored |
|---|---|---|---|---|
| S1 | morning | How recovered do you feel this morning? | 0–10 · *Not at all* … *Completely* | `am_recovered` |
| S2 | morning | Are you unwell or feverish today? — *If you are, we keep today. We just won't compare it with your other days.* | Yes / No | `am_unwell` — a confounder, never a flag |
| S3 | morning | Any alcohol last evening? — *Just yes or no, no amounts.* | Yes / No | `alcohol_last_evening` |
| S4 | evening | Today, at its most stressful — how intense did it get? | 0–10 · *Hardly at all* … *As intense as it gets* | `pm_peak` |
| S5 | evening | After the hardest moment, how long until you felt close to normal? | six band chips; below, apart and muted, *Nothing really stressful today* | `pm_recovery_latency` |
| S6 | evening | How much are you still carrying right now? — *Whatever from today is still with you.* | 0–10 · *Nothing* … *A great deal* | `pm_carryover` |
| S7 | evening, if §5 gate | Did you work today? — *Whatever counts as work for you.* | Yes / *I didn't work today* (muted) | not stored |
| ↳ | if Yes | How well have you switched off from it since? | 0–10 · *Not at all, still in it* … *Completely* | `pm_work_detachment` |
| S8 | evening | Did you do anything today on purpose to recharge? — *Anything deliberate counts, even ten quiet minutes.* | Yes / No | `pm_restorative` |
| ↳ | if Yes | What was it? | multi-select chips (§4.2) | `pm_restorative_types` |
| ↳ | if Yes | How much did it help, in the moment? | 0–10 · *Not at all* … *A lot* | `pm_restorative_effect` |
| S9 | evening | Did you have at least one conversation today that felt meaningful? — *In person, on the phone, or a message that turned into a real exchange. Whatever counted for you.* | Yes / No | `pm_meaningful_connection` |

**Controls.** Chips are the check-in's own `PillButton` in a `FlowLayout`, so the
block feels like the rest of the check-in. Single choice, **tap the chosen one again
to clear it**. The 0–10 row is a private `StressScaleRow`: one accent (`forestSoft`)
for the chosen value, a hairline for the rest, tap again to clear — not the Sleep
track's `ZeroToTenRow`, which cannot clear, and never `FAColor.scale`. Answers that
answer a different question (*no stressor*, *didn't work*) are drawn in the neutral
hue, never as a peer of the measured options. Answering anything but "yes" to S7 or
S8 clears its follow-ups immediately, as the web does.

**Why yes/no where pills exist.** The check-in already has tap-if-true pills
("Alcohol", "A walk outside", "Time with friends"). A pill nobody tapped is not a
no. S2, S3, S8 and S9 are yes/no so that a no is recorded as a no.

**Nothing shown back.** No total, no "good recovery today", no colour that grades
an answer, no comparison with yesterday. Mid-track the member sees a day count and
nothing else.

**Accessibility.** Dynamic Type through `FATypography` (`relativeTo:`); each
question is a header; each 0–10 button has its number as label and `.isSelected`
when chosen; selection is carried by weight and fill, never by colour alone; the
field ids are hidden from VoiceOver.

**Copy.** English defaults come from spec §3 and the MEMBERS mockup, verbatim. Every
string goes through `String(localized:defaultValue:)` under `stressTrack.*` keys; add
them to `Resources/Localizable.xcstrings` with French from the practice — not
machine-translated (§12 Q5).

---

## 7. The questionnaire (L1) on iOS — web-first, and why

**Decision in this draft: the L1 questionnaire is answered on the MEMBERS web. This
app does not render it.** At most, a later slice adds a card that opens the web
questionnaire (`openURL`, as `MemberGateView` does for request-access); that card is
not drafted (§12 Q7).

Why not native:

1. **One definition.** The questions, branches, scorer and in-form sentences are
   data in `clinical-dashboard/lib/stress/questionnaire.ts`, and MEMBERS carries a
   byte-identical copy that `diff` proves. A Swift port would be a third copy that
   nothing can diff.
2. **Published screeners, verbatim.** Section 11 is GAD-2 and PHQ-2 exactly as
   published — the publisher's stems, items, 0–3 response set and attribution, and
   the **publisher's own French translation**, never ours. Keeping that exact is a
   web-only job for now.
3. **Instrument results are written server-side only.** On submit, the engine
   scores each screen (`scoreScreener`: both items or nothing — a partial screen is
   **not** scored), writes `pillar_instrument_result` under the service role and
   raises flags. **This app never writes `pillar_instrument_result`** — there is no
   member policy, so it could not, and it must not try — and never reads it.

**The GAD-2 / PHQ-2 score is never shown to the member, on any surface.** When a
screen is positive, the member reads — in the web form, straight after the four
items — one note, whatever the number of positive screens. Its **only** source is
`SCREEN_POSITIVE_NOTE` in `lib/stress/questionnaire.ts`, built on the one constant
`PRACTITIONER_REVIEW_WINDOW` (`'within two working days'`):

> Thank you for answering these. Some of your answers suggest it could help to talk
> this through with someone. Your practitioner will look at them within two working
> days and raise it with you. The rest of your assessment carries on as normal.

No score, no phone number, no label. The practitioner gets `ANXIETY_SCREEN_POSITIVE`
/ `MOOD_SCREEN_POSITIVE` at `clinician_review` — never higher — and the pillar
continues. **This app shows none of this and holds no copy of the note.** If L1 ever
goes native, the note is taken from that constant (never retyped), the screeners use
the publisher's text and translation, results stay server-written, and none of it is
cached on the device.

---

## 8. Deliberately NOT built

- **No score** of any kind — stress, resilience, recovery, calm, day or pillar.
- **No second daily form**, no second calm or mood input, no inversion of calm.
- **No screener on the phone**, no screener result, no "positive" state, no clinical
  label.
- **No self-harm item, no harm-to-others item, no safe-at-home item.**
- **No support card, no crisis numbers, no helpline links.**
- **No burnout wording or items** — work detachment only.
- **No wearable anything** in this block — no HRV, no "stress level" from a watch,
  no prefill.
- **No streak, no nag, no extra push.** The check-in's reminders are the only prompt.
- **No results, drivers or protocol screens** — web.
- **No offline queue.** The check-in itself has none; the additions follow it.
  (The Sleep brief's queue, if built, should cover both.)
- **No free-text note** in the additions, so nothing here raises `FREE_TEXT_UNREAD`.

---

## 9. Wiring — exact steps into the existing files

Order matters; each step compiles on its own.

### Step 1 — move the wire file (repo rule 2)

`git mv Sources/Features/StressTrack/StressDiaryWire.swift
Sources/Core/API/StressTrackWire.swift`. It spells column names, and only
`Core/API/*` may. Nothing else changes; nothing depends on its location.

### Step 2 — `Core/API/SupabaseBackend.swift`: conform to `StressTrackBackend`

Put this **in `SupabaseBackend.swift` itself** — `rest` is `private`, and a `private`
member is reachable from an extension only in the same file. `StressTrackBackend` is
a separate protocol on purpose: `FunctionAlpsBackend` does not change, so the test
doubles `StubBackend` and `RecordingBackend` need nothing.

```swift
// MARK: Stress track (pillar_assessment · stress_diary_day · pillar_questionnaire_response) — migration 205
// Decoded with StressWire, NEVER JSON.decode: the CodingKeys are the column names (brief §4.6).
extension SupabaseBackend: StressTrackBackend {
    func activeStressAssessment(patientId: String) async throws -> StressAssessmentRow? {
        let data = try await rest.selectRaw("pillar_assessment", query: [
            PG.select(StressAssessmentRow.columns),
            PG.eq("patient_id", patientId),
            PG.eq("pillar", StressAssessmentRow.stressPillar),
            PG.eq("status", StressAssessmentRow.activeStatus),
            PG.limit(1),
        ])
        return try StressWire.decode([StressAssessmentRow].self, from: data).first
    }

    func stressDiaryDay(patientId: String, assessmentId: String, localDate: String) async throws -> StressDiaryDay? {
        let data = try await rest.selectRaw("stress_diary_day", query: [
            PG.select(StressDiaryDay.columns),
            PG.eq("patient_id", patientId),
            PG.eq("assessment_id", assessmentId),
            PG.eq("local_date", localDate),
            PG.limit(1),
        ])
        return try StressWire.decode([StressDiaryDay].self, from: data).first
    }

    /// One half of one day (brief §4.3). An RLS refusal is a 403 → AppError.forbidden.
    func upsertStressDiaryDay(_ write: StressDiaryWrite) async throws {
        try await rest.upsert("stress_diary_day", onConflict: StressDiaryWrite.naturalKey, body: write, snakeCase: false)
    }

    func stressQuestionnaireWork(assessmentId: String) async throws -> StressQuestionnaireWorkRow? {
        let data = try await rest.selectRaw("pillar_questionnaire_response", query: [
            PG.select(StressQuestionnaireWorkRow.select),
            PG.eq("assessment_id", assessmentId),
            PG.limit(1),
        ])
        return try StressWire.decode([StressQuestionnaireWorkRow].self, from: data).first
    }
}
```

`rest.upsert` sends `return=minimal`. An `INSERT … ON CONFLICT DO UPDATE` under RLS
either writes or raises (a refused existing row is an error, not a silent skip), so
there is no zero-rows-as-success trap on this path. If the team wants parity with the
CLINICAL rule (every write asks for its rows back), add an `upsertReturning` beside
`updateReturning` in `PostgRESTClient` and treat zero rows as a failure.

### Step 3 — `App/AppDependencies.swift`

```swift
let stressTrack: StressTrackService
// in init, beside `self.checkins = CheckinService(backend: backend)` — `backend` is still
// the concrete SupabaseBackend there, before it is stored as `any FunctionAlpsBackend`:
self.stressTrack = StressTrackService(backend: backend)
```

### Step 4 — `Features/Checkin/CheckinMomentViewModel.swift`

Add state and a **defaulted** init parameter, so no existing call site breaks:

```swift
private let stressTrack: StressTrackService?
private(set) var stressContext: StressCheckinContext?
var stressDraft: StressCheckinDraft?
var stressSaveError: String?

init(slot: MomentSlot, checkins: CheckinService, members: MemberService, auth: AuthService,
     wearables: WearableService? = nil, stressTrack: StressTrackService? = nil) {
    // … existing assignments …
    self.stressTrack = stressTrack
}
```

The track loads **after** `prefill()`, never inside it. Putting it in front of
`checkins.todayMoments` would hold the check-in's own prefill behind up to three
more round trips (assessment, today's row, questionnaire) for every member, track
or not — and the screen is already visible and editable while prefill runs, so a
longer prefill widens the window in which an early answer is overwritten by it.
`prefill()` gains one line: it remembers the patient id it already fetched, so the
track does not call `currentMember()` (a network RPC) a second time.

```swift
private var patientId: String?        // ← new, beside the other private state

func prefill() async {
    do {
        let member = try await members.currentMember()
        patientId = member.patientId  // ← new; the only change inside prefill()
        let moments = try await checkins.todayMoments(patientId: member.patientId)
        // … the rest of the do block and both catch blocks: unchanged …
    }
}

/// Called by the view AFTER prefill() (step 5). The track never blocks, slows or
/// breaks the check-in: any failure here just means no block.
func loadStressTrack() async {
    guard let stressTrack, let patientId else { return }
    do {
        guard let context = try await stressTrack.load(patientId: patientId, slot: slot) else { return }
        stressContext = context
        stressDraft = context.original
    } catch let error as AppError {
        Log.error(error, in: Log.data, context: "stressTrack.prefill")
    } catch {
        Log.data.error("stressTrack.prefill: \(String(describing: error), privacy: .public)")
    }
}
```

In `save()`, write the sidecar **first**, then the check-in. The order is
deliberate: the sidecar upsert is idempotent, but `member_submit_checkin` appends
`nb_checkin_events` on every call — so if the check-in went first and the sidecar
failed, the member's retry would append the check-in's events twice.

Three things the save must also do:

- **`.saved` → rebase the context** (`context.rebased(on:)`). If the check-in then
  fails and the member changes a track answer back before retrying, the retry must
  compare against what was just WRITTEN, or the change reads as "unchanged" and
  never reaches the server. Replace only the context, never `stressDraft` — the
  member may be editing it.
- **`.windowClosed` → say so.** Same card, same way out as an RLS refusal. Dropping
  the answers and saving the check-in anyway would lose them silently.
- **Only user-safe copy on screen.** `AppError.validation` carries PostgREST's raw
  message (a CHECK violation names the table and the constraint), and a non-`AppError`
  is a Swift description. The member sees fixed copy; the detail goes to the log, and
  to the screen only under `BuildInfo.showsTechnicalDetails`, as the check-in's own
  error card does.

```swift
var stressSaveDetail: String?        // ← new: technical detail, shown only to builds that show it

func save() async -> Bool {
    saveError = nil
    stressSaveError = nil
    stressSaveDetail = nil
    isSaving = true
    defer { isSaving = false }
    do {
        let member = try await members.currentMember()
        if let stressTrack, let context = stressContext, let draft = stressDraft {
            do {
                switch try await stressTrack.save(patientId: member.patientId, context: context, draft: draft) {
                case .saved:
                    stressContext = context.rebased(on: draft)
                case .nothingToSave:
                    break
                case .windowClosed:
                    stressSaveError = Self.stressTrackEnded
                    return false
                }
            } catch let error as AppError {
                Log.error(error, in: Log.data, context: "stressTrack.save")
                if case .unauthorized = error { await auth.handleUnauthorized(); return false }
                switch error {
                case .forbidden: stressSaveError = Self.stressTrackEnded
                case .offline: stressSaveError = error.userMessage
                default: stressSaveError = Self.stressTrackRetry
                }
                stressSaveDetail = error.debugDescription
                return false
            } catch {
                Log.data.error("stressTrack.save: \(String(describing: error), privacy: .public)")
                stressSaveError = Self.stressTrackRetry
                stressSaveDetail = String(describing: error)
                return false
            }
        }
        _ = try await checkins.save(slot: slot, answers: answers, catalogPills: catalogPills, patientId: member.patientId)
        return true
    } catch let error as AppError {
        // … unchanged …
    }
}

private static var stressTrackEnded: String {
    String(localized: "stressTrack.save.closed", defaultValue: "Your stress track has ended, so today’s track answers can’t be saved. Your check-in can still be saved.")
}

private static var stressTrackRetry: String {
    String(localized: "stressTrack.save.retry", defaultValue: "Your answers are still here · tap Save to try again, or save your check-in without them.")
}

/// The member's way past a track answer that will not save. Nothing is lost silently,
/// and the track never holds the check-in hostage.
func saveWithoutTrack() async -> Bool {
    stressContext = nil
    stressDraft = nil
    return await save()
}
```

Note: when the member answered only the track items, `checkins.save` returns `nil`
(nothing to send for the check-in) and the sidecar is still written. That is
correct — the check-in's "nothing answered → nothing sent" guard is unchanged.

### Step 5 — `Features/Checkin/CheckinMomentView.swift`

Pass the service where the view model is built, and load the track **after** the
check-in's own prefill (step 4 says why):

```swift
let m = CheckinMomentViewModel(slot: slot, checkins: dependencies.checkins, members: dependencies.members,
                               auth: dependencies.auth, wearables: dependencies.wearables,
                               stressTrack: dependencies.stressTrack)
model = m
await m.prefill()
await m.loadStressTrack()   // ← new: after, never before
```

The block therefore appears a moment after the check-in's answers. A Save tapped
before it appears saves the check-in alone, which is correct.

In `CheckinMomentScreen.body`, **after** the `moreSections` block and **before**
`if let error = model.saveError`:

```swift
if let context = model.stressContext {
    StressCheckinAdditionsView(
        context: context,
        draft: Binding(get: { model.stressDraft ?? context.original }, set: { model.stressDraft = $0 })
    )
}

if let stressError = model.stressSaveError {
    FACard {
        VStack(alignment: .leading, spacing: FASpacing.sm) {
            Text(String(localized: "stressTrack.save.failed", defaultValue: "Your track answers didn’t save"))
                .font(FATypography.headline).foregroundStyle(FAColor.danger)
            Text(stressError).font(FATypography.caption).foregroundStyle(FAColor.inkSecondary)
            if BuildInfo.showsTechnicalDetails, let detail = model.stressSaveDetail {
                Text(detail).font(FATypography.caption).foregroundStyle(FAColor.inkMuted)
            }
            // isLoading disables it while a save runs: a double tap would submit the
            // check-in twice, and member_submit_checkin appends events on every call.
            FAButton(title: String(localized: "stressTrack.save.without", defaultValue: "Save my check-in without these"), style: .secondary, isLoading: model.isSaving) {
                Task { if await model.saveWithoutTrack() { onSaved() } }
            }
        }
    }
}
```

### Step 6 — `Models/Checkin.swift`, `Core/Checkin/CheckinEngine.swift`, `Core/Checkin/FunctionalSchema.swift`, `Services/CheckinService.swift`: **no change**

This is a wiring instruction, not an omission:

- `CheckinMoment.stressScore` stays calmness; `DimKey.stress` and its `calm` slider
  stay as they are. Do **not** add the nine items to `CheckinMoment`, `DimAnswers`,
  `answersJSON` or the `member_submit_checkin` payload — the sidecar is its own
  table with its own RLS, written by its own call.
- `CheckinEngine.momentHasContent` is not taught about the additions: it guards the
  check-in's write, and the sidecar has its own "unchanged → nothing sent" guard.
- The check-in's reminders (`NotificationService.momentDone`) are unchanged.

### Step 7 — generate and build

`cd FunctionAlps && xcodegen generate` (the four new files are picked up from
`Sources/` — no `project.yml` edit), then build through the `iOS` workflow and fix
what the compiler finds. Add the `stressTrack.*` keys to
`Resources/Localizable.xcstrings`.

---

## 10. What is drafted, and what is missing

```
Sources/Features/StressTrack/
  StressTrackModel.swift            StressDiaryPart · RecoveryLatencyBand (7) · RestorativeType (13)
                                    StressSurface · StressCheckinDraft (Morning / Evening)
                                    StressTrackWindow · StressDays · StressWorkGate
  StressDiaryWire.swift             ⚠ → Core/API (step 1). StressWire (the decoder) · StressDiaryDay
                                    (Codable, CodingKeys = the 24 columns) · StressDiaryWrite (one half,
                                    explicit nulls) · StressAssessmentRow · StressQuestionnaireWorkRow
  StressTrackService.swift          StressTrackBackend (4 calls) · StressCheckinContext (+ rebased(on:))
                                    StressSaveOutcome · StressTrackService (load / save — the upsert)
  StressCheckinAdditionsView.swift  the block (S1–S9) + three #Previews
```

**Identifiers the drafts use that are not SwiftUI/Foundation standard — each
verified to exist in this repo by grep:** `FACard` · `FATypography.sans(_:_:relativeTo:)`,
`.Weight` (`.regular`/`.medium`/`.semibold`), `.label`, `.caption` · `FAColor.forestSoft`,
`.ink`, `.inkSecondary`, `.inkMuted`, `.cream`, `.separator` · `FASpacing.sm`, `.md`,
`.navBarClearance` · `PillButton(label:hue:on:action:)` · `FlowLayout(spacing:)` ·
`MomentSlot` (`.morning`/`.midday`/`.evening`) · `ISO8601.dayString(_:calendar:)`,
`.parse(_:)`, `.string(_:)` · `AppError.decoding(detail:)` · `View.faWall()`. The
wiring snippets add: `PostgRESTClient.selectRaw`, `.upsert(_:onConflict:body:snakeCase:)`,
`PG.select/eq/limit`, `AppDependencies`, `Log.error(_:in:context:)`, `Log.data`,
`AuthService.handleUnauthorized()`, `FAButton(title:style:isLoading:action:)` with `.secondary`,
`FAColor.danger`, `FATypography.headline`, `BuildInfo.showsTechnicalDetails`,
`AppError.debugDescription` — all present today. An adversarial audit (2026-09-25)
re-proved every one of them by grep, with its signature and `file:line`, and diffed
the CodingKeys, the latency values and the restorative keys against the migration,
the engine and the MEMBERS mockup. No compiler has seen these files yet.

No new type name collides with an existing declaration (checked).

**Still to do, and not yours to skip:** steps 1–7; the tests in §11; French copy.
**Not yours:** L1, L3, L4, flags, screeners — all web and server.

---

## 11. Done means — acceptance checks

**Build**

- `xcodegen generate` picks the files up; the project builds; the three `#Preview`s
  render (morning, evening, evening without S7).

**Behaviour**

- With no active Stress assessment, the morning, midday and evening check-ins are
  pixel-identical to today. Midday never shows the block.
- With one, the morning shows S1–S3 and the evening S4–S9, at the end, after every
  existing section; the day count reads "Day N of 14" — M is the window's own length
  (`StressTrackWindow.dayCount`), so a planned end that differs from the protocol
  never reads "Day 16 of 14".
- Outside the window (day 15 while the assessment is still `active`), no block.
- A member whose questionnaire never named work sees no S7; one whose questionnaire
  is unreadable or unsubmitted does.
- Every item can be skipped; a chosen answer tapped again clears; a cleared answer
  on an edited day is stored as `NULL`.
- "I didn't work today" and "No" to S8 hide and clear their follow-ups.
- A day answered on the web is prefilled here with the provenance line, and saving
  the calm slider alone does not rewrite it.
- The morning save leaves every `pm_*` column untouched; the evening save leaves
  every `am_*` column untouched.
- A save after the window closed mid-screen writes nothing for the track, says so,
  and still saves the check-in via "Save my check-in without these".

**Tests to add (Swift Testing, beside `CheckinBackendTests`)** — each watched to
**fail** once before it counts:

1. *Morning body* — `StressDiaryWrite(part: .morning, …)` encodes exactly
   `patient_id, assessment_id, local_date, timezone, am_recovered, am_unwell,
   alcohol_last_evening, updated_via` (+ `logged_via, logged_at` when first), a nil
   answer as `NSNull`, and **no** `pm_*` key. Mutant: switch
   `encodeExplicit` to `encodeIfPresent`.
2. *Evening body* — no `am_*` key; `restorative = false` → `pm_restorative_types = []`
   and `pm_restorative_effect = null`; `workedToday = false` → `pm_work_detachment =
   null` even when the screen still holds a number.
3. *Decoding trap* — a real row decodes through `StressWire`; the same bytes through
   `JSON.decode` do **not** round-trip (`amRecovered` nil or a throw). This test is
   the reason §4.6 exists.
4. *Service* — midday → nil; closed window → nil; unchanged half → `.nothingToSave`
   and no request; the date is taken at save time with the injected clock; an
   assessment with `actual_end_on` set ends its window there (engine parity).
   *Rebase* — save S4 = 7 (`.saved`), rebase, set S4 back to nil, save again → a
   request carrying `pm_peak: null` and no `logged_via`. Mutant: use the pre-save
   context for the second save → `.nothingToSave`, the stale 7 survives.
5. *Gate* — `StressWorkGate` against every `WORK_TRIGGER` branch, plus nil and
   `in_progress` → shows.
6. *No score* — reflect over `StressDiaryDay` and `StressCheckinDraft`: no property
   name contains `score`, `calm`, `mood` or `stress`.
7. *Contract* — `StressDiaryDay.columns` equals the server's `STRESS_DAY_COLUMNS`
   string; `RecoveryLatencyBand.allCases.map(\.rawValue)` equals the migration's
   seven, in order; `RestorativeType.allCases.map(\.rawValue)` equals the MEMBERS
   web list (13, `meditation` included). (All three were checked by script in the
   audit; the tests keep them true.)

**Scope**

- No use of `FAColor.scale` (the doc comments name it only to forbid it), no ramp,
  no number shown back, no screener, no flag, no instrument result, no crisis copy
  anywhere in `Features/StressTrack/`.
- `grep -rn "100 -\|100-" Sources/Features/StressTrack` finds nothing.
- No raw technical text on screen: the track's error card shows fixed copy, and
  PostgREST's message only under `BuildInfo.showsTechnicalDetails`.

---

## 12. Open questions for Thomas

1. **Day type is never collected.** Spec §3's nine items do not include
   obligation/free, and neither does the web check-in. The engine needs it: `high`
   coverage requires ≥2 free and ≥2 obligation days, and the `free_vs_obligation_calm`
   pattern needs it on every day. As built, high coverage is unreachable and that
   pattern never evaluates. Options: (a) a tenth item, the shared "Work or obligation
   / A free day" chip the Nutrition day-close uses; (b) derive it server-side from S7
   (not equivalent: an obligation is not always work); (c) read it from a concurrent
   Sleep or Nutrition diary. Recommendation: (a), evening only.
2. **The calm card already reads as a stress score.** `DimensionCardView` titles the
   calm dimension "Stress" (`dim.stress`) and prints the 0–100 calmness beside it on
   the ramp — so a member reads "Stress 72" as high stress. That contradicts "calm
   is calm" and "no stress score". Relabel the card "Calm" (or hide its number),
   at least while a Stress track runs? Pre-existing; the web mockup raised it too.
3. **S7 for everyone, or only when work was named?** Drafted: only when
   `WORK_TRIGGER` opened the work section (fail-open). The alternative asks every
   member and lets "I didn't work today" carry non-workers — one extra tap a day, and
   a worker who never named work as a source would still get the domain.
4. **Restorative keys have no canonical home.** They live only in the MEMBERS mockup;
   the column has no CHECK. Promote them to `lib/stress` (next to
   `RECOVERY_LATENCY_BANDS`) so both surfaces can be asserted against one list.
5. **Wording.** S4/S5 follow the web mockup ("Today, at its most stressful — …"), not
   the spec's shorthand. The rank-5 band now reads *Not yet today* on both surfaces
   (the web changed it; this app followed). The web mockup is still being edited, so
   the two lists can drift again until Q4 gives them one home. French from the
   practice.
6. **After midnight.** An evening check-in saved at 00:20 lands on the next date in
   both tables (inherited from the check-in, kept so the join holds). Acceptable for
   v1?
7. **The door in.** L1 is web-first here. Which MEMBERS route should the app open once
   it exists (today there is only `devpreview`), and should the app show a "start
   your stress track" card at all, or only the additions?
8. **`logged_via` meaning.** This app treats it as the first writer and
   `updated_via` as the last. The server's `sidecarPayload` overwrites both on every
   write (engine note 1 below). One meaning for both surfaces, please.
9. **Two tracks at once.** A member running Sleep and Stress together gets the Sleep
   morning log and S1–S3 on the same morning. Allowed, staggered, or one at a time?
10. **Apple Health reaches an association through the check-in.** The engine reads
   the morning moment's `sleep_duration_min` for `short_sleep_vs_morning_recovery`,
   and the check-in prefills that field from Apple Health (`applyHealthNight`) and
   stores no trace that it did. A device estimate the member did not touch is then
   read as member-reported — the layer rule says the wearable moves nothing. Not this
   feature's code and not changed here: should the check-in record the prefill's
   provenance, or should the engine stop reading sleep duration from it?

### Engine and schema notes (reported, not edited)

1. `lib/stress/db.ts` `sidecarPayload` (lines ~844–846) sets `logged_via` and
   `logged_at` on **every** write, so a row first logged on the phone and edited on
   the web reads `logged_via = 'web'` with the edit time: first-logger provenance and
   first-log time are lost. Likely unintended given the sibling briefs' contract.
2. **Resolved since drafting.** `lib/stress/db.ts` `getStressDiaryDays` now bounds
   `stress_diary_day` to the window (`gte`/`lte` on `local_date`, and scopes by
   `patient_id`), as it does the check-in moments. What it drafted against: it read
   `stress_diary_day` by `assessment_id` with **no `local_date` window filter**. A
   sidecar row outside the window (possible — see 3) would have become an extra
   day in `assembleStressDays` and could have counted toward coverage. This app's
   own window check stays (§4.4): it keeps such a row from being written at all.
3. Migration 205 (and 203/204 alike): the member insert/update policies check that
   the assessment is `active` but **not that it is a Stress one**, and do not bound
   `local_date`; the update `WITH CHECK` checks only ownership, so an update could
   move a row to another of the member's assessments. The server write path
   (`requireActiveStressAssessment`) checks the pillar; the member-session path this
   app uses does not. Verified against the live policies on CM OS.
