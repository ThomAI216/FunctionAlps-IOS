# Foundation Track articles · the brief

## Voice and format

- English (British spelling, as the existing library: programme, fibre, colour). Second person, warm, plain, short sentences. No hype, no fear, no jargon without a one-line explanation. Speak like Thomas, a functional-nutrition practitioner: practical, kind, evidence-minded.
- A **Read** is 500–800 words; a **Short read** or **Lesson** 300–500 words. One idea per article.
- Structure: a one-sentence summary; a short opening that says why it matters in daily life; 2–4 sections with `##` headings; a `## What to do` section that matches the habit's steps exactly; a `## What to look for` section with the benefits to notice (soft wording: 'many people notice'); a one-line key takeaway in bold at the end.
- Accuracy: only well-established claims; hedge where the evidence is mixed; never promise outcomes; no numbers you cannot source. Give 2–4 real references at the end (systematic reviews, meta-analyses, major RCTs or consensus statements), each verified on PubMed (title, first author, journal, year, PMID or DOI). Do not invent a reference.
- Safety: where relevant, one plain line on who should check first (e.g. breathing practices: sitting or lying down, never in water or driving; exercise: stop if it hurts; medical conditions: ask your doctor or nutritionist).
- No clinical diagnosis, no supplement doses, no medication advice.
- Links: mention the habit it goes with by its exact name; you may point to another track article by its exact title.

## Output

One file per article in this folder, named `dNN-slug.md` (NN = the day, two digits), starting with this front matter, then the body in Markdown:

```
---
day: 4
kind: Short read
title: The 3-2-1 rule
slug: the-3-2-1-rule
summary: One sentence.
reading_time: 3 min
habits: [The 3-2-1 rule]
status: draft for Thomas
---
```

Then the body. References under a final `## References` heading.

Read-only on the database: you may read existing library articles for voice and content with SELECT queries on Supabase project ndojytvvlvlbgtodujkf (`select title, body_md from kb_nodes where title = '…' and status = 'published'`). Never write to the database.

## The track, day by day

- **Day 1 · Your starting point** (Where you are, where you're going). New habits: Log a meal; Do your functional check-in.
- **Day 2 · Nutrition** (Pillar 1). New habits: Mindful eating: no phone, chew, breathe, a glass of water; A 5-minute walk after eating.
- **Day 3 · Movement** (Pillar 2). New habits: 3 minutes of movement; Optional: an exercise snack; 2 minutes of gentle stretching before bed.
- **Day 4 · Sleep** (Pillar 3). New habits: Daylight first thing: head out of the window, and breathe; No caffeine after 16:00; The 3-2-1 rule: 3 h no food, 2 h no intense exercise, 1 h no screens; Optional: a mini breath before sleep.
- **Day 5 · Mental and emotional health** (Pillar 4). New habits: 5 minutes of breathing, once a day; Write down three good things about your day.
- **Day 6 · Your first week** (Recap; no new action). New habits: none.
- **Day 7 · Your full day** (Everything together). New habits: 5-minute morning flow; One exercise snack a day.
- **Day 8 · Build your plate** (Week 2). New habits: Protein at every meal; Complex carbs over refined; A short walk after every meal.
- **Day 9 · Easy strength** (Week 2). New habits: 2 to 3 movement moments a day.
- **Day 10 · Your evening downshift** (Week 2). New habits: A book instead of a screen; 10 minutes to wind down: box breathing or NSDR.
- **Day 11 · Your mind, day to day** (Week 2). New habits: A second moment to breathe; Reach out to someone you care about; 5 minutes of writing: three good things, and what's on your mind.
- **Day 12 · More movement** (Week 2). New habits: 10-minute morning flow; Move 10 minutes every 2 hours.
- **Day 13 · Make it yours** (Week 2: choose the habits you keep). New habits: none.
- **Day 14 · Your two weeks** (Recap and review call with Thomas). New habits: none.

## The habits (exact names and wording to match)

- **Log a meal** (Midday, day 1–3). Snap your plate before the first bite. Drinks and snacks too. How: Open Log a meal, point, shoot / Before the first bite, not after / Drinks and snacks count. Benefits to look for: You see your real pattern, without counting; Your nutritionist sees what you eat; You notice what keeps you full. Tends to: ↑ Awareness, ↓ Cravings.
- **Do your functional check-in** (Evening, day 1–3). One minute in the evening: how the day landed. How: Five sliders: energy, sleep, mood, calmness, digestion / Around the same time each evening / Honest beats perfect. Benefits to look for: You start to see your own patterns; Your curves appear in Trends; It shows what your habits change. Tends to: ↑ Awareness, ↑ Mood.
- **Mindful eating: no phone, chew, breathe, a glass of water** (Midday, day 2+). No phone, chew a lot, breathe, a glass of water. How: Phone away, screen off / Chew each bite well; put the fork down between bites / Three breaths before you start, a glass of water with the meal. Benefits to look for: Lighter digestion, less bloating; Full sooner, fewer cravings later; Calmer meals. Tends to: ↑ Digestion, ↓ Cravings, ↓ Stress.
- **A 5-minute walk after eating** (Midday, day 2–7). Five minutes on your feet after eating. How: Right after the meal, or within half an hour / Outside if you can; the corridor works too / Easy pace, no sweat. Benefits to look for: Steadier energy after meals; Easier digestion; Less of the afternoon dip. Tends to: ↑ Energy, ↑ Digestion, ↓ Cravings.
- **3 minutes of movement** (Morning, day 3–6). Three minutes to wake the body. How: Neck, shoulder and hip circles / 10 slow squats / Reach up, fold down, breathe. Benefits to look for: Less stiffness in the morning; More awake, sooner; A first win in your day. Tends to: ↑ Energy, ↑ Mood.
- **Optional: an exercise snack** (Midday, day 3–6). One short burst of movement, if you feel like it. How: 10 squats, or a minute up the stairs / Or 10 push-ups against a wall / Any time you've been sitting a while. Benefits to look for: Clarity of mind; Stable blood sugar; More energy; A stronger body overall. Tends to: ↑ Focus, ↑ Energy, ↑ Mood.
- **2 minutes of gentle stretching before bed** (Evening, day 3–9). Two minutes of gentle stretching before bed. How: Slow, never into pain / Hamstrings, hips, an open chest / A long breath out with each stretch. Benefits to look for: Easier to fall asleep; Looser back and hips; A clear end to the day. Tends to: ↑ Sleep, ↓ Stress.
- **Daylight first thing: head out of the window, and breathe** (Morning, day 4+). Right when you wake up: daylight and fresh air, before your phone. How: Right when you wake up, before your phone / Then 5 minutes outside, or at an open window / No sunglasses; never look straight at the sun. Benefits to look for: More awake in the morning; Easier to fall asleep at night; A steadier mood. Tends to: ↑ Energy, ↑ Mood, ↑ Sleep.
- **No caffeine after 16:00** (Afternoon, day 4+). Your last coffee, tea or energy drink before 16:00. How: Coffee, black and green tea, cola and energy drinks all count / After 16:00: decaf, herbal tea or water / If 16:00 is hard, move it 30 minutes earlier each day. Benefits to look for: Falling asleep faster; Deeper sleep; Needing less caffeine the next morning. Tends to: ↑ Sleep, ↓ Stress.
- **The 3-2-1 rule: 3 h no food, 2 h no intense exercise, 1 h no screens** (Evening, day 4+). Before bed: 3 hours no food, 2 hours no intense exercise, 1 hour no screens. How: 3 hours before bed: your last food of the day / 2 hours before: no hard exercise. Stretching, light movement and a walk are fine / 1 hour before: no scrolling. Answering a message is fine; it's the stimulating stuff you leave. Benefits to look for: Falling asleep faster; Waking less in the night; Calmer evenings. Tends to: ↑ Sleep, ↑ Energy, ↓ Stress.
- **Optional: a mini breath before sleep** (Evening, day 4–9). A few slow breaths in bed: in through the nose, a long breath out. How: Lying down, lights off / In through the nose for 4 / Out slowly for 6 to 8, five times. Benefits to look for: Calmer before sleep; Easier to drop off. Tends to: ↓ Stress, ↑ Sleep.
- **5 minutes of breathing, once a day** (Midday, day 5+). 5 minutes for yourself, once a day: deep breaths, a slow exhale, a hold. How: Sit or lie down; never in water or while driving / 30 deep breaths, then breathe out slowly / Hold as long as is comfortable; 2 rounds to start. Benefits to look for: A calmer, clearer head; Energy without coffee; A moment that is yours. Tends to: ↓ Stress, ↑ Focus, ↑ Energy. Video: Guided breathing, with Wim Hof.
- **Write down three good things about your day** (Evening, day 5–10). Write down three good things about your day. How: In the evening, in your phone or a journal / Small things count / One line on why it was good. Benefits to look for: Falling asleep on a good thought; Over weeks, a more positive outlook; Noticing what helps you. Tends to: ↑ Mood, ↓ Stress, ↑ Sleep.
- **5-minute morning flow** (Morning, day 7–11). Five minutes inspired by qi gong: breathe with the arms, twist, shake it out. How: Slow breathing with the arms / Gentle twists, left and right / Shake it out. Benefits to look for: A loose, awake body; A better mood in the morning; Your first win, every day. Tends to: ↑ Energy, ↑ Mood, ↑ Focus. Video: The 5-minute morning flow.
- **One exercise snack a day** (Midday, day 7–8). One exercise snack every day, no longer optional. How: 10 squats, a minute of stairs, or 10 wall push-ups / Once a day, whenever suits you / Easier is always fine. Benefits to look for: Clarity of mind; Stable blood sugar; More energy; A stronger body overall. Tends to: ↑ Focus, ↑ Energy, ↑ Mood.
- **Protein at every meal** (Midday, day 8+). A palm of protein at every meal. How: Eggs, yogurt, fish, chicken, tofu, beans or lentils / About the size of your palm / Start with breakfast. Benefits to look for: Fuller for longer; Fewer cravings; Keeping your muscle as you age. Tends to: ↓ Cravings, ↑ Energy.
- **Complex carbs over refined** (Midday, day 8+). Complex carbs rather than refined. How: Oats, wholegrain bread, beans, quinoa, brown rice / White bread and pasta → wholegrain / Whole fruit rather than juice. Benefits to look for: Steadier energy; No three o'clock dip; Better digestion, with the fibre. Tends to: ↑ Energy, ↑ Focus, ↓ Cravings.
- **A short walk after every meal** (Midday, day 8+). A short walk after every meal. How: 5 to 10 minutes / Right after eating, or within half an hour / Even around the house. Benefits to look for: Steadier energy all day; Easier digestion; More steps without trying. Tends to: ↑ Energy, ↑ Digestion.
- **2 to 3 movement moments a day** (Afternoon, day 9+). 2 to 3 movement moments a day. It can be as light as a walk. How: Choose a movement: it can be as light as a walk / Or a few easy moves: squats, calf raises, a chest opener / Push-ups too, if you're comfortable. Benefits to look for: Clarity of mind; Stable blood sugar; More energy; A stronger body overall. Tends to: ↑ Focus, ↑ Energy, ↑ Mood. Video: Exercise-snack routines.
- **A book instead of a screen** (Evening, day 10+). A book instead of a screen in your last hour. How: Choose tonight's book now / Paper, or an e-reader without the lights up / Even 10 pages. Benefits to look for: Sleepier at the right time; Less noise in your head; Time for yourself. Tends to: ↑ Sleep, ↓ Stress.
- **10 minutes to wind down: box breathing or NSDR** (Evening, day 10+). 10 minutes to wind down: box breathing or an NSDR. How: Box breathing: in 4, hold 4, out 4, hold 4 / Or a guided NSDR, lying down / Lights low. Benefits to look for: Falling asleep faster; A calmer mind; Better recovery. Tends to: ↑ Sleep, ↓ Stress. Video: 10-minute NSDR.
- **A second moment to breathe** (Afternoon, day 11+). A second moment to breathe, in the afternoon. How: Same as your morning round, or 5 slow breaths / When the afternoon gets heavy / Away from the screen. Benefits to look for: A reset in the middle of the day; Less tension by the evening. Tends to: ↓ Stress, ↑ Focus. Video: Guided breathing, with Wim Hof.
- **Reach out to someone you care about** (Afternoon, day 11+). A message or a call to someone you care about. How: Think of one person / A message, a voice note or a call / No reason needed. Benefits to look for: Feeling more connected; A lift in mood; Stronger relationships over time. Tends to: ↑ Mood, ↓ Stress.
- **5 minutes of writing: three good things, and what's on your mind** (Evening, day 11+). 5 minutes of writing: three good things, and what's on your mind. How: Three good things first / Then whatever is on your mind / No rules, no rereading. Benefits to look for: A clearer head at night; Spotting what drains you and what helps; Easier sleep. Tends to: ↓ Stress, ↑ Sleep, ↑ Mood.
- **10-minute morning flow** (Morning, day 12+). Ten minutes: your morning flow, longer. How: Breathe, move, twist, shake it out / Outside if you can / Same time each morning. Benefits to look for: Looser, warmer, more awake; A calmer start; Daylight on top, if outside. Tends to: ↑ Energy, ↑ Mood, ↑ Focus. Video: The 10-minute morning flow.
- **Move 10 minutes every 2 hours** (Afternoon, day 12+). Every 2 hours, stand up and move for 10 minutes. How: A walk if you can / Stairs, a stretch, a call on your feet / Set a quiet reminder. Benefits to look for: Less stiffness; Sharper focus after the break; More steps without trying. Tends to: ↑ Focus, ↑ Energy.

## The articles to write (brief and existing library article to borrow from)

- Day 1 · **Introduction to functional health** (Read). What functional health is, the four pillars, why we start from where you are. Thomas is writing it. Borrow from: Feedback and Self-Tracking.
- Day 1 · **What your meal photos tell us** (Short read). Why we ask for photos (no counting), what we look at, how to snap fast: before the first bite, drinks and snacks too.
- Day 1 · **Your functional check-in, explained** (Short read). The five markers (energy, sleep, mood, calmness, digestion), one minute in the evening, and how your curves become your Trends. Borrow from: Feedback and Self-Tracking.
- Day 2 · **Mindful eating** (Read). The meal without the phone: chew a lot, breathe between bites, a glass of water, notice when you're full. Why it changes digestion, hunger and cravings.
- Day 2 · **The 5-minute walk after eating** (Short read). A few minutes of walking after a meal softens the blood-sugar rise and helps digestion. How to fit it in, even at work. Borrow from: Post-Meal Walking.
- Day 3 · **Little and often** (Read). Functional capacity, not sport. Why 3 minutes in the morning and 2 minutes of stretching at night beat a big plan you don't keep. Borrow from: Micro-Workouts / Exercise Snacks.
- Day 3 · **Exercise snacks: small signals that add up** (Lesson). What an exercise snack is (10 squats, a minute of stairs, wall push-ups) and why short bursts add up. Borrow from: Micro-Workouts / Exercise Snacks.
- Day 4 · **Light sets your body clock** (Read). Daylight first thing (even your head out of the window, breathing) sets your rhythm; bright screens at night push it back. Borrow from: Morning Wake-Up Routine.
- Day 4 · **The 3-2-1 rule** (Short read). 3 hours before bed no food, 2 hours no intense exercise (stretching, light movement and a walk are fine), 1 hour no screens: no scrolling, no stimulating phone use; answering a message is fine. Why each one helps.
- Day 4 · **Caffeine and your sleep** (Short read). Caffeine stays in the body for hours: none after 16:00, and what to drink instead.
- Day 5 · **Breathe: the time you give yourself** (Read). A Wim Hof-style round (deep breaths, a slow exhale, a comfortable hold; two rounds to start), but the point isn't the technique: it's 5 minutes for yourself, once a day, and a more positive attitude. Safety: sitting or lying down, never in water or driving. Borrow from: Breathing Exercises.
- Day 5 · **Three good things** (Short read). Writing down three good things each evening, on your phone or in a journal, and why it shifts attention and mood over a few weeks.
- Day 6 · **Simple actions, repeated** (Read). Why the basics, done every day, beat the perfect plan. Borrow from: Your Unique Terrain Roadmap.
- Day 6 · **The power of habits** (Read). How a habit forms: cue, routine, reward; anchoring the new to the old; why we start small.
- Day 6 · **The power of compounding** (Read). Small gains that add up: 1% better each day, and why the first two weeks matter more than they feel.
- Day 7 · **Your day, on one page** (Read). The full day in four moments, morning to evening, and how the habits link to each other. Borrow from: How Nutrition, Training, Gut, Recovery and Nervous System Work Together.
- Day 8 · **Protein at every meal, and why it matters** (Read). Building material, fullness, muscle as we age; easy sources for each meal. Borrow from: Nutrient-Dense Foods.
- Day 8 · **Complex or refined carbs: why it matters** (Read). Fibre, the steadier energy curve, the three o'clock dip; simple swaps.
- Day 8 · **The walk after every meal** (Short read). From one walk on day 2 to a short walk after every meal. Borrow from: Post-Meal Walking.
- Day 9 · **Muscle, a long-term investment** (Read). Muscle as a health account: joints, blood sugar, independence with age. Exercise snacks as the deposits. Borrow from: Strength Is More Than Muscle Size.
- Day 9 · **The benefits of exercise snacks** (Read). What short bursts do for the heart, blood sugar, energy and mood, and why 2 to 3 a day. Borrow from: Micro-Workouts / Exercise Snacks.
- Day 10 · **Your evening routine** (Read). Why the same steps in the same order help you sleep: the 3-2-1 rule, a book, 10 minutes to wind down (box breathing or NSDR).
- Day 10 · **NSDR, explained** (Read). Non-sleep deep rest: what it is, when to use it, how it differs from sleep and meditation. Links to a 10-minute guided session. Borrow from: NSDR / Yoga Nidra.
- Day 11 · **Connection is health** (Read). Why people matter for health; one message or call a day.
- Day 11 · **The habit of writing** (Read). From three good things to 5 minutes of writing: clearing your mind, noticing patterns.
- Day 12 · **The power of walking** (Read). The simplest, most underrated habit: heart, blood sugar, mood, creativity; ten minutes every two hours. Borrow from: Post-Meal Walking.
- Day 12 · **Sitting less** (Read). What long sitting does, and the 10-minute break every two hours. Borrow from: ROM & Loaded Mobility.
- Day 13 · **Habits that last** (Read). Keep the ones you'd miss, not the ones you think you should. Borrow from: Signals Create Adaptation.
- Day 14 · **What a personal programme adds** (Read). What comes after the app: labs, a plan made for you, follow-up with Thomas. Borrow from: Biological Recovery.
