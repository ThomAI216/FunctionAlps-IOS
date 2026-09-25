-- The member's own meal-reminder schedule (Meal Rhythm, slice 1 — docs/MEAL_RHYTHM_SPEC.md §3, §7).
--
-- Until now every member got the same two "meal not logged" nudges (lunch 13:30, dinner 20:15) and no
-- breakfast at all, while the live logs put more dinners in the 21 h hour than in any other. This is the
-- schedule the phone executes instead: one row per meal slot per ISO weekday (1 = Monday … 7 = Sunday),
-- so "never breakfast, except on Sunday" is one row flipped, not a special case.
--
-- OWNERSHIP. The member owns these rows — they are their phone's reminders. Members read, insert and update
-- their own; clinic staff read (the practitioner's view of the habit). Nobody deletes: a slot the member
-- does not want is `enabled = false`, and its `remind_at` is kept so switching it back restores their time.
-- A practitioner never moves a member's reminders; a clinical timing target, when it comes, travels through
-- the care plan (spec §9), not through this table.
--
-- SEEDING. `member_meal_schedule_seed()` creates the 35 rows on the first read and returns the schedule —
-- idempotent, SECURITY INVOKER, so it can only ever see and write the caller's own rows. It reads the two
-- things the member already told us: the intake's "I usually skip breakfast" and the nutrition profile's
-- `snacks_per_day`. Everything else starts at the defaults Thomas set: breakfast 08:00, lunch 12:00 and
-- dinner 20:00 on; the 10:00 and 16:00 snacks off. `source` records where every time came from.
--
-- Additive only. Dry-run in BEGIN … ROLLBACK before applying; get_advisors(security) after.

create table if not exists public.member_meal_schedule (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  slot text not null check (slot in ('breakfast', 'morning_snack', 'lunch', 'afternoon_snack', 'dinner')),
  -- ISO weekday: 1 = Monday … 7 = Sunday.
  weekday smallint not null check (weekday between 1 and 7),
  enabled boolean not null,
  -- The member's wall clock; kept while the slot is off.
  remind_at time not null,
  -- Where this row's time came from. `default` / `intake` / `profile` rows are the only ones a later stated
  -- source (a questionnaire, the in-app setup) may overwrite without asking (spec §3.3).
  source text not null default 'default' check (source in
    ('default', 'intake', 'profile', 'setup', 'questionnaire', 'member', 'learned', 'pillar_observation')),
  -- false = "don't ask about this slot again" (spec §4.4). Unused until the adaptive loop (slice 3).
  learning_enabled boolean not null default true,
  updated_via text check (updated_via in ('ios', 'web', 'engine')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (patient_id, slot, weekday)
);

comment on table public.member_meal_schedule is
  'The member''s meal-reminder schedule: one row per slot per ISO weekday (1 = Monday). Member-owned (their phone''s reminders); clinic staff read. Seeded by member_meal_schedule_seed(). A reminder time is not an observation of when anyone eats — never read it as one.';
comment on column public.member_meal_schedule.source is
  'Where the time came from: default · intake (skip-breakfast answer) · profile (snacks_per_day) · setup (in-app) · questionnaire (Nutrition pillar) · member (hand edit) · learned (an accepted proposal) · pillar_observation (a closed pillar week).';

drop trigger if exists trg_member_meal_schedule_updated_at on public.member_meal_schedule;
create trigger trg_member_meal_schedule_updated_at
  before update on public.member_meal_schedule
  for each row execute function set_updated_at();

alter table public.member_meal_schedule enable row level security;

drop policy if exists member_meal_schedule_member_self_select on public.member_meal_schedule;
create policy member_meal_schedule_member_self_select on public.member_meal_schedule
  for select to authenticated
  using (patient_id = current_member_patient_id());

drop policy if exists member_meal_schedule_member_self_insert on public.member_meal_schedule;
create policy member_meal_schedule_member_self_insert on public.member_meal_schedule
  for insert to authenticated
  with check (patient_id = current_member_patient_id());

drop policy if exists member_meal_schedule_member_self_update on public.member_meal_schedule;
create policy member_meal_schedule_member_self_update on public.member_meal_schedule
  for update to authenticated
  using (patient_id = current_member_patient_id())
  with check (patient_id = current_member_patient_id());

drop policy if exists member_meal_schedule_clinic_staff_read on public.member_meal_schedule;
create policy member_meal_schedule_clinic_staff_read on public.member_meal_schedule
  for select to authenticated
  using (can_access_patient(patient_id));

drop policy if exists service_role_bypass_member_meal_schedule on public.member_meal_schedule;
create policy service_role_bypass_member_meal_schedule on public.member_meal_schedule
  for all to service_role using (true) with check (true);

-- ─────────────────────────────────────────────── the seed

create or replace function public.member_meal_schedule_seed()
returns setof public.member_meal_schedule
language plpgsql
security invoker
set search_path = public, pg_catalog
as $$
declare
  v_patient uuid := current_member_patient_id();
  v_skip_breakfast boolean := false;
  v_snacks integer := 0;
begin
  if v_patient is null then
    return;
  end if;

  if not exists (select 1 from member_meal_schedule where patient_id = v_patient) then
    -- The intake's own stored value (MEMBERS intake-v1 `breakfast`); a draft does not count.
    select coalesce(q.answers ->> 'breakfast' = 'I usually skip breakfast', false)
      into v_skip_breakfast
      from patient_intake_questionnaire q
     where q.patient_id = v_patient and q.status = 'submitted'
     order by q.submitted_at desc nulls last
     limit 1;

    select coalesce(p.snacks_per_day, 0)
      into v_snacks
      from nb_patient_app_profiles p
     where p.patient_id = v_patient
     limit 1;

    v_skip_breakfast := coalesce(v_skip_breakfast, false);
    v_snacks := coalesce(v_snacks, 0);

    insert into member_meal_schedule (patient_id, slot, weekday, enabled, remind_at, source, updated_via)
    select v_patient, s.slot, d.weekday,
           case s.slot
             when 'breakfast' then not v_skip_breakfast
             when 'morning_snack' then v_snacks >= 1
             when 'afternoon_snack' then v_snacks >= 2
             else true
           end,
           s.remind_at,
           case
             when s.slot = 'breakfast' and v_skip_breakfast then 'intake'
             when s.slot = 'morning_snack' and v_snacks >= 1 then 'profile'
             when s.slot = 'afternoon_snack' and v_snacks >= 2 then 'profile'
             else 'default'
           end,
           'engine'
      from (values ('breakfast', time '08:00'),
                   ('morning_snack', time '10:00'),
                   ('lunch', time '12:00'),
                   ('afternoon_snack', time '16:00'),
                   ('dinner', time '20:00')) as s(slot, remind_at)
     cross join generate_series(1, 7) as d(weekday)
    on conflict (patient_id, slot, weekday) do nothing;
  end if;

  return query
    select * from member_meal_schedule
     where patient_id = v_patient
     order by weekday, remind_at;
end $$;

comment on function public.member_meal_schedule_seed() is
  'Returns the caller''s meal-reminder schedule, creating its 35 rows on first call (intake skip-breakfast and profile snacks_per_day applied, else defaults). SECURITY INVOKER: RLS scopes every read and write to the caller.';

revoke all on function public.member_meal_schedule_seed() from public, anon;
grant execute on function public.member_meal_schedule_seed() to authenticated;
