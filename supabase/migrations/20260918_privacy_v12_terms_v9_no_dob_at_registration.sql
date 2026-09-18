-- privacy_policy v12 + terms_of_use v9 — the app no longer asks for a date of birth.
--
-- NOT APPLIED. This file is a draft awaiting the operator's approval, because inserting it asserts
-- `approved_by = 'Thomas Convent — operator, FunctionAlps'` — a signature on a legal document — and
-- because publishing it makes every member re-accept (the version moves, so `accepted` flips to false
-- and the consent gate reopens on the next launch).
--
-- WHY: the age screen was removed on 2026-09-18 (owner's call). Both documents still promise a
-- collection we no longer perform. The 18+ REQUIREMENT itself is untouched and was already stated in
-- both languages — Terms §3 "You may use it if you are 18 or older" / "si vous avez 18 ans révolus".
-- What changes is only HOW it is established: by accepting the Terms rather than by a date we ask for.
--
-- Terms §3, both locales: the paragraph describing the registration question.
-- Privacy §4, both locales: "date of birth" drops out of the ACCOUNT-DATA bullet (what we collect from
--   you), while the "From your FunctionAlps record" bullet keeps it and stays true — the practice may
--   hold a date of birth and the app still prefills your baseline age from it.
-- Privacy §(children), both locales: the sentence that said we ask for it to verify age.
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
declare n int;
begin
  if exists (select 1 from public.consent_definitions where (consent_key = 'privacy_policy' and version = 'v12') or (consent_key = 'terms_of_use' and version = 'v9')) then
    raise exception 'privacy_policy v12 / terms_of_use v9 already exist';
  end if;

  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note)
  select consent_key, 'v12', locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[
             E'- Account data — your email address, first and last name, telephone number, date of birth, and an encrypted password',
             E'We do not knowingly collect data from anyone under 18, and we ask for your date of birth at registration to confirm this. Where we cannot confirm it, no consent record can be created and the service does not open.'
           ],
           array[
             E'- Account data — your email address, first and last name, telephone number, and an encrypted password',
             E'We do not knowingly collect data from anyone under 18. You declare that you are 18 or older by accepting the Terms of Service, which you must do before the service opens; we do not ask you for your date of birth. If we learn that an account belongs to someone under 18 we delete it — write to data@functionalps.ch.'
           ])
                     else pg_temp.fa_apply_edits(body_md,
           array[
             E'- Données de compte — votre adresse électronique, vos nom et prénom, votre numéro de téléphone, votre date de naissance et un mot de passe chiffré',
             E'Nous ne collectons pas sciemment de données concernant une personne de moins de 18 ans, et nous demandons votre date de naissance à l’inscription pour le vérifier. Lorsque nous ne pouvons pas le confirmer, aucune trace de consentement ne peut être créée et le service ne s’ouvre pas.'
           ],
           array[
             E'- Données de compte — votre adresse électronique, vos nom et prénom, votre numéro de téléphone et un mot de passe chiffré',
             E'Nous ne collectons pas sciemment de données concernant une personne de moins de 18 ans. Vous déclarez avoir 18 ans révolus en acceptant les conditions d’utilisation, ce que vous devez faire avant l’ouverture du service ; nous ne vous demandons pas votre date de naissance. Si nous apprenons qu’un compte appartient à une personne de moins de 18 ans, nous le supprimons — écrivez à data@functionalps.ch.'
           ]) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(),
         'v12 = v11 with the date of birth removed from account data and from the age-verification sentence; the app stopped asking for it on 2026-09-18. The record-prefill bullet is unchanged and still true. Operator''s call 2026-09-18 (qualified legal review still to come).'
    from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v11' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'privacy_policy v12: expected 2 rows inserted, got %', n; end if;

  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note)
  select consent_key, 'v9', locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md,
           array[E'We ask for your date of birth when you register, and we use it only to confirm you are old enough and to make our estimates accurate for your age. If the answer is that you are under 18, we record only that the check refused — never your date of birth.'],
           array[E'We do not ask for your date of birth. By accepting these Terms you declare that you are 18 or older. If your practitioner has recorded a date of birth on your FunctionAlps record, the app may use your age from it so that our estimates fit you — it never asks you to enter it again.'])
                     else pg_temp.fa_apply_edits(body_md,
           array[E'Nous vous demandons votre date de naissance lors de l’inscription, uniquement pour vérifier que vous avez l’âge requis et pour que nos estimations soient adaptées à votre âge. Si la réponse est que vous avez moins de 18 ans, nous n’enregistrons que le fait que la vérification a refusé — jamais votre date de naissance.'],
           array[E'Nous ne vous demandons pas votre date de naissance. En acceptant les présentes conditions, vous déclarez avoir 18 ans révolus. Si votre praticienne a inscrit une date de naissance à votre dossier FunctionAlps, l’application peut en tirer votre âge pour que nos estimations vous correspondent — elle ne vous demande jamais de la saisir à nouveau.']) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(),
         'v9 = v8 with §3 restated: the 18+ declaration is made by accepting these Terms, not by a date of birth we ask for. The requirement itself is unchanged. Operator''s call 2026-09-18 (qualified legal review still to come).'
    from public.consent_definitions where consent_key = 'terms_of_use' and version = 'v8' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'terms_of_use v9: expected 2 rows inserted, got %', n; end if;

  update public.consent_definitions set superseded_at = now() where consent_key = 'privacy_policy' and version = 'v11' and superseded_at is null;
  update public.consent_definitions set superseded_at = now() where consent_key = 'terms_of_use' and version = 'v8' and superseded_at is null;
  raise notice 'privacy_policy v12 + terms_of_use v9 current (en + fr); v11 / v8 superseded';
end
$mig$;
drop function pg_temp.fa_apply_edits(text, text[], text[]);
