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

  static const double duration = 1.6;
}

/// Zone d'effet d'un pouvoir ou d'un sort : onde colorée qui s'éteint.
class ZoneFx {
  ZoneFx(this.center, this.radiusTiles, this.color, this.start);

  final Offset center;
  final double radiusTiles;
  final Color color;
  final double start;

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
    List<ZoneFx> zones = const <ZoneFx>[],
    PowerDef? targetPower,
    Offset? hoverScreen,
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
    _projectiles(canvas, alpha);

    if (fogEnabled) fog.paint(canvas, vis, viewer, world.visionRevision);

    _zones(canvas, zones, time);
    if (targetPower != null && hoverScreen != null) {
      _targetPreview(canvas, targetPower, cam.screenToTile(hoverScreen));
    }
    _markers(canvas, markers, time);
    canvas.restore();
  }

  // ── Projectiles ──

  int _projTick = -1;
  Map<int, Offset> _projPrev = <int, Offset>{};
  Map<int, Offset> _projCur = <int, Offset>{};
  final Map<int, Offset> _projOrigin = <int, Offset>{};

  /// Flèches en arc et boulets de catapulte, interpolés entre deux ticks.
  void _projectiles(Canvas c, double alpha) {
    if (world.tick != _projTick) {
      _projTick = world.tick;
      _projPrev = _projCur;
      _projCur = <int, Offset>{
        for (final p in world.projectiles.values) p.id: Iso.fromFixed(p.x, p.y),
      };
      _projOrigin.removeWhere((id, _) => !_projCur.containsKey(id));
      for (final e in _projCur.entries) {
        _projOrigin.putIfAbsent(e.key, () => _projPrev[e.key] ?? e.value);
      }
    }
    for (final p in world.projectiles.values) {
      final cur = _projCur[p.id];
      if (cur == null) continue;
      final pos = Offset.lerp(_projPrev[p.id] ?? cur, cur, alpha)!;
      final origin = _projOrigin[p.id] ?? pos;
      final target = Iso.fromFixed(p.tx, p.ty);
      final total = math.max<double>(1, (target - origin).distance);
      final f = (1 - (target - pos).distance / total).clamp(0.0, 1.0);
      final arc = math.min(total * 0.35, 46);
      Offset at(double t) => Offset.lerp(origin, target, t)!.translate(
        0,
        -(4 * arc * t * (1 - t) + 16),
      );
      final here = at(f);
      final ahead = at((f + 0.03).clamp(0.0, 1.0));
      var dir = ahead - here;
      if (dir.distance < 0.01) dir = target - pos;
      dir = dir / math.max(0.01, dir.distance);
      final siege =
          p.srcUnitDef >= 0 &&
          p.srcUnitDef < world.defs.units.length &&
          world.defs.units[p.srcUnitDef].classes.contains('siege');
      // Ombre au sol.
      c.drawOval(
        Rect.fromCenter(
          center: Offset.lerp(origin, target, f)!,
          width: siege ? 10 : 6,
          height: siege ? 5 : 3,
        ),
        Paint()..color = const Color(0x44000000),
      );
      if (siege) {
        c
          ..drawCircle(here, 5.5, Paint()..color = const Color(0xFF3F3F44))
          ..drawCircle(
            here.translate(-1.5, -1.5),
            2,
            Paint()..color = const Color(0x66FFFFFF),
          );
      } else {
        final tail = here - dir * 13;
        c
          ..drawLine(
            tail,
            here,
            Paint()
              ..color = const Color(0xFFE8D8B0)
              ..strokeWidth = 1.8
              ..strokeCap = StrokeCap.round,
          )
          ..drawLine(
            tail,
            tail + dir * 4,
            Paint()
              ..color = teamColor(p.owner)
              ..strokeWidth = 3,
          )
          ..drawCircle(here, 1.6, Paint()..color = const Color(0xFF9AA3AB));
      }
    }
  }

  // ── Zones d'effet ──

  static void _ellipse(Canvas c, Offset center, double radiusTiles, Paint p) {
    final k = math.sqrt2 * radiusTiles;
    c.drawOval(
      Rect.fromCenter(
        center: center,
        width: 2 * k * Iso.halfW,
        height: 2 * k * Iso.halfH,
      ),
      p,
    );
  }

  void _zones(Canvas c, List<ZoneFx> zones, double time) {
    for (final z in zones) {
      final age = (time - z.start) / ZoneFx.duration;
      if (age < 0 || age > 1) continue;
      final grow = 0.35 + 0.65 * (1 - (1 - age) * (1 - age));
      _ellipse(
        c,
        z.center,
        z.radiusTiles * grow,
        Paint()..color = z.color.withValues(alpha: 0.28 * (1 - age)),
      );
      _ellipse(
        c,
        z.center,
        z.radiusTiles * grow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = z.color.withValues(alpha: 0.9 * (1 - age)),
      );
    }
  }

  /// Zone d'un pouvoir en cours de ciblage, sous le curseur.
  void _targetPreview(Canvas c, PowerDef pd, ({int x, int y}) tile) {
    final at = Iso.tileCenter(
      tile.x.clamp(0, world.map.width - 1),
      tile.y.clamp(0, world.map.height - 1),
    );
    final r = math.max(0.5, pd.radius / 1000);
    final col = pd.affects == PowerAffects.allies
        ? const Color(0xFF3FD35A)
        : const Color(0xFFE04040);
    _ellipse(c, at, r, Paint()..color = col.withValues(alpha: 0.18));
    _ellipse(
      c,
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = col.withValues(alpha: 0.85),
    );
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

  /// Croix posée exactement sur la destination : elle reste visible puis
  /// s'efface (pas d'anneau ni de ligne).
  void _markers(Canvas c, List<OrderMarker> markers, double time) {
    for (final m in markers) {
      final age = (time - m.start) / OrderMarker.duration;
      if (age < 0 || age > 1) continue;
      final fade = age < 0.6 ? 1.0 : (1 - age) / 0.4;
      final pop = age < 0.12 ? 1.4 - 0.4 * (age / 0.12) : 1.0;
      final r = 11.0 * pop;
      final p = m.world;
      final a = Offset(r, r * 0.55);
      final b = Offset(r, -r * 0.55);
      for (final (width, color) in <(double, Color)>[
        (5.0, const Color(0xFF000000).withValues(alpha: 0.55 * fade)),
        (2.6, m.color.withValues(alpha: fade)),
      ]) {
        final paint = Paint()
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = color;
        c
          ..drawLine(p - a, p + a, paint)
          ..drawLine(p - b, p + b, paint);
      }
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
