// Simulation d'équilibrage : parties IA contre IA headless, rapport de taux de
// victoire par clan, durées moyennes et composition des armées gagnantes.
//
//   dart run tool/balance_sim.dart --games 200 --ticks 30000 [--mode mirror|cross]
//       [--level 1] [--size 64] [--out build/balance_report.md]
//
// `mirror` : chaque clan contre lui-même (biais de côté attendu ≈ 50 %).
// `cross`  : tous les couples de clans (taux de victoire par clan).
// Seuils d'acceptation (Analyse §10) : chaque clan entre 45 % et 55 % de
// victoires ; aucune unité à plus de 40 % ou moins de 3 % des armées
// gagnantes ; aucun blocage (partie sans vainqueur au délai).
import 'dart:io';

import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';
import 'package:age_of_empire_camer/sim/systems/victory.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

void main(List<String> args) {
  final o = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      o[args[i].substring(2)] = args[++i];
    }
  }
  final games = int.parse(o['games'] ?? '100');
  final ticks = int.parse(o['ticks'] ?? '30000');
  final mode = o['mode'] ?? 'cross';
  final level = int.parse(o['level'] ?? '1');
  final size = int.parse(o['size'] ?? '64');
  final from = int.parse(o['from'] ?? '1');
  final outPath = o['out'] ?? 'build/balance_report.md';

  final defs = Defs.fromFiles(<String, String>{
    for (final n in Defs.fileNames)
      n: File('assets/data/$n.json').readAsStringSync(),
  });
  final clans = defs.clans.length;
  final wins = List<int>.filled(clans, 0);
  final played = List<int>.filled(clans, 0);
  final sideWins = <int>[0, 0];
  final unitShare = <String, int>{};
  var decided = 0;
  var draws = 0;
  var timeouts = 0;
  var totalTicks = 0;
  final sw = Stopwatch()..start();

  for (var g = 0; g < games; g++) {
    final seed = from + g;
    final a = mode == 'mirror' ? seed % clans : seed % clans;
    final b = mode == 'mirror'
        ? a
        : (a + 1 + (seed ~/ clans) % (clans - 1)) % clans;
    final w = createGame(
      defs,
      seed: seed,
      size: size,
      setups: <PlayerSetup>[
        PlayerSetup(clan: a, aiLevel: level),
        PlayerSetup(clan: b, aiLevel: level),
      ],
      victoryMode: VictoryMode.conquest,
    );
    for (var t = 0; t < ticks && !w.gameOver; t++) {
      w.step();
    }
    totalTicks += w.tick;
    played[a]++;
    played[b]++;
    if (!w.gameOver) {
      timeouts++;
      continue;
    }
    if (w.winnerTeam < 0) {
      draws++;
      continue;
    }
    decided++;
    final winner = w.players.firstWhere((p) => p.team == w.winnerTeam);
    wins[winner.clan]++;
    sideWins[winner.id]++;
    for (final u in w.units.values) {
      if (u.owner == winner.id && u.def.military) {
        unitShare[u.def.id] = (unitShare[u.def.id] ?? 0) + 1;
      }
    }
    _noop(w);
  }

  final sb = StringBuffer()
    ..writeln('# Rapport d’équilibrage ($mode, difficulté $level)')
    ..writeln()
    ..writeln(
      '$games parties, taille $size, $ticks ticks max — '
      '$decided décidées, $draws nulles, $timeouts sans vainqueur '
      '(délai), durée moyenne ${decided == 0 ? 0 : totalTicks ~/ games ~/ 10} s.',
    )
    ..writeln()
    ..writeln('| Clan | Parties | Victoires | Taux |')
    ..writeln('|---|---|---|---|');
  for (var c = 0; c < clans; c++) {
    final rate = played[c] == 0 ? 0 : wins[c] * 100 ~/ played[c];
    sb.writeln('| ${defs.clans[c].id} | ${played[c]} | ${wins[c]} | $rate % |');
  }
  sb
    ..writeln()
    ..writeln(
      'Victoires du joueur 0 : ${sideWins[0]} / joueur 1 : ${sideWins[1]}.',
    )
    ..writeln()
    ..writeln('## Unités des armées gagnantes (à la fin)')
    ..writeln();
  final totalUnits = unitShare.values.fold<int>(0, (a, b) => a + b);
  final sorted = unitShare.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    sb.writeln(
      '- ${e.key} : ${e.value} (${totalUnits == 0 ? 0 : e.value * 100 ~/ totalUnits} %)',
    );
  }
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(sb.toString());
  stdout
    ..write(sb)
    ..writeln('\n(${sw.elapsed}) rapport écrit dans $outPath');
}

void _noop(World w) {}
