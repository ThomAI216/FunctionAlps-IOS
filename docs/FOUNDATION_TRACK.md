# The Foundation Track — content source of truth

Status: **agreed with Thomas 2026-10-06, EN text for review; FR to follow once the EN is locked.**
Second pass (Thomas, 2026-10-06): days 1–7 each explain a pillar (what it is, why it matters, how we use it), say
why the day's questions matter, and end with a first thing to try that grows into a routine. No image on days 1–7.
Every call is the 20-minute members call.

**Where the content lives.** `docs/foundation-cards/build.py` is the source of the day titles, the actions (title,
one-line how-to, first and last day), each card's text (Today, why we ask, first thing to try, mini tip, how it will
evolve, library links), the motion-video voiceovers and storyboards, and the image briefs (published as the card mockups).
`supabase/seed/foundation_track_seed.py` reads it and adds the questions, the reminder texts, the `habit_bank` cards
and the day's subtitle. The day tables, card text, reminders and scripts below are generated from those two files.
Seeds `track_day`, `track_questionnaire`, `track_question` (migration `supabase/migrations/20261006_foundation_track.sql`, **applied on CM OS 2026-10-06**; track code `foundation_v1`, launched 2026-10-06).

## Decisions (Thomas, 2026-10-05/06)

- **It is the Foundation Track, not a trial.** Every newcomer from 2026-10-06 runs it (free or paying), enrolled at
  their first app open. Members who were already in are launched by Thomas with a button in CLINICAL; their 14 days
  start at their next app open.
- **Calls inside the app: always the 20-minute members call** ("Everything: 20 minutes", Thomas, 2026-10-06), booked
  at `https://www.functionalps.ch/book/thomas/foundation-call-20` ("Members call · 20 min"). Newcomers: day 3,
  optional; day 14, the review, unlocked by the review rule (or by Thomas). Existing members launched by Thomas: day 3,
  day 7 and day 14, optional. Stored per member in `member_track_enrollment.calls`. The 15- and 30-minute meeting
  types are switched off (migration `20261006_foundation_track_calls_20.sql`).
- **Day 7:** Thomas receives an email with the member's 7-day figures (how much they did) and answers yes or no;
  only on yes does the member get their summary (`track_summary.status = approved`).

- **Fixed and automatic.** The free trial is the same for everyone; real personalisation is for paying members. A
  "mini personalisation" picks variants by rule (below), never by hand. Every NEW member, paying or not, starts this
  track as their soft start in the app. The 34 members who existed before launch keep what they have.
- **Clock:** starts at first app open, 14 days. Day 15: the app stays open; Thomas decides each case.
- **Everything in the app is open from day 1.** What steps up is the daily action.
- **Review call (day 14)** unlocks with all 5 modules (days 1–5) + ≥ 80 % of expected meals
  (expected = the day-2 meals-per-day answer × (days − 1): photos start on day 2, the nutrition day). Thomas can open
  it for anyone.
- **Day-3 call:** the optional 20-minute members call, available from day 3.
- **Day-7 summary:** AI-drafted, approved by a practitioner before the member sees it.
- **Ranges:** energy = estimate ± 5 %, rounded to 50 kcal; protein = 1.3–1.7 g/kg (women), 1.6–2.0 g/kg (men).
  No refinement during the 14 days.
- **No safety-flag questions in the trial** (snoring/apnea, chest pain, fainting, self-harm, screeners). They come with
  the paid pillar questionnaires. Mood stays basic.
- **Discovery modules are basic.** The deep pillar questionnaires come in a paid programme, prefilled from these answers
  (question keys follow the spec's field names). The 131-question functional intake is not prompted during the trial.
- **Videos:** one ~1-minute video per day, recorded by Thomas in **French and English**.
- **Questionnaire screens:** 2–3 questions per page, then the next page. Never overwhelming.
- **Anything already answered is shown, not re-asked:** "You told us … Still right?"

## Automatic mini-personalisation (fixed rules)

| Answer | Effect |
|---|---|
| Day 1 wake time | morning reminder time |
| Day 2 lunch time | after-lunch reminder time |
| Day 4 bedtime | evening reminder time (45 min before) |
| Day 2 protein foods + way of eating | the breakfast/lunch ideas shown on days 8–9 |
| Day 3 discomfort when moving | gentler variants of every movement |
| Day 3 exercise days ≥ 4 | "keep it up" wording instead of "move a bit more" |
| Day 6 "how did the week feel" | easy / standard / further face of week-2 actions |
| Apple Health connected | step question skipped; bedtime prefilled from Health |

## Questionnaires

`*` = prefilled from an earlier answer or the record and shown as "Still right?".

### Day 1 · You, today (~3 min) — `foundation_d1_you_today`
Why we ask (intro): "Your goals, your usual week and your rhythm. This is your starting point: everything after builds on it, so there are no wrong answers. Don't change anything yet."

Page 1 — Your body
1. `baseline_confirm`* From your FunctionAlps record: {age} · {height} · {weight} · {activity}. Still right? — Yes · Update
2. `recent_weight_change` Over the past 12 months, has your weight… — Gone down · Stayed about the same · Gone up · Not sure
   - `recent_weight_change_kg` (if down/up) About how many kilos? — number, optional

Page 2 — What you want
3. `primary_goals` What would you most like to improve? Pick up to 3. — More energy · Better sleep · Less stress · Lose weight · Build strength and muscle · Move more comfortably · Better digestion · Focus and clarity · Healthy ageing · Something else
4. `success_3_months` If the next 3 months went really well, what would be different? — text or voice, optional

Page 3 — Your days
5. `work_schedule_type` What does a usual week look like? — Regular hours · Variable hours · Shift work · Lots of travel · Not working at the moment
6. `work_movement` During your day, are you mostly… — Sitting · A mix of sitting and moving · Standing · Physically active
7. `wake_time_workdays` What time do you usually wake up on a workday? — time

Page 4 — Your time
8. `short_movement_windows` When could you fit 5–10 minutes of movement? — After waking · Before work · Mid-morning · Lunch break · Afternoon · After work · Evening
9. `life_context_note` Anything in your life right now we should keep in mind? Children, caring for someone, a big project, travel… — text or voice, optional

Page 5 — Connect Apple Health: "Your phone and watch already know a lot about your movement and sleep. Connecting Apple Health means we don't ask what we can already see." — Connect · Not now

Page 6 — Turn on your reminders: "Each day we'll send a short reminder at the right moment: in the morning, after lunch and in the evening. Nothing else. You can change this any time." — Turn on reminders (iOS prompt) · Not now

Done: "Thank you. Tomorrow: nutrition, the first pillar."

### Day 2 · Your nutrition (~2 min) — `foundation_d2_how_you_eat`
Why we ask (intro): "How many meals, when, who cooks, which proteins you like, what you drink. It shows your real pattern before we change anything, and which ideas fit your kitchen."

Page 1 — Your meals
1. `meals_per_day` How many meals do you usually eat a day? — 1 · 2 · 3 · 4 or more  *(stored 1/2/3/4_plus; drives the 80 % rule)*
2. `breakfast_frequency` Do you usually eat breakfast? — Most days · Some days · Rarely or never
3. `lunch_time` Around what time do you usually have lunch? — time

Page 2 — Your food
4. `meal_sources` Who usually makes your meals? — I cook · My partner or family · Restaurant or canteen · Takeaway or delivery · Ready-made meals
5. `protein_sources` Which of these do you eat regularly? — Eggs · Fish · Poultry · Red meat · Dairy · Beans and lentils · Tofu or soy · Protein shakes
6. `diet_style` Do you follow a particular way of eating? — No · Vegetarian · Vegan · Mediterranean · Low-carb · Intermittent fasting · Other
7. `food_avoid` Anything you can't or don't eat? — text, optional

Page 3 — Appetite
8. `craving_time` When do you tend to snack or have cravings? — Morning · Afternoon · Evening · After dinner · Not really

Page 4 — Drinks
9. `water_per_day` How much water do you drink on a usual day? — Under 1 litre · 1–1.5 L · 1.5–2 L · Over 2 L · No idea
10. `caffeine_per_day` Coffee, tea or other caffeine drinks a day? — 0 · 1 · 2 · 3 · 4 or more
    - `last_caffeine_time` (if ≥ 1) When is your last one, usually? — Before noon · 12–14h · 14–17h · After 17h
11. `alcohol_drinks_week` Alcoholic drinks in a usual week? — None · 1–3 · 4–7 · 8–14 · More than 14

### Day 3 · Your movement (~2 min) — `foundation_d3_how_you_move`
Why we ask (intro): "How you move now, how you moved before, and whether anything hurts. It sets the right starting level for you, instead of the same workout for everyone, and keeps it safe."

Page 1 — Now
1. `exercise_days_week` On how many days a week do you exercise on purpose? — 0 · 1 · 2 · 3 · 4 · 5 or more
   - `current_activities` (if ≥ 1) What do you do? — Walking · Strength or gym · Running · Cycling · Hiking · Skiing · Swimming · Yoga or Pilates · Racket sports · Team sport · Golf · Other
2. `sitting_hours_workday` On a workday, how many hours do you spend sitting? — Under 2 · 2–4 · 4–6 · 6–8 · More than 8
3. `self_reported_steps` (only if Apple Health is not connected) About how many steps a day? — Under 3,000 · 3,000–6,000 · 6,000–9,000 · Over 9,000 · No idea

Page 2 — Before
4. `past_athletic_history` Were you regularly active or sporty in the past? — Yes, a lot · Somewhat · Not really
   - `last_consistently_active` (if exercise days = 0) When were you last regularly active? — Less than a year ago · 1–3 years · 3–5 years · More than 5 years · Never really
5. `strength_experience` How familiar are you with strength training? — Never done it · Beginner · Some experience · Trained regularly before · Training now

Page 3 — Your body today
6. `movement_discomfort` Is anything uncomfortable when you move at the moment? — No · Yes
   - `movement_discomfort_areas` (if yes) Where? — Neck · Shoulders · Back · Hips · Knees · Ankles or feet · Other
   - fixed text: "We'll keep everything gentle. Skip any movement that hurts. If a doctor has asked you to limit activity, follow their advice first."

Page 4 — What you enjoy
7. `movement_enjoy` Which kinds of movement do you actually enjoy? — Walking outside · Hiking or the mountains · Strength or gym · Classes · Sport · Yoga or stretching · Dancing · Cycling · Something else (tell us) · Not sure yet
8. `activity_confidence` — slider 0–10, wording by answer 1:
   - exercise days 0–3: "How sure are you that you can move a bit more over the next 2 weeks?"
   - exercise days 4+: "You already move a lot. How sure are you that you can keep it up over the next 2 weeks, with the daily actions on top?"

### Day 4 · Your sleep (~2 min) — `foundation_d4_how_you_sleep`
Why we ask (intro): "Your usual nights, not last night: bedtime, how long you take to fall asleep, what wakes you, how rested you feel. Your times also set when your reminders arrive."

Page 1 — Your usual night
1. `bedtime_workdays`* What time do you usually go to bed on a workday? — time (prefilled from Apple Health when connected: "Apple Health says around 23:10. Right?")
2. `wake_time_workdays`* "You told us you wake up around {day-1 time} on workdays. Still right?" — Yes · Change
3. `weekend_shift` At weekends, do you sleep in? — No · Up to 1 hour later · 1–2 hours later · More than 2 hours later

Page 2 — Falling and staying asleep
4. `sleep_latency` How long does it usually take you to fall asleep? — Under 15 min · 15–30 min · 30–60 min · Over an hour
5. `night_wakings` How often do you wake in the night? — Rarely · Once · 2–3 times · 4 or more
   - `waking_reasons` (if not rarely) What usually wakes you? — Bathroom · Thoughts or stress · Pain · Noise or light · Too hot or cold · Partner or children · Don't know

Page 3 — Mornings and evenings
6. `wake_refreshed` How refreshed do you usually feel when you wake up? — slider 0–10
7. `screens_before_bed` In the hour before bed, are you usually on a screen? — Rarely · Some nights · Most nights
8. `holiday_sleep` Do you sleep differently on holiday? — Better · About the same · Worse

### Day 5 · Your mental and emotional health (~2 min) — `foundation_d5_stress_recovery`
Why we ask (intro): "How stressed you've felt, where it comes from, your mood and what helps you switch off. Answer only what you're comfortable with: it helps us suggest tools that fit your life."

Page 1 — Your load
1. `stress_level` Overall, how stressed have you felt lately? — slider 0–10
2. `stress_sources` Where does most of it come from? — Work · Family · Relationship · Health · Money · Caring for someone · A big change · I'd rather not say

Page 2 — Switching off
3. `switch_off` How often is it hard to switch off in the evening? — Rarely · Sometimes · Often · Most days
4. `stress_effects` When stress is high, what changes for you? — Sleep · Eating · Energy · Mood · Exercise · Digestion · Concentration

Page 3 — Mood and recovery
5. `mood_overall` Over the past two weeks, how has your mood been overall? — slider 0–10
6. `recovery_methods` What helps you recover or switch off? — Exercise · Walking or nature · Breathing or meditation · Time with people · Reading or music · TV or screens · A drink · Nothing really
7. `personal_time` How much time do you have for yourself on a usual day? — Almost none · Under 15 min · 15–30 min · 30–60 min · More than an hour

Team note: a mood answer of 0–2 shows on the Trial board; nothing changes for the member.

### Day 6 · Your first week (~1 min) — `foundation_d6_first_week` (does not count toward the review)
Why we ask (intro): "Check your goals are still right and tell us how the week felt."
Page 1 — "Here's what you told us" (built from the answers by fixed sentences, not AI), e.g.:
> You'd like more energy and better sleep. You usually eat 3 meals, lunch around 12:30. You exercise 2 days a week and sit 6–8 hours on workdays. You fall asleep in 15–30 minutes and wake once or twice. Stress: 6/10, mostly work.

Page 2
1. `goals_confirm`* "On day 1 you chose: {goals}. Still what matters most?" — Yes · I'd change them (re-pick up to 3)
2. `week1_pace` How did this first week feel? — Easy · About right · A bit much
3. `week1_note` Anything you'd like us to know before next week? — text or voice, optional

Page 3 — Next week: "Week two is about action: simple, classic habits that work for almost everybody. Try them, and notice how you feel. Your check-ins will show it."

### Day 14 · Your two weeks (~2 min) — `foundation_d14_two_weeks` (does not count toward the review)
Why we ask (intro): "What helped, what was hard, and what you'd like next. Thomas reads it before your call."
Page 1 — "Fourteen days ago you started. Here's where you were, and where you are now." Check-in comparison, first 3 days vs last 3 days: energy, focus, mood, calm, how refreshed you wake (their own values, no score).

Page 2
1. `overall_change` Overall, how do you feel compared with two weeks ago? — Much better · A bit better · About the same · A bit worse · Much worse
2. `actions_helped` Which actions made the biggest difference for you? — the actions they had
3. `actions_hard` Which actions felt hard to fit in? — the actions they had

Page 3
4. `liked_most` What did you like most about these two weeks? — text or voice, optional
5. `didnt_work` What didn't work for you, or felt like too much? — text or voice, optional
6. `app_ease` How easy was the app to use? — slider 0–10

Page 4
7. `next_step` What would you like next? — Keep going with the app · Go deeper with a personal programme · I'm not sure yet, let's talk · Not right now
8. `question_for_thomas` Anything you'd like to ask Thomas before your call? — text or voice, optional

## The 14 days

Actions stack; gold on the card = new today. ✓ = an existing `habit_bank` card (with its faces and FR text).

| Day | Title | New today | Questionnaire | Short read |
|---|---|---|---|---|
| 1 | Your starting point | Morning: A glass of water on waking · Morning: 3 slow breaths at the window · Connect Apple Health · Turn on your reminders | Day 1 · You, today | Why we start with where you are |
| 2 | Nutrition | During the day: Photograph everything you eat | Day 2 · Your nutrition | What your meal photos tell us |
| 3 | Movement | Morning: 1 minute of gentle movement · During the day: Optional: an exercise snack · Evening: 2 minutes of gentle stretching before bed · Book a call with Thomas · 20 min (optional, from today) | Day 3 · Your movement | Little and often |
| 4 | Sleep | Morning: ✓ 5 minutes of daylight · Evening: ✓ Your phone sleeps outside the bedroom | Day 4 · Your sleep | Light sets your body clock |
| 5 | Mental and emotional health | Evening: ✓ Box breathing, 2 minutes in bed · Evening: ✓ One good thing | Day 5 · Your mental and emotional health | The 2-minute downshift |
| 6 | Your first week | After lunch: ✓ 5 minutes outside after lunch | Day 6 · Your first week | Simple actions, repeated |
| 7 | Your full day | Morning: 5-minute morning flow · During the day: One exercise snack a day · Your first-week summary (once Thomas has reviewed it) · Book a call with Thomas · 20 min (if Thomas launched your track) | — | Your day, on one page |
| 8 | Protein first | Morning: ✓ Protein at breakfast · Morning: A 10-minute walk after breakfast | — | Why protein matters |
| 9 | A lunch that holds you | After lunch: ✓ A lunch that holds you · After lunch: ✓ A 10-minute walk after lunch · After lunch: ✓ Last coffee before 14:00 | — | Complex carbs, simply |
| 10 | Easy strength | During the day: 5-minute easy strength routine | — | Muscle is a long-term account |
| 11 | Your evening downshift | Evening: ✓ Last meal 2–3 hours before bed · Evening: ✓ Screens off, lights low: 60 minutes before bed · Evening: A book instead of a screen · Evening: 10 minutes to wind down | — | Your evening routine |
| 12 | More morning movement | Morning: 10-minute morning flow · During the day: Move 2 minutes every hour or two | — | Sitting less |
| 13 | Make it yours | Nothing new · Choose the actions you keep | — | Habits that last |
| 14 | Your two weeks | Nothing new · Book your review call with Thomas · 20 min | Day 14 · Your two weeks | What a personal programme adds |

By moment (first day–last day):

- **Morning:** A glass of water on waking (1–14) · 3 slow breaths at the window (1–6) · 1 minute of gentle movement (3–6) · 5 minutes of daylight (4–14) · 5-minute morning flow (7–11) · Protein at breakfast (8–14) · A 10-minute walk after breakfast (8–14) · 10-minute morning flow (12–14)
- **After lunch:** 5 minutes outside after lunch (6–8) · A lunch that holds you (9–14) · A 10-minute walk after lunch (9–14) · Last coffee before 14:00 (9–14)
- **Evening:** 2 minutes of gentle stretching before bed (3–10) · Your phone sleeps outside the bedroom (4–14) · Box breathing, 2 minutes in bed (5–10) · One good thing (5–14) · Last meal 2–3 hours before bed (11–14) · Screens off, lights low: 60 minutes before bed (11–14) · A book instead of a screen (11–14) · 10 minutes to wind down (11–14)
- **During the day:** Photograph everything you eat (2–14) · Optional: an exercise snack (3–6) · One exercise snack a day (7–9) · 5-minute easy strength routine (10–14) · Move 2 minutes every hour or two (12–14)

### Card text, days 1–7: the pillars

**Day 1 · Your starting point** — Where you are, where you're going
- *What it is:* Your Foundation Track: 14 days, one card a day. Week 1 helps us understand you, one pillar a day. Week 2 is about action.
- *Why it matters:* Lasting change starts from where you really are, not from a perfect plan. Knowing your starting point and where you want to go lets everything after fit you.
- *How we use it:* Your answers and check-ins shape your week-2 actions, your first-week summary on day 7 and your review call with Thomas on day 14.
- *Why we ask:* Your goals, your usual week and your rhythm. This is your starting point: everything after builds on it, so there are no wrong answers. Don't change anything yet.
- *First thing to try · a mini morning routine:* A glass of water on waking; 3 slow breaths at the window
- *Mini tip:* Put a glass of water by your bed tonight, so tomorrow's first step is already waiting.
- *How it will evolve:* Tomorrow: Photograph what you eat. That habit runs all 14 days. · Day 3: 1 minute of movement joins your morning, and your evening routine begins. · Day 7: Your full day: a 5-minute morning flow and a daily exercise snack.

**Day 2 · Nutrition** — Pillar 1 · Nutrition
- *What it is:* What you eat, when, and how much: the material your body builds and repairs with, and the fuel for your energy.
- *Why it matters:* Food shapes your energy, hunger, mood, sleep and recovery. Small changes in what and when you eat often make a big difference.
- *How we use it:* Your answers and your meal photos show your real pattern. From them we choose the changes that will help you most, with ideas from foods you already eat.
- *Why we ask:* How many meals, when, who cooks, which proteins you like, what you drink. It shows your real pattern before we change anything, and which ideas fit your kitchen.
- *First thing to try · one habit for all 14 days:* Photograph everything you eat
- *Mini tip:* Photograph before the first bite, drinks and snacks included. A quick photo beats a perfect one.
- *How it will evolve:* Tomorrow: Your morning grows with 1 minute of movement, and your evening routine begins. · Day 4: Daylight in the morning, your phone out of the bedroom. · Days 8–9: Breakfast and lunch become the focus, built from your photos.

**Day 3 · Movement** — Pillar 2 · Movement
- *What it is:* Not sport: your functional capacity. How easily your body does what your life asks of it: getting up, carrying, climbing stairs, hiking.
- *Why it matters:* Capacity is built or lost by what you do every day. Long hours of sitting slowly take it away; small, regular movement keeps it and builds it.
- *How we use it:* Your answers set the right starting level for you and keep every movement we suggest safe. We start with little and often.
- *Why we ask:* How you move now, how you moved before, and whether anything hurts. It sets the right starting level for you, instead of the same workout for everyone, and keeps it safe.
- *First thing to try · your morning grows, your evening begins:* 1 minute of gentle movement; Optional: an exercise snack; 2 minutes of gentle stretching before bed
- *Mini tip:* No time for an exercise snack? Take the stairs once. That counts.
- *How it will evolve:* Tomorrow: 5 minutes of daylight; your phone sleeps outside the bedroom. · Day 7: Your minute of movement becomes a 5-minute flow, and the exercise snack becomes daily. · Days 10–12: Easy strength, then a 10-minute morning flow.
- *Library:* Lesson · Exercise snacks: small signals that add up (in the library)

**Day 4 · Sleep** — Pillar 3 · Sleep
- *What it is:* The time your body repairs, your brain sorts the day and your rhythm resets.
- *Why it matters:* After a poor night, hunger is louder, cravings stronger, mood shorter and effort harder. Regular times and light set your body clock.
- *How we use it:* Your usual pattern tells us where to start, and your times decide when your reminders arrive. Your morning check-in records each night.
- *Why we ask:* Your usual nights, not last night: bedtime, how long you take to fall asleep, what wakes you, how rested you feel. Your times also set when your reminders arrive.
- *First thing to try · one for the morning, one for the night:* 5 minutes of daylight; Your phone sleeps outside the bedroom
- *Mini tip:* No time to go outside? Have your coffee at the brightest window.
- *How it will evolve:* Tomorrow: Box breathing and one good thing join your evening. · Day 11: Your full evening routine: last meal earlier, screens off, a book, 10 minutes to wind down.

**Day 5 · Mental and emotional health** — Pillar 4 · Mental and emotional health
- *What it is:* The load you carry, from work, family, health or big changes, and how well you recover from it.
- *Why it matters:* When the load stays high, it shows up in your sleep, appetite, energy, digestion and mood. Recovery is what brings your body back to calm.
- *How we use it:* Knowing where your load comes from and what already helps you lets us suggest tools that fit your life, instead of adding pressure.
- *Why we ask:* How stressed you've felt, where it comes from, your mood and what helps you switch off. Answer only what you're comfortable with: it helps us suggest tools that fit your life.
- *First thing to try · your evening grows:* Box breathing, 2 minutes in bed; One good thing
- *Mini tip:* If four counts feel long, breathe in threes. The rhythm matters more than the number.
- *How it will evolve:* Tomorrow: A short walk after lunch: your routine now covers the whole day. · Day 11: Your 2 minutes of breathing grow into 10 minutes: breathing, NSDR or gentle yoga.

**Day 6 · Your first week** — Recap
- *Today:* Six days, four pillars: nutrition, movement, sleep, and your mental and emotional health. You've told us where you are and where you want to go, and you've built a small routine without really noticing. Here it is, in the four moments of your day. One new moment today: after lunch.
- *Why we ask:* Check your goals are still right and tell us how the week felt.
- *New today · after lunch:* 5 minutes outside after lunch
- *Mini tip:* Put your walking shoes by the door before lunch.
- *How it will evolve:* Tomorrow: A 5-minute morning flow and one exercise snack a day. · Week 2: One focus a day: breakfast, lunch, strength, evening, morning. · Day 13: You choose what you keep.

**Day 7 · Your full day** — Everything together
- *Today:* One week. Today everything comes together in one full day, with a little more movement: your minute in the morning becomes a 5-minute flow inspired by qi gong, and the exercise snack becomes daily. Thomas is reviewing your first week; your summary appears here once he has read it.
- *New today · a little more movement:* 5-minute morning flow; One exercise snack a day
- *Mini tip:* Link the new to the old: your flow right after your glass of water.
- *How it will evolve:* Day 8: Breakfast: protein first. · Day 9: Lunch, and a 10-minute walk after it. · Day 10: Your exercise snack becomes a strength routine. · Days 11–12: Your full evening, then a longer morning flow.

### Card text, days 8–14

**Day 8 · Protein first**
- *Today:* Protein is your body's building material: muscle, bones, skin, your immune system. Your body can't store it the way it stores fat or sugar, so it needs some regularly across the day, and more as we age to keep our muscle. Many people eat little in the morning and most at night. Today, protein moves to breakfast.
- *New today:* Protein at breakfast; A 10-minute walk after breakfast
- *Mini tip:* Boil a few eggs for the week, or keep Greek yogurt in the fridge: breakfast protein in one minute.
- *How it will evolve:* Tomorrow: Lunch: protein, vegetables, complex carbs, and your after-lunch walk doubles to 10 minutes. · Day 10: Easy strength.
- *Library:* Infographic · Protein through the day (to create: today's image, also filed in the library)

**Day 9 · A lunch that holds you**
- *Today:* Lunch decides your afternoon. Fast carbs (white bread, white pasta, sweet drinks) often mean a quick rise and a dip around three. Build your plate in three parts: half vegetables, a palm of protein, a quarter complex carbs. Complex carbs come with fibre, so they give steadier energy. Then the most important part: a 10-minute walk.
- *New today:* A lunch that holds you; A 10-minute walk after lunch; Last coffee before 14:00
- *Mini tip:* Lunch out? Ask for extra vegetables and choose the whole-grain side.
- *How it will evolve:* Tomorrow: Your exercise snack becomes a 5-minute strength routine. · Day 11: Your full evening routine.
- *Library:* Infographic · The plate that holds you (to create: today's image, also filed in the library)
- *Still to make:* Short read 'Complex carbs, simply': to write, and file in the library next to the infographic.

**Day 10 · Easy strength**
- *Today:* Muscle is one of the best long-term investments you can make: it holds you up, protects your joints, helps your body handle sugar and keeps you independent as you age. Your exercise snack becomes a 5-minute routine, at home, no equipment. Go slowly and stop if anything hurts: easier is always fine.
- *New today:* 5-minute easy strength routine
- *Mini tip:* Do your routine while the kettle boils or the coffee runs.
- *How it will evolve:* Tomorrow: Your full evening routine. · Day 12: Your morning flow grows to 10 minutes.
- *Still to make:* The routine itself: Thomas develops it (moves, reps, easier and harder versions), then films it for today's video. Until then the card says 'Thomas shows every move in today's video'.

**Day 11 · Your evening downshift**
- *Today:* Tonight your evening routine is complete. Last meal 2–3 hours before bed, so your body can rest rather than digest. An hour before bed: screens off, lights low, a book instead of the phone. Then 10 minutes to wind down: slow breathing, NSDR or gentle yoga. Your stretch and box breathing grow into this.
- *New today · the full routine:* Last meal 2–3 hours before bed; Screens off, lights low: 60 minutes before bed; A book instead of a screen; 10 minutes to wind down
- *Mini tip:* Set an alarm for 'screens off', and choose tonight's book now.
- *How it will evolve:* Tomorrow: Your morning flow grows to 10 minutes, with short movement breaks. · Day 13: You choose what you keep.
- *Library:* Audio · 10-minute NSDR (to record)

**Day 12 · More morning movement**
- *Today:* Moving early wakes your body, gets your circulation going and, outside, gives you daylight for your body clock. And what's done first thing gets done. Your flow grows from five to ten minutes. During the day, if you sit for long, stand up every hour or two and move for two minutes.
- *New today:* 10-minute morning flow; Move 2 minutes every hour or two
- *Mini tip:* Stand up whenever you take a call.
- *How it will evolve:* Tomorrow: Nothing new: you choose what you keep. · Day 14: Your two weeks, and your 20-minute review call.

**Day 13 · Make it yours**
- *Today:* Look at what you've built in twelve days. There's nothing new today: choose the actions you want to keep after these two weeks. They stay in your app. A few habits you keep are worth more than ten you try once.
- *New today:* nothing new
- *Mini tip:* Keep the ones you'd miss, not the ones you think you should.
- *How it will evolve:* Tomorrow: Your two weeks: before and after, and your review call. · After day 14: The actions you keep stay in your app.

**Day 14 · Your two weeks**
- *Today:* Two weeks ago you started. Today you see your check-ins from your first days next to your last days, tell us how it was, and book your 20-minute review call with Thomas once it's open to you.
- *Why we ask:* What helped, what was hard, and what you'd like next. Thomas reads it before your call.
- *New today:* nothing new
- *Mini tip:* Write down one question for Thomas before your call.
- *How it will evolve:* Next: Keep going with the app, or go deeper with a personal programme. You decide together on your call.

## Reminders (EN; FR with the scripts)

Times: morning = wake time + 15 min · after lunch = lunch time + 45 min · evening = 45 min before bedtime
(defaults 07:15 · 13:15 · 21:30; existing quiet hours 22:00–07:30 apply). At most three a day; the evening one
replaces the usual check-in reminder during the track.

| Day | Morning | After lunch | Evening |
|---|---|---|---|
| 1 | — | — | First day done? Your 3-minute questionnaire, if not yet, then your evening check-in. |
| 2 | Day 2 · Nutrition. Water, 3 slow breaths, then today's video. | Snap your lunch before the first bite. | Snap your dinner. Then your nutrition questions: 2 minutes. |
| 3 | Day 3 · Movement. Water, 3 breaths, 1 minute of moving. | Feel like an exercise snack? 10 squats, or a minute up the stairs. | Your movement questions, then 2 minutes of stretching before bed. |
| 4 | Day 4 · Sleep. Your morning routine, then 5 minutes of daylight. | Snap your lunch. | Your phone sleeps outside the bedroom tonight. Your sleep questions: 2 minutes. |
| 5 | Day 5 · Mental and emotional health. Water, breaths, move, daylight. | Snap your lunch. | In bed: 2 minutes of box breathing, then one good thing. Last questionnaire today. |
| 6 | Day 6 · Your first week, on one page. | New today: 5 minutes outside after lunch. | Stretch, phone out, breathe, one good thing. |
| 7 | Day 7 · Your full day starts with a 5-minute morning flow. | Your walk after lunch. And today's exercise snack? | Stretch, phone out, breathe, one good thing. Your week-1 summary is on its way. |
| 8 | Day 8 · Protein at breakfast, then a 10-minute walk. | Your walk after lunch. | Your evening routine, then your check-in. |
| 9 | Day 9 · Today's focus is lunch: vegetables, protein, complex carbs. | 10 minutes of walking, now. Last coffee before 14:00. | Your evening routine, then your check-in. |
| 10 | Day 10 · Easy strength: your 5-minute routine is in today's video. | Walk after lunch. Strength routine done yet? | Your evening routine, then your check-in. |
| 11 | Day 11 · Tonight: your full evening routine. | Your walk after lunch. | Screens off, lights low. A book, then 10 minutes to wind down. |
| 12 | Day 12 · Your morning flow grows to 10 minutes. | Walk after lunch. Every hour or two: stand up and move for 2 minutes. | Where you stand: {modules}/{modules_total} questionnaires, {pct}% of meals. 2 days to go. |
| 13 | Day 13 · Your whole routine, on one page. Which actions will you keep? | Your walk after lunch. | Your evening routine, then your check-in. |
| 14 | Day 14 · Two weeks. See how far you've come, and tell us how it was. | — | Your 20-minute review call with Thomas is ready to book. *(only if unlocked)* |

## Motion videos (EN voiceover; FR once the EN is locked)

Thomas, 2026-10-11: motion design with an AI voice instead of filmed talking-head videos. Pillar days (1–5) run
about 40 seconds, the other days 20 to 30. The card carries the detail, so each video keeps to one idea. The
storyboards, with timings, are in `docs/foundation-cards/build.py` (`VIDEOS`) and on the published card mockups.

Series style: Motion design, no presenter. 9:16 vertical master, 1080 × 1920; the card shows a tile and the film opens full screen. Keep titles and key visuals inside the centre square so the card's tile and a 1:1 or 4:5 crop for social posts work. Same look as the infographics: flat vector, rounded figures without detailed faces, forest #2E5438 and soft green #4A8A5C on cream #F5F0E8, charcoal #1A1A16 for text, gold #D4A84E only for the day's NEW action. The Alpine ridge line runs along the bottom of every frame. On-screen text is short (max 6 words) and doubles as captions for muted viewing; add full subtitles from the voiceover. Open on a small 'Day N' tag, close on a 2-second end card with the day's title. Calm, warm AI voice (EN first, FR once the EN is locked), soft music bed, gentle eased motion, no fast cuts.

### Day 1 · Your starting point (about 40 s)

Voiceover:
> Welcome to your Foundation Track.
> Fourteen days. One card a day.
> Lasting change doesn't start with a perfect plan. It starts with knowing where you are, and where you want to go.
> This first week, we look at four pillars, one a day: nutrition, movement, sleep, and your mental and emotional health.
> Don't change anything yet. Just answer honestly. Your answers shape everything that follows.
> Your first thing to try: tomorrow morning, a glass of water, then three slow breaths at the window.
> Small steps. Let's begin.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Welcome to your Foundation Track. | Your Foundation Track | The Alpine ridge line draws itself across the frame; the title fades in above it. |
| 0:02–0:06 | Fourteen days. One card a day. | 14 days · 1 card a day | Fourteen small stones appear one by one along a path winding up the ridge. |
| 0:06–0:14 | Lasting change doesn't start with a perfect plan. It starts with knowing where you are, and where you want to go. | Where you are → where you're going | A small figure stands at a trailhead; a dotted line draws from it up to a summit flag. |
| 0:14–0:24 | This first week, we look at four pillars, one a day: nutrition, movement, sleep, and your mental and emotional health. | 4 pillars · 1 a day | Four icons pop onto the path, each with its label: a plate, a walking figure, a moon, a gentle wave. |
| 0:24–0:30 | Don't change anything yet. Just answer honestly. Your answers shape everything that follows. | No changes yet · honest answers | A short questionnaire card fills with ticks; soft lines flow from it into the path ahead. |
| 0:30–0:38 | Your first thing to try: tomorrow morning, a glass of water, then three slow breaths at the window. | First thing to try | A window at sunrise; a glass fills with water, then three breath curls rise. Both in gold. |
| 0:38–0:40 | Small steps. Let's begin. | Day 1 · Your starting point | The figure takes its first step onto stone 1. End card. |

### Day 2 · Nutrition (about 39 s)

Voiceover:
> Pillar one: nutrition.
> Food is the material your body builds and repairs with, and the fuel for your energy.
> It shapes your hunger, your mood and your sleep.
> We don't start with a diet. We start with how you really eat.
> Today's questions ask how many meals, when, who cooks, and which proteins you like. Together, they show your real pattern.
> And one habit for all fourteen days: photograph everything you eat, before the first bite.
> Not to judge. To see.
> Tomorrow: movement.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Pillar one: nutrition. | Pillar 1 · Nutrition | The plate icon grows to the centre; the label slides in. |
| 0:02–0:09 | Food is the material your body builds and repairs with, and the fuel for your energy. | Build · repair · fuel | Food shapes flow into a simple body outline, which fills with a soft glow and an energy bar. |
| 0:09–0:13 | It shapes your hunger, your mood and your sleep. | Hunger · mood · sleep | Three small dials around the figure turn gently. |
| 0:13–0:19 | We don't start with a diet. We start with how you really eat. | Not a diet · your real plate | A strict diet sheet folds away; an everyday plate slides in. |
| 0:19–0:28 | Today's questions ask how many meals, when, who cooks, and which proteins you like. Together, they show your real pattern. | Why we ask: your real pattern | Four question chips (meals, times, who cooks, protein) snap into a weekly grid. |
| 0:28–0:34 | And one habit for all fourteen days: photograph everything you eat, before the first bite. | Photograph every meal | A phone frames a plate; a gold shutter flash; the photo drops into a 14-day strip. |
| 0:34–0:37 | Not to judge. To see. | Not to judge · to see | The photos tile into a timeline with small tags: time, portion, protein, variety. |
| 0:37–0:39 | Tomorrow: movement. | Day 2 · Nutrition | End card. |

### Day 3 · Movement (about 43 s)

Voiceover:
> Pillar two: movement.
> Not sport. Functional capacity: how easily your body does what your life asks of it.
> Getting up. Carrying the shopping. Climbing stairs. Hiking when you're seventy.
> Every day builds it, or slowly takes it away. Long sitting takes it away. Little and often builds it.
> Today's questions set your starting level, and keep everything safe.
> Your morning grows: one minute of gentle movement.
> If you like, an exercise snack: ten squats, or a minute of stairs.
> And tonight, your evening routine begins: two minutes of gentle stretching.
> Tomorrow: sleep.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Pillar two: movement. | Pillar 2 · Movement | The walking-figure icon grows to the centre. |
| 0:02–0:08 | Not sport. Functional capacity: how easily your body does what your life asks of it. | Functional capacity | The figure moves through a simple day: no gym, just life. |
| 0:08–0:14 | Getting up. Carrying the shopping. Climbing stairs. Hiking when you're seventy. | Get up · carry · climb · hike | Four quick vignettes: rising from the floor, carrying bags, taking stairs, an older hiker on a ridge trail. |
| 0:14–0:22 | Every day builds it, or slowly takes it away. Long sitting takes it away. Little and often builds it. | Little and often | A capacity bar drains while the figure sits at a desk, then refills with small movement icons. |
| 0:22–0:26 | Today's questions set your starting level, and keep everything safe. | Why we ask: your level, safely | A level slider settles at the figure's mark; a small shield icon appears. |
| 0:26–0:30 | Your morning grows: one minute of gentle movement. | Morning · 1 minute | Shoulder rolls, hip circles, slow squats, looping, in gold. |
| 0:30–0:36 | If you like, an exercise snack: ten squats, or a minute of stairs. | Optional · exercise snack | A short squat loop with '×10', then a stair icon. |
| 0:36–0:41 | And tonight, your evening routine begins: two minutes of gentle stretching. | Evening · 2-minute stretch | Dusk falls; the figure stretches on a mat, in gold. |
| 0:41–0:43 | Tomorrow: sleep. | Day 3 · Movement | End card, with a small phone icon: 'Call with Thomas · 20 min · open from today'. |

### Day 4 · Sleep (about 44 s)

Voiceover:
> Pillar three: sleep.
> Sleep is when your body repairs, your brain sorts the day, and your rhythm resets.
> After a poor night, hunger is louder, cravings are stronger, and everything feels harder.
> Two things set your body clock: regular times, and light. Morning light sets it. Bright screens at night push it back.
> Today's questions are about your usual nights, not last night. Your times also decide when your reminders arrive.
> Two small things. In the morning, five minutes of daylight.
> And tonight, your phone sleeps outside the bedroom.
> Tomorrow: your mental and emotional health.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Pillar three: sleep. | Pillar 3 · Sleep | The moon icon grows to the centre; the sky darkens. |
| 0:02–0:08 | Sleep is when your body repairs, your brain sorts the day, and your rhythm resets. | Repair · sort · reset | Night scene: muscles glow softly, thought bubbles file into folders, a small clock resets. |
| 0:08–0:14 | After a poor night, hunger is louder, cravings are stronger, and everything feels harder. | After a poor night | Next morning: the hunger bubble grows, snack icons crowd in, the figure walks more heavily. |
| 0:14–0:24 | Two things set your body clock: regular times, and light. Morning light sets it. Bright screens at night push it back. | Regular times + light | A 24-hour ring: the morning sun sets the hand; a bright phone at night drags it later. |
| 0:24–0:32 | Today's questions are about your usual nights, not last night. Your times also decide when your reminders arrive. | Why we ask: your usual nights | A week of moon icons; a small bell slides into place on the ring. |
| 0:32–0:36 | Two small things. In the morning, five minutes of daylight. | Morning · 5 min daylight | The figure at an open window, sun rays in gold. |
| 0:36–0:40 | And tonight, your phone sleeps outside the bedroom. | Night · phone outside | The phone charges on a shelf outside the bedroom; the door closes softly. Gold on the phone. |
| 0:40–0:44 | Tomorrow: your mental and emotional health. | Day 4 · Sleep | End card. |

### Day 5 · Mental and emotional health (about 44 s)

Voiceover:
> Pillar four: your mental and emotional health.
> We all carry a load: work, family, health, big changes.
> When it stays high, it shows up everywhere: in your sleep, your appetite, your energy, your mood.
> What matters is the balance: the load, and how well you recover.
> Today's questions ask where your load comes from, and what already helps you switch off. Answer only what feels comfortable.
> Tonight, in bed: two minutes of box breathing. In four, hold four, out four, hold four.
> Then, one good thing from your day.
> Tomorrow: your first week, on one page.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:04 | Pillar four: your mental and emotional health. | Pillar 4 · Mental and emotional health | The wave icon grows to the centre and settles. |
| 0:04–0:08 | We all carry a load: work, family, health, big changes. | The load you carry | A figure with a backpack; small icons drop into it one by one. |
| 0:08–0:16 | When it stays high, it shows up everywhere: in your sleep, your appetite, your energy, your mood. | Sleep · appetite · energy · mood | Ripples spread from the backpack to four icons around the figure. |
| 0:16–0:21 | What matters is the balance: the load, and how well you recover. | Load ⇄ recovery | A balance: the backpack on one side, recovery icons (a walk, a breath, people) on the other; it levels. |
| 0:21–0:30 | Today's questions ask where your load comes from, and what already helps you switch off. Answer only what feels comfortable. | Why we ask: tools that fit you | Question chips appear; one carries a small 'skip' mark. |
| 0:30–0:37 | Tonight, in bed: two minutes of box breathing. In four, hold four, out four, hold four. | Box breathing · 2 min | A dot travels around a square; each side lights with its count. Gold. |
| 0:37–0:40 | Then, one good thing from your day. | One good thing | A small star lights up above the bed. Gold. |
| 0:40–0:44 | Tomorrow: your first week, on one page. | Day 5 · Mental and emotional health | End card. |

### Day 6 · Your first week (about 28 s)

Voiceover:
> Six days. Four pillars. And a routine you built almost without noticing.
> In the morning: water, three breaths, a minute of movement, daylight.
> During the day: your meal photos.
> In the evening: stretch, phone out, breathe, one good thing.
> Today, one new moment: after lunch, five minutes outside.
> One minute of questions to check your goals. Tomorrow, it all comes together.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:06 | Six days. Four pillars. And a routine you built almost without noticing. | Your first week | The four pillar icons slide down into one day timeline with four moments. |
| 0:06–0:10 | In the morning: water, three breaths, a minute of movement, daylight. | Morning | Four small icons pop into the morning segment. |
| 0:10–0:14 | During the day: your meal photos. | During the day | A camera icon fills its segment. |
| 0:14–0:18 | In the evening: stretch, phone out, breathe, one good thing. | Evening | Four icons pop into the evening segment. |
| 0:18–0:22 | Today, one new moment: after lunch, five minutes outside. | New · 5 min outside after lunch | The empty after-lunch slot lights up with a walking figure in gold. |
| 0:22–0:28 | One minute of questions to check your goals. Tomorrow, it all comes together. | Day 6 · Your first week | The full timeline glows. End card. |

### Day 7 · Your full day (about 30 s)

Voiceover:
> One week. Today, your full day.
> Your minute of morning movement becomes a five-minute flow, inspired by qi gong: breathe, move, twist, shake it out.
> And one exercise snack a day: ten squats, a minute of stairs, or ten wall push-ups. Small bursts that add up.
> That's your base, and it fits in a normal day.
> Thomas is reviewing your first week. Your summary will be here soon.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:03 | One week. Today, your full day. | Your full day | The day timeline from day 6, now complete. |
| 0:03–0:12 | Your minute of morning movement becomes a five-minute flow, inspired by qi gong: breathe, move, twist, shake it out. | Morning flow · 5 min | A flowing figure moves through four poses, each melting into the next. Gold. |
| 0:12–0:20 | And one exercise snack a day: ten squats, a minute of stairs, or ten wall push-ups. Small bursts that add up. | 1 exercise snack a day | Three tiny loops; a bar fills a notch with each burst. Gold. |
| 0:20–0:25 | That's your base, and it fits in a normal day. | Your base | All four moments of the day light up together. |
| 0:25–0:30 | Thomas is reviewing your first week. Your summary will be here soon. | Day 7 · Your summary is coming | A summary card slides into a phone frame with a tick. End card. |

### Day 8 · Protein first (about 32 s)

Voiceover:
> Week two starts with breakfast.
> Protein is your body's building material: muscle, bones, skin, your immune system.
> Your body can't store it the way it stores fat or sugar, so it needs some across the day, and a little more as we age.
> Many people eat little in the morning. Today, move some to breakfast: eggs, Greek yogurt, cottage cheese, salmon or tofu. About a palm.
> Then, a ten-minute walk.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Week two starts with breakfast. | Week 2 · Protein first | A breakfast table at sunrise. |
| 0:02–0:08 | Protein is your body's building material: muscle, bones, skin, your immune system. | Your building material | Small blocks assemble into a body outline. |
| 0:08–0:20 | Your body can't store it the way it stores fat or sugar, so it needs some across the day, and a little more as we age. | Every meal · more with age | Three equal protein blocks line up over breakfast, lunch and dinner. |
| 0:20–0:30 | Many people eat little in the morning. Today, move some to breakfast: eggs, Greek yogurt, cottage cheese, salmon or tofu. About a palm. | Breakfast · about a palm | The breakfast block grows, in gold; five options orbit the plate; a palm icon beside it. |
| 0:30–0:32 | Then, a ten-minute walk. | Day 8 · + 10-min walk | The figure leaves the table and walks into daylight. End card. |

### Day 9 · A lunch that holds you (about 27 s)

Voiceover:
> Lunch decides your afternoon.
> Fast carbs often mean a quick rise, then a dip around three.
> Build your plate in three parts: half vegetables, a palm of protein, and a quarter complex carbs, like oats, whole grains or legumes.
> Their fibre means steadier energy.
> Then the most important part: a ten-minute walk.
> And your last coffee, before two.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Lunch decides your afternoon. | A lunch that holds you | A clock moves from noon into the afternoon. |
| 0:02–0:08 | Fast carbs often mean a quick rise, then a dip around three. | Fast carbs: rise, then dip | An energy line spikes, then drops as the clock reaches 15:00. |
| 0:08–0:18 | Build your plate in three parts: half vegetables, a palm of protein, and a quarter complex carbs, like oats, whole grains or legumes. | ½ veg · ¼ protein · ¼ complex carbs | A plate fills section by section, with small icons in the complex-carbs quarter. |
| 0:18–0:20 | Their fibre means steadier energy. | Steadier energy | The energy line softens into a gentle wave. |
| 0:20–0:24 | Then the most important part: a ten-minute walk. | 10-min walk after lunch | A large walking figure in gold; the wave stays even. |
| 0:24–0:27 | And your last coffee, before two. | Day 9 · Coffee before 14:00 | A cup beside a clock at 14:00. End card. |

### Day 10 · Easy strength (about 29 s)

Voiceover:
> Muscle is a long-term investment.
> It holds you up, protects your joints, helps your body handle sugar, and keeps you independent as you age.
> And it starts simply. Your exercise snack becomes a five-minute routine. At home, no equipment.
> [Thomas's routine: one short line per move, with its count.]
> Go slowly. Stop if anything hurts. Easier is always fine.
> Often beats hard.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Muscle is a long-term investment. | Easy strength | A single muscle icon, then a slowly rising line over years. |
| 0:02–0:11 | It holds you up, protects your joints, helps your body handle sugar, and keeps you independent as you age. | Hold · protect · handle sugar · stay independent | One figure through the years, still carrying, climbing, getting up. |
| 0:11–0:18 | And it starts simply. Your exercise snack becomes a five-minute routine. At home, no equipment. | 5 min · at home · no equipment | A living room; a timer ring set to 5:00. |
| 0:18–0:22 | [Thomas's routine: one short line per move, with its count.] | [move · count] | Each move as a looping pose with its count, one after another (from Thomas's routine). |
| 0:22–0:27 | Go slowly. Stop if anything hurts. Easier is always fine. | Easier is fine | The same pose next to its easier version. |
| 0:27–0:29 | Often beats hard. | Day 10 · Easy strength | End card. |

### Day 11 · Your evening downshift (about 32 s)

Voiceover:
> Tonight, your full evening routine.
> Two to three hours before bed: your last meal, so your body can rest instead of digest.
> One hour before: screens off, lights low. Bright screens tell your brain it's still day.
> Pick up a book instead.
> Then, ten minutes to wind down: slow breathing, NSDR, or gentle yoga.
> And last thing, one good thing from your day.
> Start with what's easiest. Add the rest.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Tonight, your full evening routine. | Your evening downshift | An evening timeline from dinner to sleep, the sky shifting from warm to dark. |
| 0:02–0:10 | Two to three hours before bed: your last meal, so your body can rest instead of digest. | Last meal · 2–3 h before bed | A plate on the timeline at −3 h to −2 h. Gold. |
| 0:10–0:17 | One hour before: screens off, lights low. Bright screens tell your brain it's still day. | −60 min · screens off, lights low | A phone switches off, a lamp dims. Gold. |
| 0:17–0:20 | Pick up a book instead. | A book | An open book on the sofa. Gold. |
| 0:20–0:25 | Then, ten minutes to wind down: slow breathing, NSDR, or gentle yoga. | 10 min · breathe · NSDR · yoga | Three small choices; the figure lies down and the scene softens. Gold. |
| 0:25–0:29 | And last thing, one good thing from your day. | One good thing | A small star above the bed. |
| 0:29–0:32 | Start with what's easiest. Add the rest. | Day 11 · Your evening downshift | End card. |

### Day 12 · More morning movement (about 30 s)

Voiceover:
> Your morning flow grows to ten minutes.
> Moving early wakes your body, warms you up and, outside, gives you daylight for your body clock.
> And what's done first thing gets done.
> Same movements, a little longer: breathe, move, twist, shake out.
> During the day, if you sit for long, stand up every hour or two and move for two minutes.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:04 | Your morning flow grows to ten minutes. | Morning flow · 10 min | The flow timer stretches from 5 to 10. Gold. |
| 0:04–0:11 | Moving early wakes your body, warms you up and, outside, gives you daylight for your body clock. | Wake · warm · light | The figure moves outside; the 24-hour ring sets at morning. |
| 0:11–0:14 | And what's done first thing gets done. | First thing = done | A tick lands on the morning slot. |
| 0:14–0:19 | Same movements, a little longer: breathe, move, twist, shake out. | Breathe · move · twist · shake out | The four flow poses in sequence. |
| 0:19–0:28 | During the day, if you sit for long, stand up every hour or two and move for two minutes. | Every 1–2 h · move 2 min | A workday line from 9:00 to 18:00 with small gold markers: stand, stairs, walk on a call. |
| 0:28–0:30 | (end card) | Day 12 · More morning movement | End card. |

### Day 13 · Make it yours (about 22 s)

Voiceover:
> Look at what you've built in twelve days.
> You don't need to keep everything. A few habits you keep beat ten you try once.
> Today, nothing new. Choose the actions you want to keep: the ones that felt good, and fit your life.
> They stay in your app.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:04 | Look at what you've built in twelve days. | Make it yours | Every action icon fills the four moments of the day. |
| 0:04–0:11 | You don't need to keep everything. A few habits you keep beat ten you try once. | Keep a few | Most icons fade; a few stay bright. |
| 0:11–0:20 | Today, nothing new. Choose the actions you want to keep: the ones that felt good, and fit your life. | Choose what you keep | Gold ticks land on the chosen cards. |
| 0:20–0:22 | They stay in your app. | Day 13 · Make it yours | The chosen cards fly into a phone. End card. |

### Day 14 · Your two weeks (about 28 s)

Voiceover:
> Fourteen days. Thank you.
> Today, see your first days next to your last: energy, focus, mood, sleep.
> What changed, and what didn't. Both tell us something.
> Tell us how it was, in two minutes.
> And if it's open to you, book your twenty-minute review call with Thomas: your results, your questions, and what comes next.

| Time | Voice | On screen | Animation |
|---|---|---|---|
| 0:00–0:02 | Fourteen days. Thank you. | Your two weeks | The path from day 1: all fourteen stones lit, up to the summit flag. |
| 0:02–0:08 | Today, see your first days next to your last: energy, focus, mood, sleep. | First days · last days | Four pairs of bars grow side by side (shapes only, no numbers). |
| 0:08–0:12 | What changed, and what didn't. Both tell us something. | Both count | The bars settle; a small magnifier passes over them. |
| 0:12–0:16 | Tell us how it was, in two minutes. | 2-minute questionnaire | A short questionnaire card fills. |
| 0:16–0:26 | And if it's open to you, book your twenty-minute review call with Thomas: your results, your questions, and what comes next. | Review call with Thomas · 20 min | A phone icon in gold; the path forks: 'keep going with the app' and 'a personal programme'. |
| 0:26–0:28 | (end card) | Day 14 · Your two weeks | End card. |
