import 'dart:math' as math;
import 'dart:ui';

/// Projection isométrique 2:1 : losange de 128×64 px par case.
///
/// `wx = (x − y)·64`, `wy = (x + y)·32` pour des coordonnées de case
/// fractionnaires `(x, y)`. L'unité de rendu « monde » est le pixel à zoom 1.
/// (La simulation n'utilise jamais ce code : seul le rendu a le droit
/// d'employer des `double`.)
abstract final class Iso {
  static const double tileW = 128;
  static const double tileH = 64;
  static const double halfW = tileW / 2;
  static const double halfH = tileH / 2;

  /// Coordonnées de case fractionnaires → point « monde ».
  static Offset toWorld(double x, double y) =>
      Offset((x - y) * halfW, (x + y) * halfH);

  /// Centre du losange d'une case entière.
  static Offset tileCenter(int x, int y) => toWorld(x + 0.5, y + 0.5);

  /// Point « monde » → coordonnées de case fractionnaires.
  static Offset toTileFraction(Offset world) => Offset(
    world.dx / tileW + world.dy / tileH,
    world.dy / tileH - world.dx / tileW,
  );

  /// Case entière contenant le point « monde » (picking).
  static ({int x, int y}) pick(Offset world) {
    final f = toTileFraction(world);
    return (x: f.dx.floor(), y: f.dy.floor());
  }

  /// Position en virgule fixe de la simulation (1 case = 256) → monde.
  static Offset fromFixed(int fx, int fy) => toWorld(fx / 256.0, fy / 256.0);

  /// Les quatre sommets du losange de la case (haut, droite, bas, gauche).
  static List<Offset> diamond(int x, int y) => <Offset>[
    toWorld(x.toDouble(), y.toDouble()),
    toWorld(x + 1.0, y.toDouble()),
    toWorld(x + 1.0, y + 1.0),
    toWorld(x.toDouble(), y + 1.0),
  ];

  /// Contour (losange) de l'emprise d'un rectangle de cases.
  static Path footprint(int x, int y, int w, int h) {
    final top = toWorld(x.toDouble(), y.toDouble());
    final right = toWorld((x + w).toDouble(), y.toDouble());
    final bottom = toWorld((x + w).toDouble(), (y + h).toDouble());
    final left = toWorld(x.toDouble(), (y + h).toDouble());
    return Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
  }

  /// Rectangle englobant (monde) d'une zone de cases `[x0,x1) × [y0,y1)`.
  static Rect worldBounds(int x0, int y0, int x1, int y1) {
    final c = <Offset>[
      toWorld(x0.toDouble(), y0.toDouble()),
      toWorld(x1.toDouble(), y0.toDouble()),
      toWorld(x1.toDouble(), y1.toDouble()),
      toWorld(x0.toDouble(), y1.toDouble()),
    ];
    var l = c.first.dx;
    var r = l;
    var t = c.first.dy;
    var b = t;
    for (final p in c) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Zone de cases `[x0,x1] × [y0,y1]` (incluses, bornée à la carte) visible
  /// dans le rectangle « monde » donné.
  static ({int x0, int y0, int x1, int y1}) visibleTiles(
    Rect world,
    int mapW,
    int mapH, {
    int margin = 1,
  }) {
    final corners = <Offset>[
      toTileFraction(world.topLeft),
      toTileFraction(world.topRight),
      toTileFraction(world.bottomLeft),
      toTileFraction(world.bottomRight),
    ];
    var minX = corners.first.dx;
    var maxX = minX;
    var minY = corners.first.dy;
    var maxY = minY;
    for (final c in corners) {
      minX = math.min(minX, c.dx);
      maxX = math.max(maxX, c.dx);
      minY = math.min(minY, c.dy);
      maxY = math.max(maxY, c.dy);
    }
    return (
      x0: math.max(0, minX.floor() - margin),
      y0: math.max(0, minY.floor() - margin),
      x1: math.min(mapW - 1, maxX.floor() + margin),
      y1: math.min(mapH - 1, maxY.floor() + margin),
    );
  }

  /// Clé de profondeur d'un objet : plus elle est grande, plus l'objet est
  /// « devant ». Pour un bâtiment, on utilise sa case la plus avancée.
  static double depthOfPoint(double x, double y) => x + y;

  static double depthOfFootprint(int tx, int ty, int w, int h) =>
      (tx + w) + (ty + h) - 1.0;
}
