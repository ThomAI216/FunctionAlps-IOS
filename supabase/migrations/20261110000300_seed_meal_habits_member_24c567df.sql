-- Clinic-seeded meal habits for ONE member (patient 24c567df-…), Thomas's request of 2026-11-10: "for her
-- specifically, already review her behaviours to do the changes". Apply AFTER 20261110000200_patient_meal_habits.sql,
-- with the edge functions that read the table (habits.ts) — the owner ships them together in the next build.
--
-- Source: a read-only review of her 96 complete meals (2026-09-26 → 2026-11-10), comparing what the photo model
-- identified (resolved_foods) with her edited lists (ai_identified_foods). Seeded here only what she did on MANY
-- meals; the two-meal, context-bound swaps (cauliflower → fennel, cream → ricotta…) are left to the automatic
-- learner, which needs her to repeat them twice once this ships.
--   yogurt → kefir ~60 g ............ 7 meals (the model proposes 140–220 g of yogurt)
--   + oats 30 g with kefir ........... 9 meals
--   pear → cooked apple ~100 g ....... 4 meals
--   white rice ~100 g ................ 12 meals (model: 160–290 g)
--   walnuts 10 g ..................... 8 meals (model: 20–30 g)
--   nut butters 10 g ................. 5 meals (model: 20–30 g)
--   potatoes ~100 g .................. 6 meals
--   honey ~7 g ....................... 3 meals (model: 10–20 g)
-- trigger_norm is aliasKey() of the model's usual wordings, one row per wording (the key is matched exactly).
-- Every row is visible to her as "From your habits" and removable; `active = false` switches one off.
-- Idempotent: re-running inserts nothing new.

insert into public.nb_patient_meal_habits (patient_id, kind, trigger_norm, item_name, item_grams, source, note)
select '24c567df-6eac-4b89-ac0b-17fe8b4c7d2f'::uuid, v.kind, v.trigger_norm, v.item_name, v.item_grams, 'clinic', v.note
from (values
  ('replace', 'greek yogurt',  'Kefir',        60,  'yogurt → kefir, 7 meals'),
  ('replace', 'greek yoghurt', 'Kefir',        60,  'yogurt → kefir, 7 meals'),
  ('replace', 'yogurt',        'Kefir',        60,  'yogurt → kefir, 7 meals'),
  ('replace', 'yoghurt',       'Kefir',        60,  'yogurt → kefir, 7 meals'),
  ('add',     'kefir',         'Oats',         30,  'adds 30 g oats to her kefir breakfast, 9 meals'),
  ('replace', 'pear',          'Cooked apple', 100, 'pear → cooked apple, 4 meals'),
  ('replace', 'stewed pear',   'Cooked apple', 100, 'pear → cooked apple, 4 meals'),
  ('replace', 'pear slice',    'Cooked apple', 100, 'pear → cooked apple, 4 meals'),
  ('portion', 'white rice',    null,           100, 'rice ~100 g, 12 meals'),
  ('portion', 'rice',          null,           100, 'rice ~100 g, 12 meals'),
  ('portion', 'walnut',        null,           10,  'walnuts 10 g, 8 meals'),
  ('portion', 'walnut halve',  null,           10,  'walnuts 10 g, 8 meals'),
  ('portion', 'peanut butter', null,           10,  'nut butter 5–10 g, 5 meals'),
  ('portion', 'nut butter',    null,           10,  'nut butter 5–10 g, 5 meals'),
  ('portion', 'almond butter', null,           10,  'nut butter 5–10 g, 5 meals'),
  ('portion', 'potato',        null,           100, 'potatoes ~100 g, 6 meals'),
  ('portion', 'mashed potato', null,           100, 'potatoes ~100 g, 6 meals'),
  ('portion', 'honey',         null,           7,   'honey 5–10 g, 3 meals'),
  ('portion', 'drizzled honey', null,          7,   'honey 5–10 g, 3 meals')
) as v(kind, trigger_norm, item_name, item_grams, note)
where exists (select 1 from public.patients p where p.id = '24c567df-6eac-4b89-ac0b-17fe8b4c7d2f'::uuid)
on conflict (patient_id, kind, trigger_norm, coalesce(item_name, '')) do nothing;
