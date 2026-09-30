# App backgrounds (photo walls)

The owner's full-size originals (941 × 1672 PNG, uploaded 2026-09-30). Eleven were uploaded; the owner
kept these four (the other seven were removed from the repo, recoverable from git history before this change). They are kept here, outside
`FunctionAlps/Sources`, so they never ship in the app bundle. The app ships JPEG copies
(quality 88, ~150 KB each) as `FunctionAlps/Sources/Resources/Media/<name>.jpg`, listed in
`FAPhotoWalls.all` (`DesignSystem/Components/SpotlightWall.swift`).

Settings → Appearance offers each photo below (the gradient walls Sage, Cream, Honey and Mist are retired).
While the owner tests, the first launch draws one photo at random and keeps it until changed in
Settings; once the owner names the default, `FAWalls.defaultKey` becomes that photo.

| Name | Picker label | Uploaded as |
|---|---|---|
| bg-blue-1 | Blue 1 | ChatGPT Image Sep 30, 2026, 09_01_22 AM.png |
| bg-blue-3 | Blue 3 | ChatGPT Image Sep 30, 2026, 09_01_53 AM.png |
| bg-sand-1 | Sand 1 | ChatGPT Image Sep 30, 2026, 09_02_09 AM.png |
| bg-sand-4 | Sand 4 | ChatGPT Image Sep 30, 2026, 09_02_35 AM-1.png |

To add or drop one: put the PNG here, export the JPEG next to the others in `Resources/Media`,
and add or remove its row in `FAPhotoWalls.all` (the `tint` is the image's average colour).
