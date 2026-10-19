# Journal des modifications

## Phases 5 à 7 (partielles) — 2026-10-19

Combat, âges, pouvoirs, héros, IA, interface de combat, menu d'escarmouche et moteur de campagne.

### Ajouté
- **Combat complet** (Phase 5) : armures, bonus de catégorie, projectiles, dégâts de zone, hauteur ; tours, forteresse, palais, rempart, écurie, atelier de siège, autel ; catapulte, changement d'âge, pouvoirs, 5 héros, sorts de bataille (jauge du tambour), victoire et défaite.
- **IA** (Phase 6) : 3 difficultés, 5 clans, outils `tool/ai_demo.dart` et `tool/balance_sim.dart`, rejeu identique d'une partie IA contre IA.
- **Interface de combat** : panneau des pouvoirs (Z X C V) et des sorts (F5–F8) avec recharges, jauge du tambour, bouton « Âge suivant » (prérequis et coût), bandeau de ciblage, écran de fin (résultat, statistiques par joueur), abandon avec confirmation.
- **Rendu du combat** : flèches et boulets en arc interpolés, ondes de zone des pouvoirs, aperçu de zone au ciblage, icônes d'effets sur les unités (étourdi, ralenti, bonus, malus).
- **Personnages animés** : squelette articulé et outils ; gestes réels déduits de la simulation (couper, cueillir, miner, cultiver, bâtir, chasser, estoc, frappe, tir), l'unité se place contre sa cible et se tourne vers elle ; charges portées (tronc, panier, sac) ; effets d'impact. Bâtiments animés (fumée, drapeaux, braises, blé).
- **Marqueur d'ordre** : une croix posée sur la destination (plus d'anneau ni de ligne blanche de chemin).
- **Menu d'escarmouche** : carte (taille, type, graine), clan, nombre d'IA, difficulté (bonus de l'IA Difficile affiché), victoire, ressources, vitesse, mode spectateur.
- **Campagne** (Phase 7) : moteur de missions JSON (objectifs, déclencheurs, vagues, dialogues, aide du tutoriel, fins multiples) intégré à la simulation (état sauvegardé, haché, rejoué) ; validateur de données ; 7 missions ; carte du royaume, briefing avec 3 difficultés, dialogues, écran de fin avec étoiles et déblocages, progression locale ; défi du jour (graine de la date locale).

### Corrigé
- **IA qui s'emmurait** : ses champs et huttes pouvaient enfermer le centre-ville (20 cases atteignables), bloquant bois et récolte ; chaque pose vérifie maintenant que la zone accessible n'est pas amputée.

### Qualité
- 377 tests verts ; `flutter analyze` : un avertissement de style dans `test/sim/combat_phase5_test.dart`.
- Les 7 missions sont validées (références, positions accessibles, ressources suffisantes) et la mission 1 est terminée de bout en bout avec de vraies commandes ; les missions 2 à 7 sont vérifiées par des scénarios scriptés (renforts, téléportation, dégâts directs), pas par une partie jouée.

### Limites connues
- **Équilibrage non terminé** : sur 30 parties croisées, 10 se terminent sans vainqueur et le taux de victoire par clan va de 15 % à 66 % (cible 45–55 %). La simulation nocturne de 5 000 parties n'a pas été lancée.
- Navires et portes repoussés. Pas de son ; placeholders graphiques (Phase 9).
- Missions de campagne jamais jouées par un humain ; leurs seuils (vagues, ressources, étoiles) sont des premières valeurs.
- Une sauvegarde de mission reprend les dialogues non lus mais pas l'aide à l'écran déjà fermée.

## Phases 1 à 4 — 2026-10-18

Première version jouable : une économie complète de bout en bout (récolter, construire, produire, rechercher, sauvegarder).

### Ajouté
- **Noyau de simulation déterministe** (`lib/sim`, Dart pur) : virgule fixe, RNG xorshift128+, monde à tick fixe 10 Hz, commandes + journal, hash d'état, invariants vérifiés à chaque tick, sauvegarde versionnée avec CRC32.
- **Données externes** (`assets/data/*.json`) validées avec messages d'erreur précis : terrain, ressources, unités, bâtiments, âges, recherches, équilibrage et constantes de génération de carte.
- **Générateur de cartes** procédural déterministe avec garantie de ressources de départ et de connexité.
- **Pathfinding** : A* (budget par tick), flow fields pour les groupes, évitement local, résolution d'impasses.
- **Économie** : récolte (5 ressources, portage, dépôt auto), épuisement et changement de source, champs (replantation), construction multi-bâtisseurs, production avec files et ralliement, recherches, réparation, suppression avec remboursement, marché, garnison, plafond de population.
- **Combat minimal** : poursuite, frappe, riposte, postures (le combat complet est en Phase 5).
- **Rendu isométrique** hébergé par Flame : terrain en blocs mis en cache avec transitions, tri de profondeur robuste, brouillard de guerre 3 états, mini-carte, interpolation, mode debug (F3).
- **Entrées** : souris/clavier (sélection, rectangle, double-clic, groupes, ordres contextuels, file d'ordres) et tactile (appui, glisser, pincement, tolérance de toucher, sélection multiple, file d'ordres).
- **HUD** : ressources, population, âge, panneau de sélection, actions contextuelles, files de production, alertes, villageois inactifs, vitesses, pause, menu, confirmation de suppression.
- **Sauvegarde/chargement** en cours de partie (menu pause, autosauvegarde toutes les 2 min en 3 emplacements, « Reprendre la partie », sauvegarde à la fermeture).
- **Outils** : `tool/replay.dart`, `tool/mass_sim.dart`, `tool/coverage.dart`, workflow de simulation de masse nocturne.

### Qualité
- 292 tests (unitaires, propriétés, déterminisme, sauvegarde, stress, HUD sur 8 tailles × 3 échelles, parcours menu → partie → sauvegarde → reprise, 5 goldens). Couverture de `lib/sim` : 95 %.
- Portes de sortie à pleine échelle exécutées le 2026-10-18 : 1 000 graines × 10 000 ticks (déterminisme), 10 000 cartes, 300 parties à invariants vérifiés à chaque tick, 1 000 scénarios de mouvement, 150 parties « économie » à invariants, puis 5 000 parties headless « économie » (`tool/mass_sim.dart`) : **0 échec**.
- Bogues réels trouvés par le fuzzing d'invariants et les tests de parcours, corrigés avec test de non-régression : une unité longeant le coin d'un bâtiment pouvait pénétrer une case bloquée ; la pression de foule pouvait annuler le déplacement d'unités sur terrain lent ; un déplacement pouvait momentanément n'avoir ni chemin ni demande en cours ; le bouton « Reprendre la partie » restait grisé après le retour d'une partie ; une sauvegarde incohérente (mais au CRC valide) pouvait planter plus tard au lieu d'être refusée au chargement.

### Limites connues
- Pas d'âges, de pouvoirs, de héros ni d'IA (Phases 5 et 6) : l'adversaire est inactif.
- Placeholders graphiques uniquement (assets réels en Phase 9) ; aucun son.
- HPA\* non implémenté (voir `docs/DECISIONS.md`).
- Forge et marché sont à l'âge I tant que le changement d'âge n'existe pas.

### À valider à la main (non automatisable ici)
1. Jouer **30 minutes** sur Windows puis sur un téléphone Android réel : récolter, bâtir, produire, sauvegarder/recharger. Noter tout comportement étrange (la sortie de `F3` aide).
2. Lancer `flutter test test/sim/determinism_test.dart` **sur Android** (ou via un test d'intégration) pour confirmer que `test/fixtures/hash_reference.json` (généré sous Windows) est identique sur ARM.
3. Mesurer les FPS sur 3 appareils (voir `docs/PERF.md`) : cible 60 FPS PC, 45 FPS Android milieu de gamme, 30 FPS appareil le plus faible.
4. Poser le tag Git : `git tag phase-1`, `phase-2`, `phase-3`, `phase-4` une fois ces validations faites.
