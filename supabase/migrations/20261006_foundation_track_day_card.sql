-- The day card's own text and infographic (Thomas, 2026-10-06: "push the 14 days' cards").
-- ADDITIVE ONLY: five nullable columns on track_day. Pending Thomas's explicit OK before apply.
--   intro_*      the card's "Today" paragraph (2–4 sentences)
--   image_url    Thomas's infographic (4:5 portrait), stored in CM OS storage
--   image_alt_*  what the infographic shows, for VoiceOver
alter table public.track_day
  add column if not exists intro_en     text,
  add column if not exists intro_fr     text,
  add column if not exists image_url    text,
  add column if not exists image_alt_en text,
  add column if not exists image_alt_fr text;
