# Les Royaumes du Fleuve

RTS isométrique 2D hors ligne (Windows + Android), inspiré d'Age of Empires et de Clash of Clans. Flutter + Flame.

- Analyse complète : [docs/ANALYSE.md](docs/ANALYSE.md)
- Roadmap : [docs/ROADMAP.md](docs/ROADMAP.md) (phases 0 à 4 terminées)
- Journal des modifications : [CHANGELOG.md](CHANGELOG.md)
- Performances : [docs/PERF.md](docs/PERF.md)
- Conventions : [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
- Décisions : [docs/DECISIONS.md](docs/DECISIONS.md)

## Lancer

```bash
flutter pub get
flutter run -d windows
flutter run -d <id_appareil_android>
```

Menu → **Nouvelle partie** (taille de carte, graine) → vous incarnez le joueur 1 face à un adversaire inactif.

### Contrôles (Windows)

| Action | Entrée |
|---|---|
| Sélection / rectangle / ajout | clic gauche / glisser / Maj + clic |
| Tout sélectionner (même type visible) | double-clic |
| Ordre contextuel (déplacer, récolter, attaquer, construire, réparer, garnison) | clic droit |
| File d'ordres | Maj + clic droit |
| Groupes de contrôle | Ctrl + 0-9 / 0-9 |
| Villageois inactifs | `.` |
| Caméra | flèches / WASD, bords d'écran, clic molette + glisser, molette = zoom, `Début` = centre-ville |
| Pause / vitesse | Espace / `+` `-` |
| Supprimer le bâtiment sélectionné | Suppr (confirmation) |
| Menu / annuler | Échap |
| Débogage (grille, occupation, chemins, FPS) | F3 |

Android : appui = sélectionner, puis appui sur la destination ; glisser = caméra ; pincer = zoom ; boutons « Sélection multiple » et « File d'ordres » dans le panneau d'actions.

## Vérifier

```bash
dart format lib test tool
flutter analyze --fatal-infos
dart run tool/check_arch.dart
flutter test --exclude-tags golden          # tout sauf les images de référence
flutter test --tags golden                  # images de référence (Windows)
```

### Portes de sortie à pleine échelle (longues)

```bash
# 1 000 graines × 10 000 ticks, 10 000 cartes, 300 parties à invariants, 1 000 scénarios de mouvement…
SIM_FULL=1 flutter test test/sim --exclude-tags golden      # PowerShell : $env:SIM_FULL=1

# Simulation de masse headless (journal des échecs dans build/sim_failures)
dart run tool/mass_sim.dart --games 5000 --ticks 2500 --mode economy
dart run tool/mass_sim.dart --games 1000 --ticks 3000 --check-determinism

# Rejouer un journal de commandes et comparer le hash final
dart run tool/replay.dart journal.jsonl --seed 7 --size 64 --players 2 --ticks 5000 --expect 0x…

# Couverture de la simulation (seuil de la roadmap : 90 %)
flutter test --coverage --exclude-tags golden && dart run tool/coverage.dart lib/sim --min 90
```
