-- privacy_policy v10 — linked wearable accounts (Oura, WHOOP, Polar, Garmin, Withings, Suunto, Google/Fitbit).
--
-- WHY: the Devices screen can link a member's account at a wearable vendor through OAuth; we then hold
-- an access credential and pull readings from the vendor's service. That is a new data source AND a
-- stored credential — v9 (Apple Health on the phone only) does not describe it. The app hides every
-- vendor Connect button until the CURRENT APPROVED notice is v10+ (`WearableDisclosure.vendorNoticeVersion`).
--
-- HOW: v10 = the live v9 rows with six anchor-checked insertions per locale (§1, §4, §5, §6, §9a, §13),
-- as v9 was built from v8. STATE: draft_pending_legal_review, v9 NOT superseded; approval SQL:
--   update consent_definitions set superseded_at = now() where consent_key = 'privacy_policy' and version = 'v9' and superseded_at is null;
--   update consent_definitions set review_status = 'approved', approved_by = '<operator>', approved_at = now(), effective_from = now()
--    where consent_key = 'privacy_policy' and version = 'v10';

do $mig$
declare
  v9_en text; v9_fr text; v10_en text; v10_fr text; n int; c int;
  en_a1 constant text := '- If you connect Apple Health on your iPhone, we read the readings you allow — steps, sleep, heart rate and similar, including what your Apple Watch recorded — and nothing is written back. That is described in section 9a.';
  en_i1 constant text := E'\n- If you link a wearable account (Oura, WHOOP, Polar, Garmin, Withings, Suunto or Google Fitbit), we receive the readings that service holds about you, under an access credential you can revoke at any time. That too is described in section 9a.';
  en_a2 constant text := 'Each reading carries the day or time it was recorded and the device category it came from. See section 9a.';
  en_i2 constant text := E' The same categories reach us from a wearable account you link, plus what only that service computes: heart-rate variability, recovery or readiness scores, stress, skin-temperature deviation, body composition, blood pressure and, where the service provides it, cycle information.';
  en_a3 constant text := '- From Apple Health — only if you choose to connect it, and then only the categories you allow in Apple’s permission sheet. The app reads them on your phone; Apple sends us nothing and receives nothing from us.';
  en_i3 constant text := E'\n- From a wearable account you link — only if you choose to link it, and then only what you authorise on the vendor’s own consent page. The vendor (Oura, WHOOP, Polar, Garmin, Withings, Suunto or Google) sends the readings to us directly; no intermediary service sits between us and the vendor.';
  en_a4 constant text := '- To bring in the readings from Apple Health that you choose to share, and to read them alongside what you log — wearable data. Basis: that same explicit consent to health-data processing, together with your separate choice to connect, which you can undo at any time (section 9a).';
  en_i4 constant text := E'\n- To keep the access credential a linked wearable account gives us, so that new readings keep arriving without asking you again — the credential itself. Basis: performance of our contract with you and your separate choice to link, which you can undo at any time; the credential is deleted when you unlink.';
  en_a5 constant text := 'You can stop the connection at any time on the Devices screen in the app; the phone then stops sending. You can also withdraw the app’s permission for any category, or for everything, in Settings → Health → Data Access & Devices on your iPhone. Readings already sent stay in your record under the rules in section 13 and are deleted with everything else when you delete your account.';
  en_i5 constant text := E'\n\n**Linked wearable accounts.** On the Devices screen you can also link an account you hold with Oura, WHOOP, Polar, Garmin, Withings, Suunto or Google (Fitbit). You are sent to that vendor’s own sign-in and consent page; what you allow there is what we receive. The vendor then sends us your readings — sleep, heart rate and heart-rate variability, activity and workouts, body measurements and, where the service computes them, its scores — either as they arrive or through a daily pull, and we store them with the day they belong to and the vendor they came from. To do this we keep an access credential for your vendor account, encrypted, on our servers; nobody reads it, it is used only to fetch your readings, and it is deleted the moment you unlink the account in the app, revoke it at the vendor, or delete your account. The vendor remains responsible for its own service under its own privacy policy; we do not send it anything about you. No aggregator or intermediary company is involved. Readings already received stay in your record under the rules in section 13.';
  en_a6 constant text := '- Wearable readings — while your account is active, like the rest of your record; the raw submissions from your phone are kept alongside them so that a value can always be traced back to what the phone sent.';
  en_i6 constant text := E'\n- Access credentials for linked wearable accounts — until you unlink the account, revoke it at the vendor, or delete your account; then deleted immediately.';
  fr_a1 constant text := '- Si vous connectez Apple Santé sur votre iPhone, nous lisons les mesures que vous autorisez — pas, sommeil, fréquence cardiaque et données similaires, y compris ce que votre Apple Watch a enregistré — et rien n’y est écrit en retour. Voir la section 9a.';
  fr_i1 constant text := E'\n- Si vous liez un compte d’objet connecté (Oura, WHOOP, Polar, Garmin, Withings, Suunto ou Google Fitbit), nous recevons les mesures que ce service détient à votre sujet, au moyen d’un identifiant d’accès que vous pouvez révoquer à tout moment. Voir aussi la section 9a.';
  fr_a2 constant text := 'Chaque mesure porte le jour ou l’heure de son enregistrement et la catégorie d’appareil dont elle provient. Voir la section 9a.';
  fr_i2 constant text := E' Les mêmes catégories nous parviennent d’un compte d’objet connecté que vous liez, ainsi que ce que seul ce service calcule : variabilité de la fréquence cardiaque, scores de récupération ou de readiness, stress, écart de température cutanée, composition corporelle, tension artérielle et, lorsque le service le fournit, des informations sur le cycle.';
  fr_a3 constant text := '- D’Apple Santé — uniquement si vous choisissez de le connecter, et alors seulement pour les catégories que vous autorisez dans la fenêtre d’autorisation d’Apple. L’application les lit sur votre téléphone ; Apple ne nous transmet rien et ne reçoit rien de nous.';
  fr_i3 constant text := E'\n- D’un compte d’objet connecté que vous liez — uniquement si vous choisissez de le lier, et alors seulement ce que vous autorisez sur la page de consentement du fournisseur. Le fournisseur (Oura, WHOOP, Polar, Garmin, Withings, Suunto ou Google) nous transmet les mesures directement ; aucun service intermédiaire ne s’interpose entre lui et nous.';
  fr_a4 constant text := '- Importer les mesures d’Apple Santé que vous choisissez de partager, et les lire aux côtés de vos saisies — données d’objets connectés. Base : le même consentement explicite au traitement des données de santé, joint à votre choix distinct de connecter l’appareil, que vous pouvez annuler à tout moment (section 9a).';
  fr_i4 constant text := E'\n- Conserver l’identifiant d’accès qu’un compte d’objet connecté lié nous confère, afin que les nouvelles mesures continuent d’arriver sans vous solliciter à nouveau — l’identifiant lui-même. Base : exécution de notre contrat avec vous et votre choix distinct de lier le compte, que vous pouvez annuler à tout moment ; l’identifiant est supprimé dès que vous dissociez le compte.';
  fr_a5 constant text := 'Vous pouvez interrompre la connexion à tout moment depuis l’écran Appareils de l’application ; le téléphone cesse alors d’envoyer. Vous pouvez aussi retirer l’autorisation de l’application pour une catégorie, ou pour l’ensemble, dans Réglages → Santé → Accès aux données et appareils sur votre iPhone. Les mesures déjà transmises restent dans votre dossier selon les règles de la section 13 et sont supprimées avec le reste lorsque vous supprimez votre compte.';
  fr_i5 constant text := E'\n\n**Comptes d’objets connectés liés.** Depuis l’écran Appareils, vous pouvez aussi lier un compte que vous détenez chez Oura, WHOOP, Polar, Garmin, Withings, Suunto ou Google (Fitbit). Vous êtes dirigé·e vers la page de connexion et de consentement du fournisseur ; ce que vous y autorisez est ce que nous recevons. Le fournisseur nous transmet ensuite vos mesures — sommeil, fréquence cardiaque et variabilité de la fréquence cardiaque, activité et séances, mesures corporelles et, lorsque le service les calcule, ses scores — au fil de leur arrivée ou par une récupération quotidienne, et nous les conservons avec le jour auquel elles se rapportent et le fournisseur dont elles proviennent. Pour cela, nous conservons sur nos serveurs, chiffré, un identifiant d’accès à votre compte chez le fournisseur ; personne ne le lit, il ne sert qu’à récupérer vos mesures, et il est supprimé dès que vous dissociez le compte dans l’application, le révoquez chez le fournisseur ou supprimez votre compte. Le fournisseur reste responsable de son propre service selon sa propre politique de confidentialité ; nous ne lui transmettons rien à votre sujet. Aucun agrégateur ni société intermédiaire n’intervient. Les mesures déjà reçues restent dans votre dossier selon les règles de la section 13.';
  fr_a6 constant text := '- Mesures d’objets connectés — tant que votre compte est actif, comme le reste de votre dossier ; les envois bruts de votre téléphone sont conservés avec elles afin qu’une valeur puisse toujours être rattachée à ce que le téléphone a transmis.';
  fr_i6 constant text := E'\n- Identifiants d’accès des comptes d’objets connectés liés — jusqu’à ce que vous dissociez le compte, le révoquiez chez le fournisseur ou supprimiez votre compte ; supprimés immédiatement ensuite.';
begin
  if exists (select 1 from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v10') then
    raise notice 'privacy_policy v10 already present'; return;
  end if;
  select body_md into v9_en from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v9' and locale = 'en' and superseded_at is null and review_status = 'approved';
  select body_md into v9_fr from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v9' and locale = 'fr' and superseded_at is null and review_status = 'approved';
  if v9_en is null or v9_fr is null then raise exception 'privacy_policy v9 (approved, current) not found for both locales'; end if;
  foreach c in array array[
    (length(v9_en) - length(replace(v9_en, en_a1, ''))) / length(en_a1), (length(v9_en) - length(replace(v9_en, en_a2, ''))) / length(en_a2),
    (length(v9_en) - length(replace(v9_en, en_a3, ''))) / length(en_a3), (length(v9_en) - length(replace(v9_en, en_a4, ''))) / length(en_a4),
    (length(v9_en) - length(replace(v9_en, en_a5, ''))) / length(en_a5), (length(v9_en) - length(replace(v9_en, en_a6, ''))) / length(en_a6),
    (length(v9_fr) - length(replace(v9_fr, fr_a1, ''))) / length(fr_a1), (length(v9_fr) - length(replace(v9_fr, fr_a2, ''))) / length(fr_a2),
    (length(v9_fr) - length(replace(v9_fr, fr_a3, ''))) / length(fr_a3), (length(v9_fr) - length(replace(v9_fr, fr_a4, ''))) / length(fr_a4),
    (length(v9_fr) - length(replace(v9_fr, fr_a5, ''))) / length(fr_a5), (length(v9_fr) - length(replace(v9_fr, fr_a6, ''))) / length(fr_a6)
  ] loop
    if c <> 1 then raise exception 'privacy_policy v10: an anchor does not occur exactly once in v9 (count %)', c; end if;
  end loop;
  v10_en := v9_en;
  v10_en := replace(v10_en, en_a1, en_a1 || en_i1); v10_en := replace(v10_en, en_a2, en_a2 || en_i2); v10_en := replace(v10_en, en_a3, en_a3 || en_i3);
  v10_en := replace(v10_en, en_a4, en_a4 || en_i4); v10_en := replace(v10_en, en_a5, en_a5 || en_i5); v10_en := replace(v10_en, en_a6, en_a6 || en_i6);
  v10_fr := v9_fr;
  v10_fr := replace(v10_fr, fr_a1, fr_a1 || fr_i1); v10_fr := replace(v10_fr, fr_a2, fr_a2 || fr_i2); v10_fr := replace(v10_fr, fr_a3, fr_a3 || fr_i3);
  v10_fr := replace(v10_fr, fr_a4, fr_a4 || fr_i4); v10_fr := replace(v10_fr, fr_a5, fr_a5 || fr_i5); v10_fr := replace(v10_fr, fr_a6, fr_a6 || fr_i6);
  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approval_note)
  select consent_key, 'v10', locale, title, summary, case locale when 'en' then v10_en else v10_fr end, required, display_order, legal_basis, doc_kind, basis,
         'draft_pending_legal_review', 'v10 = v9 + linked wearable accounts (Oura, WHOOP, Polar, Garmin, Withings, Suunto, Google Fitbit): §1, §4, §5, §6, §9a, §13. Drafted 2026-09-04; awaiting the operator''s approval.'
    from public.consent_definitions where consent_key = 'privacy_policy' and version = 'v9' and superseded_at is null and review_status = 'approved';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'privacy_policy v10: expected 2 rows inserted, got %', n; end if;
  raise notice 'privacy_policy v10 drafted (en + fr), v9 still current';
end
$mig$;
