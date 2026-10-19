// Simulation de masse headless : parties aléatoires (commandes fuzz) ou
// parties « économie » scriptées, avec vérification des invariants à chaque
// tick, double exécution pour le déterminisme, et journal des échecs.
//
//   dart run tool/mass_sim.dart --games 5000 --ticks 3000 [--mode fuzz|economy|ai]
//       [--from 1] [--check-determinism] [--out build/sim_failures]
//
// Un échec écrit `seed_N.jsonl` rejouable avec `tool/replay.dart`.
import 'dart:io';

import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/sim/testing/command_fuzzer.dart';
import 'package:age_of_empire_camer/sim/testing/economy_bot.dart';

void main(List<String> args) {
  final o = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      final key = args[i].substring(2);
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        o[key] = args[++i];
      } else {
        o[key] = 'true';
      }
    }
  }
  final games = int.parse(o['games'] ?? '200');
  final ticks = int.parse(o['ticks'] ?? '3000');
  final from = int.parse(o['from'] ?? '1');
  final mode = o['mode'] ?? 'fuzz';
  final checkDet = o.containsKey('check-determinism');
  final outDir = Directory(o['out'] ?? 'build/sim_failures');

  final defs = Defs.fromFiles(<String, String>{
    for (final n in Defs.fileNames)
      n: File('assets/data/$n.json').readAsStringSync(),
  });

  var failures = 0;
  var totalTicks = 0;
  final sw = Stopwatch()..start();
  for (var g = 0; g < games; g++) {
    final seed = from + g;
    final players = 2 + seed % 3;
    final size = 48 + (seed % 3) * 16;
    String? problem;
    int? hash;
    try {
      final r = _play(defs, mode, seed, size, players, ticks);
      hash = r.hash;
      totalTicks += ticks;
      if (r.violations.isNotEmpty) problem = r.violations.first;
      if (problem == null && checkDet) {
        final again = _play(defs, mode, seed, size, players, ticks);
        if (again.hash != hash) {
          problem = 'non déterministe : $hash ≠ ${again.hash}';
        }
      }
    } on Object catch (e) {
      problem = 'exception : $e';
    }
    if (problem != null) {
      failures++;
      stderr.writeln('ÉCHEC graine $seed ($players joueurs, $size) : $problem');
      outDir.createSync(recursive: true);
      File('${outDir.path}/seed_$seed.txt').writeAsStringSync(
        'seed=$seed size=$size players=$players ticks=$ticks mode=$mode\n$problem\n',
      );
    }
    if ((g + 1) % 50 == 0) {
      stdout.writeln(
        '… ${g + 1}/$games parties, $failures échec(s), '
        '${(totalTicks / (sw.elapsedMilliseconds / 1000)).round()} ticks/s',
      );
    }
  }
  stdout.writeln(
    'Terminé : $games parties × $ticks ticks, $failures échec(s) en '
    '${sw.elapsed}.',
  );
  exit(failures == 0 ? 0 : 1);
}

({int hash, List<String> violations}) _play(
  Defs defs,
  String mode,
  int seed,
  int size,
  int players,
  int ticks,
) {
  if (mode == 'ai') {
    // IA contre IA : clans, difficultés et styles de carte tirés de la graine.
    final rng = Rng(seed * 7919 + 13);
    final w = createGame(
      defs,
      seed: seed,
      size: size,
      players: players,
      style: rng.nextInt(defs.balance.mapStyles.length),
      setups: <PlayerSetup>[
        for (var i = 0; i < players; i++)
          PlayerSetup(
            clan: rng.nextInt(defs.clans.length),
            aiLevel: rng.nextInt(3),
            team: players == 4 && i < 2 ? 0 : -1,
          ),
      ],
      victoryMode: VictoryMode.conquest,
    )..checkInvariantsEachTick = true;
    for (var t = 0; t < ticks && !w.gameOver; t++) {
      w.step();
    }
    // Blocage : une IA dont le chien de garde s'est déclenché plus de 3 fois.
    final stuck = <String>[
      for (final p in w.players)
        if (!p.defeated && p.aiMem[6] > 3) 'IA ${p.id} bloquée (${p.aiMem[6]})',
    ];
    return (
      hash: w.stateHash(),
      violations: <String>[...w.violations, ...stuck],
    );
  }
  if (mode == 'economy') {
    final w = createGame(defs, seed: seed, size: size, players: players)
      ..checkInvariantsEachTick = true;
    final bots = <EconomyBot>[
      for (var i = 0; i < players; i++) EconomyBot(i),
    ];
    for (var t = 0; t < ticks; t++) {
      for (final b in bots) {
        b.update(w);
      }
      w.step();
    }
    return (hash: w.stateHash(), violations: List<String>.of(w.violations));
  }
  final r = simulateRandomGame(
    defs,
    seed: seed,
    ticks: ticks,
    size: size,
    players: players,
    cmdEvery: 1 + seed % 7,
    checkInvariants: true,
  );
  return (hash: r.finalHash, violations: r.violations);
}
