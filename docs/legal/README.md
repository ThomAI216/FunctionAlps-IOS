# Member legal texts

The binding text of each member-facing legal document lives in CM OS, table
`consent_definitions` (one row per key, version and locale, with a generated
`content_hash`). This folder is the **reviewable copy**: the text is edited here and
then published to the database as a new version. The database copy is never edited
in place, because a member's acceptance points at the exact text they read.

| Path | What it is |
|---|---|
| `texts/<key>.<locale>.md` | The body of each document, exactly as it will be stored |
| `tools/dedash.py`, `tools/build_revised.py` | The rules used to remove em dashes (2026-11-09) |
| `tools/build_migration.py` | Generates the SQL that publishes `texts/` as version N+1 |
| `pending/*.sql` | Generated SQL that has **not** been applied yet |
| `EXPERT_BRIEF_2026-11.md` | The brief for the legal review of the 2026-11 revision (French) |
| `EU_BRUSSELS_ANALYSIS_2026-11.md` | EU-level retention rules, and what a Brussels company would change |

## The 2026-11-09 revision

The history of this folder tells the story, one commit per step:

1. a snapshot of the live texts (terms v9, privacy v13, AI notice v8, health consent v7,
   analytics v3, marketing v3, medical documents sharing v2);
2. all em dashes removed, with the wording unchanged;
3. the medical-device and CE clause, the step-by-step OpenAI section (privacy 8b), the
   corrected nutrient source, and thomas@ as the contact;
4. exact retention periods.

Use `git diff 0d57c02 -- docs/legal/texts` for the whole change, or `git log -p` step by step.

## Publishing (only after the expert review and the preconditions in the brief)

```bash
python3 docs/legal/tools/build_migration.py "<approval note>" > docs/legal/pending/<date>_legal_texts_revision.sql
```

Dry-run it in `BEGIN … ROLLBACK`, then apply it. It checks that each current version is
the approved en + fr pair it expects, inserts version N+1, and supersedes the old one.
It refuses to run twice.

**Effect on members:** `terms_of_use`, `health_data_processing`, `usage_analytics` and
`marketing_comms` are `doc_kind = 'consent'`. Bumping them asks every member to accept
again on their next visit. The analytics and marketing bumps only remove one dash each,
so drop them from `DOCS` in the generator if a re-prompt is not worth it.
