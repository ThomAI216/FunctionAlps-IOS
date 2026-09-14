-- Wearables Phase 1 — platform hardening (strategy 2026-09-14 §Phase 1). ADDITIVE ONLY on the shared CM OS
-- database: new columns (all nullable or defaulted), new tables, widened check constraints (supersets of the
-- old value sets), new RPCs (service_role only), one new cron job, one refined cron predicate. No row is
-- deleted, no existing key changes. Zero vendor accounts / states / vendor jobs existed at apply time.
--
-- Deviation from the strategy, recorded: the natural keys of wearable_daily / wearable_epoch are KEPT
-- (patient, source, day|start_ts, type). They are the conflict targets of three writers (thryve-webhook,
-- wearable-ingest, the vendor functions) and changing them on a shared table is not additive.
-- `source_record_id` lands as a provenance column with its own index; a vendor record whose start moved is
-- handled in code (the old row gets `superseded_by`), not by a second unique key. The owner can revisit.

-- ───────────────────────────── accounts: nine states, lease, CAS, provenance ─────────────────────────────
alter table public.wearable_vendor_accounts
  add column if not exists token_version bigint not null default 1,
  add column if not exists token_key_version integer not null default 1,
  add column if not exists refresh_lock_owner text,
  add column if not exists refresh_lock_until timestamptz,
  add column if not exists reconnect_required boolean not null default false,
  add column if not exists granted_scopes text[],
  add column if not exists last_successful_sync_at timestamptz,
  add column if not exists last_webhook_at timestamptz,
  add column if not exists last_error_code text,
  add column if not exists disconnected_at timestamptz;

alter table public.wearable_vendor_accounts drop constraint if exists wearable_vendor_accounts_status_check;
alter table public.wearable_vendor_accounts add constraint wearable_vendor_accounts_status_check
  check (status in ('not_connected','connecting','connected','syncing','degraded','reconnect_required','revoked','disconnected','error'));

-- One vendor user links to one live FunctionAlps account at a time (a second link is answered `already_linked`).
create unique index if not exists wearable_vendor_accounts_live_vendor_user
  on public.wearable_vendor_accounts (vendor, vendor_user_id)
  where vendor_user_id is not null and status in ('connected','syncing','degraded');

-- Members read their OWN account STATUS (never the token columns): column-level grant + RLS.
grant select (id, patient_id, vendor, status, reconnect_required, granted_scopes, last_sync_at, last_successful_sync_at,
              last_webhook_at, last_error_code, connected_at, revoked_at, disconnected_at, updated_at)
  on public.wearable_vendor_accounts to authenticated;
drop policy if exists "Members read their own vendor accounts" on public.wearable_vendor_accounts;
create policy "Members read their own vendor accounts" on public.wearable_vendor_accounts
  for select to authenticated
  using (patient_id in (select id from public.patients where auth_user_id = auth.uid()));

-- Refresh lease: one worker refreshes at a time; everyone else waits and re-reads.
create or replace function public.wearable_token_lock(p_account uuid, p_owner text, p_seconds integer default 30)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update public.wearable_vendor_accounts
     set refresh_lock_owner = p_owner, refresh_lock_until = now() + make_interval(secs => p_seconds)
   where id = p_account and (refresh_lock_until is null or refresh_lock_until < now());
  return found;
end $$;
revoke all on function public.wearable_token_lock(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.wearable_token_lock(uuid, text, integer) to service_role;

-- ───────────────────────────── oauth states: hashed, encrypted verifier, atomic consume ─────────────────────
alter table public.wearable_oauth_states
  add column if not exists state_hash bytea,
  add column if not exists code_verifier_enc text,
  add column if not exists used_at timestamptz,
  add column if not exists redirect_uri text,
  add column if not exists post_auth_target text,
  add column if not exists pkce_mode text;
comment on column public.wearable_oauth_states.state is 'SHA-256 hex of the state the browser carries (the raw value is never stored).';
comment on column public.wearable_oauth_states.code_verifier is 'Legacy plaintext column — unused since platform v2; code_verifier_enc replaces it.';
create unique index if not exists wearable_oauth_states_hash on public.wearable_oauth_states (state_hash) where state_hash is not null;

create or replace function public.wearable_oauth_state_consume(p_state_hex text)
returns table (patient_id uuid, vendor text, code_verifier_enc text, redirect_uri text, post_auth_target text, pkce_mode text, expired boolean)
language sql security definer set search_path = public as $$
  update public.wearable_oauth_states s set used_at = now()
   where s.state = p_state_hex and s.used_at is null
  returning s.patient_id, s.vendor, s.code_verifier_enc, s.redirect_uri, s.post_auth_target, s.pkce_mode, (s.expires_at < now()) as expired
$$;
revoke all on function public.wearable_oauth_state_consume(text) from public, anon, authenticated;
grant execute on function public.wearable_oauth_state_consume(text) to service_role;

-- ───────────────────────────── queue: dedupe, lease, retry scheduling, claim ─────────────────────────────
alter table public.wearable_sync_queue
  add column if not exists dedupe_key text,
  add column if not exists sync_kind text not null default 'notification',
  add column if not exists priority smallint not null default 0,
  add column if not exists locked_by text,
  add column if not exists lock_expires_at timestamptz,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists last_error_code text,
  add column if not exists account_id uuid references public.wearable_vendor_accounts(id) on delete set null;
alter table public.wearable_sync_queue drop constraint if exists wearable_sync_queue_status_check;
alter table public.wearable_sync_queue add constraint wearable_sync_queue_status_check
  check (status in ('pending','processing','done','error','dead','cancelled'));
alter table public.wearable_sync_queue drop constraint if exists wearable_sync_queue_sync_kind_check;
alter table public.wearable_sync_queue add constraint wearable_sync_queue_sync_kind_check
  check (sync_kind in ('notification','backfill','reconcile','manual','push'));
create unique index if not exists wearable_sync_queue_active_dedupe
  on public.wearable_sync_queue (dedupe_key) where dedupe_key is not null and status in ('pending','processing');
create index if not exists wearable_sync_queue_ready
  on public.wearable_sync_queue (priority desc, created_at) where status = 'pending' and vendor is not null;

create or replace function public.wearable_queue_enqueue(
  p_patient uuid, p_vendor text, p_end_user text, p_kind text, p_sync_kind text,
  p_window_start timestamptz, p_window_end timestamptz, p_raw_event uuid, p_dedupe_key text,
  p_priority smallint default 0, p_account uuid default null, p_source_id integer default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.wearable_sync_queue
    (patient_id, end_user_id, notification_type, data_source_id, vendor, granularity, window_start, window_end,
     raw_event_id, dedupe_key, sync_kind, priority, account_id)
  values (p_patient, p_end_user, p_kind, p_source_id, p_vendor, 'daily', p_window_start, p_window_end,
          p_raw_event, p_dedupe_key, p_sync_kind, p_priority, p_account)
  on conflict do nothing
  returning id into v_id;
  return v_id;  -- null = an identical active job already exists
end $$;
revoke all on function public.wearable_queue_enqueue(uuid, text, text, text, text, timestamptz, timestamptz, uuid, text, smallint, uuid, integer) from public, anon, authenticated;
grant execute on function public.wearable_queue_enqueue(uuid, text, text, text, text, timestamptz, timestamptz, uuid, text, smallint, uuid, integer) to service_role;

create or replace function public.wearable_queue_claim(p_worker text, p_limit integer default 25, p_lease_seconds integer default 300, p_patient uuid default null)
returns setof public.wearable_sync_queue language plpgsql security definer set search_path = public as $$
begin
  -- Recover leases the worker never released (function timeout, crash).
  update public.wearable_sync_queue
     set status = 'pending', locked_by = null, lock_expires_at = null, last_error_code = coalesce(last_error_code, 'lease_expired')
   where status = 'processing' and vendor is not null and lock_expires_at is not null and lock_expires_at < now();
  return query
    with picked as (
      select q.id from public.wearable_sync_queue q
       where q.status = 'pending' and q.vendor is not null
         and (q.next_attempt_at is null or q.next_attempt_at <= now())
         and (p_patient is null or q.patient_id = p_patient)
       order by q.priority desc, q.created_at
       limit p_limit
       for update skip locked)
    update public.wearable_sync_queue q
       set status = 'processing', locked_by = p_worker, attempts = q.attempts + 1,
           lock_expires_at = now() + make_interval(secs => p_lease_seconds)
      from picked where q.id = picked.id
    returning q.*;
end $$;
revoke all on function public.wearable_queue_claim(text, integer, integer, uuid) from public, anon, authenticated;
grant execute on function public.wearable_queue_claim(text, integer, integer, uuid) to service_role;

-- ───────────────────────────── raw events: provenance, retention ─────────────────────────────
alter table public.wearable_raw_events
  add column if not exists payload_hash text,
  add column if not exists vendor_event_id text,
  add column if not exists vendor_record_id text,
  add column if not exists vendor_modified_at timestamptz,
  add column if not exists retention_class text not null default 'standard',
  add column if not exists delete_after timestamptz,
  add column if not exists processing_status text not null default 'stored';
create index if not exists wearable_raw_events_purge on public.wearable_raw_events (delete_after) where delete_after is not null;
create index if not exists wearable_raw_events_provider_hash on public.wearable_raw_events (provider, payload_hash) where payload_hash is not null;

-- ───────────────────────────── daily / epoch: provenance ─────────────────────────────
alter table public.wearable_daily
  add column if not exists source_connection_id uuid,
  add column if not exists source_resource_type text,
  add column if not exists source_record_id text,
  add column if not exists source_field text,
  add column if not exists source_device_id text,
  add column if not exists source_modified_at timestamptz,
  add column if not exists normalization_version text,
  add column if not exists source_timezone text,
  add column if not exists source_offset_minutes integer,
  add column if not exists local_date_basis text,
  add column if not exists is_preferred_source boolean,
  add column if not exists superseded_by uuid;
alter table public.wearable_epoch
  add column if not exists source_connection_id uuid,
  add column if not exists source_resource_type text,
  add column if not exists source_record_id text,
  add column if not exists source_field text,
  add column if not exists source_device_id text,
  add column if not exists source_modified_at timestamptz,
  add column if not exists normalization_version text,
  add column if not exists source_timezone text,
  add column if not exists source_offset_minutes integer,
  add column if not exists local_date_basis text,
  add column if not exists is_preferred_source boolean,
  add column if not exists superseded_by uuid;
create index if not exists wearable_daily_source_record on public.wearable_daily (patient_id, data_source_id, source_record_id) where source_record_id is not null;
create index if not exists wearable_epoch_source_record on public.wearable_epoch (patient_id, data_source_id, source_record_id) where source_record_id is not null;

-- ───────────────────────────── new tables ─────────────────────────────
create table if not exists public.wearable_webhook_receipts (
  id uuid primary key default gen_random_uuid(),
  vendor text not null references public.wearable_vendors(key),
  dedupe_key text not null,            -- evt:<vendor event id> | rec:<resource>:<id>:<version> | hash:<sha256 of the body>
  vendor_event_id text,
  payload_hash text not null,
  raw_event_id uuid references public.wearable_raw_events(id) on delete set null,
  received_at timestamptz not null default now(),
  unique (vendor, dedupe_key)
);
create index if not exists wearable_webhook_receipts_received on public.wearable_webhook_receipts (received_at);
alter table public.wearable_webhook_receipts enable row level security;

create table if not exists public.wearable_webhook_subscriptions (
  id uuid primary key default gen_random_uuid(),
  vendor text not null references public.wearable_vendors(key),
  patient_id uuid references public.patients(id) on delete cascade,
  account_id uuid references public.wearable_vendor_accounts(id) on delete cascade,
  vendor_subscription_id text,
  data_type text,
  event_type text,
  callback_url text,
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','expired','revoked','error')),
  meta jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (vendor, vendor_subscription_id)
);
alter table public.wearable_webhook_subscriptions enable row level security;

create table if not exists public.wearable_sync_state (
  account_id uuid primary key references public.wearable_vendor_accounts(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  vendor text not null references public.wearable_vendors(key),
  cursors jsonb not null default '{}'::jsonb,   -- structured per-resource cursors (vendor-specific shape)
  last_reconcile_at timestamptz,
  last_reconcile_window_start date,
  last_reconcile_window_end date,
  last_backfill_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.wearable_sync_state enable row level security;

create table if not exists public.wearable_audit_log (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid references public.patients(id) on delete cascade,
  vendor text,
  account_id uuid,
  action text not null,                -- connect | reconnect | disconnect | erase | revoke_by_vendor | token_refresh_failed | …
  actor text not null default 'system', -- member | system | cron | vendor | practitioner
  details jsonb,                       -- never tokens, codes, secrets or health values
  created_at timestamptz not null default now()
);
create index if not exists wearable_audit_log_patient on public.wearable_audit_log (patient_id, created_at desc);
alter table public.wearable_audit_log enable row level security;
grant select on public.wearable_audit_log to authenticated;
drop policy if exists "Members read their own wearable audit log" on public.wearable_audit_log;
create policy "Members read their own wearable audit log" on public.wearable_audit_log
  for select to authenticated
  using (patient_id in (select id from public.patients where auth_user_id = auth.uid()));

create table if not exists public.wearable_source_policy (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid references public.patients(id) on delete cascade,   -- null = practice default
  data_type_id integer not null,
  source_vendor text not null,          -- wearable_vendors.key or 'apple' / 'thryve'
  priority smallint not null default 0, -- higher wins when several sources carry the same day/type
  created_at timestamptz not null default now(),
  unique nulls not distinct (patient_id, data_type_id, source_vendor)
);
alter table public.wearable_source_policy enable row level security;
grant select on public.wearable_source_policy to authenticated;
drop policy if exists "Members read source policies" on public.wearable_source_policy;
create policy "Members read source policies" on public.wearable_source_policy
  for select to authenticated
  using (patient_id is null or patient_id in (select id from public.patients where auth_user_id = auth.uid()));

-- ───────────────────────────── erase-my-data (member request via wearable-vendor-disconnect) ─────────────
create or replace function public.wearable_erase_vendor_data(p_patient uuid, p_vendor text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_source integer; v_daily integer; v_epoch integer; v_raw integer; v_jobs integer;
begin
  select data_source_id into v_source from public.wearable_vendors where key = p_vendor;
  if v_source is null then raise exception 'unknown vendor %', p_vendor; end if;
  delete from public.wearable_daily where patient_id = p_patient and data_source_id = v_source;
  get diagnostics v_daily = row_count;
  delete from public.wearable_epoch where patient_id = p_patient and data_source_id = v_source;
  get diagnostics v_epoch = row_count;
  update public.wearable_raw_events set delete_after = now(), retention_class = 'erase_requested'
   where patient_id = p_patient and provider = p_vendor;
  get diagnostics v_raw = row_count;
  update public.wearable_sync_queue set status = 'cancelled', last_error_code = 'erased'
   where patient_id = p_patient and vendor = p_vendor and status in ('pending','processing');
  get diagnostics v_jobs = row_count;
  delete from public.wearable_sync_state where patient_id = p_patient and vendor = p_vendor;
  return jsonb_build_object('daily', v_daily, 'epoch', v_epoch, 'raw', v_raw, 'jobs', v_jobs);
end $$;
revoke all on function public.wearable_erase_vendor_data(uuid, text) from public, anon, authenticated;
grant execute on function public.wearable_erase_vendor_data(uuid, text) to service_role;

-- ───────────────────────────── retention purge (nightly) ─────────────────────────────
create or replace function public.wearable_purge_raw_events()
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  delete from public.wearable_raw_events where delete_after is not null and delete_after < now();
  get diagnostics v_n = row_count;
  delete from public.wearable_webhook_receipts where received_at < now() - interval '30 days';
  delete from public.wearable_oauth_states where expires_at < now() - interval '1 day';
  update public.wearable_sync_queue set status = 'dead', last_error_code = coalesce(last_error_code, 'stale')
   where status = 'pending' and vendor is not null and created_at < now() - interval '14 days';
  return v_n;
end $$;
revoke all on function public.wearable_purge_raw_events() from public, anon, authenticated;
grant execute on function public.wearable_purge_raw_events() to service_role;

-- ───────────────────────────── operator health view (service role) ─────────────────────────────
create or replace view public.wearable_platform_health with (security_invoker = true) as
  select 'queue'::text as kind, vendor, status as state, count(*)::integer as n, min(created_at) as oldest, max(created_at) as newest
    from public.wearable_sync_queue where vendor is not null group by vendor, status
  union all
  select 'accounts', vendor, status, count(*)::integer, min(updated_at), max(updated_at)
    from public.wearable_vendor_accounts group by vendor, status
  union all
  select 'webhooks_24h', vendor, 'received', count(*)::integer, min(received_at), max(received_at)
    from public.wearable_webhook_receipts where received_at > now() - interval '24 hours' group by vendor;

-- ───────────────────────────── cron ─────────────────────────────
-- Job 18 (wearable-vendor-sync, */10) now also fires when a lease expired; the reconcile and purge jobs are new.
select cron.alter_job(18, command := $cmd$
  select net.http_post(
    url := 'https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-vendor-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-report-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'report_secret'), '')
    ),
    body := '{}'::jsonb
  )
  where exists (select 1 from public.wearable_sync_queue
                 where vendor is not null and (status = 'pending' or (status = 'processing' and lock_expires_at < now())));
$cmd$);

do $$ begin perform cron.unschedule('wearable-reconcile'); exception when others then null; end $$;
select cron.schedule('wearable-reconcile', '25 3 * * *', $cmd$
  select net.http_post(
    url := 'https://ndojytvvlvlbgtodujkf.supabase.co/functions/v1/wearable-reconcile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-report-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'report_secret'), '')
    ),
    body := '{}'::jsonb
  )
  where exists (select 1 from public.wearable_vendor_accounts where status in ('connected','syncing','degraded'));
$cmd$);

do $$ begin perform cron.unschedule('wearable-retention-purge'); exception when others then null; end $$;
select cron.schedule('wearable-retention-purge', '40 3 * * *', $$ select public.wearable_purge_raw_events() $$);
