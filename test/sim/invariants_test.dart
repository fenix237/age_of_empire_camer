import 'dart:io';

import 'package:age_of_empire_camer/sim/testing/command_fuzzer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

final bool _full = Platform.environment['SIM_FULL'] == '1';

void main() {
  test(
    'séquences de commandes aléatoires : aucun invariant violé',
    () {
      final seeds = _full ? 300 : 30;
      final ticks = _full ? 6000 : 2500;
      for (var seed = 1; seed <= seeds; seed++) {
        final players = 2 + seed % 3;
        // Les invariants sont vérifiés (assert) après chaque tick.
        try {
          final r = simulateRandomGame(
            testDefs,
            seed: seed * 7919,
            ticks: ticks,
            players: players,
            cmdEvery: 1 + seed % 7,
            checkInvariants: true,
          );
          expect(r.violations, isEmpty, reason: 'graine $seed');
          // ignore: avoid_catching_errors, l'assertion d'invariant est le signal
        } on AssertionError catch (e) {
          fail('graine $seed (joueurs $players) : ${e.message}');
        }
      }
    },
    timeout: const Timeout(Duration(hours: 2)),
  );
}
