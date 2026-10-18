import 'dart:io';
import 'dart:ui';

import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/game/render/world_renderer.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/systems/vision.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

/// Mesure du coût de construction d'une image (enregistrement des commandes
/// de dessin + tri de profondeur). Le coût de rastérisation GPU n'est pas
/// couvert : il se mesure sur appareil (voir docs/PERF.md).
void main() {
  test('carte 128×128, 2 000 entités fixes + 200 mobiles : coût par image', () {
    final w = blankWorld(size: 128)..checkInvariantsEachTick = false;
    final r = Rng(5);
    var fixed = 0;
    while (fixed < 2000) {
      final x = r.range(1, 126);
      final y = r.range(1, 126);
      if (w.map.occupant[w.map.index(x, y)] != 0) continue;
      if (fixed % 40 == 0 && x < 120 && y < 120) {
        final b = addBuilding(w, 'hut', x, y);
        if (b.id > 0) fixed++;
      } else {
        addNode(w, fixed % 3 == 0 ? 'berries' : 'tree', x, y);
        fixed++;
      }
    }
    for (var i = 0; i < 200; i++) {
      final x = r.range(1, 126);
      final y = r.range(1, 126);
      if (!w.map.blocked(w.map.index(x, y))) {
        addUnit(w, 'villager', x, y, owner: i % 2);
      }
    }
    w.players[0].visible.fillRange(0, w.map.size, 1);
    updateVision(w);
    final reg = AssetRegistry.placeholders(testDefs);
    final renderer = WorldRenderer(world: w, assets: reg);
    final cam = GameCamera(
      mapWidth: 128,
      mapHeight: 128,
      viewport: const Size(1920, 1080),
    )..centerOnTile(64, 64);
    final sel = SelectionModel()..selectUnits(w.unitsOf(0).map((u) => u.id));

    double frameMs(double zoom, int frames) {
      cam.zoom = zoom;
      final sw = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        final rec = PictureRecorder();
        renderer.paint(
          Canvas(rec),
          const Size(1920, 1080),
          cam,
          viewerId: 0,
          selection: sel,
          alpha: 0.5,
          time: i / 60,
        );
        rec.endRecording().dispose();
        cam.panByScreen(const Offset(1, 0));
      }
      return sw.elapsedMicroseconds / 1000 / frames;
    }

    frameMs(0.6, 5); // échauffement + remplissage du cache de terrain
    final normal = frameMs(0.6, 60);
    final far = frameMs(GameCamera.minZoom, 30);
    // ignore: avoid_print, mesure affichée dans la sortie des tests
    print(
      'Rendu 128×128 / 2 000 entités / 200 unités : zoom 0,6 → '
      '${normal.toStringAsFixed(2)} ms/image ; zoom min → ${far.toStringAsFixed(2)} ms/image '
      '(${renderer.entities.lastDrawn} objets dessinés ; dernière image : '
      'construction ${renderer.entities.buildMicros} µs, '
      'tri ${renderer.entities.sortMicros} µs, '
      'dessin ${renderer.entities.paintMicros} µs)',
    );
    // Budget d'une image à 60 FPS = 16,6 ms, hors rastérisation GPU.
    final budget = Platform.environment['CI'] == 'true' ? 40 : 25;
    expect(normal, lessThan(budget));
    expect(far, lessThan(budget * 2));
    renderer.dispose();
  });
}
