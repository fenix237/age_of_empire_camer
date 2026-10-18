import 'dart:convert';

import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';

/// Erreur de donnée : fichier, chemin dans le fichier et explication claire.
class DataException implements Exception {
  DataException(this.file, this.path, this.message);

  final String file;
  final String path;
  final String message;

  @override
  String toString() => 'Donnée invalide [$file] $path : $message';
}

/// Ensemble des définitions chargées et validées.
class Defs {
  Defs._({
    required this.terrain,
    required this.resources,
    required this.units,
    required this.buildings,
    required this.ages,
    required this.techs,
    required this.balance,
  });

  /// Noms de fichiers attendus (sans extension) pour [Defs.fromFiles].
  static const List<String> fileNames = <String>[
    'terrain',
    'resources',
    'units',
    'buildings',
    'ages',
    'techs',
    'balance',
  ];

  final List<TerrainDef> terrain;
  final List<ResourceDef> resources;
  final List<UnitDef> units;
  final List<BuildingDef> buildings;
  final List<AgeDef> ages;
  final List<TechDef> techs;
  final BalanceDef balance;

  late final Map<String, UnitDef> _unitById = <String, UnitDef>{
    for (final u in units) u.id: u,
  };
  late final Map<String, BuildingDef> _buildingById = <String, BuildingDef>{
    for (final b in buildings) b.id: b,
  };
  late final Map<String, TechDef> _techById = <String, TechDef>{
    for (final t in techs) t.id: t,
  };
  late final Map<String, ResourceDef> _resById = <String, ResourceDef>{
    for (final r in resources) r.id: r,
  };

  UnitDef unit(String id) => _unitById[id]!;
  BuildingDef building(String id) => _buildingById[id]!;
  TechDef tech(String id) => _techById[id]!;
  ResourceDef resource(String id) => _resById[id]!;
  UnitDef? tryUnit(String id) => _unitById[id];
  BuildingDef? tryBuilding(String id) => _buildingById[id];
  TechDef? tryTech(String id) => _techById[id];

  /// Charge depuis le texte JSON de chaque fichier (clé = nom sans extension).
  static Defs fromFiles(Map<String, String> files) {
    final parsed = <String, Map<String, dynamic>>{};
    for (final name in fileNames) {
      final text = files[name];
      if (text == null) throw DataException(name, '', 'fichier manquant');
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) {
          throw DataException(name, '', "l'objet racine est attendu");
        }
        parsed[name] = decoded;
      } on FormatException catch (e) {
        throw DataException(name, '', 'JSON illisible : ${e.message}');
      }
    }
    return fromJson(parsed);
  }

  static Defs fromJson(Map<String, Map<String, dynamic>> files) {
    final terrain = <TerrainDef>[];
    var root = _Obj('terrain', r'$', files['terrain']!);
    var i = 0;
    for (final o in root.objList('terrain')) {
      terrain.add(
        TerrainDef(
          id: o.str('id'),
          index: i++,
          walkable: o.boolean('walkable'),
          speedPercent: o.integer('speedPercent', min: 0, max: 400),
          moveCost: o.integer('moveCost', min: 10, max: 1000),
          buildable: o.boolean('buildable'),
        ),
      );
    }
    _unique('terrain', terrain.map((e) => e.id));
    if (terrain.isEmpty) {
      throw DataException('terrain', r'$.terrain', 'au moins un terrain');
    }

    final resources = <ResourceDef>[];
    root = _Obj('resources', r'$', files['resources']!);
    i = 0;
    for (final o in root.objList('resources')) {
      resources.add(
        ResourceDef(
          id: o.str('id'),
          index: i++,
          res: o.res('res'),
          amount: o.integer('amount', min: 1, max: 1000000),
        ),
      );
    }
    _unique('resources', resources.map((e) => e.id));

    final units = <UnitDef>[];
    root = _Obj('units', r'$', files['units']!);
    i = 0;
    for (final o in root.objList('units')) {
      final rates = <Res, int>{};
      final ratesObj = o.optObj('gatherRates');
      if (ratesObj != null) {
        for (final k in ratesObj.keys) {
          final r = Res.tryParse(k);
          if (r == null) {
            throw DataException(
              o.file,
              '${o.path}.gatherRates.$k',
              'ressource inconnue',
            );
          }
          rates[r] = ratesObj.integer(k, min: 1, max: 100000);
        }
      }
      final villager = o.boolean('villager', def: false);
      final carry = o.integer('carryCapacity', min: 0, max: 1000, def: 0);
      if (villager && (carry == 0 || rates.isEmpty)) {
        throw DataException(
          o.file,
          o.path,
          'un villageois doit avoir carryCapacity > 0 et gatherRates',
        );
      }
      units.add(
        UnitDef(
          id: o.str('id'),
          index: i++,
          age: o.integer('age', min: 0, max: 9),
          cost: o.cost('cost'),
          trainSeconds: o.integer('trainSeconds', min: 1, max: 3600),
          hp: o.integer('hp', min: 1, max: 100000),
          attack: o.integer('attack', min: 0, max: 100000),
          armor: o.integer('armor', min: 0, max: 1000, def: 0),
          range: o.integer('range', min: 0, max: 30, def: 0),
          attackCooldownTicks: o.integer(
            'attackCooldownTicks',
            min: 1,
            max: 1000,
            def: 15,
          ),
          speed: o.integer('speed', min: 1, max: 20000),
          vision: o.integer('vision', min: 1, max: 30),
          pop: o.integer('pop', min: 1, max: 20, def: 1),
          villager: villager,
          carryCapacity: carry,
          gatherRates: rates,
        ),
      );
    }
    _unique('units', units.map((e) => e.id));

    final techs = <TechDef>[];
    root = _Obj('techs', r'$', files['techs']!);
    i = 0;
    for (final o in root.objList('techs')) {
      final effects = <TechEffect>[];
      for (final e in o.objList('effects')) {
        final stat = e.str('stat');
        if (stat != 'carry' && stat != 'gather') {
          throw DataException(
            e.file,
            '${e.path}.stat',
            "'carry' ou 'gather' attendu, reçu '$stat'",
          );
        }
        effects.add(
          TechEffect(
            stat: stat,
            res: stat == 'gather' ? e.res('res') : null,
            add: e.integer('add', min: -1000, max: 1000, def: 0),
            percent: e.integer('percent', min: -100, max: 1000, def: 0),
          ),
        );
      }
      techs.add(
        TechDef(
          id: o.str('id'),
          index: i++,
          age: o.integer('age', min: 0, max: 9),
          cost: o.cost('cost'),
          researchSeconds: o.integer('researchSeconds', min: 1, max: 3600),
          effects: effects,
        ),
      );
    }
    _unique('techs', techs.map((e) => e.id));

    final buildings = <BuildingDef>[];
    root = _Obj('buildings', r'$', files['buildings']!);
    i = 0;
    for (final o in root.objList('buildings')) {
      final size = o.intList('size');
      if (size.length != 2 || size.any((s) => s < 1 || s > 16)) {
        throw DataException(
          o.file,
          '${o.path}.size',
          '[largeur, hauteur] entre 1 et 16',
        );
      }
      buildings.add(
        BuildingDef(
          id: o.str('id'),
          index: i++,
          age: o.integer('age', min: 0, max: 9),
          width: size[0],
          height: size[1],
          cost: o.cost('cost'),
          buildSeconds: o.integer('buildSeconds', min: 1, max: 3600),
          hp: o.integer('hp', min: 1, max: 1000000),
          armor: o.integer('armor', min: 0, max: 1000, def: 0),
          vision: o.integer('vision', min: 1, max: 30),
          popBonus: o.integer('popBonus', min: 0, max: 200, def: 0),
          dropOff: o.strList('dropOff', def: const <String>[]).map((s) {
            final r = Res.tryParse(s);
            if (r == null) {
              throw DataException(
                o.file,
                '${o.path}.dropOff',
                "ressource inconnue '$s'",
              );
            }
            return r;
          }).toList(),
          trains: o.strList('trains', def: const <String>[]),
          researches: o.strList('researches', def: const <String>[]),
          garrison: o.integer('garrison', min: 0, max: 200, def: 0),
          fieldFood: o.integer('fieldFood', min: 0, max: 100000, def: 0),
          requires: o.strList('requires', def: const <String>[]),
          market: o.boolean('market', def: false),
          townCenter: o.boolean('townCenter', def: false),
          startsComplete: o.boolean('startsComplete', def: false),
        ),
      );
    }
    _unique('buildings', buildings.map((e) => e.id));

    final ages = <AgeDef>[];
    root = _Obj('ages', r'$', files['ages']!);
    i = 0;
    for (final o in root.objList('ages')) {
      ages.add(
        AgeDef(
          id: o.str('id'),
          index: i++,
          cost: o.cost('cost'),
          researchSeconds: o.integer('researchSeconds', min: 0, max: 3600),
          requiresBuildings: o.strList(
            'requiresBuildings',
            def: const <String>[],
          ),
        ),
      );
    }
    _unique('ages', ages.map((e) => e.id));
    if (ages.isEmpty) {
      throw DataException('ages', r'$.ages', 'au moins un âge');
    }

    final balance = _parseBalance(_Obj('balance', r'$', files['balance']!));

    final defs = Defs._(
      terrain: terrain,
      resources: resources,
      units: units,
      buildings: buildings,
      ages: ages,
      techs: techs,
      balance: balance,
    );
    defs._validateReferences();
    return defs;
  }

  static BalanceDef _parseBalance(_Obj o) {
    final mg = o.obj('mapGen');
    final speeds = o.intList('buildSpeedMilli');
    if (speeds.length < 2 || speeds.any((s) => s < 0)) {
      throw DataException(
        o.file,
        r'$.buildSpeedMilli',
        'liste de >= 2 entiers positifs',
      );
    }
    return BalanceDef(
      startingResources: o.cost('startingResources'),
      startingVillagers: o.integer('startingVillagers', min: 0, max: 50),
      maxPopulation: o.integer('maxPopulation', min: 1, max: 1000),
      maxQueue: o.integer('maxQueue', min: 1, max: 50),
      buildSpeedMilli: speeds,
      repairCostPercent: o.integer('repairCostPercent', min: 0, max: 200),
      repairSpeedPercent: o.integer('repairSpeedPercent', min: 1, max: 1000),
      marketFeePercent: o.integer('marketFeePercent', min: 0, max: 99),
      pathRequestsPerTick: o.integer('pathRequestsPerTick', min: 1, max: 1000),
      pathNodeLimit: o.integer('pathNodeLimit', min: 100, max: 1000000),
      stuckReplanTicks: o.integer('stuckReplanTicks', min: 1, max: 1000),
      stuckTeleportTicks: o.integer('stuckTeleportTicks', min: 2, max: 2000),
      flowFieldGroupMin: o.integer('flowFieldGroupMin', min: 2, max: 1000),
      separationRadius: o.integer('separationRadius', min: 0, max: 256),
      idleSearchRadius: o.integer('idleSearchRadius', min: 1, max: 64),
      fieldGatherers: o.integer('fieldGatherers', min: 1, max: 20),
      reseedCostWood: o.integer('reseedCostWood', min: 0, max: 10000),
      queueRefundPercent: o.integer('queueRefundPercent', min: 0, max: 100),
      vision: o.integer('vision', min: 1, max: 30),
      hashEveryTicks: o.integer('hashEveryTicks', min: 1, max: 1000),
      visionEveryTicks: o.integer('visionEveryTicks', min: 1, max: 100),
      mapGen: MapGenDef(
        baseClearRadius: mg.integer('baseClearRadius', min: 2, max: 30),
        playerRingPercent: mg.integer('playerRingPercent', min: 20, max: 90),
        noiseScale: mg.integer('noiseScale', min: 2, max: 64),
        waterLevel: mg.integer('waterLevel', min: 0, max: 255),
        deepWaterLevel: mg.integer('deepWaterLevel', min: 0, max: 255),
        mountainLevel: mg.integer('mountainLevel', min: 0, max: 255),
        forestThreshold: mg.integer('forestThreshold', min: 0, max: 255),
        treesPerStartForest: mg.integer(
          'treesPerStartForest',
          min: 0,
          max: 200,
        ),
        startForests: mg.integer('startForests', min: 0, max: 10),
        startBerries: mg.integer('startBerries', min: 0, max: 30),
        startStone: mg.integer('startStone', min: 0, max: 30),
        startIron: mg.integer('startIron', min: 0, max: 30),
        startGold: mg.integer('startGold', min: 0, max: 30),
        startGame: mg.integer('startGame', min: 0, max: 30),
        scatterPerThousand: mg.integer('scatterPerThousand', min: 0, max: 200),
        maxAttempts: mg.integer('maxAttempts', min: 1, max: 1000),
      ),
    );
  }

  void _validateReferences() {
    const required = <String>['grass', 'deep', 'shallow'];
    for (final t in required) {
      if (!terrain.any((e) => e.id == t)) {
        throw DataException('terrain', r'$.terrain', "terrain '$t' requis");
      }
    }
    const rIds = <String>[
      'tree',
      'berries',
      'game',
      'quarry',
      'iron_mine',
      'gold_mine',
    ];
    for (final id in rIds) {
      if (!_resById.containsKey(id)) {
        throw DataException(
          'resources',
          r'$.resources',
          "ressource '$id' requise",
        );
      }
    }
    if (!units.any((u) => u.villager)) {
      throw DataException('units', r'$.units', 'un villageois est requis');
    }
    if (!buildings.any((b) => b.townCenter)) {
      throw DataException(
        'buildings',
        r'$.buildings',
        'un centre-ville est requis',
      );
    }
    for (final b in buildings) {
      for (final u in b.trains) {
        if (!_unitById.containsKey(u)) {
          throw DataException(
            'buildings',
            '${b.id}.trains',
            "unité inconnue '$u'",
          );
        }
      }
      for (final t in b.researches) {
        if (!_techById.containsKey(t)) {
          throw DataException(
            'buildings',
            '${b.id}.researches',
            "recherche inconnue '$t'",
          );
        }
      }
      for (final r in b.requires) {
        if (!_buildingById.containsKey(r)) {
          throw DataException(
            'buildings',
            '${b.id}.requires',
            "bâtiment inconnu '$r'",
          );
        }
      }
    }
    for (final a in ages) {
      for (final r in a.requiresBuildings) {
        if (!_buildingById.containsKey(r)) {
          throw DataException(
            'ages',
            '${a.id}.requiresBuildings',
            "bâtiment inconnu '$r'",
          );
        }
      }
    }
  }

  static void _unique(String file, Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        throw DataException(file, id, 'identifiant en double');
      }
    }
  }
}

/// Lecteur d'objet JSON avec messages d'erreur contextualisés.
class _Obj {
  _Obj(this.file, this.path, this.map);

  final String file;
  final String path;
  final Map<String, dynamic> map;

  Iterable<String> get keys => map.keys;

  Never _fail(String key, String msg) =>
      throw DataException(file, '$path.$key', msg);

  String str(String key) {
    final v = map[key];
    if (v is! String || v.isEmpty) _fail(key, 'texte non vide attendu');
    return v;
  }

  bool boolean(String key, {bool? def}) {
    final v = map[key];
    if (v == null && def != null) return def;
    if (v is! bool) _fail(key, 'booléen attendu');
    return v;
  }

  int integer(String key, {required int min, required int max, int? def}) {
    final v = map[key];
    if (v == null && def != null) return def;
    if (v is! int) _fail(key, 'entier attendu');
    if (v < min || v > max) {
      _fail(key, 'doit être entre $min et $max (reçu $v)');
    }
    return v;
  }

  Res res(String key) {
    final r = Res.tryParse(str(key));
    if (r == null) _fail(key, "ressource inconnue '${map[key]}'");
    return r;
  }

  _Obj obj(String key) {
    final v = map[key];
    if (v is! Map<String, dynamic>) _fail(key, 'objet attendu');
    return _Obj(file, '$path.$key', v);
  }

  _Obj? optObj(String key) {
    final v = map[key];
    if (v == null) return null;
    return obj(key);
  }

  List<_Obj> objList(String key) {
    final v = map[key];
    if (v is! List<dynamic>) _fail(key, 'liste attendue');
    final out = <_Obj>[];
    for (var i = 0; i < v.length; i++) {
      final e = v[i];
      if (e is! Map<String, dynamic>) {
        throw DataException(file, '$path.$key[$i]', 'objet attendu');
      }
      out.add(_Obj(file, '$path.$key[$i]', e));
    }
    return out;
  }

  List<int> intList(String key) {
    final v = map[key];
    if (v is! List<dynamic> || v.any((e) => e is! int)) {
      _fail(key, "liste d'entiers attendue");
    }
    return v.cast<int>();
  }

  List<String> strList(String key, {List<String>? def}) {
    final v = map[key];
    if (v == null && def != null) return def;
    if (v is! List<dynamic> || v.any((e) => e is! String)) {
      _fail(key, 'liste de textes attendue');
    }
    return v.cast<String>();
  }

  Stock cost(String key) {
    final o = obj(key);
    final s = Stock();
    for (final k in o.keys) {
      final r = Res.tryParse(k);
      if (r == null) {
        throw DataException(file, '${o.path}.$k', "ressource inconnue '$k'");
      }
      s[r] = o.integer(k, min: 0, max: 1000000);
    }
    return s;
  }
}
