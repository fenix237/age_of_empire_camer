import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';

void main() {
  test('déplacement : l’unité atteint le centre de la case et s’arrête', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 2);
    w.submit(MoveCmd(0, [u.id], 12, 7));
    runUntil(
      w,
      () => u.isIdle && u.tileX == 12 && u.tileY == 7,
      why: 'arrivée',
    );
    expect(u.x, Fx.tileCenter(12));
    expect(u.y, Fx.tileCenter(7));
    expect(u.orders, isEmpty);
    expectHealthy(w);
  });

  test('vitesse : une unité rapide arrive avant une unité lente', () {
    final w = blankWorld();
    final slow = addUnit(w, 'villager', 2, 2);
    final fast = addUnit(w, 'horseman', 2, 4);
    w
      ..submit(MoveCmd(0, [slow.id], 30, 2))
      ..submit(MoveCmd(0, [fast.id], 30, 4));
    final tFast = runUntil(w, () => fast.isIdle && fast.tileX == 30);
    final tSlow = runUntil(w, () => slow.isIdle && slow.tileX == 30);
    expect(tFast, lessThan(tSlow + tFast));
    expect(fast.tileX, 30);
  });

  test('contournement d’un obstacle', () {
    final w = blankWorld();
    for (var y = 0; y < 30; y++) {
      addNode(w, 'tree', 10, y);
    }
    final u = addUnit(w, 'villager', 5, 10);
    w.submit(MoveCmd(0, [u.id], 15, 10));
    runUntil(w, () => u.isIdle && u.tileX == 15);
    expect(u.tileY, 10);
    expectHealthy(w);
  });

  test('cible inaccessible : l’unité se rapproche puis s’arrête', () {
    final w = blankWorld();
    for (var x = 8; x <= 12; x++) {
      addNode(w, 'tree', x, 8);
      addNode(w, 'tree', x, 12);
    }
    for (var y = 9; y <= 11; y++) {
      addNode(w, 'tree', 8, y);
      addNode(w, 'tree', 12, y);
    }
    final u = addUnit(w, 'villager', 2, 10);
    w.submit(MoveCmd(0, [u.id], 10, 10));
    runUntil(w, () => u.isIdle && w.tick > 5);
    expect((u.tileX - 10).abs() <= 3, isTrue);
    expect(u.tileX, lessThan(8));
    expectHealthy(w);
  });

  test('file d’ordres : waypoints successifs avec Maj+clic', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 2);
    w
      ..submit(MoveCmd(0, [u.id], 10, 2))
      ..submit(MoveCmd(0, [u.id], 10, 10, queue: true))
      ..submit(MoveCmd(0, [u.id], 2, 10, queue: true));
    w.step();
    expect(u.orders.length, 3);
    runUntil(w, () => u.isIdle && w.tick > 3);
    expect((u.tileX, u.tileY), (2, 10));
    expectHealthy(w);
  });

  test('un nouvel ordre sans file remplace les précédents', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 2);
    w.submit(MoveCmd(0, [u.id], 30, 30));
    run(w, 5);
    w.submit(MoveCmd(0, [u.id], 3, 3));
    runUntil(w, () => u.isIdle && w.tick > 6);
    expect((u.tileX, u.tileY), (3, 3));
  });

  test('stop annule le déplacement', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 2);
    w.submit(MoveCmd(0, [u.id], 30, 30));
    run(w, 10);
    w.submit(StopCmd(0, [u.id]));
    run(w, 2);
    expect(u.isIdle, isTrue);
    final x = u.x;
    run(w, 10);
    expect(u.x, x);
  });

  test('commandes invalides rejetées sans effet', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 2);
    final other = addUnit(w, 'villager', 5, 5, owner: 1);
    expect(MoveCmd(0, [u.id], -3, 4).apply(w), CmdResult.invalid);
    expect(MoveCmd(0, [u.id], 500, 4).apply(w), CmdResult.invalid);
    expect(MoveCmd(0, [other.id], 3, 3).apply(w), CmdResult.noUnits);
    expect(const MoveCmd(0, [9999], 3, 3).apply(w), CmdResult.noUnits);
    expect(MoveCmd(7, [u.id], 3, 3).apply(w), CmdResult.invalid);
    expect(MoveCmd(-1, [u.id], 3, 3).apply(w), CmdResult.invalid);
    expect(u.isIdle, isTrue);
    expect(other.isIdle, isTrue);
  });

  test('groupe ≥ 8 : flow field, vitesse alignée, arrivée groupée', () {
    final w = blankWorld(size: 60);
    for (var y = 0; y < 50; y++) {
      if (y != 20 && y != 21) addNode(w, 'tree', 25, y);
    }
    final ids = <int>[
      for (var i = 0; i < 12; i++)
        addUnit(
          w,
          i.isEven ? 'villager' : 'horseman',
          5 + i % 4,
          18 + i ~/ 4,
        ).id,
    ];
    w.submit(MoveCmd(0, ids, 45, 20));
    w.step();
    expect(w.flows, isNotEmpty);
    final speeds = {for (final id in ids) w.units[id]!.speedCap};
    expect(speeds.length, 1, reason: 'même plafond de vitesse');
    expect(speeds.first, w.units[ids.first]!.def.speedFxPerTick);
    runUntil(w, () => ids.every((id) => w.units[id]!.isIdle), limit: 2500);
    for (final id in ids) {
      final u = w.units[id]!;
      expect(
        (u.tileX - 45).abs() <= 3 && (u.tileY - 20).abs() <= 3,
        isTrue,
        reason: 'unité $id en (${u.tileX},${u.tileY})',
      );
    }
    // Les flows inutilisés sont libérés.
    run(w, 40);
    expect(w.flows, isEmpty);
    expectHealthy(w);
  });

  test('séparation : deux unités superposées s’écartent', () {
    final w = blankWorld();
    final a = addUnit(w, 'villager', 5, 5);
    final b = addUnit(w, 'villager', 5, 5);
    run(w, 30);
    final d = a.pos.distTo(b.pos);
    expect(d, greaterThan(40));
    expect(w.map.blocked(w.map.index(a.tileX, a.tileY)), isFalse);
  });

  test('bâtiment posé sur le chemin : replanification', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 10);
    final b = addUnit(w, 'villager', 20, 25);
    w.submit(MoveCmd(0, [u.id], 30, 10));
    run(w, 40);
    // Mur de huttes en travers du chemin.
    for (var y = 6; y <= 14; y += 2) {
      addBuilding(w, 'hut', 14, y);
    }
    runUntil(w, () => u.isIdle && w.tick > 45, limit: 2000);
    expect(u.tileX, 30);
    expect(b.isIdle, isTrue);
    expectHealthy(w);
  });

  test('transition d’état illégale : détectée et ramenée à inactif', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 2);
    u.state = UnitState.dead;
    expect(
      () => w.setState(u, UnitState.moving),
      throwsA(isA<AssertionError>()),
    );
    expect(w.violations, isNotEmpty);
    // Table de transitions : mort est absorbant, garnison ne mène qu'à idle.
    expect(allowedTransitions[UnitState.dead], isEmpty);
    expect(
      allowedTransitions[UnitState.garrisoned],
      {UnitState.idle, UnitState.dead},
    );
  });

  test('ordre en file plein : limité à 32', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 2, 2);
    for (var i = 0; i < 40; i++) {
      w.submit(MoveCmd(0, [u.id], 3 + i % 5, 3, queue: i > 0));
    }
    w.step();
    expect(u.orders.length, 32);
    expect(u.order, const Order(OrderKind.move, 3, 3));
  });
}
