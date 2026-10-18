import 'dart:typed_data';

import 'package:age_of_empire_camer/sim/core/min_heap.dart';
import 'package:age_of_empire_camer/sim/pathfinding/astar.dart';
import 'package:age_of_empire_camer/sim/world/game_map.dart';

/// Champ de coûts vers un objectif : chaque case connaît sa distance, et une
/// unité descend le gradient. Coût indépendant du nombre d'unités.
///
/// Recalculé de façon paresseuse quand la carte change ([GameMap.version]) ;
/// le résultat ne dépend que de (carte, objectif) donc reste déterministe
/// après sauvegarde/chargement.
class FlowField {
  FlowField(this.id, this.goal);

  final int id;
  final GoalRect goal;
  Int32List? _dist;
  int _version = -1;

  static const int unreachable = 0x3FFFFFFF;
  static const List<int> _dx = <int>[0, 1, 0, -1, 1, 1, -1, -1];
  static const List<int> _dy = <int>[-1, 0, 1, 0, -1, 1, 1, -1];

  /// Distance (x10) d'une case à l'objectif, [unreachable] si inaccessible.
  int distance(GameMap map, int index) {
    _ensure(map);
    return _dist![index];
  }

  /// Prochaine case à viser depuis [index], ou -1 si aucun voisin n'améliore.
  int next(GameMap map, int index) {
    _ensure(map);
    final dist = _dist!;
    final w = map.width;
    final cx = index % w;
    final cy = index ~/ w;
    var bestIdx = -1;
    var bestD = dist[index];
    for (var d = 0; d < 8; d++) {
      final nx = cx + _dx[d];
      final ny = cy + _dy[d];
      if (nx < 0 || ny < 0 || nx >= w || ny >= map.height) continue;
      final ni = ny * w + nx;
      if (map.blocked(ni)) continue;
      if (d >= 4 &&
          (map.blockedXY(cx + _dx[d], cy) || map.blockedXY(cx, cy + _dy[d]))) {
        continue;
      }
      if (dist[ni] < bestD) {
        bestD = dist[ni];
        bestIdx = ni;
      }
    }
    return bestIdx;
  }

  void _ensure(GameMap map) {
    if (_dist != null && _version == map.version) return;
    _version = map.version;
    final dist = _dist ?? Int32List(map.size);
    dist.fillRange(0, dist.length, unreachable);
    final heap = MinHeap();
    final w = map.width;
    // Sources : cases libres de la zone d'arrivée.
    for (var y = goal.y0 - goal.reach; y <= goal.y1 + goal.reach; y++) {
      for (var x = goal.x0 - goal.reach; x <= goal.x1 + goal.reach; x++) {
        if (!map.inBounds(x, y)) continue;
        final i = map.index(x, y);
        if (map.blocked(i)) continue;
        dist[i] = 0;
        heap.add(0, i);
      }
    }
    while (heap.isNotEmpty) {
      final cur = heap.removeFirst();
      final cd = dist[cur];
      final cx = cur % w;
      final cy = cur ~/ w;
      for (var d = 0; d < 8; d++) {
        final nx = cx + _dx[d];
        final ny = cy + _dy[d];
        if (nx < 0 || ny < 0 || nx >= w || ny >= map.height) continue;
        final ni = ny * w + nx;
        if (map.blocked(ni)) continue;
        if (d >= 4 &&
            (map.blockedXY(cx + _dx[d], cy) ||
                map.blockedXY(cx, cy + _dy[d]))) {
          continue;
        }
        final base = map.moveCost(cur);
        final nd = cd + (d < 4 ? base : base * 14 ~/ 10);
        if (nd < dist[ni]) {
          dist[ni] = nd;
          heap.add(nd, ni);
        }
      }
    }
    _dist = dist;
  }

  /// Libère la mémoire du champ (recalculé à la demande).
  void drop() {
    _dist = null;
    _version = -1;
  }
}
