-- confirm_member_adult_from_record() — answer the 18+ question from the CLINICAL record instead of
-- asking the member again.
--
-- A patient created in the clinical dashboard already carries `patients.date_of_birth`. Making them
-- retype it in the app is asking a question we can already answer, and it is the screen that locked
-- people out twice this week. Today 8 of the 18 patients who have a date on file still have no
-- `adult_confirmed_at`, so they would all meet that screen for nothing.
--
-- Three-state on purpose, and the NULL is the point:
--   true  → 18+ per the record; `adult_confirmed_at` is stamped, sourced 'clinical_record'
--   false → under age per the record; the failure is timestamped, nothing else kept
--   null  → no usable date on file, so the app must still ask
--
-- It only ever READS `patients.date_of_birth`. The sibling `confirm_member_adult(p_date_of_birth)`
-- keeps its own rule that a self-declaration never overwrites a clinician's record; this one cannot
-- overwrite anything at all.
--
-- An implausible stored date (in the future, or over the maximum age) is treated as no date: the
-- member is asked rather than refused on a record that is evidently wrong.
create or replace function public.confirm_member_adult_from_record()
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_patient uuid;
  v_dob     date;
  v_min     integer := public.member_minimum_age();
  v_age     integer;
begin
  v_patient := public.current_member_patient_id();
  if v_patient is null then
    raise exception 'no member context' using errcode = '42501';
  end if;

  select date_of_birth into v_dob from public.patients where id = v_patient;

  if v_dob is null
     or v_dob > current_date
     or v_dob < (current_date - interval '120 years') then
    return null;
  end if;

  v_age := extract(year from age(current_date, v_dob))::integer;

  if v_age < v_min then
    -- Same as the self-declared path: the timestamp proves the check ran and says nothing about who.
    update public.nb_patient_app_profiles
       set adult_check_last_failed_at = now()
     where patient_id = v_patient;
    return false;
  end if;

  update public.nb_patient_app_profiles
     set adult_confirmed_at        = coalesce(adult_confirmed_at, now()),
         adult_confirmation_source = coalesce(adult_confirmation_source, 'clinical_record'),
         app_age                   = v_age
   where patient_id = v_patient;

  return true;
end;
$function$;

-- A fresh CREATE picks up EXECUTE for PUBLIC and, on Supabase, for anon. Neither may call a
-- SECURITY DEFINER function that writes a confirmation stamp.
revoke execute on function public.confirm_member_adult_from_record() from public;
revoke execute on function public.confirm_member_adult_from_record() from anon;
grant execute on function public.confirm_member_adult_from_record() to authenticated;
grant execute on function public.confirm_member_adult_from_record() to service_role;
