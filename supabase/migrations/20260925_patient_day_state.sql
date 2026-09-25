-- The day as the decision engine read it — stored once, so it holds still.
--
-- `member-daily-focus` reads the member's readiness once after the morning check-in (wearable recovery when
-- there is one, the morning's own sleep score otherwise) and banded it low · mid · high on the check-in
-- engine's own cut-offs. Today's focus already holds still by storing its offers; the habits' faces (the
-- gentler version on a low day, a step further on a high day) read the SAME band, and this row is what lets
-- them hold still too — a ring syncing at 09:30 never flips a habit's face. It is also a plain record for the
-- practitioner of what the app took the day for.
--
-- One row per member per day. Members write their own rows for today ± 1 (patient-local, like habit_offers)
-- and read their own; clinic staff read. Never read by evaluate-gates: gates stay completion arithmetic.

create table if not exists public.patient_day_state (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  day date not null,
  -- null = the morning gave no band (no wearable row, no sleep score): habits show as written.
  readiness_band text check (readiness_band in ('low', 'mid', 'high')),
  -- The recovery score the band came from, when a wearable gave one.
  readiness smallint check (readiness between 0 and 100),
  -- True only when a ≥14-day personal HRV baseline backs `readiness` — the condition for "below your usual".
  readiness_vs_baseline boolean not null default false,
  band_source text check (band_source in ('wearable', 'self_report')),
  -- The states the morning revealed (stressed, slept_poorly, …), hardest first.
  states text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (patient_id, day)
);

comment on table public.patient_day_state is
  'The day as member-daily-focus read it: readiness band (low/mid/high) and detected states, stored once after the morning check-in so the focus and the habits'' faces hold still through the day. One row per member per day.';

create trigger trg_patient_day_state_updated_at
  before update on public.patient_day_state
  for each row execute function set_updated_at();

alter table public.patient_day_state enable row level security;

create policy patient_day_state_member_self_select on public.patient_day_state
  for select to authenticated
  using (patient_id = current_member_patient_id());

create policy patient_day_state_member_self_insert on public.patient_day_state
  for insert to authenticated
  with check (patient_id = current_member_patient_id()
              and day >= patient_local_today(patient_id) - 1 and day <= patient_local_today(patient_id));

create policy patient_day_state_member_self_update on public.patient_day_state
  for update to authenticated
  using (patient_id = current_member_patient_id()
         and day >= patient_local_today(patient_id) - 1 and day <= patient_local_today(patient_id))
  with check (patient_id = current_member_patient_id()
              and day >= patient_local_today(patient_id) - 1 and day <= patient_local_today(patient_id));

create policy patient_day_state_clinic_staff_read on public.patient_day_state
  for select to authenticated
  using (can_access_patient(patient_id));

create policy service_role_bypass_patient_day_state on public.patient_day_state
  for all to service_role using (true) with check (true);
