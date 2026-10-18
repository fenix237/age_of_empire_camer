// Résume la couverture (coverage/lcov.info) pour un dossier donné.
//
//   flutter test --coverage
//   dart run tool/coverage.dart lib/sim [--min 90] [--list]
import 'dart:io';

void main(List<String> args) {
  final prefix = (args.isNotEmpty ? args.first : 'lib/sim').replaceAll(
    r'\',
    '/',
  );
  final min = args.contains('--min')
      ? int.parse(args[args.indexOf('--min') + 1])
      : 0;
  final list = args.contains('--list');
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info introuvable : lancer flutter test --coverage',
    );
    exit(2);
  }
  var found = 0;
  var hit = 0;
  final perFile = <String, List<int>>{};
  String? current;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).replaceAll(r'\', '/');
      if (!current.contains(prefix)) current = null;
      if (current != null) perFile[current] = <int>[0, 0];
    } else if (current != null && line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      perFile[current]![0]++;
      found++;
      if (int.parse(parts[1]) > 0) {
        perFile[current]![1]++;
        hit++;
      }
    }
  }
  if (list) {
    final rows = perFile.entries.toList()
      ..sort((a, b) {
        final pa = a.value[1] / (a.value[0] == 0 ? 1 : a.value[0]);
        final pb = b.value[1] / (b.value[0] == 0 ? 1 : b.value[0]);
        return pa.compareTo(pb);
      });
    for (final e in rows) {
      final pct = e.value[0] == 0 ? 100 : (100 * e.value[1] / e.value[0]);
      stdout.writeln(
        '${pct.toStringAsFixed(1).padLeft(6)} %  ${e.key}  (${e.value[1]}/${e.value[0]})',
      );
    }
  }
  final pct = found == 0 ? 0.0 : 100 * hit / found;
  stdout.writeln(
    'Couverture $prefix : ${pct.toStringAsFixed(1)} % ($hit/$found lignes, ${perFile.length} fichiers)',
  );
  if (pct < min) {
    stderr.writeln('Sous le seuil de $min %');
    exit(1);
  }
}
