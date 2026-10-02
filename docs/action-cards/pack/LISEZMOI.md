# Pack « cartes action » — pour l'agent qui écrit le contenu

Ce pack montre **à quoi ressemble une carte action dans l'app iPhone FunctionAlps** et **quel champ
remplit quelle zone**, pour que l'agent écrive des textes qui tiennent à l'écran.

## Par où commencer

1. **`guide-redaction-cartes-action.md`** : le brief complet. Il explique ce qu'est une carte, détaille chaque champ, donne les règles de rédaction, le format JSON exact à livrer et un exemple complet. L'agent suit ce document.
2. **`banque-actions-inventaire.md`** : les 36 cartes qui existent aujourd'hui, l'idée derrière chacune, ce qui leur manque, et une cinquantaine d'idées de nouvelles cartes par pilier.
3. **`carte-action-anatomie.html`** : à ouvrir dans un navigateur. C'est une réplique interactive de la carte (largeur iPhone, vraies polices et couleurs de l'app), avec chaque zone numérotée et sa légende : colonne `habit_bank`, limite, règle EN/FR, et où le champ apparaît ailleurs.
   - On peut basculer EN/FR, la version Douce / Normale / Plus loin, une carte « routine » ou « respiration », et l'ouverture depuis le plan ou depuis la banque.
   - Le fichier est autonome et fonctionne hors ligne.
4. **`captures-app/`** : de **vraies captures du simulateur iPhone 16 Pro**, avec l'app en mode démonstration, sans aucune donnée réelle.
5. **`rendus/`** : des captures de la réplique HTML, pour qui ne peut pas ouvrir le fichier.
6. **`code/`** : le code source qui dessine la carte, pour lever tout doute.

## Les captures de l'app (`captures-app/`)

| Fichier | Ce qu'on voit |
|---|---|
| `20-card-top.png` / `-fr` | Une carte complète (« Morning circadian routine »), ouverte depuis les actions du jour : ligne type · moment · durée, titre, description, choix de version, lien YouTube, début des étapes |
| `21-card-middle.png` / `-fr` | La même carte, au milieu : « Comment faire », puis « Pourquoi dans votre plan », puis l'article de la bibliothèque |
| `22-card-bottom.png` / `-fr` | La fin de la carte : pourquoi, article, boutons « C'est fait » / « Pas aujourd'hui » |
| `23-card-breath.png` / `-fr` | Une carte **respiration**, ouverte depuis la banque : le cercle de respiration avec son minuteur, puis « Ajouter à mon plan » |
| `24-bank.png` / `-fr` | La banque « Actions de base » : les cartes que le membre peut ajouter lui-même, regroupées par pilier |
| `07b-action-card.png` | Une autre carte complète (« Strength session », mouvement, avec versions) |
| `01-today.png` | L'accueil : la ligne d'une action dans « Actions du jour », avec type · durée sous le titre |
| `07-care-plan.png` | « Mon plan de santé », où les actions s'inscrivent dans le plan du membre |

Les textes de démonstration se trouvent dans le fichier `ShowcaseData.swift` de l'app. Ce sont des
exemples rédigés pour la vitrine ; ils sont relus par un clinicien avant de servir de modèle.

## Les trois règles d'affichage à garder en tête

- **Champ vide, bloc absent.** Une carte sans étapes n'a pas de « Comment faire », une carte sans `general_why` n'a pas de « Pourquoi ».
- **Repli de langue champ par champ.** Un champ français vide affiche l'anglais, et inversement.
- **Le titre de la prescription passe avant celui de la carte.** Quand un clinicien prescrit l'action, c'est le titre de la prescription qui s'affiche. Le titre de la carte s'affiche quand le membre l'ouvre depuis la banque.

## Le code (`code/`)

| Fichier | Rôle |
|---|---|
| `ActionCardView.swift` | La page de la carte dans l'app (ordre des blocs, cercle de respiration, boutons) |
| `ActionCards.swift` | La fusion carte + prescription, la découpe des étapes, les liens, le repli FR/EN |
| `ActionBankView.swift` | La liste « Actions de base » |
| `action-card-preview.tsx` | L'aperçu iPhone de l'éditeur CLINICAL (`/action-cards`), où la clinicienne relit chaque carte avant publication |
