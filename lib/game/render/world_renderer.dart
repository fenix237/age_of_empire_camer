import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/game/render/entity_renderer.dart';
import 'package:age_of_empire_camer/game/render/fog_renderer.dart';
import 'package:age_of_empire_camer/game/render/terrain_renderer.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:age_of_empire_camer/sim/data/defs.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Marqueur visuel d'un ordre (destination, cible).
class OrderMarker {
  OrderMarker(this.world, this.start, this.color);

  final Offset world;
  final double start;
  final Color color;

  static const double duration = 0.9;
}

/// Aperçu fantôme d'un bâtiment en cours de placement.
class PlacementGhost {
  const PlacementGhost(this.def, this.tx, this.ty, {required this.valid});

  final BuildingDef def;
  final int tx;
  final int ty;
  final bool valid;
}

/// Options de débogage (menu caché).
class DebugOptions {
  bool grid = false;
  bool occupancy = false;
  bool paths = false;
  bool stats = false;

  bool get any => grid || occupancy || paths || stats;
}

/// Compose le rendu complet d'une image : terrain, entités, brouillard,
/// surcouches. Lecture seule sur la simulation.
class WorldRenderer {
  WorldRenderer({required this.world, required this.assets})
    : terrain = TerrainRenderer(world.map, assets),
      fog = FogRenderer(world.map),
      entities = EntityRenderer(assets);

  final World world;
  final AssetRegistry assets;
  final TerrainRenderer terrain;
  final FogRenderer fog;
  final EntityRenderer entities;

  void dispose() {
    terrain.dispose();
    fog.dispose();
    assets.dispose();
  }

  /// Dessine l'image. [viewerId] : joueur local (brouillard, visibilité).
  void paint(
    Canvas canvas,
    Size size,
    GameCamera cam, {
    required int viewerId,
    required SelectionModel selection,
    required double alpha,
    required double time,
    List<OrderMarker> markers = const <OrderMarker>[],
    PlacementGhost? ghost,
    DebugOptions? debug,
    bool fogEnabled = true,
  }) {
    cam.resize(size);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(cam.zoom)
      ..translate(-cam.center.dx, -cam.center.dy);

    final vis = cam.visibleWorld;
    terrain.paint(canvas, vis);
    if (debug != null && debug.grid) _grid(canvas, vis);
    if (debug != null && debug.occupancy) _occupancy(canvas, vis);

    final viewer = world.players[viewerId];
    _buildingGhostUnder(canvas, ghost);
    final sorted = entities.collect(world, cam, viewer, selection, alpha, time);
    if (debug != null && debug.paths) _paths(canvas);
    entities.paint(canvas, sorted);
    _orderPaths(canvas, selection);

    if (fogEnabled) fog.paint(canvas, vis, viewer, world.visionRevision);

    _markers(canvas, markers, time);
    canvas.restore();
  }

  void _grid(Canvas c, Rect vis) {
    final t = Iso.visibleTiles(
      vis,
      world.map.width,
      world.map.height,
      margin: 0,
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x44FFFFFF);
    for (var y = t.y0; y <= t.y1; y++) {
      for (var x = t.x0; x <= t.x1; x++) {
        final d = Iso.diamond(x, y);
        c.drawPath(
          Path()
            ..moveTo(d[0].dx, d[0].dy)
            ..lineTo(d[1].dx, d[1].dy)
            ..lineTo(d[2].dx, d[2].dy)
            ..lineTo(d[3].dx, d[3].dy)
            ..close(),
          p,
        );
      }
    }
  }

  void _occupancy(Canvas c, Rect vis) {
    final m = world.map;
    final t = Iso.visibleTiles(vis, m.width, m.height, margin: 0);
    final p = Paint()..color = const Color(0x55FF2020);
    for (var y = t.y0; y <= t.y1; y++) {
      for (var x = t.x0; x <= t.x1; x++) {
        if (m.blocked(m.index(x, y))) c.drawPath(Iso.footprint(x, y, 1, 1), p);
      }
    }
  }

  void _paths(Canvas c) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xAAFFE066);
    for (final u in world.units.values) {
      _drawPath(c, u, p);
    }
  }

  void _orderPaths(Canvas c, SelectionModel sel) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0x99FFFFFF);
    for (final id in sel.units) {
      final u = world.units[id];
      if (u != null) _drawPath(c, u, p);
    }
  }

  void _drawPath(Canvas c, Unit u, Paint paint) {
    if (u.pathIdx >= u.path.length) return;
    final m = world.map;
    final path = Path();
    final start = Iso.fromFixed(u.x, u.y);
    path.moveTo(start.dx, start.dy);
    final n = math.min(u.path.length, u.pathIdx + 40);
    for (var i = u.pathIdx; i < n; i++) {
      final t = u.path[i];
      final o = Iso.tileCenter(t % m.width, t ~/ m.width);
      path.lineTo(o.dx, o.dy);
    }
    c.drawPath(path, paint);
  }

  void _buildingGhostUnder(Canvas c, PlacementGhost? g) {
    if (g == null) return;
    final col = g.valid ? const Color(0xFF3FD35A) : const Color(0xFFE04040);
    // Silhouette semi-transparente du bâtiment.
    c.saveLayer(null, Paint()..color = const Color(0xB3FFFFFF));
    assets.draw(
      'building/${g.def.id}',
      c,
      Iso.toWorld(
        (g.tx + g.def.width).toDouble(),
        (g.ty + g.def.height).toDouble(),
      ),
      SpriteContext(
        footprintW: g.def.width,
        footprintH: g.def.height,
        progress: 0.6,
      ),
    );
    c.restore();
    // Emprise teintée : vert = valide, rouge = impossible.
    final fill = Paint()..color = col.withValues(alpha: 0.4);
    for (var y = g.ty; y < g.ty + g.def.height; y++) {
      for (var x = g.tx; x < g.tx + g.def.width; x++) {
        if (world.map.inBounds(x, y)) {
          final blocked = world.map.blocked(world.map.index(x, y));
          c.drawPath(
            Iso.footprint(x, y, 1, 1),
            blocked ? (Paint()..color = const Color(0x66E04040)) : fill,
          );
        }
      }
    }
    c.drawPath(
      Iso.footprint(g.tx, g.ty, g.def.width, g.def.height),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = col,
    );
  }

  void _markers(Canvas c, List<OrderMarker> markers, double time) {
    for (final m in markers) {
      final age = (time - m.start) / OrderMarker.duration;
      if (age < 0 || age > 1) continue;
      final r = 10 + 22 * age;
      c.drawOval(
        Rect.fromCenter(center: m.world, width: r * 2, height: r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = m.color.withValues(alpha: 1 - age),
      );
    }
  }
}

/// Rectangle de sélection (espace écran) : bord blanc + remplissage léger.
void paintSelectionRect(Canvas canvas, Rect r) {
  canvas
    ..drawRect(r, Paint()..color = const Color(0x2230D060))
    ..drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF9BE8A8),
    );
}
