import 'dart:ui';

import 'package:age_of_empire_camer/sim/core/min_heap.dart';

/// Objet dessinable avec son emprise au sol (cases fractionnaires) et son
/// rectangle à l'écran (monde), pour le tri de profondeur.
class Drawable {
  Drawable({
    required this.id,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.bounds,
    this.payload,
  }) : key = (x0 + x1 + y0 + y1) / 2;

  /// Identifiant stable (départage déterministe).
  final int id;

  /// Emprise au sol : `[x0, x1) × [y0, y1)`. Un point/une unité a une emprise
  /// minuscule autour de sa position.
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  /// Rectangle occupé à l'écran (en pixels « monde »).
  final Rect bounds;

  /// Clé scalaire de pré-tri : somme des coordonnées du centre.
  final double key;

  /// Dessin de l'objet (appelé une fois triés).
  final void Function(Canvas canvas)? payload;

  bool get isBox => (x1 - x0) > 1.0001 || (y1 - y0) > 1.0001;
}

/// Tri de profondeur robuste pour grands bâtiments.
///
/// Un tri par `x + y` du centre échoue quand un objet est contre le flanc d'un
/// grand bâtiment. On pré-trie par clé, puis on impose, pour chaque couple
/// « grand objet / objet qui le chevauche à l'écran », la règle isométrique
/// exacte : un objet est devant si son emprise est au-delà de la face avant
/// (x ≥ x1 ou y ≥ y1) et derrière si elle est en deçà de la face arrière.
/// Le résultat est un tri topologique ; les cycles (rares) retombent sur la
/// clé.
abstract final class DepthSorter {
  /// Vrai si [a] doit être dessiné APRÈS (devant) [b].
  static bool inFront(Drawable a, Drawable b) {
    const e = 1e-9;
    if (a.x0 >= b.x1 - e || a.y0 >= b.y1 - e) {
      // Devant par un axe ; derrière sur l'autre axe = pas de chevauchement.
      if (!(a.x1 <= b.x0 + e && a.y0 >= b.y1 - e) &&
          !(a.y1 <= b.y0 + e && a.x0 >= b.x1 - e)) {
        return true;
      }
    }
    return false;
  }

  static bool behind(Drawable a, Drawable b) => inFront(b, a);

  static List<Drawable> sort(List<Drawable> items) {
    final n = items.length;
    final order = List<Drawable>.of(items)
      ..sort((a, b) {
        final c = a.key.compareTo(b.key);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    if (n < 2) return order;

    final boxes = <int>[
      for (var i = 0; i < n; i++)
        if (order[i].isBox) i,
    ];
    if (boxes.isEmpty) return order;

    // Arêtes u → v : u doit être dessiné avant v.
    final succ = List<List<int>>.generate(n, (_) => <int>[]);
    final indeg = List<int>.filled(n, 0);
    void edge(int u, int v) {
      succ[u].add(v);
      indeg[v]++;
    }

    for (final bi in boxes) {
      final b = order[bi];
      for (var i = 0; i < n; i++) {
        if (i == bi) continue;
        final o = order[i];
        if (o.isBox && i < bi) continue; // paire box/box traitée une fois
        if (!b.bounds.overlaps(o.bounds)) continue;
        if (inFront(o, b)) {
          edge(bi, i);
        } else if (inFront(b, o)) {
          edge(i, bi);
        }
      }
    }

    // Kahn avec file de priorité : plus petit index (= clé) d'abord.
    final out = <Drawable>[];
    final ready = MinHeap();
    for (var i = 0; i < n; i++) {
      if (indeg[i] == 0) ready.add(i, i);
    }
    final done = List<bool>.filled(n, false);
    var cycleCursor = 0;
    while (out.length < n) {
      int cur;
      if (ready.isNotEmpty) {
        cur = ready.removeFirst();
      } else {
        // Cycle : on casse sur le plus petit index non traité.
        while (done[cycleCursor]) {
          cycleCursor++;
        }
        cur = cycleCursor;
      }
      if (done[cur]) continue;
      done[cur] = true;
      out.add(order[cur]);
      for (final v in succ[cur]) {
        indeg[v]--;
        if (indeg[v] == 0 && !done[v]) ready.add(v, v);
      }
    }
    return out;
  }
}
