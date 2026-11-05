#!/usr/bin/env python3
"""Builds the Foundation Track day-card mockups page (cards.html) and cards.json from one source.

Thomas, 2026-10-06 (second pass): days 1–7 each explain a pillar (what it is, why it matters, how we
use it), say why the day's questions matter, and end with a first thing to try that grows into a
routine. No image on days 1–7. Every card shows Your routine and How it will evolve. All calls are
the 20-minute members call.
"""
import html
import json
import pathlib

HERE = pathlib.Path(__file__).parent

# key → (moment, title, how)
ACTIONS = {
    "water_waking": ("morning", "A glass of water on waking", "Before your coffee. Keep a glass by your bed."),
    "breaths_3": ("morning", "3 slow breaths at the window", "In through the nose, a long breath out. Look outside, at the light."),
    "move_1min": ("morning", "1 minute of gentle movement", "Roll your shoulders, circle your hips, a few slow squats."),
    "morning_flow_5": ("morning", "5-minute morning flow", "Slow breathing with the arms, gentle twists, then shake it out. Inspired by qi gong."),
    "morning_flow_10": ("morning", "10-minute morning flow", "The same movements, a little longer."),
    "daylight": ("morning", "5 minutes of daylight", "Outside, or at an open window."),
    "protein_breakfast": ("morning", "Protein at breakfast", "Eggs, Greek yogurt, cottage cheese, smoked salmon, tofu. About a palm."),
    "walk_after_breakfast": ("morning", "A 10-minute walk after breakfast", "Outside if you can, so it counts as daylight too."),
    "meal_photos": ("day", "Photograph everything you eat", "Every meal and snack, before the first bite."),
    "exercise_snack": ("day", "Optional: an exercise snack", "10 squats, a minute up the stairs, or 10 wall push-ups. Whenever you like."),
    "exercise_snack_daily": ("day", "One exercise snack a day", "10 squats, a minute up the stairs, or 10 wall push-ups."),
    "easy_strength": ("day", "5-minute easy strength routine", "Thomas shows every move in today's video. At home, no equipment."),
    "movement_breaks": ("day", "Move 2 minutes every hour or two", "Stand up, take the stairs, walk while you're on the phone."),
    "walk_after_lunch_5": ("midday", "5 minutes outside after lunch", "A short walk. Nothing sporty."),
    "walk_after_lunch_10": ("midday", "A 10-minute walk after lunch", "The most important habit of the week."),
    "lunch_plate": ("midday", "A lunch that holds you", "Half vegetables, a palm of protein, a quarter complex carbs."),
    "coffee_before_14": ("midday", "Last coffee before 14:00", "So it doesn't follow you into the night."),
    "stretch_evening": ("evening", "2 minutes of gentle stretching before bed", "Slow and easy: neck, shoulders, back, hips."),
    "phone_out": ("evening", "Your phone sleeps outside the bedroom", "Charge it in another room. A simple alarm clock helps."),
    "box_breathing": ("evening", "Box breathing, 2 minutes in bed", "In 4 · hold 4 · out 4 · hold 4. The app guides you."),
    "one_good_thing": ("evening", "One good thing", "Before sleep, name one thing that went well today."),
    "last_meal": ("evening", "Last meal 2–3 hours before bed", "Leave space between dinner and sleep."),
    "screens_off_60": ("evening", "Screens off, lights low: 60 minutes before bed", "No phone, no laptop. Softer light tells your body the day is ending."),
    "book": ("evening", "A book instead of a screen", "Paper, on the sofa or in bed."),
    "wind_down_10": ("evening", "10 minutes to wind down", "Choose one: slow breathing, NSDR (non-sleep deep rest) or gentle yoga."),
}

# key, first day, last day (None = to the end). A replacement starts the day after the old one ends.
SCHEDULE = [
    ("water_waking", 1, None), ("breaths_3", 1, 6), ("meal_photos", 2, None),
    ("move_1min", 3, 6), ("exercise_snack", 3, 6), ("stretch_evening", 3, 10),
    ("daylight", 4, None), ("phone_out", 4, None),
    ("box_breathing", 5, 10), ("one_good_thing", 5, None),
    ("walk_after_lunch_5", 6, 8),
    ("morning_flow_5", 7, 11), ("exercise_snack_daily", 7, 9),
    ("protein_breakfast", 8, None), ("walk_after_breakfast", 8, None),
    ("lunch_plate", 9, None), ("walk_after_lunch_10", 9, None), ("coffee_before_14", 9, None),
    ("easy_strength", 10, None),
    ("last_meal", 11, None), ("screens_off_60", 11, None), ("book", 11, None), ("wind_down_10", 11, None),
    ("morning_flow_10", 12, None), ("movement_breaks", 12, None),
]

MOMENT_ORDER = ["morning", "midday", "evening", "day"]
MOMENT_LABEL = {"morning": "Morning", "midday": "After lunch", "evening": "Evening", "day": "During the day"}

SERIES_STYLE = (
    "One series, seven images (days 8–14; days 1–7 have none). Flat vector illustration, calm and friendly; simple "
    "rounded figures, no detailed faces. Palette: forest green #2E5438 and soft green #4A8A5C on cream #F5F0E8, charcoal "
    "#1A1A16 for text, one warm accent (gold #D4A84E) reserved for the day's NEW action so it stands out the same way on "
    "every card. Portrait 4:5 (1080 × 1350 px) so it fits the app card, the library and social posts. One idea per image, "
    "generous white space, short labels (max 4 words each), EN and FR versions. A small 'Day N' tag in the top-left "
    "corner. A faint Alpine ridge line along the bottom edge ties the series together."
)

CALL = "Book a call with Thomas · 20 min"

DAYS = [
    dict(day=1, week=1, title="Your starting point", pillar="Where you are, where you're going",
         today=[("What it is", "Your Foundation Track: 14 days, one card a day. Week 1 helps us understand you, one pillar a day. Week 2 is about action."),
                ("Why it matters", "Lasting change starts from where you really are, not from a perfect plan. Knowing your starting point and where you want to go lets everything after fit you."),
                ("How we use it", "Your answers and check-ins shape your week-2 actions, your first-week summary on day 7 and your review call with Thomas on day 14.")],
         questionnaire=("You, today", 3, "Your goals, your usual week and your rhythm. This is your starting point: everything after builds on it, so there are no wrong answers. Don't change anything yet."),
         extras=["Connect Apple Health", "Turn on your reminders"],
         try_label="First thing to try · a mini morning routine",
         tip="Put a glass of water by your bed tonight, so tomorrow's first step is already waiting.",
         evolve=[("Tomorrow", "Photograph what you eat. That habit runs all 14 days."),
                 ("Day 3", "1 minute of movement joins your morning, and your evening routine begins."),
                 ("Day 7", "Your full day: a 5-minute morning flow and a daily exercise snack.")],
         read="Why we start with where you are",
         script="""Hi, I'm Thomas. Welcome to your Foundation Track.

For the next fourteen days you'll get one short card a day: a video like this one, one small thing to try, and a short read.

Why fourteen days? Because lasting change doesn't start with a perfect plan. It starts with understanding where you are today, and where you want to go.

So this first week is about you. Each day we look at one pillar of your health: nutrition, movement, sleep, and your mental and emotional health. I explain why it matters and how we use it, and you answer a few short questions. Don't change anything yet: the more real your answers, the more useful everything after.

Today's questions are about your starting point: your goals, your usual week, your rhythm. Three minutes.

And your first thing to try is a mini morning routine: a glass of water when you wake up, then three slow breaths at the window. That's it.

Small steps, one a day. Let's start."""),
    dict(day=2, week=1, title="Nutrition", pillar="Pillar 1 · Nutrition",
         today=[("What it is", "What you eat, when, and how much: the material your body builds and repairs with, and the fuel for your energy."),
                ("Why it matters", "Food shapes your energy, hunger, mood, sleep and recovery. Small changes in what and when you eat often make a big difference."),
                ("How we use it", "Your answers and your meal photos show your real pattern. From them we choose the changes that will help you most, with ideas from foods you already eat.")],
         questionnaire=("Your nutrition", 2, "How many meals, when, who cooks, which proteins you like, what you drink. It shows your real pattern before we change anything, and which ideas fit your kitchen."),
         extras=[],
         try_label="First thing to try · one habit for all 14 days",
         tip="Photograph before the first bite, drinks and snacks included. A quick photo beats a perfect one.",
         evolve=[("Tomorrow", "Your morning grows with 1 minute of movement, and your evening routine begins."),
                 ("Day 4", "Daylight in the morning, your phone out of the bedroom."),
                 ("Days 8–9", "Breakfast and lunch become the focus, built from your photos.")],
         read="What your meal photos tell us",
         script="""Today: nutrition, the first pillar.

Food is more than calories. It's the material your body uses to build and repair, the fuel for your energy, and a signal that shapes your hunger, your mood and your sleep.

But to help you, we don't start with a diet. We start with how you really eat. That's why today's questions ask how many meals you have, when you eat, who cooks, and which proteins you like. Together they show your real pattern, and where one small change would help you most.

And that's why today's one habit matters so much: photograph everything you eat. Every meal, every snack, before the first bite. Not to judge. A photo shows what memory forgets: timing, portions, protein, variety. Your photos are how we understand your nutrition, and they count toward your review call on day fourteen.

So today: your nutrition questions, two minutes, and a photo before each meal.

Tomorrow: movement."""),
    dict(day=3, week=1, title="Movement", pillar="Pillar 2 · Movement",
         today=[("What it is", "Not sport: your functional capacity. How easily your body does what your life asks of it: getting up, carrying, climbing stairs, hiking."),
                ("Why it matters", "Capacity is built or lost by what you do every day. Long hours of sitting slowly take it away; small, regular movement keeps it and builds it."),
                ("How we use it", "Your answers set the right starting level for you and keep every movement we suggest safe. We start with little and often.")],
         questionnaire=("Your movement", 2, "How you move now, how you moved before, and whether anything hurts. It sets the right starting level for you, instead of the same workout for everyone, and keeps it safe."),
         extras=[CALL + " (optional, from today)"],
         try_label="First thing to try · your morning grows, your evening begins",
         tip="No time for an exercise snack? Take the stairs once. That counts.",
         evolve=[("Tomorrow", "5 minutes of daylight; your phone sleeps outside the bedroom."),
                 ("Day 7", "Your minute of movement becomes a 5-minute flow, and the exercise snack becomes daily."),
                 ("Days 10–12", "Easy strength, then a 10-minute morning flow.")],
         library=[("Lesson", "Exercise snacks: small signals that add up", "in the library")],
         read="Little and often",
         script="""Today: movement, the second pillar.

When I talk about movement, I don't mean sport. I mean functional capacity: how easily your body does what your life asks of it. Getting up from the floor. Carrying the shopping. Climbing the stairs. Hiking in the mountains when you're seventy.

That capacity is built, or lost, by what you do every day. Sitting most of the day slowly takes it away. Small, regular movement keeps it, and builds it. That's why we start with little and often, not with a hard workout.

Today's questions ask how you move now, how you moved before, and whether anything hurts. That way everything we suggest starts at the right level for you, and stays safe.

Your morning routine grows: after your water and your breaths, one minute of gentle movement. If you want more, try an exercise snack during the day: ten squats, or a minute up the stairs. And tonight your evening routine begins: two minutes of gentle stretching before bed.

From today you can also book a free twenty-minute call with me, right in the app.

Tomorrow: sleep."""),
    dict(day=4, week=1, title="Sleep", pillar="Pillar 3 · Sleep",
         today=[("What it is", "The time your body repairs, your brain sorts the day and your rhythm resets."),
                ("Why it matters", "After a poor night, hunger is louder, cravings stronger, mood shorter and effort harder. Regular times and light set your body clock."),
                ("How we use it", "Your usual pattern tells us where to start, and your times decide when your reminders arrive. Your morning check-in records each night.")],
         questionnaire=("Your sleep", 2, "Your usual nights, not last night: bedtime, how long you take to fall asleep, what wakes you, how rested you feel. Your times also set when your reminders arrive."),
         extras=[],
         try_label="First thing to try · one for the morning, one for the night",
         tip="No time to go outside? Have your coffee at the brightest window.",
         evolve=[("Tomorrow", "Box breathing and one good thing join your evening."),
                 ("Day 11", "Your full evening routine: last meal earlier, screens off, a book, 10 minutes to wind down.")],
         read="Light sets your body clock",
         script="""Today: sleep, the third pillar.

Sleep is when your body repairs, your brain sorts the day, and your rhythm resets. After a poor night, hunger is louder, cravings are stronger, your mood is shorter and every effort feels harder. Sleep quietly shapes every other pillar.

Two things matter a lot: regular times, and light. Your body clock is set by light, especially morning daylight, and pushed back by bright screens late in the evening.

Today's questions are about your usual pattern, not last night: when you go to bed, how long you take to fall asleep, what wakes you, how rested you feel. Your times also tell us when to send your reminders.

Two small things join your routine. In the morning: five minutes of daylight, outside or at an open window. In the evening: your phone sleeps outside the bedroom. A simple alarm clock helps.

Tomorrow: your mental and emotional health."""),
    dict(day=5, week=1, title="Mental and emotional health", pillar="Pillar 4 · Mental and emotional health",
         today=[("What it is", "The load you carry, from work, family, health or big changes, and how well you recover from it."),
                ("Why it matters", "When the load stays high, it shows up in your sleep, appetite, energy, digestion and mood. Recovery is what brings your body back to calm."),
                ("How we use it", "Knowing where your load comes from and what already helps you lets us suggest tools that fit your life, instead of adding pressure.")],
         questionnaire=("Your mental and emotional health", 2, "How stressed you've felt, where it comes from, your mood and what helps you switch off. Answer only what you're comfortable with: it helps us suggest tools that fit your life."),
         extras=[],
         try_label="First thing to try · your evening grows",
         tip="If four counts feel long, breathe in threes. The rhythm matters more than the number.",
         evolve=[("Tomorrow", "A short walk after lunch: your routine now covers the whole day."),
                 ("Day 11", "Your 2 minutes of breathing grow into 10 minutes: breathing, NSDR or gentle yoga.")],
         read="The 2-minute downshift",
         script="""Today: the fourth pillar, your mental and emotional health.

Stress isn't only in your head. When the load stays high, it shows up everywhere: in your sleep, your appetite, your energy, your digestion, your patience. And recovery isn't only rest. It's what brings your body back to calm after effort.

We all carry a load: work, family, health, money, big changes. What matters is the balance between that load and how well you recover from it.

Today's questions ask how stressed you've felt lately, where it comes from, how your mood has been, and what already helps you switch off. Answer only what you're comfortable with. It helps us suggest tools that fit your life, instead of adding pressure.

Your evening routine grows with two things. In bed: two minutes of box breathing. In for four, hold for four, out for four, hold for four. Then think of one good thing from your day.

That was the last questionnaire. Tomorrow: your first week, on one page."""),
    dict(day=6, week=1, title="Your first week", pillar="Recap",
         today="Six days, four pillars: nutrition, movement, sleep, and your mental and emotional health. You've told us where you are and where you want to go, and you've built a small routine without really noticing. Here it is, in the four moments of your day. One new moment today: after lunch.",
         questionnaire=("Your first week", 1, "Check your goals are still right and tell us how the week felt."),
         extras=[],
         try_label="New today · after lunch",
         tip="Put your walking shoes by the door before lunch.",
         evolve=[("Tomorrow", "A 5-minute morning flow and one exercise snack a day."),
                 ("Week 2", "One focus a day: breakfast, lunch, strength, evening, morning."),
                 ("Day 13", "You choose what you keep.")],
         read="Simple actions, repeated",
         script="""Six days. Look at what you've already done.

You've told us where you are and where you want to go. We've looked at the four pillars: nutrition, movement, sleep, and your mental and emotional health. And you've built a small routine without really noticing.

On your card today you'll see it in the four moments of your day. In the morning: water, three breaths, a minute of movement, and daylight. During the day: your meal photos, and an exercise snack if you like. In the evening: a short stretch, your phone outside the bedroom, two minutes of breathing, and one good thing.

And one new moment today: after lunch, five minutes outside. A short walk, nothing sporty.

Take one minute for today's questions: check your goals are still right, and tell me how the week felt.

Tomorrow, everything comes together in one full day."""),
    dict(day=7, week=1, title="Your full day", pillar="Everything together",
         today="One week. Today everything comes together in one full day, with a little more movement: your minute in the morning becomes a 5-minute flow inspired by qi gong, and the exercise snack becomes daily. Thomas is reviewing your first week; your summary appears here once he has read it.",
         questionnaire=None,
         extras=["Your first-week summary (once Thomas has reviewed it)", CALL + " (if Thomas launched your track)"],
         try_label="New today · a little more movement",
         tip="Link the new to the old: your flow right after your glass of water.",
         evolve=[("Day 8", "Breakfast: protein first."),
                 ("Day 9", "Lunch, and a 10-minute walk after it."),
                 ("Day 10", "Your exercise snack becomes a strength routine."),
                 ("Days 11–12", "Your full evening, then a longer morning flow.")],
         read="Your day, on one page",
         script="""One week. Today everything comes together in one full day.

In the morning, your minute of movement becomes a five-minute flow inspired by qi gong: slow breathing with the arms, gentle twists, then shake it out. It wakes the body up without rushing it.

During the day, your exercise snack is no longer optional: one a day. Ten squats, a minute up the stairs, or ten wall push-ups. Short bursts like these add up, and they're one of the simplest ways to build capacity.

After lunch: your five minutes outside. In the evening: stretch, phone out, breathe, one good thing.

That's your base, and it fits in a normal day.

I'm also reviewing your first week. You'll find your summary here as soon as I've read it: what we learned, your goals, and what week two brings.

Week two is about action, one focus a day. See you tomorrow, with breakfast."""),
    dict(day=8, week=2, title="Protein first", pillar=None,
         today="Protein is your body's building material: muscle, bones, skin, your immune system. Your body can't store it the way it stores fat or sugar, so it needs some regularly across the day, and more as we age to keep our muscle. Many people eat little in the morning and most at night. Today, protein moves to breakfast.",
         questionnaire=None, extras=[],
         try_label="New today",
         tip="Boil a few eggs for the week, or keep Greek yogurt in the fridge: breakfast protein in one minute.",
         evolve=[("Tomorrow", "Lunch: protein, vegetables, complex carbs, and your after-lunch walk doubles to 10 minutes."),
                 ("Day 10", "Easy strength.")],
         library=[("Infographic", "Protein through the day", "to create: today's image, also filed in the library")],
         read="Why protein matters",
         script="""Week two starts with breakfast, and with protein.

Protein is your body's building material: muscle, bones, skin, your immune system. Your body can't store it the way it stores fat or sugar, so it needs some regularly, across the day. And as we get older we need a little more of it to keep our muscle.

Many people eat very little protein in the morning and most of it at night. Moving some of it to breakfast is a simple change, and many people find it keeps them full for longer and steadies their energy through the morning.

So today: put protein on your breakfast plate. Eggs, Greek yogurt, cottage cheese, smoked salmon, tofu. About the size of your palm. The ideas in the app come from what you told us you eat.

Then, if you can, a ten-minute walk after breakfast. Outside, so it counts as daylight too.

Tomorrow: lunch.""",
         image_title="Protein through the day",
         image=[("Composition", "Top two thirds: one breakfast plate in the centre with five small protein options around it. Bottom third: a day strip (breakfast · lunch · dinner) with a walking figure."),
                ("Elements & labels", "Around the plate: 'eggs', 'Greek yogurt', 'cottage cheese', 'smoked salmon', 'tofu'. A palm icon next to the plate: 'about a palm'. The day strip shows three equal protein blocks, the breakfast one in gold: 'spread across the day'. A walking figure in gold: '+10 min walk'."),
                ("One message", "Protein at every meal, starting with breakfast. Then a short walk.")]),
    dict(day=9, week=2, title="A lunch that holds you", pillar=None,
         today="Lunch decides your afternoon. Fast carbs (white bread, white pasta, sweet drinks) often mean a quick rise and a dip around three. Build your plate in three parts: half vegetables, a palm of protein, a quarter complex carbs. Complex carbs come with fibre, so they give steadier energy. Then the most important part: a 10-minute walk.",
         questionnaire=None, extras=[],
         try_label="New today",
         tip="Lunch out? Ask for extra vegetables and choose the whole-grain side.",
         evolve=[("Tomorrow", "Your exercise snack becomes a 5-minute strength routine."),
                 ("Day 11", "Your full evening routine.")],
         library=[("Infographic", "The plate that holds you", "to create: today's image, also filed in the library")],
         thomas_note="Short read 'Complex carbs, simply': to write, and file in the library next to the infographic.",
         read="Complex carbs, simply",
         script="""Today: lunch, and the walk after it.

Lunch decides your afternoon. A plate of fast carbs, like white bread, white pasta or a sweet drink, often means a quick rise in energy and then a dip around three o'clock.

So build your plate in three parts. Half vegetables. A good portion of protein, about a palm. And a quarter of complex carbs: oats, wholegrain bread, legumes, quinoa, brown rice. Complex carbs come with their fibre, so they're digested more slowly and give you steadier energy. You'll find the plate and the complex-carbs principle in your library.

And the most important part comes after: a ten-minute walk. Moving right after a meal helps your muscles use the energy from it, and it's one of the easiest habits to keep.

Last thing: your last coffee before two in the afternoon, so it doesn't follow you into the night.

Tomorrow: easy strength.""",
         image_title="The plate that holds you",
         image=[("Composition", "Left: a large plate diagram. Right, stacked: two small energy curves, then a walking figure, then a small clock."),
                ("Elements & labels", "Plate: half 'vegetables' (soft green), a quarter 'protein' (forest), a quarter 'complex carbs' (cream) with tiny icons for oats, wholegrain bread, lentils, quinoa. Curves: 'fast carbs' (spike, then dip) next to 'complex carbs' (gentle wave). The walker in gold, the largest element on the right: '10-min walk after lunch'. Small clock at 14:00 with a cup: 'last coffee'."),
                ("One message", "Half vegetables, a palm of protein, complex carbs, then walk.")]),
    dict(day=10, week=2, title="Easy strength", pillar=None,
         today="Muscle is one of the best long-term investments you can make: it holds you up, protects your joints, helps your body handle sugar and keeps you independent as you age. Your exercise snack becomes a 5-minute routine, at home, no equipment. Go slowly and stop if anything hurts: easier is always fine.",
         questionnaire=None, extras=[],
         try_label="New today",
         tip="Do your routine while the kettle boils or the coffee runs.",
         evolve=[("Tomorrow", "Your full evening routine."),
                 ("Day 12", "Your morning flow grows to 10 minutes.")],
         thomas_note="The routine itself: Thomas develops it (moves, reps, easier and harder versions), then films it for today's video. Until then the card says 'Thomas shows every move in today's video'.",
         read="Muscle is a long-term account",
         script="""Today: easy strength.

Muscle is one of the best long-term investments you can make. It holds you up, protects your joints, helps your body handle sugar, and keeps you independent as you get older. And it starts very simply.

Your daily exercise snack becomes a five-minute strength routine you can do at home, in your clothes, with no equipment. I'll show you every move.

[Thomas: your routine here: each move, how many, the easier version.]

Go slowly, breathe, and stop if anything hurts. Easier is always fine. What matters is doing it often, not doing it hard.

Tomorrow: your evening.""",
         image_title="Five minutes, anywhere",
         image=[("Composition", "Placeholder until Thomas's routine is set: the moves drawn as small poses around a circle, '5 min' in the centre."),
                ("Elements & labels", "One pose per move, each labelled with the move and its count (from Thomas's routine). Gold arrows between poses. Under the circle: 'at home · no equipment · in your clothes'."),
                ("One message", "Strength starts with a few simple moves, five minutes, anywhere.")]),
    dict(day=11, week=2, title="Your evening downshift", pillar=None,
         today="Tonight your evening routine is complete. Last meal 2–3 hours before bed, so your body can rest rather than digest. An hour before bed: screens off, lights low, a book instead of the phone. Then 10 minutes to wind down: slow breathing, NSDR or gentle yoga. Your stretch and box breathing grow into this.",
         questionnaire=None, extras=[],
         try_label="New today · the full routine",
         tip="Set an alarm for 'screens off', and choose tonight's book now.",
         evolve=[("Tomorrow", "Your morning flow grows to 10 minutes, with short movement breaks."),
                 ("Day 13", "You choose what you keep.")],
         library=[("Audio", "10-minute NSDR", "to record")],
         read="Your evening routine",
         script="""Tonight: your full evening routine.

You've already started: a stretch, your phone outside the bedroom, two minutes of breathing, one good thing. Tonight we complete it.

Two to three hours before bed, finish your last meal. Your body can then focus on rest rather than digestion.

One hour before bed: screens off, lights low. Bright screens tell your brain it's still daytime. Swap the phone for a book.

Then, before sleep, ten minutes to wind down. Choose what suits you: slow breathing, a guided NSDR, which means non-sleep deep rest, or gentle yoga. Your stretch and your box breathing grow into this.

And keep your one good thing, last thing before sleep.

You don't need everything every night. Start with what's easiest, and add the rest.

Tomorrow: more morning movement.""",
         image_title="Winding down, step by step",
         image=[("Composition", "A horizontal evening timeline from dinner to sleep, its background shifting from warm to dark."),
                ("Elements & labels", "Markers: a plate at '−3 h to −2 h' ('last meal'), a phone switching off and a lamp dimming at '−60 min' ('screens off, lights low'), an open book ('read'), a figure lying down at '−10 min' ('breathe · NSDR · yoga'), a small star at 'sleep' ('one good thing'). The phone charging outside the bedroom door in grey (already in place). The four new markers in gold."),
                ("One message", "Earlier dinner, screens off, a book, ten calm minutes.")]),
    dict(day=12, week=2, title="More morning movement", pillar=None,
         today="Moving early wakes your body, gets your circulation going and, outside, gives you daylight for your body clock. And what's done first thing gets done. Your flow grows from five to ten minutes. During the day, if you sit for long, stand up every hour or two and move for two minutes.",
         questionnaire=None, extras=[],
         try_label="New today",
         tip="Stand up whenever you take a call.",
         evolve=[("Tomorrow", "Nothing new: you choose what you keep."),
                 ("Day 14", "Your two weeks, and your 20-minute review call.")],
         read="Sitting less",
         script="""Today your morning flow grows from five to ten minutes.

Why the morning? Moving early wakes your body up, gets your circulation going and, if you're outside, gives you daylight for your body clock. And a routine done first thing gets done, before the day takes over.

Same movements, a little longer: breathe, move, twist, shake out. Ten minutes is enough to feel looser, warmer and more awake.

And during the day: if you sit for long periods, stand up every hour or two and move for two minutes. Take the stairs, walk while you're on the phone, refill your water. Long sitting is one of the things that slowly takes your capacity away, and short breaks are the simplest answer.

Tomorrow: you choose what you keep.""",
         image_title="Ten minutes, then little breaks",
         image=[("Composition", "Left: a short sequence of four flow poses. Right: a workday timeline with small break markers."),
                ("Elements & labels", "Flow poses labelled 'breathe', 'move', 'twist', 'shake out', with '10 min' above them in gold. The workday line runs 9:00 to 18:00 with small gold markers every one to two hours: 'stand', 'stairs', 'walk on a call'."),
                ("One message", "A longer morning flow, and two minutes of movement every hour or two.")]),
    dict(day=13, week=2, title="Make it yours", pillar=None,
         today="Look at what you've built in twelve days. There's nothing new today: choose the actions you want to keep after these two weeks. They stay in your app. A few habits you keep are worth more than ten you try once.",
         questionnaire=None, extras=["Choose the actions you keep"],
         try_label="New today",
         tip="Keep the ones you'd miss, not the ones you think you should.",
         evolve=[("Tomorrow", "Your two weeks: before and after, and your review call."),
                 ("After day 14", "The actions you keep stay in your app.")],
         read="Habits that last",
         script="""Look at what you've built in twelve days. A morning routine, a walk after lunch, protein at breakfast, a lunch that holds you, strength, an evening that helps you sleep.

You don't need to keep everything. A few habits you keep are worth more than ten you try once.

Today there's nothing new. Look at your whole routine, and choose the actions you want to keep after these two weeks. They stay in your app.

Choose the ones that felt good and fit your life. You can always add more later.

Tomorrow: your two weeks, and what comes next.""",
         image_title="Choose what you keep",
         image=[("Composition", "Four rows of small action cards (Morning, After lunch, Evening, During the day), some lifted forward, some faded."),
                ("Elements & labels", "About twelve mini cards with icons (water, flow, daylight, protein, walk, plate, strength, book, moon, phone, star, stairs). Four of them lifted forward with a gold check: 'I keep'. The rest faded. Caption: 'Pick what fits your life'."),
                ("One message", "You don't need everything. Keep what works for you.")]),
    dict(day=14, week=2, title="Your two weeks", pillar=None,
         today="Two weeks ago you started. Today you see your check-ins from your first days next to your last days, tell us how it was, and book your 20-minute review call with Thomas once it's open to you.",
         questionnaire=("Your two weeks", 2, "What helped, what was hard, and what you'd like next. Thomas reads it before your call."),
         extras=["Book your review call with Thomas · 20 min"],
         try_label="New today",
         tip="Write down one question for Thomas before your call.",
         evolve=[("Next", "Keep going with the app, or go deeper with a personal programme. You decide together on your call.")],
         read="What a personal programme adds",
         script="""Fourteen days. Thank you.

Today you'll see your check-ins from your first days next to your last days: energy, focus, mood, sleep. Look at what changed, and what didn't. Both tell us something.

Then tell us how it was, in two minutes: what helped, what was hard, and what you'd like next.

If you completed your questionnaires and photographed your meals, you can now book your twenty-minute review call with me. We'll look at your results together, answer your questions, and talk about what's next: keep going with the app, or go deeper with a personal programme built for you.

Thank you for these two weeks. See you on the call.""",
         image_title="From day 1 to day 14",
         image=[("Composition", "A calendar strip of 14 ticked days at the top; below, four pairs of simple bars; at the bottom, a fork in the path."),
                ("Elements & labels", "Bars labelled 'energy', 'focus', 'mood', 'sleep', each pair marked 'first days' and 'last days' (illustrative shapes, no numbers). The fork: 'Keep going with the app' and 'Go deeper with a personal programme', with a small phone icon in gold: 'Review with Thomas · 20 min'."),
                ("One message", "See how far you've come, then choose what's next with Thomas.")]),
]


def actions_for(day):
    new, kept = [], []
    for key, first, last in SCHEDULE:
        if day < first or (last is not None and day > last):
            continue
        (new if day == first else kept).append(key)
    return new, kept


def brief_text(d):
    lines = [f"Day {d['day']} · {d['title']} — infographic: {d['image_title']}"]
    for k, v in d["image"]:
        lines.append(f"{k}: {v}")
    lines.append(f"Series style: {SERIES_STYLE}")
    return "\n".join(lines)


def script_text(d):
    return f"Day {d['day']} · {d['title']} — video script (EN)\n\n{d['script']}"


def words(s):
    return len(s.split())


def esc(s):
    return html.escape(s, quote=True)


def paras(s):
    return "".join(f"<p>{esc(p)}</p>" for p in s.split("\n\n"))


def card_html(d):
    day = d["day"]
    new, kept = actions_for(day)
    dots = "".join(f'<i class="dot{" on" if i <= day else ""}"></i>' for i in range(1, 15))
    new_rows = "".join(
        f'<li class="act new"><span class="tick" aria-hidden="true"></span><div><p class="act-t">{esc(ACTIONS[k][1])}</p>'
        f'<p class="act-h">{esc(ACTIONS[k][2])}</p></div><span class="moment">{esc(MOMENT_LABEL[ACTIONS[k][0]])}</span></li>'
        for k in new)
    if not new_rows:
        new_rows = '<li class="act none"><p class="act-h">Nothing new today. Keep what you\'ve started.</p></li>'
    groups = []
    for m in MOMENT_ORDER:
        items = [k for k, _, _ in SCHEDULE if k in new + kept and ACTIONS[k][0] == m]
        if items:
            chips = "".join(f'<span class="chip{" new" if k in new else ""}">{esc(ACTIONS[k][1])}</span>' for k in items)
            groups.append(f'<div class="grp"><p class="grp-l">{esc(MOMENT_LABEL[m])}</p><div class="chips">{chips}</div></div>')
    routine = "".join(groups)

    if isinstance(d["today"], list):
        today = '<dl class="tri">' + "".join(f'<div><dt>{esc(k)}</dt><dd>{esc(v)}</dd></div>' for k, v in d["today"]) + "</dl>"
    else:
        today = f'<p class="today">{esc(d["today"])}</p>'

    qblock = ""
    if d["questionnaire"]:
        name, mins, why = d["questionnaire"]
        qblock = (f'<div class="qbox"><span class="btn primary">Questionnaire · {esc(name)} · {mins} min</span>'
                  f'<p class="why"><b>Why we ask</b> {esc(why)}</p></div>')
    extras = "".join(f'<span class="btn">{esc(x)}</span>' for x in d["extras"])
    extras = f'<div class="btns">{extras}</div>' if extras else ""
    ig = ""
    if d.get("image"):
        ig = (f'<div class="ig" role="img" aria-label="Infographic slot: {esc(d["image_title"])}"><span class="ig-k">Infographic</span>'
              f'<span class="ig-t">{esc(d["image_title"])}</span></div>')
    evolve = "".join(f'<li><span class="ev-w">{esc(w)}</span><span class="ev-t">{esc(t)}</span></li>' for w, t in d["evolve"])
    lib = "".join(
        f'<div class="read lib"><span class="read-k">From the library · {esc(kind)}</span><span class="read-t">{esc(t)}</span><span class="chev" aria-hidden="true">›</span></div>'
        for kind, t, _ in d.get("library", []))
    pillar = f'<p class="pill">{esc(d["pillar"])}</p>' if d.get("pillar") else ""

    # side panel: the script for every day, the image brief for days 8–14, what Thomas still has to make
    todo = [f"{kind}: {t} ({status})" for kind, t, status in d.get("library", []) if status != "in the library"]
    if d.get("thomas_note"):
        todo.insert(0, d["thomas_note"])
    todo_html = ""
    if todo:
        todo_html = '<p class="b-k">Still to make</p><ul class="todo">' + "".join(f"<li>{esc(t)}</li>" for t in todo) + "</ul>"
    brief_html = ""
    if d.get("image"):
        rows = "".join(f'<div class="b-row"><dt>{esc(k)}</dt><dd>{esc(v)}</dd></div>' for k, v in d["image"])
        brief_html = f'''
    <p class="b-k">Image brief</p>
    <p class="b-title">{esc(d["image_title"])}</p>
    <dl>{rows}</dl>
    <button class="copy" type="button" data-src="img{day}" data-label="Copy image brief">Copy image brief</button>
    <textarea class="copy-src" id="img{day}" readonly aria-hidden="true" tabindex="-1">{esc(brief_text(d))}</textarea>'''
    week = "Week 1 · Understand" if d["week"] == 1 else "Week 2 · Act"
    secs = round(words(d["script"]) / 2.5)
    return f'''
<article class="day" id="day{day}">
  <div class="phone" aria-label="Mockup of the day {day} card">
    <div class="screen">
      <div class="sbar"><span>9:41</span><span class="sb-r">Home</span></div>
      <p class="eyebrow">Foundation Track · Day {day} of 14</p>
      <div class="dots" aria-hidden="true">{dots}</div>
      {pillar}
      <h3 class="d-title">{esc(d["title"])}</h3>
      <div class="video" role="img" aria-label="Video placeholder"><span class="play" aria-hidden="true"></span><span class="v-l">Video with Thomas · about 1 min</span></div>
      <p class="sec">Today</p>
      {today}
      {ig}
      {qblock}
      {extras}
      <p class="sec gold">{esc(d["try_label"])}</p>
      <ul class="acts">{new_rows}</ul>
      <div class="tip"><span class="tip-k">Mini tip</span><p>{esc(d["tip"])}</p></div>
      <p class="sec">Your routine</p>
      <div class="routine">{routine}</div>
      <p class="sec">How it will evolve</p>
      <ol class="evolve">{evolve}</ol>
      {lib}
      <div class="read"><span class="read-k">Short read</span><span class="read-t">{esc(d["read"])}</span><span class="chev" aria-hidden="true">›</span></div>
    </div>
  </div>
  <aside class="brief">
    <p class="b-week">{esc(week)}</p>
    <h3 class="b-day">Day {day} · {esc(d["title"])}</h3>
    <p class="b-k">Video script · EN · about {secs // 60}:{secs % 60:02d}</p>
    <div class="script">{paras(d["script"])}</div>
    <button class="copy" type="button" data-src="scr{day}" data-label="Copy script">Copy script</button>
    <textarea class="copy-src" id="scr{day}" readonly aria-hidden="true" tabindex="-1">{esc(script_text(d))}</textarea>
    {todo_html}
    {brief_html}
  </aside>
</article>'''


def page():
    w1 = "".join(card_html(d) for d in DAYS if d["week"] == 1)
    w2 = "".join(card_html(d) for d in DAYS if d["week"] == 2)
    nav = "".join(f'<a href="#day{d["day"]}">{d["day"]}</a>' for d in DAYS)
    css = (HERE / "style.css").read_text()
    js = (HERE / "script.js").read_text()
    return f'''<title>Foundation Track Cards</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700&family=DM+Serif+Display&display=swap">
<style>{css}</style>
<main class="wrap">
  <header class="head">
    <p class="kicker">FunctionAlps · Foundation Track</p>
    <h1>The 14 day cards</h1>
    <p class="lede">What a member sees on Home each day, in the app's look. Days 1 to 7 each explain a pillar (what it is, why it matters, how we use it), say why the day's questions matter, and end with a first thing to try. Those small things grow into a routine across the four moments of the day. Days 8 to 14 each add one focus, with an infographic. Next to each card: Thomas's video script, and for days 8 to 14 the image brief.</p>
    <nav class="jump" aria-label="Jump to a day">{nav}</nav>
    <div class="style-note"><p class="b-k">Series style for the seven images (days 8–14)</p><p>{esc(SERIES_STYLE)}</p></div>
  </header>
  <section class="week"><h2>Week 1 · Understand you</h2><p class="w-sub">One pillar a day, why we ask, and a first thing to try. No images this week.</p>{w1}</section>
  <section class="week"><h2>Week 2 · Act and notice</h2><p class="w-sub">One focus a day, built on the routine from week 1.</p>{w2}</section>
  <footer class="foot">Text in English; French follows once the English is locked. Gold marks what's new today, the same accent the infographics use. Every call is the 20-minute members call.</footer>
</main>
<script>{js}</script>
'''


if __name__ == "__main__":
    (HERE / "cards.html").write_text(page())
    data = []
    for d in DAYS:
        new, kept = actions_for(d["day"])
        data.append({k: v for k, v in d.items()} | {"new": new, "kept": kept})
    (HERE / "cards.json").write_text(json.dumps({"series_style": SERIES_STYLE, "actions": ACTIONS, "schedule": SCHEDULE, "days": data},
                                                ensure_ascii=False, indent=1))
    for d in DAYS:
        print(d["day"], words(d["script"]), "words", actions_for(d["day"])[0])
