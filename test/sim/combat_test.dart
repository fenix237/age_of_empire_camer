import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';

void main() {
  test('mêlée : l’unité poursuit, frappe et tue ; la cible est retirée', () {
    final w = blankWorld();
    final s = addUnit(w, 'spearman', 5, 5);
    final v = addUnit(w, 'villager', 12, 5, owner: 1);
    w.submit(AttackCmd(0, [s.id], v.id));
    runUntil(w, () => !w.units.containsKey(v.id), limit: 800);
    expect(w.units.containsKey(s.id), isTrue);
    run(w, 2);
    expect(s.isIdle, isTrue, reason: 'ordre terminé à la mort de la cible');
    expectHealthy(w);
  });

  test('dégâts = max(1, attaque − armure)', () {
    final w = blankWorld();
    final s = addUnit(w, 'spearman', 5, 5); // attaque 4
    final iron = addUnit(w, 'iron_warrior', 6, 5, owner: 1); // armure 1
    s.stance = Stance.passive;
    iron.stance = Stance.passive;
    w.submit(AttackCmd(0, [s.id], iron.id));
    runUntil(w, () => iron.hp < iron.def.hp, limit: 200);
    expect(iron.def.hp - iron.hp, 3);
    expectHealthy(w);
  });

  test(
    'distance : l’archer tire depuis sa portée sans s’approcher au contact',
    () {
      final w = blankWorld();
      w.players[0].age = 1;
      final a = addUnit(w, 'archer', 5, 5);
      final v = addUnit(w, 'villager', 10, 5, owner: 1);
      a.stance = Stance.passive;
      w.submit(AttackCmd(0, [a.id], v.id));
      runUntil(w, () => v.hp < v.def.hp, limit: 400);
      final dist = a.pos.distTo(v.pos);
      expect(dist, greaterThan(256));
      expect(dist, lessThanOrEqualTo(5 * 256 + 64));
    },
  );

  test('riposte : une unité militaire inactive répond à une attaque', () {
    final w = blankWorld();
    final attacker = addUnit(w, 'spearman', 5, 5);
    final victim = addUnit(w, 'spearman', 7, 5, owner: 1);
    attacker.stance = Stance.passive;
    w.submit(AttackCmd(0, [attacker.id], victim.id));
    runUntil(w, () => victim.order?.kind == OrderKind.attack, limit: 300);
    expect(victim.order!.a, attacker.id);
  });

  test('posture passive : n’attaque jamais seule ; agressive : si', () {
    final w = blankWorld();
    final passive = addUnit(w, 'spearman', 5, 5)..stance = Stance.passive;
    final enemy = addUnit(w, 'villager', 8, 5, owner: 1);
    run(w, 60);
    expect(passive.isIdle, isTrue);
    expect(enemy.hp, enemy.def.hp);

    final w2 = blankWorld();
    final aggressive = addUnit(w2, 'spearman', 5, 5);
    final enemy2 = addUnit(w2, 'villager', 9, 5, owner: 1);
    runUntil(w2, () => enemy2.hp < enemy2.def.hp, limit: 300);
    expect(aggressive.state, anyOf(UnitState.attacking, UnitState.idle));
  });

  test('posture défensive : réagit seulement à portée proche', () {
    final w = blankWorld();
    final d = addUnit(w, 'spearman', 5, 5)..stance = Stance.defensive;
    final far = addUnit(w, 'villager', 12, 5, owner: 1);
    run(w, 60);
    expect(d.isIdle, isTrue);
    expect(far.hp, far.def.hp);
    final near = addUnit(w, 'villager', 7, 5, owner: 1);
    runUntil(w, () => near.hp < near.def.hp, limit: 300);
  });

  test('suivre : l’unité reste près de sa cible', () {
    final w = blankWorld();
    final leader = addUnit(w, 'villager', 5, 5);
    final f = addUnit(w, 'spearman', 5, 8)
      ..stance = Stance.follow
      ..followId = leader.id;
    w.submit(MoveCmd(0, [leader.id], 30, 30));
    runUntil(w, () => leader.isIdle && w.tick > 5, limit: 2000);
    run(w, 200);
    expect(f.pos.distTo(leader.pos), lessThan(5 * 256));
    expectHealthy(w);
  });

  test('bâtiment : les soldats le détruisent et la case est libérée', () {
    final w = blankWorld();
    final target = addBuilding(w, 'hut', 15, 10, owner: 1);
    target.hp = 6;
    final s = addUnit(w, 'spearman', 8, 10);
    w.submit(AttackCmd(0, [s.id], target.id));
    runUntil(w, () => !w.buildings.containsKey(target.id), limit: 1200);
    expect(w.map.occupant[w.map.index(15, 10)], 0);
    run(w, 3);
    expect(s.isIdle, isTrue);
    expectHealthy(w);
  });

  test('double mort simultanée : deux tueurs sur la même cible', () {
    final w = blankWorld();
    final a = addUnit(w, 'spearman', 5, 5);
    final b = addUnit(w, 'spearman', 5, 7);
    final v = addUnit(w, 'villager', 6, 6, owner: 1)..hp = 1;
    w.submit(AttackCmd(0, [a.id, b.id], v.id));
    runUntil(w, () => !w.units.containsKey(v.id), limit: 200);
    run(w, 3);
    expect(a.isIdle && b.isIdle, isTrue);
    expect(w.units.length, 2);
    expectHealthy(w);
  });

  test('cible morte avant l’exécution : commande refusée proprement', () {
    final w = blankWorld();
    final s = addUnit(w, 'spearman', 5, 5);
    final v = addUnit(w, 'villager', 7, 5, owner: 1);
    w.killUnit(v);
    w.step();
    expect(AttackCmd(0, [s.id], v.id).apply(w), CmdResult.wrongTarget);
    final own = addUnit(w, 'villager', 9, 9);
    expect(AttackCmd(0, [s.id], own.id).apply(w), CmdResult.wrongTarget);
    expect(AttackCmd(0, [own.id], s.id).apply(w), CmdResult.wrongTarget);
  });

  test('mort d’une unité visée : les références sont purgées', () {
    final w = blankWorld();
    final s = addUnit(w, 'spearman', 5, 5)..stance = Stance.passive;
    final v = addUnit(w, 'villager', 20, 20, owner: 1);
    w.submit(AttackCmd(0, [s.id], v.id));
    w.submit(MoveCmd(0, [s.id], 3, 3, queue: true));
    run(w, 5);
    expect(s.orders.length, 2);
    w.killUnit(v);
    run(w, 2);
    expect(s.orders.every((o) => o.kind != OrderKind.attack), isTrue);
    runUntil(w, () => s.isIdle && s.tileX == 3, limit: 800);
    expectHealthy(w);
  });

  test('friendly fire interdit : on n’attaque pas ses alliés', () {
    final w = blankWorld();
    final a = addUnit(w, 'spearman', 5, 5);
    final b = addUnit(w, 'spearman', 6, 5);
    expect(AttackCmd(0, [a.id], b.id).apply(w), CmdResult.wrongTarget);
    run(w, 60);
    expect(b.hp, b.def.hp);
  });

  test('unité garnisonnée : inattaquable', () {
    final w = blankWorld();
    final tc = addBuilding(w, 'town_center', 5, 5, owner: 1);
    final v = addUnit(w, 'villager', 12, 5, owner: 1);
    w.submit(GarrisonCmd(1, [v.id], tc.id));
    runUntil(w, () => v.state == UnitState.garrisoned, limit: 500);
    final s = addUnit(w, 'spearman', 14, 5);
    expect(AttackCmd(0, [s.id], v.id).apply(w), CmdResult.wrongTarget);
  });
}
