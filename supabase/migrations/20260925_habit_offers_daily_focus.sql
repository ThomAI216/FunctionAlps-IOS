-- Today's focus: the columns `member-daily-focus` needs on `habit_offers`.
--
-- The table was built for state-driven offers (Habit Loop v2: `state_responses` → `habit_offers`) and has
-- never held a row. The engine now fills it, one row per offer per day, and the day holds STILL once
-- computed — a focus that reshuffles when a ring syncs at 09:30 is worse than one that stays. So a
-- re-computed day retires its old rows instead of deleting them (members hold no DELETE policy here,
-- and a retired offer is still a true record of what was put in front of them).
--
--   rank        1 = the day's focus, 2–3 = "also today"
--   reason      why it is there: state · priority · readiness_low · recovery_support
--   pillar      nutrition · exercise · mind · emotion · recovery · sleep (null for a state offer with no bank twin)
--   slot        morning · midday · evening (the habit's default moment)
--   variant     easy · standard · progression — the intensity readiness chose
--   superseded  retired by a later computation the same day; kept for the practitioner, hidden from the member
--
-- Additive and nullable: the web app's habit code (flag OFF) reads none of these.

alter table public.habit_offers
  add column if not exists rank smallint,
  add column if not exists reason text,
  add column if not exists pillar text,
  add column if not exists slot text,
  add column if not exists variant text,
  add column if not exists superseded boolean not null default false;

comment on column public.habit_offers.rank is 'Today''s focus ordering: 1 = the focus, 2–3 = also today (member-daily-focus).';
comment on column public.habit_offers.reason is 'Why the engine offered it: state | priority | readiness_low | recovery_support.';
comment on column public.habit_offers.variant is 'Intensity chosen from readiness: easy | standard | progression.';
comment on column public.habit_offers.superseded is 'Retired by a later computation the same day. Kept as a record; not shown to the member.';

create index if not exists habit_offers_patient_day_idx on public.habit_offers (patient_id, offered_on);
