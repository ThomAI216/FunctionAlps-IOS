-- One-off backfill (owner, 2026-10-12): "pour tout le monde, par défaut, dans la routine du matin, il y aura la
-- petite activation matinale." Gives every EXISTING member with a login the "Morning stretch, five minutes" action
-- in their morning routine. New members get it from patient-register (v61, ensureDefaultMorningAction) — same rules:
--   · a self_initiated habit (the member owns it: they can remove it or move it up its ladder);
--   · skipped when the member already has a habit anywhere on the card's ladder (they keep their level);
--   · skipped when the morning routine already holds 3 active actions (the cap);
--   · title and description in the member's language (profile locale, else preferred language; French by default).
-- Run ONCE. Re-running is harmless for members who still have the action, but would re-add it for a member who
-- removed it in between.

with recursive ladder(id) as (
  select '623658e7-bea0-41a9-9fe5-d646a3340dda'::uuid
  union
  select b.next_level_id from public.habit_bank b join ladder l on b.id = l.id where b.next_level_id is not null
),
card as (
  select * from public.habit_bank
   where id = '623658e7-bea0-41a9-9fe5-d646a3340dda' and active and member_can_add
),
targets as (
  select p.id as patient_id,
         lower(coalesce(nullif(pr.locale, ''), p.preferred_language, 'fr')) like 'fr%' as fr
    from public.patients p
    left join public.nb_patient_app_profiles pr on pr.patient_id = p.id
   where p.auth_user_id is not null
     and p.status = 'active'
     and not exists (select 1 from public.habits h
                      where h.patient_id = p.id and h.status <> 'cancelled'
                        and h.habit_bank_id in (select id from ladder))
     and (select count(*) from public.habits h
           where h.patient_id = p.id and h.status = 'active' and h.slot = 'morning') < 3
)
insert into public.habits (patient_id, title, description, frequency_rule, slot, pillar, habit_bank_id, source, status)
select t.patient_id,
       case when t.fr then coalesce(nullif(c.title_fr, ''), c.title) else c.title end,
       case when t.fr then coalesce(nullif(c.description_fr, ''), c.description) else c.description end,
       coalesce(nullif(trim(c.frequency_rule), ''), 'FREQ=DAILY'),
       'morning', c.pillar, c.id, 'self_initiated', 'active'
  from targets t cross join card c
returning patient_id;
