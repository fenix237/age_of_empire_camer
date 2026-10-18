import 'dart:io';

import 'package:age_of_empire_camer/sim/data/defs_loader.dart';

/// Charge les définitions réelles du jeu depuis `assets/data` (tests).
Defs loadTestDefs() {
  final files = <String, String>{
    for (final n in Defs.fileNames)
      n: File('assets/data/$n.json').readAsStringSync(),
  };
  return Defs.fromFiles(files);
}

final Defs testDefs = loadTestDefs();
