-- member_pending_consents: report WHICH version the member last agreed to, not just whether the
-- current one is signed.
--
-- The re-acceptance rule itself already worked: `accepted` matches on `c.version = d.version`, so
-- publishing terms_of_use v9 flips every v8 holder back to false and MemberGateView blocks on the
-- next launch. What the app could not tell was WHY the box is empty — a first sitting and "the
-- wording changed under you" looked identical, so a returning member was greeted with "Before you
-- start". This adds the one fact that separates them.
--
-- `accepted_version` = the most recent still-standing grant for that key, WHATEVER its version
-- (null when the member never agreed to it). So:
--   null                      → never seen it            → first acceptance
--   = version, accepted true  → signed, nothing to do
--   ≠ version                 → the text moved under them → re-acceptance, and the app names it
--
-- The return type changes, so this is a drop + create (create or replace refuses a new column) and
-- the grants are restored explicitly: postgres / authenticated / service_role, exactly as before —
-- anon never had EXECUTE and must not gain it.
--
-- Both clients tolerate the extra column: PostgREST hands back one more JSON key, the Expo app
-- ignores unknown fields, and iOS decodes it as an optional. Deploying this before or after the
-- app build is therefore safe in either order.
drop function if exists public.member_pending_consents(text, boolean);

create function public.member_pending_consents(p_locale text default 'en'::text, p_include_drafts boolean default false)
returns table(
  consent_key text, version text, title text, summary text, body_md text,
  required boolean, display_order integer, review_status text, basis text,
  accepted boolean, accepted_version text
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select current_member_patient_id() as pid),
  current_defs as (
    select distinct on (d.consent_key) d.*
    from consent_definitions d
    where d.locale = p_locale
      and d.superseded_at is null
      and d.doc_kind = 'consent'
      and (p_include_drafts or d.review_status = 'approved')
    order by d.consent_key, d.effective_from desc
  )
  select d.consent_key, d.version, d.title, d.summary, d.body_md,
         d.required, d.display_order, d.review_status, d.basis,
         exists (
           select 1 from nb_app_consents c, me
           where c.patient_id = me.pid
             and c.consent_type = d.consent_key
             and c.version      = d.version
             and c.granted is true
             and c.revoked_at is null
         ) as accepted,
         (
           select c.version from nb_app_consents c, me
           where c.patient_id = me.pid
             and c.consent_type = d.consent_key
             and c.granted is true
             and c.revoked_at is null
           order by c.granted_at desc nulls last, c.created_at desc
           limit 1
         ) as accepted_version
  from current_defs d
  order by d.required desc, d.display_order, d.consent_key;
$function$;

grant execute on function public.member_pending_consents(text, boolean) to authenticated;
grant execute on function public.member_pending_consents(text, boolean) to service_role;

-- A fresh CREATE picks up EXECUTE for PUBLIC (Postgres default) and for anon (Supabase's default
-- privileges on the public schema); the function this replaces had NEITHER. Revoke both, or the
-- migration quietly widens a SECURITY DEFINER function to unauthenticated callers.
-- Verified after applying: proacl is back to {postgres,authenticated,service_role}, as before.
revoke execute on function public.member_pending_consents(text, boolean) from public;
revoke execute on function public.member_pending_consents(text, boolean) from anon;
