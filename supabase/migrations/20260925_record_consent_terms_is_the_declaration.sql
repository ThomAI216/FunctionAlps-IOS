-- record_consent: the Terms tick IS the 18+ declaration — stop refusing members the app no longer asks.
--
-- The app has had no age screen since 2026-09-18 (owner's call: accepting the Terms is the declaration),
-- but this function still enforced the old contract — `current_member_is_adult()` or errcode X0018 — so
-- a member with no date of birth on the clinical record and no earlier confirmation was refused at the
-- consent gate, with nothing left in the app to do about it. Seen live 2026-09-25 03:21 UTC: four taps
-- on "Agree and continue", four HTTP 400s, "We couldn't save your choices". Eight members were in that
-- state when this was written.
--
-- Owner's call 2026-09-25: the practice selects its members itself, so the declaration is the tick.
-- A granted `terms_of_use` decision now STAMPS the confirmation instead of requiring it:
--   adult_confirmed_at        = the first Terms acceptance, never moved once set
--   adult_confirmation_source = 'terms_declaration', only when nothing better is on file
-- A clinician's record or a self-declared date (confirm_member_adult / _from_record, unchanged) keep
-- precedence through the coalesce. A profile row is created when the member has none — nine patients
-- had none — so the stamp never goes missing. `current_member_is_adult()` stays, for reporting.
--
-- Rollback: reinstate these four lines after the member-context check —
--   if not public.current_member_is_adult() then
--     raise exception 'member is not confirmed as % or older', public.member_minimum_age()
--       using errcode = 'X0018';
--   end if;
-- and drop the "declaration" block. Nothing else in the body changed.
create or replace function public.record_consent(
  p_consent_key text, p_version text, p_granted boolean,
  p_locale text default 'en'::text, p_user_agent text default null::text, p_app_version text default null::text,
  p_ui_template_version text default null::text, p_privacy_notice_version text default null::text,
  p_presented_keys text[] default null::text[], p_default_state boolean default null::boolean,
  p_channel text default 'app_onboarding'::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_patient  uuid;
  v_def      consent_definitions%rowtype;
  v_id       uuid;
  v_existing uuid;
begin
  v_patient := current_member_patient_id();
  if v_patient is null then
    raise exception 'no member context' using errcode = '42501';
  end if;

  select * into v_def from consent_definitions
  where consent_key = p_consent_key and version = p_version and locale = p_locale
    and superseded_at is null;
  if not found then
    raise exception 'unknown or superseded consent definition %/%/%',
      p_consent_key, p_version, p_locale using errcode = '22023';
  end if;

  if v_def.review_status <> 'approved' then
    raise exception 'consent definition %/% is not approved (%)',
      p_consent_key, p_version, v_def.review_status using errcode = '22023';
  end if;

  -- The declaration. Before the idempotency short-cut on purpose: a re-tap on Terms the member already
  -- holds still heals a missing stamp. Rolled back with the grant if the insert below fails.
  if p_granted and p_consent_key = 'terms_of_use' then
    insert into public.nb_patient_app_profiles (patient_id, adult_confirmed_at, adult_confirmation_source)
    values (v_patient, now(), 'terms_declaration')
    on conflict (patient_id) do update
      set adult_confirmed_at        = coalesce(public.nb_patient_app_profiles.adult_confirmed_at, excluded.adult_confirmed_at),
          adult_confirmation_source = coalesce(public.nb_patient_app_profiles.adult_confirmation_source, excluded.adult_confirmation_source);
  end if;

  -- IDEMPOTENCY. Live grants only -- see the header.
  if p_granted then
    select id into v_existing from nb_app_consents
     where patient_id = v_patient
       and consent_type = p_consent_key
       and version = p_version
       and granted is true
       and revoked_at is null
     order by created_at
     limit 1;
    if v_existing is not null then
      return v_existing;
    end if;
  end if;

  insert into nb_app_consents (
    patient_id, consent_type, version, granted, granted_at, revoked_at,
    definition_id, content_hash, locale, accepted_user_agent, app_version,
    ui_template_version, privacy_notice_version, presented_keys, default_state,
    basis, channel
  ) values (
    v_patient, p_consent_key, p_version, p_granted,
    case when p_granted then now() else null end,
    case when p_granted then null else now() end,
    v_def.id, v_def.content_hash, p_locale, p_user_agent, p_app_version,
    p_ui_template_version, p_privacy_notice_version, p_presented_keys, p_default_state,
    v_def.basis, p_channel
  ) returning id into v_id;

  return v_id;
end;
$function$;

-- Hygiene, found while here: `record_consent_batch` had picked up EXECUTE for anon on a fresh CREATE
-- (the repo's other consent functions revoke it explicitly). anon never had a member context, so it
-- only ever got 'no member context' back — but an unauthenticated caller has no business reaching a
-- SECURITY DEFINER writer at all.
revoke execute on function public.record_consent_batch(jsonb, text, text, text, text, text, text[], text) from anon;
