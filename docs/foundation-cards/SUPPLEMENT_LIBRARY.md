# The supplement library · app side (design 2026-11-07, built 2026-11-07)

**Status:** built, pending the first published supplement (branch `claude/functionalpas-supplement-library-r2dbph`,
the `iOS` workflow green). Files: `Models/Supplements.swift`, `Core/Library/SupplementLogic.swift` + `SupplementSample.swift`,
`Features/Library/Supplements/*`, `Route.supplement` / `Route.supplementUse`, `Tests/Core/SupplementLogicTests.swift`.
Until magnesium is published, the screens show the labelled sample (the mockup's draft wording) on `demo-` slugs only.
**Mockups:** artifact `CWHqjCHoYPsGpbibB1Mpc4` (the supplements list, the magnesium page top and bottom, "For sleep",
"For muscle cramps" (not supported), the visuals, and the CLINICAL review screen). It builds on "The library" in the
Foundation Track mockup `X4SrfHtE3Pn7UYuEvf4rjj` and on `LIBRARY_PLAN.md` (decisions of 7 November, branch
`claude/determined-brahmagupta-n20yaz`).
**Agent, review, data:** CLINICAL `clinical-dashboard/docs/wiki/features/supplement-library.md`
(the research agent, Thomas's review, migration 293, the publish rules).

## What the member gets

1. **The supplements list** (Library → Supplements): only published supplements. Each row has the visual (element tile
   or molecule), the one line, and the uses as chips. The intro is Thomas's text from the mockup.
2. **A supplement page** (magnesium first): the visual, the one line, benefits to look for (each tagged with its use and
   source number), what it does in the body (its job, where it is stored, how it is absorbed, what lowers it), the uses
   as tappable tracks with their evidence level, on the label, "Ask us first if", side effects and the upper limit, food
   first, "Goes with" (habits: Open, or + Add), the articles, the numbered sources.
3. **A page per use** ("Magnesium for sleep"): evidence first (a word and a bar, plus one sentence on what the studies
   were), benefits to look for, best form, how much, when, how long until an effect, on the label, "Ask us first if",
   "Goes with", sources.
4. **Weak evidence said plainly:** a Weak or Not-supported use stays on the page, flagged, with no dose and no how-to.

## Where the data comes from (no new RPC, no app-side table)

| What | Source | Today in the app |
|---|---|---|
| The list | `member_library_list()` rows with tag `supplement` and without `supplement-use` | rows decoded; `appearance` read for `cover_url` only |
| The list visual | `appearance.supplement_visual` on the page row | to add (`LibraryListRow`) |
| The page / a use | `member_library_get(p_slug)` → `template = supplement`, `structured.supplement_page` / `structured.supplement_use` | the RPC returns `template`, `structured`, `kicker`; `LibraryGetRow` decodes neither yet |
| Uses of a page | rows tagged `supplement-use` + `supplement-of:<page slug>` (also listed in `supplement_page.uses`) | to add (`LibraryLogic`) |
| Lock | the row's `locked` (tier) and the `supplements` veil (`member_library_access.supplements_enabled`) | already wired |
| Habits ("Goes with") | `habit_bank` ids in the payload, resolved by the bank read the app already does; "in your actions" from the member's habits | reads exist (`ActionBankView`) |
| Articles | slugs in the payload, resolved from the library bundle | exists |
| Body fallback | `body_md` (full readable version with sources) | `ReaderView` renders it |

Pages are members-only (`patient_tier_1`, like Creatine) and English. On the Foundation Track the whole library is open
(LIBRARY_PLAN decision), so leads on the track see them too.

## Build plan (after the go)

- **Models** (`Models/Supplements.swift`): `SupplementVisual` (element tiles | molecule with atoms and bonds),
  `SupplementPage`, `SupplementUse`, `EvidenceLevel` (`strong | moderate | limited | weak | notSupported`), `SourceRef`.
  Decoding is version-checked (`v == 1`); an unknown version or a missing payload falls back to `ReaderView` on
  `body_md`, so an older build never breaks on a newer page.
- **Logic** (`Core/Library/SupplementLogic.swift`, pure, tested): list = supplement and not use; group uses under
  their page; order uses by evidence; evidence label and dot count; `LibraryLogic` keeps use rows out of Foundations.
- **Views** (`Features/Library/Supplements/`): `SupplementListView`, `SupplementPageView`, `SupplementUseView`,
  `ElementTile`, `MoleculeView` (SwiftUI `Canvas` from PubChem 2D coordinates: no image, no network at reading time,
  scales with Dynamic Type), `EvidenceBadge` (word plus dots, never colour alone), `SourcesSheet`.
- **Routes:** `Route.supplement(String)` and `Route.supplementUse(String)`; `Route.read(slug)` of a `supplement` template
  lands on the supplement page.
- **States:** loading / error / empty / locked with `FALoadingState` / `FAErrorState` / `FAEmptyState` and the
  existing veil (rule 5).
- **Copy:** section headings and chrome only, through `String(localized:defaultValue:)` (English; French keys left
  untranslated, English-only decision). Every clinical word comes from the payload Thomas approved; nothing is written
  in Swift (rule 6). Doses are never formatted or computed in the app (rule 9).
- **Tests** (Swift Testing): decoding fixtures (magnesium page, a use, an unknown version), grouping and ordering,
  evidence labels, the fallback path. Each seen failing first.
- **Fixture first:** a labelled sample (`LibraryDemo`) lets the screens land and pass CI before magnesium is published.
- **CI:** the `iOS` GitHub Actions workflow on this branch; screenshots through the Showcase flags.
- When it lands: `docs/IOS_MIGRATION_MAP.md` (row F) and this page.

## Visuals by supplement

| Supplement | Visual |
|---|---|
| Magnesium | element tile: 12 · Mg · Magnesium · 24.305 |
| Creatine | molecule, PubChem CID 586 (C₄H₉N₃O₂) |
| Vitamin D | molecule: cholecalciferol (D3), from PubChem |
| Omega-3 | molecules: EPA and DHA, from PubChem |
| Protein powder | to choose with Thomas (no single molecule) |
| Electrolytes | four element tiles: Na 11, K 19, Mg 12, Cl 17 |
