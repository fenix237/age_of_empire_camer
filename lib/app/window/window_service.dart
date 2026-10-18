import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:age_of_empire_camer/app/lifecycle/close_coordinator.dart';
import 'package:age_of_empire_camer/app/logging/app_logger.dart';
import 'package:age_of_empire_camer/app/window/window_settings.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Abstraction de la fenêtre (Windows) pour rester testable.
/// Sur Android, [NoopWindowService] ne fait rien.
abstract interface class WindowService {
  /// Prépare et affiche la fenêtre (taille mémorisée, taille mini, etc.).
  Future<void> init();

  bool get isFullScreen;

  Future<void> setFullScreen({required bool value});

  Future<void> toggleFullScreen();

  /// Ferme réellement la fenêtre (après passage par le `CloseCoordinator`).
  Future<void> destroy();

  /// Sauvegarde position/taille/mode.
  Future<void> persist();
}

class NoopWindowService implements WindowService {
  @override
  Future<void> init() async {}

  @override
  bool get isFullScreen => false;

  @override
  Future<void> setFullScreen({required bool value}) async {}

  @override
  Future<void> toggleFullScreen() async {}

  @override
  Future<void> destroy() async {}

  @override
  Future<void> persist() async {}
}

/// Implémentation Windows basée sur `window_manager`.
class DesktopWindowService with WindowListener implements WindowService {
  DesktopWindowService({
    required WindowSettingsStore store,
    required CloseCoordinator closeCoordinator,
  }) : _store = store,
       _close = closeCoordinator;

  final WindowSettingsStore _store;
  final CloseCoordinator _close;
  bool _fullScreen = false;
  Rect? _lastWindowedBounds;
  bool _busy = false;
  Timer? _debounce;

  @override
  bool get isFullScreen => _fullScreen;

  @override
  Future<void> init() async {
    await windowManager.ensureInitialized();
    final saved = await _store.load();
    final displays = await _visibleDisplays();
    final bounds = WindowSettings.sanitize(saved.bounds, displays);
    _lastWindowedBounds = bounds;

    final options = WindowOptions(
      size: bounds.size,
      minimumSize: kMinWindowSize,
      title: 'Les Royaumes du Fleuve',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setBounds(bounds);
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
      if (saved.fullScreen) {
        await windowManager.setFullScreen(true);
        _fullScreen = true;
      }
    });
    windowManager.addListener(this);
  }

  Future<List<Rect>> _visibleDisplays() async {
    try {
      final list = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();
      Rect rectOf(Display d) => Rect.fromLTWH(
        d.visiblePosition?.dx ?? 0,
        d.visiblePosition?.dy ?? 0,
        (d.visibleSize ?? d.size).width,
        (d.visibleSize ?? d.size).height,
      );
      final primaryRect = rectOf(primary);
      final others = list.map(rectOf).where((r) => r != primaryRect);
      // L'écran principal en premier : c'est le repli.
      return <Rect>[primaryRect, ...others];
    } on Object catch (e) {
      AppLogger.instance.warning('Lecture des écrans impossible: $e');
      return const <Rect>[];
    }
  }

  @override
  Future<void> setFullScreen({required bool value}) async {
    if (_busy || value == _fullScreen) return;
    _busy = true;
    try {
      if (value) {
        _lastWindowedBounds = await windowManager.getBounds();
      }
      await windowManager.setFullScreen(value);
      _fullScreen = value;
      if (!value && _lastWindowedBounds != null) {
        await windowManager.setBounds(_lastWindowedBounds);
      }
      await persist();
    } on Object catch (e, s) {
      AppLogger.instance.error('Bascule plein écran échouée', e, s);
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> toggleFullScreen() => setFullScreen(value: !_fullScreen);

  @override
  Future<void> persist() async {
    try {
      final bounds = _fullScreen
          ? _lastWindowedBounds
          : await windowManager.getBounds();
      if (!_fullScreen) _lastWindowedBounds = bounds;
      await _store.save(
        WindowSettings(bounds: bounds, fullScreen: _fullScreen),
      );
    } on Object catch (e) {
      AppLogger.instance.warning('persist fenêtre échoué: $e');
    }
  }

  @override
  Future<void> destroy() async {
    windowManager.removeListener(this);
    _debounce?.cancel();
    await persist();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // --- Événements fenêtre -------------------------------------------------

  /// ✕, Alt+F4 : on passe toujours par le coordinateur de fermeture.
  @override
  void onWindowClose() {
    unawaited(_close.requestClose());
  }

  @override
  void onWindowEnterFullScreen() => _fullScreen = true;

  @override
  void onWindowLeaveFullScreen() => _fullScreen = false;

  @override
  void onWindowResized() => _persistSoon();

  @override
  void onWindowMoved() => _persistSoon();

  /// Évite d'écrire sur le disque à chaque événement pendant un glissement.
  void _persistSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), persist);
  }
}

/// Crée le service adapté à la plateforme.
WindowService createWindowService({
  required WindowSettingsStore store,
  required CloseCoordinator closeCoordinator,
}) {
  if (Platform.isWindows) {
    return DesktopWindowService(
      store: store,
      closeCoordinator: closeCoordinator,
    );
  }
  return NoopWindowService();
}
