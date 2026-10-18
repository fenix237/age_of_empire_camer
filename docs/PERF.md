# Performances

> Règle transversale n° 6 : mesurer à chaque phase. Les chiffres « PC de développement » sont automatisés (tests) ;
> les chiffres « appareils » sont **à relever à la main** (aucun appareil Android n'était disponible pendant les phases 1 à 4).

## Mesures automatisées (PC de développement, Windows 11, 8 cœurs logiques)

| Mesure | Résultat | Budget | Test / outil |
|---|---|---|---|
| Simulation, 500 villageois en déplacement (carte 128×128, 700 obstacles) | ≈ 1,4 ms / tick | ≤ 8 ms (appareil le plus faible) | `test/sim/stress_test.dart` |
| Pathfinding, 200 unités en goulot, flow field | 0,001 ms / tick | < 2 ms | `stress_test.dart` |
| Pathfinding, 200 ordres individuels (A*), carte 96×96 | 0,10 ms / tick (moyenne) | < 2 ms | `stress_test.dart` |
| Unité immobile la plus longue pendant un déplacement | 1 tick (flow) / 6 ticks (A*) | < 50 ticks (5 s) | `stress_test.dart` |
| Débit de simulation avec invariants vérifiés à chaque tick | ≈ 2 500 ticks/s | — | `tool/mass_sim.dart` |
| Construction d'une image : carte 128×128, 2 000 entités fixes + 200 unités, zoom 0,6 | ≈ 7 ms | ≤ 16,6 ms (60 FPS) | `test/game/render_perf_test.dart` |
| Idem, zoom minimal (toute la carte visible, 2 143 objets) | ≈ 20 ms (rare : vue de toute la carte) | ≤ 33 ms (30 FPS) | `render_perf_test.dart` |

Le test de rendu mesure l'**enregistrement** des commandes de dessin (tri de profondeur, sprites, caches) et non la
rastérisation GPU ; il sert de garde-fou contre les régressions. La mesure réelle se fait avec le mode debug.

### Optimisations déjà en place
- Terrain et brouillard en blocs 16×16 mis en cache dans des `Picture` ; reconstruits seulement si la révision de vision / de terrain change.
- Ressources (arbres, mines…) enregistrées une fois en `Picture` par variante : un sprite statique = une commande de dessin.
- Très dézoomé (< 0,38), les ressources deviennent des pastilles (1 commande).
- Tri de profondeur en O(n log n) (tas), arêtes seulement entre grands bâtiments et objets qui les chevauchent à l'écran.
- Le HUD ne se reconstruit qu'à chaque tick de simulation (10 Hz) ; seule la mini-carte suit chaque image.
- Simulation : grille de hachage spatiale reconstruite par tri par comptage, requêtes de chemin avec budget par tick, vision recalculée tous les 5 ticks.

## À mesurer sur appareil (porte de sortie de la Phase 2)

1. Lancer une partie en **Grande** carte (128×128) et activer **Menu → Mode debug** (ou **F3** sous Windows) pour afficher FPS, nombre d'objets dessinés et coûts.
2. Faire apparaître beaucoup d'unités (centre-ville : entraîner des villageois en continu), dézoomer au maximum, relever le FPS stable sur 30 s.
3. Remplir le tableau :

| Appareil | OS | RAM | FPS zoom normal | FPS zoom min | Mémoire | Date |
|---|---|---|---|---|---|---|
| PC de développement | Windows 11 | | | | | |
| Android milieu de gamme | | | | | | |
| Android le plus faible | | | | | | |

Objectifs (Analyse §14) : 60 FPS PC, ≥ 45 FPS Android milieu de gamme, ≥ 30 FPS appareil le plus faible ; mémoire ≤ 500 Mo (PC) / 350 Mo (Android) ; démarrage menu ≤ 3 s.
