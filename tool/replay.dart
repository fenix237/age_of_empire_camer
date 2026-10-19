// Rejoue un journal de commandes et compare l'état final.
//
//   dart run tool/replay.dart journal.jsonl --seed 7 --size 64 --players 2 \
//       --ticks 5000 [--expect 0x1234abcd] [--hash-log hashes.txt]
//
// Mêmes graine + mêmes commandes ⇒ même hash d'état (déterminisme, §3.1).
// Utilisé pour reproduire un bug à partir du journal d'une partie, et pour
// comparer deux plateformes (Windows ↔ Android).
import 'dart:io';

import 'package:age_of_empire_camer/sim/commands/journal.dart';
import 'package:age_of_empire_camer/sim/core/hashing.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:age_of_empire_camer/sim/game_setup.dart';

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(
      'usage : dart run tool/replay.dart <journal.jsonl> --seed N '
      '[--size 64] [--players 2] --ticks T [--expect HASH] [--hash-log FICHIER]',
    );
    exit(args.isEmpty ? 2 : 0);
  }
  final opts = <String, String>{};
  String? journalPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      opts[args[i].substring(2)] = args[++i];
    } else {
      journalPath = args[i];
    }
  }
  if (journalPath == null || !File(journalPath).existsSync()) {
    stderr.writeln('Journal introuvable : $journalPath');
    exit(2);
  }
  final seed = int.parse(opts['seed'] ?? '1');
  final size = int.parse(opts['size'] ?? '64');
  final players = int.parse(opts['players'] ?? '2');
  final journal = CommandJournal.fromLines(
    File(journalPath).readAsStringSync(),
  );
  final ticks = int.parse(
    opts['ticks'] ?? '${journal.ticks.isEmpty ? 0 : journal.ticks.last + 1000}',
  );

  final defs = Defs.fromFiles(<String, String>{
    for (final n in Defs.fileNames)
      n: File('assets/data/$n.json').readAsStringSync(),
  });
  List<int> list(String key, int def) {
    final l = (opts[key] ?? '').split(',').where((e) => e.isNotEmpty).toList();
    return <int>[
      for (var i = 0; i < players; i++)
        l.isEmpty ? def : int.parse(l[i % l.length]),
    ];
  }

  final clans = list('clans', 0);
  final levels = list('levels', -1);
  final w = createGame(
    defs,
    seed: seed,
    size: size,
    players: players,
    style: int.parse(opts['style'] ?? '0'),
    setups: opts.containsKey('clans') || opts.containsKey('levels')
        ? <PlayerSetup>[
            for (var i = 0; i < players; i++)
              PlayerSetup(clan: clans[i], aiLevel: levels[i]),
          ]
        : null,
    victoryMode: int.parse(opts['victory'] ?? '0'),
  )..aiEnabled = false;
  var next = 0;
  final sw = Stopwatch()..start();
  for (var t = 0; t < ticks; t++) {
    while (next < journal.length && journal.ticks[next] == t) {
      w.submit(journal.commands[next++]);
    }
    w.step();
  }
  final hash = w.stateHash();
  stdout.writeln(
    'Rejoué ${journal.length} commandes sur $ticks ticks en '
    '${sw.elapsedMilliseconds} ms — hash final 0x${hex64(hash)}',
  );
  final logPath = opts['hash-log'];
  if (logPath != null) {
    final sb = StringBuffer();
    for (var i = 0; i < w.hashLog.length; i += 2) {
      sb.writeln('${w.hashLog[i]} ${hex64(w.hashLog[i + 1])}');
    }
    File(logPath).writeAsStringSync(sb.toString());
  }
  final expect = opts['expect'];
  if (expect != null) {
    final want = int.parse(expect);
    if (want != hash) {
      stderr.writeln(
        'DÉSYNCHRONISATION : attendu 0x${hex64(want)}, '
        'obtenu 0x${hex64(hash)}',
      );
      exit(1);
    }
    stdout.writeln('OK : hash identique à la référence.');
  }
  if (w.violations.isNotEmpty) {
    stderr.writeln('Anomalies : ${w.violations.take(5).join(' | ')}');
  }
}
