-- Today's focus, rebuilt on the owner's matrix (2026-11-12), and the evening follow-up after a hard morning.
--
-- 1. patient_day_state.focus_cell — the id of the matrix cell the day was decided on (P1…P5 · O1 · OG1…OG3 · G1 · G2, or
--    the row-only cells PX · GM). `member-daily-focus` computes the cell once after the morning check-in and stores it here,
--    so the Home card holds still through the day (a ring syncing at 09:30 reshuffles nothing) and the evening check-in can
--    tell whether the morning was hard. No CHECK on the values: the matrix is the function's, and a new cell must not need a
--    migration. The table's RLS is untouched: the member reads and writes their own row for today ± 1, clinic staff read.
--
-- 2. patient_day_feelings.evening_followup / evening_pills — the daily (after 14:00) functional check-in asks, after a hard
--    morning, "how was the rest of your day?" (-1 harder · 0 about the same · 1 better) and "what made the difference?"
--    (a list of pill keys: habits the member completed today and a few generic ones). Stored on today's feelings row; the
--    row's existing member update/insert policies (own row, today or yesterday, patient-local) already cover it.
--
-- The CONTRACT the clinician dashboard reads is unchanged: a depleted day is a patient_day_feelings row with
-- energy < 40 AND (mood < 40 OR motivation < 40).
--
-- ADDITIVE and IDEMPOTENT (nullable columns / a defaulted jsonb). Not applied by the commit that adds it — the owner applies
-- it after review. Apply it BEFORE deploying member-daily-focus: the function reads focus_cell with a fallback, but a day it
-- cannot store is a day it recomputes on every read. The app treats a missing column as "no follow-up saved".

alter table public.patient_day_state
  add column if not exists focus_cell text;

comment on column public.patient_day_state.focus_cell is
  'The Today''s-focus matrix cell the day was decided on (P1-P5, O1, OG1-OG3, G1, G2; PX / GM when the feeling was skipped). Stored once by member-daily-focus after the morning check-in so the card holds still and the evening follow-up knows the morning was hard.';

alter table public.patient_day_feelings
  add column if not exists evening_followup smallint check (evening_followup in (-1, 0, 1)),
  add column if not exists evening_pills jsonb not null default '[]'::jsonb;

comment on column public.patient_day_feelings.evening_followup is
  'After a hard morning, the member''s answer in the evening check-in to "how was the rest of your day?": -1 harder, 0 about the same, 1 better. Null = not asked or not answered.';
comment on column public.patient_day_feelings.evening_pills is
  'What made the difference, as a jsonb array of pill keys: habit ids the member completed today (habit:<uuid>) and generic keys (rest, food, people, work, movement, sleep_debt, ...).';
