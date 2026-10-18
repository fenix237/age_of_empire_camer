import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/iso.dart';

/// Caméra du jeu : centre (monde), zoom, bornes de carte, inertie.
///
/// Le monde de jeu est indépendant de la taille de l'écran : seuls le
/// viewport et le zoom par défaut s'adaptent (Analyse §15.1).
class GameCamera {
  GameCamera({
    required this.mapWidth,
    required this.mapHeight,
    Size viewport = const Size(1280, 720),
  }) : _viewport = viewport {
    zoom = defaultZoomFor(viewport.height);
    center = Iso.toWorld(mapWidth / 2, mapHeight / 2);
    _clamp();
  }

  final int mapWidth;
  final int mapHeight;

  static const double minZoom = 0.25;
  static const double maxZoom = 1.8;

  /// Hauteur de référence : à 720 px de haut on voit environ 20 cases de large.
  static const double referenceHeight = 720;
  static const double referenceZoom = 0.55;

  Size _viewport;
  Offset center = Offset.zero;
  double zoom = 1;

  /// Vitesse résiduelle (pixels monde / seconde) pour l'inertie optionnelle.
  Offset velocity = Offset.zero;
  bool inertia = true;

  Size get viewport => _viewport;

  /// Zoom par défaut selon la hauteur : un nombre de cases visible constant.
  static double defaultZoomFor(double height) =>
      (referenceZoom * height / referenceHeight).clamp(minZoom, maxZoom);

  /// Redimensionnement en direct : le point central est conservé.
  void resize(Size size) {
    if (size == _viewport || size.isEmpty) return;
    _viewport = size;
    _clamp();
  }

  /// Rectangle du monde visible à l'écran.
  Rect get visibleWorld => Rect.fromCenter(
    center: center,
    width: _viewport.width / zoom,
    height: _viewport.height / zoom,
  );

  Offset worldToScreen(Offset w) => Offset(
    (w.dx - center.dx) * zoom + _viewport.width / 2,
    (w.dy - center.dy) * zoom + _viewport.height / 2,
  );

  Offset screenToWorld(Offset s) => Offset(
    (s.dx - _viewport.width / 2) / zoom + center.dx,
    (s.dy - _viewport.height / 2) / zoom + center.dy,
  );

  /// Case sous un point d'écran.
  ({int x, int y}) screenToTile(Offset s) => Iso.pick(screenToWorld(s));

  void panByScreen(Offset deltaPx) {
    center -= deltaPx / zoom;
    _clamp();
  }

  void centerOn(Offset world) {
    center = world;
    velocity = Offset.zero;
    _clamp();
  }

  void centerOnTile(double tx, double ty) => centerOn(Iso.toWorld(tx, ty));

  /// Zoom (molette / pincement) en gardant fixe le point d'écran [anchor].
  void zoomAt(double factor, Offset anchor) {
    final before = screenToWorld(anchor);
    zoom = (zoom * factor).clamp(minZoom, maxZoom);
    final after = screenToWorld(anchor);
    center += before - after;
    _clamp();
  }

  /// Défilement aux bords de l'écran (souris) : renvoie le déplacement en
  /// pixels écran par seconde à appliquer.
  Offset edgeScrollVelocity(
    Offset mouse, {
    double band = 18,
    double speed = 900,
  }) {
    var vx = 0.0;
    var vy = 0.0;
    if (mouse.dx <= band) vx = -1;
    if (mouse.dx >= _viewport.width - band) vx = 1;
    if (mouse.dy <= band) vy = -1;
    if (mouse.dy >= _viewport.height - band) vy = 1;
    return Offset(vx, vy) * speed;
  }

  /// Avance d'un pas de temps : déplacement clavier / bords + inertie.
  void update(double dt, {Offset keyboard = Offset.zero}) {
    if (keyboard != Offset.zero) {
      // Vitesse en pixels écran/s, indépendante du zoom.
      center += keyboard * dt / zoom;
      velocity = Offset.zero;
    } else if (inertia && velocity.distanceSquared > 1) {
      center += velocity * dt;
      velocity *= math.pow(0.0025, dt).toDouble(); // amortissement
      if (velocity.distanceSquared < 1) velocity = Offset.zero;
    }
    _clamp();
  }

  /// Fin d'un glisser : mémorise la vitesse pour l'inertie.
  void fling(Offset screenVelocity) {
    if (!inertia) return;
    velocity = -screenVelocity / zoom;
  }

  /// Bornes : le centre reste dans le losange de la carte (+ petite marge).
  void _clamp() {
    final b = Iso.worldBounds(0, 0, mapWidth, mapHeight);
    const marginX = Iso.tileW * 2;
    const marginY = Iso.tileH * 2;
    final minX = b.left - marginX;
    final maxX = b.right + marginX;
    final minY = b.top - marginY;
    final maxY = b.bottom + marginY;
    center = Offset(
      center.dx.clamp(minX, maxX),
      center.dy.clamp(minY, maxY),
    );
    // Reste dans le losange (norme L1 en coordonnées de case).
    final f = Iso.toTileFraction(center);
    final cx = f.dx.clamp(-2.0, mapWidth + 2.0);
    final cy = f.dy.clamp(-2.0, mapHeight + 2.0);
    if (cx != f.dx || cy != f.dy) center = Iso.toWorld(cx, cy);
  }
}
