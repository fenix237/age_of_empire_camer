# Journal des modifications

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
