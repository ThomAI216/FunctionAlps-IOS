# Foundation Track — the 14 day cards

`build.py` is the single source of the day cards' member-facing text (the "Today" paragraph, the new
actions with their one-line how-to, the routine so far, questionnaire / call / summary buttons, the
short read) and of the infographic brief for each day, plus the series style shared by all 14 images.

`python3 build.py` writes `cards.html` (the phone mockups Thomas reviews, published as an artifact on
2026-10-06) and `cards.json` (the same content as data). EN only; FR once the English is locked.

The card text reaches the app through `track_day.intro_*` and the infographic through
`track_day.image_url` / `image_alt_*` (migration `supabase/migrations/20261006_foundation_track_day_card.sql`,
pending Thomas's OK at the time of writing).
