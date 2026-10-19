// Partie IA contre IA headless, avec un point de situation périodique.
//
//   dart run tool/ai_demo.dart [--seed 1] [--ticks 12000] [--size 64]
//       [--clans 0,1] [--levels 1,1] [--players 2]
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
  final seed = int.parse(o['seed'] ?? '1');
  final ticks = int.parse(o['ticks'] ?? '12000');
  final size = int.parse(o['size'] ?? '64');
  final players = int.parse(o['players'] ?? '2');
  List<int> list(String key, int def) {
    final l = (o[key] ?? '').split(',').where((e) => e.isNotEmpty).toList();
    return <int>[
      for (var i = 0; i < players; i++)
        l.isEmpty ? def : int.parse(l[i % l.length]),
    ];
  }

  final clans = list('clans', 0);
  final levels = list('levels', 1);
  final defs = Defs.fromFiles(<String, String>{
    for (final n in Defs.fileNames)
      n: File('assets/data/$n.json').readAsStringSync(),
  });
  final w = createGame(
    defs,
    seed: seed,
    size: size,
    players: players,
    setups: <PlayerSetup>[
      for (var i = 0; i < players; i++)
        PlayerSetup(clan: clans[i], aiLevel: levels[i]),
    ],
    victoryMode: VictoryMode.conquest,
  )..checkInvariantsEachTick = o.containsKey('invariants');
  final sw = Stopwatch()..start();
  for (var t = 0; t < ticks && !w.gameOver; t++) {
    w.step();
    if (w.tick % 1200 == 0) _report(w);
  }
  _report(w);
  stdout.writeln(
    'fin : tick ${w.tick}, gagnant équipe ${w.winnerTeam}, '
    '${sw.elapsedMilliseconds} ms, violations ${w.violations.length}',
  );
  final journal = o['journal'];
  if (journal != null) {
    File(journal)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(w.journal.toLines());
    stdout.writeln(
      'journal : $journal (${w.journal.length} commandes, hash 0x'
      '${w.stateHash().toRadixString(16)}, ${w.stateHash()})',
    );
  }
  final detail = int.tryParse(o['detail'] ?? '');
  if (detail != null) _detail(w, detail);
  for (final v in w.violations.take(8)) {
    stdout.writeln('  ! $v');
  }
}

void _report(World w) {
  final b = StringBuffer('t=${w.tick ~/ 10}s ');
  for (final p in w.players) {
    final units = w.units.values.where((u) => u.owner == p.id).toList();
    final vill = units.where((u) => u.def.villager).length;
    final mil = units.where((u) => u.def.military).length;
    final blds = w.buildings.values.where((x) => x.owner == p.id).length;
    final fields = w.buildings.values
        .where((x) => x.owner == p.id && x.isField)
        .length;
    final by = <int, int>{};
    for (final u in units.where((u) => u.def.villager)) {
      by[u.gatherRes] = (by[u.gatherRes] ?? 0) + 1;
    }
    final idle = units.where((u) => u.def.villager && u.isIdle).length;
    b.write(
      '| J${p.id} âge${p.age} v$vill m$mil b$blds '
      'pop${p.popUsed}/${p.popCap} '
      '[${p.stock.v.join(",")}] k${p.stats.unitsKilled} f$fields i$idle $by '
      '${p.defeated ? "ÉLIMINÉ" : ""} ',
    );
  }
  stdout.writeln(b);
}

void _detail(World w, int id) {
  final p = w.players[id];
  stdout.writeln('--- joueur $id : âge ${p.age} pop ${p.popUsed}/${p.popCap}');
  final counts = <String, int>{};
  for (final b in w.buildings.values.where((b) => b.owner == id)) {
    final k = '${b.def.id}${b.complete ? "" : "*"}';
    counts[k] = (counts[k] ?? 0) + 1;
  }
  stdout.writeln('bâtiments : $counts');
  final units = <String, int>{};
  for (final u in w.units.values.where((u) => u.owner == id)) {
    final k = '${u.def.id}/${u.state.name}';
    units[k] = (units[k] ?? 0) + 1;
  }
  stdout.writeln('unités : $units');
  stdout.writeln('mémoire IA : ${p.aiMem}');
}
