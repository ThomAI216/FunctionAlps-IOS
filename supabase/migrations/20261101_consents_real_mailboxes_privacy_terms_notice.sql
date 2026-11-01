-- privacy_policy + terms_of_use + legal_notice (next versions) — only real mailboxes.
--
-- NOT APPLIED. A draft awaiting the operator's approval: applying it stamps
-- approved_by = 'Thomas Convent — operator, FunctionAlps' (a signature on legal documents), and
-- terms_of_use is doc_kind = 'consent', so every member re-accepts on next launch.
--
-- WHY: on 2026-11-01 the operator confirmed that only five mailboxes exist: no-reply@, data@,
-- app-contact@, thomas@, alex@ (@functionalps.ch). support@functionalps.ch does not exist, yet the
-- current Privacy Policy, Terms and Legal Notice send members there for general questions,
-- complaints and compromised accounts. Mail to it is lost.
--
-- What changes, en + fr, and NOTHING else (the address only, wording untouched):
--   general questions / support / complaints    support@ -> app-contact@
--   compromised account / unauthorised access   support@ -> data@   (a security and data matter)
--   privacy_policy  §contact (general support) + §security (compromised account)
--   terms_of_use    §account (unauthorised access), §complaints (tell us first), §contact x2
--   legal_notice    the "general and support" line
--
-- Builds on whichever version is current and approved, and takes the next number, so it is
-- independent of 20260918_privacy_v12_terms_v9_no_dob_at_registration.sql (still a draft; its
-- anchors are untouched here). If both are approved, apply them together so members re-accept once.
-- Every anchor must occur exactly once in its body, and the result must hold no dead address, or
-- the whole migration raises and nothing is written.
--
-- The pg_temp helpers are left to vanish with the session: the Supabase MCP holds any statement
-- that removes an object for a human to confirm (see the CLINICAL lessons index, 2026-10-02).
create or replace function pg_temp.fa_apply_edits(body text, anchors text[], replacements text[]) returns text language plpgsql as $f$
declare i int; c int;
begin
  for i in 1 .. array_length(anchors, 1) loop
    c := (length(body) - length(replace(body, anchors[i], ''))) / length(anchors[i]);
    if c <> 1 then raise exception 'anchor % occurs % times: %', i, c, left(anchors[i], 60); end if;
    body := replace(body, anchors[i], replacements[i]);
  end loop;
  if body ~* '(^|[^a-z0-9.-])(support|contact|dpo|info|hello|admin)@functionalps' then
    raise exception 'a dead address survives the edits: %', substring(body from '(?i)[a-z0-9.-]*(support|contact|dpo|info|hello|admin)@functionalps\.[a-z]+');
  end if;
  return body;
end $f$;

create or replace function pg_temp.fa_next_version(p_key text, en_a text[], en_r text[], fr_a text[], fr_r text[], p_note text) returns text language plpgsql as $f$
declare v_from text; v_to text; n int;
begin
  select version into v_from from public.consent_definitions
   where consent_key = p_key and superseded_at is null and review_status = 'approved' and locale = 'en';
  if v_from is null then raise exception 'no current approved %', p_key; end if;
  if (select count(*) from public.consent_definitions where consent_key = p_key and version = v_from and superseded_at is null) <> 2 then
    raise exception '% %: expected exactly en + fr current rows', p_key, v_from;
  end if;
  v_to := 'v' || (substring(v_from from 2)::int + 1);
  if exists (select 1 from public.consent_definitions where consent_key = p_key and version = v_to) then
    raise exception '% % already exists', p_key, v_to;
  end if;

  insert into public.consent_definitions (consent_key, version, locale, title, summary, body_md, required, display_order, legal_basis, doc_kind, basis, review_status, approved_by, approved_at, effective_from, approval_note, highlights)
  select consent_key, v_to, locale, title, summary,
         case locale when 'en' then pg_temp.fa_apply_edits(body_md, en_a, en_r)
                     when 'fr' then pg_temp.fa_apply_edits(body_md, fr_a, fr_r) end,
         required, display_order, legal_basis, doc_kind, basis,
         'approved', 'Thomas Convent — operator, FunctionAlps', now(), now(),
         v_to || ' = ' || v_from || ' ' || p_note,
         highlights
    from public.consent_definitions where consent_key = p_key and version = v_from and superseded_at is null;
  get diagnostics n = row_count;
  if n <> 2 then raise exception '% %: expected 2 rows inserted, got %', p_key, v_to, n; end if;

  update public.consent_definitions set superseded_at = now()
   where consent_key = p_key and version = v_from and superseded_at is null;
  return p_key || ' ' || v_from || ' -> ' || v_to;
end $f$;

do $mig$
declare note text := 'with support@functionalps.ch (which does not exist) replaced: general questions and complaints -> app-contact@functionalps.ch, compromised account -> data@functionalps.ch. Address only, wording unchanged. Operator''s call 2026-11-01.';
begin
  raise notice '%', pg_temp.fa_next_version('privacy_policy',
    array['General support: support@functionalps.ch.',
          'compromised, contact support@functionalps.ch immediately.'],
    array['General support: app-contact@functionalps.ch.',
          'compromised, contact data@functionalps.ch immediately.'],
    array['Assistance générale : support@functionalps.ch.',
          'écrivez immédiatement à support@functionalps.ch.'],
    array['Assistance générale : app-contact@functionalps.ch.',
          'écrivez immédiatement à data@functionalps.ch.'],
    note);

  raise notice '%', pg_temp.fa_next_version('terms_of_use',
    array['General and support: support@functionalps.ch.',
          'write to support@functionalps.ch describing the problem',
          'Tell us at support@functionalps.ch as soon as you suspect unauthorised access',
          'General support: support@functionalps.ch.'],
    array['General and support: app-contact@functionalps.ch.',
          'write to app-contact@functionalps.ch describing the problem',
          'Tell us at data@functionalps.ch as soon as you suspect unauthorised access',
          'General support: app-contact@functionalps.ch.'],
    array['Questions générales et assistance : support@functionalps.ch.',
          'écrivez à support@functionalps.ch en décrivant le problème',
          'Informez-nous à support@functionalps.ch dès que vous soupçonnez',
          'Assistance générale : support@functionalps.ch.'],
    array['Questions générales et assistance : app-contact@functionalps.ch.',
          'écrivez à app-contact@functionalps.ch en décrivant le problème',
          'Informez-nous à data@functionalps.ch dès que vous soupçonnez',
          'Assistance générale : app-contact@functionalps.ch.'],
    note);

  raise notice '%', pg_temp.fa_next_version('legal_notice',
    array['- General and support: support@functionalps.ch'],
    array['- General and support: app-contact@functionalps.ch'],
    array['- Questions générales et assistance : support@functionalps.ch'],
    array['- Questions générales et assistance : app-contact@functionalps.ch'],
    note);
end
$mig$;
