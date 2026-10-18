/// Générateur pseudo-aléatoire déterministe xorshift128+ (état sérialisable).
///
/// Les entiers Dart natifs sont sur 64 bits (VM) : pas de dépendance à la
/// plateforme. `>>>` est le décalage logique.
class Rng {
  Rng(int seed) {
    // SplitMix64 pour dériver deux états non nuls depuis une graine.
    var z = seed;
    int next() {
      z += -7046029254386353131; // 0x9E3779B97F4A7C15
      var r = z;
      r = (r ^ (r >>> 30)) * -4658895280553007687; // 0xBF58476D1CE4E5B9
      r = (r ^ (r >>> 27)) * -7723592293110705685; // 0x94D049BB133111EB
      return r ^ (r >>> 31);
    }

    _s0 = next();
    _s1 = next();
    if (_s0 == 0 && _s1 == 0) _s1 = 1;
  }

  Rng.fromState(int s0, int s1) : _s0 = s0, _s1 = s1 == 0 && s0 == 0 ? 1 : s1;

  late int _s0;
  late int _s1;

  List<int> get state => <int>[_s0, _s1];

  int nextInt64() {
    var x = _s0;
    final y = _s1;
    _s0 = y;
    x ^= x << 23;
    _s1 = x ^ y ^ (x >>> 17) ^ (y >>> 26);
    return _s1 + y;
  }

  /// Entier dans `[0, max)`. [max] doit être > 0.
  int nextInt(int max) {
    assert(max > 0, 'max doit être > 0');
    return (nextInt64() >>> 1) % max;
  }

  /// Entier dans `[min, max]` inclus.
  int range(int min, int max) => min + nextInt(max - min + 1);

  bool chance(int percent) => nextInt(100) < percent;

  Rng clone() => Rng.fromState(_s0, _s1);
}
