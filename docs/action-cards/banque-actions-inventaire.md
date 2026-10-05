# Banque d'actions — inventaire et idées à créer

> **Pour qui :** la personne (ou l'agent) qui va écrire le contenu des cartes action et agrandir la banque.
> **Source :** une lecture seule de `habit_bank` sur CM OS (`ndojytvvlvlbgtodujkf`), le 2026-10-02, plus le code qui
> utilise la banque (CLINICAL et `FunctionAlps-IOS`). Ce fichier ne contient aucune donnée patient : la banque est un
> catalogue de contenu du cabinet.
> **Garde-fou :** la colonne « l'idée derrière » décrit l'**intention comportementale** de chaque action et le moment où
> un praticien peut s'en servir. Ce n'est pas une affirmation médicale. Toute justification santé (le `general_why`
> d'une carte) est rédigée par l'auteur, puis **validée par le clinicien** avant publication.

---

## 1. Vue d'ensemble

### 1.1 Ce qu'est une carte action

Une carte action **est** une ligne `habit_bank`. C'est la page que le membre ouvre dans l'app iOS quand il touche une
habitude reliée à la carte (`habits.habit_bank_id`), depuis « Actions du jour » ou son plan de soins, ou quand il lit une
carte dans « Actions de base » (la banque du membre) : une image, quoi faire, comment (les étapes), la version plus
douce et la version qui va plus loin, une vidéo ou une recherche YouTube, le pourquoi et un article de la bibliothèque.
Le focus du jour, lui, n'ouvre pas de carte (voir 1.4). Les cartes s'écrivent dans **CLINICAL → Action cards**
(`/action-cards`), avec un aperçu iPhone en direct.

Limites de longueur : celles de l'éditeur (`lib/action-cards/schemas.ts`). La base n'en impose pas, mais une carte
trop longue ne pourra plus être enregistrée depuis l'éditeur.

| Champ | Rôle | Contrainte |
|---|---|---|
| `pillar` | le pilier | `emotion` · `exercise` · `mind` · `nutrition` · `recovery` · `sleep` (contrainte en base) |
| `category` | la sous-famille (utilisée par le moteur du focus du jour, voir 1.4) | texte libre, mais **réutiliser les valeurs existantes** (liste en 4.5). **Absent de l'éditeur** : une carte créée dans l'éditeur a `category = null` |
| `title` / `title_fr` | le nom | `title` obligatoire, 120 caractères max (`title_fr` aussi). Le couple (`pillar`, `title`) est **unique** en base. Pas de fréquence dans le titre (voir 4.7) |
| `description` / `description_fr` | la phrase d'accroche, sous le titre | 400 caractères max. Il en faut une (EN ou FR) pour publier |
| `easy_title`, `easy_description` (+ `_fr`) | la **version douce** | titres 120, descriptions 400 caractères max. Le focus du jour la propose quand la forme du jour est basse |
| `rev_title`, `rev_description` (+ `_fr`) | la **version plus loin** | mêmes limites. Le focus du jour la propose quand la forme du jour est haute |
| `card_kind` | le type de carte : l'étiquette et l'icône dans l'app | `breath` · `movement` · `routine` · `nutrition` · `mind` · `learn` (contrainte en base). Toutes ouvrent **la même page** ; seul `breath` y ajoute le cercle de respiration avec minuteur. **Obligatoire pour publier** |
| `duration_min` | la durée, affichée « 10 min » | entier de 1 à 240 (contrainte en base). Pour `breath`, c'est la durée du minuteur (3 min si vide) |
| `how_md` / `how_md_fr` | les étapes, une par ligne | 2000 caractères max. Les marqueurs `1.` `1)` `-` `*` `•` en début de ligne sont retirés, les lignes vides ignorées. Texte simple : l'app n'interprète pas le Markdown (`**gras**` s'afficherait tel quel). **Au moins une étape (EN ou FR) pour publier** |
| `general_why` / `general_why_fr` | le pourquoi, en langage simple (« Pourquoi dans votre plan ») | 800 caractères max. Pas exigé pour publier, mais **validé par le clinicien** |
| `resources` | les liens, en liste typée (jsonb, `[]` par défaut) | `{"kind":"video","url":"https://…","title":"…"}` · `{"kind":"youtube","query":"…"}` · `{"kind":"article","slug":"…","title":"…"}`. L'éditeur en garde **au plus un de chaque sorte**. Vidéo : URL en `https://` (sinon l'app l'ignore), 500 caractères max, titre 120. YouTube : un mot-clé de recherche (100 max), l'app ouvre la recherche YouTube, rien n'est intégré. Article : un slug **existant** de la bibliothèque de l'app (sinon l'éditeur refuse d'enregistrer) ; l'éditeur remplit le `title` avec le titre de l'article (en SQL, l'écrire soi-même) |
| `image_url`, `image_alt` | l'image en haut de la carte, et sa description pour VoiceOver | URL en `https://` (500 max) ; l'éditeur téléverse JPEG, PNG ou WebP. `image_alt` 200 max |
| `default_slot` | le moment de la journée | `morning` · `midday` · `evening`, ou vide = « N'importe quand » |
| `frequency_rule` | la fréquence proposée quand le membre ajoute la carte depuis « Actions de base » | `RRULE:FREQ=DAILY[;INTERVAL=n]` ou `RRULE:FREQ=WEEKLY[;INTERVAL=n][;BYDAY=MO,WE,…]` (le préfixe `RRULE:` est facultatif). Toute autre `FREQ` est lue comme « tous les jours » ; `WEEKLY` sans `BYDAY` = le jour de la semaine où l'habitude a été créée ; vide = `FREQ=DAILY`. **Absent de l'éditeur.** Une habitude prescrite garde sa propre règle, et le focus du jour ne lit pas ce champ |
| `member_can_add` | le membre peut l'ajouter lui-même depuis « Actions de base » | défaut `false`. Ne sert que si la carte est publiée |
| `sort_order` | l'ordre dans le pilier (focus du jour, banque du membre, sélecteur CLINICAL) | entier, défaut `0`. **Absent de l'éditeur** |
| `active`, `published_at`, `published_by` | brouillon (`active = false`, `published_at` vide) → publiée (`active = true`, `published_at` et `published_by` remplis) → retirée (`active = false`, `published_at` gardé) | brouillons : `resources.write` (nutritionniste et plus). Publier, retirer et **modifier une carte publiée** : `resources.approve`, soit `lead_nutritionist` et `super_admin`. Une carte brouillon ou retirée est invisible pour les membres (RLS = `active`) et pour le focus du jour |

**Pour publier** (bouton grisé sinon) : un titre, un `card_kind`, une description (EN ou FR) et au moins une étape
(EN ou FR). Rien d'autre n'est vérifié par le code : le `general_why`, les versions et les liens restent à la charge
de l'auteur et du clinicien.

**Deux façons de créer des cartes :**

- **L'éditeur** (une carte à la fois). Il crée un brouillon (`active = false`) et règle tout sauf `category`,
  `frequency_rule` et `sort_order`. Son bouton « Fill empty fields with AI » (OpenAI) remplit seulement les champs
  vides, en anglais et en français, à partir du titre, du pilier, du type et des notes ; il choisit un article
  uniquement dans la bibliothèque et n'écrit jamais d'URL. Tout est à relire.
- **Un script SQL relu** (création en lot, seule façon de régler `category`, `frequency_rule` et `sort_order`).
  Attention : en base, `active` vaut **`true` par défaut**. Une carte insérée sans `active = false` est aussitôt
  visible des membres qui y sont reliés et utilisée par le focus du jour, sans être passée par la publication. Toujours
  écrire `active = false` et laisser `published_at` vide, puis publier depuis l'éditeur.

### 1.2 Les chiffres

- **36 cartes**, toutes `active = true` et publiées (la migration `20261002_action_cards` les a marquées publiées
  d'office). Aucune ne passerait la barrière de publication actuelle (ni `card_kind`, ni étapes), et comme elles sont
  en ligne, seul un `lead_nutritionist` ou un `super_admin` peut les modifier.
- **6 par pilier**, exactement : emotion 6 · exercise 6 · mind 6 · nutrition 6 · recovery 6 · sleep 6.
- Toutes ont un titre et une description en **anglais et en français**, une `category` et une `frequency_rule`.
- **0 carte** a `member_can_add = true` : « Actions de base », la banque que le membre voit dans l'app, est donc
  **vide aujourd'hui**.
- **Aucune habitude** de patient n'est reliée à une carte (`habits.habit_bank_id`) : 0 sur 6 habitudes, pour 20 items
  `habit` dans les care plans. Aujourd'hui, aucun membre n'ouvre donc de page de carte : la banque ne sert qu'au focus du jour.
- Fréquences : 34 cartes sont quotidiennes, 2 sont hebdomadaires (« A real lunch with someone » le mercredi,
  « A 20-minute nature walk » le samedi).
- Créneaux : **8 le matin · 17 à midi · 11 le soir**.
- Versions : **14** cartes ont une version douce (`easy_title`), **6** ont une version plus loin (`rev_title`),
  **3** ont les deux (X1, X5, X6), **19 n'ont ni l'une ni l'autre**.
- Les 14 versions douces sont complètes (titre et description, EN et FR). Les 6 versions plus loin ont un titre EN et
  FR mais **aucune description** (`rev_description` et `rev_description_fr` vides) : l'app et le focus du jour
  affichent alors la description standard sous le titre « plus loin ».
- Aucune carte n'a d'image (`image_url`).

### 1.3 Ce qui est complet, ce qui manque

Aujourd'hui, **chaque carte n'est qu'un titre et une description**. Les 5 éléments qui font une vraie carte action
manquent sur **les 36** :

| Élément manquant | Effet dans l'app |
|---|---|
| `card_kind` | pas d'étiquette de type ni d'icône ; pas de cercle de respiration pour les cartes de respiration ; la carte ne pourrait pas être republiée |
| `duration_min` | pas de « 5 min » sur la carte ; le minuteur de respiration part sur 3 min par défaut |
| `how_md` / `how_md_fr` | pas d'étapes : le membre ne voit que la phrase d'accroche |
| `general_why` / `general_why_fr` | pas de « pourquoi » |
| `resources` | ni vidéo, ni recherche YouTube, ni article lié |

Dans les tableaux ci-dessous, ce socle est noté **« socle »**. La colonne « à compléter » ajoute ce qui manque en plus
(version douce, version plus loin) et propose un `card_kind` et une durée de départ.

Manquent aussi : la description des 6 versions plus loin (X1, X3, X5, X6, M1, R6) et toute image (`image_url`).

### 1.4 Comment la banque est utilisée aujourd'hui

1. **Le focus du jour** (`FunctionAlps-IOS/supabase/functions/member-daily-focus` + `_shared/focus/engine.ts`).
   Chaque matin, un moteur à règles (pas d'IA) propose **au plus 3 actions** :
   - d'abord la réponse du cabinet à l'état du matin (`state_responses` : stressé, mal dormi, peu d'énergie, en forme,
     bien dormi). Ces offres sont écrites à la main ; si leur titre est **identique** à celui d'une carte de la banque
     (casse et ponctuation ignorées), elles en reprennent le pilier et le créneau ;
   - puis, pour chaque priorité que le membre a tapée (« ce que la journée est pour »), une carte de la banque, choisie
     par pilier puis par catégorie :

     | Priorité du membre | Pilier | Catégories préférées, dans l'ordre | Demande un effort ? |
     |---|---|---|---|
     | `prio_train` | exercise | strength → movement | oui |
     | `prio_move` | exercise | mobility → movement | non |
     | `prio_eat_well` | nutrition | food rhythm → hydration → mindful eating | non |
     | `prio_deep_work` | mind | focus → reset | oui |
     | `prio_rest` | recovery | rest → breaks → tension | non |
     | `prio_people` | emotion | connection | non |
     | `prio_outside` | recovery | nature | non |
     | `prio_early_night` | sleep | wind-down → regularity | non |

   - forme basse → **version douce** si elle existe ; forme haute → **version plus loin** si elle existe. À catégorie
     égale, le moteur préfère, à forme basse, les cartes **qui ont** une version douce (et à forme haute, celles qui
     ont une version plus loin). La catégorie passe avant : `prio_rest` prend R3 même sans version douce.
   - effort demandé un jour de forme basse → il ajoute une carte de récupération.
   - Le moteur lit seulement les cartes publiées (`active = true`), et seulement : `pillar`, `category`, `title`,
     `description`, `default_slot`, `easy_*`, `rev_*`, `sort_order` et leurs `_fr`. Il ne lit ni `card_kind`, ni
     `duration_min`, ni `how_md`, ni `general_why`, ni `resources`, ni `frequency_rule`.
   - Le membre voit le titre et la description de l'offre, **sans ouvrir la carte** : compléter le socle d'une carte ne
     change rien au focus du jour. Seuls les titres, les descriptions et les versions comptent ici.
2. **Le plan prescrit** (CLINICAL → fiche patient → onglet Plan → panneau habitudes). Le sélecteur `CardSelect`
   (cartes publiées seulement) rattache une habitude à une carte (`habits.habit_bank_id`), soit au moment de pousser
   un item `habit` vers l'app (fenêtre « push » du panneau, `lib/habit-loop/actions.ts` → `pushHabitItem`), soit
   ensuite sur une habitude existante. L'app lit alors la carte **en direct** : une modification publiée atteint tous
   les patients qui l'ont.
3. **La banque du membre** (« Actions de base », app iOS, `ActionBankView`). Elle montre les cartes publiées avec
   `member_can_add = true`. Ajouter une carte crée une habitude `source = 'self_initiated'` reliée à la carte : titre
   et description copiés dans la langue de l'app, moment choisi par le membre (celui de la carte proposé en premier),
   fréquence = `frequency_rule` de la carte. **Vide aujourd'hui.**
4. **Le care plan** (`lib/care-plan/translator.ts` → `pushItemToApp` → `pushHabit`, utilisé par les routes
   `care-plan/items/[itemId]/push`, `edit-fields` et `care-plan/activate`). Un item `habit` crée ou met à jour une ligne
   `habits`, **sans `habit_bank_id`** (ni moment, ni pilier, ni versions). Ce chemin-là ne sait pas encore relier une
   carte : c'est le chantier suivant. Pour que ce lien serve, la banque doit **couvrir ce que les care plans
   prescrivent réellement** (voir 4.6).

### 1.5 Ce que l'app affiche (`ActionCardView.swift`, `Models/ActionCards.swift`)

De haut en bas, chaque bloc n'apparaît que s'il est rempli :

1. l'**image** (`image_url`, en `https://` seulement) ;
2. une ligne « type · moment · durée » (ex. « MOUVEMENT · MIDI · 10 MIN » ; sans moment : « N'importe quand ») ;
3. le **titre** et la **description**. Pour une habitude prescrite, le titre est **celui de l'habitude** (les mots du
   clinicien pour ce patient) ; la description, les versions, les étapes et le pourquoi viennent de la carte, et la
   description de l'habitude ne sert que si la carte n'en a pas ;
4. pour `breath` seulement : le cercle de respiration, avec un minuteur de `duration_min` (3 min si vide) ;
5. « Version du jour » : Douce · Normale · Plus loin, si la carte a une version douce ou plus loin. Le membre peut
   changer. La version choisie d'office vient des versions écrites **sur l'habitude**, pas de celles de la carte ;
6. la vidéo (« Regarder la démonstration ») et la recherche YouTube (« Chercher « … » sur YouTube ↗ ») ;
7. « Comment faire » : les étapes numérotées ;
8. « Pourquoi dans votre plan » : le `general_why` ;
9. « À lire dans la bibliothèque » : l'article.

Langue : sur la carte, chaque champ est pris dans la langue de l'app, sinon dans l'autre langue, **champ par champ**.
Le focus du jour fait l'inverse : si un seul texte de l'offre manque en français, toute l'offre reste en anglais
(`present.ts`).

### 1.6 Exemple complet

La carte « Strength session » de la vitrine (3.1), écrite comme une ligne `habit_bank`. Les textes anglais reprennent
`ShowcaseData.swift`, sans la fréquence dans la description ; le pourquoi est adouci et reste **à valider par le
clinicien**. `category`, `frequency_rule` et `sort_order` ne se règlent qu'en SQL (voir 1.1). `published_at` et
`published_by` sont remplis à la publication, jamais par l'auteur.

```json
{
  "pillar": "exercise",
  "category": "strength",
  "card_kind": "movement",
  "duration_min": 25,
  "default_slot": "midday",
  "frequency_rule": "RRULE:FREQ=WEEKLY;BYDAY=MO,TH",
  "sort_order": 7,
  "member_can_add": false,
  "active": false,
  "title": "Strength session",
  "title_fr": "Séance de renforcement",
  "description": "Four moves, three rounds, no equipment.",
  "description_fr": "Quatre mouvements, trois tours, sans matériel.",
  "easy_title": "Two rounds",
  "easy_title_fr": "Deux tours",
  "easy_description": "Same four moves, two rounds, longer rests.",
  "easy_description_fr": "Les mêmes quatre mouvements, deux tours, des pauses plus longues.",
  "rev_title": "Four rounds",
  "rev_title_fr": "Quatre tours",
  "rev_description": "Four rounds, or hold a backpack for the squats.",
  "rev_description_fr": "Quatre tours, ou un sac à dos dans les bras pour les squats.",
  "how_md": "1. 12 squats to a chair.\n2. 10 push-ups against a table or the floor.\n3. 12 rows with a backpack.\n4. 30-second plank.\n5. Rest one minute and repeat for three rounds.",
  "how_md_fr": "1. 12 squats jusqu'à la chaise.\n2. 10 pompes contre une table ou au sol.\n3. 12 tirages avec un sac à dos.\n4. 30 secondes de gainage.\n5. Une minute de pause, puis recommencez : trois tours en tout.",
  "general_why": "Muscle is your capacity reserve. Short, regular sessions help you keep it in everyday life.",
  "general_why_fr": "Le muscle est votre réserve de capacité. Des séances courtes et régulières aident à l'entretenir au quotidien.",
  "image_url": null,
  "image_alt": null,
  "resources": [
    { "kind": "youtube", "query": "beginner full body strength workout no equipment 20 minutes" }
  ]
}
```

Un lien vidéo s'écrirait `{ "kind": "video", "url": "https://…", "title": "…" }` et un article
`{ "kind": "article", "slug": "<slug existant>", "title": "<titre de l'article>" }`.

---

## 2. Inventaire par pilier

Légende : **socle** = `card_kind` + `duration_min` + `how_md`/`_fr` + `general_why`/`_fr` + `resources` (manquants
partout). Fréquence « tous les jours » = `RRULE:FREQ=DAILY`. Quand une carte a une version plus loin, sa description
(EN et FR) est aussi à écrire. Une version douce ou plus loin est une **autre façon de faire l'action le même jour** :
elle ne change ni la fréquence ni les jours. Descriptions actuelles qui affirment un effet sur le corps, à faire relire
par le clinicien en même temps que le socle : X5, M1 (« meals land better »), M5 (« Light anchors the body clock »),
N2 (« Steadier energy before 11:00 »), S2 (« The afternoon cup steals from the night »).

### 2.1 Emotion — le lien aux autres, mettre un mot sur ce qu'on ressent, protéger ses limites

| # | Titre EN / FR | Catégorie | Créneau | Fréquence | Douce / plus loin | L'idée derrière | À compléter |
|---|---|---|---|---|---|---|---|
| E1 | **Name the feeling, once**<br>*Nommez l’émotion, une fois* | awareness | soir | tous les jours | — / — | Mettre un mot précis sur ce qu'on ressent (« agacé » plutôt que « pas bien ») pour prendre un petit recul. Une seule fois par jour, pour que ce soit tenable. À proposer à un membre qui « ne sait pas ce qu'il a » ou qui réagit vite sous pression. | socle (`mind`, ~2 min) · douce (ex. choisir un mot dans une liste) · plus loin (nommer + noter le déclencheur) |
| E2 | **One message to someone you like**<br>*Un message à quelqu’un que vous appréciez* | connection | midi | tous les jours | — / — | Un micro-geste de lien, assez petit pour ne jamais être reporté. Entretient le réseau sans avoir à organiser une rencontre. Pour une personne isolée par sa charge de travail. | socle (`mind`, ~1 min) · plus loin (un appel plutôt qu'un message) |
| E3 | **Three good things tonight**<br>*Trois bonnes choses ce soir* | gratitude | soir | tous les jours | One good thing / — | Exercice classique de psychologie positive : tourner l'attention vers ce qui a marché, avant de dormir. Pour une humeur basse ou des soirées qui ruminent. | socle (`mind`, ~3 min) · plus loin (« … et pourquoi c'est arrivé ») |
| E4 | **Journaling, five minutes**<br>*Cinq minutes de journal* | reflection | soir | tous les jours | Three lines / — | Vider la tête sur le papier, sans filtre, pour mettre de l'ordre dans ce qui tourne en boucle. Pour une forte charge mentale, du mal à décrocher. | socle (`mind`, 5 min) · plus loin · ⚠ recoupe S5 et E3 (trois écritures le soir : en choisir une) |
| E5 | **A real lunch with someone**<br>*Un vrai déjeuner avec quelqu’un* | connection | midi | 1×/semaine (mercredi) | — / — | Transformer un moment déjà là (le repas) en moment partagé, une fois par semaine : pause et lien en même temps. Pour un membre qui mange seul devant l'écran. | socle (`routine`, ~45 min) · douce (un café de 15 min avec quelqu'un) · ⚠ recoupe R1 |
| E6 | **Say no to one thing**<br>*Dites non à une chose* | boundaries | midi | tous les jours | — / — | S'entraîner à protéger son temps par un petit refus quotidien, plutôt que d'attendre la grande décision. Pour une personne surchargée qui dit oui à tout. | socle (`mind`, ~2 min) · douce (repérer un oui qu'on aurait voulu être un non) · même catégorie que R4 |

À noter : **aucune carte emotion le matin**. Le moteur ne préfère que `connection` (pour `prio_people`) : les catégories
`awareness`, `gratitude`, `reflection` et `boundaries` ne sortent qu'en second choix.

### 2.2 Exercise — bouger le corps : mouvement au quotidien, mobilité, force

| # | Titre EN / FR | Catégorie | Créneau | Fréquence | Douce / plus loin | L'idée derrière | À compléter |
|---|---|---|---|---|---|---|---|
| X1 | **A 10-minute walk after lunch**<br>*Une marche de 10 minutes après le déjeuner* | movement | midi | tous les jours | Five minutes outside / Stretch it to 20 minutes | Accrochée à un moment fixe (le déjeuner), courte, faisable en tenue de travail. Vise le coup de barre de l'après-midi. **C'est aussi une des 4 actions vitrine (section 3.1)** : reprendre son contenu. | socle (`movement`, 10 min) |
| X2 | **Morning stretch, five minutes**<br>*Étirements du matin, cinq minutes* | mobility | matin | tous les jours | Two stretches at the counter / — | Un réveil du corps avant les sollicitations de la journée. La version douce s'accroche à la cuisine (on greffe le geste sur une habitude existante). Pour la raideur du matin et le travail assis. | socle (`movement`, 5 min, vidéo démo) · plus loin (à écrire ; ne pas en faire une séance de 10 min, qui doublerait « Hip and back mobility », 3.3) |
| X3 | **One set of push-ups**<br>*Une série de pompes* | strength | matin | tous les jours | — / Two sets — rest a minute between | Une dose minimale de force du haut du corps, sans matériel ; la régularité compte plus que le nombre. | socle (`movement`, ~2 min, vidéo technique) · **douce manquante** (pompes contre un mur ou une table) : prioritaire, car `prio_train` la choisit en premier, sauf les jours de forme basse où, faute de version douce, le moteur passe à X6 · clinicien : épaules et poignets |
| X4 | **Stairs instead of lifts**<br>*Les escaliers plutôt que l’ascenseur* | movement | midi | tous les jours | — / — | Du « mouvement caché » : remplacer un choix automatique par un effort court, sans temps dédié. Pour ceux qui « n'ont pas le temps de faire du sport ». | socle (`movement`, ~2 min) · douce (un étage, puis l'ascenseur) · plus loin (monter deux fois) |
| X5 | **Evening walk**<br>*Marche du soir* | movement | soir | tous les jours | Five minutes around the block / Add ten extra minutes | Bouger sans intensité après le dîner, comme transition vers la soirée. ⚠ La description actuelle (« Movement after dinner — the strongest gentle lever on sleep. ») est une affirmation santé au superlatif : le clinicien doit la valider ou la reformuler. | socle (`movement`, ~15 min) · ⚠ recoupe X1 (deux marches par jour : choisir selon la personne) |
| X6 | **Ten sit-to-stands**<br>*Dix assis-debout* | strength | midi | tous les jours | Five sit-to-stands / Two rounds of ten | Le mouvement fonctionnel de base (se lever d'une chaise), dosable partout. Une des trois cartes avec l'échelle complète douce · standard · plus loin (avec X1 et X5) : le modèle à suivre. | socle (`movement`, ~2 min, vidéo) |

À noter : la force n'existe qu'en micro-doses (X3, X6). Il manque une **vraie séance** (action vitrine 3.1).

### 2.3 Mind — l'attention et le calme : respiration, concentration, micro-pauses

| # | Titre EN / FR | Catégorie | Créneau | Fréquence | Douce / plus loin | L'idée derrière | À compléter |
|---|---|---|---|---|---|---|---|
| M1 | **Three slow breaths before meals**<br>*Trois respirations lentes avant les repas* | calm | midi | tous les jours | — / Box breathing, 4×4, once a day | Accrocher une micro-pause respiratoire à un déclencheur fréquent (le repas) : se poser avant de manger. | socle (`breath`, ~1 min) · ⚠ la version plus loin **double** la carte M2 |
| M2 | **Box breathing, 4×4**<br>*Respiration carrée, 4×4* | calm | midi | tous les jours | — / — | Une technique structurée et comptée, pour reprendre la main dans un moment de tension ; compter donne un point d'appui quand l'esprit s'agite. | socle (`breath`, ~2 min : le minuteur de l'app utilise `duration_min`) · douce (3×3 ou expiration seule) · clinicien : les rétentions de souffle ne conviennent pas à tous |
| M3 | **One phone-free coffee**<br>*Un café sans téléphone* | focus | matin | tous les jours | — / — | Un moment mono-tâche protégé par un objet (la tasse) : s'entraîner à ne faire qu'une chose. Pour un membre qui commence sa journée dans ses notifications. | socle (`mind`, ~10 min) · douce (les trois premières gorgées) |
| M4 | **Single-task the first work hour**<br>*Une seule tâche pendant la première heure de travail* | focus | matin | tous les jours | Single-task the first 20 minutes / — | Placer le travail exigeant avant le bruit (messages, réunions), en début de journée. | socle (`mind`, 60 min) · plus loin = « un bloc de 90 minutes » (item du plan vitrine) |
| M5 | **Five minutes of daylight**<br>*Cinq minutes de lumière du jour* | reset | matin | tous les jours | Open the window — two minutes counts / — | La lumière du matin comme signal de rythme, rangée ici en `mind/reset` (effet « réveil »). | socle (`routine`, 5 min) · ⚠ **doublon** de S6, proche de R2 : décider de la carte de référence (4.3) |
| M6 | **A two-minute pause between tasks**<br>*Une pause de deux minutes entre deux tâches* | reset | midi | tous les jours | — / — | Une transition entre deux tâches (se lever, regarder au loin, respirer) pour ne pas tout enchaîner. | socle (`mind`, 2 min) · douce · plus loin |

À noter : **aucune carte mind le soir**. `calm` n'est préférée par aucune priorité.

### 2.4 Nutrition — le rythme et la composition des repas, l'hydratation, la façon de manger

| # | Titre EN / FR | Catégorie | Créneau | Fréquence | Douce / plus loin | L'idée derrière | À compléter |
|---|---|---|---|---|---|---|---|
| N1 | **A glass of water before coffee**<br>*Un verre d’eau avant le café* | hydration | matin | tous les jours | — / — | Greffer un geste sur un rituel déjà quotidien (le café) : boire avant le stimulant. Fait partie de la routine vitrine du matin. | socle (`nutrition`, 1 min) · plus loin (un second verre avant midi) |
| N2 | **Protein at breakfast**<br>*Des protéines au petit-déjeuner* | food rhythm | matin | tous les jours | Anything at breakfast counts / — | Rendre le petit-déjeuner plus rassasiant avec une source de protéines simple ; viser une matinée plus régulière (formulation santé à faire valider). | socle (`nutrition`, 5 min) · plus loin = « des protéines à chaque repas » (item du plan vitrine) · quantités : clinicien |
| N3 | **Vegetables on half the plate**<br>*Des légumes sur la moitié de l’assiette* | food rhythm | midi | tous les jours | — / — | Une règle visuelle (la moitié de l'assiette) plutôt qu'un comptage. | socle (`nutrition`) · douce (une portion au déjeuner) · plus loin (deux repas par jour) |
| N4 | **Slow first five bites**<br>*Les cinq premières bouchées, lentement* | mindful eating | midi | tous les jours | Three slow bites / — | Ralentir le début du repas pour donner le rythme de tout le repas. Une porte d'entrée facile vers le « manger en conscience ». | socle (`nutrition`, 2 min) · plus loin (poser la fourchette entre les bouchées) |
| N5 | **Fruit within reach**<br>*Un fruit à portée de main* | food rhythm | midi | tous les jours | — / — | Architecture du choix : préparer l'option facile avant le moment de faiblesse (le creux de l'après-midi). | socle (`nutrition`, 1 min) · plus loin (fruit + poignée d'oléagineux) · ⚠ proche de la collation protéinée vitrine |
| N6 | **Kitchen closed after 21:00**<br>*Cuisine fermée après 21 h* | food rhythm | soir | tous les jours | One late snack is fine — just notice it / — | Une heure de fermeture fixe remplace les décisions de volonté, et laisse un espace entre le dernier repas et le coucher. | socle (`routine`) · **sur prescription** : le clinicien tient compte des horaires et du rapport à l'alimentation |

### 2.5 Recovery — récupérer pendant la journée : pauses, nature, relâcher les tensions, frontières avec le travail

| # | Titre EN / FR | Catégorie | Créneau | Fréquence | Douce / plus loin | L'idée derrière | À compléter |
|---|---|---|---|---|---|---|---|
| R1 | **A real pause at lunch, no screens**<br>*Une vraie pause à midi, sans écrans* | breaks | midi | tous les jours | Ten minutes, no screens / — | Une vraie coupure au milieu de la journée de travail, où rien n'est demandé. | socle (`routine`, 20 min) · ⚠ recoupe E5 |
| R2 | **Five minutes outside in daylight**<br>*Cinq minutes dehors, à la lumière du jour* | nature | midi | tous les jours | — / — | La recharge minimale (sortir, de la lumière, de l'air), faisable même les jours chargés. | socle (`routine`, 5 min) · douce · plus loin (→ R6) · ⚠ famille « lumière du jour » (4.3) |
| R3 | **Legs up the wall, five minutes**<br>*Jambes au mur, cinq minutes* | rest | soir | tous les jours | — / — | Une position de repos passive, un signal de bascule vers la soirée. | socle (`movement`, 5 min, vidéo) · douce (allongé, jambes sur une chaise) · clinicien : posture |
| R4 | **One work-free evening block**<br>*Un créneau sans travail le soir* | boundaries | soir | tous les jours | — / — | Une frontière nette dans le temps entre travail et récupération. | socle (`routine`, 60 min) · douce (30 min) · plus loin (toute la soirée) |
| R5 | **Shoulders down, jaw loose — three times**<br>*Épaules basses, mâchoire relâchée — trois fois* | tension | midi | tous les jours | — / — | Un scan express des endroits où la tension s'installe sans qu'on le remarque, trois rappels par jour. | socle (`mind`, 1 min) · douce · plus loin |
| R6 | **A 20-minute nature walk**<br>*Une balade de 20 minutes dans la nature* | nature | midi | 1×/semaine (samedi) | — / Make it forty minutes | Du temps au vert sans objectif de performance, le week-end, quand il y a de la place. | socle (`movement`, 20 min) · douce (10 min dans un parc) |

À noter : **aucune carte recovery le matin**. `prio_rest` tombe d'abord sur R3, qui n'a pas de version douce.

### 2.6 Sleep — la régularité du rythme veille-sommeil et la descente vers le coucher

| # | Titre EN / FR | Catégorie | Créneau | Fréquence | Douce / plus loin | L'idée derrière | À compléter |
|---|---|---|---|---|---|---|---|
| S1 | **Same bedtime on weekdays**<br>*Même heure de coucher en semaine* | regularity | soir | tous les jours | — / — | La régularité de l'horaire comme ancre : viser un rythme stable avant un nombre d'heures. | socle (`routine`) · douce (à 30 min près) · pas de « plus loin (week-end compris) » : une version ne change pas les jours · ⚠ **incohérence** : le titre dit « en semaine », la règle dit tous les jours (→ `RRULE:FREQ=WEEKLY;BYDAY=SU,MO,TU,WE,TH` pour les soirs qui précèdent un jour de semaine, ou `MO,TU,WE,TH,FR` : à trancher ; correction en SQL, l'éditeur ne règle pas `frequency_rule`) |
| S2 | **No caffeine after 14:00**<br>*Pas de caféine après 14 h* | regularity | midi | tous les jours | — / — | Une heure-limite claire plutôt qu'un « moins de café » flou. | socle (`nutrition`) · douce (après 16 h) · plus loin (avant midi seulement, item du plan vitrine) |
| S3 | **Screens off 30 minutes before bed**<br>*Écrans éteints 30 minutes avant le coucher* | wind-down | soir | tous les jours | Phone out of the bedroom / — | Donner à l'esprit une « piste d'atterrissage » sans stimulation avant le coucher. | socle (`routine`, 30 min) · plus loin (60 min) |
| S4 | **Dim the lights after 21:00**<br>*Lumières tamisées après 21 h* | wind-down | soir | tous les jours | — / — | Se servir de la lumière de la maison comme signal de fin de journée. | socle (`routine`) · douce (une seule lampe) · plus loin |
| S5 | **Tomorrow's list before bed**<br>*La liste de demain avant le coucher* | wind-down | soir | tous les jours | One line for tomorrow / — | Déposer sur papier les choses en suspens pour ne pas les emporter au lit. | socle (`mind`, 5 min) · ⚠ recoupe E4 |
| S6 | **Morning light within an hour of waking**<br>*Lumière du matin dans l’heure qui suit le réveil* | regularity | matin | tous les jours | — / — | « La nuit se prépare le matin » : de la lumière tôt, comme signal de rythme (justification à faire valider). | socle (`routine`, 10 min) · douce (à la fenêtre) · plus loin (marcher dans la lumière du matin) · ⚠ doublon de M5 |

À noter : **une seule carte sleep le matin**, alors que plusieurs leviers de régularité se jouent au réveil.

---

## 3. Actions à créer — suggestions

Chaque idée donne : titre EN / FR, créneau, fréquence (`frequency_rule` + en clair), l'idée derrière et le `card_kind`
proposé. La catégorie reprend une valeur existante quand c'est possible (voir 4.5). Profil pris comme repère : celui
du plan vitrine, **des membres de 40 à 60 ans qui veulent retrouver énergie, concentration et sommeil** ; la banque
sert tous les membres. Toute justification santé reste à faire valider par le clinicien. Rappel : `category`,
`frequency_rule` et `sort_order` ne se règlent qu'en SQL (1.1).

### 3.1 Les 4 actions vitrine (`ShowcaseData.swift`), à créer en premier

Trois de ces quatre cartes n'existent que dans les données de démonstration de l'app iOS (captures d'écran), pas en
base ; la quatrième existe déjà (X1), sous un titre un peu différent. Leur contenu (étapes, versions, pourquoi, liens)
est un **premier jet** réutilisable, à relire et faire valider. La vitrine ne leur donne pas de catégorie : celles
proposées ci-dessous sont des suggestions.

| Titre EN / FR | Pilier · catégorie | Créneau | Fréquence | `card_kind` · durée | L'idée derrière | Recoupements |
|---|---|---|---|---|---|---|
| **Morning circadian routine**<br>*Routine circadienne du matin* | sleep · regularity | matin | `RRULE:FREQ=DAILY`, tous les jours | `routine` · 10 min | Une carte « chapeau » qui regroupe 4 gestes du matin : même heure de lever, lumière du jour, eau avant le café, petit-déjeuner protéiné. Douce : « Daylight at the window ». Plus loin : « Walk in the morning light ». À prescrire à un membre prêt à faire un bloc, sinon prescrire les cartes séparées une à une. | contient S6, M5, N1, N2 : décider si la routine **remplace** ces cartes dans un plan ou si elle sert de niveau suivant |
| **Protein snack mid-afternoon**<br>*Collation protéinée en milieu d'après-midi* | nutrition · food rhythm | midi (pas de créneau « après-midi », voir 4.4) | `RRULE:FREQ=DAILY`, tous les jours | `nutrition` · 5 min | Remplacer le sucré de 16 h par une petite collation protéinée préparée d'avance (yaourt + noix, œuf + fruit, houmous + crudités). Vise le creux de fin d'après-midi et la faim du soir (formulation à valider). | proche de N5 : la version douce de cette carte peut reprendre l'idée de N5 (un fruit prêt d'avance) ; une carte ne peut pas être la version d'une autre |
| **Strength session**<br>*Séance de renforcement* | exercise · strength | midi (ajustable) | `RRULE:FREQ=WEEKLY;BYDAY=MO,TH`, 2×/semaine (jours ajustés par le praticien) | `movement` · 25 min | Quatre mouvements sans matériel (squat sur chaise, pompes inclinées, rowing avec sac à dos, gainage), trois tours. Douce : « Two rounds ». Plus loin : « Four rounds ». La vraie séance qui manque à la banque. | X3 et X6 en sont les micro-doses. Dans la vitrine, la carte s'appelle « Strength session » ; c'est **l'habitude** qui s'appelle « Strength session · twice a week ». Garder « Strength session » pour la carte : la fréquence va dans `frequency_rule` |
| **10-minute walk after lunch**<br>*Une marche de 10 minutes après le déjeuner* | exercise · movement | midi | `RRULE:FREQ=DAILY` | `movement` · 10 min | **Ne pas créer : elle existe déjà (X1).** Compléter X1 avec les étapes et le pourquoi de la vitrine. | Garder le titre de la base, « A 10-minute walk after lunch » : le moteur ne rapproche que des titres identiques |

### 3.2 Sleep — idées nouvelles

| Titre EN / FR | Catégorie | Créneau | Fréquence | `card_kind` | L'idée derrière |
|---|---|---|---|---|---|
| **Same wake-up time, weekends included**<br>*Même heure de lever, week-end compris* | regularity | matin | `RRULE:FREQ=DAILY` | `routine` | On choisit son heure de lever, pas son heure d'endormissement : c'est une ancre simple à tenir. Douce : à 30 min près le week-end. Complète S1 (coucher) côté matin. |
| **A 20-minute wind-down ritual**<br>*Un rituel de décompression de 20 minutes* | wind-down | soir | `RRULE:FREQ=DAILY` | `routine` | Enchaîner toujours les mêmes gestes (lumière basse, douche, lecture) pour que le cerveau associe la séquence au coucher. Peut servir de carte « chapeau » pour S3 et S4. |
| **Cool, dark, quiet bedroom**<br>*Chambre fraîche, sombre et calme* | wind-down | soir | `RRULE:FREQ=WEEKLY;BYDAY=SU`, 1×/semaine (vérification) | `routine` | Agir une fois sur l'environnement plutôt que chaque soir sur la volonté : rideaux, température, bruit. Item déjà présent dans le care plan vitrine. |
| **A warm shower in the evening**<br>*Une douche tiède le soir* | wind-down | soir | `RRULE:FREQ=DAILY` | `routine` | Un repère de fin de journée facile à installer dans le rituel du soir. Justification physiologique à faire valider. |
| **Alcohol-free weeknights**<br>*Soirs de semaine sans alcool* | regularity | soir | `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH` | `routine` | Une règle de calendrier plutôt qu'une quantité. Pour un membre qui boit un verre « pour décompresser ». **Sur prescription**, formulation validée par le clinicien. |
| **Keep naps short and early**<br>*Une sieste courte, avant 15 h* | regularity | midi | `RRULE:FREQ=DAILY` | `routine` | Encadrer la sieste (20 min max, tôt) au lieu de l'interdire. **Sur prescription** : selon le profil, le clinicien peut préférer pas de sieste du tout. |
| **Awake at night? Get up rather than fight it**<br>*Réveillé la nuit ? Se lever plutôt que lutter* | regularity | soir | `RRULE:FREQ=DAILY` | `routine` | Ne pas associer le lit à l'éveil : se lever, lumière douce, revenir quand le sommeil revient. Élément de prise en charge structurée : **sur prescription uniquement**. |
| **How your body clock works**<br>*Comprendre son horloge interne* | regularity | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO` | `learn` | Une carte « apprendre » reliée à un article de la bibliothèque (thème `sommeil`), pour donner du sens aux cartes de régularité. |

### 3.3 Exercise — idées nouvelles

| Titre EN / FR | Catégorie | Créneau | Fréquence | `card_kind` | L'idée derrière |
|---|---|---|---|---|---|
| **Brisk walk, 30 minutes**<br>*Marche rapide de 30 minutes* | movement | midi | `RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR`, 3×/semaine | `movement` | Une base d'endurance à une allure où l'on parle encore, mais sans pouvoir chanter. Plus loin : quelques minutes plus vite au milieu. Différente de X1 (digestion, allure facile). |
| **Balance while brushing your teeth**<br>*L'équilibre sur une jambe pendant le brossage de dents* | mobility | matin | `RRULE:FREQ=DAILY` | `movement` | Greffer un exercice d'équilibre sur un geste déjà quotidien, deux minutes sans temps dédié. Douce : une main sur le lavabo. |
| **Hip and back mobility, 10 minutes**<br>*Mobilité hanches et dos, 10 minutes* | mobility | soir | `RRULE:FREQ=WEEKLY;BYDAY=TU,TH,SA`, 3×/semaine | `movement` | Une vraie séance de mobilité pour qui est assis toute la journée. Plus longue et plus ciblée que X2 (le réveil du matin). |
| **Get off one stop early**<br>*Descendre un arrêt plus tôt* | movement | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` | `movement` | Du mouvement caché dans le trajet, de la même famille que X4. Variante voiture : se garer plus loin. |
| **A long weekend outing**<br>*Une sortie longue le week-end* | movement | midi | `RRULE:FREQ=WEEKLY;BYDAY=SU` | `movement` | Randonnée ou vélo, 60 minutes ou plus, avec un peu d'effort. Différente de R6 (balade sans objectif) : l'une récupère, l'autre entraîne. |
| **Active recovery the day after strength**<br>*Récupération active le lendemain de la séance* | movement | midi | `RRULE:FREQ=WEEKLY;BYDAY=TU,FR` (lendemains de la séance vitrine) | `movement` | 20 minutes faciles (marche, vélo doux) pour continuer à bouger sans ajouter de fatigue. À coupler avec « Strength session ». |
| **Why muscle matters after 40**<br>*Le muscle après 40 ans : comprendre l'enjeu* | strength | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO` | `learn` | Une carte « apprendre » qui donne du sens à la séance de force. Contenu santé à faire valider. |

### 3.4 Mind — idées nouvelles

| Titre EN / FR | Catégorie | Créneau | Fréquence | `card_kind` | L'idée derrière |
|---|---|---|---|---|---|
| **A long-exhale breath before bed**<br>*Respirer en allongeant l'expiration avant de dormir* | calm | soir | `RRULE:FREQ=DAILY` | `breath` (5 min) | Une respiration sans rétention, plus simple que M2, pour ralentir le soir. Comble le vide « mind le soir ». |
| **The double sigh**<br>*Le double soupir* | calm | midi | `RRULE:FREQ=DAILY` | `breath` (1 min) | Deux inspirations par le nez, une longue expiration par la bouche : un « reset » de quelques secondes, utilisable n'importe où. |
| **Ten-minute body scan**<br>*Un scan corporel de 10 minutes* | calm | soir | `RRULE:FREQ=DAILY` | `mind` (10 min) | Promener son attention dans le corps, de la tête aux pieds. Pour un esprit qui tourne le soir. Plus loin que R5 (express). |
| **Notifications off for your focus block**<br>*Notifications coupées pendant le bloc de concentration* | focus | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` | `mind` | Agir sur l'environnement plutôt que sur la volonté : ce qui ne sonne pas ne distrait pas. Complète M4. |
| **Three priorities for the day**<br>*Trois priorités pour la journée* | focus | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` | `mind` (3 min) | Décider le matin de ce qui compte, pour que l'attention ait une cible. ⚠ C'est la version matin de S5 : proposer l'une **ou** l'autre selon la personne. |
| **End-of-workday shutdown**<br>*Le rituel de fin de journée de travail* | reset | soir | `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` | `routine` (5 min) | Fermer les boucles (noter ce qui reste, fermer les onglets, dire « terminé ») pour que le travail ne déborde pas sur la soirée. C'est le déclencheur de R4. |
| **How attention gets tired**<br>*Comprendre la fatigue de l'attention* | focus | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO` | `learn` | Une carte « apprendre » qui donne du sens aux cartes de concentration et de pause (M4, M6). |

Ne pas créer « 90-minute focus block » comme carte séparée : en faire la **version plus loin de M4** (item s8 du plan
vitrine). Si un care plan le prescrit comme action principale, voir la limite en 4.6.

### 3.5 Nutrition — idées nouvelles

| Titre EN / FR | Catégorie | Créneau | Fréquence | `card_kind` | L'idée derrière |
|---|---|---|---|---|---|
| **A portion of legumes**<br>*Une portion de légumineuses* | food rhythm | midi | `RRULE:FREQ=DAILY` | `nutrition` | Une portion de lentilles, pois chiches ou haricots par jour, objectif simple et concret. Douce : une petite portion (quelques cuillères dans un plat). Pour 3×/semaine, c'est la fréquence de l'habitude qui change, pas la version. |
| **A new plant this week**<br>*Un nouveau végétal cette semaine* | food rhythm | midi | `RRULE:FREQ=WEEKLY;BYDAY=SA` | `nutrition` | Varier par la curiosité plutôt que par la règle : un légume, une herbe ou une graine jamais achetés. |
| **A water bottle on your desk**<br>*Une gourde sur le bureau* | hydration | midi | `RRULE:FREQ=DAILY` | `nutrition` | Architecture du choix : l'eau qu'on a sous les yeux, on pense à la boire. Prolonge N1 sur la journée. |
| **Swap one sweet drink**<br>*Remplacer une boisson sucrée* | hydration | midi | `RRULE:FREQ=DAILY` | `nutrition` | Une substitution précise (eau pétillante, infusion) plutôt qu'une interdiction. |
| **Oily fish for dinner**<br>*Du poisson gras au dîner* | food rhythm | soir | `RRULE:FREQ=WEEKLY;BYDAY=TU,FR` | `nutrition` | Un repère de fréquence plutôt qu'une quantité. **Sur prescription** (régime, allergies, alternatives végétales : le clinicien choisit), justification à faire valider. |
| **Plan tomorrow's lunch**<br>*Prévoir le déjeuner de demain* | food rhythm | soir | `RRULE:FREQ=WEEKLY;BYDAY=SU,MO,TU,WE,TH` | `routine` (5 min) | Décider au calme la veille, plutôt qu'affamé à midi. |
| **Sunday prep, one hour**<br>*Une heure de préparation le dimanche* | food rhythm | midi | `RRULE:FREQ=WEEKLY;BYDAY=SU` | `routine` (60 min) | Cuire d'avance une base (céréales, légumes rôtis, protéines) qui rend la semaine facile. Le niveau suivant de « Plan tomorrow's lunch ». |
| **Read a label in 30 seconds**<br>*Lire une étiquette en 30 secondes* | mindful eating | midi | `RRULE:FREQ=WEEKLY;BYDAY=SA` | `learn` | Une carte « apprendre » reliée à un article : les trois choses à regarder sur un emballage. |

Ne pas créer « Protein at every meal » comme carte séparée : en faire la **version plus loin de N2** (item s3 du plan
vitrine). Si un care plan le prescrit comme action principale, voir la limite en 4.6.

### 3.6 Recovery — idées nouvelles

| Titre EN / FR | Catégorie | Créneau | Fréquence | `card_kind` | L'idée derrière |
|---|---|---|---|---|---|
| **The first 10 minutes without a screen**<br>*Les 10 premières minutes sans écran* | breaks | matin | `RRULE:FREQ=DAILY` | `routine` | Commencer la journée à son rythme avant de laisser entrer les autres. Comble le vide « recovery le matin ». ⚠ Proche de M3 : M3 vise l'attention, celle-ci le réveil. |
| **Neck and shoulder self-massage**<br>*Auto-massage nuque et épaules* | tension | soir | `RRULE:FREQ=DAILY` | `movement` (5 min, vidéo) | La version active de R5 : relâcher en fin de journée ce qui s'est accumulé. |
| **A screen-free half-day**<br>*Une demi-journée sans écran* | boundaries | midi | `RRULE:FREQ=WEEKLY;BYDAY=SU` | `routine` | Une vraie coupure à l'échelle de la semaine, là où R4 coupe à l'échelle du jour. |
| **One evening with nothing planned**<br>*Une soirée sans rien de prévu* | rest | soir | `RRULE:FREQ=WEEKLY;BYDAY=WE` | `routine` | Protéger du vide dans l'agenda, pour qui enchaîne travail, famille et obligations. ⚠ Proche de la version plus loin proposée pour R4 (toute la soirée) : garder l'une ou l'autre. |
| **Weekly check: what drained me, what recharged me**<br>*Le bilan de la semaine : ce qui m'a vidé, ce qui m'a rechargé* | rest | soir | `RRULE:FREQ=WEEKLY;BYDAY=SU` | `mind` (10 min) | Observer avant d'ajuster : repérer ce qui recharge pour en remettre la semaine suivante. |
| **A warm bath or a sauna**<br>*Un bain chaud ou un sauna* | rest | soir | `RRULE:FREQ=WEEKLY;BYDAY=SA`, 1×/semaine | `routine` | Un temps de récupération passif et choisi. **Sur prescription** : le clinicien juge selon la personne. ⚠ Même famille que « A warm shower in the evening » (3.2). |

### 3.7 Emotion — idées nouvelles

| Titre EN / FR | Catégorie | Créneau | Fréquence | `card_kind` | L'idée derrière |
|---|---|---|---|---|---|
| **How do I want to show up today?**<br>*Comment je veux être aujourd'hui ?* | awareness | matin | `RRULE:FREQ=DAILY` | `mind` (1 min) | Une intention de **manière d'être** (patient, présent…), différente des priorités (ce qu'on fait). Comble le vide « emotion le matin ». |
| **A ten-minute worry window**<br>*Un créneau « soucis » de 10 minutes* | reflection | soir | `RRULE:FREQ=DAILY` | `mind` (10 min) | Donner un rendez-vous aux inquiétudes en début de soirée, pour qu'elles ne s'invitent pas au coucher. À placer tôt, pas juste avant de dormir. ⚠ Encore une tâche d'écriture le soir, avec E3, E4 et S5 (3.8) : une seule à la fois. |
| **Something to look forward to**<br>*Une chose à attendre avec plaisir* | gratitude | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO` | `mind` | Planifier une petite chose agréable dans la semaine : mettre des moments positifs au calendrier plutôt qu'attendre qu'ils arrivent. |
| **One small kind act**<br>*Un petit geste gentil* | connection | midi | `RRULE:FREQ=DAILY` | `mind` | Tourner l'attention vers les autres un instant, par un geste concret. ⚠ Proche de E2 (même catégorie, même créneau) : la différenciation est à écrire dans les étapes. |
| **Talk to yourself like a friend**<br>*Se parler comme à un ami* | awareness | soir | `RRULE:FREQ=DAILY` | `mind` (2 min) | Repérer une phrase dure qu'on s'est dite aujourd'hui et la reformuler comme on le ferait pour un proche. Pour les profils très exigeants envers eux-mêmes. |
| **Savour one moment**<br>*Savourer un moment* | gratitude | midi | `RRULE:FREQ=DAILY` | `mind` (1 min) | S'arrêter 20 secondes sur quelque chose d'agréable au moment où il arrive. La version « en direct » de E3. |
| **Thirty minutes just for you**<br>*Trente minutes rien que pour vous* | boundaries | soir | `RRULE:FREQ=WEEKLY;BYDAY=TH` | `routine` (30 min) | Un temps réservé à une activité choisie (loisir, musique, lecture), défendu comme un rendez-vous. |
| **What emotions are for**<br>*À quoi servent les émotions* | awareness | matin | `RRULE:FREQ=WEEKLY;BYDAY=MO` | `learn` | Une carte « apprendre » qui donne du sens à E1 et aux cartes d'émotion. |

« A weekly call to someone who matters » ne peut pas être la version plus loin de E2 : une version remplace l'action
du jour, elle ne la rend pas hebdomadaire. La version plus loin de E2 est « un appel plutôt qu'un message » (2.1) ;
un appel hebdomadaire serait une carte à part (`connection`, `RRULE:FREQ=WEEKLY;BYDAY=SU`), à ne créer que si un care
plan le prescrit.

### 3.8 Doublons et recoupements déjà présents dans la banque

| Famille | Cartes | Proposition |
|---|---|---|
| Lumière du jour | M5 « Five minutes of daylight » (matin) · S6 « Morning light within an hour of waking » (matin) · R2 « Five minutes outside in daylight » (midi) · routine vitrine | Garder **S6** comme carte de référence du matin. Reprendre l'idée de M5 dans la version douce de S6, puis retirer M5 (une carte ne peut pas être la version d'une autre). Garder R2 pour le midi (recharge, pas rythme) |
| Respiration carrée | M2 « Box breathing, 4×4 » · version plus loin de M1 | Changer la version plus loin de M1 (ex. « trois respirations avant chaque repas ») et laisser M2 seule |
| Marches | X1 (après déjeuner) · X5 (soir) · R6 (nature, samedi) | Pas un doublon, mais à ne pas prescrire toutes ensemble au départ. Chacune a son rôle |
| Écriture du soir | E3 · E4 · S5 | Trois tâches d'écriture le soir : n'en prescrire qu'une à la fois |
| Le déjeuner | E5 (avec quelqu'un) · R1 (sans écran) | Compatibles (un déjeuner partagé sans écran coche les deux), mais même créneau |
| Catégorie `boundaries` | E6 (emotion) · R4 (recovery) | Même valeur de catégorie dans deux piliers : sans gravité, à garder en tête |
| Caféine | S2 (pas après 14 h) · item vitrine « Coffee before noon only » | Faire de « avant midi » la version plus loin de S2 |
| Le creux de l'après-midi | N5 (fruit) · collation protéinée vitrine | Reprendre l'idée de N5 dans la version douce de la collation, ou garder deux cartes clairement distinctes |

Le moteur du focus du jour n'écarte que les titres **identiques** (casse et ponctuation ignorées). Deux cartes « lumière
du jour » aux titres différents peuvent donc sortir le même jour. Une raison de plus pour fusionner.

---

## 4. Pistes de structuration

### 4.1 Cartes « fondation » (candidates à `member_can_add = true`)

Ce sont des gestes universels, à faible enjeu et faciles à expliquer seuls, que le membre peut ajouter lui-même. Le
clinicien décide en cochant la case dans l'éditeur. Il faut **compléter la carte (socle) avant** de la cocher, puisque
le membre la lira sans praticien.

- **Emotion** : E1, E2, E3, E4
- **Exercise** : X1, X2, X4, X5, X6
- **Mind** : M1 (une fois sa version plus loin changée : aujourd'hui c'est la respiration carrée avec rétentions, que
  4.2 garde sur prescription), M3, M4, M6
- **Nutrition** : N1, N3, N4, N5
- **Recovery** : R1, R2, R4, R5, R6
- **Sleep** : S3, S4, S5, S6 (et S1 une fois sa fréquence corrigée)
- Parmi les idées nouvelles : même heure de lever, rituel de décompression, chambre fraîche et sombre, équilibre au
  brossage de dents, double soupir, gourde sur le bureau, légumineuses, un nouveau végétal, les 10 premières minutes
  sans écran, savourer un moment, un petit geste gentil, et toutes les cartes `learn`.

Pour démarrer la banque du membre, viser **3 à 5 cartes fondation par pilier**, dont au moins une le matin et une le
soir.

### 4.2 Cartes à garder sur prescription

Elles touchent à une situation que le clinicien doit évaluer (horaires, rapport à l'alimentation, articulations,
respiration, alcool, prise en charge du sommeil) :

- **Existantes** : X3 (pompes), M2 (rétentions de souffle), N2 si des quantités sont précisées, N6 (cuisine fermée),
  R3 (jambes au mur), E6 (dire non : à garder dans un accompagnement).
- **Nouvelles** : séance de renforcement et récupération active, soirs sans alcool, sieste, « se lever plutôt que
  lutter », poisson gras, bain chaud ou sauna, marche rapide 3×/semaine (selon le niveau de départ).

Ce classement est une proposition à valider par le clinicien, carte par carte.

### 4.3 Une carte de référence par idée

Une idée = une carte. Les variantes d'intensité passent par `easy_*` et `rev_*`, pas par une nouvelle carte. Avant de
créer une carte, chercher dans la banque une carte proche dont elle pourrait être la version douce ou plus loin (voir
3.8). C'est ce qui permet au focus du jour d'ajuster l'intensité à la forme du jour. Sur une habitude reliée, la
version proposée d'office vient des versions écrites sur l'habitude ; celles de la carte restent au choix du membre
(1.5).

### 4.4 Trous par moment de la journée

| Pilier | Matin | Midi | Soir | Manque surtout |
|---|---|---|---|---|
| emotion | 0 | 3 | 3 | **matin** |
| exercise | 2 | 3 | 1 | une vraie séance (force, endurance) |
| mind | 3 | 3 | 0 | **soir** |
| nutrition | 2 | 3 | 1 | le soir (préparation, dîner) |
| recovery | 0 | 4 | 2 | **matin** |
| sleep | 1 | 1 | 4 | le **matin** (lever, lumière) |
| **Total** | **8** | **17** | **11** | |

- `midi` regroupe le déjeuner **et** tout l'après-midi (le creux de 15 h–17 h, la collation de 16 h). Il n'existe que
  trois créneaux : `morning`, `midday`, `evening`. Un créneau « après-midi » demanderait un changement de schéma, de
  l'app et du moteur : c'est une décision produit, pas de contenu.
- **Week-end** : les 34 cartes quotidiennes valent aussi le week-end, mais une seule carte est **propre** au week-end,
  R6 (samedi). L'autre carte hebdomadaire, E5, est le mercredi. Les idées nouvelles ajoutent des cartes du week-end
  (sortie longue, préparation du dimanche, demi-journée sans écran, bilan de la semaine). Rappel : la
  `frequency_rule` d'une carte ne sert que quand le membre l'ajoute lui-même ; une habitude prescrite suit sa propre
  règle.

### 4.5 Catégories : réutiliser les valeurs existantes

La catégorie décide quelle carte le moteur choisit pour une priorité (tableau 1.4). Une **nouvelle** valeur de
catégorie n'est préférée par aucune priorité tant que `PRIORITIES` (dans `engine.ts`) n'est pas modifié : c'est du code,
pas du contenu. Il en va de même d'une carte **sans** catégorie, ce qui est le cas de toute carte créée dans l'éditeur :
la catégorie se règle en SQL.

| Pilier | Catégories existantes |
|---|---|
| emotion | `awareness` · `connection` · `gratitude` · `reflection` · `boundaries` |
| exercise | `movement` · `mobility` · `strength` |
| mind | `calm` · `focus` · `reset` |
| nutrition | `hydration` · `food rhythm` · `mindful eating` |
| recovery | `breaks` · `nature` · `rest` · `boundaries` · `tension` |
| sleep | `regularity` · `wind-down` |

### 4.6 Ordre de travail conseillé

1. **Compléter avant de créer.** Les 36 cartes ont besoin du socle. Le socle ne sert que là où un membre **ouvre** la
   carte (une habitude prescrite ou ajoutée depuis « Actions de base ») : commencer donc par les cartes qui couvrent le
   care plan (étape 3) et par les cartes fondation (4.1). Le focus du jour, lui, ne lit que titres, descriptions et
   versions : pour lui, la priorité est d'écrire les **versions douces** des cartes qu'il choisit en premier pour une
   priorité, et qui n'en ont pas : X3 (`prio_train`), M3 (`prio_deep_work`), E2 (`prio_people`), R2 (`prio_outside`),
   R3 (`prio_rest`, aussi la carte de récupération ajoutée un jour de forme basse).
2. **Créer les 3 cartes vitrine manquantes** (routine circadienne, collation protéinée, séance de renforcement) et
   compléter X1.
3. **Couvrir le care plan.** Pour que le lien care plan → carte serve, chaque prescription courante doit avoir sa
   carte. Une habitude pointe vers **une seule carte entière**, pas vers une de ses versions : l'app garde le titre de
   l'habitude (les mots du clinicien) et affiche la description, les étapes et le pourquoi de la carte, en version
   normale par défaut. Une carte n'a donc pas besoin de reprendre l'item mot pour mot, mais ses étapes doivent rester
   justes pour ce qui est prescrit. Quand l'item correspond à la version plus loin d'une carte, soit les étapes de la
   carte couvrent aussi cette variante, soit il faut une carte à part. Exemple avec le care plan vitrine :

   | Item du care plan vitrine | Carte |
   |---|---|
   | Same wake time every day, daylight within 30 minutes | Morning circadian routine (à créer). Une habitude ne porte qu'une carte : sinon deux habitudes, S6 et « Same wake-up time » (à créer) |
   | Screens off 30 minutes before bed, bedroom cool and dark | S3, ou « Cool, dark, quiet bedroom » (à créer) dans une seconde habitude |
   | Protein at every meal, a palm-sized portion | N2, avec des étapes qui couvrent « à chaque repas » (version plus loin à écrire), ou une carte à part |
   | A protein snack mid-afternoon instead of something sweet | Protein snack mid-afternoon (à créer) |
   | Coffee before noon only | S2, avec des étapes qui couvrent « avant midi » (version plus loin à écrire), ou une carte à part |
   | Strength training twice a week | Strength session (à créer) |
   | A 10-minute walk after lunch | X1 (existe, à compléter) |
   | Work in 90-minute blocks with a 5-minute break outside | M4, avec des étapes qui couvrent le bloc de 90 minutes (version plus loin à écrire), ou une carte à part |

4. **Cocher `member_can_add`** sur les cartes fondation une fois complètes et relues.
5. **Corriger S1** (fréquence « en semaine »), en SQL : l'éditeur ne règle pas `frequency_rule`.

### 4.7 Règles d'écriture pour chaque nouvelle carte

- Titre court (120 caractères max), à l'impératif ou nominal, **sans fréquence** (« Strength session », pas « Strength
  session · twice a week ») : la fréquence vit dans `frequency_rule` et dans celle de l'habitude, qui peut différer
  d'un patient à l'autre. Une durée peut faire partie de l'action (« A 10-minute walk after lunch ») ; elle doit alors
  être cohérente avec `duration_min` (minutes entières, 1 au minimum).
- Un titre ne peut pas exister deux fois dans le même pilier (contrainte unique `pillar` + `title`).
- Remplir **EN et FR** pour chaque texte, versions douce et plus loin comprises (titre **et** description). En
  français, vouvoyer le membre, comme les titres existants. Si un seul texte d'une offre manque en français, le focus
  du jour affiche toute l'offre en anglais (`present.ts`) ; la carte, elle, prend l'autre langue champ par champ.
- `how_md` : des étapes concrètes, une par ligne, une action par étape (l'assistant IA de l'éditeur vise 3 à 7 étapes
  numérotées). Texte simple, sans Markdown.
- `general_why` : 2 à 3 phrases simples (800 caractères max), sans chiffre ni promesse de résultat ; **validé par le
  clinicien**.
- Comme l'impose déjà l'assistant IA de l'éditeur : ni diagnostic, ni maladie, ni médicament, ni complément, ni dose
  dans une carte. « Peut vous aider à vous sentir plus calme » passe ; « fait baisser le cortisol » non.
- `resources` : au minimum une recherche YouTube (`{"kind":"youtube","query":"…"}`, une courte phrase en anglais) pour
  les cartes `movement` et `breath`, et un article de la bibliothèque (`{"kind":"article","slug":"…"}`, slug existant
  uniquement : 82 articles dans la bibliothèque de l'app aujourd'hui, dont 11 avec le thème `sommeil`) pour les
  cartes `learn`. Jamais d'URL inventée.
- Pour une offre d'état (`state_responses`) qui correspond à une carte, reprendre **exactement** le titre anglais de la
  carte.
- Une carte créée dans l'éditeur est un brouillon (`active = false`) : rien n'atteint un membre avant la publication
  par un `lead_nutritionist` ou un `super_admin`. En SQL, écrire `active = false` explicitement (1.1).
