-- match_food_reference: lexical candidates from the reference plane (USDA SR Legacy + CIQUAL) for many
-- reference names in ONE round trip. Used by the sovereign meal pricing (supabase/functions/_shared/meals/
-- sovereign-pricing.ts, 2026-11-10): an Infomaniak model turns each identified food into a USDA-style
-- description ("Seeds, chia seeds, dried"), this function returns the closest rows by trigram similarity,
-- and the edge function accepts a row only when it passes the food-word, raw/cooked and energy checks.
--
-- Pure SQL in Postgres (the trigram GIN index on nb_food_items.name): no embedding, so no isolate CPU —
-- the reason the embedding ladder could not price an eight-food plate inside the CPU budget.
-- Reference data, not patient data. Executable by the service role only (the edge functions).
-- Additive and idempotent.

create or replace function public.match_food_reference(q_terms text[], per_term integer default 6)
returns table (term text, id uuid, name text, energy_kcal numeric, sim double precision)
language sql
stable
set search_path to 'public', 'extensions'
as $$
  select t.term, c.id, c.name, c.energy_kcal, c.sim
  from (select distinct x as term from unnest(q_terms[1:40]) as x where length(trim(x)) between 2 and 160) t
  cross join lateral (
    select f.id, f.name, f.energy_kcal, similarity(f.name, t.term)::double precision as sim
    from public.nb_food_items f
    where f.name % t.term or t.term <% f.name
    order by similarity(f.name, t.term) desc, word_similarity(t.term, f.name) desc, length(f.name)
    limit greatest(1, least(coalesce(per_term, 6), 12))
  ) c;
$$;

revoke all on function public.match_food_reference(text[], integer) from public, anon, authenticated;
grant execute on function public.match_food_reference(text[], integer) to service_role;
