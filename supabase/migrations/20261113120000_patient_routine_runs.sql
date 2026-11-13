-- Routine runs: the practice sees whether a member did a routine it offered (owner-validated 2026-11-13).
--
-- The "Kickoff morning routine" is offered on a hard morning (the morning check-in's Today's focus decides) and is due within
-- an hour of the member waking (the wake time of last night as the morning check-in recorded it, else 10:00 local). The app
-- upserts one row per (patient, day, routine) when the green row is first shown (offered_at, due_at, focus_cell), updates
-- steps_done as the steps are ticked, and sets completed_at when the member finishes the walk.
--
-- The STATUS is derived, never stored:
--   done on time = completed_at <= due_at (or due_at is null)
--   done late    = completed_at >  due_at
--   missed       = completed_at is null and now() > due_at
--   open         = otherwise
--
-- Members read and write their own rows for today and the two days before (patient-local, like patient_day_state); clinic staff
-- read, with the same role check CLINICAL uses on nb_user_patterns (as patient_day_feelings does).
--
-- ADDITIVE and IDEMPOTENT. Not applied by the commit that adds it: the owner applies it after review. Until it is applied the app
-- keeps the day's run on the phone and reads a missing table as "no run yet" (the walk and the green row still work).

create table if not exists public.patient_routine_runs (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  day date not null,
  routine text not null check (routine in ('kickoff_morning')),
  focus_cell text,
  offered_at timestamptz not null default now(),
  due_at timestamptz,
  completed_at timestamptz,
  steps_done smallint not null default 0 check (steps_done between 0 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (patient_id, day, routine)
);

comment on table public.patient_routine_runs is
  'A routine the app offered a member on a day (today: the kickoff morning routine) and how it went. One row per member, day and routine, upserted by the member''s own phone. Status is derived, not stored: done on time = completed_at <= due_at (or due_at null); done late = completed_at > due_at; missed = completed_at null and now() > due_at; open otherwise.';
comment on column public.patient_routine_runs.id is 'Row id.';
comment on column public.patient_routine_runs.patient_id is 'The member (public.patients.id). Rows go with the patient.';
comment on column public.patient_routine_runs.day is 'The member''s own local day the routine was offered on.';
comment on column public.patient_routine_runs.routine is 'Which routine. Only kickoff_morning for now (the routine for a slow or difficult morning).';
comment on column public.patient_routine_runs.focus_cell is 'The Today''s focus matrix cell the routine was offered on (for example P5), as stored on patient_day_state.focus_cell.';
comment on column public.patient_routine_runs.offered_at is 'When the app first showed the routine to the member that day.';
comment on column public.patient_routine_runs.due_at is 'When the routine is due: one hour after the member woke up (the morning check-in''s wake time, or the wearable''s), else 10:00 local. Null when the day could not be worked out.';
comment on column public.patient_routine_runs.completed_at is 'When the member finished the walk. Null while not finished.';
comment on column public.patient_routine_runs.steps_done is 'How many steps of the routine were ticked (0 to 20).';
comment on column public.patient_routine_runs.created_at is 'Row creation time.';
comment on column public.patient_routine_runs.updated_at is 'Last change, kept by the updated_at trigger.';

create index if not exists patient_routine_runs_patient_day_idx
  on public.patient_routine_runs (patient_id, day desc);

do $$ begin
  create trigger trg_patient_routine_runs_updated_at
    before update on public.patient_routine_runs
    for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

alter table public.patient_routine_runs enable row level security;

do $$ begin
  create policy patient_routine_runs_member_self_select on public.patient_routine_runs
    for select to authenticated
    using (patient_id = public.current_member_patient_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy patient_routine_runs_member_self_insert on public.patient_routine_runs
    for insert to authenticated
    with check (patient_id = public.current_member_patient_id()
                and day between public.patient_local_today(patient_id) - 2 and public.patient_local_today(patient_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy patient_routine_runs_member_self_update on public.patient_routine_runs
    for update to authenticated
    using (patient_id = public.current_member_patient_id()
           and day between public.patient_local_today(patient_id) - 2 and public.patient_local_today(patient_id))
    with check (patient_id = public.current_member_patient_id()
                and day between public.patient_local_today(patient_id) - 2 and public.patient_local_today(patient_id));
exception when duplicate_object then null; end $$;

-- Practitioners read, with the same staff-role check as "Practitioners can read user patterns" on nb_user_patterns.
do $$ begin
  create policy patient_routine_runs_practitioner_read on public.patient_routine_runs
    for select to authenticated
    using (exists (
      select 1 from public.users u
       where u.auth_user_id = auth.uid()
         and u.role in ('lead_nutritionist', 'nutritionist', 'nurse', 'super_admin')
    ));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy service_role_all_patient_routine_runs on public.patient_routine_runs
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;

revoke all on public.patient_routine_runs from anon;
