import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Image RGBA de la mini-carte (terrain + ressources + bâtiments + brouillard),
/// régénérée à chaque recalcul de vision (pas à chaque frame).
class MiniMapImage {
  ui.Image? image;
  int _builtRevision = -1;
  bool _building = false;

  void ensure(World w, int viewerId) {
    if (_building || _builtRevision == w.visionRevision) return;
    _building = true;
    final revision = w.visionRevision;
    final px = buildPixels(w, viewerId);
    ui.decodeImageFromPixels(
      px,
      w.map.width,
      w.map.height,
      ui.PixelFormat.rgba8888,
      (img) {
        image?.dispose();
        image = img;
        _builtRevision = revision;
        _building = false;
      },
    );
  }

  void dispose() {
    image?.dispose();
    image = null;
  }

  /// Pixels RGBA (une case = un pixel). Séparé pour pouvoir être testé.
  static Uint8List buildPixels(World w, int viewerId) {
    final m = w.map;
    final p = w.players[viewerId];
    final out = Uint8List(m.size * 4);
    void put(int i, Color c, [double dim = 1]) {
      out[i * 4] = (c.r * 255 * dim).round();
      out[i * 4 + 1] = (c.g * 255 * dim).round();
      out[i * 4 + 2] = (c.b * 255 * dim).round();
      out[i * 4 + 3] = 255;
    }

    for (var i = 0; i < m.size; i++) {
      if (p.explored[i] == 0) {
        put(i, const Color(0xFF000000));
        continue;
      }
      final base = terrainColors[m.terrainDef(i).id] ?? const Color(0xFFFF00FF);
      put(i, base, p.visible[i] != 0 ? 1 : 0.55);
    }
    for (final n in w.nodes.values) {
      final i = m.index(n.tx, n.ty);
      if (p.explored[i] == 0) continue;
      put(i, resourceColor(n.res), p.visible[i] != 0 ? 0.9 : 0.5);
    }
    for (final b in w.buildings.values) {
      if (p.explored[m.index(b.tx, b.ty)] == 0) continue;
      for (var y = b.ty; y < b.ty + b.def.height; y++) {
        for (var x = b.tx; x < b.tx + b.def.width; x++) {
          put(m.index(x, y), teamColor(b.owner));
        }
      }
    }
    return out;
  }
}

/// Géométrie de la mini-carte en losange, pour le dessin et le picking.
class MiniMapGeometry {
  MiniMapGeometry(this.size, this.mapW, this.mapH) {
    final side = math.min(size.width, size.height * 2);
    width = side;
    height = side / 2;
    left = (size.width - width) / 2;
    top = (size.height - height) / 2;
  }

  final Size size;
  final int mapW;
  final int mapH;
  late final double width;
  late final double height;
  late final double left;
  late final double top;

  double get _n => (mapW + mapH) / 2;

  /// Coordonnées de case fractionnaires → point de la mini-carte.
  Offset fromTile(double x, double y) => Offset(
    left + width / 2 + (x - y) * width / (2 * _n),
    top + (x + y) * height / (2 * _n),
  );

  /// Point local → coordonnées de case fractionnaires.
  Offset toTile(Offset p) {
    final u = (p.dx - (left + width / 2)) / (width / 2);
    final v = (p.dy - top) / height;
    final sum = 2 * v * _n;
    final diff = u * _n;
    return Offset((sum + diff) / 2, (sum - diff) / 2);
  }
}

class MiniMap extends StatefulWidget {
  const MiniMap({required this.controller, this.size = 180, super.key});

  final GameController controller;
  final double size;

  @override
  State<MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<MiniMap> {
  final MiniMapImage _img = MiniMapImage();

  @override
  void dispose() {
    _img.dispose();
    super.dispose();
  }

  void _move(Offset local, Size box) {
    final c = widget.controller;
    final g = MiniMapGeometry(box, c.world.map.width, c.world.map.height);
    final t = g.toTile(local);
    c.camera.centerOnTile(
      t.dx.clamp(0.0, c.world.map.width.toDouble()),
      t.dy.clamp(0.0, c.world.map.height.toDouble()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final box = Size(widget.size, widget.size / 2 + 8);
    return SizedBox(
      width: box.width,
      height: box.height,
      child: Listener(
        // Clic gauche / appui : déplace la vue ; clic droit : ordre sur place.
        onPointerDown: (e) {
          if (e.buttons & kSecondaryMouseButton != 0) {
            final g = MiniMapGeometry(
              box,
              c.world.map.width,
              c.world.map.height,
            );
            final t = g.toTile(e.localPosition);
            final x = t.dx.floor().clamp(0, c.world.map.width - 1);
            final y = t.dy.floor().clamp(0, c.world.map.height - 1);
            c.orderAtTile(x, y);
          } else {
            _move(e.localPosition, box);
          }
        },
        onPointerMove: (e) {
          if (e.buttons & kPrimaryMouseButton != 0 ||
              e.kind == PointerDeviceKind.touch) {
            _move(e.localPosition, box);
          }
        },
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[c, c.frameClock]),
          builder: (context, _) {
            _img.ensure(c.world, c.localPlayer);
            return CustomPaint(
              painter: _MiniMapPainter(c, _img),
              size: box,
            );
          },
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter(this.c, this.img);

  final GameController c;
  final MiniMapImage img;

  @override
  void paint(Canvas canvas, Size size) {
    final w = c.world;
    final g = MiniMapGeometry(size, w.map.width, w.map.height);
    final frame = Path()
      ..moveTo(g.fromTile(0, 0).dx, g.fromTile(0, 0).dy)
      ..lineTo(
        g.fromTile(w.map.width.toDouble(), 0).dx,
        g.fromTile(w.map.width.toDouble(), 0).dy,
      )
      ..lineTo(
        g.fromTile(w.map.width.toDouble(), w.map.height.toDouble()).dx,
        g.fromTile(w.map.width.toDouble(), w.map.height.toDouble()).dy,
      )
      ..lineTo(
        g.fromTile(0, w.map.height.toDouble()).dx,
        g.fromTile(0, w.map.height.toDouble()).dy,
      )
      ..close();
    canvas
      ..drawPath(frame, Paint()..color = const Color(0xFF000000))
      ..save()
      ..clipPath(frame);
    final image = img.image;
    if (image != null) {
      final n = (w.map.width + w.map.height) / 2;
      final s = g.width / (2 * n);
      // Matrice iso : x' = ox + (x−y)·s ; y' = oy + (x+y)·s/2
      final m = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(0, 1, -s)
        ..setEntry(0, 3, g.left + g.width / 2)
        ..setEntry(1, 0, s / 2)
        ..setEntry(1, 1, s / 2)
        ..setEntry(1, 3, g.top);
      canvas
        ..save()
        ..transform(m.storage)
        ..drawImage(
          image,
          Offset.zero,
          Paint()..filterQuality = FilterQuality.none,
        )
        ..restore();
    }
    // Unités visibles (points).
    final viewer = w.players[c.localPlayer];
    for (final u in w.units.values) {
      if (!u.alive || u.state == UnitState.garrisoned) continue;
      final idx = w.map.index(
        u.tileX.clamp(0, w.map.width - 1),
        u.tileY.clamp(0, w.map.height - 1),
      );
      if (u.owner != c.localPlayer && viewer.visible[idx] == 0) continue;
      final p = g.fromTile(u.x / 256, u.y / 256);
      canvas.drawCircle(p, 1.6, Paint()..color = teamColor(u.owner));
    }
    canvas.restore();

    // Zone vue par la caméra.
    final vis = c.camera.visibleWorld;
    final corners = <Offset>[
      Iso.toTileFraction(vis.topLeft),
      Iso.toTileFraction(vis.topRight),
      Iso.toTileFraction(vis.bottomRight),
      Iso.toTileFraction(vis.bottomLeft),
    ];
    final view = Path();
    for (var i = 0; i < corners.length; i++) {
      final p = g.fromTile(corners[i].dx, corners[i].dy);
      if (i == 0) {
        view.moveTo(p.dx, p.dy);
      } else {
        view.lineTo(p.dx, p.dy);
      }
    }
    view.close();
    canvas
      ..drawPath(
        view,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFFFFFFFF),
      )
      ..drawPath(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF8B5A2B),
      );
    // Alertes d'attaque : points rouges clignotants.
    for (final a in c.alerts) {
      if (a.kind.name != 'underAttack') continue;
      final p = g.fromTile(a.tileX + 0.5, a.tileY + 0.5);
      final blink = ((c.time * 4).floor() % 2) == 0;
      if (blink) {
        canvas.drawCircle(p, 4, Paint()..color = const Color(0xFFFF3030));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) => true;
}
