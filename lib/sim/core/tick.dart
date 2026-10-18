/// Constantes de temps de la simulation.
///
/// La simulation tourne à pas fixe, indépendamment du framerate du rendu.
/// Ce dossier (`lib/sim`) ne doit JAMAIS importer `flutter` ni `flame`
/// (vérifié par `tool/check_arch.dart` et par un test).
abstract final class Tick {
  /// Nombre de ticks de simulation par seconde.
  static const int perSecond = 10;

  /// Durée d'un tick en millisecondes.
  static const int millis = 1000 ~/ perSecond;

  /// Nombre maximal de ticks rattrapés par frame de rendu, pour éviter la
  /// « spirale de la mort » quand l'appareil ralentit.
  static const int maxCatchUpPerFrame = 5;

  /// Convertit des secondes de jeu en ticks.
  static int fromSeconds(int seconds) => seconds * perSecond;
}
