import 'dart:convert';
import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';

/// Statistiques de fin de partie (n'influencent jamais la simulation).
class PlayerStats {
  int unitsKilled = 0;
  int unitsLost = 0;
  int buildingsDestroyed = 0;
  int buildingsLost = 0;
  int damageDealt = 0;
  int unitsTrained = 0;
  int buildingsBuilt = 0;
  int researches = 0;
  int peakArmy = 0;
  int heroDeaths = 0;
  int powersUsed = 0;
  int spellsCast = 0;
  final List<int> gathered = List<int>.filled(Res.values.length, 0);

  int get totalGathered => gathered.fold(0, (a, b) => a + b);

  List<int> toList() => <int>[
    unitsKilled,
    unitsLost,
    buildingsDestroyed,
    buildingsLost,
    damageDealt,
    unitsTrained,
    buildingsBuilt,
    researches,
    peakArmy,
    heroDeaths,
    powersUsed,
    spellsCast,
    ...gathered,
  ];

  static PlayerStats fromList(List<int> l) {
    final s = PlayerStats()
      ..unitsKilled = l[0]
      ..unitsLost = l[1]
      ..buildingsDestroyed = l[2]
      ..buildingsLost = l[3]
      ..damageDealt = l[4]
      ..unitsTrained = l[5]
      ..buildingsBuilt = l[6]
      ..researches = l[7]
      ..peakArmy = l[8]
      ..heroDeaths = l[9]
      ..powersUsed = l[10]
      ..spellsCast = l[11];
    for (var i = 0; i < s.gathered.length && 12 + i < l.length; i++) {
      s.gathered[i] = l[12 + i];
    }
    return s;
  }
}

/// État d'un joueur : ressources, âge, recherches, brouillard, clan, tambour.
class Player {
  Player(this.id, int mapSize)
    : stock = Stock(),
      team = id,
      explored = Uint8List(mapSize),
      visible = Uint8List(mapSize);

  final int id;
  Stock stock;
  int age = 0;

  /// Indice du clan dans `Defs.clans` (-1 : aucun, parties de test).
  int clan = -1;

  /// Équipe : les joueurs d'une même équipe sont alliés.
  int team;

  /// -1 = humain, sinon indice de difficulté de l'IA.
  int aiLevel = -1;

  /// Bonus de récolte (%) accordé à l'IA (difficulté Difficile).
  int aiGatherBonus = 0;

  bool defeated = false;
  bool resigned = false;

  /// Tick de défaite (-1 tant que le joueur est en jeu).
  int defeatTick = -1;

  /// Tick depuis lequel le joueur n'a plus de bâtiment vital (-1 : il en a).
  int noVitalSince = -1;

  /// Énergie du tambour (sorts de bataille).
  int drum = 0;

  /// Recharge restante de chaque pouvoir/sort (ticks, indexée par pouvoir).
  List<int> spellCd = <int>[];

  /// Héros tombés (indices d'unités) : leur résurrection coûte plus cher.
  final List<int> fallenHeroes = <int>[];

  final PlayerStats stats = PlayerStats();

  /// Identifiants (unités, bâtiments, recherches) interdits à ce joueur :
  /// déblocages de campagne. Vide en escarmouche.
  final Set<String> locked = <String>{};

  /// Mémoire de l'IA (hors hash : l'IA n'est qu'un producteur de commandes).
  /// 0 dernier score de progrès, 1 tick du dernier progrès, 2 état d'attaque
  /// (0 rassemblement, 1 offensive, 2 retraite), 3-4 cible (case), 5 nombre de
  /// vagues, 6 déclenchements du chien de garde, 7 fin de retraite.
  final List<int> aiMem = List<int>.filled(8, 0);

  /// Indices (triés) des recherches terminées.
  final List<int> techs = <int>[];

  /// Case de départ (centre-ville initial).
  int startX = 0;
  int startY = 0;

  /// Bonus de portage cumulé (recherches).
  int carryBonus = 0;

  /// Bonus de récolte en % par ressource (recherches, clan, difficulté).
  final List<int> gatherPercent = List<int>.filled(Res.values.length, 0);

  /// Modificateurs `statistique:catégorie` → valeur (recherches et clan).
  final Map<String, int> mods = <String, int>{};

  /// Population courante et plafond (recalculés à chaque tick).
  int popUsed = 0;
  int popCap = 0;

  /// 0 = inconnu / 1 = exploré. Persistant.
  final Uint8List explored;

  /// 1 = visible ce tick. Dérivé de la position des entités.
  final Uint8List visible;

  bool hasTech(int index) => techs.contains(index);

  bool alliedWith(Player o) => o.team == team;

  void addTech(TechDef tech) {
    if (techs.contains(tech.index)) return;
    techs
      ..add(tech.index)
      ..sort();
    tech.effects.forEach(applyEffect);
  }

  void applyEffect(TechEffect e) {
    switch (e.stat) {
      case 'carry':
        carryBonus += e.add;
      case 'gather':
        for (final r in Res.values) {
          if (e.res == null || e.res == r) gatherPercent[r.index] += e.percent;
        }
      default:
        final key = '${e.stat}:${e.cls}';
        mods[key] = (mods[key] ?? 0) + e.percent + e.add;
    }
  }

  /// Recalcule les bonus dérivés (clan + recherches + difficulté).
  void rebuildStats(Defs defs) {
    carryBonus = 0;
    for (var i = 0; i < gatherPercent.length; i++) {
      gatherPercent[i] = aiGatherBonus;
    }
    mods.clear();
    if (clan >= 0 && clan < defs.clans.length) {
      defs.clans[clan].effects.forEach(applyEffect);
    }
    for (final t in techs) {
      defs.techs[t].effects.forEach(applyEffect);
    }
  }

  /// Somme des modificateurs [stat] qui s'appliquent à cette unité.
  int mod(String stat, UnitDef def) {
    var sum = mods['$stat:all'] ?? 0;
    if (mods.isEmpty) return sum;
    for (final c in def.classes) {
      sum += mods['$stat:$c'] ?? 0;
    }
    if (def.military) sum += mods['$stat:military'] ?? 0;
    return sum;
  }

  /// Somme des modificateurs [stat] qui s'appliquent aux bâtiments.
  int buildingMod(String stat) =>
      (mods['$stat:all'] ?? 0) + (mods['$stat:building'] ?? 0);

  int carryCapacity(UnitDef def) => def.carryCapacity + carryBonus;

  /// Millièmes de ressource récoltés par tick pour ce type d'unité.
  int gatherPerTick(UnitDef def, Res res) {
    final base = def.gatherRates[res] ?? 0;
    return base * (100 + gatherPercent[res.index]) ~/ 1000;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'stock': stock.toJson(),
    'age': age,
    'techs': techs,
    'sx': startX,
    'sy': startY,
    'explored': base64Encode(explored),
    'clan': clan,
    'team': team,
    'ai': aiLevel,
    'aiBonus': aiGatherBonus,
    'defeated': defeated,
    'resigned': resigned,
    'defeatTick': defeatTick,
    'noVital': noVitalSince,
    'drum': drum,
    'spellCd': spellCd,
    'fallen': fallenHeroes,
    'stats': stats.toList(),
    'aim': aiMem,
    if (locked.isNotEmpty) 'locked': (locked.toList()..sort()),
  };

  static Player fromJson(
    Map<String, dynamic> j,
    int mapSize,
    Defs defs,
  ) {
    final p = Player(j['id'] as int, mapSize)
      ..stock = Stock.fromJson(j['stock'])
      ..age = j['age'] as int
      ..startX = j['sx'] as int
      ..startY = j['sy'] as int
      ..clan = j['clan'] as int
      ..team = j['team'] as int
      ..aiLevel = j['ai'] as int
      ..aiGatherBonus = j['aiBonus'] as int
      ..defeated = j['defeated'] as bool
      ..resigned = j['resigned'] as bool
      ..defeatTick = j['defeatTick'] as int
      ..noVitalSince = j['noVital'] as int
      ..drum = j['drum'] as int
      ..spellCd = List<int>.from(j['spellCd'] as List<dynamic>);
    p.fallenHeroes.addAll(List<int>.from(j['fallen'] as List<dynamic>));
    final lk = j['locked'];
    if (lk != null) p.locked.addAll(List<String>.from(lk as List<dynamic>));
    final st = PlayerStats.fromList(
      List<int>.from(j['stats'] as List<dynamic>),
    );
    p.stats
      ..unitsKilled = st.unitsKilled
      ..unitsLost = st.unitsLost
      ..buildingsDestroyed = st.buildingsDestroyed
      ..buildingsLost = st.buildingsLost
      ..damageDealt = st.damageDealt
      ..unitsTrained = st.unitsTrained
      ..buildingsBuilt = st.buildingsBuilt
      ..researches = st.researches
      ..peakArmy = st.peakArmy
      ..heroDeaths = st.heroDeaths
      ..powersUsed = st.powersUsed
      ..spellsCast = st.spellsCast;
    for (var i = 0; i < st.gathered.length; i++) {
      p.stats.gathered[i] = st.gathered[i];
    }
    final nPowers = defs.powers.length;
    if (p.spellCd.length > nPowers) p.spellCd = p.spellCd.sublist(0, nPowers);
    while (p.spellCd.length < nPowers) {
      p.spellCd.add(0);
    }
    final mem = List<int>.from(j['aim'] as List<dynamic>);
    for (var i = 0; i < mem.length && i < p.aiMem.length; i++) {
      p.aiMem[i] = mem[i];
    }
    p.explored.setAll(0, base64Decode(j['explored'] as String));
    final techList = List<int>.from(j['techs'] as List<dynamic>);
    for (final t in techList) {
      if (t >= 0 && t < defs.techs.length && !p.techs.contains(t)) {
        p.techs.add(t);
      }
    }
    p.techs.sort();
    p.rebuildStats(defs);
    return p;
  }
}
