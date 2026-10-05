# Ladder levels (owner, 2026-10-06)

`lot-c-ladders.json` holds the six new ladder levels and the full content for the live card "Morning stretch, five
minutes". It is in the CLINICAL import format (`functionalps/action-cards/import-v1`), English and French, and was
validated with CLINICAL's own importer: 6 new and 1 update to a published card.

## State on CM OS

**Published 2026-10-06 (owner's go):** the six new levels, and the full "Morning stretch, five minutes" (steps,
why, YouTube link, card type movement · 5 min, members can add it). Applied with CLINICAL's own import columns;
the texts were checked against this file. No demonstration video chosen yet: paste the practice's video in the
stretch card's Video field (CLINICAL → Action cards); until then the button opens the YouTube search.

**Still a draft:** "First coffee 30 minutes after waking" (lot B). It is the middle of the caffeine ladder, so a
member on "No caffeine after 14:00" sees the next level as "coming soon" until it is published.

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
