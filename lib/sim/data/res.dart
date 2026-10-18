/// Les cinq ressources du jeu. L'ordre est stable (index utilisé en sauvegarde).
enum Res {
  food,
  wood,
  stone,
  iron,
  gold
  ;

  static Res? tryParse(String id) {
    for (final r in Res.values) {
      if (r.name == id) return r;
    }
    return null;
  }
}

/// Quantités par ressource (coût, stock, charge portée).
class Stock {
  Stock() : v = List<int>.filled(Res.values.length, 0);

  Stock.of(Iterable<int> values) : v = List<int>.of(values);

  Stock.fromMap(Map<Res, int> map)
    : v = List<int>.filled(Res.values.length, 0) {
    map.forEach((r, a) => v[r.index] = a);
  }

  Stock.fromJson(Object? json)
    : v = List<int>.from((json! as List<dynamic>).cast<int>());

  final List<int> v;

  int operator [](Res r) => v[r.index];
  void operator []=(Res r, int a) => v[r.index] = a;

  bool get isZero => v.every((e) => e == 0);

  /// Vrai si ce stock couvre [cost] pour chaque ressource.
  bool covers(Stock cost) {
    for (var i = 0; i < v.length; i++) {
      if (v[i] < cost.v[i]) return false;
    }
    return true;
  }

  void add(Stock o) {
    for (var i = 0; i < v.length; i++) {
      v[i] += o.v[i];
    }
  }

  /// Retire [cost]. Précondition : `covers(cost)`.
  void subtract(Stock cost) {
    for (var i = 0; i < v.length; i++) {
      v[i] -= cost.v[i];
      assert(v[i] >= 0, 'ressource négative');
    }
  }

  /// `floor(this * num / den)` composante par composante.
  Stock scaled(int num, int den) =>
      Stock.of(<int>[for (final e in v) e * num ~/ den]);

  Stock copy() => Stock.of(v);

  List<int> toJson() => List<int>.of(v);

  @override
  bool operator ==(Object other) => other is Stock && _eq(other.v, v);

  static bool _eq(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(v);

  @override
  String toString() => 'Stock($v)';
}
