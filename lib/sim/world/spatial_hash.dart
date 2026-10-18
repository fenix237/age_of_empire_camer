import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/world/entities.dart';

/// Grille de hachage spatiale d'unités (une cellule = une case).
/// Reconstruite à chaque tick par tri par comptage : aucune allocation par
/// entrée, ordre des identifiants conservé dans chaque cellule.
class SpatialHash {
  SpatialHash(this.width, this.height)
    : start = Int32List(width * height + 1),
      items = Int32List(0);

  final int width;
  final int height;

  /// `start[c]..start[c+1]` délimite les unités de la cellule `c` dans [items].
  final Int32List start;
  Int32List items;

  void rebuild(Iterable<Unit> units, int count) {
    start.fillRange(0, start.length, 0);
    if (items.length < count) items = Int32List(count + (count >> 1) + 16);
    for (final u in units) {
      start[_cell(u) + 1]++;
    }
    for (var i = 0; i < width * height; i++) {
      start[i + 1] += start[i];
    }
    final fill = Int32List.fromList(start);
    for (final u in units) {
      final c = _cell(u);
      items[fill[c]++] = u.id;
    }
  }

  int _cell(Unit u) {
    var tx = u.tileX;
    var ty = u.tileY;
    if (tx < 0) tx = 0;
    if (ty < 0) ty = 0;
    if (tx >= width) tx = width - 1;
    if (ty >= height) ty = height - 1;
    return ty * width + tx;
  }
}
