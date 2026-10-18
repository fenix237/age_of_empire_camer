import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/data/res.dart';
import 'package:age_of_empire_camer/sim/systems/vision.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_defs.dart';

/// Monde minuscule et contrôlé : carte d'herbe, 2 joueurs, tout exploré,
/// invariants vérifiés à chaque tick.
World blankWorld({int size = 40, int players = 2, Stock? stock}) {
  final map = GameMap(size, size, testDefs.terrain);
  final w = World(defs: testDefs, map: map, seed: 1, playerCount: players)
    ..checkInvariantsEachTick = true;
  for (final p in w.players) {
    p.stock = stock?.copy() ?? Stock.of(<int>[1000, 1000, 1000, 1000, 1000]);
    p.explored.fillRange(0, p.explored.length, 1);
  }
  updateVision(w);
  return w;
}

Unit addUnit(World w, String id, int tx, int ty, {int owner = 0}) =>
    w.spawnUnit(
      testDefs.unit(id),
      owner,
      Fx.tileCenter(tx),
      Fx.tileCenter(ty),
    );

Building addBuilding(
  World w,
  String id,
  int tx,
  int ty, {
  int owner = 0,
  bool complete = true,
}) => w.spawnBuilding(testDefs.building(id), owner, tx, ty, complete: complete);

ResourceNode addNode(World w, String id, int tx, int ty) =>
    w.spawnNode(testDefs.resource(id), tx, ty);

/// Avance de [n] ticks.
void run(World w, int n) {
  for (var i = 0; i < n; i++) {
    w.step();
  }
}

/// Avance jusqu'à ce que [done] soit vrai (max [limit] ticks) ; échoue sinon.
int runUntil(World w, bool Function() done, {int limit = 3000, String? why}) {
  for (var i = 0; i < limit; i++) {
    if (done()) return i;
    w.step();
  }
  fail('Condition non atteinte en $limit ticks${why == null ? '' : ' : $why'}');
}

/// Aucune violation d'invariant ni transition illégale enregistrée.
void expectHealthy(World w) {
  expect(w.violations, isEmpty, reason: w.violations.take(5).join('\n'));
}
