import 'dart:convert';
import 'dart:io';

import 'package:age_of_empire_camer/sim/commands/command.dart';
import 'package:age_of_empire_camer/sim/commands/journal.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/testing/command_fuzzer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

final bool _full = Platform.environment['SIM_FULL'] == '1';

void main() {
  test('même graine + mêmes commandes ⇒ mêmes hashes (10 graines)', () {
    for (var seed = 1; seed <= 10; seed++) {
      final a = simulateRandomGame(testDefs, seed: seed, ticks: 1500);
      final b = simulateRandomGame(testDefs, seed: seed, ticks: 1500);
      expect(a.hashes, b.hashes, reason: 'graine $seed');
      expect(a.finalHash, b.finalHash);
      expect(a.hashes, isNotEmpty);
    }
  });

  test('graines différentes ⇒ parties différentes', () {
    final a = simulateRandomGame(testDefs, seed: 1, ticks: 300);
    final b = simulateRandomGame(testDefs, seed: 2, ticks: 300);
    expect(a.finalHash, isNot(b.finalHash));
  });

  test(
    'porte de sortie : N graines × M ticks avec commandes aléatoires',
    () {
      final seeds = _full ? 1000 : 25;
      final ticks = _full ? 10000 : 1500;
      final sw = Stopwatch()..start();
      for (var seed = 1; seed <= seeds; seed++) {
        final a = simulateRandomGame(testDefs, seed: seed, ticks: ticks);
        final b = simulateRandomGame(testDefs, seed: seed, ticks: ticks);
        expect(a.hashes, b.hashes, reason: 'graine $seed');
        expect(a.violations, isEmpty, reason: a.violations.take(3).join('\n'));
      }
      // ignore: avoid_print, mesure affichée dans la sortie des tests
      print('Déterminisme : $seeds graines × $ticks ticks en ${sw.elapsed}');
    },
    timeout: const Timeout(Duration(hours: 6)),
  );

  test('rejeu du journal de commandes : état final identique', () {
    for (final seed in [3, 8, 21]) {
      final a = createGame(testDefs, seed: seed, size: 48);
      final fuzz = CommandFuzzer(seed);
      for (var t = 0; t < 1200; t++) {
        if (t % 4 == 0) a.submit(fuzz.next(a));
        a.step();
      }
      // Sérialisation texte du journal puis rejeu sur un monde neuf.
      final lines = a.journal.toLines();
      final journal = CommandJournal.fromLines(lines);
      expect(journal.length, a.journal.length);
      final b = createGame(testDefs, seed: seed, size: 48);
      var i = 0;
      for (var t = 0; t < 1200; t++) {
        while (i < journal.length && journal.ticks[i] == t) {
          b.submit(journal.commands[i++]);
        }
        b.step();
      }
      expect(b.stateHash(), a.stateHash(), reason: 'graine $seed');
      expect(b.hashLog, a.hashLog);
    }
  });

  test('toute commande se sérialise puis se relit à l’identique', () {
    final w = createGame(testDefs, seed: 4, size: 48);
    final fuzz = CommandFuzzer(99);
    for (var i = 0; i < 500; i++) {
      final c = fuzz.next(w);
      final back = Command.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(back.toJson()), jsonEncode(c.toJson()));
      expect(back.runtimeType, c.runtimeType);
    }
    expect(
      () => Command.fromJson(<String, dynamic>{'t': 'inconnue', 'o': 0}),
      throwsFormatException,
    );
  });

  test('hashes de référence figés (comparaison Windows ↔ Android)', () {
    final f = File('test/fixtures/hash_reference.json');
    final current = <String, dynamic>{
      for (final seed in [1, 2, 3, 4, 5])
        '$seed': simulateRandomGame(
          testDefs,
          seed: seed,
          ticks: 2000,
          players: 3,
        ).finalHash,
    };
    if (!f.existsSync() || Platform.environment['UPDATE_REFERENCE'] == '1') {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(current));
    }
    final ref = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect(current, ref);
  });

  test('createGame est déterministe', () {
    final a = createGame(testDefs, seed: 12);
    final b = createGame(testDefs, seed: 12);
    expect(a.stateHash(), b.stateHash());
    expect(a.toJson().toString(), b.toJson().toString());
  });
}
