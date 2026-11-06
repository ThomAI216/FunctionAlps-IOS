-- Day 1 of the Foundation Track, Thomas's feedback of 2026-11-06. Data update, no schema change. Idempotent.
--
--  1. A card for the first action, "3 physiological breaths": Thomas's own steps (a big breath in through the
--     nose, one more when almost full, then a long breath out); the why from the reviewed lot-B card "The
--     double-inhale sigh" (docs/action-cards/huberman/lot-b-mind.json), to confirm with Thomas. English only.
--  2. The breathing action (key breaths_3, days 1–6) becomes "3 physiological breaths", without the window and the
--     light, and opens that card.
--  3. Day 1: the glass of water is gone (it starts on day 2, where it is now "New"); the day card loses
--     "What it is", the mini tip and the "First thing to try" heading.
--  4. Day 2's morning reminder follows the rename and no longer promises a video.
--  5. The day-1 questionnaire: "Turn on your reminders" moves onto the "Connect Apple Health" page.

-- 1 ────────────────────────────────────────────────────────────────────────────────
insert into public.habit_bank (id, pillar, category, card_kind, title, description, default_slot, frequency_rule,
                               how_md, general_why, resources, active, member_can_add, sort_order, published_at)
values ('7fc3d878-6d2f-40f1-957e-038d33f6d60f', 'mind', 'calm', 'routine',
        '3 physiological breaths',
        'A big breath in through the nose, one more when you''re almost full, then a long breath out.',
        'morning', 'RRULE:FREQ=DAILY',
        E'1. Stand or sit comfortably, wherever you are.\n2. Take a big breath in through the nose.\n3. When you''re almost full, take in one more short breath through the nose.\n4. Then breathe out slowly through the mouth, as long as you can.\n5. Do it three times.\n6. If you feel light-headed, go back to normal breathing.',
        'A long, slow breath out is the part of breathing that helps your heart slow down. The second breath in opens the lungs fully first, so the breath out can do more. That is why a few of these breaths can help you settle quickly, right in the moment.',
        '[]'::jsonb, true, false, 150, now())
on conflict (id) do update set
  title = excluded.title, description = excluded.description, how_md = excluded.how_md,
  general_why = excluded.general_why, updated_at = now();

-- 2 + 3 ───────────────────────────────────────────────────────────────────────────
update public.track_day d
   set actions = (
         select coalesce(jsonb_agg(
                  case when a->>'key' = 'breaths_3'
                       then a || jsonb_build_object(
                              'title_en', '3 physiological breaths',
                              'how_en', 'A big breath in through the nose. When you''re almost full, one more. Then a long breath out.',
                              'habit_bank_id', '7fc3d878-6d2f-40f1-957e-038d33f6d60f')
                       when a->>'key' = 'water_waking' and d.day = 2 then a || jsonb_build_object('new', true)
                       else a end
                  order by ord), '[]'::jsonb)
           from jsonb_array_elements(d.actions) with ordinality as t(a, ord)
          where not (d.day = 1 and a->>'key' = 'water_waking')),
       updated_at = now()
 where d.track_code = 'foundation_v1' and d.day between 1 and 6;

update public.track_day
   set card_en = (card_en - 'tip' - 'try_label')
                 || jsonb_build_object('today', coalesce((
                      select jsonb_agg(p order by ord)
                        from jsonb_array_elements(card_en->'today') with ordinality as t(p, ord)
                       where p->>'label' <> 'What it is'), '[]'::jsonb)),
       updated_at = now()
 where track_code = 'foundation_v1' and day = 1 and jsonb_typeof(card_en->'today') = 'array';

-- 4 ────────────────────────────────────────────────────────────────────────────────
update public.track_day
   set push = jsonb_set(push, '{morning,en}', to_jsonb('Day 2 · Nutrition. Water, then 3 physiological breaths.'::text)),
       updated_at = now()
 where track_code = 'foundation_v1' and day = 2 and push ? 'morning';

-- 5 ────────────────────────────────────────────────────────────────────────────────
update public.track_question
   set screen = 5, position = 2
 where questionnaire_id = 'foundation_d1_you_today' and question_key = 'enable_notifications';
