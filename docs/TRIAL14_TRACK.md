# The 14-day track — content source of truth

Status: **agreed with Thomas 2026-10-06, EN text for review; FR to follow once the EN is locked.**
Seeds `track_day`, `track_questionnaire`, `track_question` (migration `supabase/migrations/20261006_trial14_track.sql`).

## Decisions (Thomas, 2026-10-05/06)

- **Fixed and automatic.** The free trial is the same for everyone; real personalisation is for paying members. A
  "mini personalisation" picks variants by rule (below), never by hand. Every NEW member, paying or not, starts this
  track as their soft start in the app. The 34 members who existed before launch keep what they have.
- **Clock:** starts at first app open, 14 days. Day 15: the app stays open; Thomas decides each case.
- **Everything in the app is open from day 1.** What steps up is the daily action.
- **Review call (day 14)** unlocks with all 5 modules (days 1–5) + ≥ 80 % of expected meals
  (expected = the day-2 meals-per-day answer × days). Thomas can open it for anyone.
- **Day-3 call:** an optional 15-minute booking, available from day 3.
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

### Day 1 · You, today (~3 min) — `trial14_d1_you_today`
Intro: "This first week is about understanding you. Don't change anything yet: the more real your answers, the more useful the next steps."

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

Done: "Today: photograph everything you eat. Tomorrow: how you eat."

### Day 2 · How you eat (~2 min) — `trial14_d2_how_you_eat`
Intro: "Not what a perfect diet looks like: how you really eat. Keep photographing your meals as usual."

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

### Day 3 · How you move (~2 min) — `trial14_d3_how_you_move`
Intro: "How your body moves now, and how it moved before. This sets the right starting point instead of the same workout for everyone."

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

### Day 4 · How you sleep (~2 min) — `trial14_d4_how_you_sleep`
Intro: "Sleep shapes your energy, appetite, mood and recovery. Today: your usual pattern, not last night."

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

### Day 5 · Stress and recovery (~2 min) — `trial14_d5_stress_recovery`
Intro: "Stress changes sleep, eating, energy and digestion. Today: where your load comes from, and what helps you recover."

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

### Day 6 · Your first week (~1 min) — `trial14_d6_first_week` (does not count toward the review)
Page 1 — "Here's what you told us" (built from the answers by fixed sentences, not AI), e.g.:
> You'd like more energy and better sleep. You usually eat 3 meals, lunch around 12:30. You exercise 2 days a week and sit 6–8 hours on workdays. You fall asleep in 15–30 minutes and wake once or twice. Stress: 6/10, mostly work.

Page 2
1. `goals_confirm`* "On day 1 you chose: {goals}. Still what matters most?" — Yes · I'd change them (re-pick up to 3)
2. `week1_pace` How did this first week feel? — Easy · About right · A bit much
3. `week1_note` Anything you'd like us to know before next week? — text or voice, optional

Page 3 — Next week: "Week two is about action: simple, classic habits that work for almost everybody. Try them, and notice how you feel. Your check-ins will show it."

### Day 14 · Your two weeks (~2 min) — `trial14_d14_two_weeks` (does not count toward the review)
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

Actions stack. ✓ = an existing `habit_bank` card (with its easy / further faces and FR text).

| Day | Title | New today | Questionnaire | Short read |
|---|---|---|---|---|
| 1 | You, today | No action yet. Photograph every meal; connect Apple Health; turn on reminders | Day 1 | Why we start with your baseline |
| 2 | How you eat | Morning: **Hydrate** — a glass of water when you wake up, even before your coffee | Day 2 | What your meal photos tell us |
| 3 | How you move | Morning: 3 deep breaths + 1 minute of gentle movement · Midday: ✓ 5 minutes outside after lunch · optional 15-min call opens | Day 3 | Little and often |
| 4 | How you sleep | Morning: ✓ 5 minutes of daylight · Evening: ✓ phone out of the bedroom | Day 4 | Light sets your body clock |
| 5 | Stress and recovery | Evening: ✓ box breathing, 2 minutes (in-app guide) | Day 5 | The 2-minute downshift |
| 6 | Your first week | Nothing new: recap, goals check, what week 2 is | Day 6 | Simple actions, repeated |
| 7 | Your full day | Morning flow: 5-minute qi-gong-style routine (replaces the 1 minute). The full day: water → breaths → 5-min flow → daylight · walk after lunch · phone out + breathing. Summary arrives once approved | — | Your day, on one page |
| 8 | Protein first | Morning: ✓ protein at breakfast (ideas from their foods) + ✓ 10-minute walk | — | Why protein first |
| 9 | A lunch that holds you | Midday: ✓ vegetables on half the plate, protein, fewer fast carbs · walk after lunch → 10 min · ✓ last coffee before 14:00 | — | The afternoon dip |
| 10 | Easy strength | ✓ 10 sit-to-stands + ✓ one set of wall push-ups, any time | — | Muscle is a long-term account |
| 11 | Your evening downshift | ✓ dim the lights after 21:00 · ✓ screens off 30 min before bed · last meal 2 h before bed | — | Your evening routine |
| 12 | More morning movement | Morning flow 5 → 10 minutes · during the day: 2 minutes of movement every hour or two of sitting · "where you stand" message | — | Sitting less |
| 13 | Make it yours | Nothing new: the whole routine on one page; choose the actions you keep (they stay in the app) | — | Habits that last |
| 14 | Your two weeks | Before/after from check-ins · Day-14 questionnaire · review call (unlocked or invited) | Day 14 | What a personal programme adds |

By moment: **morning** water (2) → breaths + 1 min (3) → daylight (4) → 5-min flow (7) → protein breakfast + walk (8) → 10-min flow (12) ·
**midday** 5-min walk (3) → better lunch, 10-min walk, coffee before 14:00 (9) → movement breaks (12) ·
**evening** phone out (4) → breathing (5) → dim lights, screens off, earlier last meal (11).

## Reminders (EN; FR with the scripts)

Times: morning = wake time + 15 min · after lunch = lunch time + 45 min · evening = 45 min before bedtime
(defaults 07:15 · 13:15 · 21:30; existing quiet hours 22:00–07:30 apply). At most three a day; the evening one
replaces the usual check-in reminder during the track.

| Day | Morning | After lunch | Evening |
|---|---|---|---|
| 1 | — (the day starts at first open) | — | First day done? Snap your dinner, then your evening check-in. |
| 2 | Day 2 · Before coffee: a big glass of water. Today's video is ready. | Snap your lunch. That's all we need. | Today's questionnaire: how you eat. 2 minutes, then your check-in. |
| 3 | Day 3 · Water, 3 deep breaths, 1 minute of moving. | 5 minutes outside, now. | Today's questionnaire: how you move. Your 15-min call with Thomas is open to book. |
| 4 | Day 4 · Your morning: water, breaths, move, then 5 minutes of daylight. | 5 minutes outside after lunch. | Phone out of the bedroom tonight. Today's questionnaire: how you sleep. |
| 5 | Day 5 · Water, breaths, move, daylight. | 5 minutes outside after lunch. | Before bed: 2 minutes of box breathing. Last questionnaire: stress and recovery. |
| 6 | Day 6 · Your first week, on one screen. Have a look. | Your walk after lunch. | Phone out, 2 minutes of breathing, then your check-in. |
| 7 | Day 7 · Today it all comes together: your 5-minute morning flow. | Your walk after lunch. | Phone out, breathing, check-in. Your week-1 summary is on its way. |
| 8 | Day 8 · Protein at breakfast, then a 10-minute walk. | Your walk after lunch. | Phone out, breathing, check-in. |
| 9 | Day 9 · Today's focus is lunch: protein, vegetables, fewer fast carbs. | 10 minutes outside. Last coffee before 14:00. | Phone out, breathing, check-in. |
| 10 | Day 10 · Easy strength today: 10 sit-to-stands and a few wall push-ups. | Walk, then your sit-to-stands if not done yet. | Phone out, breathing, check-in. |
| 11 | Day 11 · Tonight: your evening downshift. | Your walk after lunch. | Lights down, screens off 30 minutes before bed, then 2 minutes of breathing. |
| 12 | Day 12 · Your morning flow goes to 10 minutes. | Walk after lunch. Every hour or two: stand up and move for 2 minutes. | Where you stand: {modules}/5 questionnaires, {pct}% of meals. 2 days to go. |
| 13 | Day 13 · Your whole routine, on one page. Which actions will you keep? | Your walk after lunch. | Phone out, breathing, check-in. |
| 14 | Day 14 · Two weeks. See how far you've come, and tell us how it was. | — | Your review call with Thomas is ready to book. *(only if unlocked)* |

## Video scripts (EN, ~1 minute each; FR once the EN is approved)

### Day 1 · You, today
Hi, I'm Thomas. Welcome to your first fourteen days with FunctionAlps.
Every day, you'll find one card in the app: a short video like this one, one small action, and a short read. For the first six days, there's also a quick questionnaire, one topic a day.
The whole app is open from today. What changes is the action: we start very small and build up, step by step.
This first week is about understanding you. So don't change how you eat yet. Just photograph everything you eat: that's your real starting point.
On day seven, you'll get a summary of your first week, which I review myself. In week two, your actions grow.
Complete the questionnaires and log most of your meals, and on day fourteen we'll talk, one to one, about your results.
Today: your first questionnaire. At the end, connect Apple Health and turn on your reminders. And photograph your meals. See you tomorrow.

### Day 2 · How you eat
Day two. Today is about food: not what a perfect diet looks like, but how you really eat.
Your meal photos are already working for you. Keep photographing everything, as normal. Don't eat better for the camera: we want your real week.
Today's questionnaire takes two minutes: your meals, where your food comes from, what you drink.
And your first action is simple: hydrate. A big glass of water as soon as you wake up, before anything else, even before your coffee. After a night without drinking, it's the easiest way to start the day well.
Today's read explains what we learn from your meal photos.
Tomorrow: movement. See you then.

### Day 3 · How you move
Day three. Today: movement. How your body moves now, and how it moved before.
So far, you photograph your meals and start the day with a glass of water.
Today we add two small things. In the morning, after your water: three slow, deep breaths through the nose, then one minute of gentle movement. Roll your shoulders, swing your arms, shake out your legs. That's all.
And after lunch: five minutes outside. A short walk, nothing sporty.
Today's questionnaire asks about your activity, your sporting past, and anything that feels uncomfortable when you move, so we choose the right starting point for you.
And from today, if you'd like, you can book a free fifteen-minute call with me, right in the app. It's optional, and it's a good moment for your questions.
See you tomorrow.

### Day 4 · How you sleep
Day four. Today: sleep. Sleep shapes your energy, your appetite, your mood and how you recover.
Your routine so far: water when you wake up, three breaths and a minute of moving, and five minutes outside after lunch. Plus your meal photos.
Today we add light. In the morning, get five minutes of daylight: step outside, or stand by an open window. Morning light helps set your body clock for the day.
And tonight, your phone sleeps outside the bedroom. Charge it in another room.
Today's questionnaire is about your usual nights, not just last night. Your morning check-in already records each night, so it takes two minutes.
See you tomorrow.

### Day 5 · Stress and recovery
Day five. Today: stress and recovery. Stress shows up everywhere: in your sleep, your appetite, your energy, your digestion.
Your routine so far: water, breaths and a minute of moving in the morning, five minutes of daylight, a short walk after lunch, and your phone out of the bedroom at night.
Today's action is for the evening: two minutes of box breathing before bed. Breathe in for four, hold for four, breathe out for four, hold for four. The app guides you through it.
Today's questionnaire is the last of the five: where your stress comes from, and what helps you switch off.
Tomorrow, we look back at your first week. See you then.

### Day 6 · Your first week
Day six. You've told us a lot about yourself: your goals, how you eat, move, sleep and handle stress. Thank you. That's the hard part done.
Today there's no new action. Keep what you've started: water, breathing and moving in the morning, daylight, the walk after lunch, the phone out and the breathing at night.
In the app today, you'll see a short recap of what you told us, and you can check your goals are still right.
From tomorrow, things change. Week two is about action: simple, classic habits that work for almost everybody. Your job is to try them, and notice how you feel. Your daily check-ins will show it.
See you tomorrow, for day seven.

### Day 7 · Your full day
Day seven. One week. Today, everything comes together into one simple day.
Your morning routine grows to five minutes and becomes more flowing: a glass of water, three deep breaths, then five minutes of gentle movement inspired by qi gong. Slow breathing with the arms, gentle twists, and shaking it out. Then five minutes of daylight.
During the day: your walk after lunch, and move whenever you can.
In the evening: phone out of the bedroom, and two minutes of box breathing.
That's your base. From now on, we build on it.
Your week-one summary is on its way: what we learned, your priorities, and your energy and protein ranges. I review it before it reaches you.
See you tomorrow.

### Day 8 · Protein first
Day eight. Week two starts with breakfast.
Today: protein at breakfast. Eggs, Greek yogurt, cottage cheese, smoked salmon, tofu, a protein shake: the app suggests ideas from what you told us you eat. Protein keeps you full for longer and supports your muscles.
Then, after breakfast, a ten-minute walk. Outside if you can, so it counts as your daylight too.
Everything else stays: water, breathing and your five-minute morning flow, the walk after lunch, and your evening: phone out, two minutes of breathing.
Keep photographing your meals: now we'll see the change on your plate.
See you tomorrow.

### Day 9 · A lunch that holds you
Day nine. Today: lunch, the meal that shapes your afternoon.
Build your plate like this: vegetables on half the plate, a good portion of protein, and fewer fast carbs: less white bread, white pasta and sweet drinks. Many people find their afternoon dip gets smaller.
After lunch, your walk becomes ten minutes.
And one more thing: make your last coffee before two in the afternoon, so it doesn't follow you into the night.
Your routine so far: water, breathing and your morning flow, protein at breakfast with a walk, daylight, and your evening: phone out and breathing.
See you tomorrow.

### Day 10 · Easy strength
Day ten. Today: easy strength. Muscle is one of the best things you can build for the long term, and it starts very simply.
At any moment today: ten sit-to-stands. Sit on a chair, stand up, sit down again, ten times, slowly. Then one set of push-ups against a wall, as many as feel comfortable. If anything hurts, stop: easier is fine.
The app shows you how, step by step.
Everything else stays: your morning routine, protein at breakfast, your walks, your lunch plate, your last coffee before two, and your evening routine.
See you tomorrow.

### Day 11 · Your evening downshift
Day eleven. Today: your evening. How your evening goes often shapes how your night goes.
Three things tonight. After nine o'clock, dim the lights. Screens off thirty minutes before bed: no phone, no laptop. And try to finish your last meal about two hours before you sleep.
Then your two minutes of box breathing, as usual.
The rest of your day stays the same: water, breathing and flow in the morning, protein at breakfast, your walks, your lunch plate and your sit-to-stands.
Tomorrow morning, notice how you feel, and tell us in your check-in.
See you tomorrow.

### Day 12 · More morning movement
Day twelve. Today, your morning flow grows from five to ten minutes. The same movements, a little longer: breathe, move, twist, shake it out. Ten minutes that wake up your whole body.
And during the day: if you sit for long, stand up every hour or two and move for two minutes. Walk while you're on the phone, take the stairs, stretch at your desk.
Everything else stays: water, protein breakfast and a walk, daylight, your lunch and the walk after it, your sit-to-stands, and your evening downshift.
Two days to go. In the app, you can see where you stand: your questionnaires and your meals. If something's missing, there's still time.
See you tomorrow.

### Day 13 · Make it yours
Day thirteen. Look at what you've built: a morning with water, breathing, ten minutes of movement and daylight. Protein at breakfast and a walk. A lunch that holds you, and a walk after it. Easy strength. And an evening that helps you sleep.
Today there's nothing new. Today, you choose. In the app, pick the actions you want to keep after these two weeks. They'll stay in your app.
Don't pick everything. Pick what felt good and fits your life. A few habits you keep are worth more than ten you try once.
Tomorrow is our last day on this track. See you then.

### Day 14 · Your two weeks
Day fourteen. Two weeks ago you started. Today, look at how far you've come.
In the app, you'll see your check-ins from your first days next to your last days: your energy, your focus, your mood, your sleep. Your own data, from your own life.
Then one last short questionnaire: how you felt, what you liked, what didn't work for you. Please be honest: it helps us make this better.
If you completed your questionnaires and logged your meals, you can now book your review call with me. We'll look at your results together, answer your questions, and talk about what's next: keep going with the app, or go deeper with a personal programme built for you.
Thank you for these two weeks. See you on the call.
