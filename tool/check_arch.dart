// Vérifie la règle d'architecture : `lib/sim` ne doit importer ni `flutter`
// ni `flame` (ni `dart:ui`). Usage : `dart run tool/check_arch.dart`.
import 'dart:io';

const _forbidden = <String>[
  'package:flutter/',
  'package:flame',
  'dart:ui',
  'package:flutter_riverpod',
];

/// Retourne la liste des violations dans [root] (fichiers `.dart`).
List<String> findViolations(Directory root) {
  final violations = <String>[];
  if (!root.existsSync()) return violations;
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('import') && !line.startsWith('export')) continue;
      for (final bad in _forbidden) {
        if (line.contains(bad)) {
          violations.add('${entity.path}:${i + 1}: $line');
        }
      }
    }
  }
  return violations;
}

void main() {
  final violations = findViolations(Directory('lib/sim'));
  if (violations.isEmpty) {
    stdout.writeln('Architecture OK : lib/sim est indépendant de Flutter.');
    return;
  }
  stderr
    ..writeln('Violations (lib/sim ne doit pas dépendre de Flutter/Flame) :')
    ..writeAll(violations, '\n')
    ..writeln();
  exit(1);
}
