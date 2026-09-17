-- The night's CLOCK, not just its length.
--
-- Until now a member set bedtime and wake time, the phone turned them into `sleep_duration_min`, and
-- the two times were thrown away: re-opening the morning check-in showed the default 22:00 → 06:30
-- again, and nothing downstream could see that someone goes to bed at 01:00 every night and sleeps
-- seven hours. Duration answers "how long"; the clock answers "when", which is the half that carries
-- regularity. Both columns are `time` (wall clock, the member's own), never a timestamp: the night of
-- 2026-09-17 belongs to that check-in date whatever timezone the phone was in.
--
-- 1. the two columns, on the moment and on the day roll-up
-- 2. member_submit_checkin v3: reads `answers.sleep.bed_time` / `wake_time`, writes both columns, and
--    carries them into the day row from the SAME moment the rest of the night comes from.
-- A client that never sends them keeps working unchanged — both columns simply stay null.

alter table public.patient_checkin_moments
  add column if not exists sleep_bed_time time,
  add column if not exists sleep_wake_time time;

alter table public.patient_daily_checkins
  add column if not exists sleep_bed_time time,
  add column if not exists sleep_wake_time time;

comment on column public.patient_checkin_moments.sleep_bed_time is 'Wall clock the member went to bed (their own timezone). With sleep_wake_time it is the window sleep_duration_min measures.';
comment on column public.patient_checkin_moments.sleep_wake_time is 'Wall clock the member got up (their own timezone).';

create or replace function public.member_submit_checkin(p_day date, p_slot text, p_moment jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_patient uuid;
  v_today date;
  v_submitted timestamptz;
  v_m jsonb;              -- the moment columns actually written (answers → columns when present)
  v_a jsonb;              -- raw answers, when the client sent them
  v_scored_by text := 'client';
  -- the day summary
  s_energy_overall smallint; s_energy_body smallint; s_energy_mind smallint; s_energy_stability smallint;
  s_mood smallint; s_stress smallint;
  s_sleep_overall smallint; s_sleep_refreshed smallint; s_sleep_duration smallint;
  s_sleep_latency text; s_sleep_wake text; s_has_sleep boolean := false;
  s_sleep_bed time; s_sleep_wake_time time;
  v_sleep_source public.patient_checkin_moments%rowtype;
  v_saved public.patient_checkin_moments%rowtype;
  v_count int;
  -- the red flags on the day row (written by the gut check-in / legacy daily form, never here)
  rf_blood boolean; rf_black boolean; rf_vomit boolean; rf_fever boolean; rf_weight boolean; rf_pain boolean;
begin
  select p.id into v_patient from public.patients p where p.auth_user_id = auth.uid() limit 1;
  if v_patient is null then
    raise exception 'not a member' using errcode = '42501';
  end if;
  if p_slot not in ('morning', 'midday', 'evening') then
    raise exception 'unknown slot %', p_slot using errcode = '22023';
  end if;
  v_today := public.patient_local_today(v_patient);
  if p_day is null or p_day < v_today - 1 or p_day > v_today then
    raise exception 'day out of window' using errcode = '22023';
  end if;
  v_submitted := coalesce((p_moment->>'submitted_at')::timestamptz, now());

  -- 0. score the raw answers server-side when the client sent them (one scorer for every client)
  v_m := p_moment;
  if jsonb_typeof(p_moment->'answers') = 'object' then
    v_a := p_moment->'answers';
    v_scored_by := 'server';
    v_m := (p_moment - 'answers') || jsonb_build_object(
      'energy_body', round((v_a #>> '{energy,body}')::numeric),
      'energy_mind', round((v_a #>> '{energy,mind}')::numeric),
      'energy_stability', round((v_a #>> '{energy,stability}')::numeric),
      'energy_overall', public.checkin_energy_overall((v_a #>> '{energy,body}')::numeric, (v_a #>> '{energy,mind}')::numeric, (v_a #>> '{energy,stability}')::numeric),
      'mood_score', round((v_a #>> '{mood,mood}')::numeric),
      'stress_score', round((v_a #>> '{stress,calm}')::numeric),   -- CALMNESS, never inverted
      'sleep_refreshed', round((v_a #>> '{sleep,refreshed}')::numeric),
      'sleep_duration_min', round((v_a #>> '{sleep,duration_min}')::numeric),
      'sleep_latency_band', v_a #>> '{sleep,latency}',
      'sleep_wake_count', v_a #>> '{sleep,wake_count}',
      'sleep_bed_time', nullif(v_a #>> '{sleep,bed_time}', ''),
      'sleep_wake_time', nullif(v_a #>> '{sleep,wake_time}', ''),
      'sleep_overall', public.checkin_sleep_overall(round((v_a #>> '{sleep,duration_min}')::numeric)::int, v_a #>> '{sleep,latency}', v_a #>> '{sleep,wake_count}', (v_a #>> '{sleep,refreshed}')::numeric)
    );
  end if;

  -- 1. the moment lands first (the source of truth)
  insert into public.patient_checkin_moments as m (
    patient_id, checkin_date, slot, submitted_at,
    energy_body, energy_mind, energy_stability, energy_overall, mood_score, stress_score,
    sleep_overall, sleep_refreshed, sleep_duration_min, sleep_latency_band, sleep_wake_count,
    sleep_bed_time, sleep_wake_time,
    pills, note
  ) values (
    v_patient, p_day, p_slot, v_submitted,
    (v_m->>'energy_body')::smallint, (v_m->>'energy_mind')::smallint,
    (v_m->>'energy_stability')::smallint, (v_m->>'energy_overall')::smallint,
    (v_m->>'mood_score')::smallint, (v_m->>'stress_score')::smallint,
    (v_m->>'sleep_overall')::smallint, (v_m->>'sleep_refreshed')::smallint,
    (v_m->>'sleep_duration_min')::smallint, v_m->>'sleep_latency_band', v_m->>'sleep_wake_count',
    (nullif(v_m->>'sleep_bed_time', ''))::time, (nullif(v_m->>'sleep_wake_time', ''))::time,
    coalesce(case when jsonb_typeof(v_m->'pills') = 'object' then v_m->'pills' end, '{}'::jsonb),
    nullif(v_m->>'note', '')
  )
  on conflict (patient_id, checkin_date, slot) do update set
    submitted_at = excluded.submitted_at,
    energy_body = excluded.energy_body, energy_mind = excluded.energy_mind,
    energy_stability = excluded.energy_stability, energy_overall = excluded.energy_overall,
    mood_score = excluded.mood_score, stress_score = excluded.stress_score,
    sleep_overall = excluded.sleep_overall, sleep_refreshed = excluded.sleep_refreshed,
    sleep_duration_min = excluded.sleep_duration_min, sleep_latency_band = excluded.sleep_latency_band,
    sleep_wake_count = excluded.sleep_wake_count,
    sleep_bed_time = excluded.sleep_bed_time, sleep_wake_time = excluded.sleep_wake_time,
    pills = excluded.pills, note = excluded.note,
    updated_at = now()
  returning * into v_saved;

  -- 2. the day summary from EVERY moment of the day
  with day as (
    select * from public.patient_checkin_moments
     where patient_id = v_patient and checkin_date = p_day
  )
  select
    round(percentile_cont(0.5) within group (order by energy_overall) filter (where energy_overall is not null) + 0.0)::smallint,
    round(percentile_cont(0.5) within group (order by energy_body) filter (where energy_body is not null) + 0.0)::smallint,
    round(percentile_cont(0.5) within group (order by energy_mind) filter (where energy_mind is not null) + 0.0)::smallint,
    round(avg(energy_stability))::smallint,
    round(percentile_cont(0.5) within group (order by mood_score) filter (where mood_score is not null) + 0.0)::smallint,
    round(percentile_cont(0.5) within group (order by stress_score) filter (where stress_score is not null) + 0.0)::smallint,
    count(*)
  into s_energy_overall, s_energy_body, s_energy_mind, s_energy_stability, s_mood, s_stress, v_count
  from day;

  select * into v_sleep_source
    from public.patient_checkin_moments
   where patient_id = v_patient and checkin_date = p_day
   order by (slot <> 'morning'),
            (sleep_overall is null and sleep_refreshed is null and sleep_duration_min is null
             and sleep_latency_band is null and sleep_wake_count is null
             and sleep_bed_time is null and sleep_wake_time is null),
            case slot when 'morning' then 0 when 'midday' then 1 else 2 end
   limit 1;
  if found and (v_sleep_source.slot = 'morning'
      or v_sleep_source.sleep_overall is not null or v_sleep_source.sleep_refreshed is not null
      or v_sleep_source.sleep_duration_min is not null or v_sleep_source.sleep_latency_band is not null
      or v_sleep_source.sleep_wake_count is not null
      or v_sleep_source.sleep_bed_time is not null or v_sleep_source.sleep_wake_time is not null) then
    s_sleep_overall := v_sleep_source.sleep_overall;
    s_sleep_refreshed := v_sleep_source.sleep_refreshed;
    s_sleep_duration := v_sleep_source.sleep_duration_min;
    s_sleep_latency := v_sleep_source.sleep_latency_band;
    s_sleep_wake := v_sleep_source.sleep_wake_count;
    s_sleep_bed := v_sleep_source.sleep_bed_time;
    s_sleep_wake_time := v_sleep_source.sleep_wake_time;
    s_has_sleep := s_sleep_overall is not null or s_sleep_refreshed is not null or s_sleep_duration is not null
                   or s_sleep_latency is not null or s_sleep_wake is not null
                   or s_sleep_bed is not null or s_sleep_wake_time is not null;
  end if;

  insert into public.patient_daily_checkins as d (
    patient_id, checkin_date,
    energy_body, energy_mind, energy_stability, energy_overall, mood_score, stress_score,
    energy, mood, stress,
    recovery, soreness, recent_load, recent_mental_load,
    sleep_overall, sleep_refreshed, sleep_duration_min, sleep_latency_band, sleep_wake_count, sleep,
    sleep_bed_time, sleep_wake_time,
    functional_completed_at, completed_at, last_submission_form
  ) values (
    v_patient, p_day,
    s_energy_body, s_energy_mind, s_energy_stability, s_energy_overall, s_mood, s_stress,
    public.checkin_legacy_scale(s_energy_overall), public.checkin_legacy_scale(s_mood), public.checkin_legacy_scale(s_stress),
    null, null, null, null,
    case when s_has_sleep then s_sleep_overall end, case when s_has_sleep then s_sleep_refreshed end,
    case when s_has_sleep then s_sleep_duration end, case when s_has_sleep then s_sleep_latency end,
    case when s_has_sleep then s_sleep_wake end, case when s_has_sleep then public.checkin_legacy_scale(s_sleep_overall) end,
    case when s_has_sleep then s_sleep_bed end, case when s_has_sleep then s_sleep_wake_time end,
    v_submitted, v_submitted, 'functional'
  )
  on conflict (patient_id, checkin_date) do update set
    energy_body = coalesce(excluded.energy_body, d.energy_body),
    energy_mind = coalesce(excluded.energy_mind, d.energy_mind),
    energy_stability = coalesce(excluded.energy_stability, d.energy_stability),
    energy_overall = coalesce(excluded.energy_overall, d.energy_overall),
    mood_score = coalesce(excluded.mood_score, d.mood_score),
    stress_score = coalesce(excluded.stress_score, d.stress_score),
    energy = coalesce(excluded.energy, d.energy),
    mood = coalesce(excluded.mood, d.mood),
    stress = coalesce(excluded.stress, d.stress),
    -- felt prefill: carried, never computed
    recovery = d.recovery, soreness = d.soreness, recent_load = d.recent_load, recent_mental_load = d.recent_mental_load,
    -- sleep: only when the day carries a sleep answer, and then computed ?? existing
    sleep_overall = case when s_has_sleep then coalesce(excluded.sleep_overall, d.sleep_overall) else d.sleep_overall end,
    sleep_refreshed = case when s_has_sleep then coalesce(excluded.sleep_refreshed, d.sleep_refreshed) else d.sleep_refreshed end,
    sleep_duration_min = case when s_has_sleep then coalesce(excluded.sleep_duration_min, d.sleep_duration_min) else d.sleep_duration_min end,
    sleep_latency_band = case when s_has_sleep then coalesce(excluded.sleep_latency_band, d.sleep_latency_band) else d.sleep_latency_band end,
    sleep_wake_count = case when s_has_sleep then coalesce(excluded.sleep_wake_count, d.sleep_wake_count) else d.sleep_wake_count end,
    sleep_bed_time = case when s_has_sleep then coalesce(excluded.sleep_bed_time, d.sleep_bed_time) else d.sleep_bed_time end,
    sleep_wake_time = case when s_has_sleep then coalesce(excluded.sleep_wake_time, d.sleep_wake_time) else d.sleep_wake_time end,
    sleep = case when s_has_sleep then coalesce(excluded.sleep, d.sleep) else d.sleep end,
    functional_completed_at = excluded.functional_completed_at,
    completed_at = excluded.completed_at,
    last_submission_form = 'functional'
  returning red_flag_blood_in_stool, red_flag_black_stool, red_flag_persistent_vomiting,
            red_flag_fever, red_flag_unintentional_weight_loss, red_flag_severe_worsening_pain
       into rf_blood, rf_black, rf_vomit, rf_fever, rf_weight, rf_pain;

  -- 3. the events, last, exactly once per save
  insert into public.nb_checkin_events (patient_id, dimension, value, source, ts)
  select v_patient, e.dimension, e.value, 'daily', v_submitted
    from (values ('energy', v_saved.energy_overall), ('mood', v_saved.mood_score),
                 ('sleep', v_saved.sleep_overall), ('stress', v_saved.stress_score)) as e(dimension, value)
   where e.value is not null;

  return jsonb_build_object(
    'slot', v_saved.slot,
    'checkin_date', v_saved.checkin_date,
    'submitted_at', v_saved.submitted_at,
    'energy_body', v_saved.energy_body, 'energy_mind', v_saved.energy_mind,
    'energy_stability', v_saved.energy_stability, 'energy_overall', v_saved.energy_overall,
    'mood_score', v_saved.mood_score, 'stress_score', v_saved.stress_score,
    'sleep_overall', v_saved.sleep_overall, 'sleep_refreshed', v_saved.sleep_refreshed,
    'sleep_duration_min', v_saved.sleep_duration_min, 'sleep_latency_band', v_saved.sleep_latency_band,
    'sleep_wake_count', v_saved.sleep_wake_count,
    'sleep_bed_time', to_char(v_saved.sleep_bed_time, 'HH24:MI'), 'sleep_wake_time', to_char(v_saved.sleep_wake_time, 'HH24:MI'),
    'pills', v_saved.pills, 'note', v_saved.note,
    'moment_count', v_count,
    'scored_by', v_scored_by,
    'day', jsonb_build_object(
      'energy_overall', s_energy_overall, 'energy_body', s_energy_body, 'energy_mind', s_energy_mind,
      'energy_stability', s_energy_stability, 'mood_score', s_mood, 'stress_score', s_stress,
      'has_sleep', s_has_sleep, 'sleep_overall', s_sleep_overall
    ),
    'red_flags', jsonb_build_object(
      'blood_in_stool', coalesce(rf_blood, false), 'black_stool', coalesce(rf_black, false),
      'persistent_vomiting', coalesce(rf_vomit, false), 'fever', coalesce(rf_fever, false),
      'unintentional_weight_loss', coalesce(rf_weight, false), 'severe_worsening_pain', coalesce(rf_pain, false)
    ),
    'red_flag_any', coalesce(rf_blood, false) or coalesce(rf_black, false) or coalesce(rf_vomit, false)
                    or coalesce(rf_fever, false) or coalesce(rf_weight, false) or coalesce(rf_pain, false)
  );
end;
$function$;

comment on function public.member_submit_checkin(date, text, jsonb) is
  'One writer for a check-in moment. p_moment: {submitted_at, pills, note, answers?: {energy:{body,mind,stability}, sleep:{refreshed,duration_min,latency,wake_count,bed_time,wake_time}, mood:{mood}, stress:{calm}}} — with answers the markers are scored server-side (checkin_energy_overall / checkin_sleep_overall); without, the legacy client-scored columns are written as sent. bed_time / wake_time are "HH:MM" wall clock. Reply: the saved row + moment_count + scored_by + day + red_flags + red_flag_any.';
