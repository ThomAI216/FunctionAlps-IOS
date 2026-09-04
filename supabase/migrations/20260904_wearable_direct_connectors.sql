-- Direct wearable connectors (owner decision 2026-09-04: free, direct OAuth — Withings, Suunto, Oura,
-- Polar, WHOOP, Garmin, Google; Thryve removed). Additive except the Thryve cron, which is unscheduled.
--
-- Tables: wearable_vendors (the offer; owner flips status to 'available' once a developer app is
-- approved), wearable_vendor_accounts (encrypted tokens — service role only), wearable_oauth_states
-- (single-use, 10 min). wearable_sync_queue gains `vendor`; wearable_raw_events accepts the three new
-- kinds. Catalogue rows ≥ 1000100 for vendor scores and the gaps (temperature deviation, glucose, cycle,
-- body fat, blood pressure). Source ids: 1000000 + a stable number per vendor (Apple Health stays 1000001).

create table if not exists public.wearable_vendors (
  key            text primary key,
  name           text not null,
  data_source_id integer not null unique,
  status         text not null default 'planned' check (status in ('planned', 'available', 'paused')),
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
alter table public.wearable_vendors enable row level security;
drop policy if exists "wearable_vendors_read" on public.wearable_vendors;
create policy "wearable_vendors_read" on public.wearable_vendors for select to authenticated using (true);

insert into public.wearable_vendors (key, name, data_source_id, notes) values
  ('oura',     'Oura',     1000018, 'Oura API v2 — self-serve; nightly RMSSD'),
  ('whoop',    'WHOOP',    1000042, 'WHOOP API v2 — self-serve; RMSSD per sleep'),
  ('polar',    'Polar',    1000003, 'Polar AccessLink — self-serve; Nightly Recharge HRV'),
  ('garmin',   'Garmin',   1000002, 'Garmin Health API — partner application; HRV nightly avg, stress'),
  ('withings', 'Withings', 1000008, 'Withings API — self-serve; RMSSD + SDNN, weight, BP'),
  ('suunto',   'Suunto',   1000050, 'Suunto Cloud API — self-serve (2026); sleep + recovery webhooks'),
  ('google',   'Google (Fitbit)', 1000011, 'Google Health API — restricted scopes + CASA; decision pending')
on conflict (key) do update set name = excluded.name, data_source_id = excluded.data_source_id, updated_at = now();

create table if not exists public.wearable_vendor_accounts (
  id                uuid primary key default uuid_generate_v4(),
  patient_id        uuid not null references public.patients(id) on delete cascade,
  vendor            text not null references public.wearable_vendors(key),
  vendor_user_id    text,
  access_token_enc  text,                       -- AES-256-GCM, WEARABLE_TOKEN_KEY (edge functions)
  refresh_token_enc text,
  token_expires_at  timestamptz,
  scopes            text[],
  status            text not null default 'connected' check (status in ('connected', 'revoked', 'error')),
  last_error        text,
  last_sync_at      timestamptz,
  meta              jsonb,
  connected_at      timestamptz not null default now(),
  revoked_at        timestamptz,
  updated_at        timestamptz not null default now(),
  unique (patient_id, vendor)
);
create index if not exists wearable_vendor_accounts_vendor_user on public.wearable_vendor_accounts (vendor, vendor_user_id);
alter table public.wearable_vendor_accounts enable row level security;   -- no policies: service role only
revoke all on public.wearable_vendor_accounts from anon, authenticated;

create table if not exists public.wearable_oauth_states (
  state         text primary key,
  patient_id    uuid not null references public.patients(id) on delete cascade,
  vendor        text not null references public.wearable_vendors(key),
  code_verifier text,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null
);
alter table public.wearable_oauth_states enable row level security;
revoke all on public.wearable_oauth_states from anon, authenticated;

alter table public.wearable_sync_queue add column if not exists vendor text references public.wearable_vendors(key);
create index if not exists wearable_sync_queue_pending_vendor on public.wearable_sync_queue (status, vendor) where status = 'pending';

alter table public.wearable_raw_events drop constraint if exists wearable_raw_events_kind_check;
alter table public.wearable_raw_events add constraint wearable_raw_events_kind_check check (kind in (
  'webhook_notification', 'webhook_push', 'connection', 'api_daily', 'api_epoch', 'native_healthkit',
  'oauth_callback', 'vendor_webhook', 'vendor_api'));

-- Catalogue: vendor scores + the gaps (layer 'raw' so the labelled views carry them; the engine reads by name).
insert into public.wearable_data_types (data_type_id, name, category, granularity, unit, value_type, layer, description, sources) values
  (1000100, 'ReadinessScore',           'Vendor scores',   'daily', 'score 0-100', 'DOUBLE', 'raw', 'Vendor readiness (Oura readiness, Polar Nightly Recharge status)', array['Oura','Polar']),
  (1000101, 'RecoveryScore',            'Vendor scores',   'daily', 'score 0-100', 'DOUBLE', 'raw', 'Vendor recovery (WHOOP recovery %)', array['Whoop']),
  (1000102, 'StrainScore',              'Vendor scores',   'daily', 'score',       'DOUBLE', 'raw', 'Vendor strain (WHOOP day strain 0-21)', array['Whoop']),
  (1000103, 'BodyBattery',              'Vendor scores',   'daily', 'score 0-100', 'DOUBLE', 'raw', 'Garmin Body Battery (day high / low in details)', array['Garmin']),
  (1000104, 'ANSCharge',                'Vendor scores',   'daily', 'score',       'DOUBLE', 'raw', 'Polar Nightly Recharge ANS charge (-10..10)', array['Polar']),
  (1000105, 'SleepScore',               'Vendor scores',   'daily', 'score 0-100', 'DOUBLE', 'raw', 'Vendor sleep score (Oura, WHOOP sleep performance, Garmin, Withings, Polar)', array['Oura','Whoop','Garmin','Withings','Polar','Suunto']),
  (1000106, 'SkinTemperatureDeviation', 'Body',            'daily', '°C',          'DOUBLE', 'raw', 'Nightly skin temperature deviation from the personal baseline', array['Oura','Garmin','Fitbit']),
  (1000107, 'BloodGlucose',             'Metabolic',       'both',  'mmol/L',      'DOUBLE', 'raw', 'Blood glucose (CGM or manual); mg/dL ÷ 18.016', array['AppleHealth','Fitbit']),
  (1000108, 'MenstrualCycleDay',        'Women''s health', 'daily', 'day',         'LONG',   'raw', 'Day of the cycle (1 = first day of period); phase in details', array['Garmin','AppleHealth']),
  (1000109, 'StressScore',              'Vendor scores',   'daily', 'score 0-100', 'DOUBLE', 'raw', 'Vendor daily stress score (Oura daytime stress, WHOOP, Withings)', array['Oura','Whoop','Withings']),
  (1000110, 'SkinTemperature',          'Body',            'daily', '°C',          'DOUBLE', 'raw', 'Absolute skin temperature (WHOOP, Withings)', array['Whoop','Withings']),
  (1000111, 'BodyFatPercent',           'Body',            'daily', '%',           'DOUBLE', 'raw', 'Body fat percentage (scales)', array['Withings','Garmin','AppleHealth']),
  (1000112, 'DiastolicBP',              'Cardio',          'both',  'mmHg',        'DOUBLE', 'raw', 'Diastolic blood pressure', array['Withings','Garmin','AppleHealth']),
  (1000113, 'SystolicBP',               'Cardio',          'both',  'mmHg',        'DOUBLE', 'raw', 'Systolic blood pressure', array['Withings','Garmin','AppleHealth'])
on conflict (data_type_id) do update set name = excluded.name, category = excluded.category, unit = excluded.unit, layer = excluded.layer, description = excluded.description, sources = excluded.sources;

-- Thryve: gone. The queue drainer becomes wearable-vendor-sync (same x-report-secret convention as 062).
do $$ begin perform cron.unschedule('thryve-sync'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('wearable-vendor-sync'); exception when others then null; end $$;
select cron.schedule('wearable-vendor-sync', '*/10 * * * *', $$
  select net.http_post(
    url := 'https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-vendor-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-report-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'report_secret'), '')
    ),
    body := '{}'::jsonb
  )
  where exists (select 1 from public.wearable_sync_queue where status = 'pending' and vendor is not null);
$$);

-- Expired OAuth states are swept hourly.
do $$ begin perform cron.unschedule('wearable-oauth-states-sweep'); exception when others then null; end $$;
select cron.schedule('wearable-oauth-states-sweep', '17 * * * *', $$ delete from public.wearable_oauth_states where expires_at < now() $$);
