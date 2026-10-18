import 'package:age_of_empire_camer/sim/core/invariants.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';
import '../helpers/test_defs.dart';

/// Chaque invariant doit réellement DÉTECTER la corruption qu'il surveille :
/// un détecteur qui ne détecte rien serait pire que pas de détecteur.
void main() {
  List<String> check(World w) => checkInvariants(w);

  test('monde sain : aucune violation', () {
    final w = blankWorld();
    addBuilding(w, 'town_center', 5, 5);
    addUnit(w, 'villager', 10, 10);
    addNode(w, 'tree', 20, 20);
    expect(check(w), isEmpty);
  });

  test('1. ressource négative', () {
    final w = blankWorld();
    w.players[1].stock[Res.gold] = -1;
    expect(check(w).single, contains('Ressource négative'));
  });

  test('2. population négative', () {
    final w = blankWorld();
    w.players[0].popUsed = -3;
    expect(check(w).single, contains('Population négative'));
  });

  test('3. unité hors carte et sur case bloquée', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 10, 10);
    final tree = addNode(w, 'tree', 12, 12);
    u.x = 12 * 256 + 5;
    u.y = 12 * 256 + 5;
    expect(check(w).single, contains('case bloquée'));
    expect(tree.id, isPositive);
    u.x = -500;
    expect(check(w).single, contains('hors carte'));
  });

  test('4. PV nuls, PV > max, unité morte non retirée', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 10, 10);
    u.hp = 0;
    expect(check(w).single, contains('PV'));
    u.hp = 999;
    expect(check(w).single, contains('PV > max'));
    u
      ..hp = 5
      ..state = UnitState.dead;
    expect(check(w).first, contains('morte'));
  });

  test('5. références pendantes (ordres, cibles, dépôt, ralliement)', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 10, 10);
    u.orders.add(const Order(OrderKind.gather, 777));
    u.state = UnitState.gathering;
    expect(check(w).first, contains('inexistant'));
    u.orders.clear();
    u
      ..state = UnitState.idle
      ..dropOffId = 888;
    expect(check(w).single, contains('pendante'));
    u.dropOffId = -1;
    final b = addBuilding(w, 'town_center', 20, 20);
    b.rallyTarget = 999;
    expect(check(w).single, contains('ralliement'));
  });

  test('état et ordres incohérents', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 10, 10);
    u.orders.add(Order.move(3, 3));
    expect(check(w).single, contains('inactive avec ordres'));
    u
      ..orders.clear()
      ..state = UnitState.moving;
    expect(check(w).any((s) => s.contains('sans ordre')), isTrue);
    u.carryAmt = 4;
    expect(check(w).any((s) => s.contains('charge sans type')), isTrue);
    u
      ..state = UnitState.idle
      ..carryAmt = -2;
    expect(check(w).single, contains('charge négative'));
  });

  test('7. déplacement sans chemin', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 10, 10);
    u.orders.add(Order.move(3, 3));
    u.state = UnitState.moving;
    expect(check(w).single, contains('sans chemin'));
    u.pathPending = true;
    expect(check(w), isEmpty);
  });

  test('garnison incohérente', () {
    final w = blankWorld();
    final b = addBuilding(w, 'town_center', 5, 5);
    final u = addUnit(w, 'villager', 10, 10);
    b.garrisoned.add(u.id);
    expect(check(w).single, contains('garnison incohérente'));
    b.garrisoned.clear();
    u
      ..state = UnitState.garrisoned
      ..garrisonIn = 12345;
    expect(check(w).single, contains('garnisonnée dans un bâtiment absent'));
  });

  test(
    '6. file de production : coût payé ≠ remboursable, file trop longue',
    () {
      final w = blankWorld();
      final b = addBuilding(w, 'town_center', 5, 5);
      final def = testDefs.unit('villager');
      for (var i = 0; i < 7; i++) {
        b.queue.add(
          QueueItem(
            isTech: false,
            defIndex: def.index,
            remaining: 10,
            paid: def.cost.copy(),
          ),
        );
      }
      expect(check(w).single, contains('File trop longue'));
      b.queue.clear();
      b.queue.add(
        QueueItem(
          isTech: false,
          defIndex: def.index,
          remaining: 5,
          paid: Stock(),
        ),
      );
      expect(check(w).single, contains('coût payé'));
    },
  );

  test('10. occupation incohérente et bâtiment hors carte', () {
    final w = blankWorld();
    final b = addBuilding(w, 'hut', 10, 10);
    w.map.occupant[w.map.index(10, 10)] = 0;
    expect(check(w).single, contains('Occupation incohérente'));
    w.map.occupant[w.map.index(10, 10)] = b.id;
    w.map.occupant[w.map.index(30, 30)] = 424242;
    expect(check(w).single, contains('Occupation incohérente'));
    w.map.occupant[w.map.index(30, 30)] = 0;
    b.hp = 0;
    expect(check(w).single, contains('PV'));
    b.hp = b.maxHp;
    b.stock = -4;
    expect(check(w).single, contains('stock négatif'));
  });

  test('ressource épuisée non retirée', () {
    final w = blankWorld();
    final n = addNode(w, 'tree', 10, 10);
    n.amount = 0;
    expect(check(w).single, contains('épuisée'));
  });

  test('les violations sont remontées par step() quand activé', () {
    final w = blankWorld();
    w.checkInvariantsEachTick = false;
    w.players[0].stock[Res.wood] = -5;
    w.step();
    expect(w.violations, isEmpty, reason: 'désactivé : rien vérifié');
    w.checkInvariantsEachTick = true;
    expect(w.step, throwsA(isA<AssertionError>()));
    expect(w.violations, isNotEmpty);
  });
}
