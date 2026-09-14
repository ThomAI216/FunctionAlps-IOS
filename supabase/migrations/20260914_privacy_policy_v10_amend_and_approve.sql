-- privacy_policy v10 — amended for platform v2 / Phase 2 facts, then APPROVED (owner's call 2026-09-14: "Update privacy policy already").
--
-- Additive, anchor-checked insertions into the v10 DRAFT (both locales), then the approval SQL from the v10
-- migration header: v9 superseded, v10 approved + effective now. The app's WearableDisclosure.vendorNoticeVersion
-- = 10 → the vendor Connect buttons appear for every vendor the practice switches to `available`.
--   §9a  the member may delete the readings a linked account already sent when unlinking; the link/unlink/delete
--        log the member can read; readings never given to an AI service (D5).
--   §13  raw copies of a linked account's data: 30 days after unlinking, or at once on the member's deletion request.
do $mig$
declare
  en_a1 constant text := 'No aggregator or intermediary company is involved. Readings already received stay in your record under the rules in section 13.';
  en_i1 constant text := ' When you unlink, you can also choose to delete the readings that account had already sent: we then remove them from your record right away, and the raw copies we keep for traceability follow within a month. Every link, unlink and deletion is recorded in a log you can read in the app. Readings from a linked account serve only your own scores and your practitioner’s view; they are never passed to an artificial-intelligence service.';
  en_a2 constant text := '- Access credentials for linked wearable accounts — until you unlink the account, revoke it at the vendor, or delete your account; then deleted immediately.';
  en_i2 constant text := E'\n- Raw copies of what a linked wearable account sent — 30 days after you unlink it, or right away when you ask us to delete those readings.';
  fr_a1 constant text := 'Aucun agrégateur ni société intermédiaire n’intervient. Les mesures déjà reçues restent dans votre dossier selon les règles de la section 13.';
  fr_i1 constant text := ' Lorsque vous dissociez le compte, vous pouvez aussi choisir de supprimer les mesures qu’il avait déjà transmises : nous les retirons alors immédiatement de votre dossier, et les copies brutes conservées pour la traçabilité suivent dans le mois. Chaque liaison, dissociation et suppression est inscrite dans un journal que vous pouvez consulter dans l’application. Les mesures d’un compte lié ne servent qu’à vos propres scores et à la vue de votre praticienne ; elles ne sont jamais transmises à un service d’intelligence artificielle.';
  fr_a2 constant text := '- Identifiants d’accès des comptes d’objets connectés liés — jusqu’à ce que vous dissociez le compte, le révoquiez chez le fournisseur ou supprimiez votre compte ; supprimés immédiatement ensuite.';
  fr_i2 constant text := E'\n- Copies brutes de ce qu’un compte d’objet connecté lié a transmis — 30 jours après sa dissociation, ou immédiatement si vous nous demandez de supprimer ces mesures.';
  en_body text; fr_body text; c int; n int;
begin
  select body_md into en_body from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v10' and locale = 'en' and review_status = 'draft_pending_legal_review';
  select body_md into fr_body from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v10' and locale = 'fr' and review_status = 'draft_pending_legal_review';
  if en_body is null or fr_body is null then raise exception 'privacy_policy v10 draft not found for both locales (already approved?)'; end if;
  foreach c in array array[
    (length(en_body) - length(replace(en_body, en_a1, ''))) / length(en_a1), (length(en_body) - length(replace(en_body, en_a2, ''))) / length(en_a2),
    (length(fr_body) - length(replace(fr_body, fr_a1, ''))) / length(fr_a1), (length(fr_body) - length(replace(fr_body, fr_a2, ''))) / length(fr_a2)
  ] loop
    if c <> 1 then raise exception 'privacy_policy v10 amend: an anchor does not occur exactly once (count %)', c; end if;
  end loop;
  if position(en_i1 in en_body) > 0 or position(fr_i1 in fr_body) > 0 then raise exception 'privacy_policy v10 amend already applied'; end if;
  en_body := replace(en_body, en_a1, en_a1 || en_i1); en_body := replace(en_body, en_a2, en_a2 || en_i2);
  fr_body := replace(fr_body, fr_a1, fr_a1 || fr_i1); fr_body := replace(fr_body, fr_a2, fr_a2 || fr_i2);
  update public.consent_definitions set body_md = en_body where consent_key = 'privacy_policy' and version = 'v10' and locale = 'en';
  update public.consent_definitions set body_md = fr_body where consent_key = 'privacy_policy' and version = 'v10' and locale = 'fr';

  -- Approval (the v10 header's SQL): v9 superseded, v10 approved and effective now.
  update public.consent_definitions set superseded_at = now() where consent_key = 'privacy_policy' and version = 'v9' and superseded_at is null;
  update public.consent_definitions
     set review_status = 'approved', approved_by = 'Thomas Convent — operator, FunctionAlps', approved_at = now(), effective_from = now(),
         approval_note = coalesce(approval_note, '') || ' Amended 2026-09-14 (platform v2: delete-on-unlink, the member-readable log, 30-day raw retention, no AI use) and approved by the operator on 2026-09-14 (qualified legal review deferred, as for v7–v9).'
   where consent_key = 'privacy_policy' and version = 'v10';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'privacy_policy v10 approve: expected 2 rows, got %', n; end if;
  raise notice 'privacy_policy v10 amended + approved (en + fr); v9 superseded';
end
$mig$;
