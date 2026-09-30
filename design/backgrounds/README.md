# App backgrounds (photo walls)

The owner's full-size originals (941 × 1672 PNG, uploaded 2026-09-30). They are kept here, outside
`FunctionAlps/Sources`, so they never ship in the app bundle. The app ships JPEG copies
(quality 88, ~150 KB each) as `FunctionAlps/Sources/Resources/Media/<name>.jpg`, listed in
`FAPhotoWalls.all` (`DesignSystem/Components/SpotlightWall.swift`).

Settings → Appearance offers **Random** (the default: a new photo each launch), each photo below,
and the four gradient walls (Sage, Cream, Honey, Mist).

| Name | Picker label | Uploaded as |
|---|---|---|
| bg-blue-1 | Blue 1 | ChatGPT Image Sep 30, 2026, 09_01_22 AM.png |
| bg-blue-2 | Blue 2 | ChatGPT Image Sep 30, 2026, 09_01_50 AM.png |
| bg-blue-3 | Blue 3 | ChatGPT Image Sep 30, 2026, 09_01_53 AM.png |
| bg-blue-4 | Blue 4 | ChatGPT Image Sep 30, 2026, 09_02_00 AM.png |
| bg-sand-1 | Sand 1 | ChatGPT Image Sep 30, 2026, 09_02_09 AM.png |
| bg-sand-2 | Sand 2 | ChatGPT Image Sep 30, 2026, 09_02_19 AM.png |
| bg-sand-3 | Sand 3 | ChatGPT Image Sep 30, 2026, 09_02_22 AM.png |
| bg-sand-4 | Sand 4 | ChatGPT Image Sep 30, 2026, 09_02_35 AM-1.png |
| bg-sand-5 | Sand 5 | ChatGPT Image Sep 30, 2026, 09_02_36 AM-2.png |
| bg-sand-6 | Sand 6 | ChatGPT Image Sep 30, 2026, 09_02_37 AM-3.png |
| bg-sand-7 | Sand 7 | ChatGPT Image Sep 30, 2026, 09_02_37 AM-4.png |

To add or drop one: put the PNG here, export the JPEG next to the others in `Resources/Media`,
and add or remove its row in `FAPhotoWalls.all` (the `tint` is the image's average colour).
