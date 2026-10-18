# Journal des décisions d'architecture

| # | Date | Décision | Raison |
|---|---|---|---|
| 1 | 2026-10-16 | Simulation en Dart pur, séparée du rendu | Tests headless, déterminisme, sauvegardes/replays |
| 2 | 2026-10-16 | Tick fixe 10 Hz, rendu interpolé | Indépendance du framerate, performance Android |
| 3 | 2026-10-16 | Plateformes : Windows + Android uniquement (dossiers ios/macos/linux/web supprimés) | Périmètre du projet ; moins de surface à maintenir |
| 4 | 2026-10-16 | Android : paysage verrouillé, `resizeableActivity=false`, aucune permission réseau en release | Hors ligne, états prévisibles |
| 5 | 2026-10-16 | `WindowService` abstrait (Windows via `window_manager`, Noop sur Android) | Testabilité |
| 6 | 2026-10-16 | Toute fermeture passe par `CloseCoordinator` ; échec de sauvegarde = fermeture annulée | Zéro perte de données |
| 7 | 2026-10-16 | Instance unique par verrou de fichier | Éviter deux processus écrivant les mêmes sauvegardes |
| 8 | 2026-10-16 | Échap ne quitte jamais le plein écran (F11 / Alt+Entrée) | Éviter les sorties accidentelles |
| 9 | 2026-10-17 | Positions et vitesses en entiers 1/256 de case ; vitesse en millièmes de case/s dans le JSON ; `Rng` xorshift128+ maison ; hash FNV-1a 64 bits champ par champ (pas de sérialisation JSON pour hacher) | Déterminisme Windows ↔ Android ; coût du hash négligeable |
| 10 | 2026-10-17 | `avoid_js_rounded_ints` désactivé : la simulation exige des entiers 64 bits natifs (VM Dart). Le web n'est pas une cible | Windows + Android seulement (décision 3) |
| 11 | 2026-10-17 | Une commande invalide est refusée par un `CmdResult`, jamais par une exception ; chaque commande est journalisée (même refusée) | Replays et fuzzing fiables |
| 12 | 2026-10-17 | Sauvegarde : en-tête `RDFS` + version + longueur + CRC32, charge utile JSON, écriture `.tmp` → vérification → renommage avec `.bak`. Les chemins/flow fields ne sont pas persistés tels quels : l'état de mouvement l'est, les champs sont recalculés de façon pure | Reprise identique au hash après chargement |
| 13 | 2026-10-17 | `explored` (brouillard) fait partie de l'état et du hash ; `visible` est dérivé et recalculé au chargement **sans** fusionner dans `explored` | Une partie chargée évolue exactement comme sans interruption |
| 14 | 2026-10-17 | **HPA (hiérarchique) non implémenté** : A* (plafond de nœuds) + flow field pour les groupes tiennent les budgets (0,10 ms/tick pour 200 ordres A*) | Repli prévu par la roadmap (« flow fields uniquement ») ; à rouvrir si les cartes 160×160 posent problème |
| 15 | 2026-10-17 | Forge et marché à l'âge I **provisoirement** (le changement d'âge arrive en Phase 5) ; modifier `age` dans `buildings.json` suffira | Rendre les recherches et l'échange testables dès la Phase 4 |
| 16 | 2026-10-17 | Le rendu iso est écrit sur mesure (Canvas) et hébergé par Flame (`GameWidget`/`FlameGame`), sans les composants iso génériques de Flame | Maîtrise du tri de profondeur, du cache de terrain et des performances |
| 17 | 2026-10-17 | Tri de profondeur par tri topologique (règle isométrique exacte pour grands bâtiments) plutôt que par `x + y` | Un objet contre le flanc d'un grand bâtiment est bien devant/derrière |
| 18 | 2026-10-17 | Les textes du HUD sont regroupés dans `lib/ui/strings.dart` | Migration `.arb` triviale en Phase 9 |
| 19 | 2026-10-17 | Tout élément d'équilibrage (coûts, vitesses, portées de vision, constantes de génération, frais de marché…) vit dans `assets/data/*.json` ; les portées géométriques d'interaction (≈ 1,1 case) restent des constantes de moteur | Règle transversale n° 3 |

## Limites connues (à traiter plus tard)
- La seconde instance se ferme sans ramener la première au premier plan (code natif requis) — Phase 10.
- Fermeture à l'arrêt de session Windows (`WM_QUERYENDSESSION`) non interceptée nativement — Phase 10 ; l'autosauvegarde périodique couvre ce cas dès qu'une partie existe.
- Android licences SDK : à accepter une fois avec `flutter doctor --android-licenses`.
- Flame 1.38.2 : le téléchargement depuis pub.dev a été très lent pendant le développement (réseau) ; si `flutter pub get` se bloque, relancer ou préremplir le cache (`flutter pub cache add flame --version 1.38.2`).
- Les valeurs de `test/fixtures/hash_reference.json` doivent être régénérées (`UPDATE_REFERENCE=1 flutter test test/sim/determinism_test.dart`) **uniquement** après un changement volontaire de la simulation, puis vérifiées sur Android.
- Aucun asset réel : placeholders générés par le code (Phase 9).
