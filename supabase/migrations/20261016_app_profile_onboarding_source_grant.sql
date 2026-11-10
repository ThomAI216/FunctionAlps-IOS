-- A member can write their own `onboarding_source` (live 2026-10-16: a new discovery member was stuck on the
-- last onboarding screen, "We couldn't save that you've finished setting up").
--
-- WHY IT WAS REFUSED: `20260819e_relock_app_profile_columns_after_table_grant` replaced the table-wide
-- INSERT/UPDATE with per-column grants of "every column except the protected eight". That list was frozen
-- on 2026-08-20; `191_onboarding_source` added the column on 2026-08-27 and granted nothing, so the column
-- fell outside it. The iOS stamp (since 2026-09-14) writes `onboarding_completed_at` +
-- `onboarding_source = 'app_baseline'` in ONE PATCH, and Postgres refuses the whole statement (42501 → 403):
-- the stamp never landed, so the gate kept every new iOS member in onboarding.
--
-- `onboarding_source` is descriptive only (its column comment: "never gate on it") and its CHECK constraint
-- bounds the values; it is not one of the protected entitlement/lifecycle columns (tier, funnel_status,
-- trial_started_at, trial_extended_at, warmed_at, invite_token, visibility_class, trial_emails_opt_out_at),
-- which stay service_role only. RLS still limits the row to the member's own.
--
-- ⚠ A column added to nb_patient_app_profiles later gets NO member grant by default: add it here too if the
-- app writes it.

grant insert (onboarding_source), update (onboarding_source)
  on public.nb_patient_app_profiles to authenticated;
