# Foundation Track — the 14 day cards

`build.py` is the single source of the day cards' member-facing content:

- the day titles and, on days 1–7, the pillar each day explains;
- the card's sections: **Today** (days 1–5: what it is · why it matters · how we use it; other days one paragraph),
  **Why we ask** (the day's questionnaire), **First thing to try / New today** (the day's new actions),
  **Mini tip**, **Your routine** (every action active that day, by moment), **How it will evolve**, library links
  and the short read;
- the actions themselves (`ACTIONS`: moment, title, one-line how-to) and when each starts and stops (`SCHEDULE`);
- Thomas's video script for every day;
- the infographic brief for days 8–14 (days 1–7 have no image) and the series style.

`python3 build.py` writes `cards.html` (the phone mockups Thomas reviews, published as an artifact) and `cards.json`.
`supabase/seed/foundation_track_seed.py` imports this file, so the app's day titles, actions and questionnaire
"why we ask" texts are the mockups' own, and `docs/FOUNDATION_TRACK.md` is regenerated from both. EN only; FR once the
English is locked.

The card's own text reaches the app through `track_day.card_en` / `card_fr` and the infographic through
`track_day.image_url` / `image_alt_*` (migration `supabase/migrations/20261006_foundation_track_day_card.sql`, then
the generated `20261006_foundation_track_day_card_content.sql`), both pending Thomas's OK at the time of writing.
