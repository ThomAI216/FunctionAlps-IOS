# Foundation Track v2 · the decisions every agent must honour (Thomas, 2026-11-06 → 11-10)

Sources: the approved mockup `SCRATCH/build_mock.py` (renders `SCRATCH/mock/flow.html`, published as artifact X4SrfHtE3Pn7UYuEvf4rjj),
the 29 approved articles `SCRATCH/articles/dNN-*.md` (live on CM OS since 2026-11-08), `FunctionAlps-IOS/docs/foundation-cards/LIBRARY_PLAN.md`.
SCRATCH = /tmp/claude-0/-home-user/a3c279f0-093f-5673-ab57-1d55c6a4c2c6/scratchpad

## The day-by-day habit plan (replaces the old track_day.actions: water on waking, phone out of the bedroom, coffee before 14:00…)
Source of truth: `ACTIONS` (build_mock.py:241), `HABITS` (:666), `MOVES` (:753), `MOMENTS` (:239).
- 1 · log a meal, functional check-in (these two are day 1's actions and leave the card after day 3).
- 2 · mindful eating (no phone, chew, breathe, a glass of water), a 5-minute walk after eating.
- 3 · 3 minutes of movement in the morning, an optional exercise snack, 2 minutes of gentle stretching before bed.
- 4 · daylight first thing (right when you wake up, before your phone, then 5 minutes outside or at an open window), no caffeine after 16:00, the 3-2-1 rule (3 h no food, 2 h no intense exercise, 1 h no screens), an optional mini breath before sleep.
- 5 · 5 minutes of breathing once a day (Wim Hof video), write down three good things.
- 6 · nothing new.
- 7 · the 5-minute morning flow (replaces the 3 minutes of movement), one exercise snack a day.
- 8 · protein at every meal, complex carbs, a walk after every meal.
- 9 · 2 to 3 movement moments a day.
- 10 · the evening in three: the 3-2-1 rule, a book instead of a screen, 10 minutes to wind down (box breathing or NSDR).
- 11 · reach out to someone you care about, 5 minutes of writing (three good things + what's on your mind), a second breath.
- 12 · the 10-minute flow, move 10 minutes every 2 hours.
- 13, 14 · nothing new (13: choose the habits you keep; 14: the two-week review).
Exact titles, moments, first/last day, how-to lines: take them from ACTIONS/HABITS, not from this summary.

## Habits by moment (Home's actions card)
- Moments: Morning, Midday (10:00–14:00), Afternoon, Evening. The card shows the current moment's pack, at most 3 at a time; the next ones come once these are done.
- Each habit shows its streak with a little flame.
- Tap a habit: it opens a little (its mini description + "See the habit"). "See the habit" opens its page.

## The habit page (the "first one" Thomas chose: stacked cards)
- Top: the streak, as the last 14 days as dots with how many in a row; a small blue dot marks "You are here" (today). No ring. No streak card on the habit's first day.
- Then: how to do it (with its articles, titles only, two per row), the benefits to look for, the video if there is one (our own player for our videos, YouTube's player inside the app for YouTube), "What it tends to move" (the ↑/↓ effects from MOVES, e.g. Awareness ↑, Cravings ↓).
- "Your own effects" (mood/energy/focus/sleep with vs without the habit) is LATER (the hypotheses idea): show at most the "after 10 days" line, never invented data.

## The library · first release
- The cards home: search at the top ("Search" now; Ask comes later with the AI wellness coach, as ONE shared service the library and the coach both call — do not build Ask now); the Foundation Track as day cards (read ✓, today, the days to come soft-locked); "For your habits" (the reads tied to the member's current habits); "Watch" (videos that play in the app, a little space between them but not much).
- Days are soft-locked, never hard-locked: a read from a day still to come shows its title; tapping says "Opens on day N"; it cannot be opened before its day.
- Reader: "Practice it" lists the habits the article goes with: Open if it is in your actions, a SMALL "+ Add" if not. "Mark as read". "Read next".
- English only: the French articles are hidden from the app. No show in the Library tab. No pillars, no tracks, no supplements, no long list in this release.
- Titles only, no striped cover backgrounds.

## The four tracks (LIBRARY_PLAN.md "Proposed structure, by pillar" + "Edits for all 15")
Thomas: "Do the four tracks, as I told you" (2026-11-10) = apply the proposed structure and the edits.

## Rules
- CM OS (`ndojytvvlvlbgtodujkf`) is shared clinical PRODUCTION: additive and reversible only, a rolled-back dry run before every write, record the before-state, no deletes, `get_advisors(security)` after any DDL.
- iOS: FunctionAlps-IOS/CLAUDE.md rules (View → ViewModel → Service → FunctionAlpsBackend; only Core/API knows table/RPC names; no health wording invented in Swift: copy from CM OS; String(localized:) + Localizable.xcstrings en+fr; loading/error/empty/unauthorized states; accessibility). Build/test = the `iOS` GitHub Actions workflow on push to the branch.
- No model identifiers in commits. Commit messages end with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Ac7PU9TW7tm6J6pJa4S5F8
