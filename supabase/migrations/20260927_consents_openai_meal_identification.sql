-- privacy_policy (next version) + ai_analysis v8 + health_data_processing v7 — meal identification moves to OpenAI.
--
-- APPLIED on CM OS 2026-09-27 19:49 UTC at the operator's instruction (migration
-- `consents_openai_meal_identification`): privacy_policy v11 -> v12, ai_analysis v7 -> v8,
-- health_data_processing v6 -> v7, en + fr. The 36 text literals stored in schema_migrations were
-- checked byte-for-byte against this file. health_data_processing is a doc_kind='consent' row, so every
-- member re-accepts on next launch (the versions moved, `accepted` flips to false).
--
-- WHY: on 2026-09-27 the operator decided that identifying the foods in a meal photograph or a meal
-- description runs on OpenAI (gpt-5.4-mini) instead of Infomaniak's vision model, which had started
-- timing out on half of all photos. The switch is the Supabase secret MEAL_AI_PROVIDER=openai
-- (supabase/functions/_shared/meals/meal-analysis.ts). All three documents below currently PROMISE
-- that member data is not sent to OpenAI, so this migration must be applied BEFORE that secret is set,
-- never after.
--
-- What changes, en + fr, and nothing else:
--   privacy_policy §1 at-a-glance bullet, §8 who runs the AI, §9a the wearables sentence ("like
--     everything else you log" stops being true), §11 the provider list gains OpenAI, §12 the transfer
--     paragraph names the United States. §12's existing Standard Contractual Clauses paragraph already
--     covers a provider outside Switzerland/the EEA — it requires the OpenAI DPA (with SCCs) to be signed.
--   ai_analysis §4 where it runs / who does not get your data.
--   health_data_processing §2 and §3, the two sentences naming where the analysis runs.
-- Voice (Infomaniak Whisper), meal-description structuring (preprocess-meal), reports, tips and the
-- website assessment stay on Infomaniak and their sentences are untouched.
--
-- privacy_policy builds on whichever version is current (v11 today, or v12 if that draft is applied
-- first — none of its anchors are touched by v12) and takes the next number. Every anchor is checked to
-- occur exactly once; all 18 were verified against the live v11 / v7 / v6 bodies on 2026-09-27.
create or replace function pg_temp.fa_apply_edits(body text, anchors text[], replacements text[]) returns text language plpgsql as $f$
declare i int; c int;
begin
  for i in 1 .. array_length(anchors, 1) loop
    c := (length(body) - length(replace(body, anchors[i], ''))) / length(anchors[i]);
    if c <> 1 then raise exception 'anchor % occurs % times: %', i, c, left(anchors[i], 60); end if;
    body := replace(body, anchors[i], replacements[i]);
  end loop;
  return body;
end $f$;
do $mig$
declare n int; pp_from text; pp_to text;
begin
  select version into pp_from from public.consent_definitions
   where consent_key = 'privacy_policy' and superseded_at is null and review_status = 'approved' and locale = 'en';
  if pp_from is null then raise exception 'no current privacy_policy'; end if;
  pp_to := 'v' || (substring(pp_from from 2)::int + 1);
  if exists (select 1 from public.consent_definitions where (consent_key = 'privacy_policy' and version = pp_to)
             or (consent_key = 'ai_analysis' and version = 'v8') or (consent_key = 'health_data_processing' and version = 'v7')) then
    raise exception 'privacy_policy % / ai_analysis v8 / health_data_processing v7 already exist', pp_to;
  end if;

  -- ── privacy_policy ──────────────────────────────────────────────────────────────────────────────
  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note)
  select consent_key, pp_to, locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[
             E'- Analysis is performed by Infomaniak, a Swiss provider, on infrastructure in Geneva. Your data is not sent to OpenAI, Google, Anthropic or any other general-purpose AI provider, and is never used to train anyone’s models.',
             E'Identifying foods, estimating nutrients, scoring meals, detecting patterns and drafting reports are all performed by AI models operated by Infomaniak on infrastructure in Geneva, Switzerland.',
             E'Like everything else you log, they are never sent to OpenAI, Google, Anthropic or any other general-purpose AI provider.',
             E'- Infomaniak — AI analysis, speech-to-text, and our transactional email. Switzerland (Geneva).',
             E'Your data is stored and processed in the European Union and in Switzerland. Both are recognised by the other'
           ],
           array[
             E'- Your meal photographs and meal descriptions are sent to OpenAI, in the United States, to identify the foods and estimate the portions. Everything else is analysed by Infomaniak, a Swiss provider, on infrastructure in Geneva, and is not sent to OpenAI, Google, Anthropic or any other general-purpose AI provider. None of your data is used to train anyone’s models.',
             E'Identifying the foods in a meal photograph or description, and estimating their portions, is performed by an AI model operated by OpenAI in the United States. Estimating nutrients, scoring meals, detecting patterns and drafting reports are performed by AI models operated by Infomaniak on infrastructure in Geneva, Switzerland.',
             E'They are never sent to OpenAI, Google, Anthropic or any other general-purpose AI provider.',
             E'- Infomaniak — AI analysis, speech-to-text, and our transactional email. Switzerland (Geneva).\n- OpenAI — identifying the foods in your meal photographs and meal descriptions. United States. OpenAI may keep what it receives for up to 30 days to detect abuse, then deletes it, and does not use it to train its models.',
             E'Your data is stored and processed in the European Union and in Switzerland, with one exception: your meal photographs and meal descriptions are sent to OpenAI in the United States to identify the foods, under the safeguards described in the next paragraph. The European Union and Switzerland are each recognised by the other'
           ])
                     else pg_temp.fa_apply_edits(body_md,
           array[
             E'- L’analyse est effectuée par Infomaniak, fournisseur suisse, sur une infrastructure située à Genève. Vos données ne sont transmises ni à OpenAI, ni à Google, ni à Anthropic, ni à aucun autre fournisseur d’IA généraliste, et ne servent jamais à entraîner les modèles de quiconque.',
             E'L’identification des aliments, l’estimation des nutriments, la notation des repas, la détection de tendances et la rédaction des rapports sont effectuées par des modèles d’IA exploités par Infomaniak sur une infrastructure située à Genève, en Suisse.',
             E'Comme tout ce que vous enregistrez, elles ne sont jamais transmises à OpenAI, Google, Anthropic ni à aucun autre fournisseur d’IA généraliste.',
             E'- Infomaniak — analyse par IA, transcription vocale et messagerie transactionnelle. Suisse (Genève).',
             E'Vos données sont conservées et traitées dans l’Union européenne et en Suisse. Ces deux espaces'
           ],
           array[
             E'- Les photos et descriptions de vos repas sont transmises à OpenAI, aux États-Unis, pour identifier les aliments et estimer les portions. Tout le reste est analysé par Infomaniak, fournisseur suisse, sur une infrastructure située à Genève, et n’est transmis ni à OpenAI, ni à Google, ni à Anthropic, ni à aucun autre fournisseur d’IA généraliste. Aucune de vos données ne sert à entraîner les modèles de quiconque.',
             E'L’identification des aliments sur une photo ou une description de repas, et l’estimation de leurs portions, sont effectuées par un modèle d’IA exploité par OpenAI aux États-Unis. L’estimation des nutriments, la notation des repas, la détection de tendances et la rédaction des rapports sont effectuées par des modèles d’IA exploités par Infomaniak sur une infrastructure située à Genève, en Suisse.',
             E'Elles ne sont jamais transmises à OpenAI, Google, Anthropic ni à aucun autre fournisseur d’IA généraliste.',
             E'- Infomaniak — analyse par IA, transcription vocale et messagerie transactionnelle. Suisse (Genève).\n- OpenAI — identification des aliments sur les photos et descriptions de vos repas. États-Unis. OpenAI peut conserver ce qu’il reçoit jusqu’à 30 jours pour détecter les abus, puis le supprime, et ne l’utilise pas pour entraîner ses modèles.',
             E'Vos données sont conservées et traitées dans l’Union européenne et en Suisse, à une exception près : les photos et descriptions de vos repas sont transmises à OpenAI, aux États-Unis, pour identifier les aliments, avec les garanties décrites au paragraphe suivant. L’Union européenne et la Suisse'
           ]) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(),
         pp_to || ' = ' || pp_from || ' with meal identification (photos and descriptions) moved to OpenAI, United States: at-a-glance, §8, §9a, §11 provider list, §12 transfers. Operator''s call 2026-09-27 (qualified legal review still to come).'
    from public.consent_definitions where consent_key = 'privacy_policy' and version = pp_from and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'privacy_policy %: expected 2 rows inserted, got %', pp_to, n; end if;

  -- ── ai_analysis ─────────────────────────────────────────────────────────────────────────────────
  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note)
  select consent_key, 'v8', locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[
             E'All of it runs on Infomaniak’s sovereign infrastructure in Geneva, Switzerland. Infomaniak processes your data strictly on our instructions, under a data processing agreement, and may not use it for its own purposes.',
             E'Your health data is not sent to OpenAI, Google, Anthropic, Meta or any other general-purpose AI provider. It is not used to train AI models — ours, Infomaniak’s, or anyone else’s.'
           ],
           array[
             E'Identifying the foods in a meal photograph or description runs on OpenAI, in the United States. Everything else runs on Infomaniak’s sovereign infrastructure in Geneva, Switzerland. Both process your data strictly on our instructions, under a data processing agreement, and may not use it for their own purposes.',
             E'Apart from the meal photographs and descriptions sent to OpenAI to identify the foods, your health data is not sent to OpenAI, Google, Anthropic, Meta or any other general-purpose AI provider. It is not used to train AI models — ours, OpenAI’s, Infomaniak’s, or anyone else’s.'
           ])
                     else pg_temp.fa_apply_edits(body_md,
           array[
             E'L’ensemble s’exécute sur l’infrastructure souveraine d’Infomaniak à Genève, en Suisse. Infomaniak traite vos données strictement sur nos instructions, dans le cadre d’un accord de sous-traitance, et ne peut les utiliser à ses propres fins.',
             E'Vos données de santé ne sont transmises ni à OpenAI, ni à Google, ni à Anthropic, ni à Meta, ni à aucun autre fournisseur d’IA généraliste. Elles ne servent pas à entraîner de modèles — ni les nôtres, ni ceux d’Infomaniak, ni ceux de quiconque.'
           ],
           array[
             E'L’identification des aliments sur une photo ou une description de repas s’exécute chez OpenAI, aux États-Unis. Tout le reste s’exécute sur l’infrastructure souveraine d’Infomaniak à Genève, en Suisse. L’un et l’autre traitent vos données strictement sur nos instructions, dans le cadre d’un accord de sous-traitance, et ne peuvent les utiliser à leurs propres fins.',
             E'En dehors des photos et descriptions de repas transmises à OpenAI pour identifier les aliments, vos données de santé ne sont transmises ni à OpenAI, ni à Google, ni à Anthropic, ni à Meta, ni à aucun autre fournisseur d’IA généraliste. Elles ne servent pas à entraîner de modèles — ni les nôtres, ni ceux d’OpenAI, ni ceux d’Infomaniak, ni ceux de quiconque.'
           ]) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(),
         'v8 = v7 with §4 restated: identifying the foods in meal photographs and descriptions runs on OpenAI, United States; everything else stays on Infomaniak. Operator''s call 2026-09-27 (qualified legal review still to come).'
    from public.consent_definitions where consent_key = 'ai_analysis' and version = 'v7' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'ai_analysis v8: expected 2 rows inserted, got %', n; end if;

  -- ── health_data_processing ─────────────────────────────────────────────────────────────────────
  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note)
  select consent_key, 'v7', locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[
             E'The analysis is carried out on our own infrastructure and by our AI provider in Switzerland, as described',
             E'The analysis runs on Infomaniak’s infrastructure in Geneva, Switzerland. Your data is not sent to OpenAI, Google, Anthropic or any other general-purpose AI provider, and it is never used to train anyone’s models.'
           ],
           array[
             E'The analysis is carried out on our own infrastructure, by our AI provider in Switzerland and, to identify the foods in your meals, by OpenAI in the United States, as described',
             E'Identifying the foods in a meal photograph or description runs on OpenAI in the United States; the rest of the analysis runs on Infomaniak’s infrastructure in Geneva, Switzerland. Apart from those meal photographs and descriptions, your data is not sent to OpenAI, Google, Anthropic or any other general-purpose AI provider, and it is never used to train anyone’s models.'
           ])
                     else pg_temp.fa_apply_edits(body_md,
           array[
             E'L’analyse est effectuée sur notre propre infrastructure et par notre fournisseur d’IA en Suisse, comme décrit',
             E'L’analyse s’exécute sur l’infrastructure d’Infomaniak à Genève, en Suisse. Vos données ne sont transmises ni à OpenAI, ni à Google, ni à Anthropic, ni à aucun autre fournisseur d’IA généraliste, et elles ne servent jamais à entraîner les modèles de quiconque.'
           ],
           array[
             E'L’analyse est effectuée sur notre propre infrastructure, par notre fournisseur d’IA en Suisse et, pour identifier les aliments de vos repas, par OpenAI aux États-Unis, comme décrit',
             E'L’identification des aliments sur une photo ou une description de repas s’exécute chez OpenAI, aux États-Unis ; le reste de l’analyse s’exécute sur l’infrastructure d’Infomaniak à Genève, en Suisse. En dehors de ces photos et descriptions de repas, vos données ne sont transmises ni à OpenAI, ni à Google, ni à Anthropic, ni à aucun autre fournisseur d’IA généraliste, et elles ne servent jamais à entraîner les modèles de quiconque.'
           ]) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(),
         'v7 = v6 with §2 and §3 naming OpenAI, United States, for identifying the foods in meal photographs and descriptions. Operator''s call 2026-09-27 (qualified legal review still to come).'
    from public.consent_definitions where consent_key = 'health_data_processing' and version = 'v6' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'health_data_processing v7: expected 2 rows inserted, got %', n; end if;

  update public.consent_definitions set superseded_at = now() where consent_key = 'privacy_policy' and version = pp_from and superseded_at is null;
  update public.consent_definitions set superseded_at = now() where consent_key = 'ai_analysis' and version = 'v7' and superseded_at is null;
  update public.consent_definitions set superseded_at = now() where consent_key = 'health_data_processing' and version = 'v6' and superseded_at is null;
  raise notice 'privacy_policy % + ai_analysis v8 + health_data_processing v7 current (en + fr); % / v7 / v6 superseded', pp_to, pp_from;
end
$mig$;
drop function pg_temp.fa_apply_edits(text, text[], text[]);
