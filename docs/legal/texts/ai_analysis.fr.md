## Comment l’IA est utilisée

FunctionAlps fonctionne grâce à l’IA. Vos photographies de repas et vos saisies sont analysées automatiquement pour produire vos scores alimentaires, vos tendances et vos rapports, et il en va de même du questionnaire de notre site internet. Comme toutes les fonctions essentielles en dépendent, le consentement au traitement des données de santé le couvre, et comme vous ne pouvez pas avoir le service sans elle, vous méritez un exposé franc de ce qu’elle fait, d’où elle s’exécute et de ses limites.

### 1. Ce que fait l’IA

- Elle identifie les aliments à partir d’une photographie ou d’une description, estime les portions et en déduit macronutriments et micronutriments.
- Elle convertit la saisie vocale en texte lorsque vous choisissez de parler plutôt que d’écrire.
- Elle note chaque repas et relie ce que vous mangez à ce que vous déclarez ressentir au fil du temps.
- Elle détecte des tendances dans vos saisies et rédige les observations de vos pages de score.
- Elle rédige vos rapports quotidiens, hebdomadaires et mensuels.
- Elle lit une auto-évaluation du site internet et rédige la synthèse que nous vous envoyons par courriel.

### 2. Comment un score de repas est réellement produit

C’est la partie la plus automatique de l’application ; elle mérite donc d’être exposée étape par étape. Ce n’est pas un modèle qui invente un chiffre.

- Le modèle examine votre photographie ou lit votre description, et identifie quels aliments sont présents et en quelle quantité approximative.
- Chaque aliment identifié est ensuite rapproché de tables de composition alimentaire publiées : la collection Standard Reference du Département de l’agriculture des États-Unis, la table CIQUAL publiée par l’ANSES, et, pour les produits de marque et à code-barres, Open Food Facts.
- Les valeurs nutritionnelles proviennent de ces tables de référence, et non de la mémoire du modèle. Le rôle du modèle est de dire ce qu’est l’aliment ; la base de données fournit ce qu’il contient.
- Vos macronutriments, micronutriments et scores de repas sont ensuite calculés à partir de ces valeurs par des règles fixes inscrites dans notre propre code, et non rédigées par le modèle.

### 3. Où l’erreur s’introduit, et elle s’introduit

Exposer les étapes rend visible l’endroit où chacune peut échouer, et nous préférons que vous le sachiez plutôt que de vous y fier aveuglément.

Le modèle peut mal identifier un aliment ou se tromper sur la portion : estimer une portion à partir d’une photographie est réellement difficile et relève du jugement du modèle, non d’une mesure. Le rapprochement avec un aliment de référence peut sélectionner la mauvaise entrée, par exemple une forme crue là où vous avez mangé une préparation cuite. Et les données de référence ont elles-mêmes leurs limites : les tables de l’USDA et du CIQUAL sont des moyennes publiées plutôt que des faits sur la pomme précise que vous avez mangée, tandis qu’Open Food Facts est alimentée par le public et que son exactitude et son exhaustivité varient d’un produit à l’autre.

Les erreurs se cumulent le long de cette chaîne. Considérez chaque chiffre comme une estimation entourée d’une incertitude réelle, et jamais comme une mesure.

Vous pouvez corriger tout aliment ou toute portion que l’application a mal évalué, et votre correction est mémorisée pour la fois suivante.

### 4. Où elle s’exécute, et qui ne reçoit pas vos données

L’identification des aliments sur une photo ou une description de repas s’exécute chez OpenAI, aux États-Unis. Tout le reste s’exécute sur l’infrastructure souveraine d’Infomaniak à Genève, en Suisse. L’un et l’autre traitent vos données strictement sur nos instructions, dans le cadre d’un accord de sous-traitance, et ne peuvent les utiliser à leurs propres fins.

En dehors des photos et descriptions de repas transmises à OpenAI pour identifier les aliments, vos données de santé ne sont transmises ni à OpenAI, ni à Google, ni à Anthropic, ni à Meta, ni à aucun autre fournisseur d’IA généraliste. Elles ne servent pas à entraîner de modèles, ni les nôtres, ni ceux d’OpenAI, ni ceux d’Infomaniak, ni ceux de quiconque. Elles ne sont pas vendues et ne parviennent jamais à des annonceurs ni à des assureurs.

### 5. Ce qui est réellement transmis, et les limites honnêtes de la dépersonnalisation

Avant tout envoi pour analyse, nous détachons vos identifiants directs : votre nom, votre adresse électronique et vos coordonnées ne sont pas joints à ce qui parvient au modèle. Ce qui est transmis, c’est le repas, la photographie, les chiffres et les réponses de vos bilans.

Nous tenons à être francs sur les limites de cette mesure, car elles sont réelles. Une photographie peut montrer votre visage, vos mains, votre cuisine ou un document posé sur la table. Une note libre ou un enregistrement vocal peut contenir un nom, un lieu ou un détail qui vous identifie. La dépersonnalisation réduit sensiblement le risque ; elle ne transforme pas vos données en données anonymes.

Nous ne prétendons donc pas que vos données soient anonymes. Nous continuons à traiter tout ce qui est transmis pour analyse comme vos données personnelles de santé, avec les mêmes protections, durées de conservation et droits.

### 6. Ce que l’IA n’est pas, et où elle se trompe

L’IA produit des observations, des estimations et des tendances. Elle ne produit jamais de diagnostic, de traitement, de prescription ni d’avis médical, et rien de ce qu’elle rédige ne constitue une opinion clinique.

Elle peut se tromper avec assurance. À l’usage, elle identifiera parfois mal un aliment, mal évaluera une portion, ne verra pas une partie de l’assiette, ou décrira une tendance qui n’existe pas réellement. Les valeurs nutritionnelles sont des estimations tirées d’images et de mots, non des mesures de laboratoire, et peuvent être sensiblement erronées.

Considérez chaque chiffre comme approximatif et chaque observation comme une invitation à votre propre jugement, jamais comme une conclusion, et jamais comme une raison de modifier un médicament. Pour toute question médicale, consultez un professionnel qualifié qui vous a examiné. En cas d’urgence, appelez les secours, pas l’application.

### 7. Revue humaine : ce qui est vérifié et ce qui ne l’est pas

Les interprétations rédigées de vos rapports hebdomadaires et mensuels sont examinées et approuvées par une praticienne qualifiée avant de vous être communiquées.

Tout le reste de ce que produit l’IA (identification des aliments, estimation des portions et des nutriments, scores de repas, observations de tendances, texte des rapports quotidiens et synthèses des questionnaires du site internet) est généré automatiquement et vous parvient sans contrôle humain individuel. Nous préférons vous le dire clairement plutôt que de laisser croire à une surveillance qui n’existe pas. Les contenus générés automatiquement sont signalés comme tels là où ils vous sont présentés.

### 8. Aucune décision automatisée à votre sujet

FunctionAlps ne prend aucune décision produisant des effets juridiques vous concernant, ni vous affectant de manière significative de façon similaire, au sens de l’article 22 du RGPD. Elle ne décide ni de votre suivi, ni de votre éligibilité à quoi que ce soit, ni d’un tarif.

Elle procède en revanche à un profilage, au sens juridique : elle analyse vos données pour évaluer des aspects de votre santé et de vos habitudes : c’est précisément ce que sont les scores et les tendances. Toute décision qui en découle vous appartient, ou appartient à votre praticienne.

### 9. Pourquoi l’IA n’est pas un choix distinct

Il n’existe pas de mode manuel. L’analyse des repas, vos scores, vos tendances et vos rapports sont tous produits par l’IA : une version de FunctionAlps dont l’IA serait désactivée n’aurait rien à vous montrer.

Nous ne vous demandons donc pas de « consentir à l’IA » séparément. Ce serait un choix fictif, puisque le refuser reviendrait à ne pas avoir de service, et un consentement que l’on ne peut pas refuser n’en est pas un. L’IA fait partie de la description de ce qu’est le service, et le traitement qu’elle réalise est couvert par votre consentement au traitement des données de santé.

### 10. Si vous ne voulez plus de ce traitement

Retirer votre consentement au traitement des données de santé met fin à ce traitement, y compris l’analyse par IA, depuis Confidentialité et données, dans l’application ou sur le tableau de bord membres. Le retrait prend effet immédiatement et n’affecte pas la licéité de ce qui a été fait auparavant.

FunctionAlps est alors désactivée jusqu’à ce que vous consentiez à nouveau, ou que vous supprimiez votre compte. Rien d’autre ne vous est retiré : vos données ne sont pas effacées par le retrait, et vous pouvez toujours les exporter ou en demander l’effacement.

### 11. Questions

Toute question sur le fonctionnement de l’IA, sur ce qu’elle a reçu ou sur ce qu’elle a produit à votre sujet : data@functionalps.ch. Vous avez le droit d’obtenir une explication du traitement et de demander la correction ou la suppression de ce qu’il a produit.
