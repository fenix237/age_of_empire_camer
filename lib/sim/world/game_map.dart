import 'dart:convert';
import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/data/defs.dart';

/// Carte logique : terrain, hauteurs et grille d'occupation.
class GameMap {
  GameMap(this.width, this.height, this._terrainDefs)
    : terrain = Uint8List(width * height),
      elevation = Uint8List(width * height),
      occupant = Int32List(width * height) {
    _walkableTerrain = <bool>[for (final t in _terrainDefs) t.walkable];
  }

  GameMap.fromJson(Map<String, dynamic> json, this._terrainDefs)
    : width = json['w'] as int,
      height = json['h'] as int,
      terrain = base64Decode(json['terrain'] as String),
      elevation = base64Decode(json['elevation'] as String),
      occupant = Int32List(0) {
    // `occupant` est recalculé par le monde (bâtiments et ressources).
    occupant = Int32List(width * height);
    version = json['version'] as int;
    _walkableTerrain = <bool>[for (final t in _terrainDefs) t.walkable];
  }

  final int width;
  final int height;
  final List<TerrainDef> _terrainDefs;
  late final List<bool> _walkableTerrain;

  /// Index de terrain (voir `terrain.json`) par case.
  final Uint8List terrain;

  /// Niveau d'altitude 0..2 par case.
  final Uint8List elevation;

  /// Identifiant du bâtiment/ressource qui occupe la case (0 = libre).
  Int32List occupant;

  /// Incrémenté à chaque changement d'obstacles (invalide chemins/flow fields).
  int version = 0;

  int get size => width * height;

  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  int index(int x, int y) => y * width + x;

  int xOf(int i) => i % width;
  int yOf(int i) => i ~/ width;

  bool terrainWalkable(int i) => _walkableTerrain[terrain[i]];

  /// Une case est bloquée pour le mouvement terrestre.
  bool blocked(int i) => occupant[i] != 0 || !_walkableTerrain[terrain[i]];

  bool blockedXY(int x, int y) => !inBounds(x, y) || blocked(index(x, y));

  TerrainDef terrainDef(int i) => _terrainDefs[terrain[i]];

  int moveCost(int i) => _terrainDefs[terrain[i]].moveCost;

  int speedPercent(int i) => _terrainDefs[terrain[i]].speedPercent;

  /// Pose ([id] != 0) ou retire (id == 0) l'occupation d'un rectangle.
  void setOccupant(int x0, int y0, int w, int h, int id) {
    for (var y = y0; y < y0 + h; y++) {
      for (var x = x0; x < x0 + w; x++) {
        if (inBounds(x, y)) occupant[index(x, y)] = id;
      }
    }
    version++;
  }

  GameMap copyTerrain() {
    final m = GameMap(width, height, _terrainDefs);
    m.terrain.setAll(0, terrain);
    m.elevation.setAll(0, elevation);
    return m;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'w': width,
    'h': height,
    'terrain': base64Encode(terrain),
    'elevation': base64Encode(elevation),
    'version': version,
  };
}
