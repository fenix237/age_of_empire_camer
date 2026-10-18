import 'dart:ui';

import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';

/// Brouillard de guerre à 3 états : inconnu (noir) / exploré (assombri) /
/// visible (clair), dérivé de la vision de la simulation.
///
/// Dessiné par blocs de 16×16 mis en cache ; un bloc n'est reconstruit que si
/// la révision de vision a changé.
class FogRenderer {
  FogRenderer(this.map);

  static const int chunk = 16;

  final GameMap map;
  final Map<int, Picture> _cache = <int, Picture>{};
  final Map<int, int> _revision = <int, int>{};
  int rebuilds = 0;

  int get chunksX => (map.width + chunk - 1) ~/ chunk;

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
    _revision.clear();
  }

  /// État d'une case : 0 inconnu, 1 exploré, 2 visible.
  static int stateOf(Player p, int index) {
    if (p.visible[index] != 0) return 2;
    return p.explored[index] != 0 ? 1 : 0;
  }

  void paint(Canvas canvas, Rect visibleWorld, Player viewer, int revision) {
    final t = Iso.visibleTiles(visibleWorld, map.width, map.height, margin: 2);
    for (var cy = t.y0 ~/ chunk; cy <= t.y1 ~/ chunk; cy++) {
      for (var cx = t.x0 ~/ chunk; cx <= t.x1 ~/ chunk; cx++) {
        final key = cy * chunksX + cx;
        if (_revision[key] != revision) {
          _cache.remove(key)?.dispose();
          final pic = _build(cx, cy, viewer);
          if (pic != null) _cache[key] = pic;
          _revision[key] = revision;
        }
        final pic = _cache[key];
        if (pic != null) canvas.drawPicture(pic);
      }
    }
  }

  Picture? _build(int cx, int cy, Player viewer) {
    rebuilds++;
    final x0 = cx * chunk;
    final y0 = cy * chunk;
    final x1 = (x0 + chunk).clamp(0, map.width);
    final y1 = (y0 + chunk).clamp(0, map.height);
    final unknown = Paint()..color = const Color(0xFF000000);
    final explored = Paint()..color = const Color(0x88000000);
    final rec = PictureRecorder();
    final c = Canvas(rec);
    var any = false;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final s = stateOf(viewer, map.index(x, y));
        if (s == 2) continue;
        any = true;
        final d = Iso.diamond(x, y);
        // Légèrement agrandi pour éviter les coutures entre losanges.
        final cen = Iso.tileCenter(x, y);
        Offset grow(Offset p) => cen + (p - cen) * 1.04;
        final path = Path()
          ..moveTo(grow(d[0]).dx, grow(d[0]).dy)
          ..lineTo(grow(d[1]).dx, grow(d[1]).dy)
          ..lineTo(grow(d[2]).dx, grow(d[2]).dy)
          ..lineTo(grow(d[3]).dx, grow(d[3]).dy)
          ..close();
        c.drawPath(path, s == 0 ? unknown : explored);
      }
    }
    final pic = rec.endRecording();
    if (!any) {
      pic.dispose();
      return null;
    }
    return pic;
  }
}
