import 'dart:convert';

import 'package:age_of_empire_camer/sim/commands/command.dart';

/// Journal des commandes exécutées (tick, commande) pour rejouer une partie.
class CommandJournal {
  final List<int> ticks = <int>[];
  final List<Command> commands = <Command>[];

  int get length => commands.length;

  void record(int tick, Command c) {
    ticks.add(tick);
    commands.add(c);
  }

  /// Une ligne JSON par commande : `{"tick":N,"cmd":{...}}`.
  String toLines() {
    final sb = StringBuffer();
    for (var i = 0; i < commands.length; i++) {
      sb.writeln(
        jsonEncode(<String, dynamic>{
          'tick': ticks[i],
          'cmd': commands[i].toJson(),
        }),
      );
    }
    return sb.toString();
  }

  static CommandJournal fromLines(String text) {
    final j = CommandJournal();
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final m = jsonDecode(line) as Map<String, dynamic>;
      j.record(
        m['tick'] as int,
        Command.fromJson(m['cmd'] as Map<String, dynamic>),
      );
    }
    return j;
  }
}
