# Action card catalogue: first pass on tiers and tracks

Claude's first pass, 2026-10-05, for Thomas's second pass. The interactive version (choices saved as you click) is the
"Action Card Catalogue" artifact. This file is the frozen first pass; the decisions land in `habit_bank` once Thomas has reviewed them.

**Tiers**
- **Trial**: offered in the 2-week trial and after (`member_can_add = true`).
- **Members only**: kept for paying members, not in the trial. These are 7 small ones, so the trial carries 42 of the 49 non-prescription written cards (86%).
- **Prescription**: only when a practitioner prescribes it (`member_can_add = false`). The daily focus now respects this: see `focusEligibleBank`.

**Tracks**: Basic · More energy · Better sleep · More focus · Less brain fog · Build muscle · Lose weight. Stress* is a proposed extra track.

**State**
- Live: members see it.
- Draft: in `habit_bank`, not published.
- In file: in `huberman/lot-b-*.json`, waiting for Import JSON.
- Live (short): title and one line only, no how-to or why yet.

## Fully written cards (61)

### Sleep (14)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| Same bedtime on weekdays | Live | Trial | Schedule habit. | Sleep, Energy |  |
| No caffeine after 14:00 | Live | Trial | Removes something, adds nothing. | Sleep, Energy |  |
| Screens off 30 minutes before bed | Live | Trial | Removes something, adds nothing. | Basic, Sleep |  |
| Dim the lights after 21:00 | Live | Trial | Environment only. | Sleep |  |
| Morning light within an hour of waking | Live | Trial | Outdoor light, short, never staring at the sun. | Basic, Sleep, Energy, Focus, Brain fog |  |
| Afternoon light before sunset | In file | Members only | Kept for members: the morning-light card already carries the trial. Outdoor light. | Sleep |  |
| Same wake-up time, weekends too | In file | Trial | Schedule habit. | Basic, Sleep, Energy |  |
| A mental walk at lights-out | In file | Trial | Mental exercise in bed. | Sleep |  |
| Slow eye movements at lights-out | In file | Trial | Eye movements and one long breath out. | Sleep |  |
| A cool bedroom for the night | In file | Trial | Environment only. | Sleep |  |
| A hot shower before bed | In file | Trial | Ordinary shower. | Sleep | A practitioner may switch it off for members who faint easily or have low blood pressure. |
| Hard workouts end 3–4 hours before bed | In file | Trial | Timing rule, adds no exercise. | Sleep, Muscle |  |
| A short nap, 15–20 minutes | In file | Prescription | Naps can make insomnia worse: the practitioner decides whether it fits this member's sleep plan. | Energy, Focus, Brain fog |  |
| No alcohol in the eight hours before bed | In file | Prescription | Touches alcohol use: a member who depends on alcohol needs a practitioner's plan, not an app card. | Sleep, Energy, Weight | The idea itself is safe: could go free with softer wording. |

### Exercise (12)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| A 10-minute walk after lunch | Live | Trial | Gentle, short, no equipment. | Basic, Energy, Brain fog, Weight |  |
| Evening walk | Live | Trial | Easy pace walking. | Sleep, Weight |  |
| A brisk 30-minute walk | Draft | Trial | Walking; the gentle version starts shorter. | Energy, Weight, Brain fog, Sleep |  |
| Walk five minutes every half hour | Draft | Trial | Short walking breaks. | Energy, Brain fog, Weight, Focus |  |
| Seated calf raises under the desk | Draft | Trial | Seated, bodyweight only. | Energy, Brain fog, Weight |  |
| Strength session: legs | Draft | Prescription | An hour of hard sets close to failure: the practitioner checks heart, blood pressure and joints and sets the load. | Muscle, Weight |  |
| Strength session: chest, back, core | Draft | Prescription | An hour of hard sets close to failure: the practitioner checks heart, blood pressure and joints and sets the load. | Muscle, Weight |  |
| Strength session: shoulders and arms | Draft | Prescription | An hour of hard sets close to failure: the practitioner checks heart, blood pressure and joints and sets the load. | Muscle, Weight |  |
| Long, easy cardio: 45–75 minutes | In file | Prescription | Long sessions; beginners start at 15–20 minutes, so the practitioner sets the starting point. | Energy, Weight |  |
| Steady hard cardio: 25–30 minutes | In file | Prescription | Sustained hard effort: needs a cardiovascular check first. | Energy, Weight |  |
| Hard intervals: 30 seconds on, 60 off | In file | Prescription | Near all-out effort: needs a cardiovascular check first. | Energy, Weight, Muscle |  |
| Ten-minute mobility routine | In file | Prescription | The lead clinician chose 'only if your practice has cleared you' for this card. | Muscle, Energy | Low intensity: could move to free if the clearance line comes off. |

### Nutrition (11)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| A glass of water before coffee | Live | Trial | One glass of water. | Basic, Energy, Brain fog |  |
| Protein at breakfast | Live | Trial | Food choice, no amounts imposed. | Basic, Energy, Muscle, Weight |  |
| Vegetables on half the plate | Live | Trial | Food choice, no amounts imposed. | Basic, Weight |  |
| Kitchen closed after 21:00 | Live | Trial | Meal timing only. | Sleep, Weight | A practitioner may want this off for members with a history of disordered eating. |
| First coffee 30 minutes after waking | In file | Trial | Timing of a drink the member already has. | Energy |  |
| A proper meal after training | In file | Trial | Meal timing and choice. | Muscle |  |
| Most of your water in the first ten hours | In file | Trial | Drinking pattern. | Energy, Brain fog | The steps give about 2.4 L: not for members on a fluid restriction (heart, kidney). A practitioner should switch it off for them, or make the card prescription-only. |
| One meal from single-ingredient foods | In file | Trial | Food choice. | Weight, Energy |  |
| Protein first, then the rest | In file | Trial | Order of eating, no amounts. | Weight, Energy | Same eating-history caution as 'Kitchen closed after 21:00'. |
| Cook with olive oil | In file | Trial | Food choice. | Weight |  |
| Fermented foods, two to four a day | In file | Members only | Kept for members: a refinement once the nutrition basics hold. Food choice. | Energy | Members with histamine intolerance or digestive conditions may react: practitioner to judge. |

### Mind (17)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| Five minutes sitting with your breath | In file | Trial | Sitting still, five minutes. | Focus, Stress*, Brain fog | Some members with trauma find breath focus hard; the practitioner can switch it off for them. |
| A two-hour focus block, then a break | In file | Trial | Work organisation. | Focus |  |
| Full attention on every rep | In file | Trial | Attention cue during a workout the member already does. | Focus, Muscle |  |
| A cold shower, one to three minutes | In file | Prescription | Cold shock raises heart rate and blood pressure: needs screening first. | Energy, Focus |  |
| Brisk breathing before focused work | In file | Prescription | Fast deep breathing can cause dizziness and tingling: needs screening first. | Energy, Focus |  |
| The double-inhale sigh, up to three times | In file | Trial | A few seconds of slow breathing. | Basic, Stress*, Sleep |  |
| Five minutes of cyclic sighing | In file | Trial | Slow breathing, five minutes. | Stress*, Sleep, Focus |  |
| Ten focused breaths on waking | In file | Trial | Ten calm breaths. | Focus, Brain fog |  |
| Five minutes of 40 Hz beats before focus | In file | Members only | Kept for members: an extra on the focus track, and its evidence is thin. Listening to audio. | Focus | The record cites no study. Maybe keep it out of autopilot packs until reviewed. |
| Nose breathing, belly first | In file | Trial | Breathing awareness. | Sleep, Focus |  |
| Phone in another room while you focus | In file | Trial | Removes something, adds nothing. | Focus, Brain fog |  |
| Wish, outcome, obstacle, plan — on paper | In file | Trial | Paper exercise, weekly. | Focus |  |
| Practise just beyond your level | In file | Members only | Kept for members: with the next two, a 'learn faster' mini pack. Learning method. | Focus |  |
| Short pauses while you practise | In file | Members only | Kept for members: part of the 'learn faster' mini pack. Learning method. | Focus |  |
| Test yourself after learning | In file | Members only | Kept for members: part of the 'learn faster' mini pack. Learning method. | Focus, Brain fog |  |
| Bring your thoughts back to here | In file | Trial | Attention exercise. | Stress*, Brain fog, Focus | The record says clinical depression needs professional follow-up: the card does not replace that. |
| The same small ritual at each switch | In file | Trial | A short gesture between tasks. | Focus, Stress* |  |

### Emotion (4)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| Two columns: worries and what you control | Draft | Trial | Paper exercise, monthly. | Focus, Stress* |  |
| Social media, about an hour a day | Draft | Trial | Removes something, adds nothing. | Focus, Brain fog, Stress* |  |
| Gratitude that takes some looking | Draft | Trial | Reflection, a few minutes. | Stress* |  |
| Five minutes alone, with no input | Draft | Trial | Quiet time, five minutes. | Stress*, Focus |  |

### Recovery (3)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| Ten minutes of guided deep rest | In file | Trial | Lying down, guided audio. | Sleep, Energy, Stress*, Brain fog |  |
| Midday sun on your skin, 20–30 minutes | In file | Prescription | Sun on bare skin: depends on skin history and on medication that makes skin sun-sensitive. | Energy, Sleep |  |
| One hour for a hobby this week | In file | Members only | Kept for members: a weekly extra. Leisure time. | Stress* |  |

## Live cards still short (25)

### Sleep (1)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| Tomorrow's list before bed | Live (short) | Trial | Writing. | Sleep, Stress* |  |

### Exercise (4)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| Morning stretch, five minutes | Live (short) | Trial | Gentle stretching. | Energy |  |
| One set of push-ups | Live (short) | Trial | One set, the member picks the number. | Muscle |  |
| Stairs instead of lifts | Live (short) | Trial | Everyday movement. | Energy, Weight |  |
| Ten sit-to-stands | Live (short) | Trial | Bodyweight, from a chair. | Muscle, Energy |  |

### Nutrition (2)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| Fruit within reach | Live (short) | Trial | Food choice. | Energy, Weight |  |
| Slow first five bites | Live (short) | Trial | Eating pace. | Weight |  |

### Mind (6)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| A two-minute pause between tasks | Live (short) | Trial | Short break. | Focus, Brain fog |  |
| Box breathing, 4×4 | Live (short) | Trial | Slow breathing. | Stress*, Focus |  |
| Five minutes of daylight | Live (short) | Trial | Outdoor light. | Energy, Brain fog | Near-duplicate of 'Five minutes outside in daylight': merge? |
| One phone-free coffee | Live (short) | Trial | Removes something, adds nothing. | Focus, Stress* |  |
| Single-task the first work hour | Live (short) | Trial | Work organisation. | Focus |  |
| Three slow breaths before meals | Live (short) | Trial | Slow breathing. | Stress* |  |

### Emotion (6)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| A real lunch with someone | Live (short) | Trial | Social habit. | Stress* |  |
| Journaling, five minutes | Live (short) | Trial | Writing, five minutes. | Stress*, Sleep |  |
| Name the feeling, once | Live (short) | Trial | Reflection. | Stress* |  |
| One message to someone you like | Live (short) | Trial | Social habit. | Stress* |  |
| Say no to one thing | Live (short) | Trial | Boundary habit. | Stress*, Energy |  |
| Three good things tonight | Live (short) | Trial | Reflection. | Stress*, Sleep |  |

### Recovery (6)

| Card | State | Tier | Why | Tracks | Check |
|---|---|---|---|---|---|
| A 20-minute nature walk | Live (short) | Trial | Easy walking outdoors. | Stress*, Energy |  |
| A real pause at lunch, no screens | Live (short) | Trial | Break. | Stress*, Focus, Brain fog |  |
| Five minutes outside in daylight | Live (short) | Trial | Outdoor light. | Energy, Brain fog | Near-duplicate of 'Five minutes of daylight': merge? |
| Legs up the wall, five minutes | Live (short) | Trial | Resting position. | Sleep, Stress* |  |
| One work-free evening block | Live (short) | Trial | Boundary habit. | Stress*, Sleep |  |
| Shoulders down, jaw loose — three times | Live (short) | Trial | Body awareness. | Stress* |  |
