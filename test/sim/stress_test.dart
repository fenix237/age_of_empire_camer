import 'dart:io';

import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/core/invariants.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sim_helpers.dart';

final bool _full = Platform.environment['SIM_FULL'] == '1';

/// Suit, pour chaque unité qui doit bouger, le plus long arrêt consécutif.
class StallTracker {
  StallTracker(this.w);

  final World w;
  final Map<int, int> _still = <int, int>{};
  final Map<int, int> _lastX = <int, int>{};
  final Map<int, int> _lastY = <int, int>{};
  int worst = 0;
  int worstId = -1;

  void sample() {
    for (final u in w.units.values) {
      final active = u.state == UnitState.moving;
      final moved =
          (u.x - (_lastX[u.id] ?? u.x)).abs() +
              (u.y - (_lastY[u.id] ?? u.y)).abs() >
          2;
      _lastX[u.id] = u.x;
      _lastY[u.id] = u.y;
      if (!active || moved) {
        _still[u.id] = 0;
        continue;
      }
      final n = (_still[u.id] ?? 0) + 1;
      _still[u.id] = n;
      if (n > worst) {
        worst = n;
        worstId = u.id;
      }
    }
  }
}

void main() {
  test(
    '200 unités dans un goulot : < 2 ms de chemin par tick, aucun blocage > 5 s',
    () {
      final w = blankWorld(size: 96)..checkInvariantsEachTick = false;
      // Mur vertical avec un passage de 3 cases.
      for (var y = 0; y < 96; y++) {
        if (y < 46 || y > 48) addNode(w, 'tree', 48, y);
      }
      final ids = <int>[];
      for (var i = 0; i < 200; i++) {
        ids.add(
          addUnit(
            w,
            i % 5 == 0 ? 'horseman' : 'villager',
            20 + i % 16,
            30 + i ~/ 16,
          ).id,
        );
      }
      final tracker = StallTracker(w);
      // Plusieurs groupes (certains sous le seuil du flow field) vers l'autre rive.
      for (var g = 0; g < 4; g++) {
        w.submit(
          MoveCmd(0, ids.sublist(g * 50, g * 50 + 50), 75 + g * 3, 40 + g * 4),
        );
      }
      w.step();
      expect(w.flows, isNotEmpty);
      var ticks = 0;
      while (ticks < 3000 &&
          ids.any((id) => w.units[id]!.state == UnitState.moving)) {
        w.step();
        tracker.sample();
        ticks++;
      }
      final avgPathMs = w.paths.clock.elapsedMicroseconds / 1000 / ticks;
      // ignore: avoid_print, mesure affichée dans la sortie des tests
      print(
        'goulot : $ticks ticks, chemin moyen ${avgPathMs.toStringAsFixed(3)} ms/tick, '
        'arrêt max ${tracker.worst} ticks',
      );
      expect(ticks, lessThan(3000), reason: 'tous arrivés');
      expect(avgPathMs, lessThan(2));
      expect(
        tracker.worst,
        lessThanOrEqualTo(50),
        reason: 'unité ${tracker.worstId}',
      );
      for (final id in ids) {
        expect(w.units[id]!.tileX, greaterThan(60), reason: 'unité $id');
      }
      expect(w.violations.where((v) => v.startsWith('Transition')), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    '200 ordres individuels (A*) : budget de chemin tenu, tous arrivent',
    () {
      final w = blankWorld(size: 96)..checkInvariantsEachTick = false;
      final r = Rng(42);
      for (var i = 0; i < 500; i++) {
        final x = r.range(3, 92);
        final y = r.range(3, 92);
        if (w.map.occupant[w.map.index(x, y)] == 0) addNode(w, 'tree', x, y);
      }
      final ids = <int>[];
      for (var i = 0; i < 200; i++) {
        final x = 20 + i % 20;
        final y = 20 + i ~/ 20;
        if (w.map.blocked(w.map.index(x, y))) continue;
        ids.add(addUnit(w, 'villager', x, y).id);
      }
      // Un ordre PAR unité (A*, pas de flow field), cibles toutes différentes.
      for (final id in ids) {
        w.submit(MoveCmd(0, [id], r.range(50, 90), r.range(50, 90)));
      }
      final tracker = StallTracker(w);
      w.step(); // exécute les 200 commandes
      var ticks = 1;
      while (ticks < 4000 &&
          ids.any((id) => w.units[id]!.state == UnitState.moving)) {
        w.step();
        tracker.sample();
        ticks++;
      }
      final avgPathMs = w.paths.clock.elapsedMicroseconds / 1000 / ticks;
      // ignore: avoid_print, mesure affichée dans la sortie des tests
      print(
        'A* : $ticks ticks, chemin moyen ${avgPathMs.toStringAsFixed(3)} ms/tick, '
        'arrêt max ${tracker.worst} ticks',
      );
      expect(ticks, lessThan(4000));
      expect(avgPathMs, lessThan(2));
      expect(tracker.worst, lessThanOrEqualTo(50));
      expect(w.pathQueue, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('couloir étroit : deux groupes se croisent sans blocage définitif', () {
    final w = blankWorld(size: 60)..checkInvariantsEachTick = true;
    for (var x = 0; x < 60; x++) {
      if (x < 15 || x > 45) continue;
      addNode(w, 'tree', x, 28);
      addNode(w, 'tree', x, 32);
    }
    final left = [
      for (var i = 0; i < 6; i++) addUnit(w, 'villager', 5, 28 + i % 5).id,
    ];
    final right = [
      for (var i = 0; i < 6; i++) addUnit(w, 'villager', 54, 28 + i % 5).id,
    ];
    final tracker = StallTracker(w);
    w
      ..submit(MoveCmd(0, left, 54, 30))
      ..submit(MoveCmd(0, right, 5, 30));
    var ticks = 0;
    while (ticks < 4000 &&
        [
          ...left,
          ...right,
        ].any((id) => w.units[id]!.state == UnitState.moving)) {
      w.step();
      tracker.sample();
      ticks++;
    }
    expect(ticks, lessThan(4000));
    expect(
      tracker.worst,
      lessThanOrEqualTo(50),
      reason: 'unité ${tracker.worstId}',
    );
    expect(w.violations.where((v) => !v.startsWith('Téléportation')), isEmpty);
  });

  test('impasse : l’unité entre dans un cul-de-sac puis repart', () {
    final w = blankWorld();
    // Cul-de-sac en U ouvert vers la gauche.
    for (var x = 10; x <= 20; x++) {
      addNode(w, 'tree', x, 10);
      addNode(w, 'tree', x, 14);
    }
    for (var y = 10; y <= 14; y++) {
      addNode(w, 'tree', 20, y);
    }
    final u = addUnit(w, 'villager', 2, 12);
    w.submit(MoveCmd(0, [u.id], 15, 12));
    runUntil(w, () => u.isIdle && w.tick > 3, limit: 800);
    expect((u.tileX, u.tileY), (15, 12));
    w.submit(MoveCmd(0, [u.id], 30, 30));
    run(w, 2);
    runUntil(w, () => u.isIdle, limit: 1500);
    expect((u.tileX, u.tileY), (30, 30));
    expectHealthy(w);
  });

  test(
    '500 unités : la simulation reste saine et rapide',
    () {
      final w = blankWorld(size: 128)..checkInvariantsEachTick = false;
      final r = Rng(3);
      for (var i = 0; i < 700; i++) {
        addNode(w, 'tree', r.range(2, 125), r.range(2, 125));
      }
      final ids = <int>[];
      for (var i = 0; i < 500; i++) {
        final spot = w.map.index(10 + i % 25, 10 + i ~/ 25);
        if (w.map.occupant[spot] != 0) continue;
        ids.add(
          addUnit(w, 'villager', 10 + i % 25, 10 + i ~/ 25, owner: i % 2).id,
        );
      }
      for (var g = 0; g < 10; g++) {
        for (final owner in [0, 1]) {
          final chunk = [
            for (final id in ids.skip(g * 40).take(40))
              if (w.units[id]!.owner == owner) id,
          ];
          if (chunk.isEmpty) continue;
          w.submit(MoveCmd(owner, chunk, r.range(60, 120), r.range(60, 120)));
        }
      }
      final sw = Stopwatch()..start();
      for (var t = 0; t < 600; t++) {
        w.step();
      }
      final perTick = sw.elapsedMicroseconds / 600 / 1000;
      // ignore: avoid_print, mesure affichée dans la sortie des tests
      print('500 unités : ${perTick.toStringAsFixed(2)} ms/tick');
      expect(w.units.length, ids.length);
      expect(
        perTick,
        lessThan(30),
        reason: 'budget très large (machine de CI)',
      );
      // Fin de partie : invariants valides une dernière fois.
      expect(checkInvariants(w), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'porte de sortie : scénarios de mouvement aléatoires sans violation',
    () {
      final n = _full ? 1000 : 120;
      for (var s = 0; s < n; s++) {
        final r = Rng(s + 1);
        final w = blankWorld(size: 50);
        for (var i = 0; i < r.range(0, 260); i++) {
          final x = r.range(1, 48);
          final y = r.range(1, 48);
          if (w.map.occupant[w.map.index(x, y)] == 0) addNode(w, 'tree', x, y);
        }
        final ids = <int>[];
        for (var i = 0; i < r.range(1, 40); i++) {
          final x = r.range(0, 49);
          final y = r.range(0, 49);
          if (w.map.blocked(w.map.index(x, y))) continue;
          ids.add(addUnit(w, r.chance(30) ? 'horseman' : 'villager', x, y).id);
        }
        if (ids.isEmpty) continue;
        for (var t = 0; t < 400; t++) {
          if (t % 40 == 0) {
            final chunk = ids.where((_) => r.chance(60)).toList();
            if (chunk.isNotEmpty) {
              w.submit(
                MoveCmd(
                  0,
                  chunk,
                  r.range(0, 49),
                  r.range(0, 49),
                  queue: r.chance(20),
                ),
              );
            }
          }
          if (t == 150 && r.chance(50)) {
            w.submit(
              BuildCmd(
                0,
                ids.take(3).toList(),
                'hut',
                r.range(2, 45),
                r.range(2, 45),
              ),
            );
          }
          w.step();
        }
        expect(
          w.violations.where((v) => !v.startsWith('Téléportation')),
          isEmpty,
          reason: 'scénario $s',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test('toutes les unités reçoivent leur position en case valide', () {
    final w = blankWorld();
    final u = addUnit(w, 'villager', 3, 3);
    expect(u.x, Fx.tileCenter(3));
    expect(u.px, u.x);
  });
}
