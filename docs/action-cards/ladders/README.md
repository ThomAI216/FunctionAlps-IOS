# Ladder levels (owner, 2026-10-06)

`lot-c-ladders.json` holds the six new ladder levels and the full content for the live card "Morning stretch, five
minutes". It is in the CLINICAL import format (`functionalps/action-cards/import-v1`), English and French, and was
validated with CLINICAL's own importer: 6 new and 1 update to a published card.

## State on CM OS

The six new levels and "First coffee 30 minutes after waking" (from `huberman/lot-b-nutrition.json`) are in
`habit_bank` as **drafts** (`active = false`). Members do not see them; on a ladder they show as "coming soon" until
a lead publishes them in CLINICAL → Action cards.

**"Morning stretch, five minutes" is NOT updated yet.** Its new steps, why and YouTube link reach every member at
once, so a lead applies them: CLINICAL → Action cards → Import JSON → load `lot-c-ladders.json` → tick that one card.
No demonstration video was chosen: paste the practice's video in the card's Video field. Until then the card offers
the YouTube search.

## The ladders (`habit_bank.next_level_id`)

| Ladder | Levels |
|---|---|
| Morning movement | Morning stretch, five minutes → Morning stretch + a 10-minute walk *(new)* → A brisk 30-minute walk (its versions: 20 → 30 → 40–60 min) → Warm-up + an easy run *(new, cleared-only)* |
| Bodyweight strength | Ten sit-to-stands → One set of push-ups → Morning stretch + one strength circuit *(new)* |
| Walking | A 10-minute walk after lunch → Walk five minutes every half hour → A brisk 30-minute walk |
| Screens before bed | Screens off 30 minutes before bed → Screens off 60 minutes before bed *(new)* |
| Caffeine | No caffeine after 14:00 → First coffee 30 minutes after waking → First coffee 60–90 minutes after waking *(new)* |
| Kitchen | Kitchen closed after 21:00 → Kitchen closed 3 hours before bed *(new)* |
| Light | Five minutes of daylight → Morning light within an hour of waking |

Leads change a link in CLINICAL → Action cards → a card → **Next level**. "Sleep timing" (same bedtime → same
wake-up time) waits for "Same wake-up time, weekends too" to reach the database.

Each card's `_note_clinicien` says where its numbers come from: the book's record, the owner's ladder, or the
author (to review).
