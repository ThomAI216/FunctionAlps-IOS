# Action cards from Huberman's *Protocols*

61 app action cards written from the protocols Thomas approved for clients (2026-10-03), in the
CLINICAL import format (`functionalps/action-cards/import-v1`, guide §5.2), English and French.

| Lot | Files | Cards | State |
|---|---|---|---|
| B: new cards | `lot-b-*.json` | 50 | Written to `habit_bank` as **drafts** (`active=false`) on 2026-10-05, through the importer's own row builder. Visible in CLINICAL → Action cards; a lead clinician reviews and publishes. |
| A: richer content for existing live cards | `lot-a-*.json` | 11 | **Not applied.** A change here is live for every member at once, so a lead applies them in CLINICAL → Action cards → Import JSON, ticking each card. |

Source of each card: its `_note_clinicien` names the protocol ids (`huberman:P…`) and every choice the
reviewer should check (days chosen, numbers, conversions, softer wording proposed for live texts).

Not turned into cards: supplements (forbidden in shared cards, guide §3.5), the 12 screen-first
protocols, and the protocols listed in `skipped.md` (formulas, diets, travel, device-based light).
The review that shaped the final set (duplicates merged, safety steps added) is in
`changelog-review.md`.

Rules worth knowing before publishing:
- Cards marked "members can add it themselves = off" start with "Only if your practice has cleared you
  for this." The daily focus can still suggest any published card, whatever that flag says.
- Numbers come from the book, except where the cited study corrected it (the squat break) and the
  °C in brackets next to the book's °F (derived, flagged in the note).
