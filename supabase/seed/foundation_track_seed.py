#!/usr/bin/env python3
"""Generates supabase/migrations/20261006_foundation_track_seed.sql from the agreed content
(docs/FOUNDATION_TRACK.md, Thomas 2026-10-06). EN only for now; *_fr stays NULL until the
English is locked. Re-run after editing the content, then apply the SQL (it upserts).

The day titles, the actions (title, one-line how-to, first and last day) and each questionnaire's
title and "why we ask" text come from docs/foundation-cards/build.py, the source of the card
mockups Thomas reviews, so the app and the mockups cannot drift. The card's own text (Today,
mini tip, how it will evolve) goes to supabase/migrations/20261006_foundation_track_day_card_content.sql,
applied after the day-card columns exist.

Shapes the iOS / web renderers read:
  options   [{"value": "...", "label_en": "...", "free_text": true?}]  or  {"source": "track_actions"}
  show_if   {"key": "...", "in": [...]} | {"key": "...", "not_in": [...]} | {"health_connected": false}
  prefill   {"from": "answer", "key": "..."} | {"from": "profile", "fields": [...]} | {"from": "health", "metric": "bedtime"}
  variants  [{"when": <show_if>, "prompt_en": "..."}]
  actions   [{"key", "moment": morning|midday|evening|day, "habit_bank_id"?, "face": easy|standard|further,
              "title_en" (overrides the card title, or names an action with no card), "how_en", "new": bool}]
  card_en   {"pillar"?, "today": "..." | [{"label", "text"}], "try_label", "tip", "evolve": [{"when", "text"}],
             "library": [{"kind", "title"}]}
  push      {"morning"|"midday"|"evening": {"en": "...", "only_if"?: "review_unlocked"}}
            placeholders: {modules} {modules_total} {pct}
"""
import importlib.util
import json
import pathlib
import sys

sys.dont_write_bytecode = True  # importing the card source must not leave a __pycache__ in docs/

TRACK = "foundation_v1"
ROOT = pathlib.Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location("cards", ROOT / "docs" / "foundation-cards" / "build.py")
cards = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cards)
CARD = {d["day"]: d for d in cards.DAYS}


def opts(*pairs):
    out = []
    for p in pairs:
        if isinstance(p, tuple):
            value, label, *rest = p
            o = {"value": value, "label_en": label}
            if rest and rest[0] == "free":
                o["free_text"] = True
            out.append(o)
    return out


GOALS = opts(("energy", "More energy"), ("sleep", "Better sleep"), ("stress", "Less stress"),
             ("lose_weight", "Lose weight"), ("strength_muscle", "Build strength and muscle"),
             ("move_comfortably", "Move more comfortably"), ("digestion", "Better digestion"),
             ("focus", "Focus and clarity"), ("healthy_ageing", "Healthy ageing"),
             ("other", "Something else", "free"))
YES_UPDATE = opts(("yes", "Yes, that's right"), ("update", "Update"))


def q(key, screen, pos, kind, prompt, **kw):
    d = {"question_key": key, "screen": screen, "position": pos, "kind": kind, "prompt_en": prompt}
    d.update(kw)
    return d


QUESTIONNAIRES = [
    dict(id="foundation_d1_you_today", day=1, est_minutes=3, counts_toward_review=True,
         title_en=CARD[1]["questionnaire"][0], intro_en=CARD[1]["questionnaire"][2],
         done_en="Thank you. Tomorrow: nutrition, the first pillar.",
         questions=[
             q("baseline_confirm", 1, 1, "confirm", "From your FunctionAlps record: {baseline}. Still right?",
               options=YES_UPDATE, required=True,
               prefill={"from": "profile", "fields": ["app_age", "app_height_cm", "app_weight_kg", "activity_level"]}),
             q("recent_weight_change", 1, 2, "single", "Over the past 12 months, has your weight…", required=True,
               options=opts(("down", "Gone down"), ("same", "Stayed about the same"), ("up", "Gone up"), ("not_sure", "Not sure"))),
             q("recent_weight_change_kg", 1, 3, "number", "About how many kilos?", unit="kg",
               min_value=0, max_value=80, step=0.5, show_if={"key": "recent_weight_change", "in": ["down", "up"]}),
             q("primary_goals", 2, 1, "multi", "What would you most like to improve? Pick up to 3.",
               options=GOALS, max_select=3, required=True),
             q("success_3_months", 2, 2, "text", "If the next 3 months went really well, what would be different?",
               voice=True, help_en="Optional"),
             q("work_schedule_type", 3, 1, "single", "What does a usual week look like?", required=True,
               options=opts(("regular", "Regular hours"), ("variable", "Variable hours"), ("shift", "Shift work"),
                            ("travel", "Lots of travel"), ("not_working", "Not working at the moment"))),
             q("work_movement", 3, 2, "single", "During your day, are you mostly…", required=True,
               options=opts(("sitting", "Sitting"), ("mix", "A mix of sitting and moving"), ("standing", "Standing"),
                            ("active", "Physically active"))),
             q("wake_time_workdays", 3, 3, "time", "What time do you usually wake up on a workday?", required=True),
             q("short_movement_windows", 4, 1, "multi", "When could you fit 5–10 minutes of movement?",
               options=opts(("after_waking", "After waking"), ("before_work", "Before work"), ("mid_morning", "Mid-morning"),
                            ("lunch_break", "Lunch break"), ("afternoon", "Afternoon"), ("after_work", "After work"),
                            ("evening", "Evening"))),
             q("life_context_note", 4, 2, "text",
               "Anything in your life right now we should keep in mind? Children, caring for someone, a big project, travel…",
               voice=True, help_en="Optional"),
             q("connect_health", 5, 1, "connect_health", "Connect Apple Health",
               help_en="Your phone and watch already know a lot about your movement and sleep. Connecting Apple Health means we don't ask what we can already see."),
             q("enable_notifications", 6, 1, "enable_notifications", "Turn on your reminders",
               help_en="Each day we'll send a short reminder at the right moment: in the morning, after lunch and in the evening. Nothing else. You can change this any time."),
         ]),
    dict(id="foundation_d2_how_you_eat", day=2, est_minutes=2, counts_toward_review=True,
         title_en=CARD[2]["questionnaire"][0], intro_en=CARD[2]["questionnaire"][2],
         done_en="Thank you. Keep photographing your meals. Tomorrow: movement.",
         questions=[
             q("meals_per_day", 1, 1, "single", "How many meals do you usually eat a day?", required=True,
               options=opts(("1", "1"), ("2", "2"), ("3", "3"), ("4_plus", "4 or more"))),
             q("breakfast_frequency", 1, 2, "single", "Do you usually eat breakfast?", required=True,
               options=opts(("most_days", "Most days"), ("some_days", "Some days"), ("rarely", "Rarely or never"))),
             q("lunch_time", 1, 3, "time", "Around what time do you usually have lunch?", required=True),
             q("meal_sources", 2, 1, "multi", "Who usually makes your meals?",
               options=opts(("self", "I cook"), ("family", "My partner or family"), ("restaurant_canteen", "Restaurant or canteen"),
                            ("takeaway_delivery", "Takeaway or delivery"), ("ready_made", "Ready-made meals"))),
             q("protein_sources", 2, 2, "multi", "Which of these do you eat regularly?",
               options=opts(("eggs", "Eggs"), ("fish", "Fish"), ("poultry", "Poultry"), ("red_meat", "Red meat"),
                            ("dairy", "Dairy"), ("legumes", "Beans and lentils"), ("tofu_soy", "Tofu or soy"),
                            ("protein_shakes", "Protein shakes"))),
             q("diet_style", 2, 3, "single", "Do you follow a particular way of eating?",
               options=opts(("none", "No"), ("vegetarian", "Vegetarian"), ("vegan", "Vegan"), ("mediterranean", "Mediterranean"),
                            ("low_carb", "Low-carb"), ("intermittent_fasting", "Intermittent fasting"), ("other", "Other", "free"))),
             q("food_avoid", 2, 4, "text", "Anything you can't or don't eat?", help_en="Optional"),
             q("craving_time", 3, 1, "multi", "When do you tend to snack or have cravings?",
               options=opts(("morning", "Morning"), ("afternoon", "Afternoon"), ("evening", "Evening"),
                            ("after_dinner", "After dinner"), ("not_really", "Not really"))),
             q("water_per_day", 4, 1, "single", "How much water do you drink on a usual day?",
               options=opts(("lt_1", "Under 1 litre"), ("1_1_5", "1–1.5 L"), ("1_5_2", "1.5–2 L"), ("gt_2", "Over 2 L"),
                            ("unknown", "No idea"))),
             q("caffeine_per_day", 4, 2, "single", "Coffee, tea or other caffeine drinks a day?",
               options=opts(("0", "0"), ("1", "1"), ("2", "2"), ("3", "3"), ("4_plus", "4 or more"))),
             q("last_caffeine_time", 4, 3, "single", "When is your last one, usually?",
               show_if={"key": "caffeine_per_day", "not_in": ["0"]},
               options=opts(("before_noon", "Before noon"), ("12_14", "12–14h"), ("14_17", "14–17h"), ("after_17", "After 17h"))),
             q("alcohol_drinks_week", 4, 4, "single", "Alcoholic drinks in a usual week?",
               options=opts(("none", "None"), ("1_3", "1–3"), ("4_7", "4–7"), ("8_14", "8–14"), ("gt_14", "More than 14"))),
         ]),
    dict(id="foundation_d3_how_you_move", day=3, est_minutes=2, counts_toward_review=True,
         title_en=CARD[3]["questionnaire"][0], intro_en=CARD[3]["questionnaire"][2],
         done_en="Thank you. Tonight: two minutes of gentle stretching before bed. Tomorrow: sleep.",
         questions=[
             q("exercise_days_week", 1, 1, "single", "On how many days a week do you exercise on purpose?", required=True,
               options=opts(("0", "0"), ("1", "1"), ("2", "2"), ("3", "3"), ("4", "4"), ("5_plus", "5 or more"))),
             q("current_activities", 1, 2, "multi", "What do you do?",
               show_if={"key": "exercise_days_week", "not_in": ["0"]},
               options=opts(("walking", "Walking"), ("strength_gym", "Strength or gym"), ("running", "Running"),
                            ("cycling", "Cycling"), ("hiking", "Hiking"), ("skiing", "Skiing"), ("swimming", "Swimming"),
                            ("yoga_pilates", "Yoga or Pilates"), ("racket", "Racket sports"), ("team_sport", "Team sport"),
                            ("golf", "Golf"), ("other", "Other", "free"))),
             q("sitting_hours_workday", 1, 3, "single", "On a workday, how many hours do you spend sitting?",
               options=opts(("lt_2", "Under 2"), ("2_4", "2–4"), ("4_6", "4–6"), ("6_8", "6–8"), ("gt_8", "More than 8"))),
             q("self_reported_steps", 1, 4, "single", "About how many steps a day?", show_if={"health_connected": False},
               options=opts(("lt_3000", "Under 3,000"), ("3000_6000", "3,000–6,000"), ("6000_9000", "6,000–9,000"),
                            ("gt_9000", "Over 9,000"), ("unknown", "No idea"))),
             q("past_athletic_history", 2, 1, "single", "Were you regularly active or sporty in the past?",
               options=opts(("a_lot", "Yes, a lot"), ("somewhat", "Somewhat"), ("not_really", "Not really"))),
             q("last_consistently_active", 2, 2, "single", "When were you last regularly active?",
               show_if={"key": "exercise_days_week", "in": ["0"]},
               options=opts(("lt_1y", "Less than a year ago"), ("1_3y", "1–3 years ago"), ("3_5y", "3–5 years ago"),
                            ("gt_5y", "More than 5 years ago"), ("never", "Never really"))),
             q("strength_experience", 2, 3, "single", "How familiar are you with strength training?",
               options=opts(("never", "Never done it"), ("beginner", "Beginner"), ("some", "Some experience"),
                            ("trained_before", "Trained regularly before"), ("training_now", "Training now"))),
             q("movement_discomfort", 3, 1, "single", "Is anything uncomfortable when you move at the moment?", required=True,
               options=opts(("no", "No"), ("yes", "Yes"))),
             q("movement_discomfort_areas", 3, 2, "multi", "Where?", show_if={"key": "movement_discomfort", "in": ["yes"]},
               options=opts(("neck", "Neck"), ("shoulders", "Shoulders"), ("back", "Back"), ("hips", "Hips"),
                            ("knees", "Knees"), ("ankles_feet", "Ankles or feet"), ("other", "Other", "free"))),
             q("movement_safety_note", 3, 3, "info",
               "We'll keep everything gentle. Skip any movement that hurts. If a doctor has asked you to limit activity, follow their advice first.",
               show_if={"key": "movement_discomfort", "in": ["yes"]}),
             q("movement_enjoy", 4, 1, "multi", "Which kinds of movement do you actually enjoy?",
               options=opts(("walking_outside", "Walking outside"), ("hiking_mountains", "Hiking or the mountains"),
                            ("strength_gym", "Strength or gym"), ("classes", "Classes"), ("sport", "Sport"),
                            ("yoga_stretching", "Yoga or stretching"), ("dancing", "Dancing"), ("cycling", "Cycling"),
                            ("other", "Something else (tell us)", "free"), ("not_sure", "Not sure yet"))),
             q("activity_confidence", 4, 2, "slider", "How sure are you that you can move a bit more over the next 2 weeks?",
               min_value=0, max_value=10, step=1,
               variants=[{"when": {"key": "exercise_days_week", "in": ["4", "5_plus"]},
                          "prompt_en": "You already move a lot. How sure are you that you can keep it up over the next 2 weeks, with the daily actions on top?"}]),
         ]),
    dict(id="foundation_d4_how_you_sleep", day=4, est_minutes=2, counts_toward_review=True,
         title_en=CARD[4]["questionnaire"][0], intro_en=CARD[4]["questionnaire"][2],
         done_en="Thank you. Tonight: your phone sleeps outside the bedroom. Tomorrow: mental and emotional health.",
         questions=[
             q("bedtime_workdays", 1, 1, "time", "What time do you usually go to bed on a workday?", required=True,
               prefill={"from": "health", "metric": "bedtime"}),
             q("wake_time_workdays", 1, 2, "time", "You told us you wake up around this time on workdays. Still right?",
               required=True, prefill={"from": "answer", "key": "wake_time_workdays"}),
             q("weekend_shift", 1, 3, "single", "At weekends, do you sleep in?",
               options=opts(("no", "No"), ("up_to_1h", "Up to 1 hour later"), ("1_2h", "1–2 hours later"),
                            ("gt_2h", "More than 2 hours later"))),
             q("sleep_latency", 2, 1, "single", "How long does it usually take you to fall asleep?",
               options=opts(("lt_15", "Under 15 min"), ("15_30", "15–30 min"), ("30_60", "30–60 min"), ("gt_60", "Over an hour"))),
             q("night_wakings", 2, 2, "single", "How often do you wake in the night?",
               options=opts(("rarely", "Rarely"), ("once", "Once"), ("2_3", "2–3 times"), ("4_plus", "4 or more"))),
             q("waking_reasons", 2, 3, "multi", "What usually wakes you?",
               show_if={"key": "night_wakings", "not_in": ["rarely"]},
               options=opts(("bathroom", "Bathroom"), ("thoughts_stress", "Thoughts or stress"), ("pain", "Pain"),
                            ("noise_light", "Noise or light"), ("temperature", "Too hot or cold"),
                            ("partner_children", "Partner or children"), ("unknown", "Don't know"))),
             q("wake_refreshed", 3, 1, "slider", "How refreshed do you usually feel when you wake up?",
               min_value=0, max_value=10, step=1),
             q("screens_before_bed", 3, 2, "single", "In the hour before bed, are you usually on a screen?",
               options=opts(("rarely", "Rarely"), ("some_nights", "Some nights"), ("most_nights", "Most nights"))),
             q("holiday_sleep", 3, 3, "single", "Do you sleep differently on holiday?",
               options=opts(("better", "Better"), ("same", "About the same"), ("worse", "Worse"))),
         ]),
    dict(id="foundation_d5_stress_recovery", day=5, est_minutes=2, counts_toward_review=True,
         title_en=CARD[5]["questionnaire"][0], intro_en=CARD[5]["questionnaire"][2],
         done_en="Thank you: that was the last of the five. In bed tonight: two minutes of box breathing, then one good thing.",
         questions=[
             q("stress_level", 1, 1, "slider", "Overall, how stressed have you felt lately?", min_value=0, max_value=10, step=1,
               required=True),
             q("stress_sources", 1, 2, "multi", "Where does most of it come from?",
               options=opts(("work", "Work"), ("family", "Family"), ("relationship", "Relationship"), ("health", "Health"),
                            ("money", "Money"), ("caregiving", "Caring for someone"), ("big_change", "A big change"),
                            ("prefer_not", "I'd rather not say"))),
             q("switch_off", 2, 1, "single", "How often is it hard to switch off in the evening?",
               options=opts(("rarely", "Rarely"), ("sometimes", "Sometimes"), ("often", "Often"), ("most_days", "Most days"))),
             q("stress_effects", 2, 2, "multi", "When stress is high, what changes for you?",
               options=opts(("sleep", "Sleep"), ("eating", "Eating"), ("energy", "Energy"), ("mood", "Mood"),
                            ("exercise", "Exercise"), ("digestion", "Digestion"), ("concentration", "Concentration"))),
             q("mood_overall", 3, 1, "slider", "Over the past two weeks, how has your mood been overall?",
               min_value=0, max_value=10, step=1),
             q("recovery_methods", 3, 2, "multi", "What helps you recover or switch off?",
               options=opts(("exercise", "Exercise"), ("walking_nature", "Walking or nature"),
                            ("breathing_meditation", "Breathing or meditation"), ("people", "Time with people"),
                            ("reading_music", "Reading or music"), ("screens", "TV or screens"), ("a_drink", "A drink"),
                            ("nothing", "Nothing really"))),
             q("personal_time", 3, 3, "single", "How much time do you have for yourself on a usual day?",
               options=opts(("almost_none", "Almost none"), ("lt_15", "Under 15 min"), ("15_30", "15–30 min"),
                            ("30_60", "30–60 min"), ("gt_60", "More than an hour"))),
         ]),
    dict(id="foundation_d6_first_week", day=6, est_minutes=1, counts_toward_review=False,
         title_en=CARD[6]["questionnaire"][0], intro_en=CARD[6]["questionnaire"][2],
         done_en="See you tomorrow for day seven: everything comes together.",
         questions=[
             q("week1_recap", 1, 1, "info", "Here's what you told us"),
             q("goals_confirm", 2, 1, "single", "On day 1 you chose: {primary_goals}. Still what matters most?", required=True,
               prefill={"from": "answer", "key": "primary_goals"},
               options=opts(("yes", "Yes"), ("change", "I'd change them"))),
             q("primary_goals", 2, 2, "multi", "Pick up to 3.", options=GOALS, max_select=3,
               show_if={"key": "goals_confirm", "in": ["change"]}),
             q("week1_pace", 2, 3, "single", "How did this first week feel?", required=True,
               options=opts(("easy", "Easy"), ("about_right", "About right"), ("a_bit_much", "A bit much"))),
             q("week1_note", 2, 4, "text", "Anything you'd like us to know before next week?", voice=True, help_en="Optional"),
             q("week2_intro", 3, 1, "info",
               "Week two is about action: simple, classic habits that work for almost everybody. Try them, and notice how you feel. Your check-ins will show it."),
         ]),
    dict(id="foundation_d14_two_weeks", day=14, est_minutes=2, counts_toward_review=False,
         title_en=CARD[14]["questionnaire"][0], intro_en=CARD[14]["questionnaire"][2],
         done_en="Thank you for these two weeks.",
         questions=[
             q("two_weeks_compare", 1, 1, "info", "Your check-ins: your first days next to your last days"),
             q("overall_change", 2, 1, "single", "Overall, how do you feel compared with two weeks ago?", required=True,
               options=opts(("much_better", "Much better"), ("a_bit_better", "A bit better"), ("same", "About the same"),
                            ("a_bit_worse", "A bit worse"), ("much_worse", "Much worse"))),
             q("actions_helped", 2, 2, "multi", "Which actions made the biggest difference for you?",
               options={"source": "track_actions"}),
             q("actions_hard", 2, 3, "multi", "Which actions felt hard to fit in?", options={"source": "track_actions"}),
             q("liked_most", 3, 1, "text", "What did you like most about these two weeks?", voice=True, help_en="Optional"),
             q("didnt_work", 3, 2, "text", "What didn't work for you, or felt like too much?", voice=True, help_en="Optional"),
             q("app_ease", 3, 3, "slider", "How easy was the app to use?", min_value=0, max_value=10, step=1),
             q("next_step", 4, 1, "single", "What would you like next?",
               options=opts(("keep_app", "Keep going with the app"), ("personal_programme", "Go deeper with a personal programme"),
                            ("not_sure_talk", "I'm not sure yet, let's talk"), ("not_now", "Not right now"))),
             q("question_for_thomas", 4, 2, "text", "Anything you'd like to ask Thomas before your call?", voice=True,
               help_en="Optional"),
         ]),
]

# ── actions (habit_bank ids verified on CM OS 2026-10-06) ──────────────────────────────────
WALK_LUNCH = "7e6ee768-30fe-4781-ba62-52669aeab7c3"
DAYLIGHT = "afa499c9-5033-43d3-bf0c-81f2b8e70819"
SCREENS_30 = "d76c26e1-2e7c-42f8-8ea1-204413c96916"   # easy face: "Phone out of the bedroom"
SCREENS_60 = "47613f35-cb86-4122-b168-ea3135a7a208"
BOX = "3ca4a693-d097-4a1b-92a2-95343120d2db"
GOOD_THINGS = "4e0ec835-daa1-423f-b51a-8229a55b4f82"  # easy face: "One good thing"
PROTEIN = "8ba3035e-a61f-4458-b078-9918624b8b18"
VEG = "b6cabb08-565b-4f13-8350-7bbc981fa232"
COFFEE = "fc544c65-5f4b-4c36-960a-e49b2aa16377"
KITCHEN = "7dede76d-132c-4274-9812-3edba28dfb62"     # "Kitchen closed 3 hours before bed"

# key → (habit_bank card, face). Moment, title, how-to and first/last day come from the card source.
CARDS = {
    "daylight": (DAYLIGHT, "standard"),
    "protein_breakfast": (PROTEIN, "standard"),
    "walk_after_lunch_5": (WALK_LUNCH, "easy"),
    "walk_after_lunch_10": (WALK_LUNCH, "standard"),
    "lunch_plate": (VEG, "standard"),
    "coffee_before_14": (COFFEE, "standard"),
    "phone_out": (SCREENS_30, "easy"),
    "box_breathing": (BOX, "standard"),
    "one_good_thing": (GOOD_THINGS, "easy"),
    "last_meal": (KITCHEN, "easy"),
    "screens_off_60": (SCREENS_60, "standard"),
}
assert set(CARDS) <= set(cards.ACTIONS)

# the line under the day's title on the card (and on the CLINICAL board)
FOCUS = {
    1: "Why these 14 days, and where you are today. A mini morning routine: water and 3 slow breaths.",
    2: "The nutrition pillar, and why we ask. Photograph everything you eat.",
    3: "Functional capacity. 1 minute of movement, an optional exercise snack, and your evening routine begins.",
    4: "The sleep pillar. Morning daylight; your phone sleeps outside the bedroom.",
    5: "Load and recovery. Box breathing and one good thing before sleep.",
    6: "Your routine in four moments, and a short walk after lunch.",
    7: "A 5-minute morning flow and a daily exercise snack. Your first-week summary is on its way.",
    8: "Why protein matters. Protein at breakfast, then a 10-minute walk.",
    9: "Vegetables, protein and complex carbs; a 10-minute walk after lunch; last coffee before 14:00.",
    10: "Your exercise snack becomes a 5-minute strength routine.",
    11: "Last meal 2–3 hours before bed, screens off, a book, 10 minutes to wind down.",
    12: "A 10-minute morning flow; move 2 minutes every hour or two.",
    13: "Your whole routine on one page: choose what you keep.",
    14: "Where you started, where you are, and your 20-minute review call.",
}
QUESTIONNAIRE_OF_DAY = {1: "foundation_d1_you_today", 2: "foundation_d2_how_you_eat", 3: "foundation_d3_how_you_move",
                        4: "foundation_d4_how_you_sleep", 5: "foundation_d5_stress_recovery", 6: "foundation_d6_first_week",
                        14: "foundation_d14_two_weeks"}

PUSH_TEXT = {
    1: {"evening": "First day done? Your 3-minute questionnaire, if not yet, then your evening check-in."},
    2: {"morning": "Day 2 · Nutrition. Water, 3 slow breaths, then today's video.",
        "midday": "Snap your lunch before the first bite.",
        "evening": "Snap your dinner. Then your nutrition questions: 2 minutes."},
    3: {"morning": "Day 3 · Movement. Water, 3 breaths, 1 minute of moving.",
        "midday": "Feel like an exercise snack? 10 squats, or a minute up the stairs.",
        "evening": "Your movement questions, then 2 minutes of stretching before bed."},
    4: {"morning": "Day 4 · Sleep. Your morning routine, then 5 minutes of daylight.",
        "midday": "Snap your lunch.",
        "evening": "Your phone sleeps outside the bedroom tonight. Your sleep questions: 2 minutes."},
    5: {"morning": "Day 5 · Mental and emotional health. Water, breaths, move, daylight.",
        "midday": "Snap your lunch.",
        "evening": "In bed: 2 minutes of box breathing, then one good thing. Last questionnaire today."},
    6: {"morning": "Day 6 · Your first week, on one page.",
        "midday": "New today: 5 minutes outside after lunch.",
        "evening": "Stretch, phone out, breathe, one good thing."},
    7: {"morning": "Day 7 · Your full day starts with a 5-minute morning flow.",
        "midday": "Your walk after lunch. And today's exercise snack?",
        "evening": "Stretch, phone out, breathe, one good thing. Your week-1 summary is on its way."},
    8: {"morning": "Day 8 · Protein at breakfast, then a 10-minute walk.",
        "midday": "Your walk after lunch.",
        "evening": "Your evening routine, then your check-in."},
    9: {"morning": "Day 9 · Today's focus is lunch: vegetables, protein, complex carbs.",
        "midday": "10 minutes of walking, now. Last coffee before 14:00.",
        "evening": "Your evening routine, then your check-in."},
    10: {"morning": "Day 10 · Easy strength: your 5-minute routine is in today's video.",
         "midday": "Walk after lunch. Strength routine done yet?",
         "evening": "Your evening routine, then your check-in."},
    11: {"morning": "Day 11 · Tonight: your full evening routine.",
         "midday": "Your walk after lunch.",
         "evening": "Screens off, lights low. A book, then 10 minutes to wind down."},
    12: {"morning": "Day 12 · Your morning flow grows to 10 minutes.",
         "midday": "Walk after lunch. Every hour or two: stand up and move for 2 minutes.",
         "evening": "Where you stand: {modules}/{modules_total} questionnaires, {pct}% of meals. 2 days to go."},
    13: {"morning": "Day 13 · Your whole routine, on one page. Which actions will you keep?",
         "midday": "Your walk after lunch.",
         "evening": "Your evening routine, then your check-in."},
    14: {"morning": "Day 14 · Two weeks. See how far you've come, and tell us how it was.",
         "evening": {"en": "Your 20-minute review call with Thomas is ready to book.", "only_if": "review_unlocked"}},
}


def day_actions(day):
    out = []
    for key, first, last in cards.SCHEDULE:
        if day < first or (last is not None and day > last):
            continue
        moment, title, how = cards.ACTIONS[key]
        card, face = CARDS.get(key, (None, "standard"))
        a = {"key": key, "moment": moment, "face": face, "new": day == first, "title_en": title, "how_en": how}
        if card:
            a["habit_bank_id"] = card
        out.append(a)
    return out


def day_card(day):
    d = CARD[day]
    today = d["today"] if isinstance(d["today"], str) else [{"label": k, "text": v} for k, v in d["today"]]
    out = {"today": today, "try_label": d["try_label"], "tip": d["tip"],
           "evolve": [{"when": w, "text": t} for w, t in d["evolve"]],
           "library": [{"kind": k, "title": t} for k, t, _ in d.get("library", [])]}
    if d.get("pillar"):
        out["pillar"] = d["pillar"]
    return out


def day_push(day):
    out = {}
    for moment, v in PUSH_TEXT[day].items():
        out[moment] = v if isinstance(v, dict) else {"en": v}
    return out


def sql_json(obj):
    s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    assert "$seed$" not in s
    return "$seed$" + s + "$seed$::jsonb"


def main():
    questionnaires = [{k: v for k, v in qn.items() if k != "questions"} | {"track_code": TRACK} for qn in QUESTIONNAIRES]
    questions = []
    for qn in QUESTIONNAIRES:
        for qq in qn["questions"]:
            questions.append({"questionnaire_id": qn["id"], "required": False, "voice": False} | qq)
    days = [{"track_code": TRACK, "day": d, "title_en": CARD[d]["title"], "focus_en": FOCUS[d],
             "questionnaire_id": QUESTIONNAIRE_OF_DAY.get(d), "actions": day_actions(d), "push": day_push(d)}
            for d in sorted(CARD)]
    assert len(days) == 14 and all(PUSH_TEXT.get(d["day"]) for d in days)
    assert {q["id"] for q in QUESTIONNAIRES} == set(QUESTIONNAIRE_OF_DAY.values())

    lines = [
        "-- GENERATED by supabase/seed/foundation_track_seed.py from docs/FOUNDATION_TRACK.md. Do not edit by hand.",
        "-- The Foundation Track content, EN (FR to follow). Upserts: safe to re-apply after a content edit.",
        "",
        "insert into public.track_questionnaire (id, track_code, day, title_en, intro_en, done_en, est_minutes, counts_toward_review)",
        "select id, track_code, day, title_en, intro_en, done_en, est_minutes, counts_toward_review",
        f"  from jsonb_to_recordset({sql_json(questionnaires)})",
        "    as x(id text, track_code text, day int, title_en text, intro_en text, done_en text, est_minutes int, counts_toward_review boolean)",
        "on conflict (id) do update set day = excluded.day, title_en = excluded.title_en, intro_en = excluded.intro_en,",
        "  done_en = excluded.done_en, est_minutes = excluded.est_minutes, counts_toward_review = excluded.counts_toward_review;",
        "",
        "insert into public.track_question (questionnaire_id, question_key, screen, position, kind, prompt_en, help_en, options,",
        "  max_select, min_value, max_value, step, unit, required, voice, show_if, prefill, variants)",
        "select questionnaire_id, question_key, screen, position, kind, prompt_en, help_en, options,",
        "  max_select, min_value, max_value, step, unit, required, voice, show_if, prefill, variants",
        f"  from jsonb_to_recordset({sql_json(questions)})",
        "    as x(questionnaire_id text, question_key text, screen int, position int, kind text, prompt_en text, help_en text,",
        "         options jsonb, max_select int, min_value numeric, max_value numeric, step numeric, unit text,",
        "         required boolean, voice boolean, show_if jsonb, prefill jsonb, variants jsonb)",
        "on conflict (questionnaire_id, question_key) do update set screen = excluded.screen, position = excluded.position,",
        "  kind = excluded.kind, prompt_en = excluded.prompt_en, help_en = excluded.help_en, options = excluded.options,",
        "  max_select = excluded.max_select, min_value = excluded.min_value, max_value = excluded.max_value, step = excluded.step,",
        "  unit = excluded.unit, required = excluded.required, voice = excluded.voice, show_if = excluded.show_if,",
        "  prefill = excluded.prefill, variants = excluded.variants;",
        "",
        "insert into public.track_day (track_code, day, title_en, focus_en, questionnaire_id, actions, push)",
        "select track_code, day, title_en, focus_en, questionnaire_id, actions, push",
        f"  from jsonb_to_recordset({sql_json(days)})",
        "    as x(track_code text, day int, title_en text, focus_en text, questionnaire_id text, actions jsonb, push jsonb)",
        "on conflict (track_code, day) do update set title_en = excluded.title_en, focus_en = excluded.focus_en,",
        "  questionnaire_id = excluded.questionnaire_id, actions = excluded.actions, push = excluded.push;",
        "",
    ]
    out = ROOT / "supabase" / "migrations" / "20261006_foundation_track_seed.sql"
    out.write_text("\n".join(lines))
    print(out, len(questionnaires), "questionnaires,", len(questions), "questions,", len(days), "days")

    card_rows = [{"track_code": TRACK, "day": d, "card_en": day_card(d)} for d in sorted(CARD)]
    card_sql = [
        "-- GENERATED by supabase/seed/foundation_track_seed.py from docs/foundation-cards/build.py. Do not edit by hand.",
        "-- The day card's own text, EN. Needs 20261006_foundation_track_day_card.sql applied first. Safe to re-apply.",
        "",
        "update public.track_day t set card_en = x.card_en",
        f"  from jsonb_to_recordset({sql_json(card_rows)}) as x(track_code text, day int, card_en jsonb)",
        " where t.track_code = x.track_code and t.day = x.day;",
        "",
    ]
    out2 = ROOT / "supabase" / "migrations" / "20261006_foundation_track_day_card_content.sql"
    out2.write_text("\n".join(card_sql))
    print(out2, len(card_rows), "cards")


if __name__ == "__main__":
    main()
