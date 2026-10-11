-- STATUS: NOT APPLIED. Owner said "not yet" (2026-10-05): apply after the second pass on the catalogue.
-- Dry run on CM OS passed and was rolled back the same day.
-- Action-card tracks and mini packs (owner request 2026-10-05).
-- A track is a sequence of action cards for one objective (Basic, More energy, Better sleep, More focus,
-- Less brain fog, Build muscle, Lose weight…); a pack is a small themed set. Cards are grouped in stages:
-- stage 1 first, later stages unlock after `unlock_after_days`. Inside a card, the easy / standard / further
-- versions already exist (habit_bank easy_* / rev_*): `starts_as` says which version the card opens on.
--
-- Tiers on a card:
--   member_can_add = false            → prescription only (a practitioner prescribes it)
--   member_can_add = true, members_only = false → offered in the 2-week trial and after
--   member_can_add = true, members_only = true  → kept for paying members
-- Authored in CLINICAL → Action cards → Tracks. Delivery to the app is a later step (member_tracks).

alter table public.habit_bank
  add column if not exists members_only boolean not null default false;
comment on column public.habit_bank.members_only is
  'Kept for paying members, not offered during the trial. Only meaningful when member_can_add is true (false = prescription only).';

create table if not exists public.action_tracks (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z0-9_]{2,40}$'),
  kind text not null default 'track' check (kind in ('track', 'pack')),
  title text not null check (length(title) between 1 and 120),
  title_fr text,
  description text,
  description_fr text,
  -- nb_patient_app_profiles.health_goals keys that select this track (boost_energy, better_sleep, …).
  goal_keys text[] not null default '{}',
  -- The one track every member gets, whatever their objective.
  is_basic boolean not null default false,
  -- A whole track or pack kept for paying members.
  members_only boolean not null default false,
  status text not null default 'draft' check (status in ('draft', 'published', 'retired')),
  sort_order int not null default 100,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists action_tracks_one_basic
  on public.action_tracks ((true)) where is_basic and status <> 'retired';

create table if not exists public.action_track_steps (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references public.action_tracks (id) on delete cascade,
  habit_bank_id uuid not null references public.habit_bank (id) on delete restrict,
  stage smallint not null default 1 check (stage between 1 and 12),
  position smallint not null default 0,
  starts_as text not null default 'standard' check (starts_as in ('easy', 'standard', 'rev')),
  -- Days after the member starts the track before this card is offered; null = with its stage.
  unlock_after_days smallint check (unlock_after_days between 0 and 365),
  created_at timestamptz not null default now(),
  unique (track_id, habit_bank_id)
);
create index if not exists action_track_steps_track_idx on public.action_track_steps (track_id, stage, position);
create index if not exists action_track_steps_card_idx on public.action_track_steps (habit_bank_id);

alter table public.action_tracks enable row level security;
alter table public.action_track_steps enable row level security;

-- Same shape as habit_bank: members read what is published, nutritionists and above author.
create policy action_tracks_member_select on public.action_tracks
  for select to authenticated using (status = 'published');
create policy action_tracks_nutritionist_write on public.action_tracks
  for all to authenticated using (is_nutritionist_or_above()) with check (is_nutritionist_or_above());
create policy service_role_bypass_action_tracks on public.action_tracks
  for all to service_role using (true) with check (true);

create policy action_track_steps_member_select on public.action_track_steps
  for select to authenticated using (
    exists (select 1 from public.action_tracks t where t.id = track_id and t.status = 'published'));
create policy action_track_steps_nutritionist_write on public.action_track_steps
  for all to authenticated using (is_nutritionist_or_above()) with check (is_nutritionist_or_above());
create policy service_role_bypass_action_track_steps on public.action_track_steps
  for all to service_role using (true) with check (true);
