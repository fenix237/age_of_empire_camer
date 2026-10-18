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
- [ ] Fenêtre Windows (taille mini 1024×576, plein écran F11 / Alt+Entrée sans bordure, mémorisation position/moniteur, repli si moniteur absent) via `WindowService` abstrait + `window_manager` ; orientation paysage Android (`sensorLandscape`, immersif), aucune permission Internet dans le manifeste.
- [ ] Fermeture Windows : interception ✕ / Alt+F4 / Quitter / arrêt de session, dialogue « Sauvegarder et quitter », fermeture propre sans processus fantôme, instance unique (verrou de fichier) ; bouton Retour Android (menu pause, double appui pour quitter).
- [ ] Fondations responsive : classes de taille (compact/moyen/large), widgets d'ancrage HUD, `SafeArea`, échelle d'interface 80–150 %.
- [ ] Squelette de menu principal (Jouer / Options / Quitter) ; écran de chargement.
- [ ] Documentation : `docs/CONTRIBUTING.md` (conventions), `docs/DECISIONS.md` (journal des décisions d'architecture).
- [ ] Configuration `.gitignore` (build/, .dart_tool/, clés de signature).

**Porte de sortie**
- L'application se lance sur Windows et sur un téléphone Android réel, CI verte, `flutter analyze` à 0 avertissement.

---

## Phase 1 — Noyau de simulation (3–4 sem.) — ✅ terminée

**Objectif** : un monde qui tourne sans écran, déterministe, testé.

Tâches
- [x] `FixedPoint` (entiers 1/256), vecteurs, distances entières, table trigonométrique, racine entière. → `lib/sim/core/fixed_point.dart`, `vec2.dart`
- [x] `Rng` déterministe (xorshift128+, graine SplitMix64) avec états sérialisables. → `rng.dart`
- [x] `World` : entités (IDs stables), registres, tick fixe 10 Hz, ordre de résolution déterministe (itération par identifiant croissant). → `lib/sim/world/world.dart`
- [x] Chargeur de définitions JSON (`UnitDef`, `BuildingDef`, `ResourceDef`, `AgeDef`, `TechDef`, terrain, équilibrage) avec **validation de schéma** : erreur claire (fichier, chemin, raison). → `lib/sim/data/`
- [x] Carte logique : terrain, hauteurs, grille d'occupation, ressources. → `game_map.dart`
- [x] Générateur de cartes procédural déterministe + validation de connexité + garantie de ressources de départ (régénération graine+1, puis ponts garantis). → `map_generator.dart`
- [x] File de commandes + validation + journal de commandes (pour replays). → `lib/sim/commands/`
- [x] Hash d'état (toutes les secondes de jeu) et outil `tool/replay.dart` qui rejoue un journal et compare. Outil de masse `tool/mass_sim.dart`.
- [x] Sérialisation d'état (sauvegarde/chargement) de base, format versionné + CRC32, écriture atomique (`SaveStore`). → `lib/sim/save/`, `lib/meta/save_store.dart`
- [x] Framework d'invariants (Analyse §13.2) exécuté après chaque tick en debug ; chaque détecteur est lui-même testé. → `lib/sim/core/invariants.dart`
- [x] Tests unitaires + tests de propriétés (commandes aléatoires, `CommandFuzzer`).

**Porte de sortie**
- [x] Test de déterminisme : 1 000 graines × 10 000 ticks avec commandes aléatoires, mêmes hashes entre deux exécutions (`SIM_FULL=1 flutter test test/sim/determinism_test.dart`).
- [ ] Mêmes hashes **entre Windows et Android** : le fichier de référence `test/fixtures/hash_reference.json` est généré sur Windows et comparé par `flutter test` ; **reste à exécuter sur un appareil Android réel** (aucun appareil disponible pendant le développement).
- [x] Génération de 10 000 cartes sans carte invalide (`SIM_FULL=1`, test `mapgen_test.dart`).
- [x] Couverture de `lib/sim` ≥ 90 % (mesurée : 95 %, `dart run tool/coverage.dart lib/sim`).

---

## Phase 2 — Rendu isométrique & caméra (3 sem.) — ✅ terminée (hors mesures sur appareils)

**Objectif** : voir le monde, le parcourir et choisir une case précisément.

Tâches
- [x] Projection iso et picking inverse (propriété `screenToTile(tileToScreen(p)) == p`, testée sur toutes les cases et sur 5 000 points aléatoires). → `lib/game/iso.dart`
- [x] Rendu du terrain par blocs de 16×16 mis en cache (`Picture`) ; transitions entre terrains (auto-tiling par priorité). → `terrain_renderer.dart`
- [x] Rendu des ressources, bâtiments (échafaudage selon l'avancement), unités (placeholders, léger balancement en marche). → `assets.dart`, `entity_renderer.dart`
- [x] Tri de profondeur robuste (grands bâtiments) : tri topologique par règle isométrique exacte + tests de propriété + test golden. → `depth_sorter.dart`
- [x] Caméra : glisser (clic molette / un doigt), bords d'écran, WASD/flèches, zoom molette / pincement, bornes de carte, inertie. → `camera.dart`, `input.dart`
- [x] Mini-carte en losange (terrain, ressources, bâtiments, unités, brouillard, zone vue), clic/glisser pour déplacer la caméra, clic droit = ordre, alertes d'attaque clignotantes. → `lib/ui/hud/minimap.dart`
- [x] Brouillard de guerre (3 états) lié à la vision de la simulation (`explored` sauvegardé, `visible` recalculé). → `fog_renderer.dart`, `lib/sim/systems/vision.dart`
- [x] Interpolation de rendu entre ticks (`GameLoop.alpha`).
- [x] Mode debug (F3) : grille, occupation, chemins, FPS, statistiques.
- [~] Système d'atlas + chargeur d'assets abstrait (clé → sprite) : le **registre clé → sprite** est en place (`AssetRegistry`, placeholders pour toutes les définitions, détection des clés manquantes) ; le chargement de **vrais atlas** est repoussé en Phase 9 (aucun asset réel avant).
- [x] Gestion cycle de vie : pause auto en arrière-plan / perte de focus, jamais de reprise automatique (écran « Partie en pause »).
- [x] Viewport responsive : zoom par défaut selon la hauteur, redimensionnement en direct sans perte d'état, tests de non-débordement du HUD sur 8 tailles × 3 échelles (80/100/150 %). Hôte de rendu : Flame (`GameWidget`).
- [ ] Mesure de performance sur appareil bas de gamme (nécessite le matériel ; voir `docs/PERF.md`).

**Porte de sortie**
- [ ] Carte 128×128 avec 2 000 entités fixes + 200 mobiles à ≥ 60 FPS sur le PC, ≥ 45 FPS sur Android milieu de gamme, ≥ 30 FPS sur le plus faible appareil : **à mesurer sur appareils**. Proxy automatisé : coût de construction d'une image < 25 ms (`test/game/render_perf_test.dart`).
- [x] Tests golden de tri de profondeur verts (`test/game/goldens/`).

---

## Phase 3 — Unités, mouvement, sélection (4 sem.) — ✅ terminée

**Objectif** : le cœur « Age of Empires » : sélectionner, cliquer, obéir.

Tâches
- [x] Sélection : clic, rectangle, Maj+clic, double-clic (même type visible), groupes de contrôle Ctrl+0-9 / 0-9, touche `.` « villageois inactifs ». → `lib/game/selection.dart`, `input.dart`
- [x] Interactions tactiles équivalentes : appui, glisser-sélection (mode multi-sélection), tolérance de toucher de 28 dp, pincement/déplacement à deux doigts, bouton « file d'ordres ».
- [x] Ordre contextuel (sol → déplacer, ressource → récolter, ennemi → attaquer, bâtiment → garnison/réparer/construire/cultiver). → `lib/sim/commands/contextual.dart`
- [x] Marqueur visuel de destination, lignes de chemin des unités sélectionnées, feedback d'ordre.
- [x] Pathfinding : A* (octile, départage déterministe, sans coupe de coin) + grille d'occupation, replanification sur obstacle, file de requêtes avec budget par tick.
- [x] Flow field pour les groupes (≥ 8 unités). **HPA (hiérarchique) : non implémenté** — voir `docs/DECISIONS.md` n° 14 (repli prévu par la roadmap : flow fields seuls).
- [x] Évitement local (séparation plafonnée à ¼ de vitesse, glissement le long des obstacles), gestion d'impasses et téléportation de secours journalisée.
- [x] Formations simples (arrivée en cercle autour de la cible), vitesse du groupe alignée sur la plus lente.
- [x] Files d'ordres (waypoints) via Maj+clic droit et bouton « file » (limite 32).
- [x] États d'unité en machine à états testée (table des transitions autorisées, transition illégale détectée).
- [x] Stances (agressif / défensif / passif / suivre). Combat minimal (poursuite, frappe, riposte) ; le combat complet reste en Phase 5.
- [x] Tests : stress 500 unités, couloirs étroits, impasses, cibles inaccessibles, bâtiment posé sur le chemin.

**Porte de sortie**
- [x] 200 unités envoyées dans un goulot d'étranglement : **0,001 ms** de pathfinding par tick en flow field, **0,10 ms** avec 200 ordres individuels A* (seuil 2 ms) ; aucune unité immobile plus de 1 tick (flow) / 6 ticks (A*) (seuil 5 s = 50 ticks).
- [x] 1 000 scénarios aléatoires de mouvement sans violation d'invariant (`SIM_FULL=1`).

---

## Phase 4 — Économie & construction (4 sem.) — ✅ terminée

**Objectif** : une économie complète, un village qui grandit.

Tâches
- [x] Récolte (nourriture, bois, pierre, fer, or), capacité de portage, dépôt automatique au plus proche.
- [x] Gestion de l'épuisement d'une ressource et recherche automatique de la suivante (≤ 10 cases) ; charge vidée avant de changer de source (ordre `deposit`).
- [x] Construction : aperçu fantôme (vert/rouge, silhouette), validation de placement (terrain, occupation, exploration, unités ennemies), progression, multi-constructeurs à rendement décroissant, annulation/remboursement exact.
- [x] Bâtiments d'économie : centre-ville, huttes, grenier, camp de bûcherons, camp minier (carrière/mine), champ (durée limitée, replantation payante, auto-replantation), marché (échange avec frais).
- [x] Production d'unités : files (5 max), point de ralliement contextuel, annulation (remboursement 100 %), plafond de population (la production attend de la place).
- [x] Recherches (forge) : améliorations de récolte et de portage. *Provisoire : forge et marché sont à l'âge I tant que le changement d'âge n'existe pas (Phase 5) ; seule la donnée change ensuite.*
- [x] Réparation (coût proportionnel, s'arrête sans fonds), suppression de bâtiments (confirmation obligatoire, partie en pause).
- [x] HUD complet : ressources, panneau de sélection, actions, files, alertes, villageois inactifs, vitesses, pause, menu.
- [x] Gestion des cas limites de l'Analyse §13.3 (économie, construction) : voir `test/sim/economy_test.dart`.
- [x] Tests de propriétés : conservation des ressources, aucun négatif, remboursements exacts (`conservation_test.dart`).
- [x] Sauvegarde/chargement d'une partie en cours (menu pause, autosauvegarde toutes les 2 min en 3 emplacements tournants, « Reprendre la partie »), premier test de bout en bout.

**Porte de sortie**
- [x] Partie « économie seule » de 30 min (18 000 ticks) sans violation, sauvegarde → chargement identique (hash) puis continuation identique.
- [x] 5 000 parties headless « économie » sans violation (`dart run tool/mass_sim.dart --games 5000 --mode economy`) + parties aléatoires avec invariants vérifiés à chaque tick.
- [ ] « Jouable sans bug sur Windows et Android » : **session de test manuelle de 30 min à faire par vous** sur les deux plateformes (voir `docs/CHANGELOG.md`, section « À valider à la main »).

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
- [ ] Tests Windows : veille, changement de moniteur / DPI, perte de focus, fermeture brutale pendant sauvegarde, bascule plein écran répétée 500 fois, fermeture par ✕ / Alt+F4 / arrêt de session pendant une partie, vérification qu'aucun processus ne subsiste, second lancement (instance unique), reprise après arrêt brutal.
- [ ] Tests responsive : téléphones allongés (21:9), tablettes (4:3), encoches, rotation entre les deux paysages, échelle d'interface 150 %, fenêtre redimensionnée à la taille minimale.
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
