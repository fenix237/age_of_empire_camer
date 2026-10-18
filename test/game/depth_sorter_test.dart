import 'dart:math' as math;
import 'dart:ui';

import 'package:age_of_empire_camer/game/depth_sorter.dart';
import 'package:age_of_empire_camer/game/iso.dart';
import 'package:flutter_test/flutter_test.dart';

Drawable box(int id, int x, int y, int w, int h) {
  final h3 = 40.0 + (w + h) * 10;
  return Drawable(
    id: id,
    x0: x.toDouble(),
    y0: y.toDouble(),
    x1: (x + w).toDouble(),
    y1: (y + h).toDouble(),
    bounds: Iso.worldBounds(
      x,
      y,
      x + w,
      y + h,
    ).inflate(6).translate(0, -h3 / 2).inflate(h3 / 2),
  );
}

Drawable unit(int id, double x, double y) {
  final a = Iso.toWorld(x, y);
  return Drawable(
    id: id,
    x0: x - 0.2,
    y0: y - 0.2,
    x1: x + 0.2,
    y1: y + 0.2,
    bounds: Rect.fromCenter(center: a.translate(0, -18), width: 44, height: 56),
  );
}

List<int> ids(List<Drawable> l) => [for (final d in l) d.id];

void main() {
  test('unité contre le flanc droit d’un grand bâtiment : dessinée devant', () {
    final b = box(1, 10, 10, 3, 3);
    // x ≥ x1 : à droite (côté +x) du bâtiment, près de l’angle haut.
    final u = unit(2, 13.5, 10.5);
    final order = ids(DepthSorter.sort([u, b]));
    expect(order, [1, 2], reason: 'le bâtiment d’abord, l’unité par-dessus');
    expect(ids(DepthSorter.sort([b, u])), [1, 2]);
  });

  test('unité contre le flanc gauche (côté +y) : devant également', () {
    final b = box(1, 10, 10, 3, 3);
    final u = unit(2, 10.5, 13.5);
    expect(ids(DepthSorter.sort([u, b])), [1, 2]);
  });

  test('unité derrière le bâtiment (x < x0) : dessinée avant', () {
    final b = box(1, 10, 10, 3, 3);
    final u = unit(2, 9.5, 11.5);
    expect(ids(DepthSorter.sort([b, u])), [2, 1]);
    final u2 = unit(3, 11.5, 9.5);
    expect(ids(DepthSorter.sort([b, u2])), [3, 1]);
  });

  test('cas où le tri par x+y du centre échoue', () {
    final b = box(1, 10, 10, 4, 4); // centre x+y = 24
    final u = unit(
      2,
      14.3,
      10.3,
    ); // x+y = 24.6 > 24 mais aussi contre la face droite
    final far = unit(
      3,
      14.3,
      9.2,
    ); // derrière en y, à droite en x : indifférent
    final sorted = ids(DepthSorter.sort([far, u, b]));
    expect(sorted.indexOf(1) < sorted.indexOf(2), isTrue);
  });

  test('deux bâtiments adjacents', () {
    final a = box(1, 10, 10, 3, 3);
    final b = box(2, 13, 10, 3, 3); // à droite de a (x ≥ a.x1)
    expect(ids(DepthSorter.sort([b, a])), [1, 2]);
    final c = box(3, 10, 13, 3, 3); // au-dessus en y
    expect(ids(DepthSorter.sort([c, a])), [1, 3]);
  });

  test(
    'résultat = permutation des entrées, stable pour une liste vide/unitaire',
    () {
      expect(DepthSorter.sort(<Drawable>[]), isEmpty);
      final u = unit(1, 3, 3);
      expect(DepthSorter.sort([u]), [u]);
    },
  );

  test(
    'propriété : scènes aléatoires sans chevauchement, toutes contraintes respectées',
    () {
      final r = math.Random(8);
      for (var scene = 0; scene < 60; scene++) {
        final items = <Drawable>[];
        final occupied = <int>{};
        var id = 1;
        // Bâtiments disjoints sur une grille 40×40.
        for (var i = 0; i < 12; i++) {
          final w = 1 + r.nextInt(4);
          final h = 1 + r.nextInt(4);
          final x = 2 + r.nextInt(30);
          final y = 2 + r.nextInt(30);
          var free = true;
          for (var yy = y - 1; yy < y + h + 1 && free; yy++) {
            for (var xx = x - 1; xx < x + w + 1; xx++) {
              if (occupied.contains(yy * 100 + xx)) {
                free = false;
                break;
              }
            }
          }
          if (!free) continue;
          for (var yy = y; yy < y + h; yy++) {
            for (var xx = x; xx < x + w; xx++) {
              occupied.add(yy * 100 + xx);
            }
          }
          items.add(box(id++, x, y, w, h));
        }
        // Unités hors des emprises.
        for (var i = 0; i < 40; i++) {
          final x = 1 + r.nextDouble() * 38;
          final y = 1 + r.nextDouble() * 38;
          if (occupied.contains(y.floor() * 100 + x.floor())) continue;
          items.add(unit(id++, x, y));
        }
        items.shuffle(r);
        final sorted = DepthSorter.sort(items);
        expect(sorted.length, items.length);
        expect({for (final d in sorted) d.id}.length, items.length);
        final pos = {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
        for (final b in items.where((d) => d.isBox)) {
          for (final o in items) {
            if (identical(o, b) || !b.bounds.overlaps(o.bounds)) continue;
            if (o.isBox && o.id < b.id) continue;
            if (DepthSorter.inFront(o, b)) {
              expect(
                pos[o.id]! > pos[b.id]!,
                isTrue,
                reason: 'scène $scene : ${o.id} devant ${b.id}',
              );
            } else if (DepthSorter.inFront(b, o)) {
              expect(
                pos[b.id]! > pos[o.id]!,
                isTrue,
                reason: 'scène $scene : ${b.id} devant ${o.id}',
              );
            }
          }
        }
      }
    },
  );

  test('inFront : relations antisymétriques', () {
    final a = box(1, 10, 10, 3, 3);
    final b = box(2, 13, 10, 3, 3);
    expect(DepthSorter.inFront(b, a), isTrue);
    expect(DepthSorter.inFront(a, b), isFalse);
    expect(DepthSorter.behind(a, b), isTrue);
  });
}
