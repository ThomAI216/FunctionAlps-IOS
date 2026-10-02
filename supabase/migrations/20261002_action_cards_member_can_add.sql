-- Action cards members may add themselves (owner, 2026-10-02): "users can also choose from a bank of available
-- actions — the foundational ones — learn about them in the library and add them to their action plan".
--
-- A published card (active) with member_can_add = true shows in the app's action bank. Adding one creates the
-- member's OWN habit (source = 'self_initiated', habit_bank_id = the card) — the existing RLS
-- `habits_member_self_insert` already allows exactly that and nothing more. The clinician ticks the box in
-- CLINICAL → Action cards. Additive, default false: no card changes behaviour until someone ticks it.

alter table public.habit_bank
  add column if not exists member_can_add boolean not null default false;

comment on column public.habit_bank.member_can_add is 'Members may add this published card to their own plan from the app''s action bank (self_initiated habit).';
