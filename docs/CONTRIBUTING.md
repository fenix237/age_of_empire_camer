# Conventions de développement

## Règles d'or
1. `lib/sim/` est du Dart pur : **aucun import** de `flutter`, `flame`, `dart:ui`, `riverpod`. Vérifié par `dart run tool/check_arch.dart` et par `test/sim/architecture_test.dart`.
2. Le rendu et l'UI **lisent** la simulation et lui envoient des **Commandes** ; ils ne la modifient jamais directement.
3. Aucune constante de gameplay dans le code : elles vivent dans `assets/data/*.json`.
4. Pas de `double` dans la simulation (entiers à virgule fixe), pas d'`DateTime.now()` ni de hasard non seedé.
5. Tout bug corrigé reçoit un test de non-régression.
6. Pas de `print` : utiliser `AppLogger.instance`.

## Avant chaque commit
```bash
dart format lib test tool
flutter analyze --fatal-infos
dart run tool/check_arch.dart
flutter test --exclude-tags golden
flutter test --tags golden        # Windows : images de référence
```

## Tests propres à ce projet
- **Invariants** : tout nouveau système de simulation doit laisser passer `test/sim/invariants_test.dart` (commandes aléatoires, invariants vérifiés après chaque tick). Un nouvel invariant reçoit son test de détection dans `invariants_detect_test.dart`.
- **Déterminisme** : un changement volontaire de la simulation modifie `test/fixtures/hash_reference.json`. Le régénérer avec `UPDATE_REFERENCE=1 flutter test test/sim/determinism_test.dart`, expliquer pourquoi dans le commit, et vérifier le résultat sur Android.
- **Goldens** (`test/game/goldens/`) : `flutter test --tags golden --update-goldens`, puis relire visuellement les images modifiées.
- **Pleine échelle** : `SIM_FULL=1 flutter test test/sim` avant chaque fin de phase (voir README).
- Un bogue trouvé par `tool/mass_sim.dart` laisse un fichier dans `build/sim_failures/` : le rejouer, le corriger, ajouter un test.

## Structure
Voir `docs/ANALYSE.md` §3.5. En bref : `lib/sim` (simulation), `lib/game` (Flame), `lib/ui` (menus/HUD), `lib/app` (démarrage, fenêtre, cycle de vie), `lib/meta` (village, profil).

## Commits et branches
Branches courtes, un sujet par commit, message en français ou anglais clair. Les tags `phase-N` marquent la fin de chaque phase de la roadmap.

## Définition de « terminé »
Code + tests + `flutter analyze` propre + vérifié sur Windows **et** sur un appareil Android réel.
