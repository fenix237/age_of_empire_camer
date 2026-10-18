import 'package:age_of_empire_camer/sim/core/tick.dart';

/// Pourquoi le jeu est en pause (plusieurs raisons peuvent se cumuler).
enum PauseReason { user, menu, lifecycle, dialog }

/// Accumulateur de temps : convertit le temps de rendu en ticks de
/// simulation à pas fixe (10 Hz). Découple simulation et framerate.
///
/// - La vitesse ×2 produit 2 ticks par intervalle, jamais un pas plus grand.
/// - Au plus [maxCatchUp] ticks par frame : si l'appareil rame, le jeu ralentit
///   au lieu d'entrer dans une spirale de rattrapage.
class GameLoop {
  GameLoop({this.maxCatchUp = Tick.maxCatchUpPerFrame});

  final int maxCatchUp;
  final Set<PauseReason> _pauses = <PauseReason>{};
  double _accMs = 0;
  double _speed = 1;

  static const List<double> speeds = <double>[1, 1.5, 2];

  bool get paused => _pauses.isNotEmpty;
  Set<PauseReason> get pauseReasons => Set<PauseReason>.unmodifiable(_pauses);
  double get speed => _speed;

  /// Position d'interpolation 0..1 entre le dernier tick et le suivant.
  double get alpha => (_accMs / Tick.millis).clamp(0.0, 1.0);

  set speed(double v) {
    assert(speeds.contains(v), 'vitesse non supportée');
    _speed = v;
  }

  void speedUp() {
    final i = speeds.indexOf(_speed);
    if (i < speeds.length - 1) _speed = speeds[i + 1];
  }

  /// ×1 → ×1,5 → ×2 → ×1 (bouton unique du HUD).
  void cycleSpeed() {
    final i = speeds.indexOf(_speed);
    _speed = speeds[(i + 1) % speeds.length];
  }

  void speedDown() {
    final i = speeds.indexOf(_speed);
    if (i > 0) _speed = speeds[i - 1];
  }

  void pause(PauseReason r) => _pauses.add(r);

  void resume(PauseReason r) {
    _pauses.remove(r);
    if (_pauses.isEmpty) _accMs = 0; // pas de rattrapage après une pause
  }

  void toggleUserPause() {
    if (_pauses.contains(PauseReason.user)) {
      resume(PauseReason.user);
    } else {
      pause(PauseReason.user);
    }
  }

  /// Avance de [dtSeconds] de temps réel ; renvoie le nombre de ticks à jouer.
  int advance(double dtSeconds) {
    if (paused || dtSeconds <= 0) return 0;
    // Un dt aberrant (veille, point d'arrêt) ne doit pas déclencher de rafale.
    final dt = dtSeconds > 0.25 ? 0.25 : dtSeconds;
    _accMs += dt * 1000 * _speed;
    var n = _accMs ~/ Tick.millis;
    if (n > maxCatchUp) {
      n = maxCatchUp;
      _accMs = 0; // on abandonne le retard : le jeu ralentit
    } else {
      _accMs -= n * Tick.millis;
    }
    return n;
  }

  void reset() {
    _accMs = 0;
  }
}
