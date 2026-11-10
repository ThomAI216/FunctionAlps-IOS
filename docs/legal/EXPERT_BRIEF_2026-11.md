# Dossier pour la revue juridique : textes membres FunctionAlps, révision de novembre 2026

Préparé le 9 novembre 2026 pour la personne experte (droit suisse et européen de la
protection des données, de la santé et de la consommation) qui revoit les textes avant
leur publication.

Ce dossier est un document de travail, pas un avis juridique. Chaque affirmation de droit
porte sa source. Les points où nous avons besoin de votre jugement sont numérotés
**Q1, Q2…** et regroupés à la fin.

---

## 1. Contexte

- **Responsable du traitement :** Thomas Convent, entreprise individuelle (CHE-205.025.089),
  Crans-Montana (VS). FunctionAlps Sàrl est en cours de constitution.
- **Service :** application d'accompagnement nutritionnel et de mode de vie (iOS, web,
  tableau de bord membres). Elle est destinée aux adultes résidant en Suisse et dans l'EEE.
  Sont enregistrés les repas (photos), les bilans, les symptômes, les mesures d'objets
  connectés et des documents médicaux.
- **Praticienne :** thérapeute en médecine complémentaire en Valais, certifiée ASCA et
  inscrite au RME/EMR.
- **IA :**
  - Infomaniak (Genève) pour tout, sauf une étape.
  - OpenAI (États-Unis) pour reconnaître les aliments sur une photo ou une description de
    repas. En production, OpenAI estime aussi les nutriments à partir du seul nom de chaque
    aliment.
- **Hébergement :** Supabase dans l'UE (Stockholm) ; Vercel pour la distribution web.

**Ce qui a déclenché la révision.** Un membre a posé deux questions sur les textes en vigueur.

1. « Vous écrivez que ce n'est pas un dispositif médical au sens de l'ODim ou du
   règlement (UE) 2017/745. Je pensais que vous vouliez le marquage CE, et que collecter
   des résultats d'analyses médicales y était lié ? »
2. « Les documents sont conservés "pendant la durée exigée par la loi" : combien de temps ?
   Sans durée exacte, on peut vous le reprocher, et chaque élément a sa propre règle. »

Thomas a aussi demandé :
- de supprimer tous les tirets cadratins ;
- de vérifier le fondement juridique, y compris en droit européen ;
- de décrire plus précisément l'envoi des photos de repas à OpenAI.

## 2. Les textes et où les lire

Les versions publiées sont dans la base CM OS (`consent_definitions`). La copie de travail,
avec l'historique, est dans `docs/legal/texts/`.

| Document | En vigueur | Proposé | Type |
|---|---|---|---|
| Conditions d'utilisation | v9 | v10 | consentement, requis |
| Déclaration de confidentialité | v13 | v14 | notice |
| Comment l'IA est utilisée | v8 | v9 | notice |
| Consentement au traitement des données de santé | v7 | v8 | consentement, requis |
| Partage des documents médicaux | v2 | v3 | consentement, facultatif |
| Statistiques d'usage / Nouvelles et offres | v3 | v4 | consentements, facultatifs (un tiret chacun) |

La version française prévaut pour la Suisse romande et l'EEE francophone (CGU, §24).

Pour voir chaque changement : `git diff 0d57c02 -- docs/legal/texts`. La révision est
découpée en quatre commits : instantané, tirets, contenu, durées.

## 3. Ce qui change

### 3.1 Tirets cadratins

Les 300 tirets ont été supprimés sans modifier le sens :
- deux-points après les intitulés de liste ;
- parenthèses pour les incises ;
- virgule devant « par exemple », « notamment », « une seule fois ».

Les règles sont dans `tools/dedash.py`.

### 3.2 Dispositif médical et marquage CE (CGU §4)

- **Texte précédent :** une phrase qui n'expliquait rien.
- **Nouveau texte :**
  - Il cite la LPTh (RS 812.21), l'ODim (RS 812.213) et le MDR.
  - Il dit que l'absence de marquage CE est **un choix délibéré**, et non un manque.
  - Il ajoute un paragraphe sur les résultats d'analyses : FunctionAlps les conserve, les
    affiche, les transmet à l'équipe de soins et, avec un consentement séparé, les met en
    ordre par date sans les interpréter.
  - Il pose la règle de qualification : c'est la finalité, et non le type de données, qui
    fait le dispositif.

**Réponse à la question du membre.** Il n'a jamais été question de viser le marquage CE
pour ce service. Le positionnement voulu, documenté dans la note interne du 14.08.2026
(`FunctionAlps-CLINICAL/clinical-dashboard/docs/wiki/decisions/mdsw-boundary-2026-08-14.md`),
est de rester hors du champ des dispositifs médicaux. Conserver des résultats d'analyses ne
suffit pas à faire entrer un logiciel dans ce champ.

**Sources :**
- MDR, considérant 19 : « software intended for life-style and well-being purposes is not a
  medical device ».
- MDCG 2019-11 rév. 1 (juin 2025), étape 3 : un logiciel ne peut être un DM que s'il agit
  « beyond storage, archival, communication, simple search, lossless compression ».
- Swissmedic, fiche *Medical Device Software*, BW630_30_007 v3.0 (21.04.2026) : elle exclut
  les dossiers électroniques qui remplacent simplement le papier.
- Apposer le marquage CE sur un produit qui n'est pas un dispositif est interdit :
  MDR art. 20(2) avec le règlement 765/2008, art. 30(2) et 30(5).

### 3.3 OpenAI (nouvelle section 8b de la Déclaration ; CGU §8 ; note IA §5)

**Le flux, vérifié dans le code** (`supabase/functions/_shared/meals/meal-analysis.ts`,
`identify-parts.ts`) :

1. La photo est recompressée sur le téléphone, ce qui retire les métadonnées EXIF.
2. Nos serveurs envoient à OpenAI (Chat Completions) :
   - la photo, ou jusqu'à 4 photos ;
   - la description éventuelle ;
   - nos instructions.

   Ils n'envoient aucun nom, e-mail, identifiant de compte, paramètre `user` ni métadonnée,
   et l'IP envoyée est celle du serveur. La dictée vocale est transcrite chez Infomaniak ;
   l'audio ne va jamais chez OpenAI.
3. OpenAI répond par du JSON (plat, aliments, grammes, caractéristiques), sans donnée
   personnelle.
4. Nous rattachons la réponse au repas du membre, dans notre base UE.
5. Pour les nutriments, seul le nom de l'aliment est envoyé.

**Chez OpenAI** (documentation API « Your data ») :
- pas d'entraînement sur les données de l'API ;
- conservation jusqu'à 30 jours pour la détection d'abus ;
- pas de stockage applicatif (`store` vaut `false` par défaut) ;
- Zero Data Retention possible, sous réserve d'approbation ;
- les images signalées comme pédopornographiques restent conservées, même sous ZDR.

**Le texte ne dit volontairement pas « anonyme ».**
- Une photo peut montrer un visage, un document ou un lieu.
- La CJUE, C-413/23 P *EDPS c. SRB* (4.9.2025), admet qu'une donnée pseudonymisée peut ne
  pas être personnelle pour son destinataire. Elle rappelle toutefois que l'identifiabilité
  s'apprécie du point de vue du responsable, et que le destinataire doit être nommé dans
  l'information.
- Une photo de repas prise dans un suivi nutritionnel est vraisemblablement une donnée de
  santé : CJUE C-21/23 *Lindenapotheke* (4.10.2024), qui retient une conception large.
- Elle relève donc du consentement explicite (RGPD art. 9(2)(a) ; LPD art. 6 al. 7).

**Base du transfert.** OpenAI **n'est pas certifié** au Data Privacy Framework, ni UE-É.-U.,
ni Suisse-É.-U. (liste officielle consultée le 9.11.2026 : 0 résultat). L'annexe 1 de l'OPDo
ne couvre donc pas OpenAI. Le transfert repose sur les clauses contractuelles types de
l'accord de traitement d'OpenAI (LPD art. 16 al. 2 let. d ; RGPD art. 46). Le texte le dit
désormais.

### 3.4 Correction factuelle : origine des valeurs nutritionnelles

Les textes en vigueur disent que les nutriments viennent « des tables de référence, et non
de la mémoire du modèle » et sont estimés « par Infomaniak ». C'est faux en production.

- Depuis le 12.10.2026, réglage `MEAL_PRICING` : OpenAI estime les valeurs pour 100 g à
  partir du nom de l'aliment.
- C'est le cas de 122 repas sur les 30 derniers jours (`resolution_meta.pricing.source = 'openai'`).

Les textes proposés décrivent la réalité. L'autre option est de revenir aux tables (voir
P2 ci-dessous).

### 3.5 Durées de conservation exactes (CGU §17, Déclaration §13, consentement santé §7, partage de documents §4)

| Élément | Durée proposée | Fondement |
|---|---|---|
| Dossier tenu par la praticienne | 20 ans après la fin du suivi, puis destruction | LS VS (RS VS 800.1) art. 32 al. 2 : « au moins pendant 20 ans ». Il s'applique par analogie aux personnes exerçant la médecine complémentaire (art. 45 al. 1 let. e et al. 3). ASCA et RME n'imposent pas de durée. |
| Historique des consentements (sans donnée de santé) | 10 ans après la suppression du compte | Prescription de 10 ans : CO art. 127 (contractuel) et art. 60 al. 1 (délictuel, délai absolu) |
| Pièces comptables (si paiement) | 10 ans dès la fin de l'exercice | CO art. 958f al. 1 |
| Journaux de sécurité | 12 mois dès l'événement | OPDo art. 4 al. 5 : au moins 1 an, lorsque l'art. 4 s'applique |
| Données du compte après suppression | effacées sous 30 jours, sauf les éléments ci-dessus | Délai déjà en vigueur |
| Dictée vocale (app) | jamais stockée chez nous | Vérifié dans le code |
| Notes vocales (Analyses) | jusqu'à suppression de la note | Vérifié dans le code |

Les durées qui étaient déjà chiffrées sont inchangées : rapports 12 mois, auto-évaluations
12 mois, copies brutes des objets connectés 30 jours.

**Pourquoi un chiffre exact.**
- En droit suisse, la LPD art. 19 n'impose pas d'indiquer la durée dans l'information. Elle
  figure seulement dans le droit d'accès (art. 25 al. 2 let. d : « la durée de conservation…
  ou les critères »).
- Le RGPD, applicable aux membres de l'EEE (art. 3(2)(a)), exige à l'art. 13(2)(a) « la durée
  de conservation… ou, lorsque ce n'est pas possible, les critères ». Une formule comme
  « la durée exigée par la loi » ne donne ni la durée ni un critère utilisable.

## 4. Points que nous n'avons pas pu trancher, ou qui demandent une action

### Préalables avant publication (côté FunctionAlps)

- **P1. Accord de traitement avec OpenAI.**
  - Il doit être conclu, avec ses clauses contractuelles types : le texte affirme qu'il
    existe. Le contractant, pour la Suisse et l'EEE, serait OpenAI Ireland Ltd selon des
    sources secondaires, à vérifier sur le contrat.
  - Il faut aussi une **évaluation de l'impact du transfert** (TIA ; recommandations EDPB
    01/2020).
- **P2. Choisir la source des nutriments.** Soit garder OpenAI (le texte proposé le dit),
  soit régler `MEAL_PRICING=database` et revenir à la promesse « tables de référence ».
- **P3. Vérifier les métadonnées sur Android.** L'app Expo utilise `exif: false` et
  `quality: 0.4`. Il faut contrôler sur un vrai fichier Android que les données GPS
  disparaissent ; sur iOS natif, c'est vérifié dans le code.
- **P4. Sauvegardes.** « Effacé sous 30 jours » ne mentionne pas les sauvegardes Supabase
  (durée selon le plan). Il faut les ajouter ou confirmer qu'elles expirent dans ce délai.
- **P5. Représentant dans l'UE (RGPD art. 27).**
  - Il est requis. L'exemption de l'art. 27(2)(a) suppose un traitement « occasionnel » ;
    or un service de santé traite ces données régulièrement (lignes directrices EDPB 3/2018).
  - Aucun représentant n'est désigné. Une fois désigné, il faut le nommer à la §2 de la
    Déclaration.

### Questions pour vous

- **Q1. Frontière des dispositifs médicaux.** Le texte est-il défendable au regard des
  fonctions réelles ? Les plus proches de la frontière :
  - La note IA §1 dit que l'IA « relie ce que vous mangez à ce que vous déclarez ressentir
    au fil du temps » et « détecte des tendances ». Notre propre note du 14.08.2026 classe
    les relations inférées en zone ambre ou rouge.
  - Le bilan quotidien comporte six questions « red flag ». Si l'une est cochée, le membre
    voit une orientation vers un médecin et un événement `red_flag` remonte côté praticienne.
  - Les scores de repas, d'énergie et de sommeil.
  - Les interprétations des rapports périodiques, revues par la praticienne.
  - La mise en ordre des documents médicaux par l'IA (valeurs et normes du laboratoire,
    sans interprétation).

  La finalité se lit aussi dans le site et le marketing : faut-il un audit de ces textes ?
- **Q2. Cohérence sur les signalements.** Les CGU (§4 et §5) disent qu'« aucune alerte n'est
  déclenchée » et que les signalements « n'alertent personne ». Pourtant un événement
  `red_flag` remonte côté praticienne (Déclaration §10 : « un résumé peut être examiné »).
  Faut-il reformuler, par exemple : « peut apparaître dans le dossier vu par votre
  praticienne, mais personne ne le surveille en temps réel et aucune réponse n'est
  garantie » ?
- **Q3. Durée de 20 ans.**
  - L'art. 32 LS s'applique-t-il bien à une thérapeute complémentaire via l'art. 45 al. 3 ?
    Une confirmation auprès du Service de la santé publique serait utile.
  - L'art. 32 ne fixe pas de point de départ : en retenant « fin du suivi », sommes-nous
    corrects ?
  - La loi prévoit aussi une conservation plus longue tant que le dossier « présente un
    intérêt pour la santé du patient » : faut-il le mentionner ?
- **Q4. Rôles.** La praticienne est-elle responsable distincte, coresponsable (RGPD art. 26)
  ou sous-traitante, pour le dossier qu'elle tient dans les outils FunctionAlps ? Les textes
  disent « conservé par elle, séparément de votre compte ».
- **Q5. Dix ans pour la preuve des consentements.** Est-ce proportionné (RGPD art. 5(1)(e) ;
  LPD art. 6 al. 4) ? Ou faut-il retenir une durée plus courte, ou plus longue, alignée sur
  les 20 ans des lésions corporelles (CO art. 60 al. 1bis, 128a) ?
- **Q6. For et consommateurs.**
  - Les CGU §25 fixent le for en Valais.
  - Pour un consommateur suisse, le CPC (art. 32 et 35) l'empêche de renoncer d'avance à
    son for.
  - Pour un consommateur de l'EEE, la Convention de Lugano (art. 15 à 17) ne permet au
    professionnel d'agir qu'au domicile du consommateur.

  Faut-il réécrire la clause ? Même question pour le plafond de responsabilité de 500 CHF
  (§19), au regard de la directive 2019/770. Son art. 3(1) vise les services « payés » en
  données, sauf si les données servent exclusivement à fournir le service.
- **Q7. AI Act (règlement 2024/1689).**
  - Le service n'est pas à haut risque (art. 6, annexe III), tant qu'il n'est pas un
    dispositif médical.
  - L'art. 50(1) s'applique depuis le 2.8.2026 si un membre converse avec une IA : faut-il
    une mention dédiée ? Le code mentionne une fonction `chatbot-message` ; il reste à
    vérifier si un chat IA est réellement proposé aux membres.
  - L'art. 4 (maîtrise de l'IA) a été réécrit par le règlement (UE) 2026/1744.
- **Q8. Analyses d'impact.** Faut-il une AIPD (RGPD art. 35 ; LPD art. 22) et un règlement
  de traitement (OPDo art. 5) pour un traitement de données sensibles à grande échelle ?
  Nous n'en avons pas trouvé dans les dépôts.
- **Q9. Résidence des données dans l'UE.** OpenAI propose une région « Europe (EEE +
  Suisse) » (eu.api.openai.com), avec traitement en Europe. Elle exige une approbation
  commerciale et, pour les images, un ZDR ou une surveillance des abus « renforcés ». Le
  transfert vers les États-Unis disparaîtrait. Recommandez-vous d'en faire une condition ?
- **Q10. Nouvelle acceptation.** Publier fait accepter à nouveau les CGU et le consentement
  santé à chaque membre. Faut-il aussi relancer les deux consentements facultatifs pour un
  seul tiret ?

## 5. Sources

- LS VS, RS VS 800.1, art. 32, 45, 46 : https://lex.vs.ch/app/fr/texts_of_law/800.1
- OEx LS, RS VS 811.100, art. 29 : https://lex.vs.ch/app/fr/texts_of_law/811.100
- CO, RS 220, art. 60, 127, 128a, 957, 958f : https://www.fedlex.admin.ch/eli/cc/27/317_321_377/fr
- LPD, RS 235.1, art. 6, 16, 19, 22, 25 : https://www.fedlex.admin.ch/eli/cc/2022/491/fr
- OPDo, RS 235.11, art. 4, 5, annexe 1 : https://www.fedlex.admin.ch/eli/cc/2022/568/fr
- ODim, RS 812.213 : https://www.fedlex.admin.ch/eli/cc/2020/552/fr
- RGPD 2016/679 : https://eur-lex.europa.eu/eli/reg/2016/679/oj
- EDPB, lignes directrices 3/2018 (champ territorial)
- MDR 2017/745 ; MDCG 2019-11 rév. 1 (juin 2025) ; Swissmedic BW630_30_007 v3.0
- Règlement 765/2008, art. 30
- AI Act 2024/1689 ; règlement (UE) 2026/1744 (« Omnibus numérique IA »)
- EHDS 2025/327, art. 47 : sans objet, sauf revendication d'interopérabilité avec un DPI
- Directive 2019/770 ; Bruxelles I bis, art. 17 et 18 ; Rome I, art. 6 ; règlement 2024/3228
  (abrogation de la plateforme RLL au 20.7.2025)
- CJUE C-413/23 P (4.9.2025) ; C-21/23 (4.10.2024)
- OpenAI, « Your data » et référence de l'API Chat Completions ; liste DPF :
  https://www.dataprivacyframework.gov/list

Les recherches ont été faites le 9 novembre 2026. La convention de Lugano et le contractant
OpenAI n'ont pas pu être vérifiés sur une source officielle.
