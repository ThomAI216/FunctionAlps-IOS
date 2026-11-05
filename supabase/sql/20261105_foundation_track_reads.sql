-- A short read on every Foundation Track day (Thomas, 2026-11-05: "resources every day").
--
-- Data update, not schema. Each day of foundation_v1 gets a `read_slug` — the
-- day's short read, opened in the library reader by the iOS day card
-- (`TrackReadRow`) and by the lead home on MEMBERS (`LeadTrackCard`). Every slug
-- is an article ALREADY published to members on CM OS (kb_nodes, channel
-- patient_app, tier patient_tier_1), chosen by the day's pillar; no new text.
-- Leads read them because the library opens for a live lead entitlement
-- (migration 20261105_foundation_track_leads).
--
-- Idempotent and non-destructive: only a day whose read_slug is still NULL is
-- set, and only to a slug that exists and is published — so a day Thomas has
-- already pointed elsewhere keeps his choice, and a retired article is skipped.
--
-- Day → read (pillar)
--   1  Your starting point        → feedback-and-self-tracking (the check-in, what we measure)
--   2  Nutrition                  → macros-vs-micros
--   3  Movement                   → micro-workouts-exercise-snacks (the exercise snack)
--   4  Sleep                      → morning-wake-up-routine (morning daylight)
--   5  Mental and emotional       → breathing-exercises (box breathing)
--   6  Your first week            → your-unique-terrain-roadmap
--   7  Your full day              → how-nutrition-training-gut-recovery-and-nervous-system-work-together
--   8  Protein first              → nutrient-dense-foods
--   9  A lunch that holds you     → post-meal-walking (the 10-minute walk after lunch)
--  10  Easy strength              → strength-is-more-than-muscle-size
--  11  Your evening downshift     → nsdr-yoga-nidra (the wind-down)
--  12  More morning movement      → rom-and-loaded-mobility (the morning flow)
--  13  Make it yours              → signals-create-adaptation (why consistency wins)
--  14  Your two weeks             → biological-recovery

update public.track_day d
   set read_slug = v.slug,
       updated_at = now()
  from (values
    (1,  'feedback-and-self-tracking'),
    (2,  'macros-vs-micros'),
    (3,  'micro-workouts-exercise-snacks'),
    (4,  'morning-wake-up-routine'),
    (5,  'breathing-exercises'),
    (6,  'your-unique-terrain-roadmap'),
    (7,  'how-nutrition-training-gut-recovery-and-nervous-system-work-together'),
    (8,  'nutrient-dense-foods'),
    (9,  'post-meal-walking'),
    (10, 'strength-is-more-than-muscle-size'),
    (11, 'nsdr-yoga-nidra'),
    (12, 'rom-and-loaded-mobility'),
    (13, 'signals-create-adaptation'),
    (14, 'biological-recovery')
  ) as v(day, slug)
 where d.track_code = 'foundation_v1'
   and d.day = v.day
   and d.read_slug is null
   and exists (select 1 from public.kb_nodes n where n.slug = v.slug and n.published_at is not null);
