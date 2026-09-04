-- Notifications for the native app (2026-09-04). Additive.
--
-- The phone schedules its own LOCAL reminders (check-in moments, meals not logged, the 2.5 h post-meal
-- "how do you feel", the weekly summary) from `patient_notification_preferences`. The SERVER pushes only
-- what it alone knows: a practitioner message, an approved report, a care-plan change, a meal that needs
-- the member's input — through `notify_member_push()` → edge fn `push-send` (APNs), content-free
-- (no health data in a push; the link is the payload — the same rule as message-notify's emails).

alter table public.patient_notification_preferences
  add column if not exists midday_checkin_enabled   boolean not null default true,
  add column if not exists midday_checkin_time      time    not null default '14:30:00',
  add column if not exists meal_reminders_enabled   boolean not null default true,
  add column if not exists messages_enabled         boolean not null default true,
  add column if not exists reports_enabled          boolean not null default true,
  add column if not exists care_plan_enabled        boolean not null default true,
  add column if not exists quiet_hours_enabled      boolean not null default true,
  add column if not exists quiet_hours_start        time    not null default '22:00:00',
  add column if not exists quiet_hours_end          time    not null default '07:30:00',
  add column if not exists push_enabled             boolean not null default true,
  add column if not exists apns_token               text,
  add column if not exists apns_environment         text check (apns_environment in ('production', 'sandbox')),
  add column if not exists apns_token_updated_at    timestamptz,
  add column if not exists device_platform          text,
  add column if not exists app_version              text;

-- Members may also INSERT their own row (the 023 policy is `for all using (...)` — add the check side explicitly).
drop policy if exists "Patients insert their own notification preferences" on public.patient_notification_preferences;
create policy "Patients insert their own notification preferences"
  on public.patient_notification_preferences for insert to authenticated
  with check (patient_id in (select id from public.patients where auth_user_id = auth.uid()));

-- One place that records the notification and asks push-send to deliver it.
create or replace function public.notify_member_push(
  p_patient_id uuid, p_type text, p_title text, p_body text, p_route text, p_collapse text default null, p_throttle interval default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_secret text;
begin
  if p_throttle is not null and exists (
    select 1 from public.patient_notifications
     where patient_id = p_patient_id and type = p_type and created_at > now() - p_throttle
  ) then
    return null;
  end if;
  insert into public.patient_notifications (patient_id, type, title, body, trigger_type, scheduled_for, data_json, priority)
  values (p_patient_id, p_type, p_title, p_body, 'event_driven', now(), jsonb_build_object('route', p_route, 'collapse', p_collapse), 'normal')
  returning id into v_id;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'report_secret';
  perform net.http_post(
    url := 'https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/push-send',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-report-secret', coalesce(v_secret, '')),
    body := jsonb_build_object('notification_id', v_id)
  );
  return v_id;
end $$;
revoke all on function public.notify_member_push(uuid, text, text, text, text, text, interval) from public, anon, authenticated;

-- 1. A practitioner's message (content-free).
create or replace function public.trg_notify_patient_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.sender_type <> 'patient' and new.visibility_class = 'patient_visible' then
    perform public.notify_member_push(new.patient_id, 'practitioner_message',
      'New message from your practitioner', 'Open FunctionAlps to read it.',
      'functionalps://messages', 'messages', interval '10 minutes');
  end if;
  return new;
end $$;
drop trigger if exists patient_messages_notify_push on public.patient_messages;
create trigger patient_messages_notify_push after insert on public.patient_messages
  for each row execute function public.trg_notify_patient_message();

-- 2. A report interpretation the clinician approved.
create or replace function public.trg_notify_report_approved() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
    perform public.notify_member_push(new.patient_id, 'report_ready',
      case when new.period = 'monthly' then 'Your monthly report is ready' else 'Your weekly report is ready' end,
      'Your practitioner has reviewed it. Open FunctionAlps to read it.',
      'functionalps://trends', 'report', interval '1 hour');
  end if;
  return new;
end $$;
drop trigger if exists nb_report_interpretations_notify_push on public.nb_report_interpretations;
create trigger nb_report_interpretations_notify_push after insert or update of status on public.nb_report_interpretations
  for each row execute function public.trg_notify_report_approved();

-- 3. The care plan changed (throttled: one push per 6 hours).
create or replace function public.trg_notify_care_plan() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_patient uuid;
begin
  -- care_plan_items has no patient_id: the plan carries it (only active plans notify).
  select p.patient_id into v_patient from public.care_plans p where p.id = coalesce(new.care_plan_id, old.care_plan_id) and p.status::text = 'active';
  if v_patient is null then return new; end if;
  perform public.notify_member_push(v_patient, 'care_plan_update',
    'Your care plan was updated', 'Open FunctionAlps to see what changed.',
    'functionalps://careplan', 'careplan', interval '6 hours');
  return new;
end $$;
drop trigger if exists care_plan_items_notify_push on public.care_plan_items;
create trigger care_plan_items_notify_push after insert or update on public.care_plan_items
  for each row execute function public.trg_notify_care_plan();

-- 4. A meal analysis that needs the member's input.
create or replace function public.trg_notify_meal_needs_input() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.analysis_status = 'needs_input' and old.analysis_status is distinct from 'needs_input' then
    perform public.notify_member_push(new.patient_id, 'meal_needs_input',
      'One detail about your meal', 'We need a little more to finish the analysis.',
      'functionalps://meal/' || new.id::text, 'meal-' || new.id::text, null);
  end if;
  return new;
end $$;
drop trigger if exists nb_meal_logs_notify_needs_input on public.nb_meal_logs;
create trigger nb_meal_logs_notify_needs_input after update of analysis_status on public.nb_meal_logs
  for each row execute function public.trg_notify_meal_needs_input();

-- Sweep: rows not delivered (quiet hours, transient APNs errors) are retried every 15 minutes for 24 h.
do $$ begin perform cron.unschedule('push-send-sweep'); exception when others then null; end $$;
select cron.schedule('push-send-sweep', '*/15 * * * *', $$
  select net.http_post(
    url := 'https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/push-send',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-report-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'report_secret'), '')),
    body := '{"sweep": true}'::jsonb
  )
  where exists (select 1 from public.patient_notifications where delivered_at is null and dismissed_at is null and trigger_type = 'event_driven' and created_at > now() - interval '24 hours');
$$);
