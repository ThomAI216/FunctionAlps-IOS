-- privacy_policy v13 + terms_of_use v9 + legal_notice v2 — Thomas Convent is the operator and controller.
--
-- Operator's call, 2026-11-04 (Thomas): "Thomas is the full operator and data controller. Only keep
-- Alessandra's business number, and then contact should be Thomas. Address: Rue du Grand Place."
-- These rows are the ONE shared text read by the iOS app, the Expo app and every other surface.
--
-- What changes, both locales:
--   operator / controller  Alessandra Ginsburg, independent practitioner  ->  Thomas Convent
--   business number        CHE-205.025.089 (unchanged)
--   address                Chemin de Bonne-Eau 1, 3975  ->  Rue du Grand Place 2, 3963 Crans-Montana
--   every contact          data@ / support@functionalps.ch  ->  thomas@functionalps.ch
-- Nothing else in the documents changes.
--
-- Effect: terms_of_use is doc_kind 'consent', so its version moving reopens the consent gate and
-- every member re-accepts the Terms once (the contracting party changed). The privacy policy and
-- legal notice are notices: no re-acceptance.
--
-- ⚠ The unapplied draft 20260918_privacy_v12_terms_v9_no_dob_at_registration.sql now collides
-- (terms v9 is taken here): rebuild it as privacy v14 / terms v10 from these rows before applying.
create or replace function pg_temp.fa_apply_edits(body text, anchors text[], replacements text[]) returns text language plpgsql as $f$
declare i int; c int;
begin
  for i in 1 .. array_length(anchors, 1) loop
    c := (length(body) - length(replace(body, anchors[i], ''))) / length(anchors[i]);
    if c <> 1 then raise exception 'anchor % occurs % times: %', i, c, left(anchors[i], 60); end if;
    body := replace(body, anchors[i], replacements[i]);
  end loop;
  -- every remaining contact address becomes Thomas's
  body := replace(replace(body, 'data@functionalps.ch', 'thomas@functionalps.ch'), 'support@functionalps.ch', 'thomas@functionalps.ch');
  if body ~ 'Alessandra|Ginsburg|Bonne-Eau|3975|data@functionalps|support@functionalps' then
    raise exception 'old operator, address or contact still present';
  end if;
  return body;
end $f$;

do $mig$
declare n int;
  note text := ' Operator''s call 2026-11-04 (Thomas): Thomas Convent is the operator and controller; business number CHE-205.025.089 kept; address Rue du Grand Place 2, 3963 Crans-Montana; every contact thomas@functionalps.ch. Nothing else changed.';
begin
  if exists (select 1 from public.consent_definitions where (consent_key = 'privacy_policy' and version = 'v13') or (consent_key = 'terms_of_use' and version = 'v9') or (consent_key = 'legal_notice' and version = 'v2')) then
    raise exception 'privacy_policy v13 / terms_of_use v9 / legal_notice v2 already exist';
  end if;

  -- privacy_policy v13 from v12
  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note, highlights)
  select consent_key, 'v13', locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[
             'The controller of your personal data is Alessandra Ginsburg, independent practitioner, Chemin de Bonne-Eau 1, 3975 Crans-Montana,',
             'Privacy questions and all data requests: data@functionalps.ch. General support: support@functionalps.ch. Post: FunctionAlps, Chemin de Bonne-Eau 1, 3975 Crans-Montana,'
           ],
           array[
             'The controller of your personal data is Thomas Convent, Rue du Grand Place 2, 3963 Crans-Montana,',
             'Privacy questions, all data requests and general support: thomas@functionalps.ch. Post: FunctionAlps, Rue du Grand Place 2, 3963 Crans-Montana,'
           ])
         else pg_temp.fa_apply_edits(body_md,
           array[
             'La responsable du traitement est Alessandra Ginsburg, praticienne indépendante, Chemin de Bonne-Eau 1, 3975 Crans-Montana,',
             'traitées par la responsable du traitement',
             'Questions relatives à la protection des données et demandes concernant vos données : data@functionalps.ch. Assistance générale : support@functionalps.ch. Courrier : FunctionAlps, Chemin de Bonne-Eau 1, 3975 Crans-Montana,'
           ],
           array[
             'Le responsable du traitement est Thomas Convent, Rue du Grand Place 2, 3963 Crans-Montana,',
             'traitées par le responsable du traitement',
             'Questions relatives à la protection des données, demandes concernant vos données et assistance générale : thomas@functionalps.ch. Courrier : FunctionAlps, Rue du Grand Place 2, 3963 Crans-Montana,'
           ]) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(), 'v13 = v12 with the operator and contact changed.' || note, highlights
    from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v12' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'privacy_policy v13: expected 2 rows, got %', n; end if;

  -- terms_of_use v9 from v8
  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note, highlights)
  select consent_key, 'v9', locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[
             'by Alessandra Ginsburg, an independent practitioner established at Chemin de Bonne-Eau 1, 3975 Crans-Montana,',
             'General support: support@functionalps.ch. Privacy and data-protection requests: data@functionalps.ch.',
             'General and support: support@functionalps.ch. Privacy, data requests and anything about this agreement: data@functionalps.ch. Post: FunctionAlps, Chemin de Bonne-Eau 1, 3975 Crans-Montana,'
           ],
           array[
             'by Thomas Convent, established at Rue du Grand Place 2, 3963 Crans-Montana,',
             'General support, privacy and data-protection requests: thomas@functionalps.ch.',
             'General questions, support, privacy, data requests and anything about this agreement: thomas@functionalps.ch. Post: FunctionAlps, Rue du Grand Place 2, 3963 Crans-Montana,'
           ])
         else pg_temp.fa_apply_edits(body_md,
           array[
             'par Alessandra Ginsburg, praticienne indépendante établie Chemin de Bonne-Eau 1, 3975 Crans-Montana,',
             'Assistance générale : support@functionalps.ch. Questions relatives à la protection des données : data@functionalps.ch.',
             'Questions générales et assistance : support@functionalps.ch. Protection des données, demandes relatives à vos données et questions sur le présent accord : data@functionalps.ch. Courrier : FunctionAlps, Chemin de Bonne-Eau 1, 3975 Crans-Montana,'
           ],
           array[
             'par Thomas Convent, établi Rue du Grand Place 2, 3963 Crans-Montana,',
             'Assistance générale et questions relatives à la protection des données : thomas@functionalps.ch.',
             'Questions générales, assistance, protection des données, demandes relatives à vos données et questions sur le présent accord : thomas@functionalps.ch. Courrier : FunctionAlps, Rue du Grand Place 2, 3963 Crans-Montana,'
           ]) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(), 'v9 = v8 with the operator and contact changed.' || note, highlights
    from public.consent_definitions where consent_key = 'terms_of_use' and version = 'v8' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'terms_of_use v9: expected 2 rows, got %', n; end if;

  -- legal_notice v2 from v1
  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note, highlights)
  select consent_key, 'v2', locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[
             'by Alessandra Ginsburg, an independent practitioner.',
             '- Address: Chemin de Bonne-Eau 1, 3975 Crans-Montana,',
             '- Responsible: Thomas Convent and Alessandra Ginsburg',
             E'- General and support: support@functionalps.ch\n- Privacy and all data requests: data@functionalps.ch'
           ],
           array[
             'by Thomas Convent.',
             '- Address: Rue du Grand Place 2, 3963 Crans-Montana,',
             '- Responsible: Thomas Convent',
             '- Contact (general questions, support, privacy and all data requests): thomas@functionalps.ch'
           ])
         else pg_temp.fa_apply_edits(body_md,
           array[
             '### Exploitante',
             'par Alessandra Ginsburg, praticienne indépendante.',
             '- Adresse : Chemin de Bonne-Eau 1, 3975 Crans-Montana,',
             '- Responsables : Thomas Convent et Alessandra Ginsburg',
             E'- Questions générales et assistance : support@functionalps.ch\n- Protection des données et demandes relatives à vos données : data@functionalps.ch'
           ],
           array[
             '### Exploitant',
             'par Thomas Convent.',
             '- Adresse : Rue du Grand Place 2, 3963 Crans-Montana,',
             '- Responsable : Thomas Convent',
             '- Contact (questions générales, assistance, protection des données et demandes relatives à vos données) : thomas@functionalps.ch'
           ]) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(), 'v2 = v1 with the operator and contact changed.' || note, highlights
    from public.consent_definitions where consent_key = 'legal_notice' and version = 'v1' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'legal_notice v2: expected 2 rows, got %', n; end if;

  update public.consent_definitions set superseded_at = now() where consent_key = 'privacy_policy' and version = 'v12' and superseded_at is null;
  update public.consent_definitions set superseded_at = now() where consent_key = 'terms_of_use' and version = 'v8' and superseded_at is null;
  update public.consent_definitions set superseded_at = now() where consent_key = 'legal_notice' and version = 'v1' and superseded_at is null;
  raise notice 'privacy_policy v13 + terms_of_use v9 + legal_notice v2 current (en + fr); previous versions superseded';
end
$mig$;
drop function pg_temp.fa_apply_edits(text, text[], text[]);
