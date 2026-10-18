import 'package:age_of_empire_camer/game/camera.dart';
import 'package:age_of_empire_camer/game/game_loop.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:age_of_empire_camer/game/selection.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';

void main() {
  group('boucle de jeu', () {
    test('10 ticks par seconde à vitesse ×1', () {
      final l = GameLoop();
      var total = 0;
      for (var i = 0; i < 60; i++) {
        total += l.advance(1 / 60);
      }
      expect(total, anyOf(9, 10));
    });

    test('vitesse ×2 = 2 ticks par intervalle (jamais un pas plus grand)', () {
      final l = GameLoop()..speed = 2;
      var total = 0;
      for (var i = 0; i < 60; i++) {
        total += l.advance(1 / 60);
      }
      expect(total, anyOf(19, 20));
    });

    test('plafond de rattrapage : pas de spirale de la mort', () {
      final l = GameLoop();
      expect(l.advance(0.25), lessThanOrEqualTo(5));
      expect(
        l.advance(10),
        lessThanOrEqualTo(5),
      ); // dt aberrant ramené à 0,25 s
      // Le retard est abandonné : la frame suivante ne rattrape pas.
      expect(l.advance(1 / 60), lessThanOrEqualTo(1));
    });

    test('pause : aucun tick ; plusieurs raisons cumulables', () {
      final l = GameLoop()
        ..pause(PauseReason.user)
        ..pause(PauseReason.lifecycle);
      expect(l.advance(1), 0);
      l.resume(PauseReason.user);
      expect(l.paused, isTrue);
      l.resume(PauseReason.lifecycle);
      expect(l.paused, isFalse);
      expect(l.advance(0.1), anyOf(0, 1));
      l.toggleUserPause();
      expect(l.paused, isTrue);
      l.toggleUserPause();
      expect(l.paused, isFalse);
    });

    test('interpolation alpha entre 0 et 1', () {
      final l = GameLoop();
      l.advance(0.05);
      expect(l.alpha, closeTo(0.5, 0.01));
      expect(l.advance(-1), 0);
    });

    test('vitesses : cycle et bornes', () {
      final l = GameLoop();
      expect(l.speed, 1);
      l.speedUp();
      expect(l.speed, 1.5);
      l.speedUp();
      l.speedUp();
      expect(l.speed, 2);
      l.speedDown();
      expect(l.speed, 1.5);
      l.cycleSpeed();
      l.cycleSpeed();
      expect(l.speed, 1);
      l.speedDown();
      expect(l.speed, 1);
    });
  });

  group('sélection', () {
    test('clic sur une unité, un bâtiment, une ressource, le vide', () {
      final w = blankWorld();
      final u = addUnit(w, 'villager', 10, 10);
      final b = addBuilding(w, 'town_center', 20, 20);
      final tree = addNode(w, 'tree', 6, 6);
      final cam = GameCamera(mapWidth: 40, mapHeight: 40)..centerOnTile(15, 15);
      Offset at(double tx, double ty) => cam.worldToScreen(Iso.toWorld(tx, ty));
      expect(pickAt(w, cam, at(10.5, 10.5).translate(0, -18)).id, u.id);
      expect(pickAt(w, cam, at(21, 21)).kind, PickKind.building);
      expect(pickAt(w, cam, at(21, 21)).id, b.id);
      final r = pickAt(w, cam, at(6.5, 6.5));
      expect(r.kind, PickKind.resource);
      expect(r.id, tree.id);
      expect(pickAt(w, cam, at(30, 3)).kind, PickKind.none);
    });

    test(
      'tolérance tactile : le doigt à côté d’une unité la désigne quand même',
      () {
        final w = blankWorld();
        final u = addUnit(w, 'villager', 10, 10);
        final cam = GameCamera(mapWidth: 40, mapHeight: 40)
          ..centerOnTile(10, 10);
        final p = unitScreenPos(cam, u);
        expect(pickAt(w, cam, p.translate(24, 0)).kind, PickKind.none);
        expect(pickAt(w, cam, p.translate(24, 0), tolerance: 28).id, u.id);
        expect(
          pickAt(w, cam, p.translate(60, 0), tolerance: 28).kind,
          isNot(PickKind.unit),
        );
      },
    );

    test('rectangle, ajout, bascule, groupes de contrôle', () {
      final w = blankWorld();
      final a = addUnit(w, 'villager', 10, 10);
      final b = addUnit(w, 'villager', 11, 10);
      final c = addUnit(w, 'spearman', 12, 10);
      final enemy = addUnit(w, 'villager', 10, 12, owner: 1);
      final cam = GameCamera(mapWidth: 40, mapHeight: 40)..centerOnTile(11, 11);
      final rect = Offset.zero & cam.viewport;
      final ids = unitsInScreenRect(w, cam, rect, 0);
      expect(ids.toSet(), {a.id, b.id, c.id});
      expect(ids, isNot(contains(enemy.id)));

      final s = SelectionModel()..selectUnits([a.id]);
      s.selectUnits([b.id], add: true);
      expect(s.units, [a.id, b.id]);
      s.toggleUnit(a.id);
      expect(s.units, [b.id]);
      s.setGroup(3);
      s.clear();
      expect(s.isEmpty, isTrue);
      expect(s.recallGroup(3, w), isTrue);
      expect(s.units, [b.id]);
      w.killUnit(b);
      w.step();
      s.prune(w);
      expect(s.isEmpty, isTrue);
      expect(s.recallGroup(3, w), isFalse);
      expect(s.recallGroup(7, w), isFalse);
    });

    test('double-clic : toutes les unités du même type visibles', () {
      final w = blankWorld();
      final a = addUnit(w, 'villager', 10, 10);
      final b = addUnit(w, 'villager', 12, 10);
      addUnit(w, 'spearman', 11, 10);
      final far = addUnit(w, 'villager', 39, 39);
      final cam = GameCamera(mapWidth: 40, mapHeight: 40)
        ..centerOnTile(11, 11)
        ..zoomAt(2, const Offset(640, 360));
      final ids = SelectionModel().sameTypeVisible(w, cam, a);
      expect(ids, containsAll([a.id, b.id]));
      expect(ids, isNot(contains(far.id)));
      expect(ids.length, 2);
    });

    test('villageois inactifs : parcours cyclique', () {
      final w = blankWorld();
      final a = addUnit(w, 'villager', 10, 10);
      final b = addUnit(w, 'villager', 11, 10);
      addUnit(w, 'spearman', 12, 10);
      final s = SelectionModel();
      expect(s.nextIdleVillager(w, 0)!.id, a.id);
      expect(s.nextIdleVillager(w, 0)!.id, b.id);
      expect(s.nextIdleVillager(w, 0)!.id, a.id);
      expect(s.nextIdleVillager(w, 1), isNull);
    });

    test('sélection de bâtiment remplace les unités, et inversement', () {
      final s = SelectionModel()..selectUnits([1, 2]);
      s.selectBuilding(9);
      expect(s.units, isEmpty);
      expect(s.building, 9);
      expect(s.contains(9), isTrue);
      s.selectUnits([4]);
      expect(s.building, -1);
    });

    test('unités garnisonnées non sélectionnables', () {
      final w = blankWorld();
      final u = addUnit(w, 'villager', 10, 10);
      u.state = UnitState.garrisoned;
      final cam = GameCamera(mapWidth: 40, mapHeight: 40)..centerOnTile(10, 10);
      expect(pickAt(w, cam, unitScreenPos(cam, u)).kind, isNot(PickKind.unit));
      expect(unitsInScreenRect(w, cam, Offset.zero & cam.viewport, 0), isEmpty);
    });
  });
}
