-- Thomas, 2026-10-06: "Everything: 20 minutes. Let's make it a 20-minute member's call." And the
-- meal-photo habit now starts on day 2, the nutrition day, instead of day 1.
-- Two Foundation Track objects created earlier today change (0 enrolments when applied):
--   1. member_track_enrollment.calls default: day 3 · 20 min, optional; day 14 · 20 min, unlocked by
--      the review rule. Both book the same page: booking_meeting_types 'foundation-call-20'
--      ("Members call · 20 min"). Existing members launched by staff keep day 3, 7 and 14 · 20 min.
--   2. member_track_status(): meals are expected from day 2 (meals_per_day × (days elapsed − 1)).
--      Photos from day 1 still count as logged. Mirrored in CLINICAL lib/foundation-track/status.ts.
-- The 15- and 30-minute meeting types are switched off in the same change (data, not schema).

alter table public.member_track_enrollment
  alter column calls set default '[{"day": 3, "minutes": 20, "gated": false}, {"day": 14, "minutes": 20, "gated": true}]'::jsonb;

create or replace function public.member_track_status(p_track_code text default 'foundation_v1')
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_pid        uuid := public.current_member_patient_id();
  v_enr        public.member_track_enrollment;
  v_days       int;
  v_day        int;
  v_elapsed    int;
  v_modules    int;
  v_modules_n  int;
  v_mpd        int;
  v_expected   int;
  v_logged     int;
  v_unlocked   boolean;
  v_sex        text;
  v_weight     numeric;
  v_tdee       numeric;
begin
  if v_pid is null then return null; end if;
  select * into v_enr from public.member_track_enrollment where patient_id = v_pid and track_code = p_track_code;
  if not found then return null; end if;
  if v_enr.started_at is null then
    return jsonb_build_object('track_code', p_track_code, 'status', 'invited');
  end if;

  select days into v_days from public.app_track where code = p_track_code;
  v_day := ((now() at time zone v_enr.timezone)::date - (v_enr.started_at at time zone v_enr.timezone)::date) + 1;
  v_elapsed := least(greatest(v_day, 1), v_days);

  select count(*) into v_modules_n from public.track_questionnaire
   where track_code = p_track_code and active and counts_toward_review;
  select count(*) into v_modules
    from public.track_questionnaire_response r
    join public.track_questionnaire q on q.id = r.questionnaire_id
   where r.patient_id = v_pid and r.status = 'submitted'
     and q.track_code = p_track_code and q.active and q.counts_toward_review;

  select case r.answers ->> 'meals_per_day' when '1' then 1 when '2' then 2 when '3' then 3 when '4_plus' then 4 end
    into v_mpd
    from public.track_questionnaire_response r
    join public.track_questionnaire q on q.id = r.questionnaire_id
   where r.patient_id = v_pid and q.track_code = p_track_code and r.answers ? 'meals_per_day'
   order by r.updated_at desc limit 1;
  -- meal photos start on day 2 (the nutrition day), so day 1 expects none
  v_expected := coalesce(v_mpd, 3) * greatest(v_elapsed - 1, 0);

  select count(*) into v_logged from public.nb_meal_logs m
   where m.patient_id = v_pid
     and m.created_at >= v_enr.started_at
     and m.created_at <  v_enr.started_at + make_interval(days => v_days);

  v_unlocked := v_enr.review_call_override
             or (v_modules_n > 0 and v_modules >= v_modules_n and v_expected > 0 and v_logged >= 0.8 * v_expected);

  select app_sex, app_weight_kg, tdee_kcal into v_sex, v_weight, v_tdee
    from public.nb_patient_app_profiles where patient_id = v_pid;

  return jsonb_build_object(
    'track_code',       p_track_code,
    'status',           'active',
    'started_at',       v_enr.started_at,
    'day',              v_day,
    'days',             v_days,
    'modules_done',     v_modules,
    'modules_total',    v_modules_n,
    'meals_expected',   v_expected,
    'meals_logged',     v_logged,
    'meals_pct',        case when v_expected > 0 then round(100.0 * v_logged / v_expected) end,
    'review_unlocked',  v_unlocked,
    'calls',            coalesce((
                          select jsonb_agg(c || jsonb_build_object('open',
                                   v_day >= (c ->> 'day')::int
                                   and (not coalesce((c ->> 'gated')::boolean, false) or v_unlocked))
                                 order by (c ->> 'day')::int)
                            from jsonb_array_elements(v_enr.calls) c), '[]'::jsonb),
    'energy_kcal_low',  case when v_tdee > 0 then round(v_tdee * 0.95 / 50) * 50 end,
    'energy_kcal_high', case when v_tdee > 0 then round(v_tdee * 1.05 / 50) * 50 end,
    'protein_g_low',    case when v_weight > 0 and v_sex in ('female', 'male')
                          then round(v_weight * case v_sex when 'female' then 1.3 else 1.6 end) end,
    'protein_g_high',   case when v_weight > 0 and v_sex in ('female', 'male')
                          then round(v_weight * case v_sex when 'female' then 1.7 else 2.0 end) end
  );
end $$;

update public.booking_meeting_types set active = false
 where slug in ('foundation-call-15', 'foundation-review-30') and active;
