import 'dart:ui';

import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';

/// Priorité d'affichage d'un terrain : le terrain le plus prioritaire « déborde »
/// sur ses voisins moins prioritaires (auto-tiling des transitions).
int terrainPriority(String id) => switch (id) {
  'deep' => 0,
  'shallow' => 1,
  'marsh' => 2,
  'sand' => 3,
  'dirt' => 4,
  'road' => 5,
  'savanna' => 6,
  'grass' => 7,
  'cliff' => 8,
  'mountain' => 9,
  _ => 5,
};

/// Bits de transition d'une case : quels voisins (N, E, S, W en coordonnées de
/// carte) sont plus prioritaires et doivent déborder sur elle.
///
/// 1 = voisin (x, y−1), 2 = (x+1, y), 4 = (x, y+1), 8 = (x−1, y).
int transitionMask(GameMap map, int x, int y) {
  final here = terrainPriority(map.terrainDef(map.index(x, y)).id);
  var mask = 0;
  const dirs = <List<int>>[
    [0, -1, 1],
    [1, 0, 2],
    [0, 1, 4],
    [-1, 0, 8],
  ];
  for (final d in dirs) {
    final nx = x + d[0];
    final ny = y + d[1];
    if (!map.inBounds(nx, ny)) continue;
    final other = terrainPriority(map.terrainDef(map.index(nx, ny)).id);
    if (other > here) mask |= d[2];
  }
  return mask;
}

/// Terrain rendu par blocs de 16×16 cases, mis en cache dans des `Picture`
/// et reconstruits seulement quand le terrain change.
class TerrainRenderer {
  TerrainRenderer(this.map, this.assets);

  static const int chunk = 16;

  final GameMap map;
  final AssetRegistry assets;
  final Map<int, Picture> _cache = <int, Picture>{};

  /// Nombre de reconstructions de blocs (statistiques et tests).
  int rebuilds = 0;

  int get cachedChunks => _cache.length;

  int get chunksX => (map.width + chunk - 1) ~/ chunk;
  int get chunksY => (map.height + chunk - 1) ~/ chunk;

  void invalidateAll() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }

  /// Invalide le bloc contenant la case (et ses voisins si en bord de bloc).
  void invalidateTile(int x, int y) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final cx = (x + dx) ~/ chunk;
        final cy = (y + dy) ~/ chunk;
        if (x + dx < 0 || y + dy < 0) continue;
        _cache.remove(cy * chunksX + cx)?.dispose();
      }
    }
  }

  void dispose() => invalidateAll();

  void paint(Canvas canvas, Rect visibleWorld) {
    final t = Iso.visibleTiles(visibleWorld, map.width, map.height, margin: 2);
    for (var cy = t.y0 ~/ chunk; cy <= t.y1 ~/ chunk; cy++) {
      for (var cx = t.x0 ~/ chunk; cx <= t.x1 ~/ chunk; cx++) {
        final key = cy * chunksX + cx;
        final pic = _cache[key] ??= _build(cx, cy);
        canvas.drawPicture(pic);
      }
    }
  }

  Picture _build(int cx, int cy) {
    rebuilds++;
    final rec = PictureRecorder();
    final c = Canvas(rec);
    final x0 = cx * chunk;
    final y0 = cy * chunk;
    final x1 = (x0 + chunk).clamp(0, map.width);
    final y1 = (y0 + chunk).clamp(0, map.height);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = map.index(x, y);
        final def = map.terrainDef(i);
        // Ancre : coin bas du losange de la case.
        final anchor = Iso.toWorld(x + 1.0, y + 1.0);
        assets.draw(
          'terrain/${def.id}',
          c,
          anchor,
          SpriteContext(seed: x * 73856093 ^ y * 19349663),
        );
        // Relief : teinte selon l'altitude.
        final e = map.elevation[i];
        if (e > 0) {
          c.drawPath(
            _diamondPath(x, y),
            Paint()..color = Color.fromARGB(24 * e, 255, 255, 255),
          );
        }
        final mask = transitionMask(map, x, y);
        if (mask != 0) _paintTransitions(c, x, y, mask);
      }
    }
    return rec.endRecording();
  }

  Path _diamondPath(int x, int y) {
    final d = Iso.diamond(x, y);
    return Path()
      ..moveTo(d[0].dx, d[0].dy)
      ..lineTo(d[1].dx, d[1].dy)
      ..lineTo(d[2].dx, d[2].dy)
      ..lineTo(d[3].dx, d[3].dy)
      ..close();
  }

  /// Dessine, le long de chaque arête voisine plus prioritaire, un dégradé de
  /// la couleur du voisin vers l'intérieur de la case.
  void _paintTransitions(Canvas c, int x, int y, int mask) {
    final d = Iso.diamond(x, y); // haut, droite, bas, gauche
    final center = Iso.tileCenter(x, y);
    // Arêtes : N (x, y−1) = haut→gauche ... en coordonnées carte :
    //   y−1 → arête entre sommets haut(0) et droite(1)
    //   x+1 → arête droite(1) → bas(2)
    //   y+1 → arête bas(2) → gauche(3)
    //   x−1 → arête gauche(3) → haut(0)
    const edges = <List<int>>[
      [1, 0, 1, 0, -1],
      [2, 1, 2, 1, 0],
      [4, 2, 3, 0, 1],
      [8, 3, 0, -1, 0],
    ];
    for (final e in edges) {
      if (mask & e[0] == 0) continue;
      final nx = x + e[3];
      final ny = y + e[4];
      final other = map.terrainDef(map.index(nx, ny)).id;
      final col = terrainColors[other] ?? const Color(0xFFFF00FF);
      final a = d[e[1]];
      final b = d[e[2]];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final inward = Offset.lerp(mid, center, 0.55)!;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(inward.dx, inward.dy)
        ..close();
      c.drawPath(
        path,
        Paint()
          ..shader = Gradient.linear(
            mid,
            inward,
            <Color>[col.withValues(alpha: 0.75), col.withValues(alpha: 0)],
          ),
      );
    }
  }
}
