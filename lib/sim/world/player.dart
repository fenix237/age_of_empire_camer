import 'dart:convert';
import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';

/// État d'un joueur : ressources, âge, recherches, brouillard.
class Player {
  Player(this.id, int mapSize)
    : stock = Stock(),
      explored = Uint8List(mapSize),
      visible = Uint8List(mapSize);

  final int id;
  Stock stock;
  int age = 0;

  /// Indices (triés) des recherches terminées.
  final List<int> techs = <int>[];

  /// Case de départ (centre-ville initial).
  int startX = 0;
  int startY = 0;

  /// Bonus de portage cumulé (recherches).
  int carryBonus = 0;

  /// Bonus de récolte en % par ressource (recherches).
  final List<int> gatherPercent = List<int>.filled(Res.values.length, 0);

  /// Population courante et plafond (recalculés à chaque tick).
  int popUsed = 0;
  int popCap = 0;

  /// 0 = inconnu / 1 = exploré. Persistant.
  final Uint8List explored;

  /// 1 = visible ce tick. Dérivé de la position des entités.
  final Uint8List visible;

  bool hasTech(int index) => techs.contains(index);

  void addTech(TechDef tech) {
    if (techs.contains(tech.index)) return;
    techs
      ..add(tech.index)
      ..sort();
    for (final e in tech.effects) {
      if (e.stat == 'carry') carryBonus += e.add;
      if (e.stat == 'gather') gatherPercent[e.res!.index] += e.percent;
    }
  }

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
  };

  static Player fromJson(
    Map<String, dynamic> j,
    int mapSize,
    List<TechDef> techDefs,
  ) {
    final p = Player(j['id'] as int, mapSize)
      ..stock = Stock.fromJson(j['stock'])
      ..age = j['age'] as int
      ..startX = j['sx'] as int
      ..startY = j['sy'] as int;
    p.explored.setAll(0, base64Decode(j['explored'] as String));
    for (final t in List<int>.from(j['techs'] as List<dynamic>)) {
      p.addTech(techDefs[t]);
    }
    return p;
  }
}
