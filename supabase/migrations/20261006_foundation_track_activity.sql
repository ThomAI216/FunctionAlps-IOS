-- What a member DID on the Foundation Track: an action checked off, a video watched, a short read
-- opened. Feeds Thomas's day-7 email ("how much did they do?") and the CLINICAL board.
-- ADDITIVE ONLY. Thomas, 2026-10-06 (pending explicit OK before apply).
--
-- One row per (member, day, kind, item): checking an action twice is a no-op, un-checking deletes
-- the row. A member may only touch today or yesterday (Zurich), the same window habit_completions
-- allows, so the record cannot be back-filled into a better-looking week.

create table public.track_activity (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients(id) on delete cascade,
  track_code   text not null references public.app_track(code),
  day          int  not null check (day >= 1),
  kind         text not null check (kind in ('action', 'video', 'read')),
  item_key     text not null,                      -- the action key from track_day.actions, or 'day' for video/read
  created_at   timestamptz not null default now(),
  unique (patient_id, track_code, day, kind, item_key)
);
comment on table public.track_activity is
  'Foundation Track activity: actions checked off, videos watched, reads opened. One row per member/day/kind/item; members write today or yesterday only.';
create index track_activity_patient_idx on public.track_activity (patient_id, track_code);

alter table public.track_activity enable row level security;

create policy staff_read_track_activity on public.track_activity for select to authenticated
  using (public.is_nutritionist_or_above());

create policy member_self_read_track_activity on public.track_activity for select to authenticated
  using (patient_id = public.current_member_patient_id());

-- the day written must be today's or yesterday's track day for this member
create policy member_self_insert_track_activity on public.track_activity for insert to authenticated
  with check (
    patient_id = public.current_member_patient_id()
    and exists (
      select 1 from public.member_track_enrollment e
       where e.patient_id = track_activity.patient_id
         and e.track_code = track_activity.track_code
         and e.started_at is not null
         and track_activity.day between
               ((now() at time zone e.timezone)::date - (e.started_at at time zone e.timezone)::date)
           and ((now() at time zone e.timezone)::date - (e.started_at at time zone e.timezone)::date) + 1
    )
  );

create policy member_self_delete_track_activity on public.track_activity for delete to authenticated
  using (patient_id = public.current_member_patient_id() and kind = 'action' and created_at > now() - interval '2 days');
