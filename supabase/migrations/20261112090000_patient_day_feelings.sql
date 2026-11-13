-- "Feeling for the day": how the member feels when the day starts (owner-validated 2026-11-12).
--
-- The new MORNING check-in asks three things before the day begins: mood, felt energy and motivation (0-100,
-- the same sliders as everywhere), each with a short "why might it be low?" / "what helped?" list of pills.
-- It is a different question from the daily check-in's mood and energy (which look BACK on the day), so it lives
-- in its own table: nothing here ever enters `patient_checkin_moments` or the day's mood / energy medians
-- (`member_submit_checkin` never reads this table).
--
-- One row per member per day, written by the member's own phone (upsert on patient_id, day). `pills` is the
-- picked options by group: {"mood_why": [...], "mood_helped": [...], "energy_why": [...], "energy_helped": [...],
-- "motivation_why": [...], "motivation_helped": [...]} — only the group the slider's band asks (< 40 -> why,
-- >= 60 -> helped). `end_rule` is the id of the end-screen rule the member was shown (MorningRules.swift), kept
-- so the practice can see which message went with which morning.
--
-- Members read and write their own rows for today and yesterday (patient-local, like patient_day_state); clinic
-- staff read, with the same role check CLINICAL uses on nb_user_patterns.
--
-- ADDITIVE and IDEMPOTENT. Not applied by the commit that adds it — the owner applies it after review. Until it is
-- applied the app treats the missing table as "no feeling saved" (the morning check-in still saves the night).

create table if not exists public.patient_day_feelings (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  day date not null,
  mood smallint check (mood between 0 and 100),
  energy smallint check (energy between 0 and 100),
  motivation smallint check (motivation between 0 and 100),
  pills jsonb not null default '{}'::jsonb,
  end_rule text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (patient_id, day)
);

comment on table public.patient_day_feelings is
  'How the member feels when the day starts (morning check-in): mood, felt energy, motivation 0-100, each with its why-low / what-helped pills, and the id of the end-screen rule shown. Separate from patient_checkin_moments on purpose: it never enters the day''s mood / energy medians. One row per member per day.';

do $$ begin
  create trigger trg_patient_day_feelings_updated_at
    before update on public.patient_day_feelings
    for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

alter table public.patient_day_feelings enable row level security;

do $$ begin
  create policy patient_day_feelings_member_self_select on public.patient_day_feelings
    for select to authenticated
    using (patient_id = public.current_member_patient_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy patient_day_feelings_member_self_insert on public.patient_day_feelings
    for insert to authenticated
    with check (patient_id = public.current_member_patient_id()
                and day >= public.patient_local_today(patient_id) - 1 and day <= public.patient_local_today(patient_id));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy patient_day_feelings_member_self_update on public.patient_day_feelings
    for update to authenticated
    using (patient_id = public.current_member_patient_id()
           and day >= public.patient_local_today(patient_id) - 1 and day <= public.patient_local_today(patient_id))
    with check (patient_id = public.current_member_patient_id()
                and day >= public.patient_local_today(patient_id) - 1 and day <= public.patient_local_today(patient_id));
exception when duplicate_object then null; end $$;

-- Practitioners read, with the same staff-role check as "Practitioners can read user patterns" on nb_user_patterns.
do $$ begin
  create policy patient_day_feelings_practitioner_read on public.patient_day_feelings
    for select to authenticated
    using (exists (
      select 1 from public.users u
       where u.auth_user_id = auth.uid()
         and u.role in ('lead_nutritionist', 'nutritionist', 'nurse', 'super_admin')
    ));
exception when duplicate_object then null; end $$;

do $$ begin
  create policy service_role_all_patient_day_feelings on public.patient_day_feelings
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;

revoke all on public.patient_day_feelings from anon;
