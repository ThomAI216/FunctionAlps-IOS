-- Leads run the Foundation Track automatically (Thomas, 2026-11-05).
--
-- A lead (leads pathway, CLINICAL migration 20261104120000: patients.care_stage
-- 'lead', entitlement access_type 'lead' / plan lead_14_day, 14 days from the
-- first sign-in) gets the 14-day track without anyone pressing "Launch":
--
--   1. member_track_enrollment.source gains 'lead'. A lead row may be written
--      before the member opens the app (started_at NULL, like a staff launch), so
--      CLINICAL's Add-a-patient card can enrol the lead at Send and the board
--      shows them as invited from the first minute.
--   2. member_start_track: a member with no enrolment who IS a lead (care_stage
--      'lead', or a live lead entitlement) is enrolled on the spot, source 'lead',
--      the clock started. Everyone else keeps the 2026-10-12 rule: app_track
--      .launched_at is NULL, so nobody else joins on their own.
--   3. member_library_is_active() and member_library_allowed_tiers_for_patient():
--      a live lead entitlement opens the members library for those 14 days, so the
--      day's short read (track_day.read_slug) and the card's library items are
--      readable, not locked. Nothing else about the tiers changes.
--
-- Additive: no column dropped, no row rewritten, every existing value still valid.

-- 1 ─ source 'lead' ─────────────────────────────────────────────────────────
alter table public.member_track_enrollment drop constraint if exists member_track_enrollment_source_check;
alter table public.member_track_enrollment add constraint member_track_enrollment_source_check
  check (source = any (array['ios_first_open'::text, 'web_first_open'::text, 'staff'::text, 'lead'::text]));

alter table public.member_track_enrollment drop constraint if exists member_track_enrollment_check;
alter table public.member_track_enrollment add constraint member_track_enrollment_check
  check (started_at is not null or source in ('staff', 'lead'));

-- 2 ─ member_start_track: a lead enrols on their own ─────────────────────────
create or replace function public.member_start_track(p_track_code text default 'foundation_v1', p_via text default 'ios')
returns public.member_track_enrollment
language plpgsql security definer set search_path = ''
as $$
declare
  v_pid      uuid := public.current_member_patient_id();
  v_row      public.member_track_enrollment;
  v_launched timestamptz;
  v_created  timestamptz;
  v_is_lead  boolean;
begin
  if v_pid is null then return null; end if;

  select * into v_row from public.member_track_enrollment where patient_id = v_pid and track_code = p_track_code;
  if found then
    if v_row.started_at is null then
      update public.member_track_enrollment set started_at = now()
       where id = v_row.id and started_at is null
       returning * into v_row;
    end if;
    return v_row;
  end if;

  -- A lead (leads pathway) runs the track automatically: their 14 days start now.
  select exists (
           select 1 from public.patients p where p.id = v_pid and p.care_stage = 'lead'
         ) or exists (
           select 1 from public.member_entitlements e
            where e.patient_id = v_pid and e.access_type = 'lead'
              and e.status in ('active', 'grace')
              and (e.expires_at is null or e.expires_at > now())
         )
    into v_is_lead;
  if v_is_lead and exists (select 1 from public.app_track where code = p_track_code and active) then
    insert into public.member_track_enrollment (patient_id, track_code, source, started_at)
    values (v_pid, p_track_code, 'lead', now())
    on conflict (patient_id, track_code) do nothing;
    select * into v_row from public.member_track_enrollment where patient_id = v_pid and track_code = p_track_code;
    return v_row;
  end if;

  -- Everyone else: only a launched track enrols newcomers (launched_at is NULL
  -- since 2026-10-12, so members are launched one by one from CLINICAL).
  select launched_at into v_launched from public.app_track where code = p_track_code and active;
  if v_launched is null then return null; end if;

  select created_at into v_created from public.patients where id = v_pid;
  if v_created is null or v_created < v_launched then return null; end if;

  insert into public.member_track_enrollment (patient_id, track_code, source, started_at)
  values (v_pid, p_track_code, case when p_via = 'web' then 'web_first_open' else 'ios_first_open' end, now())
  on conflict (patient_id, track_code) do nothing;

  select * into v_row from public.member_track_enrollment where patient_id = v_pid and track_code = p_track_code;
  return v_row;
end $$;

-- 3 ─ the library opens for a live lead entitlement ─────────────────────────
create or replace function public.member_library_is_active()
returns boolean
language sql stable security definer set search_path = ''
as $$
  with pid as ( select public.current_member_patient_id() as patient_id )
  select case
    when (select patient_id from pid) is null then false
    when exists ( select 1 from public.member_entitlements e, pid
      where e.patient_id = pid.patient_id and e.access_type in ('paid','beta','full_access','lead')
        and e.status in ('active','grace') and (e.expires_at is null or e.expires_at > now()) ) then true
    when exists ( select 1 from public.nb_patient_app_profiles p, pid
      where p.patient_id = pid.patient_id and (
          (p.trial_started_at is not null and now() < p.trial_started_at + interval '5 days')
          or (p.trial_extended_at is not null and now() < p.trial_extended_at + interval '5 days') ) ) then true
    else false end;
$$;

create or replace function public.member_library_allowed_tiers_for_patient(p_patient_id uuid)
returns public.library_visibility[]
language sql stable security definer set search_path = ''
as $$
  select case when (
    p_patient_id is not null and (
      exists ( select 1 from public.member_entitlements e
        where e.patient_id = p_patient_id
          and e.access_type in ('paid','beta','full_access','lead')
          and e.status in ('active','grace')
          and (e.expires_at is null or e.expires_at > now()) )
      or exists ( select 1 from public.nb_patient_app_profiles p
        where p.patient_id = p_patient_id and (
          (p.trial_started_at is not null and now() < p.trial_started_at + interval '5 days')
          or (p.trial_extended_at is not null and now() < p.trial_extended_at + interval '5 days') ) )
    )
  )
  then array['public_free','public_paid','patient_tier_1','patient_tier_2','patient_tier_3','workshop_attendee']::public.library_visibility[]
  else array['public_free']::public.library_visibility[] end;
$$;
