import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:age_of_empire_camer/app/logging/app_logger.dart';

/// Taille minimale de la fenêtre (Analyse §9.2).
const Size kMinWindowSize = Size(1024, 576);

/// Taille par défaut au premier lancement.
const Size kDefaultWindowSize = Size(1280, 720);

/// Géométrie et mode de la fenêtre, mémorisés entre deux lancements.
class WindowSettings {
  const WindowSettings({this.bounds, this.fullScreen = false});

  /// Décode un JSON ; toute valeur invalide donne les valeurs par défaut.
  factory WindowSettings.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const WindowSettings();
    Rect? bounds;
    final x = json['x'];
    final y = json['y'];
    final w = json['w'];
    final h = json['h'];
    if (x is num && y is num && w is num && h is num) {
      final candidate = Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        w.toDouble(),
        h.toDouble(),
      );
      final finite = [x, y, w, h].every((v) => v.toDouble().isFinite);
      if (finite && candidate.width > 0 && candidate.height > 0) {
        bounds = candidate;
      }
    }
    return WindowSettings(
      bounds: bounds,
      fullScreen: json['fullScreen'] == true,
    );
  }

  final Rect? bounds;
  final bool fullScreen;

  WindowSettings copyWith({Rect? bounds, bool? fullScreen}) => WindowSettings(
    bounds: bounds ?? this.bounds,
    fullScreen: fullScreen ?? this.fullScreen,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (bounds != null) ...<String, Object?>{
      'x': bounds!.left,
      'y': bounds!.top,
      'w': bounds!.width,
      'h': bounds!.height,
    },
    'fullScreen': fullScreen,
  };

  /// Ramène [bounds] dans la zone visible la plus proche parmi [displays].
  ///
  /// - taille au moins [kMinWindowSize], au plus la taille de l'écran ;
  /// - si le rectangle ne touche aucun écran (moniteur débranché), la fenêtre
  ///   est recentrée sur le premier écran (l'écran principal).
  static Rect sanitize(Rect? bounds, List<Rect> displays) {
    final primary = displays.isEmpty
        ? const Rect.fromLTWH(0, 0, 1920, 1080)
        : displays.first;
    Rect fit(Rect r, Rect screen) {
      final w = r.width
          .clamp(
            kMinWindowSize.width.clamp(0, screen.width),
            screen.width,
          )
          .toDouble();
      final h = r.height
          .clamp(
            kMinWindowSize.height.clamp(0, screen.height),
            screen.height,
          )
          .toDouble();
      final left = r.left.clamp(screen.left, screen.right - w);
      final top = r.top.clamp(screen.top, screen.bottom - h);
      return Rect.fromLTWH(left, top, w, h);
    }

    if (bounds == null) {
      const size = kDefaultWindowSize;
      return fit(
        Rect.fromCenter(
          center: primary.center,
          width: size.width,
          height: size.height,
        ),
        primary,
      );
    }
    for (final screen in displays) {
      final overlap = screen.intersect(bounds);
      if (overlap.width > 100 && overlap.height > 100) {
        return fit(bounds, screen);
      }
    }
    return fit(
      Rect.fromCenter(
        center: primary.center,
        width: bounds.width,
        height: bounds.height,
      ),
      primary,
    );
  }
}

/// Lecture/écriture atomique de [WindowSettings].
class WindowSettingsStore {
  WindowSettingsStore(this._dir);

  final Directory _dir;

  File get _file => File('${_dir.path}/window.json');

  Future<WindowSettings> load() async {
    try {
      if (!_file.existsSync()) return const WindowSettings();
      final text = await _file.readAsString();
      return WindowSettings.fromJson(jsonDecode(text));
    } on Object catch (e) {
      AppLogger.instance.warning(
        'window.json illisible, valeurs par défaut: $e',
      );
      return const WindowSettings();
    }
  }

  Future<void> save(WindowSettings settings) async {
    try {
      await _dir.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
      await tmp.rename(_file.path);
    } on Object catch (e) {
      AppLogger.instance.warning('Impossible de sauver window.json: $e');
    }
  }
}
