-- The day card's own text and infographic (Thomas, 2026-10-06: "push the 14 days' cards", then
-- "rework the new Today, your routine, and how it will evolve").
-- ADDITIVE ONLY: five nullable columns on track_day. Pending Thomas's explicit OK before apply.
--   card_*       the card's sections, one object per language:
--                  pillar     the chip above the title on days 1–7 ("Pillar 2 · Movement"), absent after
--                  today      days 1–5: [{label: "What it is" | "Why it matters" | "How we use it", text}];
--                             other days: one paragraph
--                  try_label  the heading over the day's new actions ("First thing to try · …")
--                  tip        the mini tip
--                  evolve     [{when: "Tomorrow" | "Day 7" | …, text}]: how the routine will evolve
--                  library    [{kind, title}]: library items the card points to
--                "Why we ask" is the day's track_questionnaire.intro_*; "Your routine" is built from
--                track_day.actions (every action active that day, by moment).
--   image_url    Thomas's infographic (4:5 portrait), days 8–14 only, stored in CM OS storage
--   image_alt_*  what the infographic shows, for VoiceOver
-- Content: 20261006_foundation_track_day_card_content.sql (generated), applied after this.
alter table public.track_day
  add column if not exists card_en      jsonb,
  add column if not exists card_fr      jsonb,
  add column if not exists image_url    text,
  add column if not exists image_alt_en text,
  add column if not exists image_alt_fr text;
