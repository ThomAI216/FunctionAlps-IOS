# Action-card tracks: design (2026-10-05)

## Status
Superseded in part by `routines-design.md` (routines, weekly priorities, evolution ladders). The tier model below still holds.

Proposal. The migration `supabase/migrations/20261005_action_tracks.sql` is **not applied**. The owner wants
the second pass on the catalogue (`catalogue-first-pass.md`) done first.

## What a member gets

| Tier | Rule on the card | Who sees it |
|---|---|---|
| Trial | `member_can_add = true`, `members_only = false` | Everyone, from the first day of the 2-week trial |
| Members only | `member_can_add = true`, `members_only = true` | Paying members (about 10–15 % of the non-prescription cards: "a few small ones for us") |
| Prescription | `member_can_add = false` | Only members a practitioner prescribed it to (already enforced by `focusEligibleBank` in the daily focus) |

Owner decision: the trial becomes a **14-day trial plan** (`trial_14_day` entitlement granted at sign-up, in place of
the 3 discovery days). This is built with the app delivery step, not before.

## Tracks, packs, progressions
- **Track**: the cards for one objective, grouped in **stages**. Stage 1 comes first; later stages unlock after
  `unlock_after_days`.
  - Objectives: Basic (everyone) · More energy · Better sleep · More focus · Less brain fog · Build muscle · Lose weight
    (· Less stress, proposed).
  - `goal_keys` links a track to the objectives a member picks (`nb_patient_app_profiles.health_goals`).
  - The existing keys cover energy, sleep, weight and stress. Focus, brain fog and muscle need new keys, and iOS
    onboarding needs a goal picker: today only the Expo app asks.
- **Mini pack**: `kind = 'pack'`, a small themed set (e.g. "learn faster": three members-only cards).
- **Progression inside a card**: the gentle, standard and further versions already exist (`easy_*`, `rev_*`).
  - The track step's `starts_as` says which version a member starts on.
  - The daily focus already moves between versions by readiness.
- **Progression across cards**: the stages.

## Steps
1. Owner's second pass on the catalogue: tier and tracks per card.
2. Apply the migration (approval needed). Then:
   - write `members_only` and `member_can_add` on the cards;
   - seed the tracks from the second pass;
   - deploy `focusEligibleBank` (branch only until the flags are set).
3. CLINICAL → Action cards gets a **Tracks** tab:
   - list of tracks and packs, a track editor (EN/FR texts, objectives, stages, cards, starting version, unlock day);
   - trial / members / prescription counts per track;
   - a "members only" switch in the card editor.
4. App delivery:
   - goal picker in iOS onboarding;
   - `member_tracks` (which tracks a member follows, since when);
   - the 14-day trial plan;
   - the action bank and daily focus filter by tier.
