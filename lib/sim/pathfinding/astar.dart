import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/core/min_heap.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';

/// Rectangle cible d'une recherche de chemin (cases, bornes incluses).
class GoalRect {
  const GoalRect(this.x0, this.y0, this.x1, this.y1, {this.reach = 0});

  factory GoalRect.tile(int x, int y, {int reach = 0}) =>
      GoalRect(x, y, x, y, reach: reach);

  final int x0;
  final int y0;
  final int x1;
  final int y1;

  /// Distance de Chebyshev (en cases) à laquelle on considère l'objectif atteint.
  final int reach;

  bool contains(int x, int y) =>
      x >= x0 - reach && x <= x1 + reach && y >= y0 - reach && y <= y1 + reach;

  /// Distance octile (x10) d'une case au rectangle cible étendu.
  int heuristic(int x, int y) {
    final dx = x < x0 - reach
        ? (x0 - reach - x)
        : (x > x1 + reach ? x - x1 - reach : 0);
    final dy = y < y0 - reach
        ? (y0 - reach - y)
        : (y > y1 + reach ? y - y1 - reach : 0);
    return dx > dy ? 10 * dx + 4 * dy : 10 * dy + 4 * dx;
  }

  @override
  String toString() => 'GoalRect($x0,$y0..$x1,$y1 r$reach)';
}

class PathResult {
  const PathResult(this.tiles, {required this.reached});

  /// Indices de case, départ exclu, objectif inclus.
  final List<int> tiles;

  /// Vrai si un point de l'objectif a été atteint ; sinon chemin partiel vers
  /// la case accessible la plus proche.
  final bool reached;
}

/// A* sur grille 8 directions, sans coupe de coin, départage déterministe.
class AStar {
  AStar(this.map)
    : _g = Int32List(map.size),
      _parent = Int32List(map.size),
      _stamp = Int32List(map.size),
      _closed = Int32List(map.size);

  final GameMap map;
  final Int32List _g;
  final Int32List _parent;
  final Int32List _stamp;
  final Int32List _closed;
  int _gen = 0;
  final MinHeap _open = MinHeap();

  /// Nombre de nœuds développés lors de la dernière recherche (statistiques).
  int lastExpanded = 0;

  static const List<int> _dx = <int>[0, 1, 0, -1, 1, 1, -1, -1];
  static const List<int> _dy = <int>[-1, 0, 1, 0, -1, 1, 1, -1];

  PathResult find(
    int startX,
    int startY,
    GoalRect goal, {
    int nodeLimit = 6000,
  }) {
    _gen++;
    _open.clear();
    final w = map.width;
    final start = startY * w + startX;
    _stamp[start] = _gen;
    _g[start] = 0;
    _parent[start] = -1;
    _open.add(goal.heuristic(startX, startY), start);

    var best = start;
    var bestH = goal.heuristic(startX, startY);
    var bestG = 0;
    var expanded = 0;
    var found = -1;

    if (goal.contains(startX, startY)) {
      lastExpanded = 0;
      return const PathResult(<int>[], reached: true);
    }

    while (_open.isNotEmpty) {
      final cur = _open.removeFirst();
      if (_closed[cur] == _gen) continue;
      _closed[cur] = _gen;
      expanded++;
      final cx = cur % w;
      final cy = cur ~/ w;
      final cg = _g[cur];

      if (cur != start && goal.contains(cx, cy)) {
        found = cur;
        break;
      }
      final ch = goal.heuristic(cx, cy);
      if (ch < bestH || (ch == bestH && cg < bestG)) {
        best = cur;
        bestH = ch;
        bestG = cg;
      }
      if (expanded >= nodeLimit) break;

      for (var d = 0; d < 8; d++) {
        final nx = cx + _dx[d];
        final ny = cy + _dy[d];
        if (nx < 0 || ny < 0 || nx >= w || ny >= map.height) continue;
        final ni = ny * w + nx;
        if (map.blocked(ni)) continue;
        if (d >= 4) {
          // Pas de coupe de coin.
          if (map.blockedXY(cx + _dx[d], cy) ||
              map.blockedXY(cx, cy + _dy[d])) {
            continue;
          }
        }
        final base = map.moveCost(ni);
        final step = d < 4 ? base : base * 14 ~/ 10;
        final ng = cg + step;
        if (_stamp[ni] == _gen && ng >= _g[ni]) continue;
        _stamp[ni] = _gen;
        _g[ni] = ng;
        _parent[ni] = cur;
        _open.add(ng + goal.heuristic(nx, ny), ni);
      }
    }
    lastExpanded = expanded;

    final end = found >= 0 ? found : best;
    final out = <int>[];
    for (var c = end; c != start && c >= 0; c = _parent[c]) {
      out.add(c);
    }
    return PathResult(out.reversed.toList(), reached: found >= 0);
  }
}
