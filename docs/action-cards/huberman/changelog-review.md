# Fixes applied to hcards/final/ (review.md + lead decisions)

The set went from 67 cards to 61 (lot A 11, lot B 50). The validator reports `{"new":50,"update_draft":0,"update_published":11,"invalid":0,"duplicate_in_file":0}`, with no ERROR and no warning.

## Cards removed (decisions 2 and 4)
| Removed | Kept, and what it took over |
|---|---|
| #19 A three-minute squat break | #17 Walk five minutes every half hour. New final step 7 (EN+FR): "If walking is not possible: in the study behind this card, a 3-minute bout of squats every 45 minutes worked as well as 3-minute walking breaks." The note says the 3 min is the cited paper's figure (doi 10.1111/sms.14628), used under the owner's rule "use the paper's figure", and that the book says "ten air squats". |
| #27 Eight 30-second sprints | #25 Hard intervals already carries "never the day after a hard leg session to failure" (now step 2). The note offers the 8 × 30/30 format as a prescription alternative. |
| #35 Five minutes of breath before getting up | #36 Ten focused breaths on waking. Step 6 adds "keep the habit on stressful days too". The why adds "the first days can feel more restless than calm". P049 is added to the note. |
| #50 Starch and fruit after a hard session | #47 A proper meal after training. Step 4 adds "after a long, hard session, include a piece of fruit as well" (P057). The fat-per-serving and the light-day starch rules are not carried over. |
| #56 Deep rest after learning, ten minutes | #54 (renamed, see below). New step 7: "After a study or practice session is a good moment too — and give yourself a full night's sleep that evening." P091 is added to the note. |
| #67 Wind down after a late workout | #64 Hard workouts end 3–4 hours before bed. Step 3 gets #67's light-headed safety line. P024 is added to the note. |

Lot B `sort_order` is renumbered 100, 110, … per pillar.

## Decision 1: member_can_add = false (12 cards)
Step 1 (EN/FR) is now "Only if your practice has cleared you for this." / « Seulement si votre cabinet vous l’a conseillé. », and the other steps are renumbered. Each note adds that the daily focus can surface any published card regardless of member_can_add. The 12 cards: the three strength sessions, Long easy cardio, Steady hard cardio, Hard intervals, Ten-minute mobility, Cold shower, Brisk breathing, Midday sun, Short nap and No alcohol.

Some cards needed a merge to stay at 7 steps or fewer:
- **Hard intervals**: the "truly hard / take the full rest" step is merged into the 30 s / 60 s step.
- **Mobility**: "keep painless, progress slowly" and "if it hurts, stop" are now one step.
- **Nap**: "snooze once at most" and "keep to ~20 min, never > 90" are now one step.
- **Strength ×3**: the whole-body warm-up and the warm-up sets are now one step. Rest and progression are one step. Logging and the stop/skip/60-min safety line are one step.
- **Cold shower**: rewritten into 7 steps (see below).

## Lot A (decision 5: conservative)
- **Live descriptions restored verbatim** (Annex A.7) on #2 Evening walk, #7 Same bedtime, #8 No caffeine, #9 Screens off, #10 Dim the lights and #11 Morning light. All 11 lot A cards now match A.7 for the description, the easy texts and the further titles. This was checked by script.
- **Promise-bearing live lines** are kept, and a softer text is proposed in the note, marked "NON appliquée / NOT applied". This covers #1 (new proposal: "A short walk to start the afternoon."), #2 (the earlier rewrite moves to the note), #3, #4 (unchanged, it was already in the note) and #8 (new proposal: "Last coffee, tea or other caffeinated drink before 14:00.").
- **#7 Same bedtime**: the 6–8 h sleep-window step is removed (4 steps remain), and 6–8 h is kept in the note.
- **#8 No caffeine**: "(NSDR)" is removed from step 5.
- **#9 Screens off**: step 1 now reads "at the very least 30 minutes before bed — a full hour is better" (N2).
- **#10 Dim the lights**: "1-2" becomes "1–2" in the easy description.
- **#11 Morning light**: steps 2–3 now follow P071: at least 10 min on a clear morning, 20 min partly cloudy, 30 min very overcast. This meets both P004 and P071 (N3). "3-4" becomes "3–4" in the why. The note is updated.
- **#2 Evening walk**: FR « une fois rentré » becomes « une fois de retour chez vous » (Fr12).

## Other HIGH / MEDIUM items
- **S2 Cold shower**: new step 2: "Skip it if you are pregnant, have a serious health condition, or are ill with…" (P046). It now has 7 steps, and the 5-minute cap, no forceful breathing, no jumping or diving, no outdoor water without an expert and the 6 h after strength training are all kept. "Towel off" and the "I want out → I can handle it" line were cut to fit, as the note says. F6: the why now uses "can set off… may last". Fr9: punctuation fixed.
- **N4 / S3 Strength ×3**: the reps are now 6–10 on multi-joint lifts and 8–15 on single-joint ones (P031). The progression stays at 10 / 10–15 (P033). New break-in step: "New to lifting? For the first 1–3 weeks, use light weights for 10–12 reps, stopping about 5 reps short of failure…" (P022/P030). F7 FR: « polyarticulaire / isolation » becomes « qui sollicite plusieurs articulations / à une seule », in the easy description too. The notes are rewritten and fit within 1500 characters.
- **S4 #59 Same wake-up time**: the nap option is removed from step 4, which keeps only guided deep rest (no "NSDR"). "1-2" becomes "1–2" in the easy texts.
- **S6 #48 Water**: 2.4 L is kept, with a new step 3: "If your practice has asked you to limit fluids, follow that instead." D6: step 1 now starts from the morning glass and merges the old steps 1 and 2, so the card still has 6 steps.
- **F1/D3 #50**: removed (see above).
- **F2 #37 40 Hz**: the mechanism claim and the 12–20 Hz effect claim are removed. The why now reads "Some people find a steady beat helps them settle into focus. It costs nothing to try, so notice whether it helps you."
- **F4 #26 Mobility**: "Founder pose" becomes "Standing hip hinge" / « Charnière de hanche debout » in step 6 and the easy version. The YouTube query is now "standing hip hinge arms overhead".
- **F5 #40 WOOP**: the YouTube query is now "mental contrasting wish outcome obstacle plan", and the note no longer names the method. Straight quotes are now ‘…’.
- **D1–D5**: done (see the removals above).
- **D7 #55 Midday sun**: the title already shows the angle (skin, 20–30 min). The note says so, and the category is unchanged.
- **Decision 6 #62 Cool bedroom**: °F comes first with °C in brackets, in the description and the steps (EN and FR). The note marks the °C as a derived conversion. Fr7 is applied in step 3.
- **Decision 6 #64**: step 5 is "no caffeine after 1–2 p.m." in EN and « 13 h – 14 h » in FR. The note marks the 24 h form as derived. "3-4" becomes "3–4" in the title and description.
- **Fr1–Fr3**: Fr1 is applied to #17's title_fr, Fr2 and Fr3 lapse with #27 and #50.

## LOW items also applied
- **#33 Double-inhale sigh** (S8): now `routine` with duration null, and "rather than the circle's" is removed.
- **#54** (F7): renamed "Ten minutes of guided deep rest" / « Dix minutes de repos profond guidé ». "NSDR" is gone from member text and stays in the YouTube query. "20-30" becomes "20–30".
- **#18 Calf raises** (F7): "soleus / soléaire" is removed from the why. Fr6 is applied to description_fr.
- **#65 Nap**: the title, description and easy description use en dashes. Fr11 is applied in the why_fr.
- **#58 and #61**: "toward" becomes "towards", and "10-15" becomes "10–15" in #58.
- **French fixes**: Fr4 on #32's easy_title_fr, Fr5 on #13's step 2, Fr8 on #39's step 4, and Fr12 on #2 and #23's easy description (« Vous débutez ou reprenez le cardio ? »).

## Not applied (on purpose)
- **N9** (drop #64 step 5): decision 6 keeps the record's "1–2 p.m."
- **F3** (apply the softer lot A descriptions): decision 5 says keep the live text and propose the softer text in the note.
- **A3** (#7 BYDAY=SU–TH): this is the reviewer's pick. MO–FR stays, and the note already raises it.
- **S9** (fermented foods and pregnancy): this is a reviewer decision, because the record is silent and nothing can be invented.
- **N5–N8** (sign-off only): no text change.
- **D8, D10–D12**: the review accepts these as they are.
- **The #29 120-minute duration, descriptions over 100 characters and steps over 140 characters**: LOW style items, left as they are. Several new merged steps are over 140 characters too (strength ×3, cold shower, hard intervals).
