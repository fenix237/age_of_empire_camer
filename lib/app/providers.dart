import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/window/window_service.dart';
import 'package:age_of_empire_camer/meta/save_store.dart';
import 'package:age_of_empire_camer/sim/data/defs_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fournis par `main()` via `ProviderScope.overrides`.
final closeCoordinatorProvider = Provider<CloseCoordinator>(
  (ref) => throw UnimplementedError('closeCoordinatorProvider non initialisé'),
);

final windowServiceProvider = Provider<WindowService>(
  (ref) => throw UnimplementedError('windowServiceProvider non initialisé'),
);

/// Échelle d'interface (0.8–1.5), modifiable dans les options.
final uiScaleProvider = StateProvider<double>((ref) => 1);

/// Emplacements de sauvegarde (fourni par `main()`, absent dans les tests).
final saveStoreProvider = Provider<SaveStore?>((ref) => null);

/// Définitions de gameplay chargées depuis `assets/data/*.json`.
final defsProvider = FutureProvider<Defs>((ref) async {
  final files = <String, String>{
    for (final n in Defs.fileNames)
      n: await rootBundle.loadString('assets/data/$n.json'),
  };
  return Defs.fromFiles(files);
});
