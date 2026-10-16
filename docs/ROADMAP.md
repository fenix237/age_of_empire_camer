# Les Royaumes du Fleuve — Roadmap complète

> Complète `docs/ANALYSE.md`. Chaque phase se termine par un **jalon jouable** et une **porte de sortie** (critères mesurables). On ne commence pas la phase N+1 tant que la porte de la phase N n'est pas franchie.
> Les durées sont des estimations pour un développeur travaillant avec Claude Code, à temps plein. Divisez la cadence par 2 si c'est à temps partiel.

## Vue d'ensemble

| Phase | Nom | Durée | Jalon jouable | Cumul |
|---|---|---|---|---|
| 0 | Fondations & outillage | 1–2 sem. | Fenêtre vide sur Windows + Android, CI verte | 2 sem. |
| 1 | Noyau de simulation | 3–4 sem. | Simulation headless, tests, déterminisme | 6 sem. |
| 2 | Rendu isométrique & caméra | 3 sem. | Carte iso navigable, sprites placeholder | 9 sem. |
| 3 | Unités, mouvement, sélection | 4 sem. | Sélectionner une unité, cliquer, elle va | 13 sem. |
| 4 | Économie & construction | 4 sem. | Récolter, construire, produire | 17 sem. |
| 5 | Combat, âges, pouvoirs, héros | 6 sem. | Bataille complète entre 2 camps | 23 sem. |
| 6 | IA & escarmouche | 5 sem. | Partie complète contre l'ordinateur | 28 sem. |
| 7 | Campagne (7 missions) | 7 sem. | Campagne de bout en bout | 35 sem. |
| 8 | Village persistant & raids | 6 sem. | Boucle méta complète | 41 sem. |
| 9 | Contenu, art, audio, i18n | 6 sem. | Habillage final | 47 sem. |
| 10 | Stabilisation & bêta | 5 sem. | Zéro bloquant sur 6 appareils | 52 sem. |
| 11 | Publication v1.0 | 2 sem. | Installateur Windows + APK/AAB | ≈ 54 sem. |

**Environ 12–13 mois.** Il est plus sûr de prévoir 15 mois.

---

## Règles transversales (valables dans toutes les phases)

1. **Définition de « terminé »** pour toute tâche : code + tests + documentation courte + `flutter analyze` propre + exécuté sur Windows **et** un appareil Android réel.
2. **Aucun gameplay dans l'UI** : tout passe par la simulation et les commandes.
3. **Toute constante de gameplay dans le JSON.**
4. **Tout bug corrigé = un test de non-régression.**
5. **Chaque fin de phase** : tag Git `phase-N`, CHANGELOG, build installable, session de test de 30 min, revue complète du code (`/code-review`).
6. **Mesure des performances à chaque phase** (FPS, mémoire, temps de tick) consignée dans `docs/PERF.md`.
7. **Gel des fonctionnalités** pendant les 3 derniers jours de chaque phase : stabilisation uniquement.
8. **Mise à jour des dépendances uniquement entre deux phases.**

---

## Phase 0 — Fondations & outillage (1–2 sem.)

**Objectif** : une base propre sur laquelle rien ne bouge ensuite.

Tâches
- [ ] Vérifier la chaîne : Flutter 3.41, Dart, Android Studio + SDK, Visual Studio (charge de travail C++ de bureau), émulateur + un téléphone réel en mode développeur.
- [ ] Nettoyer le projet généré (retirer web/ios/macos/linux de `flutter create` si non utiles, ou les laisser inactifs).
- [ ] `pubspec.yaml` : flame, riverpod, path_provider, window_manager, flame_audio, tests ; verrouillage des versions.
- [ ] `analysis_options.yaml` strict (`very_good_analysis`, `strict-casts`, `strict-raw-types`, `strict-inference`), règles contre `print`.
- [ ] Arborescence `lib/sim`, `lib/game`, `lib/ui`, `lib/meta` (voir Analyse §3.5).
- [ ] Test d'architecture : `lib/sim` n'importe pas Flutter/Flame (script `tool/check_arch.dart`).
- [ ] CI GitHub Actions : analyze, format, test, build Windows, build Android.
- [ ] Gestion d'erreurs globale + journal local fichier.
- [ ] Fenêtre Windows (taille mini, plein écran), orientation paysage Android, aucune permission Internet dans le manifeste.
- [ ] Squelette de menu principal (Jouer / Options / Quitter) ; écran de chargement.
- [ ] Documentation : `docs/CONTRIBUTING.md` (conventions), `docs/DECISIONS.md` (journal des décisions d'architecture).
- [ ] Configuration `.gitignore` (build/, .dart_tool/, clés de signature).

**Porte de sortie**
- L'application se lance sur Windows et sur un téléphone Android réel, CI verte, `flutter analyze` à 0 avertissement.

---

## Phase 1 — Noyau de simulation (3–4 sem.)

**Objectif** : un monde qui tourne sans écran, déterministe, testé.

Tâches
- [ ] `FixedPoint` (entiers 1/256), vecteurs, distances entières, table trigonométrique, racine entière.
- [ ] `Rng` déterministe (xorshift128+ ou PCG) avec états sérialisables.
- [ ] `World` : entités (IDs stables), registres, tick fixe 10 Hz, ordre de résolution déterministe.
- [ ] Chargeur de définitions JSON (`UnitDef`, `BuildingDef`, `ResourceDef`, `AgeDef`) avec **validation de schéma** (erreur claire si donnée invalide).
- [ ] Carte logique : terrain, hauteurs, grille d'occupation, ressources.
- [ ] Générateur de cartes procédural déterministe + validation de connexité + garantie de ressources de départ.
- [ ] File de commandes + validation + journal de commandes (pour replays).
- [ ] Hash d'état (par seconde) et outil `tool/replay` qui rejoue un journal et compare.
- [ ] Sérialisation d'état (sauvegarde/chargement) de base, format versionné + CRC.
- [ ] Framework d'invariants (Analyse §13.2) exécuté après chaque tick en debug.
- [ ] Tests unitaires + premiers tests de propriétés (commandes aléatoires).

**Porte de sortie**
- Test de déterminisme : 1 000 graines × 10 000 ticks avec commandes aléatoires, mêmes hashes entre deux exécutions et entre Windows et Android (test de hash croisé via un fichier de référence).
- Génération de 10 000 cartes sans carte invalide.
- Couverture de `sim/` ≥ 90 %.

---

## Phase 2 — Rendu isométrique & caméra (3 sem.)

**Objectif** : voir le monde, le parcourir et choisir une case précisément.

Tâches
- [ ] Projection iso et picking inverse (propriété `screenToTile(tileToScreen(p)) == p`).
- [ ] Rendu du terrain par chunks mis en cache ; transitions entre terrains (auto-tiling).
- [ ] Rendu des ressources, bâtiments (placeholders), unités (placeholders animés minimalement).
- [ ] Tri de profondeur robuste (grands bâtiments) + tests golden.
- [ ] Caméra : glisser, bords d'écran, WASD/flèches, zoom molette / pincement, bornes de carte, inertie optionnelle.
- [ ] Mini-carte (terrain + entités + vue), clic pour déplacer la caméra.
- [ ] Brouillard de guerre (3 états) lié à la vision de la simulation.
- [ ] Interpolation de rendu entre ticks.
- [ ] Mode debug : grille, FPS, coordonnées, occupation.
- [ ] Système d'atlas + chargeur d'assets abstrait (clé → sprite), pour changer les assets sans toucher au code.
- [ ] Gestion cycle de vie : pause auto en arrière-plan / perte de focus.
- [ ] Mesure de performance sur appareil bas de gamme.

**Porte de sortie**
- Carte 128×128 avec 2 000 entités fixes + 200 mobiles à ≥ 60 FPS sur le PC, ≥ 45 FPS sur Android milieu de gamme, ≥ 30 FPS sur le plus faible appareil.
- Tests golden de tri de profondeur verts.

---

## Phase 3 — Unités, mouvement, sélection (4 sem.)

**Objectif** : le cœur « Age of Empires » : sélectionner, cliquer, obéir.

Tâches
- [ ] Sélection : clic, rectangle, Maj+clic, double-clic, groupes de contrôle, touche « villageois inactifs ».
- [ ] Interactions tactiles équivalentes (appui, glisser-sélection, mode multi-sélection), tolérance de toucher.
- [ ] Ordre contextuel (sol → déplacer, ressource → récolter, ennemi → attaquer, bâtiment → garnison/réparer).
- [ ] Marqueur visuel de destination, lignes de chemin, feedback d'ordre.
- [ ] Pathfinding : A* + grille d'occupation, replanification sur obstacle, file d'attente par tick.
- [ ] Flow field pour les groupes, HPA* pour les grandes cartes.
- [ ] Évitement local (séparation, glissement), gestion d'impasses et téléportation de secours.
- [ ] Formations simples, vitesse du groupe alignée.
- [ ] Files d'ordres (waypoints) via Maj+clic droit et bouton « file ».
- [ ] États d'unité en machine à états testée (transitions autorisées).
- [ ] Stances (agressif / défensif / passif / suivre).
- [ ] Tests : stress 500 unités, couloirs étroits, impasses, cibles inaccessibles, bâtiment posé sur le chemin.

**Porte de sortie**
- 200 unités envoyées dans un goulot d'étranglement en < 2 ms moyen de pathfinding par frame, aucune unité bloquée plus de 5 s, 1 000 scénarios aléatoires de mouvement sans violation d'invariant.

---

## Phase 4 — Économie & construction (4 sem.)

**Objectif** : une économie complète, un village qui grandit.

Tâches
- [ ] Récolte (nourriture, bois, pierre, fer, or), capacité de portage, dépôt automatique au plus proche.
- [ ] Gestion de l'épuisement d'une ressource et recherche automatique de la suivante.
- [ ] Construction : aperçu fantôme, validation de placement, progression, multi-constructeurs, annulation/remboursement.
- [ ] Bâtiments d'économie : centre-ville, huttes, grenier, camp, carrière, mine, champ, marché (échange).
- [ ] Production d'unités : files, point de ralliement, annulation, plafond de population.
- [ ] Recherches (forge) : améliorations de récolte et de stockage.
- [ ] Réparation, suppression de bâtiments (avec confirmation).
- [ ] HUD complet : ressources, panneau de sélection, actions, files, alertes, villageois inactifs.
- [ ] Gestion des cas limites de l'Analyse §13.3 (économie, construction).
- [ ] Tests de propriétés : conservation des ressources, aucun négatif, remboursements exacts.
- [ ] Sauvegarde/chargement d'une partie en cours (premier test de bout en bout).

**Porte de sortie**
- Une partie « économie seule » de 30 min jouable sans bug, sauvegarde → chargement identique (hash), 5 000 parties headless aléatoires sans violation.

---

## Phase 5 — Combat, âges, pouvoirs, héros (6 sem.)

**Objectif** : la profondeur du jeu.

Tâches
- [ ] Combat : mêlée, distance, projectiles, armure, bonus par catégorie, acquisition de cibles, poursuite, abandon.
- [ ] Vision, élévation, bonus de hauteur.
- [ ] Bâtiments militaires : caserne, écurie, forge, chantier naval, tours, remparts, portes, forteresse.
- [ ] Siège : catapultes, dégâts aux bâtiments, effondrement.
- [ ] Garnison (tour, bâtiment), évacuation.
- [ ] Navires et combat naval, débarquement, eau peu profonde.
- [ ] **Âges** : Palais, recherche de changement d'âge, déblocages, bonus.
- [ ] **Pouvoirs d'unités** (système d'effets : étourdissement, ralentissement, zone, buffs, auras) avec règles anti-cumul.
- [ ] **Héros** (4 + Kaba), autel, résurrection, ultimes.
- [ ] **Sorts de bataille** et jauge « tambour ».
- [ ] Effets visuels et sonores minimaux (indicateurs de portée, zones, cooldown).
- [ ] Tableau de test d'équilibre initial (`tool/balance_sim` prototype).
- [ ] Conditions de victoire / défaite et écran de fin.
- [ ] Tests : double mort simultanée, projectile sur cible morte, friendly fire, plafonds d'effets.

**Porte de sortie**
- Toutes les unités et tous les pouvoirs déclarés dans la donnée sont couverts par au moins un test.
- 5 000 combats aléatoires headless : zéro exception, zéro blocage, aucune unité immortelle ni effet persistant après la mort.

---

## Phase 6 — IA & escarmouche (5 sem.)

**Objectif** : une partie complète en solo contre l'ordinateur.

Tâches
- [ ] Architecture IA (stratège, économie, militaire, tactique) utilisant les mêmes commandes que le joueur.
- [ ] Priorités du scénario + composition d'armée adaptative + usage des pouvoirs et du héros.
- [ ] Personnalités par clan.
- [ ] 3 niveaux de difficulté (bonus Difficile affiché à l'écran).
- [ ] Chien de garde anti-blocage de l'IA.
- [ ] Menu escarmouche : carte (taille/type/graine), clan, nombre d'IA, difficulté, conditions de victoire, ressources de départ, vitesse.
- [ ] 4 clans jouables avec unités et bonus de civilisation uniques.
- [ ] Mode spectateur IA contre IA (outil de test et de démonstration).
- [ ] Statistiques de fin de partie.
- [ ] **Simulation de masse nocturne** : IA contre IA, tous clans/cartes.
- [ ] Première passe d'équilibrage à partir des statistiques.

**Porte de sortie**
- 5 000 parties headless sans blocage, durée moyenne dans la cible, taux de victoire entre 45 % et 55 % par clan en miroir.
- Trois personnes extérieures terminent une partie escarmouche sans aide.

---

## Phase 7 — Campagne (7 sem.)

**Objectif** : le scénario complet.

Tâches
- [ ] Moteur de missions JSON : objectifs, déclencheurs, vagues, dialogues, états d'objectifs, scripts d'événements.
- [ ] Validateur de missions en CI (références, accessibilité, ressources suffisantes).
- [ ] Interface de dialogue, portraits, écran de briefing et de fin, carte du royaume pour la progression.
- [ ] Mission 1 (tutoriel interactif avec invites contextuelles), puis 2 à 7 dans l'ordre.
- [ ] Contenu spécifique : vagues (M2), villages à protéger (M3), mines et embuscade (M4), caravane et escorte (M5), duel d'armées (M6), siège et boss (M7).
- [ ] Récompenses entre missions (déblocage d'unités et de bâtiments), fins multiples.
- [ ] Sauvegarde en cours de mission, reprise, rejouabilité, étoiles de performance.
- [ ] Trois difficultés par mission.
- [ ] Défi quotidien (carte fixée par graine de date locale) — version simple.
- [ ] Tests de campagne automatisés : un « bot » termine chaque mission à partir d'un script de commandes (test de bout en bout).

**Porte de sortie**
- Les 7 missions terminables par le bot scripté et par un testeur humain, chacune testée sur 3 sessions humaines.
- Aucun objectif impossible (validateur).

---

## Phase 8 — Village persistant & raids (6 sem.)

**Objectif** : la boucle « Clash of Clans ».

Tâches
- [ ] Modèle du village (carte 40×40, bâtiments, niveaux, stockages, production passive).
- [ ] Système de temps robuste (Analyse §11.2) : plafonds, monotonicité, horloge modifiée, tests dédiés.
- [ ] Améliorations avec timers + monnaie gagnée en jeu pour accélérer.
- [ ] Laboratoire : niveaux d'unités qui influencent les stats en partie (appliqués via la donnée, non via du code).
- [ ] Héros améliorables et déblocables, autel du village.
- [ ] **Raid attaquant** : constitution d'armée, sorts, villages IA générés (40 types), étoiles, butin.
- [ ] **Raid défenseur** : simulation hors écran à l'ouverture, rapport de raid, pertes plafonnées.
- [ ] Trophées et paliers de difficulté.
- [ ] Liaison avec escarmouche et campagne : gains vers le village.
- [ ] Migration de sauvegarde de profil ; tests sur sauvegardes historiques.
- [ ] Équilibrage du village (coûts, temps, rendements) par simulation de progression sur 60 jours.

**Porte de sortie**
- Simulation de 60 jours de jeu automatique : aucune ressource négative, aucune boucle de gain infinie, pas d'impasse de progression.
- Changement d'horloge en test (−1 an, +10 ans, fuseau) : aucun crash, aucun gain illimité.

---

## Phase 9 — Contenu, art, audio, localisation (6 sem.)

**Objectif** : habiller sans toucher au gameplay.

Tâches
- [ ] Choix du ou des packs d'assets, vérification de licence, remplissage de `ASSETS_LICENSES.md`.
- [ ] Remplacement des placeholders (terrain, bâtiments, unités, effets), teinte par joueur.
- [ ] Animations (marche, attaque, récolte, mort) en 5 directions + miroir.
- [ ] Portraits, illustrations de menu et de campagne, icônes de pouvoirs et de HUD.
- [ ] Musique par âge, ~120 effets sonores, mixage, réglages volumes.
- [ ] Textes en fichiers `.arb` : FR et EN, relecture, polices complètes.
- [ ] Options : graphismes (qualité auto), contrôles configurables, accessibilité (daltonisme, échelle d'interface).
- [ ] Succès (optionnel local).
- [ ] Écran « Crédits » et notices de licence.
- [ ] Optimisation mémoire des atlas, mesure à nouveau des performances.

**Porte de sortie**
- Aucune donnée ni asset manquant (test automatique : chaque clé d'asset référencée existe).
- Budget mémoire respecté sur le plus faible appareil.
- Test de lecture de tous les textes en FR et EN sans débordement d'interface (golden aux deux langues).

---

## Phase 10 — Stabilisation & bêta (5 sem.)

**Objectif** : fiabilité maximale. Aucune nouvelle fonctionnalité.

Tâches
- [ ] Sessions de test planifiées : matrice appareils (3 téléphones, 1 tablette, 2 PC dont un faible), scénarios de l'Analyse §13.3 déroulés un par un et cochés.
- [ ] Test de soak : 4 h de jeu continu, mémoire stable, pas de fuite.
- [ ] Tests de cycle de vie Android : appel entrant, retour, rotation, tuage par le système, économie d'énergie, stockage presque plein.
- [ ] Tests Windows : veille, changement de moniteur / DPI, perte de focus, fermeture brutale pendant sauvegarde.
- [ ] Fuzzing d'entrées (clics/touches aléatoires pendant des heures) sans crash.
- [ ] Revue de sécurité (`/security-review`) : lecture des fichiers de sauvegarde (aucune exécution de contenu, tailles bornées), chemins de fichiers, permissions.
- [ ] Revue de code intégrale (`/code-review`) module par module.
- [ ] Bêta fermée (5–10 testeurs), formulaire de retour, rapports exportés par l'outil intégré.
- [ ] Correction de tous les bugs bloquants / majeurs ; chaque correction avec test de non-régression.
- [ ] Dernière passe d'équilibrage à partir des données de bêta.

**Porte de sortie (critères de sortie « sans bug »)**
- 0 bug bloquant ou majeur ouvert.
- 0 crash sur 100 heures cumulées de bêta.
- Simulation de masse : 20 000 parties sans exception ni blocage.
- Toutes les cases de la liste de contrôle des cas limites cochées.
- Taux de reprise de sauvegarde : 100 % sur le jeu de fixtures historiques.

---

## Phase 11 — Publication v1.0 (2 sem.)

Tâches
- [ ] Icône, nom de package, version, signature Android (clé stockée de manière sûre et sauvegardée à deux endroits).
- [ ] Windows : installateur MSIX ou Inno Setup, test sur machine propre.
- [ ] Android : AAB signé + APK ; vérification que le manifeste n'a **aucune permission réseau**.
- [ ] Fiches de présentation, captures, vidéo de démonstration, politique de confidentialité (« aucune donnée collectée »).
- [ ] Classification d'âge.
- [ ] Notes de version, README, guide du joueur.
- [ ] Plan de mises à jour : versionnement sémantique, procédure de correctif urgent.

**Porte de sortie** : installation et lancement sur machines propres, du premier lancement à la victoire d'une mission, vérifié.

---

## Après la v1.0 (à planifier plus tard)

- Éditeur de cartes, mode deux joueurs local, plus de clans et de cartes, succès étendus, défis hebdomadaires, modding JSON, nouvelles missions.

---

## Gestion du risque de calendrier

| Si… | Alors… |
|---|---|
| Une phase dépasse de 50 % | Réduire le périmètre de la phase suivante, jamais les tests |
| Android trop lent | Baisser la qualité auto, plafonner la population, simplifier le brouillard |
| Pathfinding insatisfaisant | Rester sur flow fields uniquement, réduire les tailles de carte |
| Assets non prêts | Livrer avec placeholders améliorés, remplacer par une mise à jour |
| Village trop gros | Livrer la v1.0 avec raids attaquants seulement, défense en v1.1 |

## Ordre de réduction du périmètre (si le temps manque)

1. Défi quotidien → après la v1.
2. Raid défenseur → v1.1.
3. Fins multiples → une fin unique.
4. Navires/combat naval → mission 3 seulement.
5. Sorts de bataille → après la v1.
Ne **jamais** sacrifier : tests, sauvegardes, stabilité.

---

## Prochain pas concret

Démarrer la **Phase 0** : vérification de l'environnement (Visual Studio C++, SDK Android, appareil réel), nettoyage du projet, `pubspec.yaml`, `analysis_options.yaml`, arborescence et CI. Dès qu'elle est validée, enchaîner la Phase 1 (noyau de simulation).
