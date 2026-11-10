# Roadmap: signal explanations, the influence map and the action engine

Status: **owner priorities recorded 2026-11-10 (Thomas).** This page is a roadmap and a brief, not a spec. It
captures what the owner said, what already exists, and ready-to-paste prompts for the sessions that will build it.
Nothing here is built yet beyond the "What exists today" section.

## 1. Priorities (owner, 2026-11-10)

| # | Item | Owner's weight | One line |
|---|---|---|---|
| **P0** | Per-signal curated, science-backed explanation + **influence map** | "Super mega important", the next feature | For each functional check-in signal (Sleep, Energy, Focus, Mood, Stress, Digestion, and the Functional score): what it is, what it feels like, and above all what it is influenced by. Every signal linked to the others and to behaviours. |
| **P1** | "What is this influenced by" on every card | Called P1 first, then "even P0": **top priority together with P0** | A short explanation on each functional check-in card (check-in screen, Trends rows, detail pages), linking to the P0 page. **Ship this first, as the first slice of P0.** |
| **P2** | Automatic action engine | "A big chunk of work for later, but very important" | From each signal's trends, propose preferred actions to try, then measure whether they worked (before/after on the signal, adherence-aware). |
| Cadence | Clinician review every 2 weeks | Owner request | A trigger on the clinician dashboard to review each member's data and give actions. Later, an AI drafts it, the clinician approves. |
| Base | Patterns ecosystem | Shipped 2026-11-10 | Patterns computed nightly, shown to members only after clinician validation. |

Order of work: **P1 card-level explanation (first slice of P0) -> P0 full pages and influence map -> clinician 2-week
review -> P2 engine.** The content track (section 3) can run in parallel with the code, because the code only renders it.

## 2. What the owner said, in his words

### P0, per signal
For EACH functional check-in signal (Sleep, Energy, Focus, Mood, Stress, Digestion, and the Functional score), a
curated, researched, science-backed explanation shown on its card and its page: **what it is, what it feels like, and
above all what it is influenced by.**

His example, to keep in spirit and nearly verbatim:

> Energy is influenced by how you feel for the day, how you woke up, how you move your body, what you eat. Each one can
> be developed further: what you eat. If you eat high-carb, most of the time you will feel more sluggish; if you eat
> more protein, normally your energy is more stable; same thing for fats, etc. Energy is also affected by sleep, and
> sleep is affected by ...

So build an **influence map**: every signal linked to the others and to behaviours (sleep -> energy / focus / mood;
food composition -> energy / digestion; movement -> energy / sleep / mood; stress <-> sleep / digestion; and so on),
**each link with its explanation and its sources. Everything linked.** Reuse and extend the Foundation Track influence
work (section 4).

Deliverables per signal:
1. Explanation pages (what it is, what it feels like, what influences it, each influence developed further).
2. Related articles (the library).
3. Pre-made actions: action cards the practice can send and the member can add.
4. The **members dashboard version with even more information** (transferred to FunctionAlps-MEMBERS).

Rules: **every claim needs a source. Content is clinician-reviewed before members see it.** CLAUDE.md rule 6 applies:
no clinical wording is invented in Swift; the content lives in the backend / library and the app renders it.

### P1, explanation on each card
On each functional check-in card (check-in screen, Trends rows and detail pages) a short "what is this influenced by"
explanation, linking to the P0 page. The owner first called this P1, then said it is even P0. It is recorded as the top
priority together with P0, and the card-level explanation ships first.

### P2, automatic action engine
From each signal's trends, the engine proposes preferred actions to try, then measures whether the actions were
effective (before/after on the signal, adherence-aware). A big chunk of work for later, but very important. It builds
on the patterns ecosystem (validated patterns), the action cards and ladders, habit completions, and the Trends data.

### Clinician review cadence
Every 2 weeks, a trigger on the clinician dashboard to review each member's data (focus, energy and so on, the same
Trends overview) and give actions. "Later in the future, a fully AI doing it for us": the AI drafts, the clinician
approves. Sovereign AI only (Infomaniak via `lib/sovereign`); nothing reaches a patient without
`approval_status = 'approved'`.

### The patterns ecosystem
Patterns are computed nightly, shown to members only after clinician validation (done 2026-11-10), and feed the
explanations, the actions and the 2-week review.

## 3. What shipped on 2026-11-10 as the base

- The daily functional check-in rework (sleep dial / wearable night, Bristol chart, voice note).
- The health plan page.
- The Trends rework (validated mockup v2): the functional score is the equal-weight average of the six signals; daily
  actions and supplements; devices; the six signals with expand-then-detail and a fixed set of trend sentences; food and
  reactions as facts; the patterns page at the end.
- Patterns hidden from members until a clinician validates them (CLINICAL migration
  `20261110223000_patterns_clinician_validation`: members see only `clinician_status = 'validated'`; the clinician has
  Share / Hide / Undo on the Data page).

**Open decision (for Thomas):** should "export my data" include unvalidated patterns (members' right of access)?

## 4. What exists today (to build on, not to redo)

### Explanations and influence content already in the app (iOS)
- `FunctionAlps/Sources/Core/Scores/SignalContent.swift` (`BodySignal`: energy, sleep, mood, stress; ported from the
  Expo `health-details.ts`). Per signal it already has `subtitle`, `insight`, `explanation`, **`focusAreas`** ("What
  influences it", three levers each, e.g. energy: protein first, stable blood sugar, recovery versus output; sleep:
  wind-down consistency, morning light, late caffeine cutoff) and **`connections`** ("How it connects": a sentence per
  other signal, among digestion, inflammation, mood, sleep, stress, energy). It also holds `GutSignal` (comfort / stool
  / reactions). **This is the seed of the influence map**, but it is hard-coded in Swift, covers only four signals,
  has no Focus or Functional-score entry, no sources and no clinician review. It must move to backend content.
- `FunctionAlps/Sources/Features/Scores/SignalDetailView.swift` renders it ("What influences it", "How it connects").
  `ScoresHubView.swift` is the hub. `Core/Scores/ScoreExplainerCopy.swift` and `ScoreLegal` cover the meal scores.
- `FunctionAlps/Sources/Core/Scores/PatternText.swift`: turns `nb_user_patterns` rows into one honest sentence each.
- Check-in "What shaped it?" pills: the `drivers` module in `FunctionAlps/Sources/Core/Checkin/FunctionalSchema.swift`
  (Sleep, Food, Work, People, ...), asked after the mood slider. This is the member's own report of what influenced the
  day, and is raw material for validating the influence map per person. UI in `Features/Checkin/PillGroupView.swift`
  and `DimensionCardView.swift`.
- Trends: `FunctionAlps/Sources/Features/Trends/TrendsView.swift` and `TrendsViewModel.swift`.
- Scores backend: the `member-scores` edge function (`supabase/functions/member-scores`), plus `generate-score-tip`.

### The Foundation Track work (14 days)
- `docs/FOUNDATION_TRACK.md`: the content source of truth (decisions, questionnaires, day cards). **Honest finding:** it
  has no explicit signal-to-signal "influence" content. Its influence thinking is by pillar: days 1-7 each explain a
  pillar (what it is, why it matters, how we use it), and the actions and "how it will evolve" sections tie behaviours
  to feelings. Cite it for tone and structure, and reuse its pillar explanations and library links.
- `docs/foundation-cards/`: `build.py` (single source of the day cards), `cards.json`, `LIBRARY_PLAN.md`,
  `ARTICLES_TO_CREATE.md`, `QUESTION_BANK.md`, `README.md`, and the sourced reads in `docs/foundation-cards/articles/`
  (for example `d04-caffeine-and-your-sleep.md`, `d04-light-sets-your-body-clock.md`, `d08-protein-at-every-meal-and-why-it-matters.md`,
  `d03-exercise-snacks-small-signals-that-add-up.md`, `d05-breathe-the-time-you-give-yourself.md`). These are the
  first "related articles" for the influence map. `docs/foundation-cards/articles/TO_CHECK.json` lists claims awaiting
  review.
- `FunctionAlps/Sources/Core/Track/TrackLogic.swift`, `TrackUnlocks.swift` and
  `FunctionAlps/Sources/Core/Showcase/ShowcaseTrackContent.swift` (a generated fixture of the track as members read it;
  do not edit by hand; it carries one "terrain" article saying the body is not isolated parts).
- In the CLINICAL repo, clinician-reviewed pillar research that the content track should mine for sources:
  `clinical-dashboard/docs/wiki/four-pillars/` (`01_SLEEP_PILLAR_SPEC.md`, `08_NUTRITION_PILLAR_SPEC.md`,
  `10_STRESS_PILLAR_SPEC.md`, `07_PILLARS_2_3_4_STRATEGY.md`, `research/`, `review-pages/`). Note `review-pages/` already
  exists as a clinician review pattern.

### Actions
- `docs/action-cards/routines-design.md`, `docs/action-cards/catalogue-first-pass.md` (+ `.json`),
  `docs/action-cards/banque-actions-inventaire.md`, `guide-redaction-cartes-action.md`, `tracks-design.md`,
  `docs/action-cards/ladders/` and `docs/action-cards/huberman/` (lots of sourced cards).
- Live: `habit_bank`, `habit_bank.next_level_id`, `habits.level_since` / `level_locked`, RPC `member_level_up`
  (migration `20261006_action_ladders.sql`). Tracks, weekly-priority cycles and sub-routines have no tables yet.

### Patterns
- Tables / RPC: `nb_user_patterns`, `compute_user_patterns` (nightly). Members read only validated rows.
- CLINICAL: migration `clinical-dashboard/supabase/migrations/20261110223000_patterns_clinician_validation.sql`.

### Where the other roadmaps live
- Members dashboard: `/FunctionAlps-MEMBERS/docs/wiki/index.md`; the one backlog is
  `/FunctionAlps-MEMBERS/docs/wiki/pages/decisions/open-work.md` (questions for Thomas:
  `pages/decisions/open-for-thomas.md`). Related pages: `pages/features/trends-page.md`, `overview-patterns.md`,
  `member-library.md`, `library-page.md`. Add the P0 members work to `open-work.md` (MEMBERS definition of done applies).
- Clinician dashboard: `/FunctionAlps-CLINICAL/clinical-dashboard/docs/wiki/index.md`; table ownership in
  `docs/wiki/data/tables.md`; traps in `docs/wiki/lessons/_index.md`. Rules in the CLINICAL `AGENTS.md` (effort tiers,
  SOPs in `.claude/sops/`).

## 5. Suggested shape of the build (to be confirmed by the sessions below)

1. **Content model.** One backend table or library collection, for example `signal_explanations` (signal, language,
   what_it_is, what_it_feels_like, version, review status, reviewer, reviewed_at) and `signal_influences` (from_node,
   to_node, direction, strength-in-words, explanation, `sources` as citations, review status). Nodes are the six
   signals, the Functional score, and behaviours (sleep timing, light, caffeine, protein, carbs, fats, fibre, movement,
   stress load, hydration, alcohol, social contact). Plus links to library articles and `habit_bank` cards per node.
   Only `approved` rows are readable by members (RLS at the database). The app and FunctionAlps-MEMBERS read the same rows.
2. **Sources.** Every influence row carries at least one citation (PubMed ids or DOI), checked by a clinician.
3. **Slice 1 (P1).** Card-level "influenced by" line from backend content on every signal card and detail page.
4. **Slice 2 (P0).** Full explanation page per signal, influence map navigation (tap an influence to open that node),
   related articles, "add this action" buttons.
5. **Slice 3.** Members dashboard version with more depth.
6. **Later (P2).** Suggestion and effectiveness engine over validated patterns, ladders and completions.

## 6. Guardrails

- Nothing clinical is written in Swift: copy from the backend / library (iOS `CLAUDE.md` rule 6).
- Every claim sourced; every row clinician-approved before a member sees it.
- Any AI drafting goes through Infomaniak via `lib/sovereign` only, and is approved by a clinician.
- English first; French only when the owner asks (it is then a localisation pass over approved rows).
- No `git add -A`; do not push `main` of CLINICAL (deploys production).

## 7. Ready-to-paste prompts

### 7.1 Clinician dashboard: the every-2-weeks review (session in FunctionAlps-CLINICAL)

```text
Repo: FunctionAlps-CLINICAL (clinical-dashboard/). Read AGENTS.md first. This is T3 (migration + UI + cron): use a
dedicated worktree, a written plan, and the full gates. Follow SOPs 01 (schema), 03 (write data), 04 (UI surface) and 07
(API route / cron). Also read FunctionAlps-IOS/docs/ROADMAP_SIGNALS_ECOSYSTEM.md (the owner's priorities, 2026-11-10).

Goal: every 14 days, each active member gets a review task for the practitioner.
- A queue item (task) per active member every 14 days, created by a cron under app/api/cron/* (scheduled in vercel.json).
- Opening it goes to that patient's Data / Overview page with the review period preselected (the same Trends overview:
  focus, energy, sleep, mood, stress, digestion, the functional score).
- The clinician reviews the signals, validates or hides patterns (the Share / Hide / Undo from migration
  20261110223000_patterns_clinician_validation), picks actions from the action-card bank (habit_bank) to send, and logs the
  review (who, when, period, notes, actions sent). Nothing reaches a patient unless approval_status = 'approved'.
- Later (design for it, do not build now): an AI draft through lib/sovereign (Infomaniak only) prepares the summary and
  proposed actions; the clinician approves or edits.
Constraints: PostgREST errors are values, check them; RLS at the database; Zod at boundaries; Server Components by
default; stage explicit paths only; push only to a preview/<name> branch if a preview is needed, never main without the owner.
Done: tsc, relevant vitest suites, SOP gates, wiki page + dev-map/map.json updated, a lessons page if a trap was hit.
```

### 7.2 iOS app: P0 first slice (session in FunctionAlps-IOS)

```text
Repo: FunctionAlps-IOS. Read CLAUDE.md, docs/ROADMAP_SIGNALS_ECOSYSTEM.md, then docs/ARCHITECTURE.md and
docs/API_MAP.md. iOS 17+, Swift 6, SwiftUI, @Observable view models; view -> view model -> service -> FunctionAlpsBackend.
There is no local Xcode: build and test via the iOS GitHub Actions workflow.

Goal (owner priority P0/P1, 2026-11-10): on each functional check-in signal card (check-in screen, Trends rows) and on
each signal detail page, show a short "What is this influenced by" explanation, rendered from BACKEND content (never
invented in Swift; CLAUDE.md rule 6), linking to the full explanation page, related articles and actions. Then add the
influence-map navigation (tap an influence to open that node).
What exists: Core/Scores/SignalContent.swift (hard-coded focusAreas and connections for energy/sleep/mood/stress only:
migrate it to backend content, add Focus, Digestion and the Functional score), Features/Scores/SignalDetailView.swift,
Features/Trends/*, Features/Checkin/* (the "What shaped it?" pills), the library, habit_bank.
Constraints: only Core/API/* knows table or function names; loading / error / empty / unauthorized states on every
network screen; strings via String(localized:defaultValue:) and Localizable.xcstrings (en, fr); Dynamic Type and labels.
If the content table does not exist yet, agree its shape with the content session (section 5 of the roadmap) and build
against a protocol-backed fake in Showcase.
Done: unit tests for the decoding and the fallback, the CI run green, docs/IOS_MIGRATION_MAP.md updated when the slice lands.
```

### 7.3 Content and members dashboard (session with access to CM OS, FunctionAlps-MEMBERS and the library)

```text
Goal: produce the curated, sourced explanation set and the influence map for Sleep, Energy, Focus, Mood, Stress,
Digestion and the Functional score, then build the richer members-dashboard pages. Read
FunctionAlps-IOS/docs/ROADMAP_SIGNALS_ECOSYSTEM.md first, then FunctionAlps-MEMBERS/CLAUDE.md and AGENTS.md (Next 16
differs from your training data: read node_modules/next/dist/docs before framework code) and the MEMBERS wiki
(docs/wiki/index.md, pages/decisions/open-work.md, pages/features/trends-page.md, member-library.md).
Content, per signal: what it is, what it feels like, what it is influenced by (each influence developed: for energy,
high-carb meals versus protein versus fats, sleep, movement, stress, how you woke up), related library articles, and
pre-made action cards (habit_bank). Each influence = one row with a one-paragraph explanation and at least one citation
(PubMed id or DOI; use the PubMed tools). Start from the existing material: iOS Core/Scores/SignalContent.swift,
docs/foundation-cards/articles/, docs/action-cards/huberman/, and CLINICAL docs/wiki/four-pillars/.
Storage: propose a table/library shape (signal_explanations, signal_influences with citations, review status, reviewer),
readable by both the app and MEMBERS only when approved (RLS), with a clinician review queue.
CM OS is shared clinical PROD with no dev branch: additive DDL only, BEGIN...ROLLBACK dry run, get_advisors(security)
after, regenerate types; clinical-dashboard owns the 0NN_ migration sequence (use date-stamped names). Members reads run
on the RLS user-session client. English first.
Done: content set drafted and flagged "pending clinician review"; schema proposal written and agreed before applying;
members pages built with the richer version; MEMBERS wiki updated (feature page, function->DB map, log, open-work).
```

### 7.4 P2: action suggestion and effectiveness engine (later)

```text
Goal: design (before any build) the engine that, from each signal's trend, proposes preferred actions to try and then
measures whether they were effective. Read FunctionAlps-IOS/docs/ROADMAP_SIGNALS_ECOSYSTEM.md, docs/action-cards/
(routines-design.md, catalogue-first-pass.md, ladders/), the patterns engine (nb_user_patterns, compute_user_patterns) and
the CLINICAL migration 20261110223000_patterns_clinician_validation.
Design questions to answer in a written proposal: which trend shapes trigger a suggestion; how a suggestion is chosen
from habit_bank using validated patterns and the influence map; how adherence is measured from habit completions; the
before/after method per signal (window lengths, minimum days, handling of confounders such as illness, travel, cycle,
a missed wearable night); when the result is "not enough data"; how a clinician sees and approves suggestions; how ladders
(member_level_up) interact; what the member is told, in non-causal, honest wording.
Constraints: server-side calculation (edge function / RPC), Swift only formats; sovereign AI only for any model use;
nothing reaches a patient without approval; no clinical wording invented outside reviewed content.
Done: a proposal page with options, a recommended approach, the data and RLS needs, the test plan and a slice plan.
Do not build until the owner approves the proposal.
```
