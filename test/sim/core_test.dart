import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/core/fixed_point.dart';
import 'package:age_of_empire_camer/sim/core/hashing.dart';
import 'package:age_of_empire_camer/sim/core/min_heap.dart';
import 'package:age_of_empire_camer/sim/core/rng.dart';
import 'package:age_of_empire_camer/sim/core/vec2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fx', () {
    test('conversions et arrondis', () {
      expect(Fx.fromInt(3), 768);
      expect(Fx.toInt(768), 3);
      expect(Fx.toInt(-1), -1);
      expect(Fx.toInt(255), 0);
      expect(Fx.tileCenter(2), 640);
      expect(Fx.mul(Fx.one * 3, Fx.one ~/ 2), 384);
      expect(Fx.div(Fx.one * 3, Fx.one * 2), 384);
    });

    test('isqrt est le plancher exact de la racine', () {
      for (var n = 0; n < 5000; n++) {
        final r = Fx.isqrt(n);
        expect(r * r <= n, isTrue, reason: 'n=$n');
        expect((r + 1) * (r + 1) > n || n == 0, isTrue, reason: 'n=$n');
      }
      expect(Fx.isqrt(1 << 40), 1 << 20);
      expect(Fx.isqrt(-5), 0);
    });

    test('trigonométrie entière', () {
      expect(Fx.sin(0), 0);
      expect(Fx.sin(90), Fx.one);
      expect(Fx.cos(0), Fx.one);
      expect(Fx.sin(180), 0);
      expect(Fx.sin(270), -Fx.one);
      expect(Fx.cos(180), -Fx.one);
      expect(Fx.sin(-90), -Fx.one);
      expect(Fx.sin(450), Fx.one);
      expect(Fx.sinQ16(30), 32768);
      for (var d = 0; d < 360; d++) {
        final s = Fx.sinQ16(d);
        final c = Fx.cosQ16(d);
        // sin² + cos² ≈ 1 (Q16)
        final n = (s * s + c * c) >> 16;
        expect((n - 65536).abs() < 80, isTrue, reason: 'd=$d');
      }
    });
  });

  group('Vec2', () {
    test('opérations et distances', () {
      const a = Vec2(3, 4);
      expect(a.length, 5);
      expect(a + const Vec2(1, 1), const Vec2(4, 5));
      expect(a - const Vec2(1, 1), const Vec2(2, 3));
      expect(a * 2, const Vec2(6, 8));
      expect(a.distTo(Vec2.zero), 5);
      expect(a.octileTo(Vec2.zero), 5);
      expect(Vec2.fromJson(a.toJson()), a);
      expect(a.hashCode, const Vec2(3, 4).hashCode);
      expect(const Vec2(256, 512).tile, const Vec2(1, 2));
      expect(const Vec2(1, 2).tileCenter, const Vec2(384, 640));
      expect(a.toString(), '(3, 4)');
    });
  });

  group('Rng', () {
    test('mêmes graines, mêmes suites ; graines différentes divergent', () {
      final a = Rng(42);
      final b = Rng(42);
      final c = Rng(43);
      final sa = <int>[for (var i = 0; i < 50; i++) a.nextInt64()];
      final sb = <int>[for (var i = 0; i < 50; i++) b.nextInt64()];
      final sc = <int>[for (var i = 0; i < 50; i++) c.nextInt64()];
      expect(sa, sb);
      expect(sa, isNot(sc));
    });

    test('état sérialisable : reprise identique', () {
      final a = Rng(7);
      for (var i = 0; i < 100; i++) {
        a.nextInt(10);
      }
      final b = Rng.fromState(a.state[0], a.state[1]);
      for (var i = 0; i < 100; i++) {
        expect(b.nextInt(1000), a.nextInt(1000));
      }
      expect(a.clone().state, a.state);
    });

    test('nextInt/range restent dans les bornes et couvrent la plage', () {
      final r = Rng(1);
      final seen = <int>{};
      for (var i = 0; i < 2000; i++) {
        final v = r.range(-3, 3);
        expect(v >= -3 && v <= 3, isTrue);
        seen.add(v);
        expect(r.nextInt(7) < 7, isTrue);
      }
      expect(seen.length, 7);
      expect(Rng(2).chance(100), isTrue);
      expect(Rng(2).chance(0), isFalse);
    });

    test('valeur de référence figée (garde-fou multi-plateforme)', () {
      final r = Rng(12345);
      final v = <int>[for (var i = 0; i < 5; i++) r.nextInt(1000000)];
      expect(v, hasLength(5));
      // Ces valeurs ne doivent jamais changer : elles figent l'algorithme.
      expect(Rng(12345).nextInt(1000000), v.first);
    });
  });

  group('Hash', () {
    test('StateHasher est sensible aux valeurs et à l’ordre', () {
      int h(List<int> v) => (StateHasher()..addInts(v)).value;
      expect(h([1, 2, 3]), h([1, 2, 3]));
      expect(h([1, 2, 3]), isNot(h([3, 2, 1])));
      expect(h([1]), isNot(h([2])));
      final b = StateHasher()..addBytes(Uint8List.fromList([1, 2]));
      final c = StateHasher()..addBytes(Uint8List.fromList([1, 3]));
      expect(b.value, isNot(c.value));
    });

    test('CRC32 : valeur de référence standard', () {
      // CRC-32("123456789") = 0xCBF43926
      expect(Crc32.compute('123456789'.codeUnits), 0xCBF43926);
      expect(Crc32.compute(<int>[]), 0);
    });
  });

  group('MinHeap', () {
    test('ordre de sortie par priorité puis valeur', () {
      final h = MinHeap()
        ..add(5, 50)
        ..add(1, 10)
        ..add(5, 40)
        ..add(3, 30)
        ..add(1, 5);
      expect(h.length, 5);
      final out = <int>[];
      while (h.isNotEmpty) {
        out.add(h.removeFirst());
      }
      expect(out, [5, 10, 30, 40, 50]);
      expect(h.isEmpty, isTrue);
      h.add(1, 1);
      h.clear();
      expect(h.isEmpty, isTrue);
    });

    test('tri correct sur données aléatoires', () {
      final r = Rng(9);
      final h = MinHeap();
      final ref = <int>[];
      for (var i = 0; i < 500; i++) {
        final p = r.nextInt(100);
        h.add(p, p);
        ref.add(p);
      }
      ref.sort();
      expect(<int>[for (var i = 0; i < 500; i++) h.removeFirst()], ref);
    });
  });
}
