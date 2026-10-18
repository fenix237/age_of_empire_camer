import 'package:age_of_empire_camer/sim/pathfinding/astar.dart';
import 'package:age_of_empire_camer/sim/world/entities.dart';
import 'package:age_of_empire_camer/sim/world/orders.dart';
import 'package:age_of_empire_camer/sim/world/world.dart';

/// File de requêtes de chemin traitées avec un budget par tick, dans l'ordre
/// d'arrivée (déterministe). Une unité attend (`pathPending`) sa réponse.
class PathService {
  PathService(this.w);

  final World w;

  /// Nombre de chemins calculés au dernier tick (statistiques).
  int lastProcessed = 0;

  /// Total de nœuds développés au dernier tick (statistiques).
  int lastExpanded = 0;

  /// Temps cumulé passé à calculer des chemins (statistiques, hors état).
  final Stopwatch clock = Stopwatch();

  void request(Unit u) {
    if (u.pathPending) return;
    u.pathPending = true;
    w.pathQueue.add(u.id);
  }

  void processQueue() {
    var budget = w.balance.pathRequestsPerTick;
    lastProcessed = 0;
    lastExpanded = 0;
    var consumed = 0;
    clock.start();
    while (consumed < w.pathQueue.length && budget > 0) {
      final id = w.pathQueue[consumed++];
      final u = w.units[id];
      if (u == null || !u.alive || !u.pathPending) continue;
      budget--;
      lastProcessed++;
      final goal = goalFor(w, u);
      u.pathPending = false;
      if (goal == null) {
        u.path = <int>[];
        u.pathIdx = 0;
        u.pathPartial = true;
        u.pathVersion = w.map.version;
        continue;
      }
      final res = w.astar.find(
        u.tileX.clamp(0, w.map.width - 1),
        u.tileY.clamp(0, w.map.height - 1),
        goal,
        nodeLimit: w.balance.pathNodeLimit,
      );
      lastExpanded += w.astar.lastExpanded;
      u.path = res.tiles;
      u.pathIdx = 0;
      u.pathPartial = !res.reached;
      u.pathVersion = w.map.version;
    }
    clock.stop();
    if (consumed > 0) w.pathQueue.removeRange(0, consumed);
  }
}

/// Zone d'arrivée de l'ordre courant d'une unité.
GoalRect? goalFor(World w, Unit u) {
  final o = u.order;
  if (o == null) return null;
  switch (o.kind) {
    case OrderKind.move:
      return GoalRect.tile(o.a, o.b, reach: u.moveReach);
    case OrderKind.gather:
      if (u.phase == Phase.returning) {
        final b = w.buildings[u.dropOffId];
        return b == null
            ? null
            : _rectGoal(<int>[b.tx, b.ty, b.def.width, b.def.height], 1);
      }
      final r = w.rectOf(u.targetId);
      return r == null ? null : _rectGoal(r, 1);
    case OrderKind.deposit:
      final b = w.buildings[u.dropOffId];
      return b == null
          ? null
          : _rectGoal(<int>[b.tx, b.ty, b.def.width, b.def.height], 1);
    case OrderKind.build:
    case OrderKind.repair:
    case OrderKind.garrison:
      final r = w.rectOf(o.a);
      return r == null ? null : _rectGoal(r, 1);
    case OrderKind.attack:
      final r = w.rectOf(o.a);
      if (r == null) return null;
      final range = u.def.range;
      return _rectGoal(r, range == 0 ? 1 : (range * 7 ~/ 10).clamp(1, 30));
  }
}

GoalRect _rectGoal(List<int> r, int reach) =>
    GoalRect(r[0], r[1], r[0] + r[2] - 1, r[1] + r[3] - 1, reach: reach);
