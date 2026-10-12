-- One-off backfill (owner, 2026-10-12): "pour tout le monde, par défaut, dans la routine du matin, il y aura la
-- petite activation matinale." Gives every EXISTING member with a login the "Morning activation, five minutes" action
-- in their morning routine. New members get it from patient-register (v61, ensureDefaultMorningAction) — same rules:
--   · a self_initiated habit (the member owns it: they can remove it or move it up its ladder), copied the way the
--     apps add a bank card: title, description, gentler / further versions, why and links (Expo createHabitFromBank);
--   · skipped when the member's MORNING routine already holds a habit on the card's ladder (they keep their level;
--     a habit in another routine on a card two ladders share does not count);
--   · skipped when the morning routine is full: 3 active actions, 2 while the member's first action is under 14 days
--     old (the app's RoutineRules);
--   · texts in the member's language (profile locale, else preferred language; French by default).
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
                      where h.patient_id = p.id and h.status <> 'cancelled' and h.slot = 'morning'
                        and h.habit_bank_id in (select id from ladder))
     and (select count(*) from public.habits h
           where h.patient_id = p.id and h.status = 'active' and h.slot = 'morning')
         < case when coalesce((select min(h.created_at) from public.habits h
                                where h.patient_id = p.id and h.status <> 'cancelled'), now())
                     > now() - interval '14 days'
                then 2 else 3 end
)
insert into public.habits (patient_id, title, description, easy_title, easy_description, rev_title, rev_description,
                           general_why, resources, frequency_rule, slot, pillar, habit_bank_id, source, status)
select t.patient_id,
       case when t.fr then coalesce(nullif(c.title_fr, ''), c.title) else c.title end,
       case when t.fr then coalesce(nullif(c.description_fr, ''), c.description) else coalesce(nullif(c.description, ''), c.description_fr) end,
       case when t.fr then coalesce(nullif(c.easy_title_fr, ''), c.easy_title) else coalesce(nullif(c.easy_title, ''), c.easy_title_fr) end,
       case when t.fr then coalesce(nullif(c.easy_description_fr, ''), c.easy_description) else coalesce(nullif(c.easy_description, ''), c.easy_description_fr) end,
       case when t.fr then coalesce(nullif(c.rev_title_fr, ''), c.rev_title) else coalesce(nullif(c.rev_title, ''), c.rev_title_fr) end,
       case when t.fr then coalesce(nullif(c.rev_description_fr, ''), c.rev_description) else coalesce(nullif(c.rev_description, ''), c.rev_description_fr) end,
       case when t.fr then coalesce(nullif(c.general_why_fr, ''), c.general_why) else coalesce(nullif(c.general_why, ''), c.general_why_fr) end,
       -- A habit's links are { kind, title, url } (Expo parseResources); a card's YouTube search has no url.
       case when jsonb_typeof(c.resources) = 'array'
            then coalesce((select jsonb_agg(e) from jsonb_array_elements(c.resources) e
                            where jsonb_typeof(e->'title') = 'string' and (e->>'url') ~* '^https?://'), '[]'::jsonb)
            else '[]'::jsonb end,
       coalesce(nullif(trim(c.frequency_rule), ''), 'FREQ=DAILY'),
       'morning', c.pillar, c.id, 'self_initiated', 'active'
  from targets t cross join card c
returning patient_id;
