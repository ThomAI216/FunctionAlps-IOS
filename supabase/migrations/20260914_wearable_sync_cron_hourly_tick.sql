-- pg_cron job 18 (wearable-vendor-sync, */10): also fire on the first tick of every hour while Oura is `available`,
-- queue or no queue — the function's Oura webhook-subscription upkeep (`ouraMaintain`, minute < 10) never ran while the
-- queue was empty (found 2026-09-14 21:14 UTC). Applied on CM OS with cron.alter_job(18, command := …) the same evening.
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
                 where vendor is not null and (status = 'pending' or (status = 'processing' and lock_expires_at < now())))
     -- once an hour regardless of the queue: the function's Oura webhook-subscription upkeep runs on the first tick of the hour
     or (extract(minute from now()) < 10 and exists (select 1 from public.wearable_vendors where key = 'oura' and status = 'available'));
$cmd$);
