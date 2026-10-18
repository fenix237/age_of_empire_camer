import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('projection isométrique', () {
    test('screenToTile(tileToScreen(p)) == p pour toutes les cases', () {
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final c = Iso.tileCenter(x, y);
          expect(Iso.pick(c), (x: x, y: y));
        }
      }
    });

    test('tout point intérieur d’une case retombe sur cette case', () {
      final r = math.Random(4);
      for (var i = 0; i < 5000; i++) {
        final x = r.nextInt(100);
        final y = r.nextInt(100);
        final fx = 0.02 + r.nextDouble() * 0.96;
        final fy = 0.02 + r.nextDouble() * 0.96;
        expect(Iso.pick(Iso.toWorld(x + fx, y + fy)), (x: x, y: y));
      }
    });

    test('aller-retour fractionnaire', () {
      final r = math.Random(5);
      for (var i = 0; i < 1000; i++) {
        final a = r.nextDouble() * 200 - 20;
        final b = r.nextDouble() * 200 - 20;
        final f = Iso.toTileFraction(Iso.toWorld(a, b));
        expect(f.dx, closeTo(a, 1e-9));
        expect(f.dy, closeTo(b, 1e-9));
      }
    });

    test('dimensions du losange 128×64', () {
      final d = Iso.diamond(3, 2);
      expect(d[1].dx - d[3].dx, 128);
      expect(d[2].dy - d[0].dy, 64);
      expect(Iso.tileCenter(0, 0), const Offset(0, 32));
      expect(Iso.fromFixed(256, 256), Iso.toWorld(1, 1));
    });

    test('cases visibles : bornées à la carte et couvrant la fenêtre', () {
      final t = Iso.visibleTiles(
        const Rect.fromLTWH(-300, 100, 600, 400),
        64,
        64,
      );
      expect(t.x0 >= 0 && t.y0 >= 0 && t.x1 <= 63 && t.y1 <= 63, isTrue);
      // Toute case dont le centre est dans la fenêtre est dans la zone.
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          if (const Rect.fromLTWH(
            -300,
            100,
            600,
            400,
          ).contains(Iso.tileCenter(x, y))) {
            expect(x >= t.x0 && x <= t.x1 && y >= t.y0 && y <= t.y1, isTrue);
          }
        }
      }
    });

    test('profondeur : plus loin du coin (0,0) = devant', () {
      expect(Iso.depthOfPoint(5, 5), greaterThan(Iso.depthOfPoint(3, 3)));
      expect(Iso.depthOfFootprint(2, 2, 3, 3), 2 + 3 + 2 + 3 - 1);
    });
  });

  group('caméra', () {
    GameCamera cam([Size s = const Size(1280, 720)]) =>
        GameCamera(mapWidth: 64, mapHeight: 64, viewport: s);

    test('zoom par défaut : nombre de cases visibles à peu près constant', () {
      int visibleRows(double h) =>
          (h / GameCamera.defaultZoomFor(h) / Iso.halfH).round();
      expect((visibleRows(720) - visibleRows(1440)).abs() <= 1, isTrue);
      expect((visibleRows(720) - visibleRows(360)).abs() <= 2, isTrue);
    });

    test('zoom borné', () {
      final c = cam();
      for (var i = 0; i < 50; i++) {
        c.zoomAt(1.3, const Offset(100, 100));
      }
      expect(c.zoom, GameCamera.maxZoom);
      for (var i = 0; i < 80; i++) {
        c.zoomAt(0.7, const Offset(100, 100));
      }
      expect(c.zoom, GameCamera.minZoom);
    });

    test(
      'zoom centré sur le pointeur : le point sous le curseur ne bouge pas',
      () {
        final c = cam();
        const anchor = Offset(900, 200);
        final before = c.screenToWorld(anchor);
        c.zoomAt(1.5, anchor);
        final after = c.screenToWorld(anchor);
        expect((before - after).distance, lessThan(1e-6));
      },
    );

    test('bornes de carte : la caméra ne s’éloigne pas du monde', () {
      final c = cam();
      c.panByScreen(const Offset(-10000000, -10000000));
      final f = Iso.toTileFraction(c.center);
      expect(f.dx >= -2.001 && f.dy >= -2.001, isTrue);
      c.panByScreen(const Offset(10000000, 10000000));
      final g = Iso.toTileFraction(c.center);
      expect(g.dx <= 66.001 && g.dy <= 66.001, isTrue);
    });

    test('redimensionnement : le centre est conservé, aucun état perdu', () {
      final c = cam();
      c.centerOnTile(20, 30);
      final center = c.center;
      final zoom = c.zoom;
      c.resize(const Size(1920, 1080));
      expect(c.center, center);
      expect(c.zoom, zoom);
      c.resize(Size.zero); // fenêtre réduite : ignoré
      expect(c.viewport, const Size(1920, 1080));
    });

    test('worldToScreen / screenToWorld sont inverses', () {
      final c = cam();
      c.zoomAt(1.7, const Offset(300, 300));
      for (final p in const [
        Offset.zero,
        Offset(640, 360),
        Offset(1279, 719),
      ]) {
        final w = c.screenToWorld(p);
        expect((c.worldToScreen(w) - p).distance, lessThan(1e-9));
      }
    });

    test('picking de case via la caméra', () {
      final c = cam();
      c.centerOnTile(32.5, 32.5);
      final s = c.worldToScreen(Iso.tileCenter(32, 32));
      expect(c.screenToTile(s), (x: 32, y: 32));
    });

    test('clavier et inertie', () {
      final c = cam();
      final start = c.center;
      c.update(0.5, keyboard: const Offset(900, 0));
      expect(c.center.dx, greaterThan(start.dx));
      c.fling(const Offset(-1200, 0));
      final x0 = c.center.dx;
      c.update(0.1);
      final x1 = c.center.dx;
      expect(x1, greaterThan(x0));
      for (var i = 0; i < 200; i++) {
        c.update(0.1);
      }
      expect(c.velocity, Offset.zero);
      c.inertia = false;
      c.fling(const Offset(500, 0));
      expect(c.velocity, Offset.zero);
    });

    test('défilement aux bords de l’écran', () {
      final c = cam();
      expect(c.edgeScrollVelocity(const Offset(5, 300)).dx, lessThan(0));
      expect(c.edgeScrollVelocity(const Offset(1279, 719)).dx, greaterThan(0));
      expect(c.edgeScrollVelocity(const Offset(1279, 719)).dy, greaterThan(0));
      expect(c.edgeScrollVelocity(const Offset(640, 360)), Offset.zero);
    });

    test('rectangle visible cohérent avec le zoom', () {
      final c = cam();
      final r = c.visibleWorld;
      expect(r.width * c.zoom, closeTo(1280, 1e-6));
      expect(r.height * c.zoom, closeTo(720, 1e-6));
    });
  });
}
