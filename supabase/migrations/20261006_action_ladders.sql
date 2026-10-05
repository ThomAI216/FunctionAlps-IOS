-- Evolution ladders (owner, 2026-10-06: "build it"). Design: docs/action-cards/routines-design.md §3–4.
--
-- A card may point at its next level (`habit_bank.next_level_id`); a chain of cards is a ladder. A member's
-- habit moves up a level IN PLACE (same habit row, so its streak and history carry on): it takes the next card,
-- its texts, and `level_since` = the member's day. The rule is server-side (CLAUDE.md rule 9) and reads
-- completions only, never health data (the habit-loop doctrine):
--   · 3 completions at the current level in the last 7 days;
--   · no other habit in the same routine (slot) moved up in the last 7 days — one change per routine per week;
--   · the habit is not locked by a clinician (`habits.level_locked`);
--   · a member's own habit (self_initiated) never moves onto a prescription-only card (member_can_add false).

alter table public.habit_bank
  add column if not exists next_level_id uuid references public.habit_bank (id) on delete set null;
alter table public.habit_bank drop constraint if exists habit_bank_next_level_not_self;
alter table public.habit_bank
  add constraint habit_bank_next_level_not_self check (next_level_id is null or next_level_id <> id);
create index if not exists habit_bank_next_level_idx on public.habit_bank (next_level_id);
comment on column public.habit_bank.next_level_id is
  'The next level of this action (evolution ladder). Null = top of its ladder.';

alter table public.habits add column if not exists level_since date;
alter table public.habits add column if not exists level_locked boolean not null default false;
comment on column public.habits.level_since is
  'The member day this habit reached its current card (level). Null = since the habit was created.';
comment on column public.habits.level_locked is
  'A clinician keeps this habit at its current level: member_level_up refuses.';

create or replace function public.member_level_up(p_habit uuid)
returns public.habits
language plpgsql
security definer
set search_path = public
as $$
declare
  h public.habits;
  cur public.habit_bank;
  nxt public.habit_bank;
  today date;
  since date;
  n int;
begin
  select * into h from public.habits
   where id = p_habit and patient_id = public.current_member_patient_id() and status = 'active'
   for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if h.level_locked then raise exception 'level_locked'; end if;

  select * into cur from public.habit_bank where id = h.habit_bank_id;
  if cur.id is null or cur.next_level_id is null then raise exception 'no_next_level'; end if;
  select * into nxt from public.habit_bank where id = cur.next_level_id and active;
  if nxt.id is null then raise exception 'next_level_unavailable'; end if;
  if h.source = 'self_initiated' and not coalesce(nxt.member_can_add, false) then
    raise exception 'prescription_only';
  end if;

  today := public.patient_local_today(h.patient_id);
  since := greatest(coalesce(h.level_since, h.created_at::date), today - 6);
  select count(distinct completion_date::date) into n
    from public.habit_completions
   where habit_id = h.id and completion_date::date between since and today;
  if n < 3 then raise exception 'not_ready'; end if;

  if exists (
    select 1 from public.habits o
     where o.patient_id = h.patient_id and o.id <> h.id and o.status = 'active'
       and o.slot is not distinct from h.slot and o.level_since > today - 7
  ) then raise exception 'one_change_per_week'; end if;

  update public.habits
     set habit_bank_id = nxt.id, title = nxt.title, description = nxt.description,
         easy_title = nxt.easy_title, easy_description = nxt.easy_description,
         rev_title = nxt.rev_title, rev_description = nxt.rev_description,
         level_since = today, updated_at = now()
   where id = h.id
  returning * into h;
  return h;
end
$$;

revoke all on function public.member_level_up(uuid) from public, anon;
grant execute on function public.member_level_up(uuid) to authenticated;

-- The ladders whose levels are already cards on CM OS (2026-10-06). The others wait for their cards
-- (docs/action-cards/routines-design.md §3, "new").
update public.habit_bank set next_level_id = 'e9c25572-8e38-4c7d-9ad8-4c9fb7af925b'  -- Five minutes of daylight → Morning light within an hour of waking
 where id = 'afa499c9-5033-43d3-bf0c-81f2b8e70819';
update public.habit_bank set next_level_id = '30032ec5-201b-49a7-bcb1-8caa536c6e0e'  -- Ten sit-to-stands → One set of push-ups
 where id = 'c8ccfdf5-ea3a-4282-b987-f231d6bdbf73';
update public.habit_bank set next_level_id = '35cc27af-c8e5-4c4f-af0c-cf790ddd6228'  -- A 10-minute walk after lunch → Walk five minutes every half hour (draft)
 where id = '7e6ee768-30fe-4781-ba62-52669aeab7c3';
update public.habit_bank set next_level_id = 'f8f1a28b-cb2f-47fb-a6ac-553438019aa6'  -- Walk five minutes every half hour → A brisk 30-minute walk (draft)
 where id = '35cc27af-c8e5-4c4f-af0c-cf790ddd6228';
