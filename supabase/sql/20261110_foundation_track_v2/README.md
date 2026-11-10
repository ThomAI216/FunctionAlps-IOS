# Foundation Track v2 on CM OS · 2026-11-10 (applied)

The record of what was written to CM OS (`ndojytvvlvlbgtodujkf`) on 2026-11-10, with the before-state of every row, so each change can be reverted.

| What | SQL | Before |
|---|---|---|
| v2 habit plan: habit_bank (25 new, daylight updated), track_day.actions + read_slug, `day:N` tags on the 29 articles, 24 French articles off the patient_app channel | trackv2.sql | trackv2_before.json |
| Day cards (card_en days 1–12) aligned with v2; day titles 8–12 (Build your plate, Easy strength, Your evening downshift, Your mind, day to day, More movement); day 8 library item → "Complex or refined carbs" | cards_after.json (+ the titles, by hand) | cards_before.json |
| The four tracks → six: Functional health from the ground up, Fuel your body, Build your engine (Stamina merged, Stamina inactive), Build a stronger body, Sleep deeper, Calm and recover | tracks.sql | tracks_before.json |
| The 15 track lessons: Phase kickers removed, programme wording made neutral | lessons_changes.md | lessons_before.json |
| "Practice it": the 15 lessons linked to their habits in habit_bank.resources ({kind:"article"}) | by hand (additive) | — |

Decisions: docs/foundation-cards/DECISIONS_V2.md.
