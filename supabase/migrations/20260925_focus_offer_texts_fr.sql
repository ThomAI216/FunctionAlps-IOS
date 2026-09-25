-- Today's focus in French — the practice's offer texts, translated, next to the English.
--
-- The house convention for bilingual content (`nb_food_items.name_fr`, `protocols.description_fr`,
-- `product_cards.description_fr`): the English column stays the source, a nullable `*_fr` column sits beside it.
-- NULL means "not translated yet" and the member reads the English — never a blank.
--
--   · habit_bank       title_fr, description_fr, easy_title_fr, easy_description_fr, rev_title_fr, rev_description_fr
--   · state_responses  title_fr (the heading, "Un démarrage en douceur"); each offer inside `offers` gains
--                      `title_fr` / `description_fr` keys beside its `title` / `description`
--   · habit_offers     title_fr, description_fr — the day is stored in both languages, so a phone that changes
--                      language mid-day reads the same offers, not a recomputed day
--
-- Additive: nullable columns and content only. Table-level grants cover new columns; RLS is unchanged.
-- Every reader that selects named columns (the Expo app, CM OS) is unaffected; extra keys inside `offers`
-- are ignored by anything that does not know them.
--
-- The French follows the app's own: « vous », déjeuner / dîner for lunch / dinner (as the meal types say),
-- 14 h rather than 14:00, typographic apostrophes. Drafted from the English on 2026-09-25 for the owner to
-- proofread — every line is plain data, editable in place.

alter table public.habit_bank
  add column if not exists title_fr text,
  add column if not exists description_fr text,
  add column if not exists easy_title_fr text,
  add column if not exists easy_description_fr text,
  add column if not exists rev_title_fr text,
  add column if not exists rev_description_fr text;

alter table public.state_responses
  add column if not exists title_fr text;

alter table public.habit_offers
  add column if not exists title_fr text,
  add column if not exists description_fr text;

-- MARK: - The library (36 habits), keyed by the table's own UNIQUE (pillar, title)

update public.habit_bank h set
  title_fr = v.title_fr,
  description_fr = v.description_fr,
  easy_title_fr = v.easy_title_fr,
  easy_description_fr = v.easy_description_fr,
  rev_title_fr = v.rev_title_fr
from (values
  -- emotion
  ('emotion', 'Name the feeling, once',
   'Nommez l’émotion, une fois', 'Un moment par jour : comment s’appelle ce que vous ressentez ?', null, null, null),
  ('emotion', 'One message to someone you like',
   'Un message à quelqu’un que vous appréciez', 'Trente secondes pour entretenir le lien.', null, null, null),
  ('emotion', 'Three good things tonight',
   'Trois bonnes choses ce soir', 'Les petites comptent double.',
   'Une bonne chose', 'Une seule, c’est déjà une pratique.', null),
  ('emotion', 'Journaling, five minutes',
   'Cinq minutes de journal', 'Sans filtre, pour personne d’autre que vous.',
   'Trois lignes', 'Trois lignes sincères valent mieux qu’une page blanche.', null),
  ('emotion', 'A real lunch with someone',
   'Un vrai déjeuner avec quelqu’un', 'Une fois dans la semaine, le déjeuner se partage — sans écran.', null, null, null),
  ('emotion', 'Say no to one thing',
   'Dites non à une chose', 'Un petit non qui protège votre journée.', null, null, null),
  -- exercise
  ('exercise', 'A 10-minute walk after lunch',
   'Une marche de 10 minutes après le déjeuner', 'Aide la digestion et chasse le coup de barre de l’après-midi.',
   'Cinq minutes dehors', 'La moitié de la marche, tout le mérite.', 'Allongez-la à 20 minutes'),
  ('exercise', 'Morning stretch, five minutes',
   'Étirements du matin, cinq minutes', 'Réveillez le corps avant que la journée ne s’en empare.',
   'Deux étirements contre le plan de travail', 'Pendant que le café coule.', null),
  ('exercise', 'One set of push-ups',
   'Une série de pompes', 'Autant que vous le sentez — la technique avant la quantité.',
   null, null, 'Deux séries — une minute de pause entre les deux'),
  ('exercise', 'Stairs instead of lifts',
   'Les escaliers plutôt que l’ascenseur', 'Un entraînement gratuit, caché dans la journée.', null, null, null),
  ('exercise', 'Evening walk',
   'Marche du soir', 'Bouger après le dîner — le levier doux le plus puissant sur le sommeil.',
   'Cinq minutes autour du pâté de maisons', 'Court, c’est très bien — passer la porte, c’est déjà gagné.', 'Ajoutez dix minutes'),
  ('exercise', 'Ten sit-to-stands',
   'Dix assis-debout', 'Depuis une chaise, sans matériel — les jambes portent tout le reste.',
   'Cinq assis-debout', 'Une demi-série compte quand même.', 'Deux séries de dix'),
  -- mind
  ('mind', 'Three slow breaths before meals',
   'Trois respirations lentes avant les repas', 'Signale au corps « tout va bien » — les repas passent mieux.',
   null, null, 'Respiration carrée, 4×4, une fois par jour'),
  ('mind', 'Box breathing, 4×4',
   'Respiration carrée, 4×4', 'Inspirez sur quatre, retenez sur quatre, expirez sur quatre, retenez sur quatre — quatre cycles.', null, null, null),
  ('mind', 'One phone-free coffee',
   'Un café sans téléphone', 'Une boisson chaude par jour, rien d’autre entre les mains.', null, null, null),
  ('mind', 'Single-task the first work hour',
   'Une seule tâche pendant la première heure de travail', 'Une chose, bien faite, avant que le bruit commence.',
   'Une seule tâche pendant les 20 premières minutes', 'Un début court mais concentré compte aussi.', null),
  ('mind', 'Five minutes of daylight',
   'Cinq minutes de lumière du jour', 'La lumière règle l’horloge interne — le matin, c’est idéal.',
   'Ouvrez la fenêtre — deux minutes, ça compte', 'La lumière à travers une vitre vaut mieux que pas de lumière.', null),
  ('mind', 'A two-minute pause between tasks',
   'Une pause de deux minutes entre deux tâches', 'Levez-vous, regardez au loin, respirez une fois.', null, null, null),
  -- nutrition
  ('nutrition', 'A glass of water before coffee',
   'Un verre d’eau avant le café', 'Commencez par vous hydrater — le café passe plus en douceur.', null, null, null),
  ('nutrition', 'Protein at breakfast',
   'Des protéines au petit-déjeuner', 'Œufs, skyr, restes — peu importe. Une énergie plus stable jusqu’à 11 h.',
   'Tout ce que vous mangez au petit-déjeuner compte', 'La version des nuits courtes, qui vous fait quand même avancer.', null),
  ('nutrition', 'Vegetables on half the plate',
   'Des légumes sur la moitié de l’assiette', 'Une assiette par jour où les légumes ont le dessus.', null, null, null),
  ('nutrition', 'Slow first five bites',
   'Les cinq premières bouchées, lentement', 'Les cinq premières bouchées donnent le rythme de tout le repas.',
   'Trois bouchées lentes', 'Petit, ça compte aussi.', null),
  ('nutrition', 'Fruit within reach',
   'Un fruit à portée de main', 'Quand le coup de barre arrive, l’option facile est déjà dans votre main.', null, null, null),
  ('nutrition', 'Kitchen closed after 21:00',
   'Cuisine fermée après 21 h', 'Une heure de fermeture vaut mieux que la volonté.',
   'Une collation tardive, ça va — remarquez-la simplement', 'Ce soir, l’habitude, c’est de la remarquer.', null),
  -- recovery
  ('recovery', 'A real pause at lunch, no screens',
   'Une vraie pause à midi, sans écrans', 'Vingt minutes où l’on ne vous demande rien.',
   'Dix minutes, sans écrans', 'Une vraie pause, même courte, vaut mieux qu’une longue à moitié prise.', null),
  ('recovery', 'Five minutes outside in daylight',
   'Cinq minutes dehors, à la lumière du jour', 'La recharge la moins chère qui soit.', null, null, null),
  ('recovery', 'Legs up the wall, five minutes',
   'Jambes au mur, cinq minutes', 'Laissez l’organisme tourner au ralenti avant la soirée.', null, null, null),
  ('recovery', 'One work-free evening block',
   'Un créneau sans travail le soir', 'Une heure où le travail ne peut pas vous atteindre.', null, null, null),
  ('recovery', 'Shoulders down, jaw loose — three times',
   'Épaules basses, mâchoire relâchée — trois fois', 'Les deux endroits où la journée se cache.', null, null, null),
  ('recovery', 'A 20-minute nature walk',
   'Une balade de 20 minutes dans la nature', 'Du temps au vert le week-end — sans rythme, sans objectif.',
   null, null, 'Allez jusqu’à quarante minutes'),
  -- sleep
  ('sleep', 'Same bedtime on weekdays',
   'Même heure de coucher en semaine', 'Le corps aime un rythme plus qu’un chiffre.', null, null, null),
  ('sleep', 'No caffeine after 14:00',
   'Pas de caféine après 14 h', 'La tasse de l’après-midi empiète sur la nuit.', null, null, null),
  ('sleep', 'Screens off 30 minutes before bed',
   'Écrans éteints 30 minutes avant le coucher', 'Offrez à l’esprit une piste d’atterrissage.',
   'Le téléphone hors de la chambre', 'La distance fait le travail à votre place.', null),
  ('sleep', 'Dim the lights after 21:00',
   'Lumières tamisées après 21 h', 'L’obscurité est un signal, pas une absence.', null, null, null),
  ('sleep', 'Tomorrow''s list before bed',
   'La liste de demain avant le coucher', 'Déposez sur papier ce qui reste en suspens.',
   'Une ligne pour demain', 'Une pensée déposée apaise les autres.', null),
  ('sleep', 'Morning light within an hour of waking',
   'Lumière du matin dans l’heure qui suit le réveil', 'La nuit se prépare dès le matin.', null, null, null)
) as v(pillar, title, title_fr, description_fr, easy_title_fr, easy_description_fr, rev_title_fr)
where h.pillar = v.pillar and h.title = v.title;

-- MARK: - The practice's state responses (the five practice-wide defaults)

update public.state_responses s set title_fr = v.title_fr
from (values
  ('feeling_strong', 'Montez d’un cran'),
  ('low_energy', 'Mode batterie faible'),
  ('slept_poorly', 'Un démarrage en douceur'),
  ('slept_well', 'Profitez de la bonne nuit'),
  ('stressed', 'Deux minutes pour souffler')
) as v(state_key, title_fr)
where s.state_key = v.state_key and s.care_plan_id is null;

-- Each offer keeps every key it has; `title_fr` / `description_fr` are added beside `title` / `description`,
-- matched on (state, offer key). The array order — which the engine reads as the practice's preference — is kept.
with fr(state_key, offer_key, title_fr, description_fr) as (values
  ('feeling_strong', 'rev_walk_20', 'Prolongez la marche d’aujourd’hui à 20 minutes', 'La même marche, un peu plus loin — mettez ce bon jour à profit.'),
  ('feeling_strong', 'rev_extra_set', 'Une série de pompes en plus', 'La technique avant la quantité, comme toujours.'),
  ('low_energy', 'daylight_pause', 'Cinq minutes dehors, à la lumière du jour', 'Une courte pause qui recharge — aucun entraînement requis.'),
  ('low_energy', 'lift_move_flat_day', 'Cinq minutes de mouvement tranquille', 'Cela semble paradoxal un jour sans énergie, mais bouger un peu recharge en général davantage la batterie que se reposer.'),
  ('slept_poorly', 'fruit_within_reach', 'Gardez un fruit à portée de main', 'Quand le coup de barre de l’après-midi arrive, l’option facile est déjà dans votre main.'),
  ('slept_poorly', 'lift_walk_short_night', 'Une petite marche dehors', 'Dix minutes de lumière du jour changent souvent la donne après une nuit courte — seulement si vous en avez envie.'),
  ('slept_well', 'morning_walk', 'Une marche de 10 minutes le matin', 'Consolidez la bonne nuit par un mouvement léger.'),
  ('slept_well', 'pushup_set', 'Une série de pompes', 'Autant que vous le sentez — la technique avant la quantité.'),
  ('stressed', 'three_slow_breaths', 'Trois respirations lentes, trois fois aujourd’hui', 'Avant les repas, c’est idéal — cela aide aussi la digestion à se détendre.'),
  ('stressed', 'lift_walk_tension', 'Un tour du pâté de maisons', 'La tension s’en va plus vite quand vous bougez — cinq minutes suffisent pour le sentir.')
)
update public.state_responses s set offers = (
  select coalesce(jsonb_agg(
           e.o || coalesce((select jsonb_build_object('title_fr', fr.title_fr, 'description_fr', fr.description_fr)
                            from fr where fr.state_key = s.state_key and fr.offer_key = e.o->>'key'), '{}'::jsonb)
           order by e.ord), '[]'::jsonb)
  from jsonb_array_elements(s.offers) with ordinality as e(o, ord)
)
where s.care_plan_id is null and s.state_key in (select state_key from fr);
