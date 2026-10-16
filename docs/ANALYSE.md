# Les Royaumes du Fleuve — Analyse complète

> Jeu de stratégie temps réel (RTS) isométrique 2D, 100 % hors ligne, Flutter + Flame, Windows et Android.
> Inspirations : Age of Empires (gameplay, âges, ressources, sélection/déplacement par clic) et Clash of Clans (pouvoirs, héros, village persistant).
> Version du document : 1.0 — 2026-10-16

## 0. Décisions prises

| Sujet | Décision | Pourquoi |
|---|---|---|
| Vue | Isométrique 2D (losange 128×64 px) | Choix utilisateur. Rendu proche d'AoE2. |
| Contenu Clash | **Les deux** : pouvoirs/héros en partie **et** village persistant | Choix utilisateur. |
| Factions | Campagne (7 missions) **et** 4 clans jouables en escarmouche | Choix utilisateur. |
| Assets | Packs libres/achetés (Kenney, itch.io, OpenGameArt) en production, **placeholders** colorés pendant le développement | Le gameplay ne dépend jamais de l'art. On remplace les assets sans toucher au code (§12). |
| Moteur | Flutter 3.41 + Flame, **simulation en Dart pur séparée du rendu** | Seul moyen sérieux d'obtenir un jeu testable sans bug (§3). |
| Réseau | Aucun. Zéro permission Internet sur Android | Hors ligne strict. |

### Honnêteté sur « zéro bug »

Aucun logiciel de cette taille n'a zéro bug. L'objectif réaliste, que cette analyse met en place, est :
**aucun crash, aucune perte de sauvegarde, aucun blocage de partie, aucune désynchronisation de simulation**, et un taux de bugs de gameplay mineurs qui tend vers zéro grâce à des tests automatisés massifs (milliers de parties IA contre IA simulées sans écran). Voir §13 et §14.

---

## 1. Vision

Un RTS complet jouable seul : récolter, construire, monter en âge, produire une armée, utiliser des pouvoirs tactiques, conquérir. Entre les parties, un village personnel évolue (Clash of Clans) et alimente la progression.

**Piliers**
1. **Clarté** : on sélectionne, on clique, ça obéit. Contrôles identiques à AoE.
2. **Profondeur par les pouvoirs** : chaque unité clé a une capacité active (cooldown), chaque clan un héros.
3. **Fiabilité** : une partie ne plante pas, ne se bloque pas, ne se corrompt pas.
4. **Fonctionne partout** : Windows (souris/clavier) et Android (tactile), du téléphone d'entrée de gamme à la tablette.

**Hors périmètre** (assumé) : multijoueur en ligne, achats intégrés, publicités, comptes, classements en ligne, cloud save.

---

## 2. Modes de jeu

| Mode | Description | Phase |
|---|---|---|
| **Campagne** | 7 missions du scénario, avec dialogues, objectifs, cinématiques en images fixes | 6 |
| **Escarmouche** | Carte aléatoire ou choisie, 1 à 3 IA, clan au choix, 3 difficultés, conditions de victoire réglables | 5 |
| **Défi quotidien** | Carte fixe dérivée de la date locale (graine), objectif spécial, récompense village | 7 |
| **Village** | Base persistante hors partie, améliorations, collecte passive, raids contre IA | 7 |
| **Raid** | Attaquer le village d'une IA avec une armée et des sorts (style CoC), défendre son village contre un raid IA simulé | 7 |
| **Deux joueurs local** | Même appareil, écran partagé tour à tour — **facultatif**, repoussé après v1 | 9 |

Le jeu est **temps réel avec pause** (pause permise en solo, vitesses ×1, ×1.5, ×2). Le scénario original parle de « tour par tour » : on garde l'esprit « tours » uniquement pour les objectifs de mission (« survivre 12 minutes » plutôt que « 12 tours »), car l'utilisateur demande un jeu comme Age of Empires.

---

## 3. Architecture technique

### 3.1 Principe central : simulation déterministe séparée du rendu

```
┌──────────────────────────────────────────────────────────────┐
│ UI Flutter (menus, HUD, dialogues, paramètres)              │
├──────────────────────────────────────────────────────────────┤
│ Couche présentation (Flame) : caméra, sprites, animations,  │
│ sons, sélection, entrée souris/tactile                      │
│        ▲ lit l'état (lecture seule)   │ émet des Commandes  │
├────────┴──────────────────────────────▼──────────────────────┤
│ SIMULATION (Dart pur, aucun import Flutter/Flame)           │
│ État du monde · systèmes · IA · pathfinding · combat        │
│ Tick fixe 10 Hz · mathématiques en entiers · RNG à graine   │
├──────────────────────────────────────────────────────────────┤
│ Données : unités/bâtiments/âges/cartes/missions en JSON     │
│ Persistance : sauvegardes, profil, village                  │
└──────────────────────────────────────────────────────────────┘
```

**Pourquoi c'est la décision la plus importante pour « pas de bug »**
- La simulation tourne **sans écran** : on peut jouer 10 000 parties IA contre IA en CI et traquer les blocages, crashs et incohérences.
- **Déterminisme** : mêmes graine + mêmes commandes ⇒ même état final (vérifié par un hash d'état à chaque seconde). Une régression de gameplay se détecte instantanément.
- **Sauvegarde / chargement / replay** deviennent triviaux (état sérialisable + journal de commandes).
- Le rendu ne peut pas corrompre la logique : il ne fait que lire.

### 3.2 Boucle de jeu

- Simulation à **10 ticks/s** (100 ms), pas fixe, indépendante du framerate.
- Rendu à 60 FPS (30 FPS sur appareils faibles) avec **interpolation** entre deux ticks pour la fluidité.
- Accumulateur de temps avec plafond (max 5 ticks de rattrapage par frame) : si l'appareil rame, le jeu ralentit au lieu de « spirale de la mort ».
- Vitesse ×2 = 2 ticks par intervalle, pas un delta plus grand.

### 3.3 Nombres : pas de `double` dans la simulation

Positions et distances en **entiers à virgule fixe** (1 case = 256 unités). Raison : les `double` sont déterministes pour + − × ÷, mais `sin/cos/sqrt/pow` ne sont pas garantis identiques entre x64 (Windows) et ARM (Android). On utilise une table de sinus entière et une racine carrée entière. Résultat : **une sauvegarde créée sur Windows se charge à l'identique sur Android** et les tests CI sont reproductibles.

### 3.4 Commandes (patron Command)

Toute action du joueur est une `Command` sérialisable : `Move`, `Attack`, `Gather`, `Build`, `Train`, `Research`, `UsePower`, `SetRally`, `Garrison`, `Delete`, `Stop`, etc. L'UI ne modifie jamais l'état directement. Avantages : validation centralisée (ressources, portée, propriétaire), annulation propre, replays, tests, et l'IA utilise **exactement les mêmes commandes** que le joueur (pas de triche d'accès à l'état, sauf bonus de ressources déclaré).

### 3.5 Structure du code (feature-first, conforme à `very_good_analysis`)

```
lib/
  main.dart
  app/                 # routes, thème, injection, cycle de vie
  sim/                 # SIMULATION pure Dart (testée à 90 %+)
    core/              # World, Tick, Rng, FixedPoint, Id, Hash
    entities/          # Unit, Building, Resource, Projectile
    systems/           # Movement, Combat, Gather, Build, Train, Age,
                       # Fog, Vision, Powers, Garrison, Victory, Economy
    pathfinding/       # A*, flow field, grille d'occupation, HPA*
    ai/                # blackboard, priorités, personnalités
    commands/
    data/              # modèles de définitions (UnitDef, BuildingDef…)
    save/              # sérialisation, migrations, checksum
  game/                # Flame : GameWidget, caméra, rendu iso, sprites
  ui/                  # menus, HUD, dialogues, village
  meta/                # village persistant, profil, succès
  audio/
assets/
  data/*.json          # équilibrage éditable sans recompiler le code
  sprites/ audio/ i18n/
test/ integration_test/ tool/   # tool/ = simulateur headless, outils d'équilibrage
```

Règle appliquée par un test d'architecture : **`lib/sim` ne doit importer ni `flutter` ni `flame`** (script CI qui échoue sinon).

### 3.6 Choix de paquets (à figer en phase 0)

| Besoin | Choix | Note |
|---|---|---|
| Moteur 2D | `flame` | Maintenu, très répandu. Rendu iso écrit sur mesure avec `SpriteBatch`/atlas, pas via le composant iso générique, pour contrôler tri de profondeur et performances. |
| État UI | `riverpod` | Simple à tester. |
| Sauvegardes | Fichiers via `path_provider` + format binaire/JSON versionné avec checksum | Pas de base SQL nécessaire. Pas de dépendance fragile. |
| Audio | `flame_audio` (ou `audioplayers`) | Pool de sons, limite de voix simultanées. |
| Fenêtre Windows | `window_manager` | Plein écran, taille mini, mémorisation. |
| Tests | `flutter_test`, `integration_test`, `glados` (propriétés), `mocktail` | |
| Journal | écriture fichier locale | Aucun envoi réseau. |

Verrouillage strict des versions (`pubspec.lock` versionné), mise à jour des dépendances uniquement entre deux jalons.

### 3.7 Rendu isométrique

- Case logique `(x, y)` → écran : `sx = (x − y)·64`, `sy = (x + y)·32`. Inverse pour le picking (clic → case), testé par propriété `screenToTile(tileToScreen(p)) == p`.
- **Ordre de dessin** : trié par `x + y` puis par hauteur ; les grands objets (bâtiments 3×3+) trient par leur case la plus avancée. Cas de bords testés par captures de référence (golden tests).
- **Terrain** : chunks de 16×16 cases pré-rendus dans un cache (Picture), reconstruits seulement si le terrain change (forêt coupée, mur détruit).
- **Culling** : on ne dessine que ce qui est dans la vue ; unités hors vue non animées.
- **Atlas** : toutes les unités dans quelques grands atlas (taille ≤ 2048 px pour compatibilité GPU Android) pour minimiser les changements de texture.
- **Brouillard de guerre** : couche 3 états (inconnu noir / exploré grisé / visible), lissée par shader ou masque basse résolution.
- **8 directions** pour les unités (5 dessinées + miroir).

### 3.8 Pathfinding et mouvement

C'est la source n°1 de bugs dans un RTS ; traité avec soin.
- Grille d'occupation + **A\*** (heuristique octile, tie-breaking déterministe) pour les unités seules.
- **Flow field** pour les groupes ≥ 8 unités vers une même cible (coût indépendant du nombre d'unités).
- **HPA\*** (hiérarchique, secteurs 16×16) pour les grandes cartes afin de borner le coût.
- Évitement local : séparation douce, glissement le long des obstacles, **résolution d'impasses** (unité coincée ⇒ replanification puis téléportation à la case libre la plus proche après N ticks bloqués, jamais de blocage éternel).
- Formation simple lors d'un déplacement groupé : la vitesse du groupe s'aligne sur la plus lente ; arrivée en cercle autour de la cible.
- Budget : **max 2 ms/frame de pathfinding**, file de requêtes réparties sur plusieurs ticks.
- Chemin invalidé (bâtiment posé, mur détruit) ⇒ replanification automatique au tick suivant.

### 3.9 Intelligence artificielle (sans apprentissage, par règles)

Basée sur le scénario, mais en couches pour qu'elle ne soit pas triviale :
1. **Stratège** (toutes les 5 s) : objectif global (boom économique, rush, défense, âge suivant).
2. **Économie** : répartition des villageois par ressource selon des ratios cibles, construction anticipée des huttes, remplacement des villageois morts.
3. **Militaire** : composition d'armée adaptée à ce que le joueur produit (contre-picking pierre-feuille-ciseaux), regroupement avant attaque, retraite si l'écart de force devient défavorable.
4. **Tactique** (chaque tick) : cibles prioritaires, usage des pouvoirs (cooldown, valeur attendue), soin du héros.
5. **Personnalités** par clan (Pêcheurs : mer/économie ; Forgerons : tourelles/siège ; Cavaliers : raids rapides ; Corbeaux : agressif).

**Difficultés** : Facile (délai de réaction ×2, pas de bonus), Normal, Difficile (+25 % ressources, réaction rapide). Aucune lecture de l'état caché au-delà du brouillard, **sauf** sur Difficile ou le bonus doit être affiché à l'écran.

**Garde-fous anti-blocage de l'IA** : un chien de garde détecte « aucun progrès économique ou militaire pendant 90 s » et force un plan de secours (rassembler et attaquer / reconstruire un centre de ville).

---

## 4. Le monde : cartes et terrain

- Tailles : Petite 64×64, Moyenne 96×96, Grande 128×128, Énorme 160×160 (limitée à 6 joueurs max, 4 IA max).
- Terrains : herbe, terre, sable, savane, forêt (bois), eau peu profonde (franchissable lentement), eau profonde (navires uniquement), montagne (bloquant), route (+vitesse), marais, falaise.
- Altitude : 3 niveaux simples (bonus de portée/vision en hauteur, pas de calcul 3D).
- Ressources : arbres, buissons de baies, gibier, poissons (bancs), carrières de pierre, mines de fer, mines d'or. Chaque tuile de ressource a un stock fini.
- **Génération procédurale** déterministe (graine) : bruit pour le terrain, placement équitable des joueurs (symétrie ou distance égale), ressources garanties à proximité de chaque départ, validation automatique (connexité : chaque base atteint chaque base ; sinon on regénère avec graine+1). Génération testée sur 10 000 graines en CI.
- Éditeur de carte : repoussé après v1 (les cartes de campagne sont créées dans des fichiers JSON maintenus à la main + un outil de validation).

---

## 5. Ressources et économie

| Ressource | Source | Utilisation |
|---|---|---|
| Nourriture | champs, baies, chasse, pêche | villageois, lanciers, passage d'âge, soins |
| Bois | forêts | bâtiments, archers, navires |
| Pierre | carrières | remparts, tours, Palais, monuments |
| Fer | mines | armes, armures, guerriers de fer, forge |
| Or | mines | unités d'élite, commerce, héros, recherches |

**Règles précises (pour éviter les ambiguïtés sources de bugs)**
- Chaque villageois porte au plus N ressources (10 de base, améliorable), les dépose au bâtiment de stockage le plus proche acceptant ce type.
- Ressource épuisée ⇒ le villageois cherche automatiquement la même ressource à ≤ 10 cases, sinon devient inactif (icône).
- Pénalité de distance : rendement plus faible si le dépôt est loin (c'est naturel via le trajet).
- Champs : durée de vie limitée, rechargement payant (comme AoE).
- Commerce : caravanes entre deux marchés, gain proportionnel à la distance.
- **Aucune ressource ne devient négative**, jamais. Coûts prélevés **à la mise en file**, remboursés (100 %) à l'annulation. Test de propriété : somme des ressources reste cohérente après toute séquence aléatoire de commandes.
- Plafond de population 200 (dépend des huttes/centre-ville/Palais). Si la population dépasse le plafond (hutte détruite), la production est bloquée mais les unités existantes restent.

---

## 6. Âges et progression

| Âge | Débloque | Coût indicatif | Condition |
|---|---|---|---|
| I — Villages | Case/Centre-ville, huttes, champs, camp de bûcherons, lancier | départ | |
| II — Royaumes | Forge, marché, archers, guerrier de fer, remparts de terre | 500 N + 200 B | Centre-ville + 2 bâtiments de l'âge I |
| III — Empires | Cavalerie, pirogues de guerre, forteresse, routes commerciales | 800 N + 400 Fe | **Palais** + 2 bâtiments âge II |
| IV — Or | Garde royal, monuments, bonus de civilisation, super-pouvoirs | 1000 N + 800 Or | Palais amélioré |

Les valeurs exactes sont dans `assets/data/*.json` et sont ajustées en phase d'équilibrage (§10). Passer d'âge prend un temps de recherche (30–60 s) pendant lequel le bâtiment ne produit pas autre chose.

---

## 7. Unités

### 7.1 Statistiques (base d'équilibrage — tous les chiffres sont des points de départ, validés par simulation §10)

Coût : N nourriture, B bois, P pierre, F fer, O or. Temps en secondes.

| Unité | Âge | Coût | PV | Dég. | Portée | Vitesse | Notes |
|---|---|---|---|---|---|---|---|
| Villageois | I | 50 N | 25 | 3 | mêlée | 1.0 | récolte, construit, répare |
| Lancier | I | 50 N 25 B | 45 | 4 (+12 vs cavalerie) | 1 | 0.95 | |
| Archer | II | 40 B 30 O | 30 | 5 | 5 | 1.0 | fragile |
| Guerrier de fer | II | 60 N 40 F | 70 | 7 | 1 | 0.95 | polyvalent |
| Cavalier | III | 80 N 40 F | 80 | 6 (+8 vs archers) | 1 | 1.7 | |
| Pirogue de guerre | III | 90 B 30 F | 100 | 8 | 4 | 1.4 | eau |
| Catapulte (Forgerons) | III | 120 B 60 F | 60 | 40 vs bâtiments | 8 | 0.6 | |
| Garde royal | IV | 100 N 60 F 40 O | 140 | 12 | 1 | 1.0 | élite |

**Triangle** : lancier > cavalier > archer > lancier. Armure en deux types (mêlée / distance), pas de formules obscures :
`dégâts_reçus = max(1, dégâts − armure)`, multiplicateurs de catégorie appliqués avant.

### 7.2 Pouvoirs (le « côté Clash »)

Chaque pouvoir : **énergie ou cooldown**, portée, zone, durée, coût éventuel. Les unités gagnent l'accès à leur pouvoir à un âge donné.

| Unité | Pouvoir | Effet | Cooldown |
|---|---|---|---|
| Villageois | Cri de ralliement | +25 % vitesse de récolte (aura 10 s) | 60 s |
| Lancier | Mur de lances | double l'armure et immobilise 4 s, +dégâts vs cavalerie | 40 s |
| Archer | Pluie de flèches | zone 3×3, 20 dégâts sur 3 s | 35 s |
| Guerrier de fer | Frappe écrasante | étourdit 2 s la cible | 30 s |
| Cavalier | Charge | ×2 dégâts sur le premier coup, +vitesse 3 s | 25 s |
| Pirogue | Éperonnage | dégâts élevés aux navires, repousse | 30 s |
| Garde royal | Fureur du lion | +50 % dégâts, immunité aux étourdissements 6 s | 60 s |

**Héros** (1 par clan, 1 vivant à la fois, ressuscite à l'Autel pour un coût croissant) :
- **Mbarga** — *Tambour des Ancêtres* : zone qui donne +20 % dégâts/vitesse à tous les alliés 15 s. Ultime : *Unité* (soin zone + purge des effets négatifs).
- **Mama Sanaga** (Pêcheurs) — *Marée* : ralentit les ennemis dans une zone, soigne les navires.
- **Ngolo** (Forgerons) — *Forge de guerre* : améliore temporairement les armes des alliés ; ultime *Tonnerre de fer* (zone).
- **Dikoumé** (Cavaliers) — *Galop du vent* : téléporte un groupe en avant en courant ; ultime *Stampede*.
- **Kaba le Corbeau** (Corbeaux, jouable une fois la campagne finie) — *Nuée* : invoque 5 corbeaux qui aveuglent.

**Sorts de bataille** (style CoC, utilisables par le joueur avec une jauge « énergie du tambour » qui se remplit en jouant) : Foudre, Soin, Rage, Gel. Jauge séparée des cooldowns d'unités.

**Règles anti-abus de pouvoirs**
- Un pouvoir est validé par la simulation (cible valide, portée, cooldown, unité vivante). Cible morte entre le clic et l'exécution ⇒ pouvoir non consommé.
- Étourdissements non cumulables (la durée se rafraîchit au plus), immunité de 3 s après un étourdissement.
- Plafond de ralentissement cumulé (−60 %), plafond d'amélioration (+100 %).
- Les effets sont une liste ordonnée dans l'entité avec expiration par tick ; mort ⇒ effets purgés.

### 7.3 États d'une unité (machine à états explicite)

`Inactive → Moving → Gathering/Building/Attacking/Garrisoned/Dead`, avec transitions autorisées listées dans un tableau testé. Toute transition illégale lève une assertion en debug et est journalisée en release (puis l'unité repasse en `Inactive`).

---

## 8. Bâtiments

| Bâtiment | Âge | Fonction | Taille |
|---|---|---|---|
| Centre-ville | I | stockage, population +10, villageois, point de départ | 4×4 |
| Hutte | I | population +5 | 2×2 |
| Grenier | I | stockage nourriture | 2×2 |
| Camp de bûcherons | I | stockage bois | 2×2 |
| Carrière / mine | I | stockage pierre, fer, or | 2×2 |
| Champ | I | nourriture | 3×3 |
| Caserne | I | lanciers, archers | 3×3 |
| Forge | II | recherches d'armes/armures, guerriers de fer | 3×3 |
| Marché | II | échange de ressources, commerce | 3×3 |
| Rempart / porte | II | défense, bloque le passage | 1×1 |
| Tour de guet | II | défense, vision, garnison | 2×2 |
| Écurie | III | cavalerie | 3×3 |
| Chantier naval | III | pirogues | 4×4 |
| Palais | II→IV | changement d'âge | 5×5 |
| Forteresse | III | production élite, grosse défense | 5×5 |
| Autel | III | ressusciter le héros | 3×3 |
| Cité sacrée | — | objectif final de mission 7 | 7×7 |
| Monument | IV | bonus de civilisation, victoire par merveille | 5×5 |

**Placement** : aperçu fantôme vert/rouge, grille d'alignement, impossible sur ressources, unités ennemies ou terrain interdit ; **les unités alliées sur l'emplacement sont repoussées automatiquement**. Construction par plusieurs villageois : vitesse additive avec rendements décroissants. Réparation payante. Destruction ⇒ ruines temporaires, 20 % des ressources récupérables par aucun joueur (pas d'exploit).

---

## 9. Contrôles et interface

### 9.1 Principes communs
Sélection → clic de destination, comme AoE. Le clic droit (ou appui) sur une ressource = récolter ; sur un ennemi = attaquer ; sur un bâtiment allié = garnison/réparer ; sur le sol = déplacer.

### 9.2 Windows (souris/clavier)

| Action | Entrée |
|---|---|
| Sélection simple / rectangle | clic gauche / glisser |
| Ajouter à la sélection | Maj + clic |
| Tout sélectionner (même type visible) | double-clic |
| Ordre contextuel | clic droit |
| File d'ordres (waypoints) | Maj + clic droit |
| Groupes de contrôle | Ctrl + 0-9 / 0-9 |
| Pouvoirs | A, Z, E, R… (configurable) |
| Caméra | bords d'écran, flèches/WASD, molette = zoom, clic molette = glisser |
| Mini-carte | clic = déplacer la vue, clic droit = ordre |
| Pause / vitesse | Espace / +, - |
| Menu | Échap |

Mode fenêtre, plein écran, redimensionnement libre (taille mini 1024×576), échelle d'interface 80–150 %, support DPI élevé, plusieurs moniteurs.

### 9.3 Android (tactile)

| Action | Geste |
|---|---|
| Sélection | toucher / glisser sur l'écran pour une zone (bouton « sélection multiple » activable) |
| Déplacer | sélectionner puis toucher la destination |
| Caméra | glisser à un doigt sur le terrain vide, pincer pour zoomer |
| Attaque/récolte | toucher la cible (ordre contextuel automatique) |
| Pouvoirs | boutons larges dans la barre du bas, visibilité du cooldown |
| Ordres en file | bouton « file » |
| Annuler | toucher en dehors de la sélection |

Précautions tactiles : cibles ≥ 48 dp, **tolérance de toucher** (le doigt cache la cible : on choisit la cible la plus proche dans un rayon de 28 dp), prévention des appuis accidentels sur des actions destructrices (suppression de bâtiment = confirmation), zones sûres (encoches), orientation paysage verrouillée.

### 9.4 HUD
Barre de ressources en haut, mini-carte en bas à gauche, panneau de sélection et actions en bas, file d'événements (attaque en cours, bâtiment terminé), alertes visuelles et sonores d'attaque sur la mini-carte, indicateur de villageois inactifs (touche point `.`).

### 9.5 Accessibilité
Mode daltonien (formes + couleurs des joueurs), échelle de texte, sous-titres, vibrations optionnelles, rebinding des touches, vitesse de jeu réduite.

---

## 10. Équilibrage

- Toutes les valeurs dans `assets/data/*.json` : **aucune constante de gameplay dans le code**.
- Outil `tool/balance_sim` : joue des milliers de parties IA contre IA, par couples de clans et d'âges, génère un rapport (taux de victoire par clan, durée moyenne, ressources collectées, unités les plus rentables). Seuils d'acceptation : chaque clan entre **45 % et 55 %** de victoires en miroir de difficulté ; aucune unité utilisée à plus de 40 % ou moins de 3 % dans les armées gagnantes.
- Tests de « coût/valeur » : puissance d'une unité (PV × dégâts × vitesse^k) rapportée à son coût doit rester dans une fourchette de ±15 % au sein d'un même âge.
- Cadence d'une partie type : 25–45 min pour une moyenne carte en Normal.
- Courbes de difficulté de la campagne validées par au moins 3 sessions de test humain par mission.

---

## 11. Mode Village persistant (Clash of Clans)

### 11.1 Fonctionnement
- Le village est une petite carte (40×40) : bâtiments de production passive (champs, scieries, mines), stockages, défenses (tours, remparts, pièges), caserne, laboratoire de recherche, autel.
- Améliorations qui coûtent des ressources du village et du **temps** ; les ressources du village se collectent passivement.
- Les ressources du village servent à : améliorer les unités (niveaux 1–10 qui augmentent légèrement les stats en partie), débloquer des héros et cosmétiques, acheter des sorts de bataille.
- **Les gains de partie classique** (campagne, escarmouche) alimentent le village (pas de contrainte d'être en ligne).

### 11.2 Temps hors ligne : la partie risquée
Les timers du jeu hors ligne s'appuient sur l'horloge de l'appareil, que le joueur peut modifier. Règles pour éviter bugs et exploits graves :
- Durée écoulée = `max(0, maintenant − dernier_temps)`, **plafonnée** (24 h pour la collecte passive, 8 h pour un chantier).
- Si l'heure recule : on ne punit pas, on **ignore** (écoulé = 0) et on enregistre un `dernier_temps` corrigé.
- Un compteur monotone (`Stopwatch` pendant l'exécution) sert de garde-fou contre le saut d'horloge en cours de session.
- L'horloge n'est jamais utilisée dans la simulation d'une partie (seulement dans la méta-progression).
- Les timers longs peuvent être raccourcis par une **monnaie gagnée en jouant** (pas d'achat) pour éviter la frustration.

### 11.3 Raids
- **Attaque** : tu choisis l'armée parmi les unités débloquées et des sorts, tu lances le raid sur un village IA généré (déterministe, selon un niveau de trophées) ; tu gagnes des étoiles (détruire 50 % / Centre-ville / 100 %) et des ressources.
- **Défense** : la simulation de raid IA contre ton village se déroule **en tâche de fond hors écran à l'ouverture** du jeu (journal de raids), sans interaction. Le résultat est calculé de façon déterministe avec le temps écoulé et les défenses en place ; le joueur voit un rapport. **Perte plafonnée** (max 25 % de chaque ressource, jamais le centre-ville).
- Aucune notification push (hors ligne), rapports à l'ouverture.

### 11.4 Contenu minimal pour la v1.0 du Village
Niveaux max 5 pour les bâtiments, 10 niveaux de troupes, 6 sorts, 40 villages IA types, 3 héros améliorables.

---

## 12. Direction artistique et audio

### 12.1 Choix recommandé pour les assets
Stratégie en 3 temps :
1. **Développement (phases 1–5)** : placeholders générés par code (losanges colorés, silhouettes). Le gameplay est validé sans dépendre de l'art. Les `SpriteDef` pointent vers des clés d'asset ; remplacer un placeholder = changer un fichier.
2. **Production (phases 6–8)** : packs isométriques **sous licence compatible commerciale** (vérifier chaque licence, la consigner dans `ASSETS_LICENSES.md` : Kenney = CC0, itch.io = lire chaque licence, OpenGameArt = CC0/CC-BY avec attribution), complétés par des retouches pour l'identité visuelle africaine centrale (patterns, couleurs, architecture) avec Krita/Aseprite.
3. **Option** : commande à un artiste pixel art pour héros, bâtiments uniques et écrans clés.

Recommandation : **ne pas générer les sprites animés d'unités par IA** (incohérence de style et de 8 directions, nombreux frames), mais l'IA est pertinente pour les illustrations de menus, portraits et fonds de cinématiques.

### 12.2 Spécifications des assets
- Tuile 128×64 px, bâtiments multiples de la tuile, unités 64×64 à 96×96, animations : idle (4 frames), marche (8), attaque (6), récolte (6), mort (6), 5 directions + miroir, ombre séparée.
- Atlas ≤ 2048×2048 ; compressions PNG ; budget mémoire texture ≤ 150 Mo sur Android.
- Palette par joueur : zones de couleur séparées (masque) pour teinter selon l'équipe.

### 12.3 Audio
Musique d'ambiance par âge (4 pistes, boucles propres), effets (≈ 120), voix off optionnelle absente, limite de 24 voix simultanées avec priorité, réglages musique/effets/global, coupure automatique en arrière-plan. Alertes sonores d'attaque, de fin de construction.

### 12.4 Langues
Français par défaut, anglais en second, tous les textes dans des fichiers `i18n/*.arb`, aucun texte en dur. Polices à jeu complet de caractères accentués.

---

## 13. Qualité : comment viser « pas de bug »

### 13.1 Pyramide de tests

| Niveau | Quoi | Cible |
|---|---|---|
| Unitaires | chaque système de la simulation (récolte, combat, pouvoirs, etc.) | couverture `sim/` ≥ 90 % |
| Propriétés | invariants sur séquences aléatoires de commandes (voir ci-dessous) | exécutés à chaque PR, 1 000+ cas |
| Déterminisme | même graine + commandes ⇒ même hash d'état ; sauvegarde → chargement → même suite | à chaque PR |
| Simulation de masse | 5 000 parties IA contre IA headless par nuit, toutes cartes/clans | zéro blocage, zéro invariant violé |
| Golden (rendu) | captures de référence du rendu iso (tri de profondeur, brouillard, HUD) | à chaque PR |
| Intégration | parcours complet d'un menu à la victoire (`integration_test`) | Windows + émulateur Android |
| Soak | partie de 4 h en vitesse ×8 sans fuite mémoire, FPS stable | avant chaque version |
| Appareils réels | 3 téléphones (bas/moyen/haut de gamme) + 1 tablette + 2 PC | avant chaque jalon |

### 13.2 Invariants vérifiés automatiquement en continu (assertions en debug, journalisés en release)
1. Ressources ≥ 0.
2. Population courante ≤ plafond (à la création) et ≥ 0.
3. Aucune entité sur une case bloquée ; aucune unité hors carte.
4. Toute unité vivante a des PV > 0 ; toute unité morte est retirée au tick suivant.
5. Toute référence d'ID vers une entité supprimée est nettoyée (pas de pointeur pendant).
6. File de production : coûts payés = coûts remboursables.
7. Aucune unité en état `Moving` sans chemin, sans cible, ni compteur d'échec.
8. Tick après tick : hash d'état stable en rejouant.
9. Au plus un héros vivant par joueur.
10. Un bâtiment détruit libère exactement sa surface.

### 13.3 Cas limites à couvrir explicitement (liste de contrôle)

**Combat et ciblage**
- Cible morte avant impact d'un projectile ; cible qui disparaît dans le brouillard ; cible garnisonnée.
- Deux unités tuent la même cible au même tick ; deux QG détruits au même tick (égalité → règle de départage définie : le joueur qui a perdu son dernier bâtiment/unité en premier selon l'ordre déterministe de résolution, ou match nul affiché).
- Friendly fire des zones : défini par pouvoir, testé.
- Unité attaquée pendant qu'elle bâtit : choix (riposter si militaire, fuir si villageois) ; configurable par stance (agressif/défensif/passif).

**Économie**
- Ressource à 0 pendant la file ; annulation en milieu de production ; coût des recherches modifié pendant leur mise en attente.
- Dépôt détruit pendant que le villageois porte des ressources ; ressource tarie ; chargement plein sans stockage.
- Plafond de population atteint pendant qu'on met en file.

**Construction et placement**
- Placement simultané par deux villageois sur la même zone ; bâtiment posé sur un chemin d'unité en mouvement ; bâtiment en construction détruit (remboursement 0 / partiel défini).
- Mur fermant totalement une base (l'IA doit pouvoir percer ; la validation de carte ne le sur-interdit pas).
- Construction hors brouillard connu (interdite).

**Navigation**
- Cible inaccessible (île) ; cible entourée ; pont/gué qui disparaît ; navire sur eau peu profonde ; unités qui se bloquent mutuellement dans un couloir ; garnison pleine.

**Pause, sauvegarde, cycle de vie**
- Ordre donné en pause ; sauvegarde en plein combat ; chargement d'une sauvegarde plus récente/plus ancienne que l'app (migration + refus clair si trop récente) ; sauvegarde corrompue (bascule sur la précédente) ; disque plein ; écriture interrompue (écriture atomique : fichier temporaire + renommage + checksum).
- Android : application mise en arrière-plan (pause auto + sauvegarde auto), appel entrant, bouton retour, rotation, tuée par le système (reprise sur la dernière autosauvegarde), mémoire faible (libération de caches), mode économie d'énergie (30 FPS), écran éteint.
- Windows : réduction/restauration, changement de DPI ou de moniteur, mise en veille du PC, perte de focus (pause auto), fermeture pendant l'écriture.

**Campagne**
- Objectifs simultanés ; objectif échoué après réussite ; mission rejouée ; déblocage entre missions avec sauvegarde mi-parcours ; défaite et reprise.

**Village**
- Horloge modifiée, fuseau horaire changé, heure d'été ; absence de 6 mois ; améliorations simultanées au niveau max ; raid arrivé avec village vide ; plafonds de stockage.

**Saisie**
- Clic pendant transition d'écran ; double toucher accidentel ; multi-touch parasite pendant le placement ; appui sur plusieurs boutons de pouvoir ; touches maintenues perdues au défocus ; clic droit sur le HUD.

### 13.4 Tests de propriété (exemples)
- Pour toute suite aléatoire de 1 000 commandes valides ou invalides sur un monde aléatoire, aucun invariant §13.2 n'est violé et aucune exception n'est levée.
- `charger(sauvegarder(état)) == état` (égalité structurelle) pour tout état atteignable.
- `rejouer(graine, commandes) == état` sur Windows et Android (tests de hash comparés).
- Génération de carte : toute carte est connexe pour les bases, et chaque base a ses ressources garanties.

### 13.5 Outils de diagnostic intégrés
- **Mode debug** (menu caché) : affichage des chemins, occupation, états des unités, IDs, FPS, mémoire, ticks de simulation.
- **Journal local** circulaire (5 Mo) : exceptions, assertions, transitions illégales, résultats de pathfinding échoués ; bouton « Exporter le rapport de bug » (génère un fichier à envoyer manuellement).
- **Replay automatique** : les 30 dernières minutes de commandes sont gardées ; en cas de crash, le replay sert à reproduire.
- `FlutterError.onError` et `PlatformDispatcher.instance.onError` capturent tout ; une erreur d'un système de simulation ne fait pas planter l'app : l'entité fautive est isolée, la partie propose de sauvegarder et quitter.

### 13.6 Processus
- Intégration continue (GitHub Actions) : `flutter analyze` sans avertissement, formatage, tests, tests de propriétés, golden, build Windows et Android.
- Branches courtes, revue de chaque changement (y compris par `/code-review`), `CHANGELOG.md`.
- **Règle d'or** : un bug corrigé reçoit toujours un test de non-régression.
- Gel des fonctionnalités avant chaque jalon : une phase de stabilisation sans nouvelle fonctionnalité.

---

## 14. Performance

| Cible | Valeur |
|---|---|
| Windows | 60 FPS stables, 200 unités + 300 bâtiments/ressources visibles |
| Android milieu de gamme | 60 FPS (≥ 45 sur 200 pop) |
| Android bas de gamme (2 Go RAM) | 30 FPS, cap population 150 automatique, effets réduits |
| Mémoire | ≤ 500 Mo sur PC, ≤ 350 Mo sur Android |
| Taille de l'APK | ≤ 150 Mo (AAB avec assets compressés) |
| Démarrage à froid | ≤ 3 s menu, ≤ 8 s chargement d'une partie moyenne |
| Simulation | ≤ 8 ms par tick sur le plus faible appareil cible |
| Batterie | 30 FPS en mode économie, pas de wake locks inutiles |

Techniques : grille spatiale de hachage pour requêtes de proximité, tableaux typés (structure de tableaux) pour les entités chaudes, pas d'allocation dans la boucle chaude (pools pour projectiles et effets), isolates pour la génération de carte et les raids hors écran, profil automatique de qualité au premier lancement.

---

## 15. Plateformes

### Windows
- Cible Windows 10/11 x64, installateur MSIX ou Inno Setup, plein écran borderless, sauvegardes dans `%APPDATA%`, aucune dépendance runtime à installer à part VC++ (inclus).

### Android
- minSdk 24 (Android 7), targetSdk à jour, ABI arm64-v8a (+ armeabi-v7a si nécessaire), AAB pour Play Store (App Bundle) + APK pour diffusion directe.
- **Permissions : aucune** (pas d'INTERNET) — argument de confidentialité. Stockage interne de l'application uniquement.
- Gestion des encoches, barres système immersives, `onTrimMemory`, services : aucun.
- Signature de la clé de publication à conserver dans un coffre (perte = impossibilité de mettre à jour).

### Questions de publication (à trancher avant la phase 9)
- Distribution : Microsoft Store / Play Store / itch.io / directe ? Cela détermine l'emballage, les politiques de contenu et la classification d'âge.

---

## 16. Sauvegarde et données

- **Format** : en-tête (magie, version de format, version du jeu, checksum CRC32) + charge utile (JSON compressé ou binaire).
- **Écriture atomique** : écrire `slot.tmp`, vérifier, renommer en `slot.sav` en conservant `slot.bak`.
- **Migrations** : chaque changement de schéma incrémente la version ; une chaîne de migrateurs testée par des fichiers de sauvegarde historiques conservés dans `test/fixtures/saves/`.
- **Emplacements** : 5 slots manuels + autosave toutes les 2 min en jeu (rotation de 3) + autosave à la mise en arrière-plan.
- **Profil** : progression de campagne, déblocages, village, paramètres, succès — fichier séparé de l'état d'une partie.
- **Intégrité** : si le checksum échoue, tenter `.bak`, sinon message clair et proposition de réinitialisation sélective (jamais de crash au chargement).
- **Compatibilité PC ↔ Android** : même format (garantie par la simulation déterministe et les fixtures croisées).

---

## 17. Campagne détaillée

Mise en place du scénario du document source, avec les compléments techniques :

| # | Mission | Objectif principal | Objectifs secondaires | Récompense | Systèmes nouveaux |
|---|---|---|---|---|---|
| 1 | Le Village au bord du fleuve (tutoriel) | 3 huttes, 200 nourriture, 5 villageois | passer à l'âge II | Palais | récolte, construction, âge |
| 2 | L'ombre du Corbeau | survivre 12 min, bâtir une caserne | tuer 30 pillards | lanciers | vagues d'IA, défense |
| 3 | Le clan des Pêcheurs | protéger 3 villages (sans les conquérir) | sauver 10 pêcheurs | pirogues | eau, navires, persuasion par protection |
| 4 | Le clan des Forgerons | prendre une mine de fer, résister à l'embuscade | ne perdre aucune forge | guerriers de fer, forge | montagnes, mines, attaque surprise |
| 5 | La Grande Caravane | escorter la caravane 20 min | zéro perte de chariot | marché, routes | escorte, IA ennemie en embuscade |
| 6 | Le clan des Cavaliers | battre le champion (duel d'armées) puis s'allier | capturer 3 puits | cavalerie | savane, bataille ouverte |
| 7 | La Cité sacrée | détruire les défenses, poser le Tambour au centre | sauver les prisonniers | fin | siège, boss Kaba |

**Fins multiples** : Kaba vaincu (conquête) ou exilé (si les alliés sont tous sauvés et aucune ville alliée détruite). Le choix est enregistré dans le profil.

**Moteur de missions** : fichier JSON déclarant carte, joueurs, objectifs (avec états : en attente/réussi/échoué), déclencheurs (« à T = 3 min, vague A », « quand le joueur possède X, dialogue Y »), dialogues et conditions de victoire/défaite. Un **validateur** de missions échoue en CI si un objectif est impossible à atteindre (références manquantes, ressources insuffisantes sur la carte, etc.).

Chaque mission est **rejouable** avec trois difficultés et un classement d'étoiles (temps, pertes, objectifs bonus).

---

## 18. Conditions de victoire (escarmouche)

- Conquête (détruire tous les bâtiments et unités militaires ennemis ; les villageois isolés ne comptent pas après 60 s).
- Régicide (tuer le héros / le chef).
- Merveille (Monument tenu 10 min).
- Course à l'âge d'Or.
- Défaite : plus de bâtiments de production et plus d'unités.
- Match nul si deux conditions de défaite sont remplies au même tick.
- Reddition possible à tout moment.

---

## 19. Risques et parades

| Risque | Gravité | Parade |
|---|---|---|
| Ampleur (RTS + Clash + campagne) trop grande | **Critique** | Roadmap par jalons jouables ; chaque phase livre quelque chose de complet ; gel des fonctionnalités ; contenu en dernier |
| Pathfinding de masse défaillant | Haute | Phase dédiée ; tests de stress ; chiens de garde de blocage |
| Performances Android | Haute | Budget FPS dès la phase 1 ; tests sur vrai téléphone chaque phase |
| Désynchronisation PC/Android (flottants) | Haute | Entiers à virgule fixe, tests de hash croisés |
| Perte de sauvegarde | Haute | Écriture atomique, backups, fixtures de migration |
| Équilibrage injouable | Moyenne | Simulation de masse, données externes |
| Assets incohérents | Moyenne | Spécification stricte, un seul pack principal, retouche de palette |
| Exploits d'horloge | Moyenne | Plafonds, monotonicité, simulation sans horloge |
| Dérive de dépendances | Moyenne | Verrouillage, mises à jour planifiées |
| Épuisement du développeur | Haute | Périmètre v1.0 défini (§20), « après v1 » séparé |

---

## 20. Périmètre par version

**v1.0** : campagne 7 missions, escarmouche (4 clans + Corbeaux déblocable), 3 IA difficultés, pouvoirs et héros, Village + raids simplifiés, sauvegardes, FR/EN, Windows + Android.

**v1.1+ (après)** : défi quotidien étendu, éditeur de cartes, deux joueurs local, succès, plus de cartes, nouvelles factions, modding de données JSON.

---

## 21. Questions encore ouvertes (n'empêchent pas de commencer)

1. Distribution : Play Store, Microsoft Store, itch.io, directe ?
2. Budget assets : gratuit uniquement, ou budget pour des packs/un artiste ?
3. Langues au lancement : FR + EN suffisent ?
4. Appareil Android le plus faible à supporter (RAM/année) ?
5. Le jeu est-il gratuit, payant, ou diffusé en privé ? (impacte la licence des assets)
6. Souhaites-tu des cinématiques (images fixes avec voix) ou seulement des dialogues texte ?

Valeurs par défaut utilisées en attendant : diffusion directe + itch.io, assets gratuits CC0/CC-BY, FR+EN, 3 Go de RAM minimum, dialogues texte avec portraits.
