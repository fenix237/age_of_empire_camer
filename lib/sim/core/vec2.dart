import 'package:age_of_empire_camer/sim/core/fixed_point.dart';

/// Vecteur entier immuable. Selon le contexte : coordonnées de case ou
/// positions en virgule fixe (voir [Fx]).
class Vec2 {
  const Vec2(this.x, this.y);

  static const Vec2 zero = Vec2(0, 0);

  final int x;
  final int y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(int k) => Vec2(x * k, y * k);

  int get lengthSq => x * x + y * y;

  /// Longueur entière (même unité que les composantes).
  int get length => Fx.isqrt(lengthSq);

  int distSqTo(Vec2 o) => (this - o).lengthSq;

  int distTo(Vec2 o) => (this - o).length;

  /// Distance octile (rapide, sans racine) : max + min/2.
  int octileTo(Vec2 o) {
    final dx = (x - o.x).abs();
    final dy = (y - o.y).abs();
    return dx > dy ? dx + (dy >> 1) : dy + (dx >> 1);
  }

  /// Case contenant cette position en virgule fixe.
  Vec2 get tile => Vec2(Fx.toInt(x), Fx.toInt(y));

  /// Centre de cette case en virgule fixe.
  Vec2 get tileCenter => Vec2(Fx.tileCenter(x), Fx.tileCenter(y));

  List<int> toJson() => <int>[x, y];

  static Vec2 fromJson(Object? json) {
    final list = json! as List<dynamic>;
    return Vec2(list[0] as int, list[1] as int);
  }

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => x * 73856093 ^ y * 19349663;

  @override
  String toString() => '($x, $y)';
}
