import 'dart:async';
import 'dart:io';

/// Niveaux de journal.
enum LogLevel { debug, info, warning, error }

/// Journal local à rotation. Aucune donnée n'est envoyée hors de l'appareil.
///
/// Écrit dans `<dossier>/game.log` ; au-delà de [maxBytes], le fichier devient
/// `game.1.log` (l'ancien `game.1.log` est écrasé).
class AppLogger {
  AppLogger._(this._dir, this.maxBytes);

  /// Crée un logger lié à [directory], sans toucher à [instance] (tests).
  AppLogger.forDirectory(Directory directory, {int maxBytes = 1024})
    : this._(directory, maxBytes);

  /// Instance globale, utilisable avant et après [init].
  static AppLogger instance = AppLogger._(null, defaultMaxBytes);

  static const int defaultMaxBytes = 5 * 1024 * 1024;

  final Directory? _dir;
  final int maxBytes;
  final List<String> _recent = <String>[];
  Future<void> _queue = Future<void>.value();

  /// Dernières lignes en mémoire (utile pour les rapports de bug et les tests).
  List<String> get recent => List<String>.unmodifiable(_recent);

  /// Initialise le journal dans [directory] (créé au besoin).
  static Future<AppLogger> init(
    Directory directory, {
    int maxBytes = defaultMaxBytes,
  }) async {
    try {
      await directory.create(recursive: true);
      instance = AppLogger._(directory, maxBytes);
    } on FileSystemException {
      // Impossible d'écrire : on garde un journal en mémoire seulement.
      instance = AppLogger._(null, maxBytes);
    }
    return instance;
  }

  File? get _file => _dir == null ? null : File('${_dir.path}/game.log');

  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warning(String message) => _log(LogLevel.warning, message);

  void error(String message, [Object? error, StackTrace? stack]) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' | $error');
    if (stack != null) buffer.write('\n$stack');
    _log(LogLevel.error, buffer.toString());
  }

  void _log(LogLevel level, String message) {
    final line =
        '${DateTime.now().toIso8601String()} '
        '[${level.name.toUpperCase()}] $message';
    _recent.add(line);
    if (_recent.length > 200) _recent.removeAt(0);
    final file = _file;
    if (file == null) return;
    _queue = _queue.then((_) => _append(file, line)).catchError((Object _) {
      // Le journal ne doit jamais faire planter l'application.
    });
  }

  Future<void> _append(File file, String line) async {
    if (file.existsSync() && file.lengthSync() > maxBytes) {
      final old = File('${_dir!.path}/game.1.log');
      if (old.existsSync()) old.deleteSync();
      file.renameSync(old.path);
    }
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  /// Attend que toutes les écritures en cours soient terminées.
  Future<void> flush() => _queue;
}
