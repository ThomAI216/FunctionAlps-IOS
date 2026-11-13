-- signal_explanations: the practice's curated explanation of each check-in signal, shown in the members app
-- ("About energy", "About sleep", ... and "About your functional score"), 2026-11-11 (owner's decision; owner priority
-- P0/P1 of 2026-11-10, docs/ROADMAP_SIGNALS_ECOSYSTEM.md).
--
-- This is practice-curated, clinician-reviewed member content. The app RENDERS it and never invents it: there is no
-- explanation text in Swift (CLAUDE.md rule 6). A signal with no approved row simply shows no explanation.
--
-- One row per (signal, locale, version). `signal` is one of sleep | energy | focus | mood | stress | digestion | score
-- (score = the Functional score). `locale` is en | fr. The app reads the NEWEST approved version per signal in the
-- member's language. `review_status` is draft | approved; members can only read approved rows (RLS below).
--
-- `content` (jsonb) shape — every key below is read by the app; unknown keys are ignored, a missing optional key or
-- array means "that block is hidden":
--   {
--     "title":        "About energy",                  page title
--     "what_it_is":   "...",                           "What it is" paragraph
--     "feels_high":   "...",                           "What it feels like" — the good end (shown green)
--     "feels_low":    "...",                           "What it feels like" — the other end (shown red-orange)
--     "feels_high_label": "Calm",                      optional, the chip word for the good end (default: High)
--     "feels_low_label":  "High stress",               optional, the chip word for the other end (default: Low)
--     "card_text":    "...",                           the short text on the Trends row ("What influences it")
--     "influences_intro":   "...",                     optional, a lead-in above the influence rows
--     "influences": [                                  "What influences it", one row each, tap to open its Why
--       { "icon": "sleep|move|food|water|stress|mind|caffeine|light|alcohol|social|screen|breath|time",
--         "line": "...",                               the member-facing line
--         "why":  "...",                               the mechanism, shown when the row is opened
--         "evidence": "strong|moderate|emerging" } ],  badge: Strong (green) · Moderate (blue) · Emerging (purple)
--     "connections_intro":  "...",                     optional, replaces the default caption under "How it connects"
--     "connections": [                                 the mini map: this signal in the centre
--       { "to": "mood",                                the other signal (sleep|energy|focus|mood|stress|digestion)
--         "direction": "out|in|both",                  out = this signal moves it · in = it moves this signal
--         "label": "...",                              a short word on the arrow
--         "evidence": "strong|moderate|emerging" } ],  optional, the line style (solid · dashed · dotted)
--     "actions": [                                     "Easy ways to influence it"
--       { "text": "...",
--         "habit_hint": "walk|daylight|protein_breakfast|hydration|breathwork|nsdr|bedtime|..." } ],
--                                                      a hint the app matches to an action card of the bank; no match
--                                                      opens the action bank. Never a habit the practice has not written.
--     "plate_intro": "...",                            energy only: "What's on your plate"
--     "plate": [ { "key": "carbs|protein|fat|fibre", "title": "Carbs", "line": "...", "evidence": "..." } ],
--     "plate_rule": { "title": "...", "line": "...", "evidence": "..." },
--     "safety_line": "If this stays low for weeks, talk to your practitioner.",
--     "sources": ["Lim & Dinges 2010 · Psychol Bull", ...]   the list at the bottom of the page
--   }
--
-- Who reads/writes: members SELECT approved rows (RLS: authenticated, review_status = 'approved'); writes are service
-- role only (the practice, through the CLINICAL dashboard or a reviewed migration). Nothing for anon.
--
-- ADDITIVE and IDEMPOTENT: the table is created if missing and the 14 seed rows (7 signals x en/fr, v1, approved by
-- the owner 2026-11-11) are upserted on (signal, locale, version). NOT applied by the commit that adds it: the owner
-- applies it after review. Until it is applied the app treats the missing table as "no explanations" and hides the
-- new blocks.
-- Seed text: en from the research draft (docs: signals-research, 25 sources); fr a faithful translation, "vous".

create table if not exists public.signal_explanations (
  id            uuid primary key default gen_random_uuid(),
  signal        text not null check (signal in ('sleep', 'energy', 'focus', 'mood', 'stress', 'digestion', 'score')),
  locale        text not null check (locale in ('en', 'fr')),
  version       int  not null default 1,
  content       jsonb not null,
  review_status text not null default 'draft' check (review_status in ('draft', 'approved')),
  approved_by   text,
  approved_at   timestamptz,
  updated_at    timestamptz not null default now(),
  unique (signal, locale, version)
);

comment on table public.signal_explanations is
  'Practice-curated, clinician-reviewed member content: the explanation of each check-in signal (what it is, what it feels like, what influences it, how it connects, easy ways to influence it, sources). The app renders it, never invents it. Shape of content: see the header of migration 20261111090000_signal_explanations.sql.';

alter table public.signal_explanations enable row level security;

do $$ begin
  create policy signal_explanations_read_approved on public.signal_explanations
    for select to authenticated
    using (review_status = 'approved');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy signal_explanations_service_all on public.signal_explanations
    for all to service_role using (true) with check (true);
exception when duplicate_object then null; end $$;

revoke all on public.signal_explanations from anon;
grant select on public.signal_explanations to authenticated;
grant all on public.signal_explanations to service_role;

-- Seed: 7 signals x en/fr, version 1, approved by the owner on 2026-11-11.
insert into public.signal_explanations (signal, locale, version, content, review_status, approved_by, approved_at) values
  ('sleep', 'en', 1, $json$
{
  "title": "About sleep",
  "what_it_is": "How well you slept: how long, how deeply, and how rested you feel on waking.",
  "feels_high": "You wake up fairly easily, feel clear within an hour, and don't need to fight the afternoon.",
  "feels_low": "Heavy mornings, waking at night, feeling \"wired but tired\", leaning on caffeine.",
  "card_text": "Sleep is shaped by light, caffeine, alcohol, movement and how calm you feel at bedtime. Morning daylight and a dimmer evening help most people sleep deeper. Poor sleep then pulls down energy, focus and mood.",
  "influences": [
    {
      "icon": "light",
      "line": "Daylight early in the day, and dimmer light in the evening, help your body know when it is night.",
      "why": "Light is the main signal that sets the body clock; bright light in the evening delays and shortens the night-time melatonin rise.",
      "evidence": "strong"
    },
    {
      "icon": "caffeine",
      "line": "Caffeine late in the day can cost you sleep, even if you fall asleep fine.",
      "why": "Caffeine blocks the \"sleepiness\" signal for hours; even a dose 6 hours before bed measurably cut sleep time in a trial.",
      "evidence": "strong"
    },
    {
      "icon": "alcohol",
      "line": "Alcohol may help you drop off, but it often makes the second half of the night lighter.",
      "why": "It shortens time to sleep but disrupts sleep later in the night and tends to reduce REM.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Moving your body during the day is linked to deeper, easier sleep.",
      "why": "Regular activity builds sleep pressure and steadies the body clock; effects are small to moderate and strongest for regular exercise over weeks.",
      "evidence": "moderate"
    },
    {
      "icon": "breath",
      "line": "A busy mind at bedtime makes sleep lighter; winding down helps your nervous system switch off.",
      "why": "Stress keeps the body in a more alert state; slow breathing and calm routines shift it toward rest.",
      "evidence": "moderate"
    },
    {
      "icon": "screen",
      "line": "Screens and bright light close to bed push your sleep later.",
      "why": "Evening light (including e-readers) suppresses melatonin and delays the body clock, with next-morning grogginess.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "A big or late meal can make the night less restful for some people.",
      "why": "Digestion and reflux are more active lying down; individual and food-dependent.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "energy",
      "direction": "out",
      "label": "alertness",
      "evidence": "strong"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "attention",
      "evidence": "strong"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "positive mood",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "out",
      "label": "feels heavier",
      "evidence": "moderate"
    },
    {
      "to": "digestion",
      "direction": "out",
      "label": "gut reactivity",
      "evidence": "emerging"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "lighter sleep",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "rumination",
      "evidence": "emerging"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "late meals",
      "evidence": "emerging"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "active days",
      "evidence": "moderate"
    }
  ],
  "actions": [
    {
      "text": "Get 10 minutes of daylight within an hour of waking.",
      "habit_hint": "daylight"
    },
    {
      "text": "Keep your last coffee or tea before early afternoon.",
      "habit_hint": "caffeine_cutoff"
    },
    {
      "text": "Dim lights and put screens away for the last hour before bed.",
      "habit_hint": "wind_down"
    },
    {
      "text": "Keep wake-up time within an hour of the same every day.",
      "habit_hint": "wake_time"
    },
    {
      "text": "Take a 20–30 minute walk most days, ideally not right before bed.",
      "habit_hint": "walk"
    },
    {
      "text": "Try five slow breaths in bed, longer out than in.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "If this stays low for weeks, talk to your practitioner.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Lim & Dinges 2010 · Psychol Bull",
    "Drake 2013 · J Clin Sleep Med",
    "Kredlow 2015 · J Behav Med",
    "Gooley 2011 · J Clin Endocrinol Metab",
    "Chang 2015 · PNAS",
    "Goyal 2014 · JAMA Intern Med",
    "Fincham 2023 · Sci Rep",
    "Ebrahim 2013 · Alcohol Clin Exp Res",
    "Khalsa 2003 · J Physiol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('sleep', 'fr', 1, $json$
{
  "title": "À propos du sommeil",
  "what_it_is": "La qualité de votre sommeil : sa durée, sa profondeur et à quel point vous vous sentez reposé(e) au réveil.",
  "feels_high": "Vous vous réveillez assez facilement, vous avez les idées claires en moins d’une heure et vous n’avez pas à lutter contre le coup de barre de l’après-midi.",
  "feels_low": "Des matins lourds, des réveils nocturnes, l’impression d’être « épuisé(e) mais sur les nerfs », un besoin de caféine pour tenir.",
  "card_text": "Le sommeil dépend de la lumière, de la caféine, de l’alcool, du mouvement et de votre calme au moment du coucher. La lumière du jour le matin et une soirée plus tamisée aident la plupart des gens à mieux dormir. Un mauvais sommeil fait ensuite baisser l’énergie, la concentration et l’humeur.",
  "influences": [
    {
      "icon": "light",
      "line": "La lumière du jour en début de journée et une lumière plus douce le soir aident votre corps à savoir quand c’est la nuit.",
      "why": "La lumière est le principal signal qui règle l’horloge interne ; une lumière vive le soir retarde et raccourcit la hausse nocturne de mélatonine.",
      "evidence": "strong"
    },
    {
      "icon": "caffeine",
      "line": "La caféine en fin de journée peut vous coûter du sommeil, même si vous vous endormez sans problème.",
      "why": "La caféine bloque pendant des heures le signal de « somnolence » ; même une dose prise 6 heures avant le coucher a réduit de façon mesurable le temps de sommeil dans une étude.",
      "evidence": "strong"
    },
    {
      "icon": "alcohol",
      "line": "L’alcool peut aider à s’endormir, mais il rend souvent la seconde moitié de la nuit plus légère.",
      "why": "Il raccourcit le temps d’endormissement mais perturbe le sommeil plus tard dans la nuit et tend à réduire le sommeil paradoxal (REM).",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Bouger pendant la journée est associé à un sommeil plus profond et plus facile.",
      "why": "L’activité régulière augmente la pression de sommeil et stabilise l’horloge interne ; les effets sont faibles à modérés et surtout nets avec un exercice régulier sur plusieurs semaines.",
      "evidence": "moderate"
    },
    {
      "icon": "breath",
      "line": "Un esprit agité au coucher rend le sommeil plus léger ; ralentir le rythme aide votre système nerveux à se mettre au repos.",
      "why": "Le stress maintient le corps dans un état de vigilance accrue ; la respiration lente et les routines calmes l’orientent vers le repos.",
      "evidence": "moderate"
    },
    {
      "icon": "screen",
      "line": "Les écrans et la lumière vive juste avant le coucher repoussent votre sommeil.",
      "why": "La lumière du soir (y compris celle des liseuses) freine la mélatonine et retarde l’horloge interne, avec un réveil plus brumeux le lendemain.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "Un repas copieux ou tardif peut rendre la nuit moins reposante chez certaines personnes.",
      "why": "La digestion et le reflux sont plus marqués en position couchée ; cela varie selon les personnes et les aliments.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "energy",
      "direction": "out",
      "label": "vigilance",
      "evidence": "strong"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "attention",
      "evidence": "strong"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "humeur positive",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "out",
      "label": "charge ressentie",
      "evidence": "moderate"
    },
    {
      "to": "digestion",
      "direction": "out",
      "label": "réactivité intestinale",
      "evidence": "emerging"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "sommeil plus léger",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "ruminations",
      "evidence": "emerging"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "repas tardifs",
      "evidence": "emerging"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "journées actives",
      "evidence": "moderate"
    }
  ],
  "actions": [
    {
      "text": "Prenez 10 minutes de lumière du jour dans l’heure qui suit le réveil.",
      "habit_hint": "daylight"
    },
    {
      "text": "Prenez votre dernier café ou thé avant le début de l’après-midi.",
      "habit_hint": "caffeine_cutoff"
    },
    {
      "text": "Baissez les lumières et rangez les écrans pendant la dernière heure avant le coucher.",
      "habit_hint": "wind_down"
    },
    {
      "text": "Gardez une heure de lever à peu près identique chaque jour, à une heure près.",
      "habit_hint": "wake_time"
    },
    {
      "text": "Faites une marche de 20 à 30 minutes presque tous les jours, de préférence pas juste avant le coucher.",
      "habit_hint": "walk"
    },
    {
      "text": "Essayez cinq respirations lentes au lit, en expirant plus longuement qu’en inspirant.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "Si cela reste bas pendant des semaines, parlez-en à votre praticienne.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Lim & Dinges 2010 · Psychol Bull",
    "Drake 2013 · J Clin Sleep Med",
    "Kredlow 2015 · J Behav Med",
    "Gooley 2011 · J Clin Endocrinol Metab",
    "Chang 2015 · PNAS",
    "Goyal 2014 · JAMA Intern Med",
    "Fincham 2023 · Sci Rep",
    "Ebrahim 2013 · Alcohol Clin Exp Res",
    "Khalsa 2003 · J Physiol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('energy', 'en', 1, $json$
{
  "title": "About energy",
  "what_it_is": "How much usable get-up-and-go you have, not just how awake you are.",
  "feels_high": "Steady through the day, tasks feel doable.",
  "feels_low": "Heavy, slow, mid-afternoon crashes, everything takes effort.",
  "card_text": "Energy is influenced by how you slept, how you move, what and when you eat, how much you drink and how stressed you are. Protein and fibre often keep it steadier; big refined-carb meals often feel sluggish.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Sleep sets the ceiling: after a short night, energy is lower and less steady.",
      "why": "Sleep loss slows reaction and lowers alertness and sustained attention.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Moving your body, even gently, tends to make you feel more energised, not less.",
      "why": "Regular activity improves the felt sense of energy and lowers fatigue in sedentary people.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "What you eat shapes the day: big refined-carb meals often feel sluggish; protein and fibre tend to keep energy steadier.",
      "why": "Fast-digesting carbs raise and drop blood sugar quickly; protein, fats and fibre slow digestion and add fullness.",
      "evidence": "moderate"
    },
    {
      "icon": "water",
      "line": "Not drinking enough can quietly dull energy and concentration.",
      "why": "Even small fluid deficits are linked to tiredness and poorer mood and attention in some studies.",
      "evidence": "moderate"
    },
    {
      "icon": "stress",
      "line": "Ongoing stress burns energy, because your body stays on alert without a real recovery.",
      "why": "Prolonged activation keeps arousal high while recovery is short.",
      "evidence": "emerging"
    },
    {
      "icon": "mind",
      "line": "How you feel for the day matters: mood, motivation and how you woke up colour how energetic you feel.",
      "why": "Perceived energy is partly mood and expectation; waking after a long sleep inertia window feels flat.",
      "evidence": "emerging"
    },
    {
      "icon": "caffeine",
      "line": "Caffeine can lift alertness for a few hours, especially after a short night, but it doesn't replace sleep.",
      "why": "It blocks sleepiness signals temporarily.",
      "evidence": "strong"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "alertness",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "burns energy",
      "evidence": "emerging"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "effort",
      "evidence": "moderate"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "concentration",
      "evidence": "moderate"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "harder day",
      "evidence": "emerging"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "active days",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "flat days",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Put protein in your first meal of the day.",
      "habit_hint": "protein_breakfast"
    },
    {
      "text": "Swap one refined-carb meal for whole food with fibre.",
      "habit_hint": "fibre"
    },
    {
      "text": "Walk for 10 minutes after a meal.",
      "habit_hint": "walk_after_meal"
    },
    {
      "text": "Keep a glass of water with you; drink regularly.",
      "habit_hint": "hydration"
    },
    {
      "text": "Do two minutes of movement when you feel the afternoon dip.",
      "habit_hint": "movement_break"
    },
    {
      "text": "Protect a regular bedtime tonight.",
      "habit_hint": "bedtime"
    }
  ],
  "plate_intro": "Energy is shaped by what's on your plate. Everyone is a little different, so watch how you feel after meals.",
  "plate": [
    {
      "key": "carbs",
      "title": "Carbs",
      "line": "A big refined-carb meal often leaves you sluggish an hour or two later. Whole, high-fibre carbs are digested more slowly.",
      "evidence": "emerging"
    },
    {
      "key": "protein",
      "title": "Protein",
      "line": "Protein adds fullness and tends to keep appetite, and so energy, steadier between meals.",
      "evidence": "moderate"
    },
    {
      "key": "fat",
      "title": "Fat",
      "line": "A bit of fat helps you stay full. Very fatty or fried meals are, for many people, a common cause of heaviness.",
      "evidence": "emerging"
    },
    {
      "key": "fibre",
      "title": "Fibre",
      "line": "Fibre slows sugar absorption and supports regular stools. It needs water, and is best increased gradually.",
      "evidence": "strong"
    }
  ],
  "plate_rule": {
    "title": "The practical rule",
    "line": "Combine protein, fibre and fat with carbohydrate, not carbs alone. Regular meals avoid long gaps, and a short walk after a meal can flatten a dip.",
    "evidence": "moderate"
  },
  "safety_line": "If this stays low for weeks, talk to your practitioner.",
  "sources": [
    "Lim & Dinges 2010 · Psychol Bull",
    "Kredlow 2015 · J Behav Med",
    "Noetel 2024 · BMJ",
    "Reynolds 2019 · Lancet",
    "Leidy 2015 · Am J Clin Nutr",
    "Firth 2019 · Psychosom Med",
    "Engeroff 2023 · Sports Med",
    "Irwin 2020 · Neurosci Biobehav Rev",
    "Mou 2026 · Am J Clin Nutr",
    "Gangwisch 2015 · Am J Clin Nutr",
    "Qin 2014 · World J Gastroenterol",
    "Puetz 2008 · Psychother Psychosom",
    "O'Connor & Puetz 2005 · Med Sci Sports Exerc",
    "Benton & Young 2015 · Nutr Rev",
    "Ker 2010 · Cochrane Database Syst Rev"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('energy', 'fr', 1, $json$
{
  "title": "À propos de l’énergie",
  "what_it_is": "La quantité d’élan réellement utilisable dont vous disposez, pas seulement votre degré d’éveil.",
  "feels_high": "Stable tout au long de la journée, les tâches paraissent faisables.",
  "feels_low": "Lourdeur, lenteur, coups de barre en milieu d’après-midi, tout demande un effort.",
  "card_text": "L’énergie dépend de votre sommeil, de votre activité, de ce que vous mangez et de quand, de ce que vous buvez et de votre niveau de stress. Les protéines et les fibres la stabilisent souvent ; les gros repas riches en glucides raffinés laissent souvent une impression de lourdeur.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Le sommeil fixe le plafond : après une courte nuit, l’énergie est plus basse et moins stable.",
      "why": "Le manque de sommeil ralentit les réactions et réduit la vigilance ainsi que l’attention soutenue.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Bouger, même doucement, tend à vous donner plus d’énergie, pas moins.",
      "why": "L’activité régulière améliore la sensation d’énergie et diminue la fatigue chez les personnes sédentaires.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "Ce que vous mangez façonne la journée : les gros repas riches en glucides raffinés laissent souvent une sensation de lourdeur ; les protéines et les fibres tendent à stabiliser l’énergie.",
      "why": "Les glucides à digestion rapide font monter puis chuter vite la glycémie ; les protéines, les graisses et les fibres ralentissent la digestion et donnent une sensation de satiété.",
      "evidence": "moderate"
    },
    {
      "icon": "water",
      "line": "Ne pas boire assez peut émousser discrètement l’énergie et la concentration.",
      "why": "Même de petits déficits en liquides sont associés, dans certaines études, à de la fatigue, à une humeur plus basse et à une moins bonne attention.",
      "evidence": "moderate"
    },
    {
      "icon": "stress",
      "line": "Un stress qui dure épuise l’énergie, car votre corps reste en alerte sans vraie récupération.",
      "why": "Une activation prolongée maintient un niveau d’éveil élevé alors que la récupération est brève.",
      "evidence": "emerging"
    },
    {
      "icon": "mind",
      "line": "Votre ressenti de la journée compte : l’humeur, la motivation et la manière dont vous vous êtes réveillé(e) colorent votre sensation d’énergie.",
      "why": "L’énergie perçue dépend en partie de l’humeur et des attentes ; se réveiller pendant une longue phase d’inertie du sommeil donne une impression de platitude.",
      "evidence": "emerging"
    },
    {
      "icon": "caffeine",
      "line": "La caféine peut augmenter la vigilance pendant quelques heures, surtout après une courte nuit, mais elle ne remplace pas le sommeil.",
      "why": "Elle bloque temporairement les signaux de somnolence.",
      "evidence": "strong"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "vigilance",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "épuise l’énergie",
      "evidence": "emerging"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "effort",
      "evidence": "moderate"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "concentration",
      "evidence": "moderate"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "journée plus dure",
      "evidence": "emerging"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "journées actives",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "journées sans élan",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Mettez des protéines dans votre premier repas de la journée.",
      "habit_hint": "protein_breakfast"
    },
    {
      "text": "Remplacez un repas riche en glucides raffinés par des aliments complets riches en fibres.",
      "habit_hint": "fibre"
    },
    {
      "text": "Marchez 10 minutes après un repas.",
      "habit_hint": "walk_after_meal"
    },
    {
      "text": "Gardez un verre d’eau à portée de main et buvez régulièrement.",
      "habit_hint": "hydration"
    },
    {
      "text": "Faites deux minutes de mouvement quand vous sentez le creux de l’après-midi.",
      "habit_hint": "movement_break"
    },
    {
      "text": "Protégez une heure de coucher régulière dès ce soir.",
      "habit_hint": "bedtime"
    }
  ],
  "plate_intro": "L’énergie dépend de ce qu’il y a dans votre assiette. Chacun est un peu différent : observez comment vous vous sentez après les repas.",
  "plate": [
    {
      "key": "carbs",
      "title": "Glucides",
      "line": "Un gros repas riche en glucides raffinés laisse souvent une sensation de lourdeur une à deux heures plus tard. Les glucides complets, riches en fibres, sont digérés plus lentement.",
      "evidence": "emerging"
    },
    {
      "key": "protein",
      "title": "Protéines",
      "line": "Les protéines donnent une sensation de satiété et tendent à stabiliser l’appétit, donc l’énergie, entre les repas.",
      "evidence": "moderate"
    },
    {
      "key": "fat",
      "title": "Graisses",
      "line": "Un peu de graisse aide à rester rassasié(e). Les repas très gras ou frits sont, pour beaucoup de personnes, une cause fréquente de lourdeur.",
      "evidence": "emerging"
    },
    {
      "key": "fibre",
      "title": "Fibres",
      "line": "Les fibres ralentissent l’absorption du sucre et favorisent un transit régulier. Elles ont besoin d’eau et il vaut mieux les augmenter progressivement.",
      "evidence": "strong"
    }
  ],
  "plate_rule": {
    "title": "La règle pratique",
    "line": "Associez protéines, fibres et graisses aux glucides, plutôt que de manger des glucides seuls. Des repas réguliers évitent les longs jeûnes, et une courte marche après le repas peut aplatir un creux.",
    "evidence": "moderate"
  },
  "safety_line": "Si cela reste bas pendant des semaines, parlez-en à votre praticienne.",
  "sources": [
    "Lim & Dinges 2010 · Psychol Bull",
    "Kredlow 2015 · J Behav Med",
    "Noetel 2024 · BMJ",
    "Reynolds 2019 · Lancet",
    "Leidy 2015 · Am J Clin Nutr",
    "Firth 2019 · Psychosom Med",
    "Engeroff 2023 · Sports Med",
    "Irwin 2020 · Neurosci Biobehav Rev",
    "Mou 2026 · Am J Clin Nutr",
    "Gangwisch 2015 · Am J Clin Nutr",
    "Qin 2014 · World J Gastroenterol",
    "Puetz 2008 · Psychother Psychosom",
    "O'Connor & Puetz 2005 · Med Sci Sports Exerc",
    "Benton & Young 2015 · Nutr Rev",
    "Ker 2010 · Cochrane Database Syst Rev"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('focus', 'en', 1, $json$
{
  "title": "About focus",
  "what_it_is": "How well you can hold your attention on one thing and think clearly.",
  "feels_high": "You stay with a task and ideas connect.",
  "feels_low": "Foggy, distractible, rereading the same line.",
  "card_text": "Focus is influenced mainly by sleep, then movement, caffeine timing, steady meals, fluids and how stressed or distracted you are. A short walk often sharpens thinking for about an hour.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Sleep is the biggest lever: short nights reliably cut attention and working memory.",
      "why": "Sleep loss impairs the brain networks that sustain attention.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "A short bout of movement can sharpen thinking for the next hour or so.",
      "why": "Acute exercise gives a small improvement in cognitive performance, mainly afterwards.",
      "evidence": "moderate"
    },
    {
      "icon": "caffeine",
      "line": "Caffeine helps alertness, most when you are tired, but a late dose costs sleep that costs focus.",
      "why": "Caffeine restores some performance after sleep loss.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "Steady meals help: a big refined-carb lunch can bring on a post-meal dip for some people.",
      "why": "Blood-sugar swings and post-meal drowsiness.",
      "evidence": "emerging"
    },
    {
      "icon": "stress",
      "line": "Stress and a worried mind use up the attention you'd otherwise point at the task.",
      "why": "Worry occupies working memory; arousal narrows attention.",
      "evidence": "moderate"
    },
    {
      "icon": "water",
      "line": "Being low on fluids can make concentration harder.",
      "why": "Small fluid deficits are linked to poorer attention in some studies.",
      "evidence": "moderate"
    },
    {
      "icon": "time",
      "line": "Breaks and fewer interruptions help attention last.",
      "why": "Attention depletes over time; breaks restore it.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "attention",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "uses attention",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "concentration",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "concentration",
      "evidence": "emerging"
    },
    {
      "to": "stress",
      "direction": "out",
      "label": "struggling",
      "evidence": "emerging"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "distraction",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Take a 10-minute walk before a task that needs thinking.",
      "habit_hint": "walk"
    },
    {
      "text": "Have your coffee in the morning, not after 2pm.",
      "habit_hint": "caffeine_cutoff"
    },
    {
      "text": "Silence notifications for one 25-minute block.",
      "habit_hint": "focus_block"
    },
    {
      "text": "Eat a protein-rich lunch and add vegetables.",
      "habit_hint": "protein"
    },
    {
      "text": "Drink a glass of water before you start.",
      "habit_hint": "hydration"
    },
    {
      "text": "Do five slow breaths before a hard task.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "If this stays low for weeks, talk to your practitioner.",
  "sources": [
    "Lim & Dinges 2010 · Psychol Bull",
    "Drake 2013 · J Clin Sleep Med",
    "Goyal 2014 · JAMA Intern Med",
    "Irwin 2020 · Neurosci Biobehav Rev",
    "Chang 2012 · Brain Res",
    "Benton & Young 2015 · Nutr Rev"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('focus', 'fr', 1, $json$
{
  "title": "À propos de la concentration",
  "what_it_is": "Votre capacité à maintenir votre attention sur une seule chose et à penser clairement.",
  "feels_high": "Vous restez sur une tâche et les idées s’enchaînent.",
  "feels_low": "Tête embrumée, facilement distrait(e), vous relisez la même ligne.",
  "card_text": "La concentration dépend surtout du sommeil, puis du mouvement, du moment où vous prenez de la caféine, de la régularité des repas, des liquides et de votre niveau de stress ou de distraction. Une courte marche affine souvent la pensée pendant environ une heure.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Le sommeil est le plus grand levier : les nuits courtes réduisent de façon fiable l’attention et la mémoire de travail.",
      "why": "Le manque de sommeil perturbe les réseaux cérébraux qui soutiennent l’attention.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Un court moment de mouvement peut affiner la pensée pendant environ l’heure qui suit.",
      "why": "Un effort ponctuel apporte une petite amélioration des performances cognitives, surtout juste après.",
      "evidence": "moderate"
    },
    {
      "icon": "caffeine",
      "line": "La caféine aide la vigilance, surtout quand vous êtes fatigué(e), mais une dose tardive coûte du sommeil, qui coûte de la concentration.",
      "why": "La caféine restaure une partie des performances après un manque de sommeil.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "Des repas réguliers aident : un gros déjeuner riche en glucides raffinés peut provoquer un coup de barre après le repas chez certaines personnes.",
      "why": "Variations de la glycémie et somnolence après le repas.",
      "evidence": "emerging"
    },
    {
      "icon": "stress",
      "line": "Le stress et un esprit préoccupé consomment l’attention que vous porteriez sinon sur la tâche.",
      "why": "L’inquiétude occupe la mémoire de travail ; l’activation excessive rétrécit l’attention.",
      "evidence": "moderate"
    },
    {
      "icon": "water",
      "line": "Manquer de liquides peut rendre la concentration plus difficile.",
      "why": "De petits déficits en liquides sont associés, dans certaines études, à une moins bonne attention.",
      "evidence": "moderate"
    },
    {
      "icon": "time",
      "line": "Les pauses et moins d’interruptions aident l’attention à durer.",
      "why": "L’attention s’épuise avec le temps ; les pauses la restaurent.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "attention",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "mobilise l’attention",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "concentration",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "concentration",
      "evidence": "emerging"
    },
    {
      "to": "stress",
      "direction": "out",
      "label": "difficulté",
      "evidence": "emerging"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "distraction",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Faites une marche de 10 minutes avant une tâche qui demande de réfléchir.",
      "habit_hint": "walk"
    },
    {
      "text": "Buvez votre café le matin, pas après 14 h.",
      "habit_hint": "caffeine_cutoff"
    },
    {
      "text": "Coupez les notifications pendant un bloc de 25 minutes.",
      "habit_hint": "focus_block"
    },
    {
      "text": "Prenez un déjeuner riche en protéines et ajoutez des légumes.",
      "habit_hint": "protein"
    },
    {
      "text": "Buvez un verre d’eau avant de commencer.",
      "habit_hint": "hydration"
    },
    {
      "text": "Faites cinq respirations lentes avant une tâche difficile.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "Si cela reste bas pendant des semaines, parlez-en à votre praticienne.",
  "sources": [
    "Lim & Dinges 2010 · Psychol Bull",
    "Drake 2013 · J Clin Sleep Med",
    "Goyal 2014 · JAMA Intern Med",
    "Irwin 2020 · Neurosci Biobehav Rev",
    "Chang 2012 · Brain Res",
    "Benton & Young 2015 · Nutr Rev"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('mood', 'en', 1, $json$
{
  "title": "About mood",
  "what_it_is": "Your emotional tone and resilience through the day: how steady and flexible you feel.",
  "feels_high": "You recover quickly from irritations and feel open.",
  "feels_low": "Flat, tense or tearful, small things feel big.",
  "card_text": "Mood is influenced by sleep, movement, how you eat, stress, and connection with others. Regular movement and whole foods are linked to a steadier mood over time, and poor sleep makes it more fragile.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Sleep is one of the strongest levers: after short sleep, positive mood drops and anxiety rises.",
      "why": "Sleep loss amplifies emotional reactivity.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Moving your body regularly lifts mood, and for many people the effect is meaningful.",
      "why": "Exercise helps depressive symptoms in trials; walking, jogging, yoga and strength training all showed benefit.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "Eating more whole foods (vegetables, fruit, fish, legumes) is linked to better mood over time.",
      "why": "Dietary improvement trials show modest benefits for depressive symptoms; mechanisms are likely several, including gut, inflammation and blood sugar.",
      "evidence": "moderate"
    },
    {
      "icon": "food",
      "line": "A diet high in refined carbs and sugars is linked to higher risk of low mood.",
      "why": "Large observational data; cause unclear.",
      "evidence": "emerging"
    },
    {
      "icon": "stress",
      "line": "Chronic stress wears down mood; short, regular resets help.",
      "why": "Stress and mood move together quickly, especially when recovery is low.",
      "evidence": "moderate"
    },
    {
      "icon": "social",
      "line": "Time with people you like and meaningful contact support mood.",
      "why": "Social connection is protective; evidence here is mostly observational.",
      "evidence": "moderate"
    },
    {
      "icon": "light",
      "line": "Daylight and time outside lift many people.",
      "why": "Light and activity support the body clock and mood.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "positive mood",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "wears mood down",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "effort",
      "evidence": "moderate"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "rumination",
      "evidence": "emerging"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "harder day",
      "evidence": "emerging"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "concentration",
      "evidence": "emerging"
    },
    {
      "to": "energy",
      "direction": "out",
      "label": "flat days",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Walk outside for 10 minutes, ideally in daylight.",
      "habit_hint": "walk"
    },
    {
      "text": "Message or call one person you like today.",
      "habit_hint": "social"
    },
    {
      "text": "Add one portion of vegetables or fruit to a meal.",
      "habit_hint": "fibre"
    },
    {
      "text": "Don't skip meals; build each one around protein.",
      "habit_hint": "protein"
    },
    {
      "text": "Write three good things from today.",
      "habit_hint": "gratitude"
    },
    {
      "text": "Protect a regular bedtime.",
      "habit_hint": "bedtime"
    }
  ],
  "safety_line": "If this stays low for weeks, talk to your practitioner.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Noetel 2024 · BMJ",
    "Holt-Lunstad 2015 · Perspect Psychol Sci",
    "Goyal 2014 · JAMA Intern Med",
    "Firth 2019 · Psychosom Med",
    "Fincham 2023 · Sci Rep",
    "Gangwisch 2015 · Am J Clin Nutr",
    "Khalsa 2003 · J Physiol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('mood', 'fr', 1, $json$
{
  "title": "À propos de l’humeur",
  "what_it_is": "Votre tonalité émotionnelle et votre résilience au fil de la journée : à quel point vous vous sentez stable et souple.",
  "feels_high": "Vous vous remettez vite des contrariétés et vous vous sentez ouvert(e).",
  "feels_low": "Humeur plate, tendue ou larmoyante, les petites choses paraissent grandes.",
  "card_text": "L’humeur dépend du sommeil, du mouvement, de votre alimentation, du stress et du lien avec les autres. Un mouvement régulier et des aliments complets sont associés à une humeur plus stable à long terme, et un mauvais sommeil la fragilise.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Le sommeil est l’un des leviers les plus puissants : après une courte nuit, l’humeur positive baisse et l’anxiété monte.",
      "why": "Le manque de sommeil amplifie la réactivité émotionnelle.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Bouger régulièrement améliore l’humeur et, pour beaucoup de personnes, l’effet est significatif.",
      "why": "L’exercice soulage les symptômes dépressifs dans les études ; la marche, le jogging, le yoga et la musculation ont tous montré un bénéfice.",
      "evidence": "strong"
    },
    {
      "icon": "food",
      "line": "Manger plus d’aliments complets (légumes, fruits, poisson, légumineuses) est associé à une meilleure humeur à long terme.",
      "why": "Les études d’amélioration de l’alimentation montrent des bénéfices modestes sur les symptômes dépressifs ; les mécanismes sont probablement multiples, notamment l’intestin, l’inflammation et la glycémie.",
      "evidence": "moderate"
    },
    {
      "icon": "food",
      "line": "Une alimentation riche en glucides raffinés et en sucres est associée à un risque plus élevé de baisse d’humeur.",
      "why": "Données observationnelles de grande ampleur ; la cause reste incertaine.",
      "evidence": "emerging"
    },
    {
      "icon": "stress",
      "line": "Le stress chronique use l’humeur ; de courtes pauses régulières aident.",
      "why": "Le stress et l’humeur évoluent ensemble rapidement, surtout quand la récupération est faible.",
      "evidence": "moderate"
    },
    {
      "icon": "social",
      "line": "Passer du temps avec des personnes que vous appréciez et avoir des contacts qui comptent soutiennent l’humeur.",
      "why": "Le lien social est protecteur ; les données sont surtout observationnelles.",
      "evidence": "moderate"
    },
    {
      "icon": "light",
      "line": "La lumière du jour et le temps passé dehors font du bien à beaucoup de personnes.",
      "why": "La lumière et l’activité soutiennent l’horloge interne et l’humeur.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "humeur positive",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "use l’humeur",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "effort",
      "evidence": "moderate"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "ruminations",
      "evidence": "emerging"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "journée plus dure",
      "evidence": "emerging"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "concentration",
      "evidence": "emerging"
    },
    {
      "to": "energy",
      "direction": "out",
      "label": "journées sans élan",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Marchez dehors pendant 10 minutes, de préférence à la lumière du jour.",
      "habit_hint": "walk"
    },
    {
      "text": "Écrivez ou appelez aujourd’hui une personne que vous appréciez.",
      "habit_hint": "social"
    },
    {
      "text": "Ajoutez une portion de légumes ou de fruits à un repas.",
      "habit_hint": "fibre"
    },
    {
      "text": "Ne sautez pas de repas ; construisez chacun autour des protéines.",
      "habit_hint": "protein"
    },
    {
      "text": "Notez trois belles choses de votre journée.",
      "habit_hint": "gratitude"
    },
    {
      "text": "Protégez une heure de coucher régulière.",
      "habit_hint": "bedtime"
    }
  ],
  "safety_line": "Si cela reste bas pendant des semaines, parlez-en à votre praticienne.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Noetel 2024 · BMJ",
    "Holt-Lunstad 2015 · Perspect Psychol Sci",
    "Goyal 2014 · JAMA Intern Med",
    "Firth 2019 · Psychosom Med",
    "Fincham 2023 · Sci Rep",
    "Gangwisch 2015 · Am J Clin Nutr",
    "Khalsa 2003 · J Physiol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('stress', 'en', 1, $json$
{
  "title": "About stress",
  "what_it_is": "How much load and pressure you feel, and how well you recover from it. (The app shows calmness: higher = calmer.)",
  "feels_high": "You can pause, breathe, switch off in the evening.",
  "feels_low": "Tense, rushed, racing thoughts, a body that doesn't switch off.",
  "feels_high_label": "Calm",
  "feels_low_label": "High stress",
  "card_text": "Stress is influenced by workload and gaps, sleep, movement, breathing, and the people around you. Short breathing or walking breaks help, and good sleep makes the same day feel lighter.",
  "influences": [
    {
      "icon": "breath",
      "line": "Short slow-breathing breaks calm the body quickly and can lower stress over weeks.",
      "why": "Slow breathing shifts the nervous system toward its calming mode.",
      "evidence": "moderate"
    },
    {
      "icon": "mind",
      "line": "Mindfulness or meditation practice reduces perceived stress for many people.",
      "why": "Training attention changes how the mind responds to pressure.",
      "evidence": "moderate"
    },
    {
      "icon": "move",
      "line": "Regular movement tends to lower stress and anxiety.",
      "why": "Exercise improves stress regulation and sleep.",
      "evidence": "moderate"
    },
    {
      "icon": "sleep",
      "line": "Poor sleep makes the same workload feel heavier.",
      "why": "Sleep loss increases emotional reactivity.",
      "evidence": "strong"
    },
    {
      "icon": "time",
      "line": "Calendar load: back-to-back commitments with no gaps keep you in a higher-alert state.",
      "why": "Without recovery windows arousal stays high.",
      "evidence": "emerging"
    },
    {
      "icon": "social",
      "line": "Support from people you trust protects you.",
      "why": "Social connection buffers stress; evidence mostly observational.",
      "evidence": "moderate"
    },
    {
      "icon": "alcohol",
      "line": "Alcohol and lots of caffeine can feel like relief but often worsen sleep and next-day tension.",
      "why": "Both disrupt sleep, which feeds stress.",
      "evidence": "moderate"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "feels heavier",
      "evidence": "moderate"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "lighter sleep",
      "evidence": "moderate"
    },
    {
      "to": "digestion",
      "direction": "out",
      "label": "flares",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "wears mood down",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "out",
      "label": "burns energy",
      "evidence": "emerging"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "uses attention",
      "evidence": "moderate"
    },
    {
      "to": "focus",
      "direction": "in",
      "label": "struggling",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Do five slow breaths: in for 4, out for 6.",
      "habit_hint": "breathwork"
    },
    {
      "text": "Take a 5-minute walk between meetings.",
      "habit_hint": "walk"
    },
    {
      "text": "Leave a 10-minute gap between calls.",
      "habit_hint": "calendar_gap"
    },
    {
      "text": "Set a phone-off time in the evening.",
      "habit_hint": "wind_down"
    },
    {
      "text": "Write down tomorrow's top three things before you finish.",
      "habit_hint": "plan_tomorrow"
    },
    {
      "text": "Call someone who calms you.",
      "habit_hint": "social"
    }
  ],
  "safety_line": "If this stays low for weeks, talk to your practitioner.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Drake 2013 · J Clin Sleep Med",
    "Kredlow 2015 · J Behav Med",
    "Noetel 2024 · BMJ",
    "Holt-Lunstad 2015 · Perspect Psychol Sci",
    "Goyal 2014 · JAMA Intern Med",
    "Fincham 2023 · Sci Rep",
    "Ebrahim 2013 · Alcohol Clin Exp Res",
    "Qin 2014 · World J Gastroenterol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('stress', 'fr', 1, $json$
{
  "title": "À propos du stress",
  "what_it_is": "La charge et la pression que vous ressentez, et votre capacité à en récupérer. (L’application affiche le calme : plus c’est haut, plus vous êtes calme.)",
  "feels_high": "Vous pouvez faire une pause, respirer, décrocher le soir.",
  "feels_low": "Tendu(e), pressé(e), pensées qui s’emballent, un corps qui ne décroche pas.",
  "feels_high_label": "Calme",
  "feels_low_label": "Stress élevé",
  "card_text": "Le stress dépend de la charge de travail et des pauses, du sommeil, du mouvement, de la respiration et des personnes qui vous entourent. De courtes pauses de respiration ou de marche aident, et un bon sommeil rend la même journée plus légère.",
  "influences": [
    {
      "icon": "breath",
      "line": "De courtes pauses de respiration lente calment rapidement le corps et peuvent réduire le stress au fil des semaines.",
      "why": "La respiration lente fait basculer le système nerveux vers son mode apaisant.",
      "evidence": "moderate"
    },
    {
      "icon": "mind",
      "line": "La pleine conscience ou la méditation réduit le stress perçu chez beaucoup de personnes.",
      "why": "Entraîner l’attention change la façon dont l’esprit réagit à la pression.",
      "evidence": "moderate"
    },
    {
      "icon": "move",
      "line": "Un mouvement régulier tend à diminuer le stress et l’anxiété.",
      "why": "L’exercice améliore la régulation du stress et le sommeil.",
      "evidence": "moderate"
    },
    {
      "icon": "sleep",
      "line": "Un mauvais sommeil rend la même charge de travail plus lourde.",
      "why": "Le manque de sommeil augmente la réactivité émotionnelle.",
      "evidence": "strong"
    },
    {
      "icon": "time",
      "line": "La charge d’agenda : des rendez-vous enchaînés sans pause vous maintiennent dans un état d’alerte plus élevé.",
      "why": "Sans fenêtres de récupération, l’activation reste élevée.",
      "evidence": "emerging"
    },
    {
      "icon": "social",
      "line": "Le soutien de personnes de confiance vous protège.",
      "why": "Le lien social amortit le stress ; les données sont surtout observationnelles.",
      "evidence": "moderate"
    },
    {
      "icon": "alcohol",
      "line": "L’alcool et beaucoup de caféine peuvent donner l’impression de soulager, mais aggravent souvent le sommeil et la tension du lendemain.",
      "why": "Tous deux perturbent le sommeil, ce qui nourrit le stress.",
      "evidence": "moderate"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "charge ressentie",
      "evidence": "moderate"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "sommeil plus léger",
      "evidence": "moderate"
    },
    {
      "to": "digestion",
      "direction": "out",
      "label": "poussées",
      "evidence": "moderate"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "use l’humeur",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "out",
      "label": "épuise l’énergie",
      "evidence": "emerging"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "mobilise l’attention",
      "evidence": "moderate"
    },
    {
      "to": "focus",
      "direction": "in",
      "label": "difficulté",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Faites cinq respirations lentes : inspirez sur 4 temps, expirez sur 6.",
      "habit_hint": "breathwork"
    },
    {
      "text": "Faites une marche de 5 minutes entre deux réunions.",
      "habit_hint": "walk"
    },
    {
      "text": "Laissez 10 minutes d’écart entre deux appels.",
      "habit_hint": "calendar_gap"
    },
    {
      "text": "Fixez une heure à laquelle éteindre le téléphone le soir.",
      "habit_hint": "wind_down"
    },
    {
      "text": "Notez les trois priorités de demain avant de terminer.",
      "habit_hint": "plan_tomorrow"
    },
    {
      "text": "Appelez quelqu’un qui vous apaise.",
      "habit_hint": "social"
    }
  ],
  "safety_line": "Si cela reste bas pendant des semaines, parlez-en à votre praticienne.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Drake 2013 · J Clin Sleep Med",
    "Kredlow 2015 · J Behav Med",
    "Noetel 2024 · BMJ",
    "Holt-Lunstad 2015 · Perspect Psychol Sci",
    "Goyal 2014 · JAMA Intern Med",
    "Fincham 2023 · Sci Rep",
    "Ebrahim 2013 · Alcohol Clin Exp Res",
    "Qin 2014 · World J Gastroenterol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('digestion', 'en', 1, $json$
{
  "title": "About digestion",
  "what_it_is": "How comfortable and regular your gut feels: comfort, stool regularity, and how meals sit afterwards.",
  "feels_high": "Comfortable after meals, regular, you forget about it.",
  "feels_low": "Bloating, cramps, urgency or constipation, heaviness after eating.",
  "feels_high_label": "Good",
  "feels_low_label": "Poor",
  "card_text": "Digestion is influenced by fibre, water, how fast and calmly you eat, movement after meals, your own food triggers, and stress. A stressed or poorly slept gut is often more reactive.",
  "influences": [
    {
      "icon": "food",
      "line": "Fibre from plants (vegetables, fruit, legumes, whole grains) keeps things moving for most people.",
      "why": "Fibre adds bulk and feeds gut bacteria; high fibre intake is linked to better health outcomes.",
      "evidence": "strong"
    },
    {
      "icon": "stress",
      "line": "Stress shows up in the gut quickly: tightness, cramps, flares.",
      "why": "The brain and gut are linked by nerves and hormones; stress changes gut movement and sensitivity.",
      "evidence": "moderate"
    },
    {
      "icon": "water",
      "line": "Drinking enough water helps stool stay soft, especially if you eat more fibre.",
      "why": "Fibre works with water.",
      "evidence": "emerging"
    },
    {
      "icon": "move",
      "line": "Gentle movement, especially a walk after meals, tends to help digestion.",
      "why": "Light activity supports gut movement and also steadies blood sugar after meals.",
      "evidence": "moderate"
    },
    {
      "icon": "food",
      "line": "Food triggers vary: some people react to specific foods, large or very fatty meals.",
      "why": "Individual tolerance (FODMAPs, fat load, portions).",
      "evidence": "emerging"
    },
    {
      "icon": "time",
      "line": "Eating slowly and calmly helps; rushed meals sit worse.",
      "why": "Chewing and parasympathetic state support digestion.",
      "evidence": "emerging"
    },
    {
      "icon": "sleep",
      "line": "A poor night often makes the gut more reactive next day.",
      "why": "Sleep affects pain sensitivity and gut signalling.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "gut reactivity",
      "evidence": "emerging"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "flares",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "out",
      "label": "harder day",
      "evidence": "emerging"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "harder day",
      "evidence": "emerging"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "late meals",
      "evidence": "emerging"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "distraction",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Add one plant food with fibre to every meal.",
      "habit_hint": "fibre"
    },
    {
      "text": "Walk for 10 minutes after your biggest meal.",
      "habit_hint": "walk_after_meal"
    },
    {
      "text": "Have a glass of water with each meal.",
      "habit_hint": "hydration"
    },
    {
      "text": "Eat your first five bites slowly, seated.",
      "habit_hint": "slow_eating"
    },
    {
      "text": "Note a food that sat badly; check again in a week.",
      "habit_hint": "food_notes"
    },
    {
      "text": "Take two minutes to breathe before eating.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "If this stays low for weeks, talk to your practitioner.",
  "sources": [
    "Reynolds 2019 · Lancet",
    "Engeroff 2023 · Sports Med",
    "Mou 2026 · Am J Clin Nutr",
    "Qin 2014 · World J Gastroenterol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('digestion', 'fr', 1, $json$
{
  "title": "À propos de la digestion",
  "what_it_is": "À quel point votre intestin est confortable et régulier : confort, régularité des selles et manière dont les repas passent ensuite.",
  "feels_high": "Confortable après les repas, régulier, vous l’oubliez.",
  "feels_low": "Ballonnements, crampes, urgence ou constipation, lourdeur après les repas.",
  "feels_high_label": "Bonne",
  "feels_low_label": "Mauvaise",
  "card_text": "La digestion dépend des fibres, de l’eau, de la vitesse et du calme avec lesquels vous mangez, du mouvement après les repas, de vos propres déclencheurs alimentaires et du stress. Un intestin stressé ou mal reposé est souvent plus réactif.",
  "influences": [
    {
      "icon": "food",
      "line": "Les fibres végétales (légumes, fruits, légumineuses, céréales complètes) favorisent le transit chez la plupart des gens.",
      "why": "Les fibres augmentent le volume des selles et nourrissent les bactéries intestinales ; une consommation élevée de fibres est associée à une meilleure santé.",
      "evidence": "strong"
    },
    {
      "icon": "stress",
      "line": "Le stress se manifeste vite dans l’intestin : tension, crampes, poussées.",
      "why": "Le cerveau et l’intestin sont reliés par des nerfs et des hormones ; le stress modifie les mouvements et la sensibilité de l’intestin.",
      "evidence": "moderate"
    },
    {
      "icon": "water",
      "line": "Boire suffisamment d’eau aide à garder des selles molles, surtout si vous mangez plus de fibres.",
      "why": "Les fibres agissent avec l’eau.",
      "evidence": "emerging"
    },
    {
      "icon": "move",
      "line": "Un mouvement doux, surtout une marche après les repas, tend à aider la digestion.",
      "why": "Une activité légère favorise les mouvements de l’intestin et stabilise aussi la glycémie après les repas.",
      "evidence": "moderate"
    },
    {
      "icon": "food",
      "line": "Les déclencheurs alimentaires varient : certaines personnes réagissent à des aliments précis, à de gros repas ou à des repas très gras.",
      "why": "Tolérance individuelle (FODMAP, quantité de graisses, portions).",
      "evidence": "emerging"
    },
    {
      "icon": "time",
      "line": "Manger lentement et calmement aide ; les repas pris à la hâte passent moins bien.",
      "why": "La mastication et un état parasympathique favorisent la digestion.",
      "evidence": "emerging"
    },
    {
      "icon": "sleep",
      "line": "Une mauvaise nuit rend souvent l’intestin plus réactif le lendemain.",
      "why": "Le sommeil influence la sensibilité à la douleur et les signaux de l’intestin.",
      "evidence": "emerging"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "réactivité intestinale",
      "evidence": "emerging"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "poussées",
      "evidence": "moderate"
    },
    {
      "to": "energy",
      "direction": "out",
      "label": "journée plus dure",
      "evidence": "emerging"
    },
    {
      "to": "mood",
      "direction": "out",
      "label": "journée plus dure",
      "evidence": "emerging"
    },
    {
      "to": "sleep",
      "direction": "out",
      "label": "repas tardifs",
      "evidence": "emerging"
    },
    {
      "to": "focus",
      "direction": "out",
      "label": "distraction",
      "evidence": "emerging"
    }
  ],
  "actions": [
    {
      "text": "Ajoutez à chaque repas un aliment végétal riche en fibres.",
      "habit_hint": "fibre"
    },
    {
      "text": "Marchez 10 minutes après votre repas le plus copieux.",
      "habit_hint": "walk_after_meal"
    },
    {
      "text": "Buvez un verre d’eau à chaque repas.",
      "habit_hint": "hydration"
    },
    {
      "text": "Mangez vos cinq premières bouchées lentement, assis(e).",
      "habit_hint": "slow_eating"
    },
    {
      "text": "Notez un aliment qui est mal passé ; vérifiez à nouveau dans une semaine.",
      "habit_hint": "food_notes"
    },
    {
      "text": "Prenez deux minutes pour respirer avant de manger.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "Si cela reste bas pendant des semaines, parlez-en à votre praticienne.",
  "sources": [
    "Reynolds 2019 · Lancet",
    "Engeroff 2023 · Sports Med",
    "Mou 2026 · Am J Clin Nutr",
    "Qin 2014 · World J Gastroenterol"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('score', 'en', 1, $json$
{
  "title": "About your functional score",
  "what_it_is": "A single summary: the equal-weight average of Sleep, Energy, Focus, Mood, Stress (calmness) and Digestion. It is a map of the whole picture, not a verdict.",
  "feels_high": "Most things are working together.",
  "feels_low": "Usually one or two signals are dragging the rest.",
  "card_text": "Your Functional score averages six signals. Sleep, movement, food, stress and connection all feed it. Look for the lowest signal first: lifting that one usually lifts the rest.",
  "influences_intro": "It is influenced by everything that moves the six signals, so it is best read as \"which signal is the weak link today?\"",
  "connections_intro": "Each of the six feeds it equally. Because it is an average, one very low signal can pull it down, and improving the lowest signal usually moves it most.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Sleep is usually the keystone: it feeds energy, focus, mood and stress.",
      "why": "A short or broken night lowers alertness and makes emotions harder to regulate the next day, so several signals dip together.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Movement helps several signals at once: sleep, mood, energy, stress.",
      "why": "Regular activity has wide effects.",
      "evidence": "moderate"
    },
    {
      "icon": "food",
      "line": "Eating whole foods with protein and fibre helps energy, mood and digestion together.",
      "why": "Protein and fibre slow digestion and keep blood sugar steadier; whole-food patterns are linked to better mood and gut comfort.",
      "evidence": "moderate"
    },
    {
      "icon": "stress",
      "line": "Stress management lifts sleep, mood and digestion.",
      "why": "Stress is a multiplier on the other signals.",
      "evidence": "moderate"
    },
    {
      "icon": "social",
      "line": "Connection with people supports mood and stress.",
      "why": "Observational.",
      "evidence": "moderate"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "focus",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    }
  ],
  "actions": [
    {
      "text": "Find your lowest signal this week; start there.",
      "habit_hint": "lowest_signal"
    },
    {
      "text": "Protect your bedtime on three nights.",
      "habit_hint": "bedtime"
    },
    {
      "text": "Walk 10 minutes after one meal a day.",
      "habit_hint": "walk_after_meal"
    },
    {
      "text": "Add one fibre-rich plant food per meal.",
      "habit_hint": "fibre"
    },
    {
      "text": "Take one slow-breathing break daily.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "If this stays low for weeks, talk to your practitioner.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Lim & Dinges 2010 · Psychol Bull",
    "Kredlow 2015 · J Behav Med",
    "Noetel 2024 · BMJ",
    "Reynolds 2019 · Lancet",
    "Holt-Lunstad 2015 · Perspect Psychol Sci",
    "Leidy 2015 · Am J Clin Nutr",
    "Goyal 2014 · JAMA Intern Med",
    "Firth 2019 · Psychosom Med",
    "Fincham 2023 · Sci Rep",
    "Qin 2014 · World J Gastroenterol",
    "Puetz 2008 · Psychother Psychosom"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now()),
  ('score', 'fr', 1, $json$
{
  "title": "À propos de votre score fonctionnel",
  "what_it_is": "Un résumé unique : la moyenne, à poids égal, du sommeil, de l’énergie, de la concentration, de l’humeur, du stress (calme) et de la digestion. C’est une carte de l’ensemble, pas un verdict.",
  "feels_high": "La plupart des éléments fonctionnent bien ensemble.",
  "feels_low": "En général, un ou deux signaux tirent les autres vers le bas.",
  "card_text": "Votre score fonctionnel est la moyenne de six signaux. Le sommeil, le mouvement, l’alimentation, le stress et le lien avec les autres l’alimentent tous. Cherchez d’abord le signal le plus bas : le faire remonter fait généralement remonter le reste.",
  "influences_intro": "Il est influencé par tout ce qui fait bouger les six signaux ; le plus utile est de le lire comme « quel signal est aujourd’hui le maillon faible ? ».",
  "connections_intro": "Chacun des six l’alimente à parts égales. Comme c’est une moyenne, un signal très bas peut la tirer vers le bas, et améliorer le signal le plus bas la fait généralement le plus progresser.",
  "influences": [
    {
      "icon": "sleep",
      "line": "Le sommeil est généralement la clé de voûte : il nourrit l’énergie, la concentration, l’humeur et le stress.",
      "why": "Une nuit courte ou hachée réduit la vigilance et rend les émotions plus difficiles à réguler le lendemain : plusieurs signaux baissent ensemble.",
      "evidence": "strong"
    },
    {
      "icon": "move",
      "line": "Le mouvement aide plusieurs signaux à la fois : sommeil, humeur, énergie, stress.",
      "why": "L’activité régulière a des effets étendus.",
      "evidence": "moderate"
    },
    {
      "icon": "food",
      "line": "Manger des aliments complets avec des protéines et des fibres aide l’énergie, l’humeur et la digestion à la fois.",
      "why": "Les protéines et les fibres ralentissent la digestion et stabilisent la glycémie ; une alimentation à base d’aliments complets est associée à une meilleure humeur et à un meilleur confort digestif.",
      "evidence": "moderate"
    },
    {
      "icon": "stress",
      "line": "Gérer son stress améliore le sommeil, l’humeur et la digestion.",
      "why": "Le stress est un multiplicateur des autres signaux.",
      "evidence": "moderate"
    },
    {
      "icon": "social",
      "line": "Le lien avec les autres soutient l’humeur et le stress.",
      "why": "Données observationnelles.",
      "evidence": "moderate"
    }
  ],
  "connections": [
    {
      "to": "sleep",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "energy",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "focus",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "mood",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "stress",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    },
    {
      "to": "digestion",
      "direction": "in",
      "label": "1/6",
      "evidence": "strong"
    }
  ],
  "actions": [
    {
      "text": "Repérez votre signal le plus bas cette semaine ; commencez par celui-là.",
      "habit_hint": "lowest_signal"
    },
    {
      "text": "Protégez votre heure de coucher pendant trois nuits.",
      "habit_hint": "bedtime"
    },
    {
      "text": "Marchez 10 minutes après un repas par jour.",
      "habit_hint": "walk_after_meal"
    },
    {
      "text": "Ajoutez un aliment végétal riche en fibres à chaque repas.",
      "habit_hint": "fibre"
    },
    {
      "text": "Faites chaque jour une pause de respiration lente.",
      "habit_hint": "breathwork"
    }
  ],
  "safety_line": "Si cela reste bas pendant des semaines, parlez-en à votre praticienne.",
  "sources": [
    "Palmer 2024 · Psychol Bull",
    "Lim & Dinges 2010 · Psychol Bull",
    "Kredlow 2015 · J Behav Med",
    "Noetel 2024 · BMJ",
    "Reynolds 2019 · Lancet",
    "Holt-Lunstad 2015 · Perspect Psychol Sci",
    "Leidy 2015 · Am J Clin Nutr",
    "Goyal 2014 · JAMA Intern Med",
    "Firth 2019 · Psychosom Med",
    "Fincham 2023 · Sci Rep",
    "Qin 2014 · World J Gastroenterol",
    "Puetz 2008 · Psychother Psychosom"
  ]
}
$json$::jsonb, 'approved', 'Thomas (owner) 2026-11-11', now())
on conflict (signal, locale, version) do update set
  content       = excluded.content,
  review_status = excluded.review_status,
  approved_by   = excluded.approved_by,
  approved_at   = excluded.approved_at,
  updated_at    = now();
