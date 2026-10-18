import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/depth_sorter.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/player.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// Construit, trie et dessine ressources, bâtiments et unités.
class EntityRenderer {
  EntityRenderer(this.assets);

  final AssetRegistry assets;

  /// Nombre d'objets dessinés à la dernière image (statistiques / debug).
  int lastDrawn = 0;

  /// En dessous de ce zoom, les ressources sont dessinées en pastilles.
  static const double lodZoom = 0.38;

  static final List<Paint> _lodPaints = <Paint>[
    Paint()..color = const Color(0xFFD35D5D), // nourriture
    Paint()..color = const Color(0xFF2F6B35), // bois
    Paint()..color = const Color(0xFF9B9B9B), // pierre
    Paint()..color = const Color(0xFF6E8CA8), // fer
    Paint()..color = const Color(0xFFE6B422), // or
  ];

  /// Temps (µs) de construction, de tri et de dessin de la dernière image.
  int buildMicros = 0;
  int sortMicros = 0;
  int paintMicros = 0;

  /// Drawables visibles, triés en profondeur.
  List<Drawable> collect(
    World w,
    GameCamera cam,
    Player viewer,
    SelectionModel sel,
    double alpha,
    double time,
  ) {
    final clock = Stopwatch()..start();
    final lod = cam.zoom < lodZoom;
    final vis = cam.visibleWorld.inflate(80);
    final t = Iso.visibleTiles(vis, w.map.width, w.map.height, margin: 3);
    final out = <Drawable>[];
    final m = w.map;

    bool inView(int x, int y) =>
        x >= t.x0 && x <= t.x1 && y >= t.y0 && y <= t.y1;

    for (final n in w.nodes.values) {
      if (!inView(n.tx, n.ty)) continue;
      if (viewer.explored[m.index(n.tx, n.ty)] == 0) continue;
      final anchor = Iso.toWorld(
        n.tx + 1.0,
        n.ty + 1.0,
      ).translate(0, -Iso.halfH);
      final key = 'resource/${n.def.id}';
      // Très dézoomé : une simple pastille (1 commande) au lieu du sprite.
      final paint = lod ? _lodPaints[n.res.index] : null;
      out.add(
        Drawable(
          id: n.id,
          x0: n.tx.toDouble(),
          y0: n.ty.toDouble(),
          x1: n.tx + 1.0,
          y1: n.ty + 1.0,
          bounds: Rect.fromCenter(
            center: anchor.translate(0, -18),
            width: 56,
            height: 64,
          ),
          payload: (c) {
            if (paint != null) {
              c.drawRect(
                Rect.fromCenter(
                  center: anchor.translate(0, -14),
                  width: 22,
                  height: 28,
                ),
                paint,
              );
            } else {
              assets.draw(
                key,
                c,
                anchor,
                SpriteContext(seed: n.id * 40503),
              );
            }
          },
        ),
      );
    }

    for (final b in w.buildings.values) {
      if (b.tx > t.x1 ||
          b.ty > t.y1 ||
          b.tx + b.def.width < t.x0 ||
          b.ty + b.def.height < t.y0) {
        continue;
      }
      if (viewer.explored[m.index(b.tx, b.ty)] == 0) continue;
      final anchor = Iso.toWorld(
        (b.tx + b.def.width).toDouble(),
        (b.ty + b.def.height).toDouble(),
      );
      final progress = b.complete
          ? 1.0
          : (b.progressMilli / b.totalBuildMilli).clamp(0.0, 1.0);
      final h = 40.0 + (b.def.width + b.def.height) * 10;
      final bounds = Iso.worldBounds(
        b.tx,
        b.ty,
        b.tx + b.def.width,
        b.ty + b.def.height,
      ).inflate(6).translate(0, -h / 2).inflate(h / 2);
      final key = 'building/${b.def.id}';
      final selected = sel.contains(b.id);
      out.add(
        Drawable(
          id: b.id,
          x0: b.tx.toDouble(),
          y0: b.ty.toDouble(),
          x1: (b.tx + b.def.width).toDouble(),
          y1: (b.ty + b.def.height).toDouble(),
          bounds: bounds,
          payload: (c) {
            assets.draw(
              key,
              c,
              anchor,
              SpriteContext(
                team: b.owner,
                progress: progress,
                footprintW: b.def.width,
                footprintH: b.def.height,
              ),
            );
            if (selected) _selectionOutline(c, b);
            if (b.hp < b.maxHp || selected) {
              _hpBar(
                c,
                Iso.worldBounds(
                  b.tx,
                  b.ty,
                  b.tx + b.def.width,
                  b.ty + b.def.height,
                ).center.translate(0, -h - 6),
                b.hp / b.maxHp,
                width: 12.0 * b.def.width,
              );
            }
            if (!b.complete) {
              _progressBar(
                c,
                Iso.worldBounds(
                  b.tx,
                  b.ty,
                  b.tx + b.def.width,
                  b.ty + b.def.height,
                ).center.translate(0, -h - 14),
                progress,
              );
            }
          },
        ),
      );
    }

    for (final u in w.units.values) {
      if (!u.alive || u.state == UnitState.garrisoned) continue;
      final tx = u.tileX;
      final ty = u.tileY;
      if (!inView(tx, ty)) continue;
      final idx = m.index(tx.clamp(0, m.width - 1), ty.clamp(0, m.height - 1));
      if (u.owner != viewer.id && viewer.visible[idx] == 0) continue;
      // Interpolation entre le tick précédent et le courant.
      final fx = u.px + (u.x - u.px) * alpha;
      final fy = u.py + (u.y - u.py) * alpha;
      final tfx = fx / 256.0;
      final tfy = fy / 256.0;
      final anchor = Iso.toWorld(tfx, tfy);
      final moving = u.px != u.x || u.py != u.y;
      final selected = sel.contains(u.id);
      out.add(
        Drawable(
          id: u.id,
          x0: tfx - 0.2,
          y0: tfy - 0.2,
          x1: tfx + 0.2,
          y1: tfy + 0.2,
          bounds: Rect.fromCenter(
            center: anchor.translate(0, -18 * unitScale),
            width: 44 * unitScale,
            height: 56 * unitScale,
          ),
          payload: (c) {
            if (selected) _unitRing(c, anchor, teamColor(u.owner));
            assets.draw(
              'unit/${u.def.id}',
              c,
              anchor,
              SpriteContext(
                team: u.owner,
                time: time,
                moving: moving,
                seed: u.id,
                scale: unitScale,
              ),
            );
            if (u.hp < u.def.hp || selected) {
              _hpBar(c, anchor.translate(0, -36 * unitScale), u.hp / u.def.hp);
            }
            if (u.carryAmt > 0 && selected) {
              _carryDot(
                c,
                anchor.translate(14, -34 * unitScale + 6),
                u.carryType!.index,
              );
            }
          },
        ),
      );
    }
    buildMicros = clock.elapsedMicroseconds;
    clock.reset();
    final sorted = DepthSorter.sort(out);
    sortMicros = clock.elapsedMicroseconds;
    return sorted;
  }

  void paint(Canvas canvas, List<Drawable> sorted) {
    final clock = Stopwatch()..start();
    for (final d in sorted) {
      d.payload!(canvas);
    }
    lastDrawn = sorted.length;
    paintMicros = clock.elapsedMicroseconds;
  }

  // ── Surcouches d'entités ──

  static void _unitRing(Canvas c, Offset a, Color team) {
    c
      ..drawOval(
        Rect.fromCenter(
          center: a,
          width: 34 * unitScale,
          height: 17 * unitScale,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFFFFFFFF),
      )
      ..drawOval(
        Rect.fromCenter(
          center: a,
          width: 38 * unitScale,
          height: 19 * unitScale,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = team,
      );
  }

  static void _selectionOutline(Canvas c, Building b) {
    c.drawPath(
      Iso.footprint(b.tx, b.ty, b.def.width, b.def.height),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFFFFF),
    );
  }

  static void _hpBar(
    Canvas c,
    Offset center,
    double frac, {
    double width = 28,
  }) {
    final f = frac.clamp(0.0, 1.0);
    final r = Rect.fromCenter(center: center, width: width, height: 5);
    c
      ..drawRect(r.inflate(1), Paint()..color = const Color(0xCC000000))
      ..drawRect(
        Rect.fromLTWH(r.left, r.top, r.width * f, r.height),
        Paint()
          ..color = f > 0.5
              ? const Color(0xFF4CAF50)
              : (f > 0.25 ? const Color(0xFFE0B72B) : const Color(0xFFD64545)),
      );
  }

  static void _progressBar(Canvas c, Offset center, double frac) {
    final r = Rect.fromCenter(center: center, width: 40, height: 4);
    c
      ..drawRect(r.inflate(1), Paint()..color = const Color(0xCC000000))
      ..drawRect(
        Rect.fromLTWH(r.left, r.top, r.width * frac, r.height),
        Paint()..color = const Color(0xFF4FA3C7),
      );
  }

  static void _carryDot(Canvas c, Offset at, int resIndex) {
    c.drawCircle(
      at,
      4,
      Paint()..color = resourceColorByIndex(resIndex),
    );
  }

  /// Distance de fondu des unités en bord de vue (utilitaire de test).
  static double edgeFade(double d) => math.max(0, 1 - d / 100);
}

Color resourceColorByIndex(int i) => const <Color>[
  Color(0xFFD35D5D),
  Color(0xFF8B5A2B),
  Color(0xFF9B9B9B),
  Color(0xFF6E8CA8),
  Color(0xFFE6B422),
][i.clamp(0, 4)];
