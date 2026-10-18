import 'dart:async';
import 'dart:io';

import 'package:age_of_empire_camer/app/app.dart';
import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/lifecycle/single_instance.dart';
import 'package:age_of_empire_camer/app/logging/app_logger.dart';
import 'package:age_of_empire_camer/app/providers.dart';
import 'package:age_of_empire_camer/app/window/window_service.dart';
import 'package:age_of_empire_camer/app/window/window_settings.dart';
import 'package:age_of_empire_camer/meta/save_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(_bootstrap, (error, stack) {
    AppLogger.instance.error('Erreur non interceptée (zone)', error, stack);
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supportDir = await getApplicationSupportDirectory();
  await AppLogger.init(Directory('${supportDir.path}/logs'));
  final log = AppLogger.instance..info('Démarrage');

  FlutterError.onError = (details) {
    log.error('FlutterError', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.error('PlatformDispatcher', error, stack);
    return true; // Erreur traitée : l'application ne se ferme pas.
  };

  // Une seule instance à la fois (sauvegardes protégées).
  final instanceLock = SingleInstanceLock(Directory(supportDir.path));
  if (!instanceLock.tryAcquire()) {
    log.warning('Une autre instance tourne déjà : arrêt.');
    await log.flush();
    exit(0);
  }

  final closeCoordinator = CloseCoordinator(
    terminate: () async {
      log.info('Fermeture');
      await log.flush();
      if (Platform.isAndroid) {
        await SystemNavigator.pop();
      } else {
        exit(0);
      }
    },
  );

  final windowService = createWindowService(
    store: WindowSettingsStore(Directory('${supportDir.path}/settings')),
    closeCoordinator: closeCoordinator,
  );
  closeCoordinator
    ..addDisposer(() async => instanceLock.release())
    ..addDisposer(windowService.persist);

  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  await windowService.init();

  if (kDebugMode) log.debug('Mode debug actif');

  runApp(
    ProviderScope(
      overrides: <Override>[
        closeCoordinatorProvider.overrideWithValue(closeCoordinator),
        windowServiceProvider.overrideWithValue(windowService),
        saveStoreProvider.overrideWithValue(
          SaveStore(Directory('${supportDir.path}/saves')),
        ),
      ],
      child: const App(),
    ),
  );
}
