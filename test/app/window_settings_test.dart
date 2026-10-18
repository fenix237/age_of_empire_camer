import 'dart:io';
import 'dart:ui';

import 'package:age_of_empire_camer/app/window/window_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const primary = Rect.fromLTWH(0, 0, 1920, 1080);
  const second = Rect.fromLTWH(1920, 0, 2560, 1440);

  group('sanitize', () {
    test("sans valeur : fenêtre par défaut centrée sur l'écran principal", () {
      final r = WindowSettings.sanitize(null, const [primary]);
      expect(r.size, kDefaultWindowSize);
      expect(r.center, primary.center);
    });

    test('rectangle valide conservé', () {
      const saved = Rect.fromLTWH(100, 100, 1300, 800);
      expect(WindowSettings.sanitize(saved, const [primary]), saved);
    });

    test("moniteur débranché : repli sur l'écran principal", () {
      const saved = Rect.fromLTWH(2500, 200, 1300, 800);
      final r = WindowSettings.sanitize(saved, const [primary]);
      expect(primary.contains(r.topLeft), isTrue);
      expect(primary.contains(r.bottomRight), isTrue);
    });

    test('moniteur secondaire présent : fenêtre conservée dessus', () {
      const saved = Rect.fromLTWH(2500, 200, 1300, 800);
      final r = WindowSettings.sanitize(saved, const [primary, second]);
      expect(r, saved);
    });

    test('trop petite : agrandie à la taille minimale', () {
      const saved = Rect.fromLTWH(10, 10, 200, 100);
      final r = WindowSettings.sanitize(saved, const [primary]);
      expect(r.width, kMinWindowSize.width);
      expect(r.height, kMinWindowSize.height);
    });

    test("plus grande que l'écran : réduite", () {
      const saved = Rect.fromLTWH(0, 0, 5000, 4000);
      final r = WindowSettings.sanitize(saved, const [primary]);
      expect(r.width, primary.width);
      expect(r.height, primary.height);
    });

    test('aucun écran détecté : ne plante pas', () {
      final r = WindowSettings.sanitize(null, const []);
      expect(r.width, greaterThan(0));
    });
  });

  group('fromJson', () {
    test('valeurs invalides donnent les défauts', () {
      expect(WindowSettings.fromJson(null).bounds, isNull);
      expect(WindowSettings.fromJson('x').fullScreen, isFalse);
      expect(
        WindowSettings.fromJson(<String, dynamic>{
          'x': 'a',
          'y': 0,
          'w': 10,
          'h': 10,
        }).bounds,
        isNull,
      );
      expect(
        WindowSettings.fromJson(<String, dynamic>{
          'x': 0,
          'y': 0,
          'w': -5,
          'h': 10,
        }).bounds,
        isNull,
      );
    });

    test('aller-retour JSON', () {
      const s = WindowSettings(
        bounds: Rect.fromLTWH(1, 2, 1100, 700),
        fullScreen: true,
      );
      final back = WindowSettings.fromJson(s.toJson());
      expect(back.bounds, s.bounds);
      expect(back.fullScreen, isTrue);
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ws_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('sauvegarde puis relecture', () async {
      final store = WindowSettingsStore(dir);
      await store.save(
        const WindowSettings(
          bounds: Rect.fromLTWH(5, 6, 1200, 800),
          fullScreen: true,
        ),
      );
      final loaded = await store.load();
      expect(loaded.bounds, const Rect.fromLTWH(5, 6, 1200, 800));
      expect(loaded.fullScreen, isTrue);
    });

    test("fichier corrompu : valeurs par défaut, pas d'exception", () async {
      File('${dir.path}/window.json').writeAsStringSync('{ pas du json');
      final loaded = await WindowSettingsStore(dir).load();
      expect(loaded.bounds, isNull);
    });
  });
}
