-- 2026-11-06 — Strava as a direct vendor, behind status 'planned' (activities only: no sleep, HRV, resting HR,
-- steps or weight). Additive: ONE row in `wearable_vendors` — every vendor FK (oauth states, accounts, queue,
-- receipts, webhook subscriptions, sync state) points here, and `wearable_erase_vendor_data()` and the clinical
-- dashboard read the source id and name from this row, so nothing else changes.
-- data_source_id 1000070: FunctionAlps-assigned, after the reserved Health Connect relay id (1000060).
-- Adapter: supabase/functions/_shared/wearables/strava.ts. Flip to 'available' only after the owner's go and one
-- real connection has synced (docs/DEPLOYMENT.md → Direct wearable connectors → Strava).
-- Status: NOT APPLIED on CM OS (dry run BEGIN…ROLLBACK passed 2026-11-06) — waits for the owner's go.
insert into public.wearable_vendors (key, name, data_source_id, status, notes)
values ('strava', 'Strava', 1000070, 'planned', 'Strava API v3 — activities only (workout epochs); unsigned webhook = pull hint; new apps capped at 1 athlete until Strava review')
on conflict (key) do nothing;
