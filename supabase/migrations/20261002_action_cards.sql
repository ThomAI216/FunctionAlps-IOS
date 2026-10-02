-- Action cards: the habit bank becomes the catalogue of cards the app opens (owner, 2026-10-02).
--
-- A card is a `habit_bank` row, authored in CLINICAL → Cartes action (with an OpenAI draft the clinician
-- reviews). Most of what a card shows already has a column: title / description (+ `_fr`), the gentler and
-- further versions (`easy_*`, `rev_*`), `how_md` (the steps), `general_why`, `image_url`, and `resources`
-- (jsonb, `[]` on every row today), which now holds the card's links as a typed list:
--   {"kind":"video","url":"https://…","title":"…"}     a video to play
--   {"kind":"youtube","query":"box breathing 4 4 4 4"}  a YouTube search the app opens
--   {"kind":"article","slug":"…","title":"…"}          a library article
--
-- Added here, all additive and nullable — nothing existing changes meaning:
--   card_kind        which detail page the app opens: breath · movement · routine · nutrition · mind · learn
--   duration_min     how long it takes, 1–240 minutes
--   how_md_fr        the steps in French (title/description already have their `_fr`)
--   general_why_fr   the why in French
--   published_at/by  a card the clinician has reviewed. Drafts are saved with active = false, so they stay
--                    invisible to members (RLS `habit_bank_member_select` = active) and to the daily focus
--                    engine; publishing sets active = true and stamps these. The 36 live cards count as
--                    published.
--   habits.habit_bank_id
--                    the card a prescribed habit opens. Members read the card LIVE (owner decision: a card
--                    edit reaches every patient who has it). Null = a habit with no card (today's rows).

alter table public.habit_bank
  add column if not exists card_kind text,
  add column if not exists duration_min smallint,
  add column if not exists how_md_fr text,
  add column if not exists general_why_fr text,
  add column if not exists published_at timestamptz,
  add column if not exists published_by uuid references public.users(id) on delete set null;

alter table public.habit_bank
  drop constraint if exists habit_bank_card_kind_check,
  add constraint habit_bank_card_kind_check
    check (card_kind is null or card_kind in ('breath', 'movement', 'routine', 'nutrition', 'mind', 'learn')),
  drop constraint if exists habit_bank_duration_min_check,
  add constraint habit_bank_duration_min_check
    check (duration_min is null or duration_min between 1 and 240);

update public.habit_bank
   set published_at = coalesce(updated_at, created_at)
 where active and published_at is null;

comment on column public.habit_bank.card_kind is 'Action card type — which detail page the app opens: breath | movement | routine | nutrition | mind | learn.';
comment on column public.habit_bank.duration_min is 'Action card duration in minutes (1–240).';
comment on column public.habit_bank.resources is 'Action card links, typed list: {kind:video,url,title} | {kind:youtube,query} | {kind:article,slug,title}.';
comment on column public.habit_bank.published_at is 'Reviewed and published by a clinician (CLINICAL → Cartes action). Drafts are active = false and null here.';

alter table public.habits
  add column if not exists habit_bank_id uuid references public.habit_bank(id) on delete set null;

create index if not exists habits_habit_bank_id_idx on public.habits (habit_bank_id);

comment on column public.habits.habit_bank_id is 'The action card this habit opens, read live from habit_bank (CLINICAL → Cartes action).';
