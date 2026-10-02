# Guide de rédaction des cartes action FunctionAlps

> **À quoi sert ce document.** C'est le brief complet à donner à un agent IA chargé
> d'écrire la **banque de base des cartes action** (le contenu), et l'explication, pour
> un humain, de ce qu'est une « action ». Il se suffit à lui-même : l'agent qui le lit n'a
> besoin ni du code ni de la base de données.
>
> **État du système décrit :** 2026-10-02, vérifié dans le code et sur la base CM OS
> (lecture seule). Les noms de champs, les valeurs d'énumération et les identifiants de
> code sont laissés **en anglais, à l'identique** : ce sont les mots exacts que la
> base attend.

---

## 0. La mission de l'agent, en dix lignes

1. Tu écris des **cartes action** : chacune est une petite chose concrète qu'un membre fait dans sa journée, dans l'app iPhone FunctionAlps.
2. Tu écris **chaque texte en anglais ET en français** (vouvoiement en français).
3. Tu livres des **fichiers JSON** au format exact de la section 5. Aucune autre forme n'est importée.
4. Tu n'as **aucun accès à la base**. Tu ne publies jamais rien : tes cartes entrent en **brouillon** et une clinicienne responsable les relit, les corrige et les publie.
5. Une carte = **un seul comportement**, faisable en quelques minutes, sans matériel particulier.
6. Tu n'écris **jamais** de diagnostic, de traitement, de complément, de dosage, de régime ni de promesse de résultat. Ces éléments relèvent du care plan de chaque patient, pas des cartes.
7. Tu n'inventes **aucun lien**. L'article se choisit seulement dans le catalogue de l'annexe C. Pour la vidéo, tu ne donnes qu'un mot-clé de recherche YouTube.
8. Toute justification santé est une **proposition** : tu la signales dans `_note_clinicien`, et la clinicienne la valide.
9. Tu commences par **enrichir les 36 cartes existantes** (annexe A, lot A), puis tu en crées de nouvelles (annexe B, lot B).
10. Avant de livrer, tu passes la **checklist de la section 6**, carte par carte.

---

## 1. Qu'est-ce qu'une carte action ?

### 1.1 Définition

Une **carte action** est la fiche que le membre ouvre quand il touche une action dans
l'app. Elle dit :

- **ce qu'il faut faire** : le titre et une phrase de description ;
- **comment le faire** : les étapes du bloc « Comment faire » ;
- **en plus doux ou en plus loin** : la version « Douce » pour un jour sans énergie, « Plus loin » pour un bon jour ;
- **pourquoi** cette action est là : le bloc « Pourquoi dans votre plan » ;
- **où en voir ou en lire davantage** : une vidéo, une recherche YouTube, un article de la bibliothèque.

Techniquement, une carte **est une ligne de la table `habit_bank`**, la banque d'habitudes
du cabinet. C'est un **contenu partagé** : une seule carte peut être ouverte par des
centaines de membres. Le membre la lit **en direct**, donc une correction publiée par le
cabinet arrive aussitôt chez tous ceux qui l'ont.

### 1.2 Où la carte apparaît dans l'app iPhone

| Surface (libellé FR dans l'app) | Quand | Ce que la carte y apporte |
|---|---|---|
| **Accueil → « Actions du jour »** | L'action du membre est prévue aujourd'hui | Sous le titre de l'action, une ligne méta « *Type · N min* », par exemple « Respiration · 5 min ». Toucher la ligne ouvre la carte. |
| **Carte détaillée** (ouverte depuis « Actions du jour », « Mon plan de soins » ou « Actions de base ») | Toujours | Tout le contenu, dans cet ordre : image (facultative), ligne méta en capitales « TYPE · MOMENT · N MIN », titre, description, cercle de respiration (cartes `breath` uniquement), sélecteur « Aujourd'hui, la version : Douce / Normale / Plus loin », bloc vidéo et lien « Chercher « … » sur YouTube ↗ », « Comment faire » (étapes numérotées), « Pourquoi dans votre plan », « À lire dans la bibliothèque », puis les boutons « C'est fait » / « Pas aujourd'hui » quand l'action est prévue ce jour-là (ou « Ajouter à mon plan » depuis la banque). |
| **« Actions de base »** (la banque, ouverte depuis « Mon plan de soins → Ajouter une action de base », ou par « Choisir une action » tant que le plan du membre n'a aucune action) | La carte est publiée **et** `member_can_add = true` | Regroupement par pilier, dans l'ordre alphabétique des valeurs de `pillar` (Émotions, Mouvement, Esprit, Nutrition, Récupération, Sommeil), puis par `sort_order`. Pour chaque carte : son icône de type, son titre et « Type · N min ». Le membre lit la carte puis « Ajouter à mon plan » au moment de son choix ; le moment suggéré par la carte est proposé en premier. |
| **« Mon plan de soins » → « Mes actions »** (la page plan de santé du membre) | Les actions actives du membre, groupées par moment | L'icône du type et « Type · N min » sous chaque action. |
| **Focus du jour** (moteur `member-daily-focus`) | Toute carte **publiée**, même si `member_can_add = false` | Le titre et la description, ou ceux de la version douce ou plus loin selon la forme du jour, le pilier, le moment, la catégorie. Voir 1.5. |

Les deux langues : l'app affiche le français aux membres francophones. **Si un champ
français est vide, elle affiche l'anglais** (et inversement). Un oubli de traduction se
voit donc tout de suite chez le membre.

### 1.3 La carte et la prescription, deux choses différentes

| | **La carte** (`habit_bank`) | **La prescription** (`habits`, une ligne par action d'un membre) |
|---|---|---|
| Qui l'écrit | Le cabinet, une fois pour tous | La clinicienne pour un patient, ou le membre lui-même depuis la banque |
| Ce qu'elle contient | Titre, description, versions, étapes, pourquoi, liens, image, type, durée | Le titre pour CE patient, la fréquence (`frequency_rule`), le moment (`slot`), le statut, l'origine (`source`) et le lien vers la carte (`habit_bank_id`) |
| Ce que voit le membre | Tout le contenu de la carte | Le **titre de la prescription** (les mots de la clinicienne passent en premier), son moment et sa fréquence |
| Durée de vie | Publiée, puis éventuellement retirée | Active, en pause ou terminée selon le plan du patient |

En clair : **la carte dit quoi, comment et pourquoi ; la prescription dit pour qui,
quand et à quelle fréquence.** Donc une carte ne contient jamais rien de personnel :
pas de « 3 fois par semaine parce que vos analyses… », pas de prénom, pas de
situation clinique.

### 1.4 Le lien avec le care plan

Le care plan d'un patient (`care_plans` → `care_plan_items`) contient des éléments de
plusieurs types (`item_kind`) : `habit`, `supplement_plan`, `reminder`,
`meal_protocol`, `info_only`, `curriculum`. **Seuls les éléments de type `habit`
deviennent des actions dans l'app.**

- **Depuis le 2026-10-02.** Un élément de care plan de type `habit` **pointe vers une carte**
  (`care_plan_items.habit_bank_id`). La clinicienne la choisit dans l'éditeur de l'élément
  (onglet Plan du patient), ou l'IA la propose depuis la liste des cartes publiées. Si aucune
  carte ne convient, elle peut **créer une carte en brouillon à partir de l'élément**, qu'une
  responsable relit et publie.
- **Au push** vers l'app, la ligne `habits` du patient reçoit `habit_bank_id`, le moment
  (`default_slot` de la carte), la fréquence (celle de l'élément, sinon celle de la carte), les
  versions douce et plus loin de la carte, et le titre de la carte dans la langue du patient
  quand la clinicienne n'en a pas écrit un autre. Le patient voit alors la carte complète.
- Une carte **non publiée** n'est jamais envoyée : l'action part avec ses propres mots, et la
  carte apparaît d'elle-même dès qu'une responsable la publie.

Conséquence pour l'auteur : **chaque carte doit pouvoir être prescrite telle quelle à des
patients très différents.** Ce qui est propre à un patient (fréquence, durée du suivi,
raison individuelle, dosage) reste dans l'élément du care plan, jamais dans la carte.

Correspondance **indicative** entre les domaines du care plan (`care_plan_domain`) et les
piliers des cartes :

| Domaine du care plan | Pilier de carte le plus proche | Remarque |
|---|---|---|
| `nutrition`, `meal_timing`, `hydration` | `nutrition` (parfois `sleep` pour les horaires du soir) | Comportements alimentaires simples |
| `elimination_diet`, `digestive_support` | aucun en banque de base | Relève d'un protocole individuel (`meal_protocol`) |
| `exercise` | `exercise` | |
| `sleep` | `sleep` | |
| `stress_regulation` | `mind`, `emotion`, `recovery` | |
| `behavior_change`, `education` | n'importe quel pilier, souvent `card_kind = learn` ou `routine` | |
| `supplementation`, `symptom_monitoring`, `biomarker_follow_up`, `referral` | **aucun** | Jamais une carte action |

### 1.5 Le focus du jour : chaque carte publiée peut être proposée à tout le monde

Chaque matin, le moteur `member-daily-focus` choisit **jusqu'à 3** actions à mettre en
avant pour chaque membre. La première vient souvent des réponses que le cabinet a
écrites pour l'état du matin (`state_responses`, pas des cartes). Les suivantes sont
piochées dans **toutes les cartes publiées** (`active = true`), une par priorité que le
membre a choisie ce matin-là (plus une carte de récupération quand une priorité exigeante
tombe un jour de faible forme). Il utilise le pilier, la `category`, le titre et la
description, les versions douce et plus loin, `default_slot` et `sort_order`.

| Priorité du matin (clé) | Pilier | Catégories préférées, dans l'ordre |
|---|---|---|
| `prio_train` | `exercise` | `strength`, `movement` |
| `prio_move` | `exercise` | `mobility`, `movement` |
| `prio_eat_well` | `nutrition` | `food rhythm`, `hydration`, `mindful eating` |
| `prio_deep_work` | `mind` | `focus`, `reset` |
| `prio_rest` | `recovery` | `rest`, `breaks`, `tension` |
| `prio_people` | `emotion` | `connection` |
| `prio_outside` | `recovery` | `nature` |
| `prio_early_night` | `sleep` | `wind-down`, `regularity` |

À catégorie égale, un jour de faible forme, le moteur préfère une carte qui **a** une
version douce. Un très bon jour, il préfère une carte qui **a** une version plus loin.

> **Conséquence importante.** Le moteur ne regarde pas `member_can_add`. Toute carte
> publiée peut donc être proposée à **n'importe quel membre**, sans prescription. Une
> carte de la banque doit être **sans risque pour un adulte tout-venant**. Une action qui
> demande une évaluation individuelle (voir 3.5 et 3.6) n'est **pas** une carte de base.
> Signale-la dans `_note_clinicien` : c'est le cabinet qui décidera comment la réserver
> aux patients concernés.

### 1.6 Ce qu'une carte n'est pas

- un **rappel** : les rappels sont des éléments `reminder` du care plan ;
- un **protocole ou un plan de repas** : ce sont des éléments `meal_protocol` ;
- un **complément ou un médicament** : ce sont des éléments `supplement_plan` ;
- un **article** : l'article vit dans la bibliothèque, et la carte peut y renvoyer ;
- un **programme d'entraînement** : une carte est un geste, pas un plan sur plusieurs semaines.

---

## 2. Anatomie d'une carte

### 2.1 Tableau champ par champ

Limites exactes : le schéma Zod de l'éditeur (`lib/action-cards/schemas.ts`) et les
contraintes de la base. **Livraison** désigne ce qui est obligatoire dans tes fichiers
JSON, ce qui va plus loin que le minimum technique.

| Colonne `habit_bank` | Libellé dans l'éditeur CLINICAL | Obligatoire | Format / limite exacte | Où ça s'affiche | Exemple |
|---|---|---|---|---|---|
| `pillar` | Pillar | **Oui** (NOT NULL) | Une des valeurs : `nutrition` `exercise` `mind` `emotion` `recovery` `sleep` | Groupe de la banque (Nutrition, Mouvement, Esprit, Émotions, Récupération, Sommeil) ; choix du focus du jour | `sleep` |
| `category` | *(absent de l'éditeur, fixé à l'import)* | Livraison : oui | Texte en minuscules, vocabulaire de 2.3 | Invisible pour le membre ; sert au focus du jour | `regularity` |
| `card_kind` | Card type | **Oui pour publier** | Une des valeurs : `breath` `movement` `routine` `nutrition` `mind` `learn` | Icône et libellé du type dans toutes les listes et la ligne méta ; `breath` ajoute le cercle de respiration | `routine` |
| `duration_min` | Duration (min) | Livraison : oui, sauf action non chronométrée (`null`) | Entier de **1 à 240** | « 10 min » dans la ligne méta (Accueil, plan, banque, carte) ; durée du minuteur du cercle pour `breath` (3 min si vide) | `10` |
| `default_slot` | Moment | Facultatif | `morning`, `midday`, `evening` ou `null` (= « N'importe quand ») | Ligne méta d'une carte ouverte depuis la banque ; moment proposé en premier par « Ajouter à mon plan » ; moment du focus du jour | `morning` |
| `frequency_rule` | *(absent de l'éditeur, fixé à l'import)* | Livraison : oui | RRULE, voir 2.4 | Copiée dans l'action du membre qui ajoute la carte depuis la banque ; `null` donne « tous les jours » | `RRULE:FREQ=DAILY` |
| `title` | Title · EN | **Oui** (NOT NULL) | 1 à **120** caractères. **Unique dans le pilier** (contrainte `UNIQUE (pillar, title)`) | Titre en anglais partout | `Morning light within an hour of waking` |
| `title_fr` | Title · FR | Livraison : oui | ≤ **120** | Titre en français partout | `Lumière du matin dans l’heure qui suit le réveil` |
| `description`, `description_fr` | Short description · EN / FR | **Au moins une langue pour publier** ; livraison : les deux | ≤ **400** chacune | Sous le titre de la carte ; texte du focus du jour ; description de l'action créée depuis la banque | Voir 5.3 |
| `easy_title`, `easy_title_fr` | Gentle — title | Facultatif, mais **les 4 champs « easy » vont ensemble** | ≤ **120** | Bouton « Douce » ; titre affiché quand la version douce est choisie | `Five minutes by an open window` |
| `easy_description`, `easy_description_fr` | Gentle — description | Obligatoires si `easy_title` est rempli | ≤ **400** | Description sous le titre doux. Sans elle, la description normale s'affiche sous le titre doux, ce qui ne colle pas | |
| `rev_title`, `rev_title_fr` | Further — title | Facultatif, **les 4 champs « rev » vont ensemble** | ≤ **120** | Bouton « Plus loin » | `A 20-minute morning walk outside` |
| `rev_description`, `rev_description_fr` | Further — description | Obligatoires si `rev_title` est rempli | ≤ **400** | | |
| `how_md`, `how_md_fr` | Steps — one per line · EN / FR | **Au moins une étape pour publier** ; livraison : 3 à 7 étapes dans chaque langue | ≤ **2000** chacun ; **une étape par ligne** (voir 2.6) | Bloc « Comment faire », étapes numérotées par l'app | Voir 5.3 |
| `general_why`, `general_why_fr` | Why it is in the plan · EN / FR | Livraison : oui | ≤ **800** chacun | Bloc « Pourquoi dans votre plan » | Voir 5.3 |
| `resources` | Video link + Video title, YouTube search keyword, Library article | Facultatif (liste vide `[]` par défaut) | Liste JSON typée, voir 2.7 | Bloc vidéo, lien YouTube, carte « À lire dans la bibliothèque » | Voir 2.7 |
| `image_url` | Image URL / Upload | **Jamais rempli par l'agent** (`null`) | `https://` seulement ; image téléversée JPEG/PNG/WebP, redimensionnée à 1600 px au plus, 1,9 Mo au plus | Bandeau de 170 pt en haut de la carte | `null` |
| `image_alt` | Image description (VoiceOver) | `null` dans la livraison (l'idée d'image va dans `_note_clinicien`) | ≤ **200** | Lu par VoiceOver | `null` |
| `member_can_add` | Members can add it themselves | Oui (booléen, `false` par défaut) | `true` / `false` | `true` : la carte apparaît dans « Actions de base » | `true` |
| `sort_order` | *(absent de l'éditeur, fixé à l'import)* | Livraison : oui | Entier ≥ 0 ; ordre dans le pilier | Ordre dans la banque et dans CLINICAL ; départage du focus du jour | `7` |
| `active`, `published_at`, `published_by` | Publish / Retire | **Jamais par l'agent** | Fixés par l'import (brouillon) puis par la responsable qui publie | Voir 2.10 | absent |
| `id`, `created_by`, `created_at`, `updated_at` | — | **Jamais par l'agent** | Fixés par la base | — | absent |

### 2.2 Valeurs fermées

**`pillar`** : six valeurs, imposées par une contrainte CHECK.

| Valeur | Libellé dans l'app (EN / FR) |
|---|---|
| `nutrition` | Nutrition / Nutrition |
| `exercise` | Movement / Mouvement |
| `mind` | Mind / Esprit |
| `emotion` | Emotions / Émotions |
| `recovery` | Recovery / Récupération |
| `sleep` | Sleep / Sommeil |

**`card_kind`** décide de la page que l'app ouvre et de l'icône. Il est **indépendant du
pilier** : une carte `sleep` peut être une `routine`, une carte `mind` peut être une
`breath`.

| Valeur | Libellé EN / FR | Icône (SF Symbol) | Pour quoi | Ce que l'app ajoute |
|---|---|---|---|---|
| `breath` | Breathwork / Respiration | `wind` | Un exercice de respiration guidé | Le **cercle de respiration** avec « Commencer · N min ». Le minuteur dure `duration_min` (3 min par défaut). Le cercle gonfle en 5 s et se resserre en 5 s (l'aperçu CLINICAL l'anime un peu plus vite, 4 s / 4 s) et il n'annonce aucun rythme (avant le départ, seulement « Suivez les étapes avec le cercle ») : **le rythme doit être écrit dans les étapes.** Si ce rythme n'est pas 5 s / 5 s (respiration carrée, expiration plus longue…), les étapes disent de suivre son propre compte plutôt que le cercle. |
| `movement` | Movement / Mouvement | `figure.walk` | Un mouvement du corps : marche, mobilité, renforcement, étirement | Rien de plus, mais une démonstration (YouTube) est fortement recommandée |
| `routine` | Routine / Routine | `checklist` | Un geste du quotidien, une règle d'environnement ou d'horaire, une petite séquence | — |
| `nutrition` | Nutrition / Nutrition | `fork.knife` | Un geste alimentaire ou d'hydratation | — |
| `mind` | Mind / Esprit | `brain.head.profile` | Attention, écriture, concentration, observation de soi, sans technique de respiration | — |
| `learn` | Learn / Comprendre | `book` | Comprendre un sujet : la carte mène à un article de la bibliothèque | — (l'article est l'essentiel : il doit être présent) |

**`default_slot`** : `morning` (Matin), `midday` (Midi), `evening` (Soir), ou `null`
(« N'importe quand »). C'est une **suggestion** : pour une action prescrite, c'est le
moment fixé par la clinicienne qui s'affiche.

### 2.3 `category` : le vocabulaire existant

`category` est invisible pour le membre mais **fonctionnelle** : le focus du jour
l'utilise (tableau de 1.5). **Réutilise ces valeurs, à l'identique** (minuscules,
espaces et traits d'union compris) :

| Pilier | Catégories en usage |
|---|---|
| `nutrition` | `hydration`, `food rhythm`, `mindful eating` |
| `exercise` | `movement`, `mobility`, `strength` |
| `mind` | `calm`, `focus`, `reset` |
| `emotion` | `awareness`, `connection`, `gratitude`, `reflection`, `boundaries` |
| `recovery` | `breaks`, `nature`, `rest`, `boundaries`, `tension` |
| `sleep` | `regularity`, `wind-down` |

Attention : seules les catégories du tableau de 1.5 sont **préférées** par le focus du
jour. Une carte classée `calm`, `awareness`, `gratitude`, `reflection` ou `boundaries`
reste choisissable, mais seulement quand il ne reste rien de mieux dans son pilier.

Une nouvelle catégorie est possible (en minuscules, en anglais), mais **le focus du jour
ne la préfère jamais**. Justifie-la dans `_note_clinicien`.

### 2.4 `frequency_rule` : le format RRULE accepté

C'est le rythme **suggéré**. Il est copié tel quel quand un membre ajoute la carte depuis
la banque. Pour une action prescrite, c'est la fréquence de la clinicienne qui s'applique.

L'app ne comprend que ce sous-ensemble : `FREQ=DAILY` ou `FREQ=WEEKLY`, `INTERVAL=n`,
`BYDAY=MO,TU,WE,TH,FR,SA,SU`. Écris toujours le préfixe `RRULE:`, comme les cartes
existantes, et les parties dans l'ordre `FREQ`, puis `INTERVAL`, puis `BYDAY`.

| Intention | `frequency_rule` |
|---|---|
| Tous les jours | `RRULE:FREQ=DAILY` |
| Un jour sur deux | `RRULE:FREQ=DAILY;INTERVAL=2` |
| 2 fois par semaine (mardi et vendredi) | `RRULE:FREQ=WEEKLY;BYDAY=TU,FR` |
| 3 fois par semaine | `RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR` |
| Les jours de semaine | `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` |
| Une fois par semaine (samedi) | `RRULE:FREQ=WEEKLY;BYDAY=SA` |
| Une semaine sur deux (dimanche) | `RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SU` |

Pièges :

- « 2 fois par semaine, n'importe quels jours » n'existe pas. **Fixe les jours** avec `BYDAY`.
- Une fréquence que l'app ne connaît pas (`MONTHLY`, `YEARLY`…) rend l'action **due tous les jours**. `COUNT`, `UNTIL`, `BYMONTHDAY` et `BYHOUR` sont ignorés.
- `WEEKLY` sans `BYDAY` tombe le jour de la semaine où l'action a été ajoutée. Mets toujours `BYDAY`.
- « Une seule fois » n'existe pas : une action revient toujours. Pour une carte `learn`, choisis un rythme hebdomadaire.

### 2.5 Les versions « Douce » et « Plus loin »

- **Douce** (`easy_*`) : **le même comportement, en plus petit ou en plus facile.** Moins de minutes, moins de répétitions, assis plutôt que debout, à la fenêtre plutôt que dehors. Elle sert les jours de faible forme et elle déculpabilise : *« Half the walk, all the credit. » / « La moitié de la marche, tout le mérite. »*
- **Plus loin** (`rev_*`) : **le même comportement, une marche au-dessus.** Plus de temps, une deuxième série, une variante un peu plus exigeante. Ce n'est jamais un autre exercice ni un effort maximal.
- Dans l'app, le sélecteur affiche « Douce · Normale · Plus loin », seulement pour les versions qui existent. Le focus du jour propose de lui-même la version douce les jours de faible forme et la version plus loin les très bons jours. Le membre peut toujours changer à la main sur la carte.
- Pour une action du plan, la version **présélectionnée** (sur l'Accueil et à l'ouverture de la carte) dépend des versions écrites dans l'action du membre (la ligne `habits`), pas de celles de la carte. Une action poussée par le care plan ou ajoutée depuis la banque n'en a pas aujourd'hui : elle s'ouvre donc sur « Normale », et les versions de la carte restent au choix du membre.
- **Les étapes (`how_md`) sont communes aux trois versions.** Elles décrivent la version normale. La description de chaque version dit **ce qui change** : *« Same steps, five minutes only. » / « Mêmes étapes, cinq minutes seulement. »*
- Chaque version a **ses 4 champs** (titre et description, en anglais et en français), ou aucun.
- Écris les deux versions dès que le geste peut se doser. Le focus du jour choisit plus souvent les cartes qui en ont.

### 2.6 `how_md` : les étapes

- **Une étape par ligne**, au format `1. …`, de 3 à 7 étapes. Les sauts de ligne s'écrivent `\n` dans le JSON.
- L'app (comme l'aperçu CLINICAL, fonction `cardSteps`) **enlève** les marqueurs en début de ligne (`1.`, `1)`, `-`, `*`, `•` suivis d'un espace), **ignore** les lignes vides et **renumérote** elle-même.
- **Pas de markdown** malgré le nom du champ : `**gras**`, `_italique_`, les liens et les titres s'afficheraient tels quels, astérisques comprises.
- Une étape ne peut pas tenir sur deux lignes : chaque ligne devient une étape.
- Chaque étape est **une action, une phrase complète**, lisible seule. VoiceOver la lit sous la forme « Étape 2 : … ».

### 2.7 `resources` : les liens typés

C'est une liste JSON. L'app retient **une ressource de chaque sorte, au plus** (la
première vidéo, la première recherche YouTube, le premier article). Mets-les dans cet
ordre : vidéo, puis YouTube, puis article.

```json
[
  { "kind": "video",   "url": "https://…", "title": "Titre affiché sur la vignette" },
  { "kind": "youtube", "query": "box breathing 4 4 4 4" },
  { "kind": "article", "slug": "breathing-exercises", "title": "Breathing Exercises" }
]
```

| Sorte | Forme exacte | Règle pour l'agent | Rendu dans l'app |
|---|---|---|---|
| `video` | `{"kind":"video","url":"https://…","title":"…" ou null}` ; l'URL commence par `https://` (500 caractères au plus) et le titre fait 120 caractères au plus | **Interdit à l'agent**, sauf URL fournie explicitement par le cabinet. Une vidéo doit appartenir au cabinet ou avoir été validée par lui | Vignette sombre avec ▶ et le titre (« Regarder la démonstration » par défaut) |
| `youtube` | `{"kind":"youtube","query":"…"}` ; de 1 à **100** caractères | **Un mot-clé de recherche**, jamais une URL. 3 à 6 mots qui trouvent une **démonstration** du geste. Par convention (le brouillon IA de CLINICAL fait pareil), la recherche est **en anglais**, parce qu'elle trouve plus de démonstrations. Une recherche en français est acceptable quand le sujet a de bonnes vidéos francophones | Lien « Chercher « *query* » sur YouTube ↗ ». La recherche s'affiche **telle quelle**, même dans l'app en français : elle doit se lire naturellement |
| `article` | `{"kind":"article","slug":"…","title":"…"}` ; slug de 200 caractères au plus | **Seulement un slug du catalogue** (annexe C). Le titre se recopie à l'identique. Un slug inconnu est **refusé à l'enregistrement** (« That library article no longer exists ») | Carte « À lire dans la bibliothèque » + titre. Toucher ouvre l'article dans l'app |

Quand mettre quoi :

- `movement` et `breath` : une recherche YouTube presque toujours ;
- `learn` : un article toujours ;
- les autres types : un article seulement s'il approfondit **vraiment** le geste. Pas de lien plutôt qu'un lien approximatif.

### 2.8 Image

`image_url` et `image_alt` sont **toujours `null`** dans ta livraison. Le cabinet
téléverse l'image dans l'éditeur. Tu peux proposer une idée d'image dans `_note_clinicien`,
par exemple : *« un balcon au lever du jour, une tasse à la main ; pas de visage
reconnaissable »*. Quand l'image sera posée, `image_alt` la décrira en une phrase pour
VoiceOver.

### 2.9 `member_can_add` : la banque de base

`true` veut dire que **n'importe quel membre peut ajouter cette action à son plan, sans
prescription**, depuis « Actions de base ». Mets `true` seulement si l'action est :

- sans risque pour un adulte tout-venant, sans évaluation individuelle ;
- utile à presque tout le monde ;
- compréhensible sans l'explication d'une clinicienne.

Sinon `false`, avec la raison dans `_note_clinicien`. La décision finale revient à la
responsable qui publie. Pour rappel (1.5), une carte publiée peut **de toute façon** être
proposée par le focus du jour, même avec `false`.

### 2.10 Cycle de vie : brouillon, publiée, retirée

| État | Colonnes | Qui la voit |
|---|---|---|
| **Brouillon** | `active = false`, `published_at = null` | Les cliniciennes, dans CLINICAL seulement. Invisible pour les membres et pour le focus du jour |
| **Publiée** | `active = true`, `published_at` rempli, `published_by` = la responsable | Les membres dont une action pointe vers elle (en direct), la banque si `member_can_add`, le focus du jour, le sélecteur de carte de CLINICAL |
| **Retirée** | `active = false`, `published_at` rempli | Aucun membre, ni la banque, ni le focus du jour. Reste visible dans CLINICAL pour l'historique et peut être republiée. Les actions de patients qui pointaient vers elle ne montrent plus que leurs propres mots |

- Créer et modifier un brouillon : permission `resources.write` (rôles `nutritionist`, `lead_nutritionist`, `super_admin`).
- Publier, retirer ou **modifier une carte publiée** : permission `resources.approve` (rôles `lead_nutritionist` et `super_admin` seulement ; le rôle `admin` ne l'a pas). Une modification d'une carte publiée arrive **immédiatement chez tous les patients** qui l'ont.
- La publication est bloquée tant qu'il manque un titre, un type (`card_kind`), une description (EN ou FR) ou au moins une étape (EN ou FR). C'est la fonction `publishBlockers`.

---

## 3. Règles de rédaction

### 3.1 Voix et ton, tirés des 36 cartes existantes

Les 36 cartes en ligne ont une voix nette. Garde-la.

- **Court, chaleureux, concret.** *« A closing time beats willpower. » / « Une heure de fermeture vaut mieux que la volonté. »*
- **Deuxième personne.** « you » en anglais, **« vous »** en français, jamais « tu » sur les cartes.
- **Des chiffres concrets dans le titre** quand c'est possible : *« Ten sit-to-stands »*, *« A 10-minute walk after lunch »*, *« Box breathing, 4×4 »*, *« Cuisine fermée après 21 h »*.
- **Zéro culpabilité, de la permission.** *« Small still counts. » / « Petit, ça compte aussi. »* ; *« Short is fine — out the door is the win. » / « Court, c'est très bien — passer la porte, c'est déjà gagné. »*
- **Pas de jargon.** On dit « l'horloge interne », pas « le rythme circadien » ; « le coup de barre », pas « l'hypoglycémie réactionnelle ».
- **Une image simple plutôt qu'une explication** : *« Give the mind a runway. » / « Offrez à l'esprit une piste d'atterrissage. »*
- **Le geste, pas le résultat** : on décrit ce que la personne fait, pas ce qu'elle va obtenir.
- Le français n'est **pas une traduction mot à mot**. Il doit sonner naturel pour un lecteur suisse romand. Exemple : *« Moves lunch along and clears the afternoon slump »* devient *« Aide la digestion et chasse le coup de barre de l'après-midi »*.
- L'app parle du cabinet comme de « votre cabinet ». Ne parle pas de « votre praticienne » ou de « votre médecin » dans une carte.
- **Ce qu'il ne faut pas imiter.** Quelques descriptions en ligne promettent un effet santé ou l'affirment comme un fait : *« Movement after dinner — the strongest gentle lever on sleep »* (Evening walk), *« Steadier energy before 11:00 »* (Protein at breakfast), *« Tells the body "we're safe" — meals land better »* (Three slow breaths before meals), *« Light anchors the body clock »* (Five minutes of daylight). Ne reprends pas ce registre dans tes textes. Dans le lot A, signale ces phrases dans `_note_clinicien` et propose une formulation plus prudente (voir 3.4 et 3.5).

### 3.2 Longueurs recommandées

| Champ | Maximum technique | Cible | Observé dans les 36 cartes |
|---|---|---|---|
| `title` / `title_fr` | 120 | 15 à 45 caractères, 2 à 7 mots. Il s'affiche en grand (26 pt) sur la carte, et sur **2 lignes au plus** sur l'Accueil et dans « Mes actions » | 12 à 39 en anglais, 14 à 52 en français |
| `description` / `_fr` | 400 | **Une phrase**, 30 à 100 caractères. Elle doit tenir seule dans le focus du jour, sans les étapes | 23 à 63 en anglais |
| `easy_title`, `rev_title` | 120 | 15 à 45 | |
| `easy_description`, `rev_description` | 400 | Une phrase courte qui dit ce qui change | |
| `how_md` / `_fr` | 2000 | 3 à 7 étapes, 140 caractères au plus chacune | (vide aujourd'hui) |
| `general_why` / `_fr` | 800 | 2 à 3 phrases, 200 à 450 caractères | (vide aujourd'hui) |
| `query` YouTube | 100 | 3 à 6 mots | |

### 3.3 Une action = un comportement

- **Un seul geste observable**, qu'on peut cocher « C'est fait » sans hésiter. *« Bien dormir »* n'est pas une action. *« Écrans éteints 30 minutes avant le coucher »* en est une.
- **Faisable en N minutes**, sans matériel spécial, chez soi, au bureau ou dehors. La durée (`duration_min`) est réaliste pour quelqu'un qui débute.
- **Ancrée dans la journée** quand c'est possible : *« avant le café »*, *« après le déjeuner »*, *« en vous brossant les dents »*.
- **Pas de doublon d'idée.** Le focus du jour n'écarte que les titres identiques (à la casse et à la ponctuation près). Trois cartes existantes parlent déjà de lumière du jour (« Five minutes of daylight », « Five minutes outside in daylight », « Morning light within an hour of waking ») : une nouvelle carte doit avoir **un angle clairement différent**, ou ne pas exister.

### 3.4 Le « pourquoi » (`general_why`)

- Il s'affiche sous le titre « **Pourquoi dans votre plan** ». Il doit donc se lire comme une raison d'agir, **valable pour tout le monde**.
- 2 à 3 phrases : **le mécanisme en mots simples**, puis éventuellement ce que le geste rend plus facile. Formule *« can help » / « peut aider »*, jamais *« fait baisser »*, *« guérit »* ou *« prouvé »*.
- Pas de chiffre d'efficacité, pas d'étude citée, pas de promesse de résultat.
- La consigne du brouillon IA de CLINICAL vaut aussi pour toi : *« "May help you feel calmer" is fine; "lowers cortisol" is not. »*
- **Chaque pourquoi est une proposition** : liste dans `_note_clinicien` les affirmations santé que la clinicienne doit valider.

### 3.5 Interdits : ce qui relève du care plan, pas d'une carte de base

- Diagnostic, nom de maladie ou de symptôme comme cible (*« pour votre SII »*, *« contre l'insomnie »*, *« si vous êtes prédiabétique »*).
- Traitement, médicament, **complément alimentaire**, plante à visée thérapeutique, **dosage** (mg, gélules, UI).
- Régime d'éviction, jeûne, restriction calorique, calories ou grammes de macronutriments chiffrés pour la personne.
- Interprétation d'analyses, de scores ou de mesures de montre connectée.
- Promesse de résultat (*« perdez 2 kg »*, *« réduit l'inflammation »*) ou affirmation présentée comme un fait médical.
- Jargon physiologique dans le texte du membre (cortisol, glycémie, HRV, mélatonine…). Un article de la bibliothèque peut l'expliquer ; la carte, non.
- Culpabilisation, injonction, comparaison sociale, poids, apparence (*« vous devez »*, *« ne craquez pas »*, *« rattrapez »*).
- Contenu de crise ou de soin psychologique (traumatisme, deuil, idées noires) : jamais dans une carte.
- Marques, produits, applications tierces.
- **Toute donnée de patient** : pas d'exemple tiré d'un dossier, pas de prénom, pas de situation réelle.
- Tout lien inventé (voir 2.7).

### 3.6 Sécurité : mouvement et respiration

Les formulations ci-dessous sont des **propositions à faire valider par la clinicienne** :

- **Cartes `movement`** :
  - décris la position de départ, le geste, le nombre de répétitions ou la durée, et la respiration (« sans bloquer le souffle ») ;
  - la version douce propose un appui (chaise, mur) ou une amplitude réduite ;
  - pas de charge, pas de saut, pas d'effort maximal dans une carte de base ;
  - dernière étape proposée : *« If a movement hurts, stop it. » / « Si un mouvement fait mal, arrêtez-le. »* ;
  - pour l'équilibre : *« près d'un appui »*.
- **Cartes `breath`** :
  - écris le rythme en secondes dans les étapes ;
  - respiration douce par le nez, sans forcer ;
  - pas de rétention longue ni d'hyperventilation volontaire dans une carte de base ;
  - étape proposée : *« If you feel light-headed, go back to normal breathing. » / « Si la tête vous tourne, reprenez une respiration normale. »*.
- **Pas de carte de base** (`member_can_add = false`, à signaler) pour : intervalles intenses, zones cardio élevées, entraînement excentrique lourd, exposition au froid, jeûne, sieste longue, techniques de prise en charge de l'insomnie (par exemple « se lever si l'on ne dort pas »). Ces actions supposent une évaluation individuelle.

### 3.7 Accessibilité

- Chaque étape est une **phrase complète**, compréhensible quand VoiceOver la lit seule (« Étape 3 : … »).
- **Pas d'emoji**, pas de flèches ni de symboles à la place des mots (→, ✓, ↗), **pas de MAJUSCULES** (l'app met déjà la ligne méta en capitales), pas de markdown.
- Rien ne doit passer **seulement par l'image ou la couleur** : l'image décore, le texte dit tout.
- Textes courts. Les membres agrandissent souvent la taille du texte (Dynamic Type), et un titre court reste lisible.
- Langage simple : des phrases de 20 mots au plus, pas d'abréviations (sauf « min »).

### 3.8 Conventions EN / FR

| | Anglais | Français |
|---|---|---|
| Personne | you | vous |
| Orthographe | britannique (*« lifts »*, *« colour »*), comme les cartes existantes | standard, adaptée à la Suisse romande |
| Heures | `21:00`, `14:00` | `21 h`, `14 h` |
| Petits nombres dans un titre | en toutes lettres (*« Ten sit-to-stands »*, *« Five minutes »*) | en toutes lettres (*« Dix assis-debout »*, *« cinq minutes »*) |
| Durées dans les étapes | chiffres (*« 10 minutes »*) | chiffres (*« 10 minutes »*) |
| Ponctuation | tiret cadratin espacé « — » pour une respiration de phrase ; signe « × » (*« 4×4 »*) | apostrophe typographique `’`, guillemets « … », tiret cadratin espacé « — » |

---

## 4. Les six piliers et ce qu'on attend dans chacun

| Pilier (`pillar`) | Libellé FR | Ce qu'on y met | Catégories | Hors banque de base (care plan / prescription) |
|---|---|---|---|---|
| `nutrition` | Nutrition | Comment, quand et à quel rythme on mange et on boit ; des ajouts simples (légumes, eau, protéines à un repas) ; un environnement qui rend le bon choix facile | `hydration`, `food rhythm`, `mindful eating` | Régimes, évictions, jeûne, quantités individuelles, compléments, plans de repas |
| `exercise` | Mouvement | Bouger dans la journée, la mobilité, le renforcement au poids du corps, la marche | `movement`, `mobility`, `strength` | Programmes d'entraînement, intervalles intenses, zones cardio élevées, rééducation |
| `mind` | Esprit | L'attention et la concentration, le calme, la respiration, les micro-pauses | `calm`, `focus`, `reset` | Méditation thérapeutique ciblée, prise en charge de l'anxiété |
| `emotion` | Émotions | Nommer ce qu'on ressent, le lien aux autres, la gratitude, l'écriture, les limites | `awareness`, `connection`, `gratitude`, `reflection`, `boundaries` | Tout travail psychologique ou de crise |
| `recovery` | Récupération | Les vraies pauses, la nature, le repos, les tensions du corps, les limites avec le travail | `breaks`, `nature`, `rest`, `boundaries`, `tension` | Protocoles de récupération sportive individualisés |
| `sleep` | Sommeil | La régularité des horaires, la lumière, la préparation au coucher | `regularity`, `wind-down` | Techniques de prise en charge de l'insomnie, tout ce qui touche à un médicament du sommeil |

Équilibre visé : **chaque pilier** offre des actions du matin, de midi et du soir, des
types variés (au moins une carte `learn` par pilier, adossée à un article de l'annexe C :
l'article « fondation » quand il existe, c'est-à-dire pour le sommeil, le stress, le
mouvement et la nutrition ; un autre article pour les émotions et la récupération) et des
actions de 1 à 20 minutes.

---

## 5. Format de livraison

### 5.1 Les fichiers

- **Un fichier par pilier et par lot**, encodé en UTF-8. Chaque fichier est un **tableau JSON de cartes**.
  - Lot A, enrichissement des 36 cartes existantes : `lot-a-<pillar>.json`, par exemple `lot-a-sleep.json`.
  - Lot B, nouvelles cartes : `lot-b-<pillar>.json`.
- **Lot A.** `pillar` et `title` (anglais) doivent être **exactement** ceux de la carte existante (annexe A). C'est ce qui l'identifie. Les autres champs sont tes propositions. Recopie à l'identique les textes déjà en ligne (titre FR, description, versions : annexe A.7), sauf amélioration nette que tu justifies dans `_note_clinicien`. Complète ce qui manque. En particulier, les 6 cartes qui ont une version plus loin n'ont **que son titre** : écris `rev_description` et `rev_description_fr`, sinon le fichier ne passe pas le schéma.
- **Lot B.** Le `title` anglais doit être **nouveau dans son pilier**. Il ne peut pas reprendre un titre de l'annexe A (contrainte d'unicité `pillar` + `title`).
- Chaque clé de carte correspond **une pour une** à une colonne de `habit_bank`. **Une seule exception, `_note_clinicien`** (texte libre pour la relectrice), qui n'est **pas importée**.
- Un texte absent vaut `null`, jamais `""`.

### 5.2 Le schéma JSON exact

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "functionalps/action-cards/import-v1",
  "title": "Lot de cartes action FunctionAlps (import en brouillon dans habit_bank)",
  "type": "array",
  "items": { "$ref": "#/$defs/card" },
  "$defs": {
    "text120": { "type": "string", "minLength": 1, "maxLength": 120 },
    "text400": { "type": "string", "minLength": 1, "maxLength": 400 },
    "text800": { "type": "string", "minLength": 1, "maxLength": 800 },
    "steps":   { "type": "string", "minLength": 1, "maxLength": 2000 },
    "opt120":  { "type": ["string", "null"], "minLength": 1, "maxLength": 120 },
    "opt400":  { "type": ["string", "null"], "minLength": 1, "maxLength": 400 },
    "link": {
      "oneOf": [
        {
          "type": "object", "additionalProperties": false,
          "required": ["kind", "url", "title"],
          "properties": {
            "kind":  { "const": "video" },
            "url":   { "type": "string", "pattern": "^https://\\S+$", "maxLength": 500 },
            "title": { "type": ["string", "null"], "maxLength": 120 }
          }
        },
        {
          "type": "object", "additionalProperties": false,
          "required": ["kind", "query"],
          "properties": {
            "kind":  { "const": "youtube" },
            "query": { "type": "string", "minLength": 1, "maxLength": 100 }
          }
        },
        {
          "type": "object", "additionalProperties": false,
          "required": ["kind", "slug", "title"],
          "properties": {
            "kind":  { "const": "article" },
            "slug":  { "type": "string", "minLength": 1, "maxLength": 200 },
            "title": { "type": "string", "minLength": 1 }
          }
        }
      ]
    },
    "card": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "pillar", "category", "card_kind", "duration_min", "default_slot", "frequency_rule",
        "member_can_add", "sort_order",
        "title", "title_fr", "description", "description_fr",
        "easy_title", "easy_title_fr", "easy_description", "easy_description_fr",
        "rev_title", "rev_title_fr", "rev_description", "rev_description_fr",
        "how_md", "how_md_fr", "general_why", "general_why_fr",
        "image_url", "image_alt", "resources"
      ],
      "properties": {
        "pillar":         { "enum": ["nutrition", "exercise", "mind", "emotion", "recovery", "sleep"] },
        "category":       { "type": "string", "pattern": "^[a-z][a-z -]*$", "maxLength": 40 },
        "card_kind":      { "enum": ["breath", "movement", "routine", "nutrition", "mind", "learn"] },
        "duration_min":   { "type": ["integer", "null"], "minimum": 1, "maximum": 240 },
        "default_slot":   { "enum": ["morning", "midday", "evening", null] },
        "frequency_rule": {
          "type": "string",
          "pattern": "^RRULE:FREQ=(DAILY|WEEKLY)(;INTERVAL=[1-9][0-9]?)?(;BYDAY=(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*)?$"
        },
        "member_can_add": { "type": "boolean" },
        "sort_order":     { "type": "integer", "minimum": 0 },

        "title":          { "$ref": "#/$defs/text120" },
        "title_fr":       { "$ref": "#/$defs/text120" },
        "description":    { "$ref": "#/$defs/text400" },
        "description_fr": { "$ref": "#/$defs/text400" },

        "easy_title":          { "$ref": "#/$defs/opt120" },
        "easy_title_fr":       { "$ref": "#/$defs/opt120" },
        "easy_description":    { "$ref": "#/$defs/opt400" },
        "easy_description_fr": { "$ref": "#/$defs/opt400" },
        "rev_title":           { "$ref": "#/$defs/opt120" },
        "rev_title_fr":        { "$ref": "#/$defs/opt120" },
        "rev_description":     { "$ref": "#/$defs/opt400" },
        "rev_description_fr":  { "$ref": "#/$defs/opt400" },

        "how_md":         { "$ref": "#/$defs/steps" },
        "how_md_fr":      { "$ref": "#/$defs/steps" },
        "general_why":    { "$ref": "#/$defs/text800" },
        "general_why_fr": { "$ref": "#/$defs/text800" },

        "image_url": { "const": null },
        "image_alt": { "const": null },
        "resources": {
          "type": "array",
          "maxItems": 3,
          "items": { "$ref": "#/$defs/link" },
          "allOf": [
            { "contains": { "properties": { "kind": { "const": "video" } } },   "minContains": 0, "maxContains": 1 },
            { "contains": { "properties": { "kind": { "const": "youtube" } } }, "minContains": 0, "maxContains": 1 },
            { "contains": { "properties": { "kind": { "const": "article" } } }, "minContains": 0, "maxContains": 1 }
          ]
        },

        "_note_clinicien": { "type": "string", "maxLength": 1500 }
      },
      "allOf": [
        {
          "if":   { "properties": { "easy_title": { "type": "string" } } },
          "then": { "properties": {
            "easy_title_fr": { "type": "string" }, "easy_description": { "type": "string" }, "easy_description_fr": { "type": "string" } } },
          "else": { "properties": {
            "easy_title_fr": { "type": "null" }, "easy_description": { "type": "null" }, "easy_description_fr": { "type": "null" } } }
        },
        {
          "if":   { "properties": { "rev_title": { "type": "string" } } },
          "then": { "properties": {
            "rev_title_fr": { "type": "string" }, "rev_description": { "type": "string" }, "rev_description_fr": { "type": "string" } } },
          "else": { "properties": {
            "rev_title_fr": { "type": "null" }, "rev_description": { "type": "null" }, "rev_description_fr": { "type": "null" } } }
        },
        {
          "if":   { "properties": { "card_kind": { "const": "breath" } } },
          "then": { "properties": { "duration_min": { "type": "integer" } } }
        },
        {
          "if":   { "properties": { "card_kind": { "const": "learn" } } },
          "then": { "properties": { "resources": { "contains": { "properties": { "kind": { "const": "article" } } } } } }
        }
      ]
    }
  }
}
```

Règles que le schéma ne peut pas vérifier, mais que l'import et la relecture vérifient :

- `title` (anglais) unique dans son pilier, et absent de l'annexe A pour le lot B ;
- `slug` présent dans le catalogue (annexe C) et `title` de l'article recopié à l'identique ;
- `how_md` et `how_md_fr` ont **le même nombre d'étapes**, dans le même ordre ;
- `category` reprend le vocabulaire de 2.3, sauf justification.

### 5.3 Exemple complet : « Morning light within an hour of waking »

Cette carte existe déjà (pilier `sleep`, catégorie `regularity`, ordre 6). Elle n'a ni
type, ni étapes, ni pourquoi, ni liens. L'exemple ci-dessous est donc **un enrichissement
du lot A**. Il montre le format et le ton attendus. **Le pourquoi est une proposition que
la clinicienne valide.**

```json
[
  {
    "pillar": "sleep",
    "category": "regularity",
    "card_kind": "routine",
    "duration_min": 10,
    "default_slot": "morning",
    "frequency_rule": "RRULE:FREQ=DAILY",
    "member_can_add": true,
    "sort_order": 6,

    "title": "Morning light within an hour of waking",
    "title_fr": "Lumière du matin dans l’heure qui suit le réveil",
    "description": "Ten minutes outside in daylight, soon after you get up — the night is built in the morning.",
    "description_fr": "Dix minutes dehors, à la lumière du jour, peu après le lever — la nuit se prépare dès le matin.",

    "easy_title": "Five minutes by an open window",
    "easy_title_fr": "Cinq minutes à la fenêtre ouverte",
    "easy_description": "Low on energy or a grey start? Open the window, face the sky, five minutes. It counts.",
    "easy_description_fr": "Peu d’énergie ou matin gris ? Ouvrez la fenêtre, face au ciel, cinq minutes. Ça compte.",
    "rev_title": "A 20-minute morning walk outside",
    "rev_title_fr": "Une marche de 20 minutes dehors le matin",
    "rev_description": "Same light, on the move: walk part of the way to work, or once around the block.",
    "rev_description_fr": "La même lumière, en marchant : une partie du trajet à pied, ou le tour du quartier.",

    "how_md": "1. Within an hour of getting up, step outside: a balcony, the garden, the doorstep or the way to work.\n2. Stay out for about ten minutes, facing the open sky rather than a wall.\n3. Never look straight at the sun — being in daylight is enough.\n4. Grey or rainy morning? Go out anyway: the light outside still counts.\n5. Pair it with something you already do, like your coffee, the dog or the walk to the bus.",
    "how_md_fr": "1. Dans l’heure qui suit votre lever, sortez : balcon, jardin, pas de porte ou trajet du matin.\n2. Restez dehors une dizaine de minutes, face au ciel plutôt que face à un mur.\n3. Ne regardez jamais directement le soleil — être à la lumière du jour suffit.\n4. Matin gris ou pluvieux ? Sortez quand même : la lumière du dehors compte aussi.\n5. Associez-le à un geste que vous faites déjà, comme le café, le chien ou le trajet jusqu’au bus.",

    "general_why": "Daylight in the morning is one of the signals your body clock uses to set the rhythm of your day, including when sleepiness comes in the evening. A few minutes outside, early and at about the same time each day, can help give it that signal.",
    "general_why_fr": "La lumière du jour, le matin, fait partie des signaux qu’utilise votre horloge interne pour régler le rythme de la journée, y compris le moment où le sommeil vient le soir. Quelques minutes dehors, tôt et à peu près à la même heure chaque jour, peuvent aider à lui donner ce signal.",

    "image_url": null,
    "image_alt": null,
    "resources": [
      { "kind": "youtube", "query": "morning sunlight walk routine" },
      { "kind": "article", "slug": "morning-wake-up-routine", "title": "Morning Wake-Up Routine" }
    ],

    "_note_clinicien": "Lot A : enrichissement de la carte existante (sleep · regularity · ordre 6). Description existante gardée en fin de phrase. Affirmations à valider : « la lumière du matin fait partie des signaux de l’horloge interne, y compris pour le moment où le sommeil vient le soir ». Article choisi sur son titre : vérifier qu’il parle bien de la lumière du matin, sinon « anatomie-bonne-nuit ». member_can_add proposé à true (sans risque pour un adulte tout-venant). Idée d’image : un balcon au lever du jour, une tasse à la main, sans visage reconnaissable."
  }
]
```

Une carte `breath` en plus, juste pour la forme des étapes (le cercle de l'app gonfle en
5 s et se resserre en 5 s) :

```text
1. Asseyez-vous, le dos droit, les pieds à plat au sol.
2. Inspirez doucement par le nez pendant 5 secondes, pendant que le cercle grandit.
3. Expirez lentement pendant 5 secondes, pendant que le cercle se resserre.
4. Continuez ainsi jusqu’à la fin du minuteur, sans forcer.
5. Si la tête vous tourne, reprenez une respiration normale.
```

### 5.4 Ce que le membre voit (l'exemple 5.3, en français)

```text
‹ Actions du jour

[ image du cabinet, si elle est ajoutée ]
ROUTINE · MATIN · 10 MIN
Lumière du matin dans l’heure qui suit le réveil
Dix minutes dehors, à la lumière du jour, peu après le lever — la nuit se prépare dès le matin.

AUJOURD'HUI, LA VERSION
[ Douce ]  [ Normale ]  [ Plus loin ]

Chercher « morning sunlight walk routine » sur YouTube ↗

Comment faire
 1  Dans l’heure qui suit votre lever, sortez : balcon, jardin, pas de porte ou trajet du matin.
 2  Restez dehors une dizaine de minutes, face au ciel plutôt que face à un mur.
 3  Ne regardez jamais directement le soleil — être à la lumière du jour suffit.
 4  Matin gris ou pluvieux ? Sortez quand même : la lumière du dehors compte aussi.
 5  Associez-le à un geste que vous faites déjà, comme le café, le chien ou le trajet jusqu’au bus.

Pourquoi dans votre plan
La lumière du jour, le matin, fait partie des signaux…

À lire dans la bibliothèque
Morning Wake-Up Routine                                              ›

[ C'est fait ]
[ Pas aujourd'hui ]
```

Sur l'Accueil, la même carte donne la ligne : **Lumière du matin dans l’heure qui suit le
réveil**, puis, en dessous, *Routine · 10 min*.

### 5.5 Comment les cartes entrent dans le système

1. **L'agent livre les fichiers JSON.** Il n'a aucun accès à la base et ne publie rien.
2. **Import en brouillon** dans **CLINICAL → Action cards → Import JSON** (bouton visible avec la permission `resources.write`). On choisit un ou plusieurs fichiers `.json` (ou on colle le JSON). L'outil n'appelle aucune IA et ne touche à aucune donnée patient. Il procède en deux temps :
   - **Aperçu, sans rien écrire.** Chaque carte est validée contre le schéma 5.2 et contre les limites de l'éditeur (`actionCardDraftSchema`) : valeurs fermées, longueurs, liens en `https://` seulement, `frequency_rule` lisible par l'app, versions douce et plus loin complètes (4 textes ou aucun), même nombre d'étapes en anglais et en français, durée pour une carte `breath`, article pour une carte `learn`, et **chaque slug d'article présent dans la bibliothèque publiée**. Chaque carte reçoit un statut : **nouvelle** (aucune ligne avec le même pilier et le même titre anglais), **met à jour un brouillon**, **met à jour une carte publiée** (lot A), **invalide** (avec l'erreur champ par champ) ou **doublon dans l'import** (le même pilier et le même titre deux fois : toutes les occurrences sont écartées). Des avertissements signalent ce qui ne bloque pas : catégorie hors du vocabulaire de 2.3, règle hebdomadaire sans `BYDAY`, fichier `lot-a` sans carte correspondante, fichier `lot-b` qui retrouve une carte existante. Le `_note_clinicien` s'affiche sous chaque carte pour la relectrice ; il n'est **jamais** enregistré.
   - **Import.** Le serveur revalide et reclasse tout (il ne se fie pas à l'aperçu). Une carte **nouvelle** est insérée en brouillon avec **`active = false`** écrit explicitement (`active` vaut **`true` par défaut** en base : un import qui l'oublierait mettrait la carte en ligne sans relecture), `published_at = null`, `published_by = null` et `created_by` = la clinicienne qui lance l'import ; `category`, `frequency_rule`, `sort_order` et `member_can_add` viennent du fichier. Un **brouillon** existant est mis à jour. Les cartes **invalides** et les **doublons** sont écartés. Une mise à jour ne touche jamais au pilier, au titre anglais, à l'image ni à l'état de publication. L'outil affiche ensuite le résultat carte par carte.
3. **Lot A, à part.** Les 36 cartes existantes sont **déjà publiées**, et toute modification serait en ligne immédiatement. Le lot A n'est donc **jamais appliqué automatiquement**. Dans l'aperçu de l'import, chaque carte publiée concernée porte une case à cocher, **décochée par défaut**, avec l'avertissement que le changement part en direct chez tous les membres. Seule une responsable (`resources.approve`) peut cocher, carte par carte ; sans case cochée, la carte reste telle quelle. La responsable peut aussi reporter les changements à la main dans l'éditeur.
4. **Relecture** dans **CLINICAL → Action cards** (`/action-cards`). Chaque brouillon s'ouvre avec l'aperçu iPhone en direct (bascule FR/EN, versions cliquables). La nutritionniste corrige, téléverse l'image et remplit `image_alt`. Le bouton « Fill empty fields with AI » ne remplit **que les champs vides**.
5. **Publication** par une responsable (`resources.approve`), bouton *Publish*. La carte devient visible : focus du jour, banque « Actions de base » si `member_can_add`, sélecteur de carte des habitudes du patient et, bientôt, éléments du care plan.
6. **Après publication**, seule une responsable peut la modifier (en direct pour tous) ou la retirer (*Retire*).

---

## 6. Checklist qualité avant livraison

À passer pour **chaque** carte. Une seule réponse « non » et la carte n'est pas livrée.

**Format**

- [ ] Le fichier est un tableau JSON valide en UTF-8 qui passe le schéma 5.2.
- [ ] Toutes les clés sont présentes ; les textes absents valent `null`, jamais `""`.
- [ ] `pillar`, `card_kind` et `default_slot` reprennent exactement les valeurs autorisées.
- [ ] `category` vient du vocabulaire de 2.3, sinon la note la justifie.
- [ ] `frequency_rule` commence par `RRULE:` et suit l'un des formats de 2.4 ; une règle hebdomadaire a un `BYDAY`.
- [ ] `duration_min` est un entier réaliste de 1 à 240, ou `null` pour une action non chronométrée. Il est obligatoire pour `breath`.
- [ ] Lot A : `pillar` et `title` sont identiques à l'annexe A ; les textes déjà en ligne (annexe A.7) sont repris, ou leur changement est justifié dans la note. Lot B : le titre est nouveau dans son pilier.
- [ ] `image_url` et `image_alt` valent `null`. Il n'y a pas de clé `active`, `published_at` ou `id`.

**Contenu**

- [ ] Un seul comportement, cochable « C'est fait » sans hésiter.
- [ ] Le titre fait au plus ~45 caractères et la description tient en une phrase et se comprend seule, sans les étapes.
- [ ] 3 à 7 étapes, une par ligne au format `1. …`, chacune une phrase complète, sans markdown. Même nombre d'étapes en anglais et en français.
- [ ] Les versions douce et plus loin gardent **le même geste**, et chacune a ses 4 champs ou aucun. Leur description dit ce qui change.
- [ ] Le pourquoi tient en 2 à 3 phrases, explique le mécanisme en mots simples, formule « peut aider » et ne promet rien.
- [ ] Aucun interdit de 3.5 : diagnostic, traitement, complément, dosage, régime, jargon, culpabilisation, donnée patient.
- [ ] `movement` et `breath` : la ligne de sécurité est présente et le rythme est écrit en secondes (respiration).
- [ ] Aucun doublon d'idée avec l'annexe A ou une autre carte du lot.

**Langues et ton**

- [ ] Chaque texte existe en anglais **et** en français ; le français sonne naturel et vouvoie.
- [ ] Conventions de 3.8 respectées : heures, apostrophe ’, guillemets « », tiret —.
- [ ] Ni emoji, ni majuscules, ni symboles à la place des mots.

**Liens**

- [ ] Pas de `video`, sauf URL fournie par le cabinet.
- [ ] La recherche YouTube fait 3 à 6 mots, trouve une démonstration et se lit bien dans l'app en français.
- [ ] L'article est un slug de l'annexe C, son titre est recopié à l'identique et il approfondit vraiment le geste. Une carte `learn` a toujours un article.

**Relecture**

- [ ] `_note_clinicien` liste les affirmations santé à valider, la raison du choix de `member_can_add`, une idée d'image et tout doute.
- [ ] La carte serait sans risque si le focus du jour la proposait à n'importe quel adulte. Sinon : `member_can_add = false`, et la note dit pourquoi.

---

## Annexe A — Les 36 cartes existantes et l'idée derrière chacune

État au 2026-10-02 : toutes sont **publiées** (`active = true`), **aucune** n'a de type, de
durée, d'étapes, de pourquoi ou de lien, et **aucune** n'a `member_can_add = true`. La
banque « Actions de base » de l'app est donc **vide** aujourd'hui. Le lot A consiste à
les compléter. La colonne « Type proposé » est une suggestion de départ.

Légende des versions : D = version douce présente (titre et description, EN et FR),
P = version plus loin présente, **titre seulement** : aucune des 6 cartes P n'a de
`rev_description` ni de `rev_description_fr`, à écrire dans le lot A. Les textes exacts
déjà en ligne sont en A.7.
Fréquence : quotidienne sauf mention.

### Émotions (`emotion`)

| Ordre | Titre EN / FR | Catégorie | Moment | Versions | Type proposé | L'idée derrière |
|---|---|---|---|---|---|---|
| 1 | Name the feeling, once / Nommez l’émotion, une fois | `awareness` | soir | — | `mind` | Mettre un mot sur ce qu'on ressent, une fois par jour, sans chercher à le changer. |
| 2 | One message to someone you like / Un message à quelqu’un que vous appréciez | `connection` | midi | — | `routine` | Entretenir le lien par un geste de trente secondes. |
| 3 | Three good things tonight / Trois bonnes choses ce soir | `gratitude` | soir | D | `mind` | Tourner l'attention vers ce qui a bien marché, même petit. |
| 4 | Journaling, five minutes / Cinq minutes de journal | `reflection` | soir | D | `mind` | Déposer ses pensées sur le papier, sans filtre, pour soi seul. |
| 5 | A real lunch with someone / Un vrai déjeuner avec quelqu’un | `connection` | midi | — | `routine` | Un repas partagé, sans écran, une fois par semaine (`BYDAY=WE`). |
| 6 | Say no to one thing / Dites non à une chose | `boundaries` | midi | — | `mind` | Protéger sa journée par un petit refus choisi. |

### Mouvement (`exercise`)

| Ordre | Titre EN / FR | Catégorie | Moment | Versions | Type proposé | L'idée derrière |
|---|---|---|---|---|---|---|
| 1 | A 10-minute walk after lunch / Une marche de 10 minutes après le déjeuner | `movement` | midi | D, P | `movement` | Bouger juste après le repas, contre le coup de barre de l'après-midi. Article possible : `post-meal-walking`. |
| 2 | Morning stretch, five minutes / Étirements du matin, cinq minutes | `mobility` | matin | D | `movement` | Réveiller le corps avant que la journée ne s'en empare. Article possible : `mobilite-matinale`. |
| 3 | One set of push-ups / Une série de pompes | `strength` | matin | P | `movement` | Une seule série, la technique avant la quantité. |
| 4 | Stairs instead of lifts / Les escaliers plutôt que l’ascenseur | `movement` | midi | — | `movement` | Glisser l'effort dans les trajets du quotidien. |
| 5 | Evening walk / Marche du soir | `movement` | soir | D, P | `movement` | Bouger doucement après le dîner. |
| 6 | Ten sit-to-stands / Dix assis-debout | `strength` | midi | D, P | `movement` | Renforcer les jambes depuis une chaise, sans matériel. Article possible : `squat-and-lower-limb-confidence`. |

### Esprit (`mind`)

| Ordre | Titre EN / FR | Catégorie | Moment | Versions | Type proposé | L'idée derrière |
|---|---|---|---|---|---|---|
| 1 | Three slow breaths before meals / Trois respirations lentes avant les repas | `calm` | midi | P | `breath` | Une transition calme avant de manger. Sa version plus loin actuelle (« Box breathing, 4×4, once a day ») est un autre exercice, qui existe déjà en carte (ordre 2) : contraire à 2.5, à signaler dans la note avec une proposition (par exemple cinq respirations lentes). |
| 2 | Box breathing, 4×4 / Respiration carrée, 4×4 | `calm` | midi | — | `breath` | Rythme 4-4-4-4 (inspirer, retenir, expirer, retenir), quatre cycles. Les étapes doivent dire que le cercle de l'app ne suit pas ce rythme : on suit son propre compte. |
| 3 | One phone-free coffee / Un café sans téléphone | `focus` | matin | — | `routine` | Un moment à une seule chose, rien d'autre entre les mains. |
| 4 | Single-task the first work hour / Une seule tâche pendant la première heure de travail | `focus` | matin | D | `mind` | Protéger la première heure de travail des interruptions. |
| 5 | Five minutes of daylight / Cinq minutes de lumière du jour | `reset` | matin | D | `routine` | Une recharge rapide à la lumière. Proche de deux autres cartes « lumière » : trouver son angle propre (la pause qui recentre). |
| 6 | A two-minute pause between tasks / Une pause de deux minutes entre deux tâches | `reset` | midi | — | `mind` | Une micro-coupure : se lever, regarder au loin, respirer. |

### Nutrition (`nutrition`)

| Ordre | Titre EN / FR | Catégorie | Moment | Versions | Type proposé | L'idée derrière |
|---|---|---|---|---|---|---|
| 1 | A glass of water before coffee / Un verre d’eau avant le café | `hydration` | matin | — | `nutrition` | S'hydrater en premier, en s'appuyant sur un geste déjà installé. |
| 2 | Protein at breakfast / Des protéines au petit-déjeuner | `food rhythm` | matin | D | `nutrition` | Une source de protéines au premier repas, pour une matinée plus régulière. |
| 3 | Vegetables on half the plate / Des légumes sur la moitié de l’assiette | `food rhythm` | midi | — | `nutrition` | Un repas par jour où les légumes occupent la moitié de l'assiette. |
| 4 | Slow first five bites / Les cinq premières bouchées, lentement | `mindful eating` | midi | D | `nutrition` | Ralentir le début du repas pour en donner le rythme. |
| 5 | Fruit within reach / Un fruit à portée de main | `food rhythm` | midi | — | `routine` | Préparer l'environnement pour que le choix simple soit déjà là. |
| 6 | Kitchen closed after 21:00 / Cuisine fermée après 21 h | `food rhythm` | soir | D | `routine` | Une heure de fermeture plutôt que la volonté. |

### Récupération (`recovery`)

| Ordre | Titre EN / FR | Catégorie | Moment | Versions | Type proposé | L'idée derrière |
|---|---|---|---|---|---|---|
| 1 | A real pause at lunch, no screens / Une vraie pause à midi, sans écrans | `breaks` | midi | D | `routine` | Vingt minutes où l'on ne vous demande rien. |
| 2 | Five minutes outside in daylight / Cinq minutes dehors, à la lumière du jour | `nature` | midi | — | `routine` | La recharge la plus simple : sortir. Proche d'autres cartes « lumière » : insister sur le dehors et la pause. |
| 3 | Legs up the wall, five minutes / Jambes au mur, cinq minutes | `rest` | soir | — | `movement` | Une posture de repos pour ralentir avant la soirée (une démonstration aide). |
| 4 | One work-free evening block / Un créneau sans travail le soir | `boundaries` | soir | — | `routine` | Une heure où le travail ne peut pas vous atteindre. |
| 5 | Shoulders down, jaw loose — three times / Épaules basses, mâchoire relâchée — trois fois | `tension` | midi | — | `mind` | Relâcher les deux endroits où la journée s'accumule, trois fois par jour. |
| 6 | A 20-minute nature walk / Une balade de 20 minutes dans la nature | `nature` | midi | P | `movement` | Du temps au vert, le week-end, sans rythme ni objectif (`BYDAY=SA`). |

### Sommeil (`sleep`)

| Ordre | Titre EN / FR | Catégorie | Moment | Versions | Type proposé | L'idée derrière |
|---|---|---|---|---|---|---|
| 1 | Same bedtime on weekdays / Même heure de coucher en semaine | `regularity` | soir | — | `routine` | La régularité plutôt qu'un nombre d'heures. Sa fréquence en base est **quotidienne** alors que le titre dit « en semaine » : propose `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` et signale-le dans la note. |
| 2 | No caffeine after 14:00 / Pas de caféine après 14 h | `regularity` | midi | — | `nutrition` | Une heure limite pour la dernière tasse. |
| 3 | Screens off 30 minutes before bed / Écrans éteints 30 minutes avant le coucher | `wind-down` | soir | D | `routine` | Laisser à l'esprit le temps d'atterrir. |
| 4 | Dim the lights after 21:00 / Lumières tamisées après 21 h | `wind-down` | soir | — | `routine` | Baisser la lumière, comme un signal de fin de journée. |
| 5 | Tomorrow's list before bed / La liste de demain avant le coucher | `wind-down` | soir | D | `mind` | Déposer sur le papier ce qui reste en suspens. |
| 6 | Morning light within an hour of waking / Lumière du matin dans l’heure qui suit le réveil | `regularity` | matin | — | `routine` | La nuit se prépare dès le matin (exemple complet en 5.3). |

### A.7 Les textes déjà en ligne (à recopier à l'identique dans le lot A)

Relevé en lecture seule sur `habit_bank` le 2026-10-02. « — » = champ vide. Le titre FR
est dans les tableaux ci-dessus. Les apostrophes typographiques (’) et les tirets (—) font
partie du texte.

| Pilier · ordre | Titre EN | `description` / `description_fr` | Version douce : `easy_title` / `easy_title_fr`, puis `easy_description` / `easy_description_fr` | Plus loin : `rev_title` / `rev_title_fr` (aucune description) |
|---|---|---|---|---|
| `emotion` · 1 | Name the feeling, once | One moment a day: what is this feeling called? / Un moment par jour : comment s’appelle ce que vous ressentez ? | — | — |
| `emotion` · 2 | One message to someone you like | Thirty seconds of connection, sent. / Trente secondes pour entretenir le lien. | — | — |
| `emotion` · 3 | Three good things tonight | Small ones count double. / Les petites comptent double. | titre : One good thing / Une bonne chose<br>description : One is a practice too. / Une seule, c’est déjà une pratique. | — |
| `emotion` · 4 | Journaling, five minutes | Unfiltered, for nobody else. / Sans filtre, pour personne d’autre que vous. | titre : Three lines / Trois lignes<br>description : Three honest lines beat an empty page. / Trois lignes sincères valent mieux qu’une page blanche. | — |
| `emotion` · 5 | A real lunch with someone | Once in the week, lunch is company, not a screen. / Une fois dans la semaine, le déjeuner se partage — sans écran. | — | — |
| `emotion` · 6 | Say no to one thing | One small no that protects the day. / Un petit non qui protège votre journée. | — | — |
| `exercise` · 1 | A 10-minute walk after lunch | Moves lunch along and clears the afternoon slump. / Aide la digestion et chasse le coup de barre de l’après-midi. | titre : Five minutes outside / Cinq minutes dehors<br>description : Half the walk, all the credit. / La moitié de la marche, tout le mérite. | Stretch it to 20 minutes / Allongez-la à 20 minutes |
| `exercise` · 2 | Morning stretch, five minutes | Wake the body before the day claims it. / Réveillez le corps avant que la journée ne s’en empare. | titre : Two stretches at the counter / Deux étirements contre le plan de travail<br>description : While the coffee brews. / Pendant que le café coule. | — |
| `exercise` · 3 | One set of push-ups | Whatever number feels doable — form over count. / Autant que vous le sentez — la technique avant la quantité. | — | Two sets — rest a minute between / Deux séries — une minute de pause entre les deux |
| `exercise` · 4 | Stairs instead of lifts | Free training hidden in the day. / Un entraînement gratuit, caché dans la journée. | — | — |
| `exercise` · 5 | Evening walk | Movement after dinner — the strongest gentle lever on sleep. / Bouger après le dîner — le levier doux le plus puissant sur le sommeil. | titre : Five minutes around the block / Cinq minutes autour du pâté de maisons<br>description : Short is fine — out the door is the win. / Court, c’est très bien — passer la porte, c’est déjà gagné. | Add ten extra minutes / Ajoutez dix minutes |
| `exercise` · 6 | Ten sit-to-stands | From a chair, no equipment — legs carry everything else. / Depuis une chaise, sans matériel — les jambes portent tout le reste. | titre : Five sit-to-stands / Cinq assis-debout<br>description : Half a round still counts. / Une demi-série compte quand même. | Two rounds of ten / Deux séries de dix |
| `mind` · 1 | Three slow breaths before meals | Tells the body "we're safe" — meals land better. / Signale au corps « tout va bien » — les repas passent mieux. | — | Box breathing, 4×4, once a day / Respiration carrée, 4×4, une fois par jour |
| `mind` · 2 | Box breathing, 4×4 | In four, hold four, out four, hold four — four rounds. / Inspirez sur quatre, retenez sur quatre, expirez sur quatre, retenez sur quatre — quatre cycles. | — | — |
| `mind` · 3 | One phone-free coffee | One warm drink a day with nothing else in your hands. / Une boisson chaude par jour, rien d’autre entre les mains. | — | — |
| `mind` · 4 | Single-task the first work hour | One thing, done properly, before the noise starts. / Une chose, bien faite, avant que le bruit commence. | titre : Single-task the first 20 minutes / Une seule tâche pendant les 20 premières minutes<br>description : A short focused start still counts. / Un début court mais concentré compte aussi. | — |
| `mind` · 5 | Five minutes of daylight | Light anchors the body clock — mornings work best. / La lumière règle l’horloge interne — le matin, c’est idéal. | titre : Open the window — two minutes counts / Ouvrez la fenêtre — deux minutes, ça compte<br>description : Light through glass beats no light. / La lumière à travers une vitre vaut mieux que pas de lumière. | — |
| `mind` · 6 | A two-minute pause between tasks | Stand up, look far away, breathe once. / Levez-vous, regardez au loin, respirez une fois. | — | — |
| `nutrition` · 1 | A glass of water before coffee | Start hydrated — the coffee lands softer. / Commencez par vous hydrater — le café passe plus en douceur. | — | — |
| `nutrition` · 2 | Protein at breakfast | Eggs, skyr, leftovers — anything. Steadier energy before 11:00. / Œufs, skyr, restes — peu importe. Une énergie plus stable jusqu’à 11 h. | titre : Anything at breakfast counts / Tout ce que vous mangez au petit-déjeuner compte<br>description : A short-night version that still moves you forward. / La version des nuits courtes, qui vous fait quand même avancer. | — |
| `nutrition` · 3 | Vegetables on half the plate | One plate a day where vegetables win the territory. / Une assiette par jour où les légumes ont le dessus. | — | — |
| `nutrition` · 4 | Slow first five bites | The first five bites set the pace for the whole meal. / Les cinq premières bouchées donnent le rythme de tout le repas. | titre : Three slow bites / Trois bouchées lentes<br>description : Small still counts. / Petit, ça compte aussi. | — |
| `nutrition` · 5 | Fruit within reach | When the dip hits, the easy option is already in your hand. / Quand le coup de barre arrive, l’option facile est déjà dans votre main. | — | — |
| `nutrition` · 6 | Kitchen closed after 21:00 | A closing time beats willpower. / Une heure de fermeture vaut mieux que la volonté. | titre : One late snack is fine — just notice it / Une collation tardive, ça va — remarquez-la simplement<br>description : Noticing is the habit tonight. / Ce soir, l’habitude, c’est de la remarquer. | — |
| `recovery` · 1 | A real pause at lunch, no screens | Twenty minutes where nothing is asked of you. / Vingt minutes où l’on ne vous demande rien. | titre : Ten minutes, no screens / Dix minutes, sans écrans<br>description : A shorter true pause beats a long half-one. / Une vraie pause, même courte, vaut mieux qu’une longue à moitié prise. | — |
| `recovery` · 2 | Five minutes outside in daylight | The cheapest recharge there is. / La recharge la moins chère qui soit. | — | — |
| `recovery` · 3 | Legs up the wall, five minutes | Let the system idle before the evening. / Laissez l’organisme tourner au ralenti avant la soirée. | — | — |
| `recovery` · 4 | One work-free evening block | An hour where work cannot reach you. / Une heure où le travail ne peut pas vous atteindre. | — | — |
| `recovery` · 5 | Shoulders down, jaw loose — three times | The two places the day hides. / Les deux endroits où la journée se cache. | — | — |
| `recovery` · 6 | A 20-minute nature walk | Green time on the weekend — no pace, no goal. / Du temps au vert le week-end — sans rythme, sans objectif. | — | Make it forty minutes / Allez jusqu’à quarante minutes |
| `sleep` · 1 | Same bedtime on weekdays | The body loves a rhythm more than a number. / Le corps aime un rythme plus qu’un chiffre. | — | — |
| `sleep` · 2 | No caffeine after 14:00 | The afternoon cup steals from the night. / La tasse de l’après-midi empiète sur la nuit. | — | — |
| `sleep` · 3 | Screens off 30 minutes before bed | Give the mind a runway. / Offrez à l’esprit une piste d’atterrissage. | titre : Phone out of the bedroom / Le téléphone hors de la chambre<br>description : Distance does the work for you. / La distance fait le travail à votre place. | — |
| `sleep` · 4 | Dim the lights after 21:00 | Darkness is a signal, not an absence. / L’obscurité est un signal, pas une absence. | — | — |
| `sleep` · 5 | Tomorrow's list before bed | Park the open loops on paper. / Déposez sur papier ce qui reste en suspens. | titre : One line for tomorrow / Une ligne pour demain<br>description : One parked thought quiets the rest. / Une pensée déposée apaise les autres. | — |
| `sleep` · 6 | Morning light within an hour of waking | The night is built in the morning. / La nuit se prépare dès le matin. | — | — |

---

## Annexe B — Pistes de nouvelles cartes (lot B)

Ce sont des **idées de départ**, pas des cartes : à toi d'en tirer des cartes complètes,
d'en écarter ou d'en ajouter, dans le respect des sections 3 et 4. Objectif indicatif :
**environ 8 nouvelles cartes par pilier**. « Base ? » est une proposition pour
`member_can_add` ; « à voir » veut dire « clinicienne à consulter, dis-le dans la note ».
Les articles sont des slugs de l'annexe C. Chaque idée a été comparée à l'annexe A et aux
autres idées : quand elle en est proche, la colonne « Base ? » dit quel angle garder.

### Nutrition

| Idée (titre provisoire) | `card_kind` | `category` | Moment | Fréquence | Article possible | Base ? |
|---|---|---|---|---|---|---|
| Une gourde visible sur le bureau | `nutrition` | `hydration` | midi | jours de semaine | — | oui |
| Un verre d'eau à chaque repas | `nutrition` | `hydration` | midi | quotidienne | — | oui |
| Manger assis, sans écran, pour un repas | `nutrition` | `mindful eating` | soir | quotidienne | — | oui (le soir : à midi, l'idée double « A real pause at lunch, no screens ») |
| Une couleur de plus dans l'assiette | `nutrition` | `food rhythm` | midi | quotidienne | `nutrient-dense-foods` | oui |
| Préparer le déjeuner de demain la veille | `routine` | `food rhythm` | soir | jours de semaine | — | oui |
| Un repas cuisiné maison cette semaine | `routine` | `food rhythm` | soir | hebdomadaire | — | oui |
| Lire une étiquette en faisant les courses | `routine` | `food rhythm` | — | hebdomadaire | — | à voir (repérer la liste des ingrédients, jamais compter des calories ou des grammes : voir 3.5 ; l'article « Macros & micros » est déjà pris par la carte suivante) |
| Comprendre : « Macros & micros, la base » | `learn` | `food rhythm` | — | hebdomadaire | `macros-micros-la-base` | oui |

### Mouvement

| Idée (titre provisoire) | `card_kind` | `category` | Moment | Fréquence | Article possible | Base ? |
|---|---|---|---|---|---|---|
| Mobilité des hanches et du dos, 5 minutes | `movement` | `mobility` | matin | quotidienne | `mobilite-matinale` | oui, seulement avec un angle clairement différent de « Morning stretch, five minutes » (même moment, même durée) : une séquence précise hanches et dos. Sinon, enrichis la carte existante |
| Une pause mouvement de 2 minutes au bureau | `movement` | `movement` | midi | jours de semaine | `movement-snack-bureau` | oui (un vrai mouvement, pour se distinguer de « A two-minute pause between tasks ») |
| Se lever toutes les heures | `routine` | `movement` | midi | jours de semaine | `exercise-snacks-small-signals-that-add-up` | oui (très proche de la précédente : n'en garder qu'une si les deux se ressemblent) |
| Montées sur la pointe des pieds, 15 fois | `movement` | `strength` | matin | quotidienne | — | oui |
| Équilibre sur un pied pendant le brossage de dents (près d'un appui) | `movement` | `mobility` | soir | quotidienne | — | oui |
| Marche d'un bon pas, 20 minutes (on peut encore parler) | `movement` | `movement` | — | 3×/semaine | `build-your-aerobic-base` | oui |
| Planche, 3 × 20 secondes | `movement` | `strength` | matin | 3×/semaine | `strength-is-more-than-muscle-size` | à voir |
| Échauffement de 5 minutes avant votre séance | `movement` | `mobility` | — | 3×/semaine | `warm-up-before-training` | oui |
| Comprendre : « Bouger fonctionnel » | `learn` | `movement` | — | hebdomadaire | `bouger-fonctionnel` | oui |

### Esprit

| Idée (titre provisoire) | `card_kind` | `category` | Moment | Fréquence | Article possible | Base ? |
|---|---|---|---|---|---|---|
| Cohérence cardiaque, 5 minutes (5 s / 5 s, le rythme du cercle de l'app) | `breath` | `calm` | — | quotidienne | `la-coherence-cardiaque` | oui |
| Respiration de 3 minutes | `breath` | `calm` | midi | quotidienne | `respiration-3-minutes` | oui |
| Expiration plus longue que l'inspiration | `breath` | `calm` | midi | quotidienne | `breathing-exercises` | oui (en journée, assis ; la version au lit est en Sommeil. Rythme différent du cercle : voir 2.2) |
| Scan corporel de 5 minutes | `mind` | `calm` | soir | quotidienne | — | oui |
| Notifications coupées pendant une heure | `routine` | `focus` | midi | jours de semaine | — | oui (un bloc de l'après-midi : le matin est déjà « Single-task the first work hour ») |
| Écrire la tâche la plus importante du jour | `mind` | `focus` | matin | jours de semaine | — | oui |
| Une marche sans téléphone, 10 minutes | `movement` | `reset` | — | quotidienne | — | oui (angle : sans téléphone, entre deux tâches ; ne pas doubler « A 10-minute walk after lunch ») |
| Comprendre : « Le stress et ton corps » | `learn` | `calm` | — | hebdomadaire | `le-stress-et-ton-corps` | oui |

### Émotions

| Idée (titre provisoire) | `card_kind` | `category` | Moment | Fréquence | Article possible | Base ? |
|---|---|---|---|---|---|---|
| Un merci dit à voix haute | `mind` | `gratitude` | — | quotidienne | — | oui |
| Savourer un moment agréable, 20 secondes | `mind` | `gratitude` | midi | quotidienne | — | oui |
| Appeler quelqu'un plutôt que lui écrire | `routine` | `connection` | soir | hebdomadaire | — | oui |
| Un geste gentil pour quelqu'un | `routine` | `connection` | — | quotidienne | — | oui |
| Demander de l'aide pour une chose | `mind` | `connection` | — | hebdomadaire | — | oui |
| Écrire une inquiétude, puis une première petite étape | `mind` | `reflection` | soir | quotidienne | — | à voir |
| Un moment pour vous, inscrit à l'agenda | `routine` | `boundaries` | — | hebdomadaire | — | oui |
| Comprendre : « Microbiote & humeur » | `learn` | `awareness` | — | hebdomadaire | `microbiote-humeur` | à voir |

### Récupération

| Idée (titre provisoire) | `card_kind` | `category` | Moment | Fréquence | Article possible | Base ? |
|---|---|---|---|---|---|---|
| Repos profond guidé (NSDR / yoga nidra), 10 minutes | `mind` | `rest` | midi | quotidienne | `nsdr-yoga-nidra` | oui |
| Étirements doux du soir, 5 minutes | `movement` | `tension` | soir | quotidienne | `routine-du-soir` | oui |
| Détendre la nuque et les épaules, 2 minutes | `movement` | `tension` | midi | quotidienne | — | à voir (proche de « Shoulders down, jaw loose — three times » : seulement si c'est un vrai mouvement de nuque et d'épaules, sinon enrichis la carte existante) |
| Une pause de 5 minutes toutes les 90 minutes | `routine` | `breaks` | midi | jours de semaine | — | oui |
| Une soirée sans écran par semaine | `routine` | `boundaries` | soir | hebdomadaire | — | oui |
| Une douche ou un bain chaud le soir, comme un rituel | `routine` | `rest` | soir | quotidienne | — | oui |
| Comprendre : « Recovery in Three Parts » | `learn` | `rest` | — | hebdomadaire | `recovery-in-three-parts` | oui |

### Sommeil

| Idée (titre provisoire) | `card_kind` | `category` | Moment | Fréquence | Article possible | Base ? |
|---|---|---|---|---|---|---|
| Même heure de lever, même le week-end | `routine` | `regularity` | matin | quotidienne | — | oui |
| Une routine du soir en trois gestes | `routine` | `wind-down` | soir | quotidienne | `wind-down-sommeil` | oui |
| Quelques pages sur papier au lit | `routine` | `wind-down` | soir | quotidienne | — | oui |
| Préparer la chambre : fraîche, sombre, calme | `routine` | `wind-down` | soir | quotidienne | — | oui |
| Expiration longue au lit, 3 minutes | `breath` | `wind-down` | soir | quotidienne | `breathing-exercises` | oui |
| Pas d'alcool les soirs de semaine | `nutrition` | `regularity` | soir | jours de semaine | — | à voir |
| Une sieste courte, avant le milieu d'après-midi | `routine` | `regularity` | midi | — | — | à voir |
| Comprendre : « Anatomie d'une bonne nuit » | `learn` | `regularity` | — | hebdomadaire | `anatomie-bonne-nuit` | oui |

### À ne **pas** écrire comme carte de base (réservé à une prescription)

Intervalles intenses (HIIT), zones cardio 4 et 5, entraînement excentrique ou découpage
d'entraînement, exposition au froid, jeûne ou fenêtre alimentaire, reset sucre, protocoles
intestin (4R, éviction), restriction de sommeil et « se lever si l'on ne dort pas »,
tout complément (créatine, magnésium…), tout ce qui touche à la périménopause, aux
analyses ou aux scores. Le cabinet en fera, s'il le souhaite, des cartes à part,
attachées par la clinicienne à un patient précis.

---

## Annexe C — Catalogue des articles de la bibliothèque (slugs)

Instantané du 2026-10-02 : articles publiés sur le canal `patient_app`, ceux que
l'app affiche et que l'éditeur propose. **La source de vérité est le sélecteur
« Library article » de CLINICAL**, et un slug absent est refusé à l'enregistrement. La
colonne « En carte de base » est une **indication tirée du seul titre** : la clinicienne
vérifie le contenu. Les tags de durée (`minutes:N`) sont omis de la colonne « Tags ».

| Slug | Titre (à recopier tel quel) | Tags | En carte de base |
|---|---|---|---|
| `anatomie-bonne-nuit` | Anatomie d'une bonne nuit | sommeil, foundation | oui (fondation sommeil) |
| `le-stress-et-ton-corps` | Le stress et ton corps | stress, foundation | oui (fondation esprit / émotions) |
| `bouger-fonctionnel` | Bouger fonctionnel | mouvement, foundation | oui (fondation mouvement) |
| `macros-micros-la-base` | Macros & micros, la base | nutrition, foundation | oui (fondation nutrition) |
| `comprendre-ton-intestin` | Comprendre ton intestin | intestin, foundation | à voir |
| `l-energie-cellulaire` | L'énergie cellulaire | energie, foundation | à voir |
| `l-inflammation-expliquee` | L'inflammation expliquée | inflammation, foundation | à voir |
| `hormones-tableau-ensemble` | Hormones, le tableau d'ensemble | hormones, foundation | à voir |
| `breathing-exercises` | Breathing Exercises | sommeil | oui |
| `respiration-3-minutes` | Respiration 3 minutes | stress, video | oui |
| `la-coherence-cardiaque` | La cohérence cardiaque | stress, article | oui |
| `coherence-cardiaque-21-jours` | Cohérence cardiaque 21 jours | stress, protocol | oui |
| `nsdr-yoga-nidra` | NSDR / Yoga Nidra | sommeil | oui |
| `morning-wake-up-routine` | Morning Wake-Up Routine | sommeil, quick | oui |
| `routine-energie-matin` | Routine énergie du matin | energie, protocol | oui |
| `routine-du-soir` | Routine du soir | sommeil, video | oui |
| `wind-down-sommeil` | Wind-down sommeil | sommeil, protocol | oui |
| `le-sommeil-pilier-sante` | Le sommeil, pilier de la santé | sommeil, article | oui |
| `ecrans-melatonine` | Écrans & mélatonine | sommeil, article | oui |
| `optimiser-son-sommeil` | Optimiser son sommeil | sommeil, webinar | oui |
| `biological-recovery` | Biological Recovery | sommeil | oui |
| `recovery-in-three-parts` | Recovery in Three Parts | sommeil | oui |
| `post-meal-walking` | Post-Meal Walking | quick, energie | oui |
| `mobilite-matinale` | Mobilité matinale | mouvement, video | oui |
| `movement-snack-bureau` | Movement snack au bureau | mouvement, video | oui |
| `micro-workouts-exercise-snacks` | Micro-Workouts / Exercise Snacks | mouvement | oui |
| `exercise-snacks-small-signals-that-add-up` | Exercise Snacks — Small Signals That Add Up | — | oui |
| `warm-up-before-training` | Warm-Up Before Training | mouvement | oui |
| `squat-and-lower-limb-confidence` | Squat & Lower-Limb Confidence | mouvement | oui |
| `rom-and-loaded-mobility` | ROM & Loaded Mobility | mouvement | à voir |
| `build-your-aerobic-base` | Build Your Aerobic Base | — | oui |
| `zone-2-cardio` | Zone 2 Cardio | energie | à voir |
| `strength-is-more-than-muscle-size` | Strength Is More Than Muscle Size | — | oui |
| `build-a-stronger-more-capable-body` | Build a Stronger, More Capable Body | — | oui |
| `make-your-training-work-better` | Make Your Training Work Better | — | à voir |
| `stamina-capacity-building` | Stamina & Capacity Building | energie, deep | à voir |
| `nervous-system-and-muscle-recruitment` | Nervous System & Muscle Recruitment | mouvement | à voir |
| `signals-create-adaptation` | Signals Create Adaptation | deep | à voir |
| `build-your-engine` | Build Your Engine | — | à voir |
| `raise-your-aerobic-ceiling` | Raise Your Aerobic Ceiling | — | non (intensité) |
| `hiit` | HIIT | energie | non (intensité) |
| `hiit-work-recover-repeat` | HIIT: Work, Recover, Repeat | — | non (intensité) |
| `zones-4-and-5` | Zones 4 & 5 | energie | non (intensité) |
| `eccentric-training` | Eccentric Training | mouvement | non (intensité) |
| `training-split-optimisation` | Training Split Optimisation | mouvement | non (programme) |
| `fuel-the-adaptation` | Fuel the Adaptation | — | à voir |
| `fuel-and-cellular-machinery` | Fuel & Cellular Machinery | — | à voir |
| `refuel-training-signal` | Refuel the Training Signal | — | à voir |
| `nutrient-dense-foods` | Nutrient-Dense Foods | nutrition | oui |
| `macros-vs-micros` | Macros vs Micros | nutrition | oui |
| `micronutrient-tracking` | Micronutrient Tracking | nutrition | à voir |
| `micronutrients-and-hormones` | Micronutrients & Hormones | nutrition | à voir |
| `coup-de-pompe-15h` | Le coup de pompe de 15h | energie, article | oui |
| `anti-inflammatoire-quotidien` | Anti-inflammatoire au quotidien | inflammation, article | à voir |
| `petit-dej-anti-inflammatoire` | Petit-déj anti-inflammatoire | inflammation, recipe | à voir |
| `bowl-intestin-friendly` | Bowl intestin-friendly | intestin, recipe | à voir |
| `smoothie-energie-durable` | Smoothie énergie durable | energie, recipe | à voir |
| `diner-riche-en-fer` | Dîner riche en fer | energie, recipe | à voir |
| `assiette-hormonale` | Assiette hormonale | hormones, recipe | à voir |
| `microbiote-humeur` | Microbiote & humeur | intestin, article | à voir |
| `microbiote-101` | Microbiote 101 | intestin, webinar | à voir |
| `energie-durable-quotidien` | Énergie durable au quotidien | energie, webinar | oui |
| `feedback-and-self-tracking` | Feedback and Self-Tracking | quick | oui |
| `how-nutrition-training-gut-recovery-and-nervous-system-work-together` | How Nutrition, Training, Gut, Recovery and Nervous System Work Together | — | à voir |
| `your-unique-terrain-roadmap` | Your Unique Terrain Roadmap | — | à voir |
| `hydration-sweat-and-recovery-journal-for-athletes` | Hydration, Sweat, and Recovery Journal for Athletes | — | à voir |
| `ballonnements-vraies-causes` | Ballonnements, les vraies causes | intestin, article | non (symptôme) |
| `reparer-son-intestin` | Réparer son intestin en 4 semaines | intestin, article | non (protocole) |
| `protocole-4r-intestin` | Protocole 4R intestin | intestin, protocol | non (protocole) |
| `plan-repas-reset-intestin` | Plan repas 7 jours Reset Intestin | intestin, recipe | non (plan de repas) |
| `reset-sucre-7-jours` | Reset sucre 7 jours | nutrition, protocol | non (protocole) |
| `reset-energie` | Reset Énergie | energie, protocol | non (protocole) |
| `jeune-intermittent-pour-qui` | Jeûne intermittent, pour qui | nutrition, article | non (jeûne) |
| `creatine-the-basics` | Creatine, the Basics | nutrition, supplement | non (complément) |
| `magnesium-lequel-choisir` | Magnésium, lequel choisir | nutrition, article | non (complément) |
| `fer-energie` | Fer & énergie, le lien caché | energie, article | non (carence) |
| `cortisol-poids` | Cortisol & poids | hormones, article | non (poids / hormones) |
| `comprendre-la-perimenopause` | Comprendre la périménopause | hormones, article | non (condition) |
| `soutien-perimenopause` | Soutien périménopause | hormones, protocol | non (condition) |
| `perimenopause-qr-alessandra` | Périménopause: Q&R avec Alessandra | hormones, webinar | non (condition) |
| `lire-ses-analyses` | Lire ses analyses | nutrition, video | non (analyses) |
| `comprendre-score-fonctionnel` | Comprendre ton Score Fonctionnel | nutrition, video | non (score) |

---

## Annexe D — Où tout cela vit dans le code (pour l'équipe technique)

| Sujet | Fichier |
|---|---|
| Types, valeurs fermées (`CARD_KINDS`, `CARD_PILLARS`, `CARD_SLOTS`, `CardLink`) | `clinical-dashboard/lib/action-cards/types.ts` |
| Limites de longueur (Zod) | `clinical-dashboard/lib/action-cards/schemas.ts` |
| Étapes (`cardSteps`), liens (`parseCardLinks`), conditions de publication (`publishBlockers`) | `clinical-dashboard/lib/action-cards/logic.ts` |
| Brouillon IA (consignes de rédaction côté CLINICAL) | `clinical-dashboard/lib/action-cards/draft.ts` |
| Enregistrer, publier, retirer, téléverser l'image | `clinical-dashboard/lib/action-cards/actions.ts` |
| Import JSON : validation (schéma import-v1), classement, lignes écrites | `clinical-dashboard/lib/action-cards/import.ts` (actions `previewActionCardImport`, `applyActionCardImport` dans `actions.ts` ; fenêtre `components/action-cards/import-cards-dialog.tsx`) |
| Éditeur et aperçu iPhone | `clinical-dashboard/components/action-cards/` |
| Page wiki du flux | `clinical-dashboard/docs/wiki/flows/action-cards.md` |
| Push du care plan vers l'app (`pushHabit`) | `clinical-dashboard/lib/care-plan/translator.ts` |
| Rendu iOS de la carte | `FunctionAlps-IOS/FunctionAlps/Sources/Features/Plan/ActionCardView.swift` |
| Modèle iOS (repli de langue, étapes, liens) | `FunctionAlps-IOS/FunctionAlps/Sources/Models/ActionCards.swift` |
| Fréquences RRULE comprises par l'app | `FunctionAlps-IOS/FunctionAlps/Sources/Models/Habits.swift` (`parseRule`, `isDue`) |
| Banque « Actions de base » | `FunctionAlps-IOS/FunctionAlps/Sources/Features/Plan/ActionBankView.swift`, `Models/PlanAccess.swift` |
| Focus du jour (priorités vers catégories) | `FunctionAlps-IOS/supabase/functions/_shared/focus/engine.ts` |
| Focus du jour (lecture des cartes publiées) | `FunctionAlps-IOS/supabase/functions/member-daily-focus/index.ts` |
| Sélecteur de carte des habitudes du patient (`CardSelect`) | `clinical-dashboard/components/patients/habits/habit-panel.tsx` |
| Rôles et permissions (`resources.write`, `resources.approve`) | `clinical-dashboard/lib/types/app.ts` (`ROLE_PERMISSIONS`) |
| Migrations | `FunctionAlps-IOS/supabase/migrations/20261002_action_cards.sql`, `20261002_action_cards_member_can_add.sql` |
