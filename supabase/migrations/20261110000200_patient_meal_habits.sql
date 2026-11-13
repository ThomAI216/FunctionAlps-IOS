-- nb_patient_meal_habits: meal habits a clinician sets for one member, applied to that member's PHOTO meals before
-- pricing by the meal analysis (supabase/functions/_shared/meals/habits.ts, 2026-11-10, owner's decision).
--
-- What a habit is: a correction the member keeps making to what the photo model reads — "the yogurt is kefir"
-- (replace), "there is milk in the chia pudding" (add), "my oats are 60 g" (portion). The edge functions LEARN these
-- from the member's own edits on the fly (the same fix on 2 meals) and write nothing here. This table is for the
-- habits a clinician knows without waiting for two meals: a row is applied from the next photo on, needs no history,
-- is not dropped by the member undoing it, and wins over a learned habit on the same food. `active = false` switches
-- a row off without losing it.
--
-- Columns, as habits.ts reads them:
--   kind          'add'     — when the trigger food is on the plate and item_name is not, add item_name at item_grams
--                 'replace' — the trigger food is item_name (item_grams, or the model's grams when null)
--                 'portion' — the trigger food's portion is item_grams
--   trigger_norm  the food's normalised key: aliasKey(name) in _shared/meals/food-resolver.ts, the same key
--                 nb_patient_food_aliases.alias_norm holds (lowercase, preparation words and plurals stripped:
--                 "Plain Greek yogurts" -> "greek yogurt"). Read as stored, never re-normalised.
--   item_name     the food added / swapped in, as the member should see it. Null for 'portion'.
--   item_grams    grams. Required for 'add' and 'portion'.
--   source        'clinic' (a clinician wrote it) or 'learned' (a learned habit someone chose to keep).
--
-- Who reads/writes: the meal analysis edge functions read active rows (the interactive one under the member's JWT,
-- the retry worker with the service role); the member may SELECT their own rows (so the app can explain a habit);
-- writes are service role only (the CLINICAL dashboard's server side). Nothing for anon.
--
-- ADDITIVE and IDEMPOTENT. Not applied by the commit that adds it — the owner applies it with the edge functions.
-- Until it is applied the functions treat the missing table as "no clinic habits" (42P01 / PGRST205).

create table if not exists public.nb_patient_meal_habits (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references public.patients(id) on delete cascade,
  kind          text not null check (kind in ('add', 'replace', 'portion')),
  trigger_norm  text not null,
  item_name     text,
  item_grams    numeric check (item_grams is null or item_grams > 0),
  active        boolean not null default true,
  source        text not null default 'clinic' check (source in ('clinic', 'learned')),
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.nb_patient_meal_habits is
  'Meal habits for one member (add / replace / portion), applied to their photo meals before pricing by the meal analysis edge functions. Learned habits are computed from meal edits and not stored here; clinic rows need no history.';

-- One habit per (member, kind, food, item). item_name is null for a portion rule, and a plain UNIQUE treats nulls as
-- distinct, which would let two portion rows for the same food coexist — hence the expression index.
create unique index if not exists nb_patient_meal_habits_uniq
  on public.nb_patient_meal_habits (patient_id, kind, trigger_norm, coalesce(item_name, ''));

alter table public.nb_patient_meal_habits enable row level security;

do $$ begin
  create policy service_role_all_nb_patient_meal_habits on public.nb_patient_meal_habits
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy member_self_read_nb_patient_meal_habits on public.nb_patient_meal_habits
    for select to authenticated
    using (patient_id in (select id from public.patients where auth_user_id = auth.uid()));
exception when duplicate_object then null; end $$;

revoke all on public.nb_patient_meal_habits from anon;
