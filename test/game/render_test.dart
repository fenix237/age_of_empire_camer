import 'dart:ui';

import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/game_controller.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/render/assets.dart';
import 'package:age_of_empire_camer/game/render/fog_renderer.dart';
import 'package:age_of_empire_camer/game/render/terrain_renderer.dart';
import 'package:age_of_empire_camer/game/render/world_renderer.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/vision.dart';
import 'package:age_of_empire_camer/ui/hud/minimap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

/// Rend le monde dans un Picture et renvoie la caméra utilisée.
void _renderOnce(
  WorldRenderer r,
  GameCamera cam,
  int viewer, {
  Size size = const Size(800, 500),
}) {
  final rec = PictureRecorder();
  r.paint(
    Canvas(rec),
    size,
    cam,
    viewerId: viewer,
    selection: SelectionModel(),
    alpha: 1,
    time: 0,
  );
  rec.endRecording().dispose();
}

void main() {
  test(
    'tous les assets référencés par les définitions existent (placeholders)',
    () {
      final reg = AssetRegistry.placeholders(testDefs);
      for (final u in testDefs.units) {
        expect(reg.has('unit/${u.id}'), isTrue);
      }
      for (final b in testDefs.buildings) {
        expect(reg.has('building/${b.id}'), isTrue);
      }
      for (final r in testDefs.resources) {
        expect(reg.has('resource/${r.id}'), isTrue);
      }
      for (final t in testDefs.terrain) {
        expect(reg.has('terrain/${t.id}'), isTrue);
      }
      // Une clé inconnue est signalée (test de complétude de la Phase 9).
      final rec = PictureRecorder();
      reg.draw('unit/dragon', Canvas(rec), Offset.zero, const SpriteContext());
      expect(reg.missing, {'unit/dragon'});
    },
  );

  test(
    'rendu complet d’une vraie partie : aucune exception, aucun asset manquant',
    () {
      final w = createGame(testDefs, seed: 9);
      final reg = AssetRegistry.placeholders(testDefs);
      final r = WorldRenderer(world: w, assets: reg);
      final cam = GameCamera(mapWidth: 64, mapHeight: 64);
      final p = w.players[0];
      cam.centerOnTile(p.startX + 0.5, p.startY + 0.5);
      for (var i = 0; i < 20; i++) {
        w.step();
      }
      _renderOnce(r, cam, 0);
      expect(reg.missing, isEmpty);
      expect(r.entities.lastDrawn, greaterThan(5));
      r.dispose();
    },
  );

  test(
    'terrain mis en cache par blocs : reconstruit seulement si invalidé',
    () {
      final w = blankWorld(size: 64);
      final reg = AssetRegistry.placeholders(testDefs);
      final t = TerrainRenderer(w.map, reg);
      final rec = PictureRecorder();
      final c = Canvas(rec);
      final cam = GameCamera(mapWidth: 64, mapHeight: 64)..centerOnTile(32, 32);
      t.paint(c, cam.visibleWorld);
      final first = t.rebuilds;
      expect(first, greaterThan(0));
      t.paint(c, cam.visibleWorld);
      expect(t.rebuilds, first, reason: 'cache réutilisé');
      t.invalidateTile(32, 32);
      t.paint(c, cam.visibleWorld);
      expect(t.rebuilds, greaterThan(first));
      final before = t.rebuilds;
      t.invalidateAll();
      expect(t.cachedChunks, 0);
      t.paint(c, cam.visibleWorld);
      expect(t.rebuilds, greaterThan(before));
      rec.endRecording().dispose();
      t.dispose();
    },
  );

  test(
    'auto-tiling : les transitions pointent vers les voisins prioritaires',
    () {
      final w = blankWorld(size: 20);
      final m = w.map;
      final grass = m.terrain[0];
      // Colonne d'eau peu profonde à x == 10.
      for (var y = 0; y < 20; y++) {
        m.terrain[m.index(10, y)] = testDefs.terrain
            .firstWhere((t) => t.id == 'shallow')
            .index;
      }
      // L'herbe (prioritaire) ne reçoit rien ; l'eau reçoit l'herbe des deux côtés.
      expect(transitionMask(m, 9, 5), 0);
      expect(transitionMask(m, 11, 5), 0);
      expect(transitionMask(m, 10, 5), 2 | 8);
      expect(transitionMask(m, 5, 5), 0);
      expect(grass, isNonNegative);
      expect(
        terrainPriority('mountain'),
        greaterThan(terrainPriority('grass')),
      );
      expect(terrainPriority('inconnu'), 5);
    },
  );

  test('brouillard : trois états dérivés de la vision', () {
    final w = createGame(testDefs, seed: 3);
    final p = w.players[0];
    final tc = w.buildings.values.firstWhere((b) => b.owner == 0);
    final centre = w.map.index(tc.tx + 1, tc.ty + 1);
    expect(FogRenderer.stateOf(p, centre), 2);
    var unknown = 0;
    var explored = 0;
    for (var i = 0; i < w.map.size; i++) {
      final s = FogRenderer.stateOf(p, i);
      if (s == 0) unknown++;
      if (s == 1) explored++;
    }
    expect(
      unknown,
      greaterThan(w.map.size ~/ 2),
      reason: 'la plupart est inconnue',
    );
    expect(explored, 0, reason: 'rien n’a encore été quitté');
    // Fait partir toutes les unités et recalcule : l’ancienne zone devient « explorée ».
    List.of(w.units.values).forEach(w.killUnit);
    for (var i = 0; i < 6; i++) {
      w.step();
    }
    w.buildings.values.toList().forEach(
      (b) => w.removeBuilding(b, destroyed: true),
    );
    updateVision(w);
    expect(FogRenderer.stateOf(p, centre), 1);
    final f = FogRenderer(w.map);
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    final cam = GameCamera(mapWidth: 64, mapHeight: 64)
      ..centerOnTile(p.startX + 0.5, p.startY + 0.5);
    f.paint(canvas, cam.visibleWorld, p, w.visionRevision);
    final built = f.rebuilds;
    f.paint(canvas, cam.visibleWorld, p, w.visionRevision);
    expect(
      f.rebuilds,
      built,
      reason: 'cache tant que la révision ne change pas',
    );
    updateVision(w);
    f.paint(canvas, cam.visibleWorld, p, w.visionRevision);
    expect(f.rebuilds, greaterThan(built));
    rec.endRecording().dispose();
    f.dispose();
  });

  test('les unités ennemies hors vision ne sont pas dessinées', () {
    final w = blankWorld();
    for (var i = 0; i < 3; i++) {
      addUnit(w, 'villager', 30 + i, 30, owner: 1);
    }
    addUnit(w, 'villager', 5, 5);
    final reg = AssetRegistry.placeholders(testDefs);
    final r = WorldRenderer(world: w, assets: reg);
    final cam = GameCamera(mapWidth: 40, mapHeight: 40)..centerOnTile(20, 20);
    // blankWorld rend tout « exploré » mais pas « visible » à distance.
    _renderOnce(r, cam, 0, size: const Size(1600, 900));
    final shown = r.entities.lastDrawn;
    w.players[0].visible.fillRange(0, w.map.size, 1);
    _renderOnce(r, cam, 0, size: const Size(1600, 900));
    expect(r.entities.lastDrawn, greaterThan(shown));
    r.dispose();
  });

  test('mini-carte : pixels du terrain, brouillard et bâtiments', () {
    final w = createGame(testDefs, seed: 3);
    final px = MiniMapImage.buildPixels(w, 0);
    expect(px.length, 64 * 64 * 4);
    final p = w.players[0];
    final tc = w.buildings.values.firstWhere((b) => b.owner == 0);
    final i = w.map.index(tc.tx, tc.ty) * 4;
    final team = teamColor(0);
    expect(px[i], (team.r * 255).round());
    // Une case inconnue est noire.
    final unknown = List.generate(
      w.map.size,
      (k) => k,
    ).firstWhere((k) => p.explored[k] == 0);
    expect(px.sublist(unknown * 4, unknown * 4 + 3), [0, 0, 0]);

    final g = MiniMapGeometry(const Size(200, 120), 64, 64);
    final back = g.toTile(g.fromTile(20.5, 33.25));
    expect(back.dx, closeTo(20.5, 1e-9));
    expect(back.dy, closeTo(33.25, 1e-9));
  });

  testWidgets(
    'goldens : scène de profondeur et de transitions',
    tags: ['golden'],
    (
      tester,
    ) async {
      final w = blankWorld(size: 24);
      // Lac au nord-ouest.
      final shallow = testDefs.terrain
          .firstWhere((t) => t.id == 'shallow')
          .index;
      final sand = testDefs.terrain.firstWhere((t) => t.id == 'sand').index;
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          if ((x - 3) * (x - 3) + (y - 3) * (y - 3) < 10) {
            w.map.terrain[w.map.index(x, y)] = shallow;
          }
          if ((x - 3) * (x - 3) + (y - 3) * (y - 3) < 18 &&
              w.map.terrain[w.map.index(x, y)] != shallow) {
            w.map.terrain[w.map.index(x, y)] = sand;
          }
        }
      }
      addBuilding(w, 'town_center', 10, 10);
      addBuilding(w, 'barracks', 15, 11, owner: 1);
      addBuilding(w, 'hut', 10, 15, complete: false).progressMilli = 400;
      addBuilding(w, 'field', 14, 15);
      addNode(w, 'tree', 9, 9);
      addNode(w, 'tree', 14, 9);
      addNode(w, 'berries', 8, 13);
      addNode(w, 'gold_mine', 17, 15);
      addNode(w, 'quarry', 18, 8);
      // Unités devant, derrière et contre les flancs du centre-ville.
      addUnit(w, 'villager', 14, 11);
      addUnit(w, 'spearman', 12, 14);
      addUnit(w, 'villager', 9, 12, owner: 1);
      addUnit(w, 'horseman', 13, 9);
      addUnit(w, 'archer', 11, 9);
      w.players[0].visible.fillRange(0, w.map.size, 1);
      final c = GameController(world: w, defs: testDefs);
      c.camera.centerOnTile(12, 12);
      c.selection.selectUnits(w.unitsOf(0).map((u) => u.id));
      await tester.binding.setSurfaceSize(const Size(900, 560));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: const ValueKey('scene'),
            child: CustomPaint(
              size: const Size(900, 560),
              painter: _ScenePainter(c),
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('scene')),
        matchesGoldenFile('goldens/scene_depth.png'),
      );
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'goldens : terrain, transitions, brouillard, aperçu de construction',
    tags: ['golden'],
    (tester) async {
      final w = blankWorld();
      final shallow = testDefs.terrain
          .firstWhere((t) => t.id == 'shallow')
          .index;
      final deep = testDefs.terrain.firstWhere((t) => t.id == 'deep').index;
      final sand = testDefs.terrain.firstWhere((t) => t.id == 'sand').index;
      final mountain = testDefs.terrain
          .firstWhere((t) => t.id == 'mountain')
          .index;
      final dirt = testDefs.terrain.firstWhere((t) => t.id == 'dirt').index;
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final d = (x - 14) * (x - 14) + (y - 14) * (y - 14);
          final i = w.map.index(x, y);
          if (d < 6) {
            w.map.terrain[i] = deep;
          } else if (d < 22) {
            w.map.terrain[i] = shallow;
          } else if (d < 34) {
            w.map.terrain[i] = sand;
          }
          if (x > 22 && x < 27 && y > 8 && y < 16) w.map.terrain[i] = mountain;
          if (x > 18 && x < 30 && y > 20 && y < 24) w.map.terrain[i] = dirt;
        }
      }
      for (var i = 0; i < 12; i++) {
        addNode(w, 'tree', 20 + i % 4, 18 + i ~/ 4);
      }
      final v = addUnit(w, 'villager', 20, 20);
      addUnit(w, 'villager', 21, 21);
      // Seule une petite zone est visible/explorée.
      final p = w.players[0];
      p.explored.fillRange(0, p.explored.length, 0);
      p.visible.fillRange(0, p.visible.length, 0);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          final d = (x - 20) * (x - 20) + (y - 20) * (y - 20);
          if (d < 100) p.explored[w.map.index(x, y)] = 1;
          if (d < 30) p.visible[w.map.index(x, y)] = 1;
        }
      }
      final c = GameController(world: w, defs: testDefs);
      c.camera.centerOnTile(18, 18);
      c.selection.selectUnits([v.id]);
      c.placing = testDefs.building('barracks');
      c.ghostX = 24;
      c.ghostY = 21;
      c.ghostValid = true;
      c.markers.add(
        OrderMarker(Iso.tileCenter(18, 22), 0, const Color(0xFF9BE8A8)),
      );
      await tester.binding.setSurfaceSize(const Size(1000, 640));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: const ValueKey('scene2'),
            child: CustomPaint(
              size: const Size(1000, 640),
              painter: _ScenePainter(c, fog: true),
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(const ValueKey('scene2')),
        matchesGoldenFile('goldens/scene_terrain_fog.png'),
      );
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.c, {this.fog = false});

  final GameController c;
  final bool fog;

  @override
  void paint(Canvas canvas, Size size) {
    c.renderer.paint(
      canvas,
      size,
      c.camera,
      viewerId: 0,
      selection: c.selection,
      alpha: 1,
      time: 0,
      markers: c.markers,
      ghost: c.ghost,
      fogEnabled: fog,
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;
}
