-- The 14-day app track (the free trial, and the soft start every new member gets).
-- Thomas, 2026-10-06. ADDITIVE ONLY: seven new tables, two member RPCs, nothing existing altered.
--
-- What it models:
--   app_track                    one row per track. launched_at is the cut-off: members whose
--                                patients row is older are never enrolled ("keep the current
--                                members on what they have"). NULL = not launched, nobody enrols.
--   member_track_enrollment      the trial clock: started_at = the member's first app open.
--                                Tier-agnostic (a paying new member runs the same track).
--                                outcome/* is the team's day-15 decision; review_call_override
--                                lets Thomas open the review call to anyone.
--   track_day                    the fixed content of each day: focus, video (EN/FR), short read,
--                                actions (habit_bank ids + moment + face), push texts.
--   track_questionnaire          the question bank, as data: one row per daily module…
--   track_question               …and one row per question (EN/FR, options, show_if, prefill).
--                                iOS and the web both render from these rows.
--   track_questionnaire_response one row per member per module; answers keyed by question_key,
--                                so later questionnaires (and the deep ones) can prefill.
--   track_summary                the day-7 summary: AI-drafted, staff-approved, and only an
--                                approved row is member-readable.
--
-- Calculations stay server-side (iOS CLAUDE.md rule 9): member_track_status() returns the day,
-- module completion, expected vs logged meals, whether the review call is unlocked, and the
-- energy / protein ranges. The app only formats.

-- 1 ─ tracks ─────────────────────────────────────────────────────────────────────────────────
create table public.app_track (
  code         text primary key,
  title        text not null,
  days         int  not null check (days between 1 and 90),
  launched_at  timestamptz,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
comment on table public.app_track is
  'A fixed app track (the 14-day trial). launched_at is the enrolment cut-off: a member whose patients row predates it is never enrolled. NULL = not launched.';

-- 2 ─ enrolment (the trial clock) ────────────────────────────────────────────────────────────
create table public.member_track_enrollment (
  id                    uuid primary key default gen_random_uuid(),
  patient_id            uuid not null references public.patients(id) on delete cascade,
  track_code            text not null references public.app_track(code),
  started_at            timestamptz not null default now(),
  timezone              text not null default 'Europe/Zurich',
  source                text not null default 'ios_first_open'
                          check (source in ('ios_first_open', 'web_first_open', 'staff')),
  review_call_override  boolean not null default false,
  outcome               text check (outcome in ('converted', 'extended', 'ended', 'no_response')),
  outcome_note          text,
  outcome_set_by        uuid references public.users(id),
  outcome_set_at        timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (patient_id, track_code)
);
comment on table public.member_track_enrollment is
  'The trial clock: started_at = first app open. Written only by member_start_track() (or staff). Day N = Zurich calendar days since started_at + 1.';
create trigger trg_member_track_enrollment_updated_at before update on public.member_track_enrollment
  for each row execute function public.set_updated_at();

-- 3 ─ the fixed content of each day ──────────────────────────────────────────────────────────
create table public.track_day (
  track_code    text not null references public.app_track(code) on delete cascade,
  day           int  not null check (day >= 1),
  title_en      text not null,
  title_fr      text,
  focus_en      text,
  focus_fr      text,
  video_url_en  text,
  video_url_fr  text,
  read_slug     text,
  questionnaire_id text,
  -- [{ "habit_bank_id": uuid | null, "moment": "morning|midday|evening|day", "face": "easy|standard|further",
  --    "title_en": "...", "title_fr": "..." }]  — title_* only for an action with no habit_bank card yet
  actions       jsonb not null default '[]'::jsonb,
  -- { "morning": {"en": "...", "fr": "..."}, "midday": {...}, "evening": {...} }
  push          jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now(),
  primary key (track_code, day)
);
create trigger trg_track_day_updated_at before update on public.track_day
  for each row execute function public.set_updated_at();

-- 4 ─ the question bank ─────────────────────────────────────────────────────────────────────
create table public.track_questionnaire (
  id           text primary key,                      -- e.g. 'trial14_d1_you_today'
  track_code   text not null references public.app_track(code) on delete cascade,
  day          int  not null check (day >= 1),
  version      int  not null default 1,
  title_en     text not null,
  title_fr     text,
  intro_en     text,
  intro_fr     text,
  done_en      text,
  done_fr      text,
  est_minutes  int,
  counts_toward_review boolean not null default true, -- the five modules of days 1–5
  active       boolean not null default true,
  updated_at   timestamptz not null default now()
);
create trigger trg_track_questionnaire_updated_at before update on public.track_questionnaire
  for each row execute function public.set_updated_at();

alter table public.track_day
  add constraint track_day_questionnaire_fk foreign key (questionnaire_id) references public.track_questionnaire(id);

create table public.track_question (
  id               uuid primary key default gen_random_uuid(),
  questionnaire_id text not null references public.track_questionnaire(id) on delete cascade,
  question_key     text not null,                     -- the spec's field id, e.g. 'primary_goals'
  screen           int  not null check (screen >= 1),
  position         int  not null default 1,
  kind             text not null check (kind in
                     ('single', 'multi', 'text', 'number', 'time', 'slider', 'confirm', 'info', 'connect_health', 'enable_notifications')),
  prompt_en        text not null,
  prompt_fr        text,
  help_en          text,
  help_fr          text,
  options          jsonb,                             -- [{ "value": "...", "label_en": "...", "label_fr": "...", "free_text": bool }]
  max_select       int,
  min_value        numeric,
  max_value        numeric,
  step             numeric,
  unit             text,
  required         boolean not null default false,
  voice            boolean not null default false,
  show_if          jsonb,                             -- { "key": "...", "eq"|"in"|"gte"|"lte"|"not_in": ..., "health_connected": bool }
  prefill          jsonb,                             -- { "from": "answer", "key": "..." } | { "from": "profile", "field": "..." }
  variants         jsonb,                             -- [{ "when": <show_if>, "prompt_en": "...", "prompt_fr": "..." }]
  unique (questionnaire_id, question_key)
);

-- 5 ─ answers ───────────────────────────────────────────────────────────────────────────────
create table public.track_questionnaire_response (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references public.patients(id) on delete cascade,
  questionnaire_id text not null references public.track_questionnaire(id),
  version          int  not null default 1,
  answers          jsonb not null default '{}'::jsonb, -- { "<question_key>": value }
  status           text not null default 'in_progress' check (status in ('in_progress', 'submitted')),
  logged_via       text not null default 'ios' check (logged_via in ('ios', 'web')),
  started_at       timestamptz not null default now(),
  submitted_at     timestamptz,
  updated_at       timestamptz not null default now(),
  unique (patient_id, questionnaire_id),
  check ((status = 'submitted') = (submitted_at is not null))
);
comment on table public.track_questionnaire_response is
  'One daily module per member. Answers keyed by track_question.question_key so later modules and the deep questionnaires prefill from them. Editable while in_progress; frozen once submitted.';
create trigger trg_track_questionnaire_response_updated_at before update on public.track_questionnaire_response
  for each row execute function public.set_updated_at();

-- 6 ─ the day-7 summary ─────────────────────────────────────────────────────────────────────
create table public.track_summary (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references public.patients(id) on delete cascade,
  track_code    text not null references public.app_track(code),
  day           int  not null default 7,
  content       jsonb not null,                       -- the fixed-format summary
  model         text,
  status        text not null default 'draft' check (status in ('draft', 'approved', 'rejected')),
  approved_by   uuid references public.users(id),
  approved_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (patient_id, track_code, day),
  check ((status = 'approved') = (approved_at is not null))
);
comment on table public.track_summary is
  'Day-7 summary. AI-drafted on the sovereign tier, approved by a practitioner. A member can read ONLY an approved row.';
create trigger trg_track_summary_updated_at before update on public.track_summary
  for each row execute function public.set_updated_at();

create index track_questionnaire_response_patient_idx on public.track_questionnaire_response (patient_id);
create index track_summary_status_idx on public.track_summary (status) where status = 'draft';

-- 7 ─ row-level security ────────────────────────────────────────────────────────────────────
alter table public.app_track                    enable row level security;
alter table public.member_track_enrollment      enable row level security;
alter table public.track_day                    enable row level security;
alter table public.track_questionnaire          enable row level security;
alter table public.track_question               enable row level security;
alter table public.track_questionnaire_response enable row level security;
alter table public.track_summary                enable row level security;

-- staff: everything
create policy staff_all_app_track on public.app_track for all to authenticated
  using (public.is_nutritionist_or_above()) with check (public.is_nutritionist_or_above());
create policy staff_all_member_track_enrollment on public.member_track_enrollment for all to authenticated
  using (public.is_nutritionist_or_above()) with check (public.is_nutritionist_or_above());
create policy staff_all_track_day on public.track_day for all to authenticated
  using (public.is_nutritionist_or_above()) with check (public.is_nutritionist_or_above());
create policy staff_all_track_questionnaire on public.track_questionnaire for all to authenticated
  using (public.is_nutritionist_or_above()) with check (public.is_nutritionist_or_above());
create policy staff_all_track_question on public.track_question for all to authenticated
  using (public.is_nutritionist_or_above()) with check (public.is_nutritionist_or_above());
create policy staff_all_track_questionnaire_response on public.track_questionnaire_response for all to authenticated
  using (public.is_nutritionist_or_above()) with check (public.is_nutritionist_or_above());
create policy staff_all_track_summary on public.track_summary for all to authenticated
  using (public.is_nutritionist_or_above()) with check (public.is_nutritionist_or_above());

-- members: the shared content (read-only)
create policy member_read_app_track on public.app_track for select to authenticated using (active);
create policy member_read_track_day on public.track_day for select to authenticated using (true);
create policy member_read_track_questionnaire on public.track_questionnaire for select to authenticated using (active);
create policy member_read_track_question on public.track_question for select to authenticated
  using (exists (select 1 from public.track_questionnaire q where q.id = questionnaire_id and q.active));

-- members: their own rows
create policy member_self_read_member_track_enrollment on public.member_track_enrollment for select to authenticated
  using (patient_id = public.current_member_patient_id());

create policy member_self_read_track_questionnaire_response on public.track_questionnaire_response for select to authenticated
  using (patient_id = public.current_member_patient_id());
create policy member_self_insert_track_questionnaire_response on public.track_questionnaire_response for insert to authenticated
  with check (patient_id = public.current_member_patient_id());
-- editable only while in progress; the member may submit (in_progress → submitted), never reopen
create policy member_self_update_track_questionnaire_response on public.track_questionnaire_response for update to authenticated
  using (patient_id = public.current_member_patient_id() and status = 'in_progress')
  with check (patient_id = public.current_member_patient_id());

create policy member_read_approved_track_summary on public.track_summary for select to authenticated
  using (patient_id = public.current_member_patient_id() and status = 'approved');

-- 8 ─ member RPCs ───────────────────────────────────────────────────────────────────────────

-- Called by the app on every launch; idempotent. Starts the clock on the FIRST call only, and
-- only for a member created after the track launched. Returns the enrolment, or NULL.
create or replace function public.member_start_track(p_track_code text default 'trial14_v1', p_via text default 'ios')
returns public.member_track_enrollment
language plpgsql security definer set search_path = ''
as $$
declare
  v_pid      uuid := public.current_member_patient_id();
  v_row      public.member_track_enrollment;
  v_launched timestamptz;
  v_created  timestamptz;
begin
  if v_pid is null then return null; end if;

  select * into v_row from public.member_track_enrollment where patient_id = v_pid and track_code = p_track_code;
  if found then return v_row; end if;

  select launched_at into v_launched from public.app_track where code = p_track_code and active;
  if v_launched is null then return null; end if;

  select created_at into v_created from public.patients where id = v_pid;
  if v_created is null or v_created < v_launched then return null; end if;

  insert into public.member_track_enrollment (patient_id, track_code, source)
  values (v_pid, p_track_code, case when p_via = 'web' then 'web_first_open' else 'ios_first_open' end)
  on conflict (patient_id, track_code) do nothing;

  select * into v_row from public.member_track_enrollment where patient_id = v_pid and track_code = p_track_code;
  return v_row;
end $$;

-- Everything the app shows about the track, computed here. NULL when not enrolled.
--   day                 1-based Zurich calendar day (can exceed the track length; the app shows "done")
--   modules_done        submitted modules that count toward the review (days 1–5)
--   meals_expected      meals_per_day (day-2 answer; 3 until answered) × days elapsed, capped at the track length
--   meals_logged        nb_meal_logs rows since started_at, within the track window
--   review_unlocked     (all counted modules done AND logged ≥ 80 % of expected) OR the staff override
--   energy_kcal_low/high  tdee_kcal ± 5 %, rounded to 50 kcal (Thomas, 2026-10-06)
--   protein_g_low/high    weight × 1.3–1.7 g/kg (female) or 1.6–2.0 g/kg (male) (Thomas, 2026-10-06)
create or replace function public.member_track_status(p_track_code text default 'trial14_v1')
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
  v_sex        text;
  v_weight     numeric;
  v_tdee       numeric;
begin
  if v_pid is null then return null; end if;
  select * into v_enr from public.member_track_enrollment where patient_id = v_pid and track_code = p_track_code;
  if not found then return null; end if;

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
  v_expected := coalesce(v_mpd, 3) * v_elapsed;

  select count(*) into v_logged from public.nb_meal_logs m
   where m.patient_id = v_pid
     and m.created_at >= v_enr.started_at
     and m.created_at <  v_enr.started_at + make_interval(days => v_days);

  select app_sex, app_weight_kg, tdee_kcal into v_sex, v_weight, v_tdee
    from public.nb_patient_app_profiles where patient_id = v_pid;

  return jsonb_build_object(
    'track_code',       p_track_code,
    'started_at',       v_enr.started_at,
    'day',              v_day,
    'days',             v_days,
    'modules_done',     v_modules,
    'modules_total',    v_modules_n,
    'meals_expected',   v_expected,
    'meals_logged',     v_logged,
    'meals_pct',        case when v_expected > 0 then round(100.0 * v_logged / v_expected) end,
    'review_unlocked',  v_enr.review_call_override
                          or (v_modules_n > 0 and v_modules >= v_modules_n and v_expected > 0 and v_logged >= 0.8 * v_expected),
    'energy_kcal_low',  case when v_tdee > 0 then round(v_tdee * 0.95 / 50) * 50 end,
    'energy_kcal_high', case when v_tdee > 0 then round(v_tdee * 1.05 / 50) * 50 end,
    'protein_g_low',    case when v_weight > 0 and v_sex in ('female', 'male')
                          then round(v_weight * case v_sex when 'female' then 1.3 else 1.6 end) end,
    'protein_g_high',   case when v_weight > 0 and v_sex in ('female', 'male')
                          then round(v_weight * case v_sex when 'female' then 1.7 else 2.0 end) end
  );
end $$;

revoke all on function public.member_start_track(text, text) from public, anon;
revoke all on function public.member_track_status(text) from public, anon;
grant execute on function public.member_start_track(text, text) to authenticated;
grant execute on function public.member_track_status(text) to authenticated;

-- 9 ─ the track itself (not launched: launched_at stays NULL until Thomas says go) ──────────
insert into public.app_track (code, title, days, launched_at) values ('trial14_v1', 'The 14-day start', 14, null);
